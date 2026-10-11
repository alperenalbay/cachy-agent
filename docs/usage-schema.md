# Kullanım kaydı şeması (usage JSON)

`cachy-agent-usage-*` kolektörlerinin yazdığı ve bütün okuyucuların (oneline,
panel, alarm, fetch, `cachy-agent usage`) okuduğu ortak kayıt sözleşmesi.
Kaynak doğrulama: `cachy-agent-usage-update`, kolektör çıktısını JSON
olmadığı için zaten reddeder; bu belge sözleşmenin kendisini sabitler.

## Konum

Her kayıt tek dosyadır:

```
${XDG_STATE_HOME:-$HOME/.local/state}/cachy-agent/agents/usage/<id>.json
```

`XDG_STATE_HOME` onurlanır. Beş okuyucunun hepsi aynı çözümü kullanır;
hardcoded `~/.local/state` kalmaması bilinçli bir kuraldır (Task 7 defekt-1:
eski main.qml gömülü python'u bu kuralı çiğniyordu).

## Alanlar

| Alan | Tip | ready:true | ready:false |
|---|---|---|---|
| `schemaVersion` | int | zorunlu (1) | zorunlu (1) |
| `id` | string | zorunlu | zorunlu |
| `name` | string | zorunlu | zorunlu |
| `updatedAt` | string (ISO-8601 UTC, `...Z`) | zorunlu | zorunlu |
| `ready` | bool | `true` | `false` |
| `tierLabel` | string | zorunlu (boş olabilir) | zorunlu (boş olabilir) |
| `limits` | dizi | zorunlu (boş olabilir) | zorunlu (boş olabilir) |
| `todayPrompts` | int | zorunlu (0 olabilir, **asla eksik olamaz**) | yazılmaz |
| `todaySessions` | int | zorunlu | yazılmaz |
| `todayTotalTokens` | int | zorunlu | yazılmaz |
| `totalPrompts` | int | zorunlu | yazılmaz |
| `totalSessions` | int | zorunlu | yazılmaz |
| `reason` | string | yazılmaz | isteğe bağlı |

### Sözleşmenin iki kuralı

1. **`ready:true` kayıt TÜM sayaç alanlarını taşır.** Değer `0` olabilir;
   alanın yokluğu olamaz. Okuyucular eksik alanı varsayılanla doldurmak
   zorunda değildir — eski `cachy-agent usage`'nın `today`/`total`
   fallback'leri (Task 7 defekt-2) bu yüzden silindi.
2. **`ready:false` kayıt yalnızca temel alanları taşır:**
   `{schemaVersion, id, name, updatedAt, ready, limits}` + isteğe bağlı
   `reason`. Sayaçlar yazılmaz; "toplanamadı" ile "0 kullanıldı" ayrımı
   `ready` alanının kendisidir.

### `limits` öğesi

```json
{"label": "5h", "percent": 0.42, "resetsAt": "2026-10-07T12:00:00Z"}
```

- `percent` **0–1 arası orandır**. Kolektör yüzde ölçtüyse (0–100)
  `/100` ile normalize etmek kolektörün işidir; okuyucular >1.0 gördüklerinde
  yine de /100 uygulayarak okur (eski davranış korunur).
- `resetsAt` ISO-8601 UTC; yoksa `null` ya da `""`. Okuyucular ikisini de
  boş sayar.
- `label` boş olabilir; okuyucular boş etiketi kendi varsayılanıyla
  görselleştirir.

## `reason` gösterimi

`ready:false` + `reason` taşıyan kayıtta okuyucular gerekçeyi kullanıcıya
gösterir:

- `cachy-agent-usage-fetch summary` → `copilot: veri yok (no CLI quota command)`
- `cachy-agent-usage-oneline` → `copilot:- (no CLI quota command)`
- `cachy-agent-usage-panel` → `● Copilot  veri yok (no CLI quota command)`

Task 7 öncesinde `reason` hiçbir okuyucuda görünmüyordu.

## Tüketiciler ve çıktı biçimleri

### `cachy-agent-usage-fetch` (varsayılan mod — plasmoid)

`main.qml` stdout'u `JSON.parse` edip `providers[]` ve `alarm` okur.
**Bu şema birebir korunmak zorundadır** — plasmoid sessizce bozulur:

```json
{"providers":[{"id":"codex","name":"Codex","today":3,"total":9,
  "limits":[{"label":"5h","percent":0.42,"resetsAt":"2026-10-07T12:00:00Z"}]}],
 "alarm":false}
```

- `alarm`, herhangi bir limitin `percent >= 0.9` olmasıdır (eşik sabittir).
- Kayıt hiç yoksa `{"providers":[],"alarm":false}` basılır — **boş stdout
  değil**: `main.qml` boş stdout'u "boş çıktı" hatası sayar.
- Parse edilemeyen dosya sessizce atlanır.
- `ready:false` kayıtlar da `providers[]` içinde yer alır (sayaçları 0,
  limitleri genelde boştur).

### `cachy-agent-usage-fetch summary` (`cachy-agent usage`)

Satır satır:

```
codex: today=3 total=9 limits[5h 42% (7 Eki),weekly 82% (13 Eki)]
copilot: veri yok (no CLI quota command)
```

- Reset tarihi Türkçe kısa ay adıyla basılır (usage-oneline ile aynı
  `MONTHS_TR`).
- Limit yoksa `limits[-]`.
- Kullanılabilir kayıt hiç yoksa `kayıt yok, \`cachy-agent-usage-update\`
  çalıştır`.

## `ready` varsayılanı

Hiçbir okuyucuda `ready` alanı yoksa kayıt **hazır** sayılır (`True`).
usage-oneline hep böyleydi; usage-panel Task 7'ye kadar `False` ile
varsayılanlıyordu — aynı soruya iki farklı cevap (defekt-3) tek değerde
birleşti.

## Kolektörler

| id | kolektör | kaynak |
|---|---|---|
| `opencode` | `cachy-agent-usage-opencode` | `opencode stats --json` |
| `codex` | `cachy-agent-usage-codex` | usage RPC |
| `copilot` | `cachy-agent-usage-copilot` | CLI sorgusu |
| `agy`, `claude`, `crush`, `cursor-agent`, `grok` | — | kolektörü yok |

Kolektörü olmayan agent'ın kullanımı izlenmez; `usage` dizininde dosyası
olmaz. Hata yolundaki kolektör (ör. CLI bulunamadı) **aynı sözleşmeye
uymak zorundadır**: `ready:false` + tüm temel alanlar (Task 7'ye kadar
`cachy-agent-usage-opencode` yalnızca 4 alan basıyordu).
