#!/bin/bash
# [R2] Interface da LAN#2 (clientes X e Y)
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

echo "=== [R2] LAN #2 ==="
IF_C=$(escolher_item "Interface conectada ao switch dos clientes (X/Y):" "$(list_net_interfaces)")
read -rp "IP do R2 [192.168.0.1/24]: " IP_R2; IP_R2=${IP_R2:-192.168.0.1/24}
echo "Interface=$IF_C  IP=$IP_R2"; confirmar

echo "[R2] Parando NetworkManager..."
sudo systemctl stop NetworkManager 2>/dev/null || true

sudo ip addr flush dev "$IF_C"
sudo ip addr add "$IP_R2" dev "$IF_C"
sudo ip link set "$IF_C" up
sudo ip link set "$IF_C" multicast on

sudo sysctl -w net.ipv4.ip_forward=1
sudo sysctl -w net.ipv4.conf.all.mc_forwarding=1

echo "$IF_C" > /tmp/frc_if_lan2
echo; echo "=== OK ==="; ip -br addr show dev "$IF_C"
