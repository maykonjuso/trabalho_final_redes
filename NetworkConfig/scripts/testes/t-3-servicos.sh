#!/bin/bash
# T3 — Serviços da intranet: DNS, WEB/API-Gateway, e-mail (SMTP/IMAP/POP3), DHCP
# Rode em qualquer máquina; testes que não se aplicam são marcados como pulados.
S_IP=172.16.0.2
PASSA=0; FALHA=0; PULA=0
ok(){ PASSA=$((PASSA+1)); echo -e "\e[32m[OK]\e[0m $1"; }
falha(){ FALHA=$((FALHA+1)); echo -e "\e[31m[FALHOU]\e[0m $1"; }
pula(){ PULA=$((PULA+1)); echo -e "\e[33m[PULADO]\e[0m $1"; }
# lê os primeiros bytes que o serviço manda ao conectar (banner)
banner(){ timeout 3 bash -c "exec 3<>/dev/tcp/$1/$2 && head -c 128 <&3" 2>/dev/null; }
porta(){ timeout 2 bash -c "echo >/dev/tcp/$1/$2" 2>/dev/null; }

echo "=== T3: Serviços da intranet ==="
echo
echo "--- DNS (BIND9 no S) ---"
for h in s r1 r2; do
  IP=$(nslookup "$h.grupo4.unb" "$S_IP" 2>/dev/null | awk '/^Address: /{print $2; exit}')
  [ -n "$IP" ] && ok "registro A $h.grupo4.unb -> $IP" || falha "registro A $h.grupo4.unb"
done
nslookup google.com "$S_IP" >/dev/null 2>&1 \
  && ok "recursão p/ nomes externos (google.com via $S_IP)" \
  || falha "recursão p/ nomes externos"

echo
echo "--- WEB + API Gateway (Apache no R1) ---"
R1=r1.grupo4.unb
nslookup $R1 >/dev/null 2>&1 || R1=172.16.0.1
curl -s --connect-timeout 4 "http://$R1/" | grep -qi "intranet" \
  && ok "página da intranet (http://$R1/)" || falha "página da intranet (http://$R1/)"
curl -s --connect-timeout 4 "http://$R1/iptv.html" | grep -qi "iptv" \
  && ok "frontend Mini-IPTV (http://$R1/iptv.html)" || falha "frontend Mini-IPTV"
curl -sk --connect-timeout 4 "https://$R1/iptv.html" | grep -qi "iptv" \
  && ok "frontend via HTTPS (certificado autoassinado)" || falha "frontend via HTTPS"
TOK=$(curl -s --connect-timeout 4 -X POST "http://$R1/api/auth/token" \
        -d username=admin -d password=admin123 | grep -o access_token)
[ -n "$TOK" ] && ok "API Gateway HTTP repassa /api p/ o backend no S" \
              || falha "API Gateway HTTP -> backend"
TOK=$(curl -sk --connect-timeout 4 -X POST "https://$R1/api/auth/token" \
        -d username=admin -d password=admin123 | grep -o access_token)
[ -n "$TOK" ] && ok "API Gateway HTTPS repassa /api p/ o backend no S" \
              || falha "API Gateway HTTPS -> backend"

echo
echo "--- E-mail no S (Postfix + Dovecot) ---"
B=$(banner $S_IP 25)
echo "$B" | grep -q "^220" && ok "SMTP porta 25 ($(echo "$B" | head -1 | cut -c1-40)...)" \
                           || falha "SMTP porta 25"
B=$(banner $S_IP 143)
echo "$B" | grep -q "OK" && ok "IMAP porta 143" || falha "IMAP porta 143"
B=$(banner $S_IP 110)
echo "$B" | grep -q "+OK" && ok "POP3 porta 110" || falha "POP3 porta 110"
porta $S_IP 993 && ok "IMAPS porta 993 (TLS) aberta" || falha "IMAPS porta 993"
porta $S_IP 995 && ok "POP3S porta 995 (TLS) aberta" || falha "POP3S porta 995"

echo
echo "--- DHCP (R2 servindo X e Y) ---"
MEU_IP=$(hostname -I 2>/dev/null | tr ' ' '\n' | grep '^192\.168\.0\.' | head -1)
if [ -n "$MEU_IP" ]; then
  OCT=${MEU_IP##*.}
  [ "$OCT" -ge 100 ] && [ "$OCT" -le 200 ] \
    && ok "IP dinâmico na faixa do DHCP ($MEU_IP em .100-.200)" \
    || falha "IP $MEU_IP fora da faixa .100-.200 do DHCP"
  ip route | grep -q "default via 192.168.0.1" \
    && ok "rota default via R2 (192.168.0.1) recebida por DHCP" \
    || falha "rota default via R2"
  grep -q "$S_IP" /etc/resolv.conf 2>/dev/null \
    && ok "DNS apontando p/ o S ($S_IP) via DHCP" || falha "DNS via DHCP"
else
  pula "testes de cliente DHCP (esta máquina não está na LAN#2 192.168.0.0/24)"
fi

echo
echo "=== T3: $PASSA ok, $FALHA falhas, $PULA pulados ==="
exit $FALHA
