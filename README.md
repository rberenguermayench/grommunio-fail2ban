# grommunio fail2ban

Configuracions per desplegar `fail2ban` en un servidor grommunio, amb filtres, jails, configuracio nginx per `X-Forwarded-For` i script auxiliar d'unban.

El fitxer `fail2ban/etc/fail2ban/jail.d/grommunio.local` aplica un perfil PARANOID pensat per servidors exposats a Internet: bans de 24 hores, bans escalables i jail `recidive` per reincidents.

Fonts originals:

- (c) 2020-2025 Walter Hofstaedtler
- Script de referencia de crpb: <https://github.com/crpb/grommunio/tree/main/setup/fail2ban>

## Estructura

```text
fail2ban/
  etc/
    fail2ban/
      jail.local
      jail.d/
        grommunio.local
      filter.d/
    nginx/
      conf.d/
  scripts/
    unban-grommunio.sh
deploy_fail2ban_grommunio_wh.sh
```

## Desplegament

Opcionalment, crea un `.env` a partir de l'exemple:

```bash
cp .env.example .env
vi .env
```

Variables disponibles:

```bash
REAL_IP_FROM=
FAIL2BAN_DESTEMAIL=monitor@example.com
FAIL2BAN_SENDER=fail2ban-grommunio@example.com
SKIP_EDIT=0
SKIP_WATCH=0
```

Executa el script com a `root` des de l'arrel del repo:

```bash
sudo ./deploy_fail2ban_grommunio_wh.sh
```

Per defecte, el script intenta detectar la IP publica i la posa a `set_real_ip_from` dins de `/etc/nginx/conf.d/x-forewarded-for.conf`.

Si el servidor rep `X-Forwarded-For` des d'un proxy concret, indica explicitament la IP o CIDR de confianca:

```bash
sudo REAL_IP_FROM=192.168.129.200 ./deploy_fail2ban_grommunio_wh.sh
```

Les variables passades per entorn tenen prioritat sobre el `.env`.

El script fa aquestes accions:

1. Instal-la `fail2ban` amb `zypper`.
2. Copia `fail2ban/etc/fail2ban/jail.local` a `/etc/fail2ban/jail.local`.
3. Genera `/etc/fail2ban/jail.d/grommunio.local` amb els mails de notificacio.
4. Copia els filtres de `fail2ban/etc/fail2ban/filter.d/` a `/etc/fail2ban/filter.d/`.
5. Genera `/etc/nginx/conf.d/x-forewarded-for.conf` amb el valor de `set_real_ip_from`.
6. Copia `fail2ban/scripts/unban-grommunio.sh` a `/scripts/unban-grommunio.sh`.
7. Obre `/etc/fail2ban/jail.d/grommunio.local` per revisar-lo.
8. Reinicia `fail2ban`.
9. Mostra l'estat amb `watch -n 2 fail2ban-client status`.

Per saltar les parts interactives:

```bash
sudo SKIP_EDIT=1 SKIP_WATCH=1 ./deploy_fail2ban_grommunio_wh.sh
```

## Ajustos manuals

Revisa aquests fitxers despres del desplegament:

- `/etc/fail2ban/jail.local`
- `/etc/fail2ban/jail.d/grommunio.local`
- `/etc/nginx/conf.d/x-forewarded-for.conf`

El perfil actual envia notificacions per correu amb whois i linies de log (`action = %(action_mwl)s`). Els valors `destemail` i `sender` es generen des del `.env`.

Despres de modificar la configuracio de nginx:

```bash
nginx -t
systemctl restart nginx
```

Si vols que `fail2ban` arrenqui automaticament:

```bash
systemctl enable fail2ban
```

## Logs grommunio-sync i grommunio-dav

Si els logs de `grommunio-sync` o `grommunio-dav` no existeixen, crea'ls manualment:

```bash
touch /var/log/grommunio-sync/grommunio-sync.log
chown grosync:grosync /var/log/grommunio-sync/grommunio-sync.log

touch /var/log/grommunio-dav/dav.log
chown grodav:grodav /var/log/grommunio-dav/dav.log
```
