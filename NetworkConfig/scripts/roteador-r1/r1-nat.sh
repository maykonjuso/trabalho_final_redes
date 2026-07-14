#!/bin/bash
# [R1] Source NAT (Internet p/ todos) + Destination NAT + firewall
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
[ -n "$IF_LAN" ] || IF_LAN=$(escolher_item "Interface da LAN#1 (cabo até S):" "$(list_net_interfaces)")
[ -n "$IF_LAB" ] || IF_LAB=$(escolher_item "Interface do Lab/Internet:" "$(list_net_interfaces | grep -v -w "$IF_LAN")")
echo "=== [R1] NAT: LAN=$IF_LAN  LAB=$IF_LAB ==="; confirmar

sudo sysctl -w net.ipv4.ip_forward=1

echo "[R1] Limpando regras antigas..."
sudo iptables -F
sudo iptables -t nat -F

echo "[R1] Source NAT (masquerade)..."
sudo iptables -t nat -A POSTROUTING -o "$IF_LAB" -j MASQUERADE

echo "[R1] Encaminhamento (todas as direções usadas na topologia)..."
sudo iptables -A FORWARD -i "$IF_LAN" -o "$IF_LAB" -j ACCEPT
sudo iptables -A FORWARD -i ppp0     -o "$IF_LAB" -j ACCEPT
sudo iptables -A FORWARD -i "$IF_LAN" -o ppp0     -j ACCEPT
sudo iptables -A FORWARD -i ppp0     -o "$IF_LAN" -j ACCEPT
sudo iptables -A FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT

echo "[R1] Destination NAT: Lab:8080 -> S:80..."
sudo iptables -t nat -A PREROUTING -i "$IF_LAB" -p tcp --dport 8080 -j DNAT --to-destination 172.16.0.2:80
sudo iptables -A FORWARD -p tcp -d 172.16.0.2 --dport 80 -j ACCEPT

command -v netfilter-persistent >/dev/null && sudo netfilter-persistent save

echo; echo "=== OK ==="; sudo iptables -t nat -L POSTROUTING -n -v | head -5
echo "Teste em S/R2/X: curl -sI http://1.1.1.1 | head -1"
