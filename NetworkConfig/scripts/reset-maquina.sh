#!/bin/bash
# RESET — desfaz TUDO que os scripts do projeto configuraram nesta máquina
# e devolve a rede ao NetworkManager (Internet normal do Lab de volta).
# Serve para S, R1, R2, X ou Y. Pode rodar quantas vezes quiser.
set -u

echo "=== RESET da máquina (desfaz o projeto e restaura a Internet) ==="
read -rp "Confirma? [s/N] " c
[[ "$c" =~ ^[sS]$ ]] || { echo "Abortado."; exit 1; }

echo "[1/9] Matando pppd e removendo peers..."
sudo killall pppd 2>/dev/null || true
sudo rm -f /etc/ppp/peers/wan_r1 /etc/ppp/peers/wan_r2

echo "[2/9] Parando serviços do projeto (se existirem)..."
sudo systemctl stop isc-dhcp-server 2>/dev/null || true
sudo systemctl disable isc-dhcp-server 2>/dev/null || true
sudo systemctl stop smcroute 2>/dev/null || true
sudo systemctl disable smcroute 2>/dev/null || true
sudo systemctl stop miniiptv 2>/dev/null || true

echo "[3/9] Limpando firewall/NAT..."
sudo iptables -F 2>/dev/null || true
sudo iptables -t nat -F 2>/dev/null || true
sudo netfilter-persistent save 2>/dev/null || true

echo "[4/9] Removendo tc da WAN..."
sudo tc qdisc del dev ppp0 root 2>/dev/null || true

echo "[5/9] Zerando IPs fixos e rotas de todas as placas cabeadas..."
for d in /sys/class/net/*; do
  n=$(basename "$d")
  case "$n" in lo|ppp*|docker*|veth*|br-*|virbr*|wl*) continue;; esac
  sudo ip addr flush dev "$n" 2>/dev/null || true
done
sudo ip route flush table main 2>/dev/null || true

echo "[6/9] Desligando roteamento do kernel..."
sudo sysctl -w net.ipv4.ip_forward=0 >/dev/null
sudo sysctl -w net.ipv4.conf.all.mc_forwarding=0 >/dev/null 2>&1 || true

echo "[7/9] Restaurando o resolv.conf padrão (systemd-resolved)..."
sudo rm -f /etc/resolv.conf
sudo ln -s ../run/systemd/resolve/stub-resolv.conf /etc/resolv.conf 2>/dev/null || true
sudo systemctl restart systemd-resolved 2>/dev/null || true

echo "[8/9] Religando o NetworkManager (ele refaz DHCP e a Internet)..."
sudo systemctl start NetworkManager
sudo systemctl enable NetworkManager 2>/dev/null || true
sleep 6

echo "[9/9] Verificando..."
ip -br addr
ip route | grep default || echo "[AVISO] sem rota default ainda — aguarde uns segundos ou reconecte o cabo do Lab"
curl -sI --connect-timeout 6 http://1.1.1.1 2>/dev/null | head -1 | grep -q HTTP \
  && echo -e "\e[32m[OK] Internet restaurada!\e[0m" \
  || echo -e "\e[31m[FALHOU]\e[0m Sem Internet ainda. Confira: o cabo desta máquina está na rede do LAB? (não no switch do projeto). Se sim: sudo nmcli device connect <placa>  ou reinicie a máquina."

echo
echo "Reset concluído. Para remontar o projeto depois, rode os scripts na ordem do README."
