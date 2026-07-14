#!/bin/bash
# [R2] Roteamento multicast: WAN (ppp0) -> LAN#2
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

IF_C=$(cat /tmp/frc_if_lan2 2>/dev/null || true)
[ -n "$IF_C" ] || IF_C=$(escolher_item "Interface da LAN#2:" "$(list_net_interfaces)")
echo "=== [R2] Multicast: ppp0 -> $IF_C ==="; confirmar

command -v smcroutectl >/dev/null || sudo apt install -y smcroute
sudo systemctl restart smcroute
sudo systemctl enable smcroute 2>/dev/null || true
sleep 1
sudo smcroutectl add ppp0 239.20.4.0/24 "$IF_C"
sudo smcroutectl join "$IF_C" 239.20.4.1

echo; echo "=== OK ==="; sudo smcroutectl show
