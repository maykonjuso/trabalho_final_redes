#!/bin/bash
#
# Menu do projeto — na 1ª execução você diz QUE máquina é esta; a escolha
# fica gravada e, das próximas vezes, o menu já mostra somente os scripts
# de configuração e os testes que fazem sentido nesta máquina.
# Topologia: S --- R1 ===(PPP 115200)=== R2 --- X/Y
#
cd "$(dirname "$0")"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[0;33m'; RED='\033[0;31m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

# guarda a escolha FORA do repositório (o pendrive roda em várias máquinas);
# /etc quando der (sudo), senão no home do usuário
ARQ_MAQ_ETC="/etc/miniiptv.maquina"
ARQ_MAQ_HOME="$HOME/.miniiptv.maquina"
MAQUINAS=(servidor-s roteador-r1 roteador-r2 cliente-x)

descricao_maquina(){
  case "$1" in
    servidor-s)  echo "S  — DNS, e-mail, VLC e backend (172.16.0.2)";;
    roteador-r1) echo "R1 — gateway, NAT, tc, Apache/API-GW (172.16.0.1 / 10.0.0.1)";;
    roteador-r2) echo "R2 — DHCP e multicast da LAN#2 (10.0.0.2 / 192.168.0.1)";;
    cliente-x)   echo "X/Y — cliente com frontend e VLC (DHCP .100-.200)";;
  esac
}

descricao_script(){
  case "$(basename "$1")" in
    s-1-lan.sh)  echo "IP fixo 172.16.0.2 + gateway R1";;
    s-2-dns.sh)  echo "BIND9: zona grupo6.unb";;
    s-3-email.sh) echo "Postfix + Dovecot (SMTP/IMAP/POP3 TLS)";;
    s-4-backend.sh) echo "backend Mini-IPTV (Flask + systemd)";;
    r1-1-lan.sh) echo "IP 172.16.0.1 + uplink do Lab";;
    r1-2-ppp.sh) echo "WAN PPP serial (rodar DEPOIS do R2)";;
    r1-3-nat.sh) echo "SNAT/DNAT/firewall";;
    r1-4-multicast.sh) echo "smcroute LAN/WAN";;
    r1-5-tc.sh)  echo "limita a WAN em 115200 bps";;
    r1-6-web.sh) echo "Apache: intranet + API Gateway + frontend";;
    r2-1-lan.sh) echo "IP 192.168.0.1";;
    r2-2-ppp.sh) echo "WAN PPP serial (rodar ANTES do R1)";;
    r2-3-dhcp.sh) echo "DHCP para X e Y";;
    r2-4-multicast.sh) echo "smcroute WAN -> LAN#2";;
    x-1-dhcp.sh) echo "pega IP por DHCP + DNS -> S";;
    x-2-dns.sh)  echo "aponta o DNS para o S";;
    t-1-conectividade.sh) echo "pings de todos os saltos, NAT, DNS";;
    t-2-multicast.sh) echo "multicast fim a fim com iperf";;
    t-3-servicos.sh) echo "DNS, web/gateway, e-mail, DHCP";;
    t-4-backend.sh) echo "bateria completa da aplicação (41 testes)";;
    t-5-wan.sh)  echo "enlace PPP: tc, latência, drops";;
    *) echo "";;
  esac
}

testes_da_maquina(){
  case "$1" in
    servidor-s)  echo "t-1-conectividade.sh t-2-multicast.sh t-4-backend.sh";;
    roteador-r1|roteador-r2)
                 echo "t-1-conectividade.sh t-2-multicast.sh t-5-wan.sh";;
    cliente-x)   echo "t-1-conectividade.sh t-2-multicast.sh t-3-servicos.sh t-4-backend.sh";;
  esac
}

salvar_maquina(){
  if echo "$1" | sudo tee "$ARQ_MAQ_ETC" >/dev/null 2>&1; then :; else
    echo "$1" > "$ARQ_MAQ_HOME"
  fi
}

carregar_maquina(){
  MAQ=$(cat "$ARQ_MAQ_ETC" 2>/dev/null || cat "$ARQ_MAQ_HOME" 2>/dev/null)
  case " ${MAQUINAS[*]} " in
    *" $MAQ "*) ;;         # valor válido
    *) MAQ="";;            # arquivo ausente/corrompido -> pergunta de novo
  esac
}

# usa caixas de diálogo (whiptail, já vem no Ubuntu) quando há terminal;
# senão cai no menu de texto colorido
TEM_WHIPTAIL=0
command -v whiptail >/dev/null && [ -t 0 ] && [ -t 1 ] && TEM_WHIPTAIL=1

cabecalho(){
  echo -e "${BOLD}${CYAN}==============================================${NC}"
  echo -e "${BOLD}  MINI-IPTV ${MAGENTA}GRUPO 6${NC}${BOLD} — $1${NC}"
  echo -e "${DIM}  [S] --- [R1] ==PPP== [R2] --- [X] [Y]${NC}"
  echo -e "${BOLD}${CYAN}==============================================${NC}"
  echo
}

escolher_maquina(){
  clear
  cabecalho "primeira configuração"
  echo -e "${BOLD}Que máquina é esta?${NC} ${DIM}(fica gravado; dá p/ trocar depois no menu)${NC}"
  echo
  local i=1
  for m in "${MAQUINAS[@]}"; do
    echo -e "  ${BOLD}${YELLOW}$i)${NC} $(descricao_maquina "$m")"
    i=$((i+1))
  done
  echo
  while true; do
    read -rp "$(echo -e "${BOLD}Número da máquina: ${NC}")" R
    [[ "$R" =~ ^[1-4]$ ]] && break
    echo -e "${RED}opção inválida — digite 1 a 4${NC}"
  done
  MAQ="${MAQUINAS[$((R-1))]}"
  salvar_maquina "$MAQ"
  echo -e "${GREEN}✔ Gravado: esta máquina é '$MAQ'.${NC}"
  sleep 1
}

carregar_maquina
[ -z "$MAQ" ] && escolher_maquina

while true; do
  clear
  cabecalho "$(descricao_maquina "$MAQ")"

  # monta o menu: configuração da máquina + testes aplicáveis + utilitários
  ARQUIVOS=(); N=0
  echo -e "${BOLD}${GREEN}  CONFIGURAÇÃO ${NC}${DIM}(rode na ordem dos números)${NC}"
  for s in $(ls "NetworkConfig/scripts/$MAQ"/*.sh 2>/dev/null | sort); do
    N=$((N+1)); ARQUIVOS+=("$s")
    printf "   ${BOLD}${YELLOW}%2d)${NC} ${GREEN}%-24s${NC} ${DIM}%s${NC}\n" \
           "$N" "$(basename "$s")" "$(descricao_script "$s")"
  done
  echo
  echo -e "${BOLD}${CYAN}  TESTES ${NC}${DIM}(desta máquina)${NC}"
  for t in $(testes_da_maquina "$MAQ"); do
    N=$((N+1)); ARQUIVOS+=("NetworkConfig/scripts/testes/$t")
    printf "   ${BOLD}${YELLOW}%2d)${NC} ${CYAN}%-24s${NC} ${DIM}%s${NC}\n" \
           "$N" "$t" "$(descricao_script "$t")"
  done
  echo
  echo -e "${BOLD}${MAGENTA}  OUTROS${NC}"
  OPC_RESET=$((N+1)); OPC_TROCA=$((N+2)); OPC_SAIR=$((N+3))
  printf "   ${BOLD}${YELLOW}%2d)${NC} ${RED}%-24s${NC} ${DIM}%s${NC}\n" "$OPC_RESET" "RESET" "desfaz TUDO nesta máquina e volta a Internet do Lab"
  printf "   ${BOLD}${YELLOW}%2d)${NC} ${MAGENTA}%-24s${NC} ${DIM}%s${NC}\n" "$OPC_TROCA" "trocar de máquina" "regrava qual máquina é esta"
  printf "   ${BOLD}${YELLOW}%2d)${NC} %-24s\n" "$OPC_SAIR" "sair"
  echo

  read -rp "$(echo -e "${BOLD}Opção: ${NC}")" R
  [[ "$R" =~ ^[0-9]+$ ]] || { echo -e "${RED}opção inválida${NC}"; sleep 1; continue; }

  if   [ "$R" = "$OPC_SAIR" ]; then exit 0
  elif [ "$R" = "$OPC_TROCA" ]; then escolher_maquina; continue
  elif [ "$R" = "$OPC_RESET" ]; then
    bash NetworkConfig/scripts/reset-maquina.sh
    read -rp "ENTER para voltar ao menu..."; continue
  elif [ "$R" -ge 1 ] && [ "$R" -le "$N" ]; then
    SCRIPT="${ARQUIVOS[$((R-1))]}"
    echo -e "${GREEN}${BOLD}▶ Executando $SCRIPT ...${NC}"
    echo "----------------------------------------------"
    bash "$SCRIPT"
    echo "----------------------------------------------"
    read -rp "ENTER para voltar ao menu..."
  else
    echo -e "${RED}opção inválida${NC}"; sleep 1
  fi
done
