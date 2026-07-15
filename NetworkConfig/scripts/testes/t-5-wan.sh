#!/bin/bash
# T5 — Enlace WAN PPP 115200 bps + controle de banda (tc)
#
# ONDE RODAR: no R1 (é lá que estão o ppp0 e o tc de 115200 bps — mostra
# qdisc, drops e backlog). No R2 valida o outro lado do enlace; nas demais
# máquinas só a travessia é testada e o resto sai como [PULADO].
PASSA=0; FALHA=0; PULA=0
ok(){ PASSA=$((PASSA+1)); echo -e "\e[32m[OK]\e[0m $1"; }
falha(){ FALHA=$((FALHA+1)); echo -e "\e[31m[FALHOU]\e[0m $1"; }
pula(){ PULA=$((PULA+1)); echo -e "\e[33m[PULADO]\e[0m $1"; }

echo "=== T5: Enlace WAN (PPP serial 115200 bps) ==="
echo
if ip link show ppp0 >/dev/null 2>&1; then
  ok "interface ppp0 existe nesta máquina"
  ip -br addr show ppp0
  echo
  echo "--- controle de banda (tc) no ppp0 ---"
  TC=$(tc qdisc show dev ppp0 2>/dev/null)
  echo "$TC"
  if echo "$TC" | grep -qE "tbf|htb|cake"; then
    echo "$TC" | grep -qE "115200|115Kbit|112Kbit" \
      && ok "qdisc limitando em ~115200 bps" \
      || ok "qdisc de limitação presente (confira a taxa acima)"
  else
    pula "sem qdisc de limitação aqui (o tc fica no R1: r1-5-tc.sh)"
  fi
  echo
  echo "--- estatísticas do enlace (drops/backlog indicam saturação) ---"
  tc -s qdisc show dev ppp0 2>/dev/null | sed 's/^/  /'
  ip -s link show ppp0 | sed 's/^/  /'
else
  pula "ppp0 não existe aqui (normal fora de R1/R2)"
fi

echo
echo "--- travessia do enlace (10.0.0.1 <-> 10.0.0.2) ---"
for IP in 10.0.0.1 10.0.0.2; do
  ping -c 2 -W 3 $IP >/dev/null 2>&1 && ok "alcança $IP" || falha "não alcança $IP"
done

echo
echo "--- latência x tamanho do pacote (serialização a 115200 bps) ---"
# a 115200 bps, cada byte leva ~69 us; um ping de 1000 B deve demorar
# ~140 ms a mais (ida+volta) que um de 56 B — é a prova de que o enlace
# está mesmo limitado à taxa serial.
for TAM in 56 500 1000; do
  RTT=$(ping -c 3 -s $TAM -W 4 10.0.0.2 2>/dev/null | awk -F/ '/rtt|round-trip/{print $5}')
  [ -n "$RTT" ] && echo "  payload ${TAM}B -> RTT médio ${RTT} ms" \
                || echo "  payload ${TAM}B -> sem resposta"
done
RTT=$(ping -c 3 -s 1000 -W 4 10.0.0.2 2>/dev/null | awk -F/ '/rtt|round-trip/{print $5}')
if [ -n "$RTT" ]; then
  python3 -c "
rtt = float('$RTT')
print('[OK] RTT de %.0f ms p/ 1000B é coerente com 115200 bps' % rtt if rtt > 100
      else '[AVISO] RTT de %.0f ms p/ 1000B parece rápido demais — o enlace está mesmo a 115200 bps?' % rtt)"
fi

echo
echo "--- vazão real do enlace (iperf TCP, opcional) ---"
echo "  No R2:  iperf -s          |  No R1:  iperf -c 10.0.0.2 -t 10"
echo "  Esperado: ~90-110 kbit/s úteis (115200 menos overhead PPP/TCP)."

echo
echo "=== T5: $PASSA ok, $FALHA falhas, $PULA pulados ==="
exit $FALHA
