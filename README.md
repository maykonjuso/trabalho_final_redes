# Mini-IPTV Multicast com Controle de Banda WAN — Grupo 4

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

Multicast (grupo 4): `239.10.4.x` = perfil LAN (Z/W, vídeo HD) · `239.20.4.x` = perfil WAN115K (X/Y, vídeo leve) · porta 5004.

## Como usar

```bash
sudo bash run.sh        # menu: escolha a máquina e o script
```

Ou rode direto (os nomes têm número = ordem):

| Máquina | Ordem | Script | Faz o quê |
|---|---|---|---|
| S  | 1 | `servidor-s/s1-lan.sh` | IP 172.16.0.2 + gateway R1 |
| R1 | 1 | `roteador-r1/r1-lan.sh` | IP 172.16.0.1 + uplink Lab (DHCP) |
| R2 | 1 | `roteador-r2/r2-lan.sh` | IP 192.168.0.1 |
| R2 | 2 | `roteador-r2/r2-ppp.sh` | WAN PPP (rodar ANTES do R1) |
| R1 | 2 | `roteador-r1/r1-ppp.sh` | WAN PPP + rota p/ LAN#2 |
| R1 | 3 | `roteador-r1/r1-nat.sh` | SNAT/DNAT/firewall |
| R2 | 3 | `roteador-r2/r2-dhcp.sh` | DHCP p/ X e Y |
| R1 | 4 | `roteador-r1/r1-multicast.sh` | smcroute LAN/WAN |
| R2 | 4 | `roteador-r2/r2-multicast.sh` | smcroute WAN->LAN#2 |
| R1 | 5 | `roteador-r1/r1-tc.sh` | tc 115200 bps na WAN |
| S  | 2 | `servidor-s/s2-dns.sh` | BIND9 zona grupo4.unb |
| S  | 3 | `servidor-s/s3-email.sh` | Postfix+Dovecot TLS (IMAP/POP3) |
| S  | 4 | `servidor-s/s4-backend.sh` | Backend Mini-IPTV (Flask+systemd) |
| R1 | 6 | `roteador-r1/r1-web.sh` | Apache: intranet + API Gateway HTTP/HTTPS + frontend |
| X/Y| 1 | `cliente-x/x1-dhcp.sh` | DHCP + DNS -> S |
| —  | — | `testes/t1-conectividade.sh` | bateria de ping/curl/DNS |
| —  | — | `testes/t2-multicast.sh` | teste multicast com iperf |

**Ordem recomendada no lab:** R2(1,2) → R1(1,2,3) → S(1,2,3,4) → R2(3,4) → R1(4,5,6) → X/Y(1) → testes.

## Deu problema? Reset total

`sudo bash NetworkConfig/scripts/reset-maquina.sh` (ou opção **RESET** no menu) desfaz tudo que o projeto configurou naquela máquina — PPP, IPs fixos, rotas, NAT, DHCP server, multicast, tc, resolv.conf — e religa o NetworkManager, **restaurando a Internet normal do Lab**. Depois é só remontar rodando os scripts na ordem.

## Observações

- Os scripts **param o NetworkManager** antes de configurar (senão ele desfaz IP/rotas/resolv.conf).
- Todos são **idempotentes**: limpam o estado anterior antes de aplicar — rode de novo sem medo.
- Pacotes (bind9, postfix, smcroute...) são instalados pelo próprio script quando faltam — instale **enquanto a máquina ainda tem Internet** (a WAN de 115200 bps não serve para apt).
- Vídeos: copie `filme.mp4`, `aula.mp4`, `show.mp4` para `/opt/miniiptv/videos` (o s4 converte p/ versão leve).
- Usuários da aplicação: `admin/admin123`, `aluno1/senha1` … `aluno4/senha4`.
