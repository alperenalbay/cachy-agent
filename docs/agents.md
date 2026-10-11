# agents.conf referansı

Tüm agent tanımları tek dosyada: `~/.config/cachy-agent/agents.conf`.
Menüler, script'ler ve plasmoid buradan okur; kodda agent listesi yoktur.

## Satır biçimi

```ini
id=görünen_ad|install|flags|prompt_flag|login
```

| Alan | Anlamı | `-` anlamı |
|---|---|---|
| `id` | PATH'te aranan komut adı; `[A-Za-z0-9_-]+`, benzersiz | — |
| `görünen_ad` | Menüde ve plasmoidde gösterilen ad | — |
| `install` | `cachy-agent-install <id>` çalıştırdığı komut | otomatik kurulum yok |
| `flags` | Her açılışta geçirilen bayraklar (boş olabilir) | — |
| `prompt_flag` | Prompt'un verildiği bayrak (`--prompt`, `-p`) | prompt konumsal verilir |
| `login` | Açılış başarısızsa gösterilen ipucu | giriş gerekmez |

## Kurallar

- Alan ayırıcı `|`. `install` içinde bir `|` gerekiyorsa kaçışlı yazın: `\|`
  (örn. `curl … -fsS \| bash`). Kaçışsız `|` alanı böler — parse hatası.
- `flags` ve `prompt_flag` içinde **tırnak olamaz** (`"` / `'`).
  `install` tırnak kullanabilir, çünkü `bash -c` ile çalıştırılır.
- `prompt_flag` ya `-` ya da `-` ile başlayan tek bir bayrak olmalı.
- `install` veya `login` boş bırakılırsa okuma tarafında `-` sayılır;
  `cachy-agent-agents check` yine de hatayı raporlar (yazar hatası görünür kalsın).
- `WORKDIR=~/Projeler` satırı agent değil, **global ayardır**: `a`/`ga`
  bunun içinde açılır. Satır yoksa varsayılan `~/Projeler`.

## Doğrulama

```bash
cachy-agent-agents check
```

Şunları satır numarasıyla raporlar: alan sayısı, `id` biçimi ve benzersizliği,
tırnak, `prompt_flag` biçimi, boş `install`/`login`, birden fazla `WORKDIR`.

## Yeni agent ekleme

1. `agents.conf`'a bir satır ekleyin.
2. Kota verisi toplanmasını istiyorsanız bir kolektör yazın:
   `src/bin/cachy-agent-usage-<id>`, stdout'a JSON basar
   (şema: `docs/usage-schema.md`).

Kod değişikliği gerekmez — menü, script'ler ve plasmoid listeyi config'ten okur.

## `agy` koşullu bayrakları (ölçülmüş)

`cachy-agent`, `agy`'yi çağırmadan önce `agy --help` çıktısında
`dangerously-skip-permissions` geçip geçmediğine bakar. İki dal:

| `agy --help` çıktısı | prompt ile | promptsuz |
|---|---|---|
| bayrağı **içerir** | `--dangerously-skip-permissions --effort low --prompt P` | `--dangerously-skip-permissions` |
| bayrağı **içermez** | `--prompt P` | — (çıplak `agy`) |

Bu davranış config'te **ifade edilemez** (B dalında bayraklar tamamen düşer),
o yüzden `run_agent` içinde `agy` özelinde bir koşul olarak kalır. Ölçüm:
`tests/fixtures/argv-baseline.md`; doğrulama: `tests/argv-differential.sh --check`.

## `--seed` neden config'e taşınmadı

`cachy-agent --seed <ad> <metin>` interaktif oturum + başlangıç bağlamı
başlatır ve agent başına farklı bayrak kullanır (`agy --prompt-interactive`,
`opencode --prompt`). Bu tek bir agent'ın tek bir modu; config'e alan eklemek
yerine ayrı `case` olarak bırakıldı (YAGNI).

## Prompt bayrağı hakkında

Her CLI prompt'u aynı şekilde almıyor. Config bu yüzden agent başına
`prompt_flag` tutar; `run_agent` şunu üretir:

```bash
exec "$agent" $flags "$prompt_flag" "$*"
```

`prompt_flag` `-` ise prompt konumsal verilir. Değerler gerçek CLI'lardan
birebir çıkarıldı; bir agent'ın `--help`'i değişirse config'deki satırı
güncelleyin — `tests/argv-differential.sh --check` sapmayı yakalar.
