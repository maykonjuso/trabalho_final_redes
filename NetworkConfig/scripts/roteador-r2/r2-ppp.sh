#!/bin/bash
# [R2] Enlace WAN PPP 115200 via arquivo de peer (com defaultroute)
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

echo "=== [R2] PPP ==="
SERIAL=$(escolher_item "Porta serial do cabo PPP:" "$(list_serial_devices)")
echo "Serial=$SERIAL | 10.0.0.2 (R2) <-> 10.0.0.1 (R1) @115200"; confirmar

sudo mkdir -p /etc/ppp/peers
sudo tee /etc/ppp/peers/wan_r2 >/dev/null <<EOF
$SERIAL
115200
10.0.0.2:10.0.0.1
local
noauth
nocrtscts
lock
persist
defaultroute
EOF

sudo killall pppd 2>/dev/null || true; sleep 1
sudo pppd call wan_r2

echo -n "[R2] Aguardando ppp0"
for i in {1..15}; do ip link show ppp0 &>/dev/null && break; echo -n "."; sleep 1; done; echo
ip link show ppp0 &>/dev/null || { echo "[ERRO] ppp0 não subiu (cabo cross? porta certa?)"; exit 1; }

sudo ip link set ppp0 multicast on
sudo ip route del default 2>/dev/null || true
sudo ip route add default via 10.0.0.1 dev ppp0
sudo ip route replace 172.16.0.0/16 via 10.0.0.1   # rota de volta p/ LAN#1
sudo ip route add 224.0.0.0/4 dev ppp0 2>/dev/null || true

echo; echo "=== OK ==="; ip addr show dev ppp0 | grep inet; ip route
echo "Teste: ping -c 3 10.0.0.1  e  curl -sI http://1.1.1.1 | head -1 (após o NAT do R1)"
