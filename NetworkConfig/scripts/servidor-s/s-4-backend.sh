#!/bin/bash
# [S] Backend Mini-IPTV v2: Flask + SQLite + systemd
# JWT implementado com a biblioteca padrão (hmac/base64) — sem PyJWT,
# o que elimina o erro "Object of type bytes is not JSON serializable"
# (o python3-jwt do apt é PyJWT 1.x, cujo jwt.encode() retorna bytes).
set -e
echo "=== [S] Backend Mini-IPTV v2 ==="

# ---------- pacotes (Ubuntu/Debian via apt; Fedora via dnf) ----------
if ! python3 -c "import flask" 2>/dev/null || ! command -v ffmpeg >/dev/null || ! command -v cvlc >/dev/null; then
  if command -v apt >/dev/null; then
    sudo apt update
    sudo apt install -y python3-flask python3-werkzeug ffmpeg vlc-bin vlc-plugin-base sqlite3
  else
    sudo dnf install -y python3-flask ffmpeg-free vlc-core sqlite 2>/dev/null \
      || sudo dnf install -y python3-flask ffmpeg-free vlc sqlite
  fi
fi

id iptv >/dev/null 2>&1 || sudo useradd -r -m -d /opt/miniiptv iptv
sudo mkdir -p /opt/miniiptv/videos
sudo chmod 755 /opt/miniiptv   # home criada pelo useradd vem 700 e esconde os vídeos dos testes [ -f ]

# ---------- aplicação ----------
sudo tee /opt/miniiptv/servidor.py >/dev/null <<'PYAPP'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Servidor Mini-IPTV — Grupo 6 (FRC / UnB-FGA)

Backend da aplicação de difusão de vídeos em multicast (spec seção 2.2):
  * autenticação OAuth2 (password grant) emitindo JWT HS256;
  * administração de canais e vídeos (upload, conversão via ffmpeg,
    metadados via ffprobe);
  * difusão multicast sob demanda (VLC), encerrada quando não há
    espectadores;
  * perfis de cliente: LAN (qualidade original, canais simultâneos) e
    WAN115K (versão leve, um único canal por vez no enlace de 115200 bps);
  * qualidades WAN: "leve" (80 kb/s, comando da spec), "ultra"
    (~20 kb/s totais) e "minima" (~12 kb/s totais) — o enlace PPP de
    115200 bps ainda carrega o overhead do TS/UDP/PPP, então as opções
    precisam ser bem ruins mesmo p/ transmitir sem travar no serial;
  * playlist m3u por perfil e painel administrativo.

Endereçamento multicast: 239.<perfil>.<grupo>.<canal>, porta 5004,
perfil 10 = LAN, 20 = WAN115K, grupo = 6.

Uso:  servidor.py --init   (cria/semeia o banco)
      servidor.py          (sobe a API na porta 8000)
"""
import base64
import hashlib
import hmac
import json
import os
import sqlite3
import subprocess
import sys
import threading
import time
from functools import wraps

from flask import Flask, g, jsonify, request
from werkzeug.security import check_password_hash, generate_password_hash

# ---------------------------------------------------------------- constantes
BASE          = "/opt/miniiptv"
BANCO         = os.path.join(BASE, "iptv.db")
DIR_VIDEOS    = os.path.join(BASE, "videos")
CHAVE_JWT     = "grupo6-frc-2026-troque-esta-chave"
VALIDADE_SEG  = 4 * 3600
GRUPO         = 6
PORTA_MCAST   = 5004
PERFIL_BYTE   = {"LAN": 10, "WAN115K": 20}
CAPACIDADE_WAN = 115200  # bps do enlace PPP

# Presets de conversão p/ clientes WAN115K. "leve" é o comando da Obs1 da
# spec; "ultra" é agressiva de propósito: o cabo serial de 115200 bps ainda
# perde banda com o overhead TS/UDP/PPP, então o alvo real útil é ~20 kb/s
# (vídeo 12k @ 5 fps 160x120 + áudio 8k mono 11 kHz).
PRESETS_WAN = {
    "leve":   ["-b:v", "80k", "-r", "10", "-s", "320x240", "-b:a", "16k", "-ar", "22050"],
    "ultra":  ["-b:v", "12k", "-r", "5",  "-s", "160x120", "-b:a", "8k",  "-ar", "11025"],
    "minima": ["-b:v", "6k",  "-r", "3",  "-s", "128x96",  "-b:a", "6k",  "-ar", "8000"],
}
COLUNA_QUALIDADE = {"leve": "arquivo_ld", "ultra": "arquivo_uld", "minima": "arquivo_min"}

app = Flask(__name__)

# ------------------------------------------------------------------- banco
def abrir_banco():
    con = sqlite3.connect(BANCO, timeout=15)
    con.row_factory = sqlite3.Row
    con.execute("PRAGMA journal_mode=WAL")
    con.execute("PRAGMA foreign_keys=ON")
    return con

def banco():
    """Uma conexão por requisição, fechada no teardown — evita conexões
    penduradas segurando trancas do SQLite ('database is locked')."""
    if "banco" not in g:
        g.banco = abrir_banco()
    return g.banco

@app.teardown_appcontext
def fechar_banco(_exc):
    con = g.pop("banco", None)
    if con is not None:
        con.close()  # fecha e desfaz qualquer transação pendente

ESQUEMA = """
CREATE TABLE IF NOT EXISTS usuarios(
    login  TEXT PRIMARY KEY,
    senha  TEXT NOT NULL,
    papel  TEXT NOT NULL DEFAULT 'user'
);
CREATE TABLE IF NOT EXISTS canais(
    numero    INTEGER PRIMARY KEY,
    nome      TEXT NOT NULL,
    descricao TEXT DEFAULT ''
);
CREATE TABLE IF NOT EXISTS videos(
    canal       INTEGER PRIMARY KEY REFERENCES canais(numero) ON DELETE CASCADE,
    titulo      TEXT,
    arquivo_hd  TEXT,
    arquivo_ld  TEXT,
    arquivo_uld TEXT,
    arquivo_min TEXT,
    duracao_s   REAL,
    resolucao   TEXT,
    bitrate_bps INTEGER,
    codec_video TEXT,
    codec_audio TEXT,
    tamanho_mb  REAL
);
CREATE TABLE IF NOT EXISTS sessoes(
    login  TEXT PRIMARY KEY,
    canal  INTEGER NOT NULL,
    perfil TEXT NOT NULL,
    desde  INTEGER NOT NULL
);
"""

def garantir_esquema(con):
    # migração do banco da app v1: a tabela videos usava a coluna "channel";
    # recria no formato novo (os vídeos são recadastrados pelo --init/upload)
    if con.execute("SELECT 1 FROM sqlite_master WHERE type='table' AND name='videos'").fetchone():
        colunas = {c[1] for c in con.execute("PRAGMA table_info(videos)")}
        if "canal" not in colunas:
            con.execute("DROP TABLE videos")
    con.execute("DROP TABLE IF EXISTS users")     # tabelas da app v1
    con.execute("DROP TABLE IF EXISTS channels")
    con.executescript(ESQUEMA)
    for coluna in ("arquivo_uld", "arquivo_min"):  # bancos criados antes das qualidades extras
        try:
            con.execute(f"ALTER TABLE videos ADD COLUMN {coluna} TEXT")
        except sqlite3.OperationalError:
            pass
    con.commit()

# ------------------------------------------------------- JWT (stdlib apenas)
def _b64url(dados: bytes) -> str:
    return base64.urlsafe_b64encode(dados).rstrip(b"=").decode("ascii")

def _b64url_dec(txt: str) -> bytes:
    return base64.urlsafe_b64decode(txt + "=" * (-len(txt) % 4))

def _assinar(cab_corpo: str) -> str:
    mac = hmac.new(CHAVE_JWT.encode(), cab_corpo.encode(), hashlib.sha256)
    return _b64url(mac.digest())

def jwt_emitir(login: str, papel: str) -> str:
    cab   = _b64url(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
    corpo = _b64url(json.dumps({"sub": login, "papel": papel,
                                "exp": int(time.time()) + VALIDADE_SEG}).encode())
    return f"{cab}.{corpo}.{_assinar(f'{cab}.{corpo}')}"

def jwt_validar(token: str):
    partes = token.split(".")
    if len(partes) != 3:
        return None
    cab, corpo, assinatura = partes
    if not hmac.compare_digest(assinatura, _assinar(f"{cab}.{corpo}")):
        return None
    try:
        dados = json.loads(_b64url_dec(corpo))
    except (ValueError, json.JSONDecodeError):
        return None
    if dados.get("exp", 0) < time.time():
        return None
    return dados

def exige_login(admin=False):
    def decorador(f):
        @wraps(f)
        def protegida(*args, **kwargs):
            cabecalho = request.headers.get("Authorization", "")
            if not cabecalho.startswith("Bearer "):
                return jsonify(erro="token ausente"), 401
            dados = jwt_validar(cabecalho[7:])
            if not dados:
                return jsonify(erro="token inválido ou expirado"), 401
            if admin and dados["papel"] != "admin":
                return jsonify(erro="apenas administradores"), 403
            g.login, g.papel = dados["sub"], dados["papel"]
            return f(*args, **kwargs)
        return protegida
    return decorador

# ------------------------------------------------------------ perfil/mcast
def perfil_do_cliente() -> str:
    """LAN #2 (192.168.0.0/24, atrás da WAN de 115200 bps) => WAN115K."""
    ip = request.headers.get("X-Forwarded-For", request.remote_addr or "")
    ip = ip.split(",")[0].strip()
    return "WAN115K" if ip.startswith("192.168.0.") else "LAN"

def endereco_mcast(canal: int, perfil: str) -> str:
    return f"239.{PERFIL_BYTE[perfil]}.{GRUPO}.{canal}"

# --------------------------------------------------------- ffmpeg / ffprobe
def codec_ld_disponivel() -> str:
    """libx264 é o pedido na spec; cai para alternativas se o build local
    do ffmpeg não o incluir (ex.: ffmpeg-free do Fedora)."""
    try:
        saida = subprocess.run(["ffmpeg", "-hide_banner", "-encoders"],
                               capture_output=True, text=True).stdout
    except FileNotFoundError:
        return "libx264"
    for codec in ("libx264", "libopenh264", "mpeg4"):
        if f" {codec} " in saida:
            return codec
    return "libx264"

def converter_wan(origem: str, destino: str, qualidade: str):
    """Gera versão compatível com o enlace WAN de 115200 bps."""
    subprocess.run(["ffmpeg", "-y", "-i", origem,
                    "-c:v", codec_ld_disponivel(), *PRESETS_WAN[qualidade],
                    "-c:a", "aac", "-ac", "1", destino],
                   check=True, capture_output=True)

def extrair_metadados(arquivo: str) -> dict:
    proc = subprocess.run(["ffprobe", "-v", "quiet", "-print_format", "json",
                           "-show_format", "-show_streams", arquivo],
                          capture_output=True, text=True)
    info = json.loads(proc.stdout or "{}")
    fmt = info.get("format", {})
    video = next((s for s in info.get("streams", []) if s.get("codec_type") == "video"), {})
    audio = next((s for s in info.get("streams", []) if s.get("codec_type") == "audio"), {})
    largura, altura = video.get("width"), video.get("height")
    return {
        "duracao_s":   round(float(fmt.get("duration", 0) or 0), 1),
        "bitrate_bps": int(fmt.get("bit_rate", 0) or 0),
        "resolucao":   f"{largura}x{altura}" if largura and altura else None,
        "codec_video": video.get("codec_name"),
        "codec_audio": audio.get("codec_name"),
        "tamanho_mb":  round(int(fmt.get("size", 0) or 0) / 1048576, 2),
    }

# ------------------------------------------------- gerência de transmissões
class Transmissoes:
    """Fluxos VLC ativos, indexados por (canal, perfil).

    A regra da spec: a difusão só existe enquanto houver espectador
    interessado (tabela sessoes); LAN e WAN115K de um mesmo canal são
    fluxos independentes (endereços multicast distintos). A qualidade
    WAN é decidida pelo primeiro espectador que liga o fluxo."""

    def __init__(self):
        self._fluxos = {}  # (canal, perfil) -> {proc, arquivo, qualidade}
        self.trava = threading.Lock()

    def info(self, canal, perfil):
        fluxo = self._fluxos.get((canal, perfil))
        if fluxo and fluxo["proc"].poll() is None:
            return fluxo
        return None

    def iniciar(self, canal, perfil, arquivo, qualidade):
        destino = f"{endereco_mcast(canal, perfil)}:{PORTA_MCAST}"
        proc = subprocess.Popen(
            ["cvlc", "-I", "dummy", arquivo, "--loop", "--ttl", "16",
             "--sout", f"#udp{{mux=ts,dst={destino}}}"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self._fluxos[(canal, perfil)] = {"proc": proc, "arquivo": arquivo,
                                         "qualidade": qualidade}

    def parar(self, canal, perfil):
        fluxo = self._fluxos.pop((canal, perfil), None)
        if fluxo and fluxo["proc"].poll() is None:
            fluxo["proc"].terminate()

    def listar(self):
        return {chave: fluxo for chave, fluxo in self._fluxos.items()
                if fluxo["proc"].poll() is None}

transmissoes = Transmissoes()

def encerrar_se_vazio(con, canal, perfil):
    resto = con.execute("SELECT COUNT(*) c FROM sessoes WHERE canal=? AND perfil=?",
                        (canal, perfil)).fetchone()["c"]
    if resto == 0:
        transmissoes.parar(canal, perfil)

def arquivo_do_perfil(video, perfil, qualidade="leve"):
    """LAN => original; WAN115K => leve/ultra (cai p/ leve se ultra faltar)."""
    if perfil == "LAN":
        arq = video["arquivo_hd"]
    else:
        arq = video[COLUNA_QUALIDADE.get(qualidade, "arquivo_ld")] or video["arquivo_ld"]
    return arq if arq and os.path.isfile(arq) else None

def qualidades_disponiveis(video):
    return [q for q, coluna in COLUNA_QUALIDADE.items()
            if video[coluna] and os.path.isfile(video[coluna])]

# =========================================================== autenticação
@app.route("/api/auth/token", methods=["POST"])
def emitir_token():
    """OAuth2 password grant: login+senha => JWT de acesso."""
    dados = request.form if request.form else (request.get_json(silent=True) or {})
    usuario = banco().execute("SELECT * FROM usuarios WHERE login=?",
                              (dados.get("username"),)).fetchone()
    if not usuario or not check_password_hash(usuario["senha"], dados.get("password", "")):
        return jsonify(erro="invalid_grant", detalhe="login ou senha incorretos"), 401
    return jsonify(access_token=jwt_emitir(usuario["login"], usuario["papel"]),
                   token_type="Bearer", expires_in=VALIDADE_SEG,
                   papel=usuario["papel"])

@app.route("/api/auth/perfil", methods=["GET"])
@exige_login()
def quem_sou():
    return jsonify(login=g.login, papel=g.papel, perfil_rede=perfil_do_cliente())

# ================================================================= canais
@app.route("/api/canais", methods=["GET"])
@exige_login()
def listar_canais():
    perfil = perfil_do_cliente()
    con = banco()
    saida = []
    for canal in con.execute("SELECT * FROM canais ORDER BY numero"):
        n = canal["numero"]
        video = con.execute("SELECT * FROM videos WHERE canal=?", (n,)).fetchone()
        espectadores = con.execute(
            "SELECT COUNT(*) c FROM sessoes WHERE canal=?", (n,)).fetchone()["c"]
        assistindo = con.execute(
            "SELECT 1 FROM sessoes WHERE login=? AND canal=?", (g.login, n)).fetchone()
        if espectadores > 0:
            situacao = "ativo"
        elif video and arquivo_do_perfil(video, perfil):
            situacao = "disponivel"
        else:
            situacao = "indisponivel"
        saida.append({
            "numero": n, "nome": canal["nome"], "descricao": canal["descricao"],
            "situacao": situacao, "espectadores": espectadores,
            "assistindo": bool(assistindo),
            "mcast": f"udp://@{endereco_mcast(n, perfil)}:{PORTA_MCAST}",
            "qualidades_wan": qualidades_disponiveis(video) if video else [],
            "video": dict(video) if video else None,
        })
    return jsonify(perfil=perfil, canais=saida)

@app.route("/api/canais", methods=["POST"])
@exige_login(admin=True)
def criar_canal():
    dados = request.get_json(silent=True) or {}
    try:
        numero = int(dados["numero"])
        nome = str(dados["nome"]).strip()
        assert 1 <= numero <= 254 and nome
    except (KeyError, ValueError, AssertionError):
        return jsonify(erro="informe numero (1-254) e nome"), 400
    con = banco()
    try:
        con.execute("INSERT INTO canais(numero,nome,descricao) VALUES(?,?,?)",
                    (numero, nome, dados.get("descricao", "")))
        con.commit()
    except sqlite3.IntegrityError:
        con.rollback()
        return jsonify(erro=f"canal {numero} já existe"), 409
    return jsonify(ok=True, numero=numero), 201

@app.route("/api/canais/<int:numero>", methods=["DELETE"])
@exige_login(admin=True)
def remover_canal(numero):
    con = banco()
    with transmissoes.trava:
        for perfil in PERFIL_BYTE:
            transmissoes.parar(numero, perfil)
        con.execute("DELETE FROM sessoes WHERE canal=?", (numero,))
        apagados = con.execute("DELETE FROM canais WHERE numero=?", (numero,)).rowcount
        con.commit()
    if not apagados:
        return jsonify(erro="canal inexistente"), 404
    return jsonify(ok=True)

# ===================================================== assistir/trocar/sair
@app.route("/api/canais/<int:numero>/assistir", methods=["POST"])
@exige_login()
def assistir(numero):
    perfil = perfil_do_cliente()
    dados = request.get_json(silent=True) or {}
    qualidade = dados.get("qualidade", request.args.get("qualidade", "leve"))
    if qualidade not in PRESETS_WAN:
        qualidade = "leve"
    con = banco()
    if not con.execute("SELECT 1 FROM canais WHERE numero=?", (numero,)).fetchone():
        return jsonify(erro="canal inexistente"), 404
    video = con.execute("SELECT * FROM videos WHERE canal=?", (numero,)).fetchone()
    if not video or not arquivo_do_perfil(video, perfil, qualidade):
        return jsonify(erro="canal sem vídeo cadastrado para este perfil"), 404

    with transmissoes.trava:
        # Regra WAN115K: um único canal por vez em toda a LAN #2.
        if perfil == "WAN115K":
            ocupado = con.execute(
                "SELECT canal FROM sessoes WHERE perfil='WAN115K' AND canal!=? "
                "AND login!=? LIMIT 1", (numero, g.login)).fetchone()
            if ocupado:
                return jsonify(erro=f"enlace WAN ocupado: canal {ocupado['canal']} "
                                    "em exibição — assista-o ou aguarde liberar",
                               canal_ativo=ocupado["canal"]), 409
        # troca de canal: encerra a sessão anterior deste usuário
        anterior = con.execute("SELECT * FROM sessoes WHERE login=?", (g.login,)).fetchone()
        con.execute("INSERT OR REPLACE INTO sessoes VALUES(?,?,?,?)",
                    (g.login, numero, perfil, int(time.time())))
        con.commit()
        if anterior and (anterior["canal"], anterior["perfil"]) != (numero, perfil):
            encerrar_se_vazio(con, anterior["canal"], anterior["perfil"])
        fluxo = transmissoes.info(numero, perfil)
        if not fluxo:
            arquivo = arquivo_do_perfil(video, perfil, qualidade)
            transmissoes.iniciar(numero, perfil, arquivo,
                                 qualidade if perfil == "WAN115K" else "original")
            fluxo = transmissoes.info(numero, perfil)

    destino = f"{endereco_mcast(numero, perfil)}:{PORTA_MCAST}"
    return jsonify(canal=numero, perfil=perfil, mcast=f"udp://@{destino}",
                   qualidade=fluxo["qualidade"] if fluxo else None,
                   playlist=f"#EXTM3U\n#EXTINF:-1,Canal {numero}\nudp://@{destino}\n")

@app.route("/api/canais/<int:numero>/sair", methods=["POST"])
@exige_login()
def sair(numero):
    con = banco()
    with transmissoes.trava:
        con.execute("DELETE FROM sessoes WHERE login=? AND canal=?", (g.login, numero))
        con.commit()
        for perfil in PERFIL_BYTE:
            encerrar_se_vazio(con, numero, perfil)
    return jsonify(ok=True)

# ================================================================== vídeos
@app.route("/api/videos", methods=["POST"])
@exige_login(admin=True)
def cadastrar_video():
    """Upload + conversões WAN (leve e ultra) + metadados + vínculo ao canal."""
    arquivo = request.files.get("arquivo")
    try:
        canal = int(request.form["canal"])
    except (KeyError, ValueError):
        return jsonify(erro="informe o campo canal"), 400
    if not arquivo or not arquivo.filename:
        return jsonify(erro="envie o campo arquivo (multipart)"), 400
    con = banco()
    if not con.execute("SELECT 1 FROM canais WHERE numero=?", (canal,)).fetchone():
        return jsonify(erro="canal inexistente — cadastre-o antes"), 404

    extensao = os.path.splitext(arquivo.filename)[1].lower() or ".mp4"
    caminho_hd  = os.path.join(DIR_VIDEOS, f"canal{canal}_hd{extensao}")
    caminho_ld  = os.path.join(DIR_VIDEOS, f"canal{canal}_ld.mp4")
    caminho_uld = os.path.join(DIR_VIDEOS, f"canal{canal}_uld.mp4")
    caminho_min = os.path.join(DIR_VIDEOS, f"canal{canal}_min.mp4")
    arquivo.save(caminho_hd)
    try:
        converter_wan(caminho_hd, caminho_ld, "leve")
        converter_wan(caminho_hd, caminho_uld, "ultra")
        converter_wan(caminho_hd, caminho_min, "minima")
    except subprocess.CalledProcessError as e:
        os.unlink(caminho_hd)
        return jsonify(erro="falha na conversão ffmpeg",
                       detalhe=e.stderr.decode(errors="replace")[-400:]), 500

    meta = extrair_metadados(caminho_hd)
    titulo = request.form.get("titulo") or os.path.splitext(arquivo.filename)[0]
    con.execute("""INSERT OR REPLACE INTO videos
                   (canal,titulo,arquivo_hd,arquivo_ld,arquivo_uld,arquivo_min,
                    duracao_s,resolucao,bitrate_bps,codec_video,codec_audio,tamanho_mb)
                   VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
                (canal, titulo, caminho_hd, caminho_ld, caminho_uld, caminho_min,
                 meta["duracao_s"], meta["resolucao"], meta["bitrate_bps"],
                 meta["codec_video"], meta["codec_audio"], meta["tamanho_mb"]))
    con.commit()
    return jsonify(ok=True, canal=canal, titulo=titulo, metadados=meta), 201

@app.route("/api/videos/<int:canal>", methods=["DELETE"])
@exige_login(admin=True)
def remover_video(canal):
    con = banco()
    video = con.execute("SELECT * FROM videos WHERE canal=?", (canal,)).fetchone()
    if not video:
        return jsonify(erro="canal sem vídeo"), 404
    with transmissoes.trava:
        for perfil in PERFIL_BYTE:
            transmissoes.parar(canal, perfil)
        con.execute("DELETE FROM sessoes WHERE canal=?", (canal,))
        con.execute("DELETE FROM videos WHERE canal=?", (canal,))
        con.commit()
    for arq in (video["arquivo_hd"], video["arquivo_ld"],
                video["arquivo_uld"], video["arquivo_min"]):
        if arq and os.path.isfile(arq):
            os.unlink(arq)
    return jsonify(ok=True)

# ================================================================ playlist
@app.route("/api/playlist.m3u", methods=["GET"])
@exige_login()
def playlist_m3u():
    perfil = perfil_do_cliente()
    linhas = ["#EXTM3U"]
    for canal in banco().execute("SELECT * FROM canais ORDER BY numero"):
        linhas.append(f"#EXTINF:-1,{canal['nome']}")
        linhas.append(f"udp://@{endereco_mcast(canal['numero'], perfil)}:{PORTA_MCAST}")
    return "\n".join(linhas) + "\n", 200, {"Content-Type": "audio/x-mpegurl"}

# ============================================================ painel admin
@app.route("/api/admin/painel", methods=["GET"])
@exige_login(admin=True)
def painel():
    con = banco()
    sessoes = [dict(s) for s in con.execute(
        "SELECT login,canal,perfil,desde FROM sessoes ORDER BY canal")]
    fluxos = []
    with transmissoes.trava:
        for (canal, perfil), fluxo in transmissoes.listar().items():
            fluxos.append({"canal": canal, "perfil": perfil,
                           "pid": fluxo["proc"].pid,
                           "qualidade": fluxo["qualidade"],
                           "arquivo": fluxo["arquivo"],
                           "mcast": f"{endereco_mcast(canal, perfil)}:{PORTA_MCAST}"})
    vlc = subprocess.run(["pgrep", "-a", "vlc"], capture_output=True, text=True)
    fluxo_wan = next((f for f in fluxos if f["perfil"] == "WAN115K"), None)
    bitrate_wan = 0
    if fluxo_wan and os.path.isfile(fluxo_wan["arquivo"]):
        bitrate_wan = extrair_metadados(fluxo_wan["arquivo"])["bitrate_bps"]
    return jsonify(
        usuarios_conectados=sessoes,
        total_conectados=len(sessoes),
        fluxos_multicast=fluxos,
        processos_vlc=vlc.stdout.strip().splitlines(),
        wan={"capacidade_bps": CAPACIDADE_WAN,
             "ocupada": fluxo_wan is not None,
             "canal": fluxo_wan["canal"] if fluxo_wan else None,
             "qualidade": fluxo_wan["qualidade"] if fluxo_wan else None,
             "bitrate_video_bps": bitrate_wan,
             "ocupacao_estimada": f"{100*bitrate_wan//CAPACIDADE_WAN}%" if bitrate_wan else "0%"})

# ============================================================ inicialização
SEMENTES_USUARIOS = [("admin", "admin123", "admin"), ("aluno1", "senha1", "user"),
                     ("aluno2", "senha2", "user"), ("aluno3", "senha3", "user"),
                     ("aluno4", "senha4", "user")]
SEMENTES_CANAIS = [(1, "Filme", "Canal de filmes", "filme"),
                   (2, "Aula", "Canal de aulas", "aula"),
                   (3, "Show", "Canal de shows", "show")]

def inicializar_banco():
    con = abrir_banco()
    garantir_esquema(con)
    for login, senha, papel in SEMENTES_USUARIOS:
        con.execute("INSERT OR REPLACE INTO usuarios VALUES(?,?,?)",
                    (login, generate_password_hash(senha), papel))
    for numero, nome, descricao, base in SEMENTES_CANAIS:
        con.execute("INSERT OR IGNORE INTO canais VALUES(?,?,?)",
                    (numero, nome, descricao))
        # registra vídeos-semente já copiados p/ /opt/miniiptv/videos
        # (aceita filme.mp4 ou filme_hd.mp4; _ld/_uld são geradas pelo script)
        hd = next((c for c in (os.path.join(DIR_VIDEOS, f"{base}_hd.mp4"),
                               os.path.join(DIR_VIDEOS, f"{base}.mp4"))
                   if os.path.isfile(c)), None)
        ld  = os.path.join(DIR_VIDEOS, f"{base}_ld.mp4")
        uld = os.path.join(DIR_VIDEOS, f"{base}_uld.mp4")
        mn  = os.path.join(DIR_VIDEOS, f"{base}_min.mp4")
        if hd and os.path.isfile(ld):
            meta = extrair_metadados(hd)
            con.execute("""INSERT OR REPLACE INTO videos
                           (canal,titulo,arquivo_hd,arquivo_ld,arquivo_uld,arquivo_min,
                            duracao_s,resolucao,bitrate_bps,codec_video,codec_audio,tamanho_mb)
                           VALUES(?,?,?,?,?,?,?,?,?,?,?,?)""",
                        (numero, nome, hd, ld,
                         uld if os.path.isfile(uld) else None,
                         mn if os.path.isfile(mn) else None,
                         meta["duracao_s"], meta["resolucao"], meta["bitrate_bps"],
                         meta["codec_video"], meta["codec_audio"], meta["tamanho_mb"]))
    con.commit()
    con.close()
    print("banco inicializado:", BANCO)

if __name__ == "__main__":
    if "--init" in sys.argv:
        inicializar_banco()
    else:
        con = abrir_banco()
        garantir_esquema(con)
        con.execute("DELETE FROM sessoes")  # sessões antigas morrem com o serviço
        con.commit()
        con.close()
        app.run(host="0.0.0.0", port=8000, threaded=True)
PYAPP

# ---------- converte vídeos-semente (se existirem) e semeia o banco ----------
CODEC=$(ffmpeg -hide_banner -encoders 2>/dev/null | grep -oE ' (libx264|libopenh264|mpeg4) ' | head -1 | tr -d ' ')
CODEC=${CODEC:-libx264}
converte(){ # converte <origem> <destino> <bv> <fps> <res> <ba> <ar>
  sudo ffmpeg -y -i "$1" -c:v "$CODEC" -b:v "$3" -r "$4" -s "$5" \
              -c:a aac -b:a "$6" -ac 1 -ar "$7" "$2" >/dev/null 2>&1
}
LD_ARGS="80k 10 320x240 16k 22050"
ULD_ARGS="12k 5 160x120 8k 11025"
MIN_ARGS="6k 3 128x96 6k 8000"

# se os presets WAN mudaram desde a última execução, refaz _uld e _min
MARCA=/opt/miniiptv/videos/.preset-wan
if [ "$(sudo cat "$MARCA" 2>/dev/null)" != "$ULD_ARGS | $MIN_ARGS" ]; then
  sudo ls /opt/miniiptv/videos/*_uld.mp4 >/dev/null 2>&1 \
    && echo "[S] Presets WAN mudaram — regerando as versões _uld/_min..."
  sudo rm -f /opt/miniiptv/videos/*_uld.mp4 /opt/miniiptv/videos/*_min.mp4 \
             /opt/miniiptv/videos/.preset-uld
  echo "$ULD_ARGS | $MIN_ARGS" | sudo tee "$MARCA" >/dev/null
fi

gerar_versoes(){ # gerar_versoes <arquivo_hd> <prefixo-saida>
  local HD="$1" PRE="/opt/miniiptv/videos/$2"
  if ! sudo test -f "${PRE}_ld.mp4"; then
    echo "[S] Convertendo $(basename "$HD") -> $2_ld.mp4 ($LD_ARGS, codec $CODEC)..."
    converte "$HD" "${PRE}_ld.mp4" $LD_ARGS \
      || echo "[AVISO] conversão leve de $2 falhou — verifique o ffmpeg"
  fi
  if ! sudo test -f "${PRE}_uld.mp4"; then
    echo "[S] Convertendo $(basename "$HD") -> $2_uld.mp4 ($ULD_ARGS, ultra p/ PPP)..."
    converte "$HD" "${PRE}_uld.mp4" $ULD_ARGS \
      || echo "[AVISO] conversão ultra de $2 falhou — verifique o ffmpeg"
  fi
  if ! sudo test -f "${PRE}_min.mp4"; then
    echo "[S] Convertendo $(basename "$HD") -> $2_min.mp4 ($MIN_ARGS, mínima p/ PPP)..."
    converte "$HD" "${PRE}_min.mp4" $MIN_ARGS \
      || echo "[AVISO] conversão mínima de $2 falhou — verifique o ffmpeg"
  fi
}

# vídeos-semente (filme/aula/show copiados manualmente)
for v in filme aula show; do
  HD=""
  sudo test -f "/opt/miniiptv/videos/${v}_hd.mp4" && HD="/opt/miniiptv/videos/${v}_hd.mp4"
  [ -z "$HD" ] && sudo test -f "/opt/miniiptv/videos/${v}.mp4" && HD="/opt/miniiptv/videos/${v}.mp4"
  [ -n "$HD" ] && gerar_versoes "$HD" "$v"
done
# vídeos que entraram por upload no frontend (canalN_hd.*)
for HD in $(sudo sh -c 'ls /opt/miniiptv/videos/canal*_hd.* 2>/dev/null'); do
  PRE=$(basename "$HD"); PRE=${PRE%%_hd.*}
  gerar_versoes "$HD" "$PRE"
done

sudo chown -R iptv:iptv /opt/miniiptv

# valida o código antes de subir o serviço (pega incompatibilidade de versão do Flask etc.)
sudo python3 -m py_compile /opt/miniiptv/servidor.py \
  || { echo "[ERRO] servidor.py com erro de sintaxe"; exit 1; }
sudo -u iptv python3 -c "
import sys; sys.path.insert(0, '/opt/miniiptv')
import servidor" \
  || { echo "[ERRO] servidor.py não importa nesta máquina (veja o traceback acima)"; exit 1; }

sudo -u iptv python3 /opt/miniiptv/servidor.py --init

# ---------- serviço systemd ----------
sudo tee /etc/systemd/system/miniiptv.service >/dev/null <<'EOF'
[Unit]
Description=Backend Mini-IPTV Grupo 6
After=network.target

[Service]
User=iptv
WorkingDirectory=/opt/miniiptv
ExecStart=/usr/bin/python3 /opt/miniiptv/servidor.py
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF
sudo systemctl daemon-reload
sudo systemctl enable --now miniiptv >/dev/null 2>&1
sudo systemctl restart miniiptv
sleep 3

# ---------- autoteste ----------
echo; echo "=== Autoteste ==="
# extrai um campo de um JSON sem estourar traceback se a resposta vier vazia
campo(){ python3 -c "
import sys, json
try:
    print(json.load(sys.stdin).get('$1', ''))
except Exception:
    print('')"; }

if ! systemctl is-active --quiet miniiptv; then
  echo "[ERRO] serviço miniiptv não está ativo — últimas linhas do log:"
  sudo journalctl -u miniiptv -n 30 --no-pager
  exit 1
fi
TOKEN=$(curl -s --max-time 5 -X POST http://localhost:8000/api/auth/token \
          -d username=admin -d password=admin123 | campo access_token)
if [ -n "$TOKEN" ]; then
  echo "[OK] backend no ar — JWT emitido na porta 8000"
  N=$(curl -s --max-time 5 http://localhost:8000/api/canais \
        -H "Authorization: Bearer $TOKEN" | campo perfil)
  [ -n "$N" ] && echo "[OK] lista de canais respondendo (perfil $N)" \
              || echo "[AVISO] /api/canais não respondeu como esperado"
else
  echo "[ERRO] backend ativo mas não emitiu token — últimas linhas do log:"
  sudo journalctl -u miniiptv -n 30 --no-pager
  exit 1
fi
# reconhece vídeos já cadastrados no banco (de execuções anteriores ou upload),
# não apenas os arquivos-semente novos
NVID=$(sudo -u iptv python3 -c "
import sqlite3
print(sqlite3.connect('/opt/miniiptv/iptv.db').execute('SELECT COUNT(*) FROM videos').fetchone()[0])" 2>/dev/null || echo 0)
if [ "${NVID:-0}" -gt 0 ]; then
  echo "[OK] $NVID vídeo(s) cadastrados no banco e prontos para transmissão"
else
  echo "[PENDENTE] nenhum vídeo cadastrado — copie filme.mp4, aula.mp4, show.mp4 p/ /opt/miniiptv/videos e rode este script de novo (ou envie pelo frontend como admin)"
fi
