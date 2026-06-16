#!/bin/bash
#
if [ ! -z "$1" ]; then
  echo ""
  echo "Unban a grommunio-web-auth or grommunio-sync or sshd IP "
  echo "$0 IP"
  fail2ban-client set nginx-http-auth unbanip $1
  #fail2ban-client set nginx-limit-req unbanip $1
  fail2ban-client set nginx-botsearch unbanip $1
  fail2ban-client set grommunio-web-auth unbanip $1
  fail2ban-client set grommunio-sync unbanip $1
  fail2ban-client set postfix-sasl unbanip $1
  fail2ban-client set sshd unbanip $1
  fail2ban-client set grommunio-imap unbanip $1
  fail2ban-client set grommunio-pop3 unbanip $1
  fail2ban-client set grommunio-dav unbanip $1
  #fail2ban-client set pam-generic unbanip $1
fi
#
echo ""
echo ""
#echo "Currently banned IPs in nginx-http-auth jail:"
fail2ban-client status nginx-http-auth
#echo ""
#echo "Currently banned IPs in nginx-limit-req jail:"
#fail2ban-client status nginx-limit-req
echo ""
#echo "Currently banned IPs in nginx-botsearch jail:"
fail2ban-client status nginx-botsearch
echo ""
#echo "Currently banned IPs in grommunio-web-auth jail:"
fail2ban-client status grommunio-web-auth 
echo ""
#echo "Currently banned IPs in grommunio-sync jail:"
fail2ban-client status grommunio-sync
echo ""
#echo "Currently banned IPs in postfix-sasl jail:"
fail2ban-client status postfix-sasl
echo ""
#echo "Currently banned IPs in sshd jail:"
fail2ban-client status sshd
echo ""
#echo "Currently banned IPs in grommunio-imap jail:"
fail2ban-client status grommunio-imap
echo ""
#echo "Currently banned IPs in grommunio-pop3 jail:"
fail2ban-client status grommunio-pop3
echo ""
#echo "Currently banned IPs in grommunio-dav jail:"
fail2ban-client status grommunio-dav
echo ""
##echo "Currently banned IPs in pam-generic jail:"
#fail2ban-client status pam-generic

#

