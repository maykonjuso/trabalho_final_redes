#!/bin/bash
# [R1] Interfaces: LAN#1 (cabo até S) + uplink do Lab (USB->Eth, DHCP)
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

echo "=== [R1] LAN #1 + uplink do Lab ==="
IF_S=$(escolher_item "Interface conectada ao S (cabo direto):" "$(list_net_interfaces)")
read -rp "IP do R1 na LAN#1 [172.16.0.1/16]: " IP_R1; IP_R1=${IP_R1:-172.16.0.1/16}
RESTO=$(list_net_interfaces | grep -v -w "$IF_S")
IF_LAB=$(escolher_item "Interface do LAB/Internet (adaptador USB->Eth):" "$RESTO")
echo "LAN#1: $IF_S ($IP_R1) | Lab: $IF_LAB (DHCP)"; confirmar

echo "[R1] Parando NetworkManager..."
sudo systemctl stop NetworkManager 2>/dev/null || true

echo "[R1] LAN#1..."
sudo ip addr flush dev "$IF_S"
sudo ip addr add "$IP_R1" dev "$IF_S"
sudo ip link set "$IF_S" up
sudo ip link set "$IF_S" multicast on

echo "[R1] Uplink do Lab (DHCP)..."
sudo dhclient -r "$IF_LAB" 2>/dev/null || true
sudo dhclient -v "$IF_LAB"

echo "[R1] IP forwarding..."
sudo sysctl -w net.ipv4.ip_forward=1
# mc_forwarding é somente-leitura (fica 1 sozinho quando o smcroute registra a rota em r1-4-multicast.sh)

echo "$IF_S"  > /tmp/frc_if_lan
echo "$IF_LAB" > /tmp/frc_if_lab

echo; echo "=== OK ==="; ip -br addr; ip route | grep default
echo "Teste Internet: curl -sI http://1.1.1.1 | head -1"
