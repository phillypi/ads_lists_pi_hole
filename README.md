# ads_lists_pi_hole

Blocklist para Pi-hole que junta listas mantidas pela comunidade e **não bloqueia** Google/Google Ads nem grandes lojas (AliExpress, Amazon, Mercado Livre, Shopee, Shein, Temu, Magalu, KaBuM! etc.).

## URL para o Pi-hole

```
https://raw.githubusercontent.com/phillypi/ads_lists_pi_hole/main/pihole_blocklist.txt
```

Atualizada automaticamente todo dia pelo GitHub Actions (`.github/workflows/update.yml`).

## Como funciona

- `sources.txt`: listas de origem (HaGeZi Pro, HaGeZi TIF mini, StevenBlack).
- `allowlist.txt`: domínios que nunca entram na lista. Edite e faça commit; a lista é regerada sozinha.
- `build.ps1`: baixa, filtra, remove duplicados e grava `pihole_blocklist.txt` no formato `||dominio^`.

Para gerar localmente: `powershell -ExecutionPolicy Bypass -File build.ps1`
