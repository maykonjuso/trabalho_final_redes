#!/bin/bash
# Bateria de conectividade — rode em qualquer máquina
ok(){ echo -e "\e[32m[OK]\e[0m $1"; }
falha(){ echo -e "\e[31m[FALHOU]\e[0m $1"; }
t(){ ping -c 2 -W 2 "$1" >/dev/null 2>&1 && ok "$2 ($1)" || falha "$2 ($1)"; }

echo "=== Conectividade ==="
t 172.16.0.1  "R1 LAN#1"
t 172.16.0.2  "S"
t 10.0.0.1    "R1 WAN"
t 10.0.0.2    "R2 WAN"
t 192.168.0.1 "R2 LAN#2"
curl -sI --connect-timeout 5 http://1.1.1.1 2>/dev/null | head -1 | grep -q HTTP && ok "Internet (via NAT)" || falha "Internet"
nslookup s.grupo4.unb >/dev/null 2>&1 && ok "DNS interno (s.grupo4.unb)" || falha "DNS interno"
nslookup google.com   >/dev/null 2>&1 && ok "DNS externo (google.com)"  || falha "DNS externo"
