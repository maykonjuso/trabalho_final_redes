#!/bin/bash
# [R1] Controle de banda: limita a WAN (ppp0) a 115200 bps com tc/tbf
set -e
echo "=== [R1] tc 115200bit em ppp0 ==="
sudo tc qdisc del dev ppp0 root 2>/dev/null || true
sudo tc qdisc add dev ppp0 root tbf rate 115200bit burst 4kb latency 400ms
tc -s qdisc show dev ppp0
echo "Teste: iperf -s em X | iperf -c <ip-de-X> em S -> ~115 kbps"
