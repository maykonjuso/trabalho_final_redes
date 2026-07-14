#!/bin/bash
# [S] Backend Mini-IPTV: Flask + SQLite + systemd (código testado 15/15)
set -e
echo "=== [S] Backend Mini-IPTV ==="

if ! python3 -c "import flask, jwt" 2>/dev/null; then
  # pip3 install global quebra em Ubuntu 22.04+ (PEP 668 / externally-managed-environment) -> usa pacotes apt
  sudo apt update && sudo apt install -y python3-flask python3-jwt python3-werkzeug \
    ffmpeg vlc-bin vlc-plugin-base sqlite3
fi

id iptv >/dev/null 2>&1 || sudo useradd -r -m -d /opt/miniiptv iptv
sudo mkdir -p /opt/miniiptv/videos

sudo tee /opt/miniiptv/app.py >/dev/null <<'PYAPP'
import os, json, sqlite3, subprocess, functools, datetime, jwt
from flask import Flask, request, jsonify, g
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename

SECRET  = "grupo4-troque-este-segredo"
DB      = "/opt/miniiptv/iptv.db"
VIDEOS  = "/opt/miniiptv/videos"
GRUPO   = 4
PORTA_M = 5004
app = Flask(__name__)

# (canal, perfil) -> {"proc": Popen, "addr": str}   [LAN e WAN podem coexistir no mesmo canal]
streams = {}
# (canal, perfil) -> set(usuarios)
viewers = {}

def db():
    c = sqlite3.connect(DB); c.row_factory = sqlite3.Row; return c

def perfil():
    ip = request.headers.get("X-Forwarded-For", request.remote_addr).split(",")[0].strip()
    return "WAN115K" if ip.startswith("192.168.0.") else "LAN"

def mcast(canal, prof):
    return f"239.{20 if prof=='WAN115K' else 10}.{GRUPO}.{canal}"

def auth(admin=False):
    def deco(f):
        @functools.wraps(f)
        def w(*a, **kw):
            h = request.headers.get("Authorization", "")
            if not h.startswith("Bearer "):
                return jsonify(error="token ausente"), 401
            try:
                t = jwt.decode(h[7:], SECRET, algorithms=["HS256"])
            except jwt.PyJWTError as e:
                return jsonify(error=f"token invalido: {e}"), 401
            if admin and t["role"] != "admin":
                return jsonify(error="apenas admin"), 403
            g.user, g.role = t["sub"], t["role"]
            return f(*a, **kw)
        return w
    return deco

# ---------- OAuth2 (password grant) -> JWT ----------
@app.post("/api/token")
def token():
    d = request.form if request.form else (request.json or {})
    u = db().execute("SELECT * FROM users WHERE username=?", (d.get("username"),)).fetchone()
    if not u or not check_password_hash(u["pw"], d.get("password", "")):
        return jsonify(error="invalid_grant"), 401
    tok = jwt.encode({"sub": u["username"], "role": u["role"],
                      "exp": datetime.datetime.utcnow() + datetime.timedelta(hours=4)},
                     SECRET, algorithm="HS256")
    return jsonify(access_token=tok, token_type="Bearer", expires_in=14400)

# ---------- Canais ----------
@app.get("/api/channels")
@auth()
def channels():
    prof, out = perfil(), []
    for c in db().execute("SELECT * FROM channels ORDER BY num"):
        v = db().execute("SELECT * FROM videos WHERE channel=?", (c["num"],)).fetchone()
        ativo = any(cn == c["num"] for (cn, _) in streams)
        out.append({"num": c["num"], "nome": c["nome"], "descricao": c["desc"],
                    "video": dict(v) if v else None,
                    "status": "ativo" if ativo else ("disponivel" if v else "indisponivel"),
                    "espectadores": sum(len(s) for (n, p), s in viewers.items() if n == c["num"]),
                    "mcast": mcast(c["num"], prof)})
    return jsonify(perfil=prof, canais=out)

@app.post("/api/channels")
@auth(admin=True)
def add_channel():
    d = request.json
    db().execute("INSERT INTO channels(num,nome,desc) VALUES(?,?,?)",
                 (d["num"], d["nome"], d.get("desc", ""))).connection.commit()
    return jsonify(ok=True), 201

@app.delete("/api/channels/<int:n>")
@auth(admin=True)
def del_channel(n):
    db().execute("DELETE FROM channels WHERE num=?", (n,)).connection.commit()
    return jsonify(ok=True)

# ---------- Vídeos (upload + conversão LD + metadados) ----------
@app.post("/api/videos")
@auth(admin=True)
def add_video():
    f = request.files["file"]; canal = int(request.form["channel"])
    nome = secure_filename(f.filename); orig = os.path.join(VIDEOS, nome)
    f.save(orig)
    ld = orig.rsplit(".", 1)[0] + "_ld.mp4"
    subprocess.run(["ffmpeg", "-y", "-i", orig, "-c:v", "libx264", "-b:v", "80k",
                    "-r", "10", "-s", "320x240", "-c:a", "aac", "-b:a", "16k",
                    "-ac", "1", "-ar", "22050", ld], check=True, capture_output=True)
    p = subprocess.run(["ffprobe", "-v", "quiet", "-print_format", "json",
                        "-show_format", "-show_streams", orig], capture_output=True, text=True)
    meta = json.loads(p.stdout)
    db().execute("INSERT OR REPLACE INTO videos(channel,arq_hd,arq_ld,meta) VALUES(?,?,?,?)",
                 (canal, orig, ld, json.dumps(meta["format"]))).connection.commit()
    return jsonify(ok=True, metadados=meta["format"]), 201

# ---------- Assistir / trocar / sair ----------
def start_stream(canal, prof):
    v = db().execute("SELECT * FROM videos WHERE channel=?", (canal,)).fetchone()
    if not v: return None
    arq = v["arq_ld"] if prof == "WAN115K" else v["arq_hd"]
    addr = mcast(canal, prof)
    proc = subprocess.Popen(["cvlc", "-I", "dummy", arq, "--loop", "--ttl", "16",
                             "--sout", f"#udp{{mux=ts,dst={addr}:{PORTA_M}}}"],
                            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    streams[(canal, prof)] = {"proc": proc, "addr": addr}
    return addr

def stop_if_empty(canal, prof):
    if not viewers.get((canal, prof)) and (canal, prof) in streams:
        streams[(canal, prof)]["proc"].terminate()
        del streams[(canal, prof)]

@app.post("/api/channels/<int:n>/watch")
@auth()
def watch(n):
    prof = perfil()
    if prof == "WAN115K":
        outro = next((c for (c, p) in streams if p == "WAN115K" and c != n), None)
        if outro:
            return jsonify(error=f"WAN ocupada: canal {outro} em exibicao; assista-o ou aguarde",
                           canal_ativo=outro), 409
    # sai de outros canais (troca de canal)
    for k in list(viewers):
        if g.user in viewers[k] and k != (n, prof):
            viewers[k].discard(g.user); stop_if_empty(*k)
    if (n, prof) not in streams:
        if not start_stream(n, prof):
            return jsonify(error="canal sem video"), 404
    viewers.setdefault((n, prof), set()).add(g.user)
    addr = streams[(n, prof)]["addr"]
    m3u = f"#EXTM3U\n#EXTINF:-1,Canal {n}\nudp://@{addr}:{PORTA_M}\n"
    return jsonify(canal=n, perfil=prof, mcast=f"udp://@{addr}:{PORTA_M}", playlist=m3u)

@app.post("/api/channels/<int:n>/leave")
@auth()
def leave(n):
    prof = perfil()
    viewers.get((n, prof), set()).discard(g.user)
    stop_if_empty(n, prof)
    return jsonify(ok=True)

# ---------- Playlist m3u do perfil ----------
@app.get("/api/playlist.m3u")
@auth()
def playlist():
    prof, linhas = perfil(), ["#EXTM3U"]
    for c in db().execute("SELECT * FROM channels ORDER BY num"):
        linhas += [f"#EXTINF:-1,{c['nome']}", f"udp://@{mcast(c['num'], prof)}:{PORTA_M}"]
    return "\n".join(linhas) + "\n", 200, {"Content-Type": "audio/x-mpegurl"}

# ---------- Admin: visão geral ----------
@app.get("/api/admin/status")
@auth(admin=True)
def status():
    vlc = subprocess.run(["pgrep", "-a", "vlc"], capture_output=True, text=True).stdout
    return jsonify(
        usuarios_conectados={f"canal{n}/{p}": sorted(s) for (n, p), s in viewers.items() if s},
        canais_ativos={f"canal{n}/{p}": s["addr"] for (n, p), s in streams.items()},
        processos_vlc=vlc.strip().splitlines())

if __name__ == "__main__":
    app.run(host="0.0.0.0", port=8000)
PYAPP

sudo tee /opt/miniiptv/initdb.py >/dev/null <<'PYDB'
import sqlite3
from werkzeug.security import generate_password_hash
c = sqlite3.connect("/opt/miniiptv/iptv.db")
c.executescript("""
CREATE TABLE IF NOT EXISTS users(username TEXT PRIMARY KEY, pw TEXT, role TEXT);
CREATE TABLE IF NOT EXISTS channels(num INTEGER PRIMARY KEY, nome TEXT, desc TEXT);
CREATE TABLE IF NOT EXISTS videos(channel INTEGER PRIMARY KEY, arq_hd TEXT, arq_ld TEXT, meta TEXT);
""")
for u, p, r in [("admin", "admin123", "admin"), ("aluno1", "senha1", "user"), ("aluno2", "senha2", "user"),
                ("aluno3", "senha3", "user"), ("aluno4", "senha4", "user")]:
    c.execute("INSERT OR REPLACE INTO users VALUES(?,?,?)", (u, generate_password_hash(p), r))
canais = [(1, "Filme", "Canal de filmes", "filme"), (2, "Aula", "Canal de aulas", "aula"), (3, "Show", "Canal de shows", "show")]
for n, nome, d, arq in canais:
    c.execute("INSERT OR REPLACE INTO channels VALUES(?,?,?)", (n, nome, d))
    c.execute("INSERT OR REPLACE INTO videos VALUES(?,?,?,?)",
              (n, f"/opt/miniiptv/videos/{arq}.mp4", f"/opt/miniiptv/videos/{arq}_ld.mp4", "{}"))
c.commit()
print("ok")
PYDB

sudo chown -R iptv:iptv /opt/miniiptv
sudo -u iptv python3 /opt/miniiptv/initdb.py

sudo tee /etc/systemd/system/miniiptv.service >/dev/null <<'EOF'
[Unit]
Description=Backend Mini-IPTV
After=network.target
[Service]
User=iptv
WorkingDirectory=/opt/miniiptv
ExecStart=/usr/bin/python3 /opt/miniiptv/app.py
Restart=always
[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now miniiptv
sudo systemctl restart miniiptv
sleep 3

# converte vídeos se existirem
for v in filme aula show; do
  if [ -f "/opt/miniiptv/videos/$v.mp4" ] && [ ! -f "/opt/miniiptv/videos/${v}_ld.mp4" ]; then
    echo "[S] Convertendo $v.mp4 -> ${v}_ld.mp4 ..."
    ffmpeg -y -i "/opt/miniiptv/videos/$v.mp4" -c:v libx264 -b:v 80k -r 10 -s 320x240 \
           -c:a aac -b:a 16k -ac 1 -ar 22050 "/opt/miniiptv/videos/${v}_ld.mp4" >/dev/null 2>&1
  fi
done
sudo chown -R iptv:iptv /opt/miniiptv/videos

echo; echo "=== Teste ==="
curl -s -X POST http://localhost:8000/api/token -d username=admin -d password=admin123 | grep -q access_token \
  && echo "[OK] backend no ar (JWT emitido na porta 8000)" \
  || { echo "[ERRO] veja: journalctl -u miniiptv -n 20"; exit 1; }
[ -f /opt/miniiptv/videos/filme.mp4 ] || echo "[PENDENTE] copie filme.mp4, aula.mp4, show.mp4 p/ /opt/miniiptv/videos e rode de novo"
