#!/bin/bash
# [R1] Apache: página da intranet + API Gateway (proxy reverso) HTTP e HTTPS + frontend
set -e
echo "=== [R1] WEB + API Gateway ==="

command -v apache2ctl >/dev/null || sudo apt install -y apache2
sudo a2enmod proxy proxy_http headers ssl >/dev/null

echo '<h1>Intranet Grupo 4 - Mini-IPTV</h1><p><a href="/iptv.html">Abrir Mini-IPTV</a></p>' | sudo tee /var/www/html/index.html >/dev/null

sudo tee /var/www/html/iptv.html >/dev/null <<'HTML'
<!doctype html><meta charset="utf-8"><title>Mini-IPTV Grupo 4</title>
<style>body{font-family:sans-serif;max-width:720px;margin:2em auto}li{margin:.6em 0}
button{margin-left:.5em}#log{color:#06c}</style>
<h1>Mini-IPTV — Grupo 4</h1>
<div id="login"><input id="u" placeholder="usuário"> <input id="p" type="password" placeholder="senha">
<button onclick="entrar()">Entrar</button></div>
<p id="log"></p><ul id="canais"></ul>
<script>
let tok=null;
const api=(p,opt={})=>fetch("/api"+p,{...opt,headers:{...opt.headers,
  ...(tok?{"Authorization":"Bearer "+tok}:{})}}).then(r=>r.json().then(j=>({s:r.status,j})));
async function entrar(){
  const b=new URLSearchParams({username:u.value,password:p.value});
  const {s,j}=await api("/token",{method:"POST",body:b});
  if(s!=200){log.textContent="login falhou";return}
  tok=j.access_token; login.style.display="none"; listar();
}
async function listar(){
  const {j}=await api("/channels");
  log.textContent="perfil: "+j.perfil;
  canais.innerHTML=j.canais.map(c=>`<li><b>Canal ${c.num} — ${c.nome}</b> (${c.status},
   ${c.espectadores} assistindo) ${c.descricao||""}
   <button onclick="assistir(${c.num})">Assistir</button>
   <button onclick="sair(${c.num})">Sair</button></li>`).join("");
}
async function assistir(n){
  const {s,j}=await api(`/channels/${n}/watch`,{method:"POST"});
  if(s!=200){log.textContent=j.error;return}
  log.textContent=`Canal ${n}: abra no VLC -> ${j.mcast}`;
  const b=new Blob([j.playlist],{type:"audio/x-mpegurl"});
  const a=document.createElement("a");a.href=URL.createObjectURL(b);
  a.download=`canal${n}.m3u`;a.click(); listar();
}
async function sair(n){await api(`/channels/${n}/leave`,{method:"POST"});listar()}
setInterval(()=>tok&&listar(),5000);
</script>
HTML

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
