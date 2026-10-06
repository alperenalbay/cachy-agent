# argv-baseline — spec §8.2

Mevcut (`--inline`) davranışın ölçülmüş hali. **Faz 1 refactor'ı bu tabloyu
bozmamalıdır.** `tests/test.sh` test 15 bu değerleri üretilen argv ile
karşılaştırır; sapma olursa test kırmızıya döner.

Ölçüm yöntemi: agent'lar PATH'te stub'larla gölgeleniyor, stub çağrıldığında
argv'sini log'a yazıyor. Gerçek agent CLI'dir çalıştırılmıyor.

Üretim: `tests/argv-differential.sh --emit` (bkz. o dosya).

## prompt ile (`cachy-agent --inline <agent> P`)

| agent | argv |
|---|---|
| opencode | `--auto --prompt P` |
| agy | `--dangerously-skip-permissions --effort low --prompt P` |
| claude | `--permission-mode auto -p P` |
| codex | `--approve-for-me P` |
| crush | `--yolo P` |
| copilot | `--allow-all P` |
| cursor-agent | `--yolo --trust P` |
| grok | `--permission-mode bypassPermissions P` |

## promptsuz (`cachy-agent --inline <agent>`)

| agent | argv |
|---|---|
| opencode | `--auto` |
| agy | `--dangerously-skip-permissions` |
| claude | `--permission-mode auto` |
| codex | `--approve-for-me` |
| crush | `--yolo` |
| copilot | `--allow-all` |
| cursor-agent | `--yolo --trust` |
| grok | `--permission-mode bypassPermissions` |

## agy — koşullu dal

`cachy-agent:20-25`, `agy --help` çıktısında `dangerously-skip-permissions`
geçiyorsa bayrakları geçiyor, geçmiyorsa düşürüyor. İki dal da ölçüldü:

| `agy --help` çıktısı | prompt ile | promptsuz |
|---|---|---|
| bayrağı **içerir** | `--dangerously-skip-permissions --effort low --prompt P` | `--dangerously-skip-permissions` |
| bayrağı **içermez** | `--prompt P` | — (çıplak `agy`, bayrak yok) |

İkinci dal önemli: config'te sabit `flags` tutulduğu için, koşullu bayrak
düşürme `run_agent`'da `agy` için ayrıca ele alınmalı (spec §5.4.1).
