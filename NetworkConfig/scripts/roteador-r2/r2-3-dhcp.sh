#!/bin/bash
# [R2] Servidor DHCP para X e Y (192.168.0.100-200, gw R2, dns S)
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
echo "=== [R2] DHCP em $IF_C ==="; confirmar

command -v dhcpd >/dev/null || sudo apt install -y isc-dhcp-server

sudo systemctl stop isc-dhcp-server 2>/dev/null || true
sudo tee /etc/dhcp/dhcpd.conf >/dev/null <<'EOF'
option domain-name "grupo6.unb";
option domain-name-servers 172.16.0.2;
default-lease-time 600;
max-lease-time 7200;
authoritative;

subnet 192.168.0.0 netmask 255.255.255.0 {
    range 192.168.0.100 192.168.0.200;
    option routers 192.168.0.1;
    option broadcast-address 192.168.0.255;
}
EOF
echo "INTERFACESv4=\"$IF_C\"" | sudo tee /etc/default/isc-dhcp-server >/dev/null
sudo systemctl restart isc-dhcp-server
sudo systemctl enable isc-dhcp-server 2>/dev/null || true

systemctl is-active isc-dhcp-server && echo "=== OK: DHCP ativo ===" \
  || { echo "[ERRO] veja: journalctl -u isc-dhcp-server -n 20"; exit 1; }
echo "Em X: plugue o cabo -> ip a (deve vir 192.168.0.10x)"
