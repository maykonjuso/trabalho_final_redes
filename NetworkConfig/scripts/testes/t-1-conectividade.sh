#!/bin/bash
# T1 — Conectividade IP (camada de rede) — rode em QUALQUER máquina
# Verifica se todos os saltos da topologia se enxergam:
#   [S] --- [R1] ==PPP== [R2] --- [X/Y]
PASSA=0; FALHA=0
ok(){ PASSA=$((PASSA+1)); echo -e "\e[32m[OK]\e[0m $1"; }
falha(){ FALHA=$((FALHA+1)); echo -e "\e[31m[FALHOU]\e[0m $1"; }
t(){ ping -c 2 -W 2 "$1" >/dev/null 2>&1 && ok "$2 ($1)" || falha "$2 ($1)"; }

echo "=== T1: Conectividade — $(hostname) $(hostname -I 2>/dev/null | tr -s ' ') ==="
echo
echo "--- Endereços desta máquina ---"
ip -br addr | grep -v "^lo" || true
ip route | grep default || echo "(sem rota default)"
echo
echo "--- Saltos da topologia ---"
t 172.16.0.2  "S (servidor)"
t 172.16.0.1  "R1 LAN#1"
t 10.0.0.1    "R1 lado WAN (ppp)"
t 10.0.0.2    "R2 lado WAN (ppp)"
t 192.168.0.1 "R2 LAN#2"

echo
echo "--- Internet via Source NAT do R1 ---"
curl -sI --connect-timeout 5 http://1.1.1.1 2>/dev/null | head -1 | grep -q HTTP \
  && ok "Internet (HTTP até 1.1.1.1)" || falha "Internet (HTTP até 1.1.1.1)"
ping -c 2 -W 2 8.8.8.8 >/dev/null 2>&1 \
  && ok "Internet (ICMP até 8.8.8.8)" || falha "Internet (ICMP até 8.8.8.8)"

echo
echo "--- Resolução de nomes (DNS do S) ---"
for h in s r1 r2; do
  IP=$(nslookup "$h.grupo4.unb" 2>/dev/null | awk '/^Address: /{print $2; exit}')
  [ -n "$IP" ] && ok "DNS interno $h.grupo4.unb -> $IP" || falha "DNS interno $h.grupo4.unb"
done
nslookup google.com >/dev/null 2>&1 && ok "DNS externo (google.com)" || falha "DNS externo (google.com)"

echo
echo "=== T1: $PASSA ok, $FALHA falhas ==="
exit $FALHA
