#!/bin/bash
# [R2/X/Y] Aponta o resolv.conf para o DNS do S (rode onde precisar)
sudo rm -f /etc/resolv.conf
echo "nameserver 172.16.0.2" | sudo tee /etc/resolv.conf >/dev/null
echo "OK. Teste: nslookup s.grupo6.unb && nslookup google.com"
