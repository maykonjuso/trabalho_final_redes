# Mini-IPTV Multicast com Controle de Banda WAN — Grupo 6

Projeto da disciplina **FRC — Fundamentos de Redes de Computadores** (UnB/FGA).
Scripts de configuração por máquina: leve o repositório para cada PC (pendrive/git) e rode na ordem.

## Topologia

```
                [ Rede do Laboratório (Internet, Z e W) ]
                                |
                                | USB->Eth (Source NAT)
[ Host S ] -----cabo----- [ Roteador R1 ] ==serial PPP 115200== [ Roteador R2 ]
 172.16.0.2                172.16.0.1 / 10.0.0.1                 10.0.0.2 / 192.168.0.1
 DNS SMTP VLC backend      Apache proxy/API-GW, NAT, tc          DHCP, multicast
                                                                      |
                                                               [ X ]  [ Y ]  (DHCP .100-.200)
```

Multicast (grupo 6): `239.10.6.x` = perfil LAN (Z/W, vídeo HD) · `239.20.6.x` = perfil WAN115K (X/Y, vídeo leve) · porta 5004.

## Como usar

```bash
sudo bash run.sh        # menu: escolha a máquina e o script
```

Ou rode direto (os nomes têm número = ordem):

| Máquina | Ordem | Script | Faz o quê |
|---|---|---|---|
| S  | 1 | `servidor-s/s-1-lan.sh` | IP 172.16.0.2 + gateway R1 |
| R1 | 1 | `roteador-r1/r1-1-lan.sh` | IP 172.16.0.1 + uplink Lab (DHCP) |
| R2 | 1 | `roteador-r2/r2-1-lan.sh` | IP 192.168.0.1 |
| R2 | 2 | `roteador-r2/r2-2-ppp.sh` | WAN PPP (rodar ANTES do R1) |
| R1 | 2 | `roteador-r1/r1-2-ppp.sh` | WAN PPP + rota p/ LAN#2 |
| R1 | 3 | `roteador-r1/r1-3-nat.sh` | SNAT/DNAT/firewall |
| R2 | 3 | `roteador-r2/r2-3-dhcp.sh` | DHCP p/ X e Y |
| R1 | 4 | `roteador-r1/r1-4-multicast.sh` | smcroute LAN/WAN |
| R2 | 4 | `roteador-r2/r2-4-multicast.sh` | smcroute WAN->LAN#2 |
| R1 | 5 | `roteador-r1/r1-5-tc.sh` | tc 115200 bps na WAN |
| S  | 2 | `servidor-s/s-2-dns.sh` | BIND9 zona grupo6.unb |
| S  | 3 | `servidor-s/s-3-email.sh` | Postfix+Dovecot TLS (IMAP/POP3) |
| S  | 4 | `servidor-s/s-4-backend.sh` | Backend Mini-IPTV (Flask+systemd) |
| R1 | 6 | `roteador-r1/r1-6-web.sh` | Apache: intranet + API Gateway HTTP/HTTPS + frontend |
| X/Y| 1 | `cliente-x/x-1-dhcp.sh` | DHCP + DNS -> S |
| —  | — | `testes/t-1-conectividade.sh` | camada IP: pings de todos os saltos, NAT, DNS |
| —  | — | `testes/t-2-multicast.sh` | multicast fim a fim com iperf (emissor/receptor/roteador) |
| —  | — | `testes/t-3-servicos.sh` | DNS, intranet/API-Gateway HTTP+HTTPS, SMTP/IMAP/POP3, DHCP |
| —  | — | `testes/t-4-backend.sh` | bateria completa da aplicação (41 testes: JWT, perfis, WAN, upload, qualidades, painel) |
| —  | — | `testes/t-5-wan.sh` | enlace PPP: tc 115200, latência x tamanho de pacote, drops |

**Ordem recomendada no lab:** R2(1,2) → R1(1,2,3) → S(1,2,3,4) → R2(3,4) → R1(4,5,6) → X/Y(1) → testes.

**Testes:** todos os `t-*.sh` rodam em qualquer máquina — o que não se aplica ali é marcado
`[PULADO]`. O `t-4` acha a API sozinho (backend direto no S ou via gateway do R1) e, quando roda
no próprio S, confere também processos VLC, arquivos convertidos e o serviço systemd.

## Deu problema? Reset total

`sudo bash NetworkConfig/scripts/reset-maquina.sh` (ou opção **RESET** no menu) desfaz tudo que o projeto configurou naquela máquina — PPP, IPs fixos, rotas, NAT, DHCP server, multicast, tc, resolv.conf — e religa o NetworkManager, **restaurando a Internet normal do Lab**. Depois é só remontar rodando os scripts na ordem.

## Observações

- Os scripts **param o NetworkManager** antes de configurar (senão ele desfaz IP/rotas/resolv.conf).
- Todos são **idempotentes**: limpam o estado anterior antes de aplicar — rode de novo sem medo.
- Pacotes (bind9, postfix, smcroute...) são instalados pelo próprio script quando faltam — instale **enquanto a máquina ainda tem Internet** (a WAN de 115200 bps não serve para apt).
- Vídeos: copie `filme.mp4`, `aula.mp4`, `show.mp4` para `/opt/miniiptv/videos` (o s4 converte p/ as versões WAN).
- Usuários da aplicação: `admin/admin123`, `aluno1/senha1` … `aluno4/senha4`.
- **Qualidades WAN**: além da versão *leve* (80 kb/s, comando da spec), o backend gera *ultra*
  (~20 kb/s: vídeo 12k @ 5 fps 160x120 + áudio 8k) e *mínima* (~12 kb/s: vídeo 6k @ 3 fps 128x96 +
  áudio 6k). O PPP de 115200 bps perde muita banda com o overhead TS/UDP/PPP, então na prática só as
  versões bem ruins passam sem travar no cabo serial — o cliente WAN escolhe no frontend (ou via
  `POST /api/canais/<n>/assistir` com `{"qualidade":"ultra"}` / `{"qualidade":"minima"}`).
  Se os presets mudarem, o s4 apaga e regera os `_uld`/`_min` automaticamente na próxima execução.
- O JWT é gerado com `hmac`/`base64` da biblioteca padrão (sem PyJWT — o `python3-jwt` do apt é a
  versão 1.x, que retorna `bytes` e quebrava o `jsonify`).
