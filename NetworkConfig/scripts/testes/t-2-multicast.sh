#!/bin/bash
# Teste de multicast sem VLC (iperf)
echo "=== Multicast 239.20.4.1 (perfil WAN) ==="
echo "1) Em X (receptor, deixe rodando):  iperf -s -u -B 239.20.4.1 -i 1"
echo "2) Em S (emissor):                  iperf -c 239.20.4.1 -u -T 5 -t 15 -b 80k"
echo "3) Em R1 e R2 (contadores subindo): sudo smcroutectl show"
echo
read -rp "Este host é o receptor (X)? [s/N] " r
if [[ "$r" =~ ^[sS]$ ]]; then
  command -v iperf >/dev/null || sudo apt install -y iperf
  iperf -s -u -B 239.20.4.1 -i 1
fi
