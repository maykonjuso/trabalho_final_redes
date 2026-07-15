#!/bin/bash
# T4 — Bateria completa da aplicação Mini-IPTV (backend + regras de negócio)
# Rode no S (testa também processos VLC e arquivos) ou em qualquer máquina
# (testa via API Gateway do R1 — os testes locais são pulados).
#
# Cobre: OAuth2/JWT, perfis LAN x WAN115K, endereçamento multicast, regra do
# canal único na WAN, troca/saída de canal, difusão sob demanda, playlist,
# upload+conversão+metadados, qualidades leve/ultra/minima, painel admin,
# permissões e o serviço systemd.
PASSA=0; FALHA=0; PULA=0
ok(){ PASSA=$((PASSA+1)); echo -e "\e[32m[OK]\e[0m $1"; }
falha(){ FALHA=$((FALHA+1)); echo -e "\e[31m[FALHOU]\e[0m $1 -> $2"; }
pula(){ PULA=$((PULA+1)); echo -e "\e[33m[PULADO]\e[0m $1"; }
jpick(){ python3 -c "
import sys, json
try: print(json.loads(sys.argv[1]).get(sys.argv[2], ''))
except Exception: print('')" "$1" "$2"; }

# -------- descobre onde está a API (backend direto ou via gateway) --------
API=""; LOCAL=0
for CAND in "http://localhost:8000/api" "http://s.grupo4.unb:8000/api" \
            "http://172.16.0.2:8000/api" "http://r1.grupo4.unb/api" \
            "http://172.16.0.1/api"; do
  R=$(curl -s --max-time 3 -X POST "$CAND/auth/token" -d username=admin -d password=admin123)
  if [ -n "$(jpick "$R" access_token)" ]; then API=$CAND; break; fi
done
[ -z "$API" ] && { echo "[ERRO] nenhum endpoint da API respondeu — backend está no ar?"; exit 1; }
[ "${API#http://localhost}" != "$API" ] && LOCAL=1
echo "=== T4: Backend Mini-IPTV — API: $API $([ $LOCAL = 1 ] && echo '(modo local: S)') ==="
XFF="X-Forwarded-For: 192.168.0.150"   # simula cliente da LAN#2 (perfil WAN115K)

# -------- limpeza de execuções anteriores --------
R=$(curl -s -X POST $API/auth/token -d username=admin -d password=admin123)
TA=$(jpick "$R" access_token)
curl -s -X DELETE $API/videos/9 -H "Authorization: Bearer $TA" >/dev/null
curl -s -X DELETE $API/canais/9 -H "Authorization: Bearer $TA" >/dev/null

echo; echo "--- autenticação OAuth2 / JWT ---"
[[ "$TA" == *.*.* ]] && ok "login admin emite JWT (header.payload.assinatura)" || falha "login admin" "$R"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/auth/token -d username=admin -d password=errada)
[ "$S" = 401 ] && ok "senha errada -> 401" || falha "senha errada" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' $API/canais)
[ "$S" = 401 ] && ok "requisição sem token -> 401" || falha "sem token" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' $API/canais -H "Authorization: Bearer ${TA}x")
[ "$S" = 401 ] && ok "token adulterado -> 401 (assinatura HMAC confere)" || falha "token adulterado" "$S"
R=$(curl -s -X POST $API/auth/token -d username=aluno1 -d password=senha1); TU=$(jpick "$R" access_token)
[ "$(jpick "$R" papel)" = user ] && ok "login aluno1 (papel user)" || falha "login aluno1" "$R"
R=$(curl -s $API/auth/perfil -H "Authorization: Bearer $TU")
[ "$(jpick "$R" login)" = aluno1 ] && ok "/auth/perfil identifica o usuário do token" || falha "/auth/perfil" "$R"

echo; echo "--- permissões (admin x user) ---"
S=$(curl -s -o /dev/null -w '%{http_code}' $API/admin/painel -H "Authorization: Bearer $TU")
[ "$S" = 403 ] && ok "user comum no painel admin -> 403" || falha "painel como user" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais -H "Authorization: Bearer $TU" \
     -H 'Content-Type: application/json' -d '{"numero":9,"nome":"Pirata"}')
[ "$S" = 403 ] && ok "user comum não cadastra canal -> 403" || falha "canal por user" "$S"

echo; echo "--- perfis e endereçamento multicast (239.<perfil>.<grupo>.<canal>) ---"
R=$(curl -s $API/canais -H "Authorization: Bearer $TU")
echo "$R" | grep -q '"perfil":"LAN"' && echo "$R" | grep -q '239.10.4.1' \
  && ok "perfil LAN: canais anunciam 239.10.4.x" || falha "canais LAN" "$R"
R=$(curl -s $API/canais -H "Authorization: Bearer $TU" -H "$XFF")
echo "$R" | grep -q '"perfil":"WAN115K"' && echo "$R" | grep -q '239.20.4.1' \
  && ok "perfil WAN115K (IP 192.168.0.x): canais anunciam 239.20.4.x" || falha "canais WAN" "$R"
echo "$R" | grep -q '"situacao"' && ok "situação por canal (disponivel/ativo/indisponivel)" || falha "situação" "$R"
echo "$R" | grep -q '"duracao_s"' && ok "metadados do vídeo expostos na listagem" || falha "metadados" "$R"

echo; echo "--- assistir / trocar / sair (difusão sob demanda) ---"
R=$(curl -s -X POST $API/canais/1/assistir -H "Authorization: Bearer $TU")
[ "$(jpick "$R" mcast)" = "udp://@239.10.4.1:5004" ] && ok "assistir canal 1 LAN -> 239.10.4.1:5004" || falha "assistir LAN" "$R"
echo "$R" | grep -q '#EXTM3U' && ok "resposta traz playlist .m3u pronta p/ VLC" || falha "playlist na resposta" "$R"
if [ $LOCAL = 1 ]; then
  sleep 1
  pgrep -f "dst=239.10.4.1" >/dev/null && ok "processo cvlc transmitindo p/ 239.10.4.1" || falha "cvlc canal 1" "$(pgrep -a vlc)"
else
  pula "verificação do processo cvlc (só no S)"
fi
curl -s -X POST $API/canais/3/assistir -H "Authorization: Bearer $TU" >/dev/null
if [ $LOCAL = 1 ]; then
  sleep 1
  ! pgrep -f "dst=239.10.4.1" >/dev/null && pgrep -f "dst=239.10.4.3" >/dev/null \
    && ok "troca de canal: difusão antiga parou, nova no ar" || falha "troca de canal" "$(pgrep -a vlc)"
else
  R=$(curl -s $API/canais -H "Authorization: Bearer $TA")
  N=$(python3 -c "import sys,json; print([c['espectadores'] for c in json.loads(sys.argv[1])['canais'] if c['numero']==3][0])" "$R")
  [ "$N" = 1 ] && ok "troca de canal: sessão migrou p/ o canal 3" || falha "troca de canal" "$N"
fi

echo; echo "--- regra WAN115K: um único canal por vez na LAN#2 ---"
R=$(curl -s -X POST $API/auth/token -d username=aluno2 -d password=senha2); T2=$(jpick "$R" access_token)
R=$(curl -s -X POST $API/auth/token -d username=aluno3 -d password=senha3); T3=$(jpick "$R" access_token)
R=$(curl -s -X POST $API/canais/2/assistir -H "Authorization: Bearer $T2" -H "$XFF")
[ "$(jpick "$R" mcast)" = "udp://@239.20.4.2:5004" ] && ok "1º cliente WAN escolhe o canal (2)" || falha "WAN assiste" "$R"
RESP=$(curl -s -w '\n%{http_code}' -X POST $API/canais/3/assistir -H "Authorization: Bearer $T3" -H "$XFF")
S=$(echo "$RESP" | tail -1); CORPO=$(echo "$RESP" | head -1)
[ "$S" = 409 ] && [ "$(jpick "$CORPO" canal_ativo)" = 2 ] \
  && ok "2º cliente WAN em outro canal -> 409 (canal_ativo=2)" || falha "regra WAN" "$S $CORPO"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais/2/assistir -H "Authorization: Bearer $T3" -H "$XFF")
[ "$S" = 200 ] && ok "2º cliente WAN no MESMO canal -> ok (multicast compartilhado)" || falha "mesmo canal WAN" "$S"
R=$(curl -s $API/canais -H "Authorization: Bearer $TA")
N=$(python3 -c "import sys,json; print([c['espectadores'] for c in json.loads(sys.argv[1])['canais'] if c['numero']==2][0])" "$R")
[ "$N" = 2 ] && ok "contagem de espectadores do canal 2 = 2" || falha "espectadores" "$N"

echo; echo "--- painel administrativo ---"
R=$(curl -s $API/admin/painel -H "Authorization: Bearer $TA")
echo "$R" | grep -q '"total_conectados":3' && ok "usuários conectados = 3" || falha "conectados" "$R"
echo "$R" | grep -q '239.20.4.2:5004' && ok "fluxos multicast ativos listados" || falha "fluxos" "$R"
echo "$R" | grep -q '"ocupada":true' && ok "ocupação da WAN reportada" || falha "wan" "$R"
echo "$R" | grep -q 'processos_vlc' && ok "processos VLC reportados" || falha "processos_vlc" "$R"

echo; echo "--- sair do canal encerra a difusão quando esvazia ---"
curl -s -X POST $API/canais/3/sair -H "Authorization: Bearer $TU" >/dev/null
curl -s -X POST $API/canais/2/sair -H "Authorization: Bearer $T2" -H "$XFF" >/dev/null
curl -s -X POST $API/canais/2/sair -H "Authorization: Bearer $T3" -H "$XFF" >/dev/null
sleep 1
R=$(curl -s $API/admin/painel -H "Authorization: Bearer $TA")
[ "$(jpick "$R" total_conectados)" = 0 ] && ok "todas as sessões encerradas" || falha "sessões restantes" "$R"
if [ $LOCAL = 1 ]; then
  ! pgrep -f "dst=239" >/dev/null && ok "nenhum cvlc órfão transmitindo" || falha "difusão órfã" "$(pgrep -a vlc)"
else
  echo "$R" | grep -q '"fluxos_multicast":\[\]' && ok "nenhum fluxo multicast órfão" || falha "fluxo órfão" "$R"
fi

echo; echo "--- playlist m3u por perfil ---"
R=$(curl -s $API/playlist.m3u -H "Authorization: Bearer $TU")
echo "$R" | head -1 | grep -q '#EXTM3U' && echo "$R" | grep -q '239.10.4.' \
  && ok "playlist LAN (#EXTM3U com 239.10.4.x)" || falha "playlist LAN" "$R"
R=$(curl -s $API/playlist.m3u -H "Authorization: Bearer $TU" -H "$XFF")
echo "$R" | grep -q '239.20.4.' && ok "playlist WAN (239.20.4.x)" || falha "playlist WAN" "$R"

echo; echo "--- administração de canais ---"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais -H "Authorization: Bearer $TA" \
     -H 'Content-Type: application/json' -d '{"numero":9,"nome":"Teste T4","descricao":"canal temporário"}')
[ "$S" = 201 ] && ok "admin cadastra canal 9 -> 201" || falha "cadastrar canal" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais -H "Authorization: Bearer $TA" \
     -H 'Content-Type: application/json' -d '{"numero":9,"nome":"Duplicado"}')
[ "$S" = 409 ] && ok "canal duplicado -> 409" || falha "duplicado" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais -H "Authorization: Bearer $TA" \
     -H 'Content-Type: application/json' -d '{"numero":999,"nome":"x"}')
[ "$S" = 400 ] && ok "número de canal inválido (999) -> 400" || falha "canal inválido" "$S"

echo; echo "--- upload de vídeo (conversões leve/ultra/minima + metadados) ---"
if command -v ffmpeg >/dev/null; then
  ffmpeg -y -f lavfi -i "testsrc=duration=3:size=640x480:rate=25" -f lavfi -i "sine=duration=3" \
         -c:v mpeg4 -c:a aac -shortest /tmp/t4-upload.mp4 >/dev/null 2>&1
  R=$(curl -s -X POST $API/videos -H "Authorization: Bearer $TA" \
       -F canal=9 -F titulo="Video T4" -F arquivo=@/tmp/t4-upload.mp4)
  echo "$R" | grep -q '"ok":true' && echo "$R" | grep -q '"resolucao":"640x480"' \
    && ok "upload + metadados ffprobe (640x480)" || falha "upload" "$R"
  if [ $LOCAL = 1 ]; then
    sudo test -f /opt/miniiptv/videos/canal9_ld.mp4 && sudo test -f /opt/miniiptv/videos/canal9_uld.mp4 \
      && sudo test -f /opt/miniiptv/videos/canal9_min.mp4 \
      && ok "arquivos _ld/_uld/_min gerados" || falha "arquivos WAN" "$(sudo ls /opt/miniiptv/videos/ | grep canal9)"
  else
    pula "conferência dos arquivos convertidos (só no S)"
  fi
  # qualidades WAN no canal recém-criado
  for Q in leve ultra minima; do
    R=$(curl -s -X POST $API/canais/9/assistir -H "Authorization: Bearer $T2" -H "$XFF" \
         -H 'Content-Type: application/json' -d "{\"qualidade\":\"$Q\"}")
    [ "$(jpick "$R" qualidade)" = "$Q" ] && ok "assistir WAN qualidade '$Q'" || falha "qualidade $Q" "$R"
    curl -s -X POST $API/canais/9/sair -H "Authorization: Bearer $T2" -H "$XFF" >/dev/null
    sleep 1
  done
  S=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE $API/videos/9 -H "Authorization: Bearer $TA")
  [ "$S" = 200 ] && ok "remoção do vídeo (registro + arquivos)" || falha "remover vídeo" "$S"
else
  pula "upload e qualidades (ffmpeg não instalado nesta máquina)"
fi
S=$(curl -s -o /dev/null -w '%{http_code}' -X DELETE $API/canais/9 -H "Authorization: Bearer $TA")
[ "$S" = 200 ] && ok "remoção do canal 9" || falha "remover canal" "$S"

echo; echo "--- robustez ---"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais/77/assistir -H "Authorization: Bearer $TU")
[ "$S" = 404 ] && ok "assistir canal inexistente -> 404" || falha "canal inexistente" "$S"
S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/canais -H "Authorization: Bearer $TA" \
     -H 'Content-Type: application/json' -d '{"numero":8,"nome":"PosDup"}')
[ "$S" = 201 ] && ok "escrita após erro anterior (sem 'database is locked')" || falha "lock sqlite" "$S"
curl -s -X DELETE $API/canais/8 -H "Authorization: Bearer $TA" >/dev/null
if [ $LOCAL = 1 ]; then
  sudo systemctl restart miniiptv; sleep 3
  S=$(curl -s -o /dev/null -w '%{http_code}' -X POST $API/auth/token -d username=admin -d password=admin123)
  [ "$S" = 200 ] && [ "$(systemctl is-active miniiptv)" = active ] \
    && ok "serviço systemd volta sozinho após restart" || falha "systemd" "$S"
else
  pula "restart do serviço systemd (só no S)"
fi

echo; echo "=== T4: $PASSA ok, $FALHA falhas, $PULA pulados ==="
exit $FALHA
