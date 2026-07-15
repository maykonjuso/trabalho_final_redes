#!/bin/bash
# T2 — Roteamento multicast fim a fim (sem depender do VLC)
#
# ONDE RODAR: em 3 máquinas AO MESMO TEMPO, nesta ordem:
#   1º receptor em X ou Y (perfil WAN) — ou Z/W do lab (perfil LAN)
#   2º emissor no S (é de lá que os vídeos saem)
#   3º contadores em R1 e R2 (papel "roteador")
#
# Emissor injeta tráfego UDP no grupo; receptor confirma que os pacotes
# atravessaram os roteadores (smcroute). Funciona nos dois perfis:
#   LAN  (Z/W):  239.10.6.<canal>   WAN (X/Y):  239.20.6.<canal>
set -u
echo "=== T2: Multicast — escolha o papel desta máquina ==="
echo
echo "Roteiro completo:"
echo "  1) No receptor (X/Y ou Z/W):  este script, papel 'receptor'"
echo "  2) No emissor  (S):           este script, papel 'emissor'"
echo "  3) Nos roteadores (R1/R2):    este script, papel 'roteador'"
echo

PS3="Papel: "
select PAPEL in "receptor" "emissor" "roteador (ver contadores)" "sair"; do
  [ -n "${PAPEL:-}" ] && break
done
[ "$PAPEL" = "sair" ] && exit 0

read -rp "Perfil [1=LAN 239.10.6.x | 2=WAN 239.20.6.x] (padrão 2): " P
GRUPO_M=$([ "${P:-2}" = 1 ] && echo 239.10.6.1 || echo 239.20.6.1)

case "$PAPEL" in
  receptor*)
    if ! command -v iperf >/dev/null; then
      command -v apt >/dev/null && sudo apt install -y iperf || sudo dnf install -y iperf
    fi
    echo "[T2] Escutando $GRUPO_M:5001 — deixe rodando e inicie o emissor no S."
    echo "     Se aparecerem relatórios de banda por segundo, o multicast atravessou a rede."
    iperf -s -u -B "$GRUPO_M" -i 1
    ;;
  emissor*)
    if ! command -v iperf >/dev/null; then
      command -v apt >/dev/null && sudo apt install -y iperf || sudo dnf install -y iperf
    fi
    echo "[T2] Emitindo 80 kb/s por 15 s para $GRUPO_M (TTL 16)..."
    iperf -c "$GRUPO_M" -u -T 16 -t 15 -b 80k
    echo "[T2] Fim. Confira se o receptor mostrou tráfego chegando."
    ;;
  roteador*)
    echo "--- rotas multicast instaladas (smcroute) ---"
    sudo smcroutectl show 2>/dev/null || echo "(smcroute não está rodando nesta máquina)"
    echo
    echo "--- grupos IGMP assinados nas interfaces ---"
    ip maddr show | grep -E "239\.(10|20)\." || echo "(nenhum grupo 239.x assinado aqui)"
    echo
    echo "--- encaminhamento multicast do kernel ---"
    sysctl net.ipv4.conf.all.mc_forwarding 2>/dev/null || true
    echo
    echo "[T2] Rode o emissor+receptor e observe os contadores de pacotes:"
    echo "     watch -n1 'sudo smcroutectl show'"
    ;;
esac
