#!/bin/bash
#
# Menu: escolha a máquina e o script para executar
# Topologia: S --- R1 ===(PPP 115200)=== R2 --- X/Y
#
cd "$(dirname "$0")"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; RED='\033[0;31m'; NC='\033[0m'

while true; do
  clear
  echo "=============================================="
  echo "  MINI-IPTV GRUPO 4 — SCRIPTS DE CONFIGURAÇÃO"
  echo "  [S] --- [R1] ==PPP== [R2] --- [X] [Y]"
  echo "=============================================="
  echo
  echo -e "${BLUE}Escolha a máquina:${NC}"
  select MAQ in "servidor-s" "roteador-r1" "roteador-r2" "cliente-x" "testes" "sair"; do
    [ -n "$MAQ" ] && break
  done
  [ "$MAQ" = "sair" ] && exit 0

  DIR="NetworkConfig/scripts/$MAQ"
  echo
  echo -e "${BLUE}Scripts de $MAQ (rode na ordem dos números):${NC}"
  select SCRIPT in $(ls "$DIR"/*.sh 2>/dev/null | sort) "voltar"; do
    [ -n "$SCRIPT" ] && break
  done
  [ "$SCRIPT" = "voltar" ] && continue

  echo -e "${GREEN}Executando $SCRIPT ...${NC}"
  echo "----------------------------------------------"
  bash "$SCRIPT"
  echo "----------------------------------------------"
  read -rp "ENTER para voltar ao menu..."
done
