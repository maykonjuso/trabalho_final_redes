#!/bin/bash
# [X/Y] Recebe IP via DHCP do R2 e aponta DNS para o S
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

echo "=== [X/Y] DHCP + DNS ==="
IF_X=$(escolher_item "Interface conectada à LAN#2 (switch do R2):" "$(list_net_interfaces)")
confirmar

echo "[X] Parando NetworkManager..."
sudo systemctl stop NetworkManager 2>/dev/null || true

sudo dhclient -r "$IF_X" 2>/dev/null || true
sudo dhclient -v "$IF_X"

echo "[X] DNS -> servidor S..."
sudo rm -f /etc/resolv.conf
echo "nameserver 172.16.0.2" | sudo tee /etc/resolv.conf >/dev/null

echo; echo "=== OK ==="; ip -br addr show dev "$IF_X"
echo "Testes:"
echo "  ping -c 2 192.168.0.1     # R2"
echo "  ping -c 2 172.16.0.2      # S pela WAN"
echo "  nslookup s.grupo4.unb     # DNS"
echo "  curl -sI http://1.1.1.1 | head -1   # Internet"
