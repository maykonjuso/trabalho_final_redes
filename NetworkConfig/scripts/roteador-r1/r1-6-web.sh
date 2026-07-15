#!/bin/bash
# [R1] Apache: página da intranet + API Gateway (proxy reverso) HTTP e HTTPS + frontend v2
set -e
echo "=== [R1] WEB + API Gateway ==="

command -v apache2ctl >/dev/null || sudo apt install -y apache2
sudo a2enmod proxy proxy_http headers ssl >/dev/null

# ---------- página estática da intranet ----------
sudo tee /var/www/html/index.html >/dev/null <<'HTML'
<!doctype html><meta charset="utf-8"><title>Intranet Grupo 4</title>
<style>
  body{margin:0;min-height:100vh;display:grid;place-items:center;
       background:#0b0e14;color:#e6e9f0;font-family:system-ui,sans-serif}
  .cartao{text-align:center;padding:3rem 4rem;border:1px solid #232a3a;
          border-radius:18px;background:#111623}
  h1{margin:0 0 .3rem;font-size:2rem;
     background:linear-gradient(90deg,#7c6cff,#2dd4bf);
     -webkit-background-clip:text;background-clip:text;color:transparent}
  p{color:#8b93a7}
  a{display:inline-block;margin-top:1.2rem;padding:.8rem 2rem;border-radius:10px;
    background:linear-gradient(90deg,#7c6cff,#5b8cff);color:#fff;
    text-decoration:none;font-weight:600}
</style>
<div class="cartao">
  <h1>Intranet — Grupo 4</h1>
  <p>FRC · Mini-IPTV Multicast com Controle de Banda WAN</p>
  <a href="/iptv.html">▶ Abrir Mini-IPTV</a>
</div>
HTML

# ---------- frontend Mini-IPTV ----------
sudo tee /var/www/html/iptv.html >/dev/null <<'HTML'
<!doctype html>
<html lang="pt-BR">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>Mini-IPTV · Grupo 4</title>
<style>
  :root{
    --fundo:#0b0e14; --painel:#111623; --painel2:#161d2e; --borda:#232a3a;
    --texto:#e6e9f0; --apagado:#8b93a7; --roxo:#7c6cff; --azul:#5b8cff;
    --verde:#2dd4bf; --vermelho:#f87171; --ambar:#fbbf24;
  }
  *{box-sizing:border-box}
  body{margin:0;background:var(--fundo);color:var(--texto);
       font-family:system-ui,-apple-system,"Segoe UI",sans-serif}
  button{font:inherit;cursor:pointer;border:none;border-radius:9px;
         padding:.55rem 1.1rem;font-weight:600}
  input,select{font:inherit;background:var(--fundo);color:var(--texto);
         border:1px solid var(--borda);border-radius:9px;padding:.6rem .8rem;width:100%}
  input:focus,select:focus{outline:2px solid var(--roxo)}
  .primario{background:linear-gradient(90deg,var(--roxo),var(--azul));color:#fff}
  .fantasma{background:var(--painel2);color:var(--texto);border:1px solid var(--borda)}
  .perigo{background:transparent;color:var(--vermelho);border:1px solid var(--vermelho)}
  .marca{font-weight:800;background:linear-gradient(90deg,var(--roxo),var(--verde));
         -webkit-background-clip:text;background-clip:text;color:transparent}

  /* ---- login ---- */
  #telaLogin{min-height:100vh;display:grid;place-items:center}
  #telaLogin form{width:min(360px,92vw);background:var(--painel);padding:2.2rem;
        border:1px solid var(--borda);border-radius:18px;display:grid;gap:.9rem}
  #telaLogin h1{margin:0;text-align:center;font-size:1.9rem}
  #telaLogin p{margin:0 0 .5rem;text-align:center;color:var(--apagado);font-size:.85rem}
  #erroLogin{color:var(--vermelho);text-align:center;font-size:.85rem;min-height:1.1em;margin:0}

  /* ---- app ---- */
  #app{display:none;max-width:1100px;margin:0 auto;padding:0 1rem 4rem}
  header{display:flex;align-items:center;gap:.8rem;flex-wrap:wrap;padding:1.1rem 0;
         border-bottom:1px solid var(--borda);margin-bottom:1.2rem}
  header .marca{font-size:1.4rem;margin-right:auto}
  .chip{padding:.25rem .7rem;border-radius:99px;font-size:.75rem;font-weight:700;
        border:1px solid var(--borda);background:var(--painel2)}
  .chip.lan{color:var(--verde);border-color:var(--verde)}
  .chip.wan{color:var(--ambar);border-color:var(--ambar)}

  #avisoAgora{display:none;align-items:center;gap:.8rem;flex-wrap:wrap;
        background:linear-gradient(90deg,#1b1533,#0f2430);border:1px solid var(--roxo);
        border-radius:14px;padding:.9rem 1.2rem;margin-bottom:1.2rem}
  #avisoAgora code{background:#000;padding:.25rem .6rem;border-radius:7px;color:var(--verde)}

  .grade{display:grid;grid-template-columns:repeat(auto-fill,minmax(310px,1fr));gap:1.1rem}
  .canal{background:var(--painel);border:1px solid var(--borda);border-radius:16px;
         padding:1.1rem 1.2rem;display:flex;flex-direction:column;gap:.7rem}
  .canal.aovivo{border-color:var(--roxo);box-shadow:0 0 22px #7c6cff33}
  .canal .topo{display:flex;align-items:center;gap:.7rem}
  .numero{width:2.6rem;height:2.6rem;border-radius:12px;display:grid;place-items:center;
          font-weight:800;font-size:1.15rem;color:#fff;
          background:linear-gradient(135deg,var(--roxo),var(--azul))}
  .canal h3{margin:0;font-size:1.05rem}
  .pil{margin-left:auto;padding:.2rem .65rem;border-radius:99px;font-size:.7rem;font-weight:700}
  .pil.ativo{background:#7c6cff26;color:var(--roxo)}
  .pil.ativo::before{content:"● ";color:var(--vermelho)}
  .pil.disponivel{background:#2dd4bf1f;color:var(--verde)}
  .pil.indisponivel{background:#f871711f;color:var(--vermelho)}
  .desc{color:var(--apagado);font-size:.86rem;min-height:1.2em;margin:0}
  .meta{display:grid;grid-template-columns:1fr 1fr;gap:.25rem .8rem;font-size:.78rem;
        background:var(--painel2);border-radius:10px;padding:.6rem .8rem}
  .meta span{color:var(--apagado)}
  .rodape{display:flex;align-items:center;gap:.6rem;margin-top:auto}
  .rodape .esp{margin-right:auto;color:var(--apagado);font-size:.82rem}
  .mcast{font-size:.72rem;color:var(--apagado);font-family:monospace}

  /* ---- admin ---- */
  #admin{display:none;margin-top:2.2rem;background:var(--painel);
         border:1px solid var(--borda);border-radius:16px;overflow:hidden}
  #abas{display:flex;border-bottom:1px solid var(--borda)}
  #abas button{flex:1;background:none;color:var(--apagado);border-radius:0;padding:.9rem}
  #abas button.ativa{color:var(--texto);background:var(--painel2);
        box-shadow:inset 0 -2px 0 var(--roxo)}
  .aba{display:none;padding:1.3rem}
  .aba.ativa{display:block}
  .formlinha{display:flex;gap:.7rem;flex-wrap:wrap;margin-bottom:1rem}
  .formlinha>*{flex:1;min-width:130px}
  table{width:100%;border-collapse:collapse;font-size:.85rem}
  th,td{text-align:left;padding:.5rem .6rem;border-bottom:1px solid var(--borda)}
  th{color:var(--apagado);font-weight:600}
  .medidor{height:10px;border-radius:99px;background:var(--painel2);overflow:hidden;margin:.3rem 0 1rem}
  .medidor div{height:100%;background:linear-gradient(90deg,var(--verde),var(--ambar));width:0}
  pre{background:#000;border-radius:10px;padding:.8rem;font-size:.72rem;overflow-x:auto}

  #toasts{position:fixed;bottom:1.2rem;right:1.2rem;display:grid;gap:.5rem;z-index:9}
  .toast{background:var(--painel2);border:1px solid var(--borda);border-left:4px solid var(--verde);
         border-radius:10px;padding:.7rem 1.1rem;font-size:.85rem;max-width:320px}
  .toast.erro{border-left-color:var(--vermelho)}
</style>

<!-- ============ LOGIN ============ -->
<div id="telaLogin">
  <form onsubmit="entrar(event)">
    <h1 class="marca">IPTV·4</h1>
    <p>Mini-IPTV Multicast — FRC · Grupo 4</p>
    <input id="campoUsuario" placeholder="usuário" autocomplete="username" required>
    <input id="campoSenha" type="password" placeholder="senha" autocomplete="current-password" required>
    <p id="erroLogin"></p>
    <button class="primario">Entrar</button>
  </form>
</div>

<!-- ============ APLICAÇÃO ============ -->
<div id="app">
  <header>
    <span class="marca">IPTV·4</span>
    <span id="chipPerfil" class="chip"></span>
    <span id="chipUsuario" class="chip"></span>
    <select id="selQualidade" style="display:none;width:auto" title="qualidade da transmissão WAN">
      <option value="leve">qualidade leve · 80 kb/s</option>
      <option value="ultra" selected>ultra leve · ~20 kb/s (PPP lento)</option>
      <option value="minima">mínima · ~12 kb/s (último recurso)</option>
    </select>
    <button class="fantasma" onclick="baixarPlaylist()">⬇ playlist .m3u</button>
    <button id="botaoAdmin" class="fantasma" style="display:none"
            onclick="alternarAdmin()">⚙ admin</button>
    <button class="perigo" onclick="sairDoSistema()">sair</button>
  </header>

  <div id="avisoAgora">
    <b>▶ Assistindo canal <span id="agoraCanal"></span></b>
    <span>abra no VLC (Mídia → Abrir fluxo de rede):</span>
    <code id="agoraMcast"></code>
  </div>

  <div id="gradeCanais" class="grade"></div>

  <!-- ============ ADMIN ============ -->
  <section id="admin">
    <div id="abas">
      <button class="ativa" onclick="abrirAba(event,'abaCanais')">Canais</button>
      <button onclick="abrirAba(event,'abaVideos')">Vídeos</button>
      <button onclick="abrirAba(event,'abaPainel')">Painel</button>
    </div>

    <div id="abaCanais" class="aba ativa">
      <div class="formlinha">
        <input id="novoNumero" type="number" min="1" max="254" placeholder="nº">
        <input id="novoNome" placeholder="nome do canal">
        <input id="novaDescricao" placeholder="descrição">
        <button class="primario" onclick="criarCanal()">+ cadastrar</button>
      </div>
      <table id="tabelaCanais"></table>
    </div>

    <div id="abaVideos" class="aba">
      <div class="formlinha">
        <select id="videoCanal"></select>
        <input id="videoTitulo" placeholder="título (opcional)">
        <input id="videoArquivo" type="file" accept="video/*">
        <button class="primario" onclick="enviarVideo()">⬆ enviar</button>
      </div>
      <p id="statusUpload" class="desc"></p>
      <table id="tabelaVideos"></table>
    </div>

    <div id="abaPainel" class="aba">
      <h4>Enlace WAN (115200 bps)</h4>
      <div class="medidor"><div id="barraWan"></div></div>
      <p id="textoWan" class="desc"></p>
      <h4>Usuários conectados</h4><table id="tabelaSessoes"></table>
      <h4>Fluxos multicast ativos</h4><table id="tabelaFluxos"></table>
      <h4>Processos VLC no servidor</h4><pre id="preVlc"></pre>
    </div>
  </section>
</div>

<div id="toasts"></div>

<script>
"use strict";
let token = null, souAdmin = false, dadosCanais = [];
const $ = id => document.getElementById(id);

function toast(msg, erro=false){
  const t = document.createElement("div");
  t.className = "toast" + (erro ? " erro" : "");
  t.textContent = msg;
  $("toasts").appendChild(t);
  setTimeout(() => t.remove(), 4200);
}

async function api(caminho, opcoes = {}){
  const r = await fetch("/api" + caminho, {...opcoes,
    headers: {...(opcoes.headers||{}), ...(token ? {Authorization: "Bearer " + token} : {})}});
  const texto = await r.text();
  let corpo = {};
  try { corpo = JSON.parse(texto); } catch { corpo = {bruto: texto}; }
  return {status: r.status, corpo};
}

/* ---------------- autenticação ---------------- */
async function entrar(ev){
  ev.preventDefault();
  const corpoForm = new URLSearchParams({username: $("campoUsuario").value,
                                         password: $("campoSenha").value});
  const {status, corpo} = await api("/auth/token", {method: "POST", body: corpoForm});
  if (status !== 200){ $("erroLogin").textContent = corpo.detalhe || "falha no login"; return; }
  token = corpo.access_token;
  souAdmin = corpo.papel === "admin";
  $("telaLogin").style.display = "none";
  $("app").style.display = "block";
  $("chipUsuario").textContent = "@" + $("campoUsuario").value;
  $("botaoAdmin").style.display = souAdmin ? "" : "none";
  await atualizar();
}

function sairDoSistema(){ location.reload(); }

/* ---------------- canais ---------------- */
function fmtDuracao(s){
  if (!s) return "—";
  return Math.floor(s/60) + "m" + String(Math.round(s%60)).padStart(2,"0") + "s";
}
function fmtBitrate(b){ return b ? (b/1000).toFixed(0) + " kb/s" : "—"; }

async function atualizar(){
  const {status, corpo} = await api("/canais");
  if (status !== 200) return;
  dadosCanais = corpo.canais;
  const perfil = corpo.perfil;
  const chip = $("chipPerfil");
  chip.textContent = perfil === "LAN" ? "perfil LAN · alta velocidade" : "perfil WAN115K · 115,2 kbps";
  chip.className = "chip " + (perfil === "LAN" ? "lan" : "wan");
  // no PPP de 115200 bps o cliente pode escolher uma versão ainda mais leve
  $("selQualidade").style.display = perfil === "LAN" ? "none" : "";

  const assistindo = dadosCanais.find(c => c.assistindo);
  $("avisoAgora").style.display = assistindo ? "flex" : "none";
  if (assistindo){
    $("agoraCanal").textContent = assistindo.numero + " — " + assistindo.nome;
    $("agoraMcast").textContent = assistindo.mcast;
  }

  $("gradeCanais").innerHTML = dadosCanais.map(c => `
    <article class="canal ${c.situacao === "ativo" ? "aovivo" : ""}">
      <div class="topo">
        <span class="numero">${c.numero}</span>
        <h3>${c.nome}</h3>
        <span class="pil ${c.situacao}">${c.situacao === "ativo" ? "AO VIVO" : c.situacao}</span>
      </div>
      <p class="desc">${c.descricao || ""}</p>
      ${c.video ? `<div class="meta">
        <div><span>título</span><br>${c.video.titulo || "—"}</div>
        <div><span>duração</span><br>${fmtDuracao(c.video.duracao_s)}</div>
        <div><span>resolução</span><br>${c.video.resolucao || "—"}</div>
        <div><span>bitrate</span><br>${fmtBitrate(c.video.bitrate_bps)}</div>
        <div><span>vídeo/áudio</span><br>${c.video.codec_video || "—"} / ${c.video.codec_audio || "—"}</div>
        <div><span>tamanho</span><br>${c.video.tamanho_mb ? c.video.tamanho_mb + " MB" : "—"}</div>
      </div>` : `<div class="meta"><div><span>sem vídeo vinculado</span></div></div>`}
      <div class="rodape">
        <span class="esp">👁 ${c.espectadores} assistindo</span>
        ${c.assistindo
          ? `<button class="perigo" onclick="deixarCanal(${c.numero})">sair</button>`
          : `<button class="primario" onclick="assistirCanal(${c.numero})"
               ${c.situacao === "indisponivel" ? "disabled style='opacity:.4'" : ""}>▶ assistir</button>`}
      </div>
      <div class="mcast">${c.mcast}</div>
    </article>`).join("");

  if (souAdmin) atualizarAdmin();
}

async function assistirCanal(n){
  const {status, corpo} = await api(`/canais/${n}/assistir`, {method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({qualidade: $("selQualidade").value})});
  if (status !== 200){ toast(corpo.erro || "não foi possível assistir", true); return; }
  const blob = new Blob([corpo.playlist], {type: "audio/x-mpegurl"});
  const a = Object.assign(document.createElement("a"),
                          {href: URL.createObjectURL(blob), download: `canal${n}.m3u`});
  a.click();
  const extra = corpo.qualidade && corpo.qualidade !== "original" ? ` · qualidade ${corpo.qualidade}` : "";
  toast(`Canal ${n} sintonizado${extra} — abra o .m3u no VLC (${corpo.mcast})`);
  atualizar();
}

async function deixarCanal(n){
  await api(`/canais/${n}/sair`, {method: "POST"});
  toast(`Você saiu do canal ${n}`);
  atualizar();
}

async function baixarPlaylist(){
  const r = await fetch("/api/playlist.m3u", {headers: {Authorization: "Bearer " + token}});
  const blob = new Blob([await r.text()], {type: "audio/x-mpegurl"});
  const a = Object.assign(document.createElement("a"),
                          {href: URL.createObjectURL(blob), download: "iptv-grupo4.m3u"});
  a.click();
}

/* ---------------- admin ---------------- */
function alternarAdmin(){
  const a = $("admin");
  a.style.display = a.style.display === "block" ? "none" : "block";
  if (a.style.display === "block") atualizarAdmin();
}
function abrirAba(ev, id){
  document.querySelectorAll("#abas button").forEach(b => b.classList.remove("ativa"));
  document.querySelectorAll(".aba").forEach(a => a.classList.remove("ativa"));
  ev.target.classList.add("ativa");
  $(id).classList.add("ativa");
}

async function criarCanal(){
  const {status, corpo} = await api("/canais", {method: "POST",
    headers: {"Content-Type": "application/json"},
    body: JSON.stringify({numero: +$("novoNumero").value, nome: $("novoNome").value,
                          descricao: $("novaDescricao").value})});
  status === 201 ? toast("canal cadastrado") : toast(corpo.erro || "erro", true);
  atualizar();
}
async function removerCanal(n){
  if (!confirm(`Remover o canal ${n}?`)) return;
  await api(`/canais/${n}`, {method: "DELETE"});
  toast(`canal ${n} removido`);
  atualizar();
}
async function removerVideo(n){
  if (!confirm(`Remover o vídeo do canal ${n}?`)) return;
  await api(`/videos/${n}`, {method: "DELETE"});
  toast(`vídeo do canal ${n} removido`);
  atualizar();
}

async function enviarVideo(){
  const arq = $("videoArquivo").files[0];
  if (!arq){ toast("escolha um arquivo de vídeo", true); return; }
  const dados = new FormData();
  dados.append("arquivo", arq);
  dados.append("canal", $("videoCanal").value);
  dados.append("titulo", $("videoTitulo").value);
  $("statusUpload").textContent = "enviando e convertendo para versão leve (ffmpeg)… aguarde";
  const {status, corpo} = await api("/videos", {method: "POST", body: dados});
  $("statusUpload").textContent = "";
  status === 201
    ? toast(`vídeo "${corpo.titulo}" vinculado ao canal ${corpo.canal}`)
    : toast(corpo.erro || "falha no upload", true);
  atualizar();
}

async function atualizarAdmin(){
  $("tabelaCanais").innerHTML =
    "<tr><th>nº</th><th>nome</th><th>descrição</th><th></th></tr>" +
    dadosCanais.map(c => `<tr><td>${c.numero}</td><td>${c.nome}</td><td>${c.descricao||""}</td>
      <td><button class="perigo" onclick="removerCanal(${c.numero})">remover</button></td></tr>`).join("");

  $("videoCanal").innerHTML =
    dadosCanais.map(c => `<option value="${c.numero}">canal ${c.numero} — ${c.nome}</option>`).join("");

  $("tabelaVideos").innerHTML =
    "<tr><th>canal</th><th>título</th><th>resolução</th><th>duração</th><th>bitrate</th><th></th></tr>" +
    dadosCanais.filter(c => c.video).map(c => `<tr><td>${c.numero}</td>
      <td>${c.video.titulo||"—"}</td><td>${c.video.resolucao||"—"}</td>
      <td>${fmtDuracao(c.video.duracao_s)}</td><td>${fmtBitrate(c.video.bitrate_bps)}</td>
      <td><button class="perigo" onclick="removerVideo(${c.numero})">remover</button></td></tr>`).join("");

  const {status, corpo} = await api("/admin/painel");
  if (status !== 200) return;
  $("barraWan").style.width = corpo.wan.ocupacao_estimada;
  $("textoWan").textContent = corpo.wan.ocupada
    ? `ocupada pelo canal ${corpo.wan.canal} (qualidade ${corpo.wan.qualidade}) — vídeo a ${fmtBitrate(corpo.wan.bitrate_video_bps)} (${corpo.wan.ocupacao_estimada} do enlace)`
    : "livre — nenhum fluxo WAN115K ativo";
  $("tabelaSessoes").innerHTML =
    "<tr><th>usuário</th><th>canal</th><th>perfil</th><th>desde</th></tr>" +
    (corpo.usuarios_conectados.map(s => `<tr><td>${s.login}</td><td>${s.canal}</td>
       <td>${s.perfil}</td><td>${new Date(s.desde*1000).toLocaleTimeString()}</td></tr>`).join("")
     || "<tr><td colspan=4>ninguém conectado</td></tr>");
  $("tabelaFluxos").innerHTML =
    "<tr><th>canal</th><th>perfil</th><th>endereço mcast</th><th>pid</th></tr>" +
    (corpo.fluxos_multicast.map(f => `<tr><td>${f.canal}</td><td>${f.perfil}</td>
       <td>${f.mcast}</td><td>${f.pid}</td></tr>`).join("")
     || "<tr><td colspan=4>nenhum fluxo ativo</td></tr>");
  $("preVlc").textContent = corpo.processos_vlc.join("\n") || "(nenhum processo VLC)";
}

setInterval(() => token && atualizar(), 5000);
</script>
</html>
HTML

# ---------- certificado + virtual hosts (API Gateway HTTP/HTTPS) ----------
[ -f /etc/ssl/certs/r1.pem ] || sudo openssl req -new -x509 -days 365 -nodes -subj "/CN=r1.grupo4.unb" \
  -out /etc/ssl/certs/r1.pem -keyout /etc/ssl/private/r1.key 2>/dev/null

sudo tee /etc/apache2/sites-available/miniiptv.conf >/dev/null <<'EOF'
<VirtualHost *:80>
    ServerName r1.grupo4.unb
    DocumentRoot /var/www/html
    ProxyPreserveHost On
    ProxyPass        /api http://172.16.0.2:8000/api
    ProxyPassReverse /api http://172.16.0.2:8000/api
</VirtualHost>
EOF

sudo tee /etc/apache2/sites-available/miniiptv-ssl.conf >/dev/null <<'EOF'
<VirtualHost *:443>
    ServerName r1.grupo4.unb
    SSLEngine on
    SSLCertificateFile /etc/ssl/certs/r1.pem
    SSLCertificateKeyFile /etc/ssl/private/r1.key
    DocumentRoot /var/www/html
    ProxyPreserveHost On
    ProxyPass        /api http://172.16.0.2:8000/api
    ProxyPassReverse /api http://172.16.0.2:8000/api
</VirtualHost>
EOF

sudo a2dissite 000-default >/dev/null 2>&1 || true
sudo a2ensite miniiptv miniiptv-ssl >/dev/null
sudo apache2ctl configtest
sudo systemctl restart apache2

echo; echo "=== Teste ==="
curl -s http://localhost/ | head -1
echo "Nos clientes: https://r1.grupo4.unb/iptv.html (aceite o certificado)"
