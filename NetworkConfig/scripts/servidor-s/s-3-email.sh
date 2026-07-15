#!/bin/bash
# [S] E-mail seguro: Postfix (SMTP) + Dovecot (IMAP e POP3) com TLS
set -e

DOMINIO="grupo6.unb"
echo "=== [S] E-mail (postfix + dovecot, TLS) ==="

if ! command -v postconf >/dev/null; then
  echo "postfix postfix/main_mailer_type select Internet Site" | sudo debconf-set-selections
  echo "postfix postfix/mailname string $DOMINIO" | sudo debconf-set-selections
  sudo DEBIAN_FRONTEND=noninteractive apt install -y postfix dovecot-imapd dovecot-pop3d mailutils
fi

echo "[S] Certificado TLS autoassinado..."
sudo openssl req -new -x509 -days 365 -nodes -subj "/CN=s.$DOMINIO" \
  -out /etc/ssl/certs/mail.pem -keyout /etc/ssl/private/mail.key 2>/dev/null

echo "[S] Postfix..."
sudo postconf -e "myhostname = s.$DOMINIO" \
              "mydomain = $DOMINIO" \
              "mydestination = \$myhostname, $DOMINIO, localhost" \
              "mynetworks = 127.0.0.0/8 172.16.0.0/16 192.168.0.0/24 10.0.0.0/30" \
              "smtpd_tls_cert_file=/etc/ssl/certs/mail.pem" \
              "smtpd_tls_key_file=/etc/ssl/private/mail.key" \
              "smtpd_tls_security_level=may"
sudo systemctl restart postfix

echo "[S] Dovecot (IMAP + POP3 + TLS)..."
# nomes dos parâmetros de cert/key mudaram no Dovecot 2.4 (ssl_cert/ssl_key -> ssl_server_cert_file/ssl_server_key_file);
# cobre as duas versões para não falhar silenciosamente
sudo sed -i -E \
  -e 's#^(ssl_cert|ssl_server_cert_file) =.*#\1 = </etc/ssl/certs/mail.pem#' \
  -e 's#^(ssl_key|ssl_server_key_file) =.*#\1 = </etc/ssl/private/mail.key#' \
  -e 's#^ssl =.*#ssl = yes#' \
  /etc/dovecot/conf.d/10-ssl.conf
sudo systemctl restart dovecot

echo "[S] Caixas de e-mail (aluno1/aluno1123, aluno2/aluno2123)..."
for u in aluno1 aluno2; do
  id "$u" >/dev/null 2>&1 || sudo useradd -m -s /bin/bash "$u"
  echo "$u:${u}123" | sudo chpasswd
done

echo; echo "=== Teste ==="
echo "corpo" | mail -s "teste" aluno2@$DOMINIO
sleep 2; sudo tail -n 3 /var/log/mail.log
echo "Thunderbird (em X): IMAP s.$DOMINIO:143 STARTTLS (ou POP3 110) | SMTP s.$DOMINIO:25 STARTTLS"
