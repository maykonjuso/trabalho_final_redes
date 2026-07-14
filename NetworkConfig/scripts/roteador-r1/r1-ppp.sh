#!/bin/bash
# [R1] Enlace WAN PPP 115200 via arquivo de peer (roda em segundo plano)
set -e

list_net_interfaces() {
    ip -o link show \
        | awk -F': ' '{print $2}' \
        | grep -Ev '^(lo|ppp[0-9]*|docker|veth|br-|virbr|wl)' \
        | sort
}

list_serial_devices() {
    ls /dev/ttyS0 /dev/ttyS1 /dev/ttyUSB* /dev/ttyACM* 2>/dev/null || true
}

escolher_item() {
    local titulo="$1"; local itens="$2"; local arr=()
    while IFS= read -r linha; do [ -n "$linha" ] && arr+=("$linha"); done <<< "$itens"
    if [ ${#arr[@]} -eq 0 ]; then echo "[ERRO] Nada encontrado para: $titulo" >&2; exit 1; fi
    echo "$titulo" >&2
    select escolha in "${arr[@]}"; do
        [ -n "$escolha" ] && { echo "$escolha"; return 0; }
        echo "Opção inválida." >&2
    done
}

confirmar() {
    read -rp "Confirma? [s/N] " c
    [[ "$c" =~ ^[sS]$ ]] || { echo "Abortado."; exit 1; }
}

echo "=== [R1] PPP ==="
SERIAL=$(escolher_item "Porta serial do cabo PPP:" "$(list_serial_devices)")
echo "Serial=$SERIAL | 10.0.0.1 (R1) <-> 10.0.0.2 (R2) @115200"; confirmar

sudo mkdir -p /etc/ppp/peers
sudo tee /etc/ppp/peers/wan_r1 >/dev/null <<EOF
$SERIAL
115200
10.0.0.1:10.0.0.2
local
noauth
nocrtscts
lock
persist
EOF

sudo killall pppd 2>/dev/null || true; sleep 1
sudo pppd call wan_r1

echo -n "[R1] Aguardando ppp0"
for i in {1..15}; do ip link show ppp0 &>/dev/null && break; echo -n "."; sleep 1; done; echo
ip link show ppp0 &>/dev/null || { echo "[ERRO] ppp0 não subiu (R2 rodou o r2-ppp.sh? cabo cross?)"; exit 1; }

sudo ip link set ppp0 multicast on
sudo ip route replace 192.168.0.0/24 via 10.0.0.2   # rota p/ LAN#2
sudo ip route add 224.0.0.0/4 dev ppp0 2>/dev/null || true

echo; echo "=== OK ==="; ip addr show dev ppp0 | grep inet
echo "Teste: ping -c 3 10.0.0.2   (RTT alto é normal)"
