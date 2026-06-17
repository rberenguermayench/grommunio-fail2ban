#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_DIR="${SCRIPT_DIR}/fail2ban"
JAIL_LOCAL="/etc/fail2ban/jail.local"
GROMMUNIO_JAIL_LOCAL="/etc/fail2ban/jail.d/grommunio.local"
NGINX_REALIP_CONF="/etc/nginx/conf.d/x-forewarded-for.conf"
DEFAULT_FAIL2BAN_DESTEMAIL="monitor@example.com"
DEFAULT_FAIL2BAN_SENDER="fail2ban-grommunio@example.com"

usage() {
  cat <<USAGE
Usage: sudo $0

Deploys the grommunio fail2ban configuration from ${SOURCE_DIR}.

Options:
  ENV_FILE=PATH   Load deployment variables from PATH instead of ./.env.
  REAL_IP_FROM=IP  Trusted proxy/server IP for nginx set_real_ip_from.
  FAIL2BAN_DESTEMAIL=EMAIL  Destination for fail2ban notification emails.
  FAIL2BAN_SENDER=EMAIL     Sender for fail2ban notification emails.
  SKIP_EDIT=1   Do not open ${GROMMUNIO_JAIL_LOCAL} before restarting fail2ban.
  SKIP_WATCH=1  Do not start the final watch command.
USAGE
}

load_env_file() {
  local env_file="${ENV_FILE:-${SCRIPT_DIR}/.env}"
  local line key value

  if [[ ! -f "${env_file}" ]]; then
    return
  fi

  echo "==> Loading deployment variables from ${env_file}"
  while IFS= read -r line || [[ -n "${line}" ]]; do
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    if [[ -z "${line}" || "${line}" == \#* ]]; then
      continue
    fi

    key="${line%%=*}"
    value="${line#*=}"
    key="${key%"${key##*[![:space:]]}"}"
    value="${value#"${value%%[![:space:]]*}"}"

    if [[ ! "${key}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
      echo "Error: invalid key in ${env_file}: ${key}" >&2
      exit 1
    fi

    if [[ "${value}" =~ ^\".*\"$ || "${value}" =~ ^\'.*\'$ ]]; then
      value="${value:1:${#value}-2}"
    fi

    if [[ -z "${!key+x}" ]]; then
      printf -v "${key}" '%s' "${value}"
      export "${key}"
    fi
  done < "${env_file}"
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "Error: run this script as root, for example: sudo $0" >&2
    exit 1
  fi
}

require_sources() {
  local required_paths=(
    "${SOURCE_DIR}/etc/fail2ban/jail.local"
    "${SOURCE_DIR}/etc/fail2ban/filter.d"
    "${SOURCE_DIR}/etc/fail2ban/jail.d"
    "${SOURCE_DIR}/etc/nginx/conf.d"
    "${SOURCE_DIR}/scripts/unban-grommunio.sh"
  )

  for path in "${required_paths[@]}"; do
    if [[ ! -e "${path}" ]]; then
      echo "Error: required source path not found: ${path}" >&2
      exit 1
    fi
  done
}

install_fail2ban() {
  echo "==> Installing fail2ban"
  zypper --non-interactive in fail2ban
}

is_ip_or_cidr() {
  [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}(/[0-9]{1,2})?$ || "$1" =~ ^[0-9A-Fa-f:]+(/[0-9]{1,3})?$ ]]
}

detect_public_ip() {
  local detected_ip=""

  if command -v curl >/dev/null 2>&1; then
    detected_ip="$(curl -fsS --max-time 5 https://api.ipify.org || true)"
  fi

  if [[ -z "${detected_ip}" ]] && command -v wget >/dev/null 2>&1; then
    detected_ip="$(wget -qO- --timeout=5 https://api.ipify.org || true)"
  fi

  if [[ -z "${detected_ip}" ]] && command -v dig >/dev/null 2>&1; then
    detected_ip="$(dig +short myip.opendns.com @resolver1.opendns.com || true)"
  fi

  detected_ip="$(echo "${detected_ip}" | head -n 1 | tr -d '[:space:]')"
  if [[ -n "${detected_ip}" ]] && is_ip_or_cidr "${detected_ip}"; then
    echo "${detected_ip}"
  fi
}

resolve_real_ip_from() {
  local real_ip_from="${REAL_IP_FROM:-}"

  if [[ -z "${real_ip_from}" ]]; then
    echo "==> Detecting public IP for nginx set_real_ip_from" >&2
    real_ip_from="$(detect_public_ip)"
  fi

  if [[ -z "${real_ip_from}" ]]; then
    echo "Error: could not detect public IP for nginx set_real_ip_from." >&2
    echo "Set it manually, for example: sudo REAL_IP_FROM=192.168.129.200 $0" >&2
    exit 1
  fi

  if ! is_ip_or_cidr "${real_ip_from}"; then
    echo "Error: invalid REAL_IP_FROM value: ${real_ip_from}" >&2
    exit 1
  fi

  echo "${real_ip_from}"
}

deploy_nginx_real_ip_conf() {
  local real_ip_from="$1"

  echo "==> Deploying nginx forwarded-for configuration with set_real_ip_from ${real_ip_from}"
  install -d /etc/nginx/conf.d
  awk -v real_ip_from="${real_ip_from}" '{ gsub(/__REAL_IP_FROM__/, real_ip_from); print }' \
    "${SOURCE_DIR}/etc/nginx/conf.d/x-forewarded-for.conf" > "${NGINX_REALIP_CONF}"
  chmod 0644 "${NGINX_REALIP_CONF}"
}

deploy_grommunio_jail_conf() {
  local destemail="${FAIL2BAN_DESTEMAIL:-${DEFAULT_FAIL2BAN_DESTEMAIL}}"
  local sender="${FAIL2BAN_SENDER:-${DEFAULT_FAIL2BAN_SENDER}}"

  echo "==> Deploying grommunio jail overrides with notifications ${destemail}"
  awk -v destemail="${destemail}" -v sender="${sender}" '
    {
      gsub(/__FAIL2BAN_DESTEMAIL__/, destemail)
      gsub(/__FAIL2BAN_SENDER__/, sender)
      print
    }
  ' "${SOURCE_DIR}/etc/fail2ban/jail.d/grommunio.local" > "${GROMMUNIO_JAIL_LOCAL}"
  chmod 0644 "${GROMMUNIO_JAIL_LOCAL}"
}

deploy_files() {
  local real_ip_from
  real_ip_from="$(resolve_real_ip_from)"

  echo "==> Deploying fail2ban filters and jail configuration"
  install -d /etc/fail2ban/filter.d
  install -d /etc/fail2ban/jail.d
  install -m 0644 "${SOURCE_DIR}/etc/fail2ban/jail.local" /etc/fail2ban/jail.local
  install -m 0644 "${SOURCE_DIR}/etc/fail2ban/filter.d/"*.conf /etc/fail2ban/filter.d/
  deploy_grommunio_jail_conf

  deploy_nginx_real_ip_conf "${real_ip_from}"

  echo "==> Deploying helper scripts"
  install -d /scripts
  install -m 0755 "${SOURCE_DIR}/scripts/unban-grommunio.sh" /scripts/unban-grommunio.sh
}

edit_configuration() {
  if [[ "${SKIP_EDIT:-0}" == "1" ]]; then
    echo "==> Skipping ${GROMMUNIO_JAIL_LOCAL} edit because SKIP_EDIT=1"
    return
  fi

  if [[ ! -f "${GROMMUNIO_JAIL_LOCAL}" ]]; then
    echo "Error: expected configuration file not found after deployment: ${GROMMUNIO_JAIL_LOCAL}" >&2
    exit 1
  fi

  if [[ -t 0 && -t 1 ]]; then
    echo "==> Opening ${GROMMUNIO_JAIL_LOCAL} for review"
    "${EDITOR:-vi}" "${GROMMUNIO_JAIL_LOCAL}"
  else
    echo "==> Non-interactive shell detected; review ${GROMMUNIO_JAIL_LOCAL} manually if needed"
  fi
}

restart_fail2ban() {
  echo "==> Restarting fail2ban"
  systemctl restart fail2ban
  systemctl --no-pager --full status fail2ban
}

watch_fail2ban() {
  if [[ "${SKIP_WATCH:-0}" == "1" ]]; then
    echo "==> Skipping watch because SKIP_WATCH=1"
    return
  fi

  if [[ -t 0 && -t 1 ]]; then
    echo "==> Watching fail2ban status; press Ctrl+C to stop"
    watch -n 2 fail2ban-client status
  else
    echo "==> Non-interactive shell detected; run this manually to watch:"
    echo "    watch -n 2 fail2ban-client status"
  fi
}

main() {
  load_env_file

  if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
  fi

  require_root
  require_sources
  install_fail2ban
  deploy_files
  edit_configuration
  restart_fail2ban
  watch_fail2ban
}

main "$@"
