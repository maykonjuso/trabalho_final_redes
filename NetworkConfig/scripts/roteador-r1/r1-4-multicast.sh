#!/bin/bash
# [R1] Roteamento multicast (smcroute): 239.10.6.x -> Lab | 239.20.6.x -> WAN
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

IF_LAN=$(cat /tmp/frc_if_lan 2>/dev/null || true)
IF_LAB=$(cat /tmp/frc_if_lab 2>/dev/null || true)
[ -n "$IF_LAN" ] || IF_LAN=$(escolher_item "Interface da LAN#1 (origem S):" "$(list_net_interfaces)")
[ -n "$IF_LAB" ] || IF_LAB=$(escolher_item "Interface do Lab (Z/W):" "$(list_net_interfaces | grep -v -w "$IF_LAN")")
echo "=== [R1] Multicast: $IF_LAN -> $IF_LAB (LAN) e $IF_LAN -> ppp0 (WAN) ==="; confirmar

command -v smcroutectl >/dev/null || sudo apt install -y smcroute
sudo systemctl restart smcroute      # limpa rotas antigas
sudo systemctl enable smcroute 2>/dev/null || true
sleep 1
sudo smcroutectl add "$IF_LAN" 239.10.6.0/24 "$IF_LAB"
sudo smcroutectl add "$IF_LAN" 239.20.6.0/24 ppp0

echo; echo "=== OK ==="; sudo smcroutectl show
