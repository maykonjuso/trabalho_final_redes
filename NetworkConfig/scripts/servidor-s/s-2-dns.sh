#!/bin/bash
# [S] Servidor DNS (BIND9) — zona grupo6.unb direta e reversa + forwarder
set -e

DOMINIO="grupo6.unb"
IP_S="172.16.0.2"
FORWARDER="${1:-8.8.8.8}"   # pode passar outro: ./s-2-dns.sh <ip-dns-do-lab>

echo "=== [S] DNS BIND9 ($DOMINIO, forwarder $FORWARDER) ==="

if ! command -v named >/dev/null; then
  echo "[S] Instalando bind9 (precisa de Internet)..."
  sudo apt update && sudo apt install -y bind9 bind9utils dnsutils
fi

echo "[S] Zonas..."
sudo tee /etc/bind/named.conf.local >/dev/null <<EOF
zone "$DOMINIO" { type master; file "/etc/bind/db.$DOMINIO"; };
zone "16.172.in-addr.arpa" { type master; file "/etc/bind/db.172.16"; };
EOF

sudo tee /etc/bind/db.$DOMINIO >/dev/null <<EOF
\$TTL 604800
@   IN  SOA s.$DOMINIO. admin.$DOMINIO. ( 2 604800 86400 2419200 604800 )
@   IN  NS  s.$DOMINIO.
@   IN  MX  10 s.$DOMINIO.
s   IN  A   $IP_S
r1  IN  A   172.16.0.1
r2  IN  A   192.168.0.1
mail IN CNAME s.$DOMINIO.
EOF

sudo tee /etc/bind/db.172.16 >/dev/null <<EOF
\$TTL 604800
@   IN  SOA s.$DOMINIO. admin.$DOMINIO. ( 2 604800 86400 2419200 604800 )
@   IN  NS  s.$DOMINIO.
2.0 IN  PTR s.$DOMINIO.
1.0 IN  PTR r1.$DOMINIO.
EOF

sudo tee /etc/bind/named.conf.options >/dev/null <<EOF
options {
    directory "/var/cache/bind";
    allow-query { 172.16.0.0/16; 192.168.0.0/24; 10.0.0.0/30; localhost; };
    recursion yes;
    forwarders { $FORWARDER; };
    dnssec-validation no;
    listen-on-v6 { any; };
};
EOF

echo "[S] Validando e reiniciando..."
sudo named-checkconf
sudo named-checkzone $DOMINIO /etc/bind/db.$DOMINIO
sudo systemctl restart bind9 && sudo systemctl enable bind9 2>/dev/null

echo "[S] resolv.conf do próprio S aponta para ele mesmo..."
sudo rm -f /etc/resolv.conf
echo "nameserver 127.0.0.1" | sudo tee /etc/resolv.conf >/dev/null

echo; echo "=== Testes ==="
nslookup s.$DOMINIO 127.0.0.1 | tail -2
nslookup google.com 127.0.0.1 | tail -3 || echo "[AVISO] externo falhou: veja se o S tem Internet (NAT do R1) ou troque o forwarder: ./s-2-dns.sh <dns-do-lab>"
echo "Nos clientes (R2/X/Y): rode cliente-x/x-2-dns.sh"
