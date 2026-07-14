#!/bin/bash
# [S] Interface de rede + gateway padrão
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

echo "=== [S] LAN #1 ==="
IF_S=$(escolher_item "Interface conectada ao R1 (cabo direto):" "$(list_net_interfaces)")
read -rp "IP do S [172.16.0.2/16]: " IP_S; IP_S=${IP_S:-172.16.0.2/16}
read -rp "Gateway (R1) [172.16.0.1]: " GW_S; GW_S=${GW_S:-172.16.0.1}
echo "Interface=$IF_S  IP=$IP_S  GW=$GW_S"; confirmar

echo "[S] Parando NetworkManager (senão ele desfaz a config)..."
sudo systemctl stop NetworkManager 2>/dev/null || true

echo "[S] Limpando e aplicando..."
sudo ip addr flush dev "$IF_S"
sudo ip addr add "$IP_S" dev "$IF_S"
sudo ip link set "$IF_S" up
sudo ip link set "$IF_S" multicast on
sudo ip route del default 2>/dev/null || true
sudo ip route add default via "$GW_S"
sudo ip route replace 239.0.0.0/8 dev "$IF_S"   # multicast sai pela LAN#1

echo; echo "=== OK ==="; ip -br addr show dev "$IF_S"; ip route show
echo "Teste: ping -c 2 $GW_S"
