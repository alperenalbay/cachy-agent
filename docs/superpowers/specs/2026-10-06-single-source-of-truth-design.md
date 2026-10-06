# cachyAgent — Single Source of Truth & Honesty Redesign

**Date:** 2026-10-06
**Status:** Draft for review
**Scope:** v0.1.0 → v0.2.0

---

## 1. Problem

cachyAgent v0.1.0 çalışıyor, `tests/smoke.sh` geçiyor, kod okunabilir. Ama üç yapısal
sorun var:

### 1.1 Agent kataloğu kodun içinde dağınık

README.md:8 "genel agent tanımları + proje bazlı geçersiz kılmalar, menü kurulurken
birleştirilir" diyor. Böyle bir dosya veya mekanizma **yok**. Agent listesi 6 dosyada
hardcoded:

| Konum | Satırlar |
|---|---|
| `src/bin/cachy-agent` | 10, 61, 71, 85, 127 |
| `src/bin/cachy-agent-menu` | 9, 28, 35, 38 |
| `src/bin/cachy-agent-open` | 7 |
| `src/bin/cachy-agent-install` | 6 (farklı liste — 8'de 6) |
| `src/bin/cachy-agent-usage-update` | 15 |
| `src/plasmoid/.../main.qml` | 33 |

Sonuç: yeni agent eklemek 6 dosyayı elle düzenlemek demek. Hepsi birbirinden
bağımsız kaldığı için biri unutulunca hata sessizdir.

Aynı şekilde her agent'ın davranışı (`run_agent`, `case` ifadeleri) kodun içinde:
`cachy-agent:16-43` her agent için farklı izin bayrakları geçiriyor. Bu bayraklar
da hardcoded.

### 1.2 Testler repoyu değil kurulu sistemi test ediyor

`tests/test.sh:9` → `BIN="$HOME/.local/bin"`. Temiz bir checkout'ta `./install.sh`
çalıştırmadan **hiçbir** test grubu koşmuyor (10/10 grup kurulum gerektiriyor).
Repo doğrudan `~/Projeler/cachy-agent` olarak yaşadığı için bu sorun gözünüze
gelmemiş; ama bu bir tesadüf, bir özellik değil.

Dahası: test 6b (`test.sh:45-50`) "≥3 geçerli JSON" bekliyor. Bu, gerçek
`cachy-agent-usage-codex`'in credential okuyup ağ üzerinden JSON-RPC çağrısı
yapmasını (`usage-codex:26,41,43`) ve gerçek `opencode stats`'in çalışmasını
gerektiriyor. CI'da koşamaz, gizli olarak credential'e dokunur.

CI yok (`.github/` yok). Lint yok. `.gitignore` yok — `py_compile` ürettiği
`__pycache__` izlenmiyor.

### 1.3 README gerçeği yansıtmıyor

| README iddiası | Gerçek |
|---|---|
| :8 "two-part catalog … merged at menu build time" | Yok |
| :9 "Guided setup flow — interactive first-run installer" | `cachy-agent-install` sadece `npm i -g @…`; ilk-çalıştırma akışı yok |
| :29 "registers the global shortcut" | Kaydetmiyor; `install.sh:124` kullanıcıya "Sistem Ayarları'ndan ekle" diyor. `kwriteconfig6` bağımlılık olarak kontrol ediliyor (:17) ama hiç çağrılmıyor |
| :59 "Placeholder — add a real screenshot" | `docs/screenshot-menu.png` gerçek bir PNG (1719×1065) |

Ayrıca:

- `WORKDIR="$HOME/Projeler"` hardcoded (`cachy-agent:6`, `:111`) — kullanıcının
  dizin düzenine varsayım.
- `cachy-agent:106`'daki gömülü Python **ölü alanlar okuyor**: `limits[].usedPercent`,
  `limits[].name`, top-level `today`, `total`. Hiçbir kolektör bunları üretmiyor.
  Yani `cachy-agent usage` her zaman `?` gösterecek.
- `main.qml:34` (`fetchCommand`) `~/.local/state`'i hardcoded — `XDG_STATE_HOME`'u yok
  sayıyor. Diğer 5 okuyucu honour ediyor.
- `ready` varsayılanı tutarsız: `usage-oneline:55` → `True`,
  `usage-panel:95` → `False`.
- 8 agent'ın 5'inde (`agy`, `claude`, `crush`, `cursor-agent`, `grok`) **hiç
  kolektör yok**. `usage-update:25-28` yoksa sessizce atlıyor. Kullanım takibi
  bu agent'lar için var olmayan bir özellik gibi sunuluyor.
- Kolektörler birbirinden farklı field setleri yayıyor (bkz. §6.4).

---

## 2. Amaç

**Bu bir kişisel araç.** Dağıtım, paketleme, AUR, çok dilgi destek hedefi yok.
Başarı ölçütü: bu repo, başka birinin (veya 6 ay sonra benim) dokunduğu zaman
kendisiyle çelişmiyor.

Üç hedef:

1. **Tek doğruluk kaynağı.** Agent listesi ve davranışı tek dosyada. Yeni agent =
   config'e bir satır + (varsa) kolektör script'i. Kod değişmez.
2. **Dürüstlük.** README kodu anlatsın. Var olmayan özellik iddia edilmesin.
3. **Doğrulanabilirlik.** `./tests/test.sh` temiz bir checkout'ta, kurulum
   yapmadan, ağa ve credential'e dokunmadan koşsun. CI bunu her push'ta doğrulasın.

## 3. Kapsam Dışı

Bu çalışma **bunları yapmaz**:

- Proje bazlı agent override'i (README'nin vaat ettiği "two-part catalog").
  Config tek parça olacak; `WORKDIR` hariç proje bazlı seçim yok.
- Yeni agent kolektörü (`agy`, `claude`, `crush`, `cursor-agent`, `grok` için
  kullanım toplama). §6.4 bu agent'ların neden izlenemediğini belgeler ve
  README buna göre düzeltilir.
- Paketleme: AUR PKGBUILD, `.pkg.tar`, release tarball.
- Çok dillik UI. README'ler İngilizce/Türkçe olarak kalır (mevcut durum).
- `hasNerdFont` gerçek kontrolü (`main.qml:14-16` — yorum bir kontrol
  tarif ediyor, kod `true` sabitliyor). Kozmetik; dokunulmaz.
- Güvenlik sertleştirme (`--yolo`, `--dangerously-skip-permissions`, `curl | bash`).
  Bilinçli mevcut tercih; ayrı bir çalışma konusu.

## 4. Genel Yaklaşım

Dört faz, bağımlılık sırasıyla. Her fazı tek başına çalıştırılabilir ve
`tests/test.sh` geçer bırakır.

```
Faz 1  agents.conf + cachy-agent-agents okuyucu + 7 hardcode temizliği
  ↓
Faz 2  install/uninstall --prefix + test.sh repoya bağlanır + CI
  ↓
Faz 3  Gömülü Python → gerçek scriptler + şema düzeltmeleri
  ↓
Faz 4  README / README.tr / CHANGELOG / VERSION
```

Faz 1 olmadan Faz 3 anlamsız (plasmoid config'ten beslenmeli). Faz 4 en sona
kalır çünkü diğer fazların son halini belgelemeli.

### Neden `source` edilen kütüphane değil, CLI?

`cachy-agent-agents` bir **CLI script'i**. Diğerleri onu subprocess olarak çağırır.

Alternatif: `source "$(dirname "$0")/cachy-agent-lib"`. Reddedildi çünkü

- script'ler `~/.local/bin`'e düz kopyalanıyor; biri symlink'lenirse `dirname`
  çözümlemesi kırılır ve `source` sessizce başarısız olur,
- `source` global state paylaşır — 6 script'in arasında sızan bir değişken
  bulmak zor olur,
- plasmoid QML'i bash `source` yapamaz; yine de ayrı bir yol gerekir.

CLI yaklaşımı her tüketiciyi izole tutar, testi kolaydır (çıktıyı assert et,
durumu kurma), ve plasmoid için tek satırlık bir komut verir.

---

## 5. Faz 1 — Config + Tek Okuyucu

### 5.1 `src/config/agents.conf`

Repo'da versiyonlanır. Format: satır tabanlı, `#` yorum, `|` ile ayrılmış alanlar.
Boş satır ve `#` ile başlayan satırlar atlanır.

```
# cachyAgent agent kataloğu
# Format: id=görünen_ad|install|flags|prompt_flag|login
#   id           komut adı (PATH'te aranır), benzersiz olmalı
#   görünen_ad  menüde ve plasmoidde gösterilen ad
#   install      kurulum komutu; "-" ise harici kurulum (kurulum desteklenmez)
#   flags        çalıştırılırken geçirilecek bayraklar (boş olabilir)
#   prompt_flag  prompt için kullanılan bayrak (ör. --prompt, -p);
#                "-" ise prompt konumsal argüman olarak verilir
#   login        giriş yapılmamışsa gösterilecek ipucu; "-" ise giriş gerekmez
#
# Bu dosyayı düzenleyebilirsin; install.sh sadece dosya YOKSA kopyalar.
# Ayrıntılar: docs/agents.md

opencode=opencode|-|--auto|--prompt|-
agy=agy|-|--dangerously-skip-permissions --effort low|--prompt|-
claude=Claude Code|npm i -g @anthropic-ai/claude-code|--permission-mode auto|-p|claude login
codex=Codex|npm i -g @openai/codex|--approve-for-me|-|codex login
crush=Crush|npm i -g @charmlabs/crush|--yolo|-|-
copilot=Copilot CLI|npm i -g @github/copilot|--allow-all|-|copilot login
cursor-agent=cursor-agent|curl https://cursor.com/install -fsS \| bash|--yolo --trust|-|agent login
grok=Grok CLI|curl -fsSL https://x.ai/cli/install.sh \| bash|--permission-mode bypassPermissions|-|grok login
```

Bu tablo, mevcut `run_agent` (`cachy-agent:16-43`) ve `--seed`
(`cachy-agent:73-79`) `case`lerinden **birebir** çıkarılmıştır — yani config
ilk yazıldığında davranış değişmez. `prompt_flag` ayrımı zorunluydu: `opencode`,
`agy` ve `claude` prompt'u bayrakla alırken `codex`, `crush`, `copilot`,
`cursor-agent` ve `grok` konumsal argüman bekliyor. Tek bir `--prompt`
varsayımı bu 5 agent'ı kırardı.

Noktalar:

- `|` alan ayracı olduğu için `install` içindeki `|` kaçışlı (`\|`).
  Kaçışsız `|` bir alanı böler — belirsizlik yerine hata tercih edilir.
- Alan sayısı 6'dan azsa hata; 6'dan fazlaysa son alanlar yok sayılır
  (ileri uyum). Boş bırakılan `install` veya `login` alanı `-` sayılır.
- Tüketiciler `install == "-"` olan agent'ı kurulamaz sayar (`agy`, `opencode`
  dışarıdan gelir).
- `flags` içinde tırnak **olamaz** (parse `IFS='|'` ile yapılıyor).
  `install` komutu `bash -c` ile çalıştırıldığı için tırnak kullanabilir —
  ama kaçışlı `|` yine de zorunlu.
- **Global ayarlar** `=`'den önceki anahtar `WORKDIR` ise ayrı ele alınır:
  geri kalan satır tek alandır (`WORKDIR=~/Projeler`), agent değildir ve
  `cachy-agent-agents` tarafından listeye hiç girmez. `~` genişletilir.
  Satır yoksa `~/Projeler` (mevcut davranış, geriye uyum).
  `check`, `WORKDIR` satırlarının tam olarak 1 alan içermesini doğrular ve
  birden fazla `WORKDIR` satırını hata olarak raporlar.

### 5.2 `src/bin/cachy-agent-agents`

Tek doğruluk kaynağının okuyucusu. Diğer tüm script'ler yalnızca bunu çağırır.

```bash
cachy-agent-agents list              # id'ler, birer satır (config sırası)
cachy-agent-agents ids               # id'ler, tek satır (menü döngüsü)
cachy-agent-agents get <id> <key>    # tek alan: name|install|flags|prompt_flag|login
cachy-agent-agents flags <id>        # yalnızca flags alanı (exec'e güvenli; prompt_flag
                                    #   `get <id> prompt_flag` ile ayrı alınır)
cachy-agent-agents installed         # PATH'te bulunan id'ler, birer satır
cachy-agent-agents external          # install != "-" olan id'ler
cachy-agent-agents known <id>        # id katalogda ise exit 0, değilse 1
cachy-agent-agents workdir           # WORKDIR değeri (genişletilmiş)
cachy-agent-agents json              # aşağıdaki §5.3
cachy-agent-agents check             # parse + tutarlılık doğrulaması, §5.5
```

Sözleşme:

- **stdout yalnızca sorunun cevabı.** Tanı mesajları stderr'e. Bu, çağıranların
  `$(...)` ile güvenle kullanmasını sağlar.
- Bilinmeyen `get`/`flags`/`known` id → stderr'de mesaj, **exit 1**, stdout boş.
- **Config eksik veya parse edilemiyorsa tüm sorgular exit 1 verir**, stderr'e
  açıklayıcı mesaj (dosya yolu + satır numarası).

  Bu bilinçli bir seçimdir. Config yokken boş liste dönerse menü boş görünür ve
  kullanıcı nedenini anlamaz. Oysa `install.sh` dosyayı her zaman kurar —
  dosyanın yokluğu normal değil, bir sorun işaretidir. `cachy-agent-agents`
  stderr'ine yazdığı mesaj kullanıcının terminalinde görünür, bu yüzden
  hatayı yutmak yerine **yukarı taşımak** gerekir. Tüketiciler bu mesajı
  `||` ile yutmaz; `run_agent` ve menü, config okunamadığında kullanıcıyı uyarır
  ve ihtiyaç duyulan yerde `install.sh`'a yönlendirir.
- Çıkış kodları: 0 = tamam, 1 = bilinmeyen id / config eksik-bozuk / check
  başarısız, 2 = kullanım hatası.

### 5.3 `json` çıktısı (plasmoid için)

```json
{"catalog":[{"id":"opencode","name":"opencode","installed":true,"external":true}, ...]}
```

- `installed`: `command -v <id>` başarılı mı
- `external`: `install != "-"` (yani menüde "Kur" gösterilebilir mi)

`main.qml:33`'teki gömülü Python'ın birebir yerine geçer; orada yalnızca
`{id, installed}` vardı, burada iki alan daha var.

### 5.4 Tüketicilerin yeni hâli

| Konum | Eski | Yeni |
|---|---|---|
| `cachy-agent:10` `KNOWN_AGENTS` | sabit string | `cachy-agent-agents ids` (hata mesajları için) |
| `cachy-agent:16-43` `run_agent` | 8 `case` kolu | `cachy-agent-agents flags "$agent"` → `exec "$agent" $flags "$@"` |
| `cachy-agent:61,71,85` whitelist `case` | 8 seçenek | `cachy-agent-agents known "$sel"` |
| `cachy-agent:127` help metni | liste | `cachy-agent-agents ids` ile üretilir |
| `cachy-agent:6` `WORKDIR` | `$HOME/Projeler` | `cachy-agent-agents workdir` |
| `cachy-agent-menu:9` döngü | 8 isim sabiti | `cachy-agent-agents list` |
| `cachy-agent-menu:28,35,38` `case` | 3 ayrı whitelist | `cachy-agent-agents known "$name"` |
| `cachy-agent-open:7` `case` | 8 seçenek | `cachy-agent-agents known "$AGENT"` |
| `cachy-agent-install:6` `case` | 6 seçenek (opencode/agy yok) | `get <name> install`; `-` ise "kurulum desteklenmiyor" + exit 1 |
| `cachy-agent-install:11-19` `case` kurulum | 6 `npm/curl` kolu | `get <name> install` çalıştırılır (shell olarak, kullanıcı onayından sonra) |
| `cachy-agent-open:14-19`, `cachy-agent-install:22-28` login ipuçları | `case` | `get <name> login`; `-` ise genel ipucu |
| `cachy-agent-usage-update:15` `AGENTS` | 8 isim | `cachy-agent-agents list` |
| `main.qml:33` `catalogCommand` | gömülü Python | `__HOME__/.local/bin/cachy-agent-agents json` |

`--seed` (`cachy-agent:73-79`) ayrı bir moddur: `agy --prompt-interactive`,
`opencode --prompt` kullanır, diğer agent'lar bayraksız çağrılır. Bu **tek bir
agent'ın tek bir modu** olduğu için config'e taşınmaz — ayrı `case` olarak kalır,
yalnızca `known` ile doğrulanır ve artık hardcoded agent listesi içermez.
Yani `cachy-agent`'de kalan tek `case`: `agy` ve `opencode` için iki kol. Bu,
"YAGNI" sınırının bilinçli olarak burada çizildiği yerdir.

Yeni `run_agent` — `prompt_flag` sayesinde iki prompt modunu da karşılar:

```bash
run_agent() {
  local agent="$1"; shift || true
  if ! cachy-agent-agents known "$agent"; then
    echo "bilinmeyen agent: $agent (bilinenler: $(cachy-agent-agents ids))" >&2
    return 1
  fi
  if [[ "$PWD" == "$HOME" ]]; then
    local wd; wd="$(cachy-agent-agents workdir)"
    [[ -d "$wd" ]] && cd "$wd"
  fi
  local flags pf
  flags="$(cachy-agent-agents get "$agent" flags)"
  pf="$(cachy-agent-agents get "$agent" prompt_flag)"
  if [[ $# -gt 0 && "$pf" != "-" ]]; then
    # shellcheck disable=SC2086  # flags config'ten kelime kelime gelir
    exec "$agent" $flags "$pf" "$*"
  elif [[ $# -gt 0 ]]; then
    # shellcheck disable=SC2086
    exec "$agent" $flags "$*"
  else
    # shellcheck disable=SC2086
    exec "$agent" $flags
  fi
}
```

Bu, mevcut `cachy-agent:16-43` ile **davranış olarak özdeş**tir:

| Agent | Mevcut (`cachy-agent:16-43`) | Yeni |
|---|---|---|
| opencode | `opencode --auto --prompt "$*"` | `flags="--auto"`, `pf="--prompt"` → aynı |
| agy | `agy --dangerously-skip-permissions --effort low --prompt "$*"` | aynı |
| claude | `claude --permission-mode auto -p "$*"` | `pf="-p"` → aynı |
| codex | `codex --approve-for-me "$*"` | `pf="-"` → konumsal, aynı |
| crush / copilot / cursor-agent / grok | konumsal | `pf="-"` → aynı |

Tek fark: `agy`'nin `--help` çıktısında `dangerously-skip-permissions` yoksa
mevcut kod bayrağı düşürüyor (`cachy-agent:20-25`). Bu koşullu davranış
korunur — config okunduktan sonra, `agy` özelinde, `cachy-agent-agents`'tan
bağımsız bir `if` olarak kalır.

### 5.5 `check` — config doğrulaması

`cachy-agent-agents check` şunları doğrular ve satır numarasıyla raporlar:

1. Her agent satırı tam olarak 6 alan içeriyor.
2. `id` benzersiz ve `[A-Za-z0-9_-]+` ile eşleşiyor.
3. `flags` ve `prompt_flag` içinde tırnak (`"` / `'`) yok ve `flags` içinde `|`
   yok — parse `IFS='|'` ile yapılıyor.
4. `prompt_flag` ya `-` ya da `-` ile başlayan tek bir bayrak.
5. `install` ve `login` alanları ya dolu ya `-` değil.
6. `WORKDIR` ya hiç yok ya tam olarak 1 tane ve 1 alan içeriyor.

Bu `check`, Faz 2'de CI'a girer. `tests/test.sh` de kendi fixture config'ini
geçerli/bozuk olarak iki kez çalıştırarak `check`'i test edecek.

---

## 6. Faz 3 — Gömülü Python ve Şema

### 6.1 `cachy-agent-usage-fetch` (yeni)

`main.qml:34` ve `cachy-agent:106`'daki gömülü Python'un yerine geçer.

```bash
cachy-agent-usage-fetch          # plasmoid için providers JSON
cachy-agent-usage-fetch summary  # `cachy-agent usage` için satır satır özet
```

`providers` çıktısı — `main.qml`'nin beklediği şekle birebir uyumlu olmalı,
aksi hâlde QML değişir ve kapsam taşar:

```json
{"providers":[{"id":"codex","name":"Codex","today":0,"total":0,
               "limits":[{"label":"5h","percent":0.42,"resetsAt":"2026-10-06T12:00:00Z"}]}],
 "alarm":false}
```

`alarm`, herhangi bir limit `percent >= 0.9` ise `true` — mevcut davranış korunur
(`main.qml:34`).

**`XDG_STATE_HOME` düzeltmesi:** `main.qml:34` şu an `~/.local/state` hardcoded.
Yeni script `os.environ.get("XDG_STATE_HOME", ...)` kullanır — diğer 5 okuyucuyla
hizalanır.

### 6.2 Ölü okumaların temizlenmesi

`cachy-agent:106`'daki `l.get("percent", l.get("usedPercent","?"))` gibi
fallback'ler ve `today`/`total` fallback'leri kaldırılır. Hiçbir kolektör
`usedPercent`, `limits[].name`, `today` veya `total` üretmiyor — bu fallback'ler
yalnızca `?` üretiyor. Tek alan adı gerçek şema olur: `percent`, `label`,
`todayPrompts`, `totalPrompts`.

### 6.3 `ready` varsayılanı

`usage-oneline:55` → `get("ready", True)`; `usage-panel:95` → `get("ready", False)`.
Tek doğruluk kaynağı: `True`. Gerekçe: okunamayan/eksik alan `ready`'yi
göstergelemez; ayrıca "veri yok" göstergesini `panel` zaten limit listesi boşsa
veriyor. Kolektörler `ready`'yi açıkça yazdığı için varsayılan nadiren devreye
girer — ama tutarsız iki farklı varsayılan olmasındansa tek olan yeğdir.

### 6.4 Kolektör şema farkları — belgelenir, düzeltilmez

Kolektörler bugün tutarlı **değil**:

| Alan | codex | opencode | copilot |
|---|---|---|---|
| `schemaVersion` | ✅ | ✅ | ✅ |
| `id`, `name`, `updatedAt` | ✅ | ✅ | ✅ |
| `ready` | ✅ | ✅ | `false` (sabit) |
| `tierLabel` | ✅ | ✅ | `""` |
| `limits[]` | ✅ | `[]` | `[]` |
| `todayPrompts` / `totalPrompts` | `0` (sabit) | ✅ gerçek | `0` (sabit) |
| `todaySessions` / `totalSessions` | `0` | ✅ | — (yok) |
| `todayTotalTokens` | `0` | ✅ gerçek | — (yok) |
| `reason` | — | — | ✅ (tek başına) |

Ek olarak `opencode`'ın hata yolları (`:7`, `:19`) yalnızca
`{schemaVersion,id,ready,limits}` yazıyor; `name`/`updatedAt`/sayaçlar yok.
`copilot` `reason` alanını üretiyor ama **hiçbir okuyucu onu okumuyor**.

Bu turda şema birleştirilmiyor — bu ayrı bir iş. Bunun yerine:

- **Sözleşme:** `ready:true` olan bir kayıt **tüm** sayaç alanlarını içerir
  (`0` olabilir ama **yok olmaz**). `ready:false` olan kayıt yalnızca
  `{schemaVersion,id,name,updatedAt,ready,limits}` yazar. Bu, okuyucuların
  `or 0` ile güvenli varsaymasını mümkün kılar.
- `opencode:7,19` bu sözleşmeye uyacak şekilde genişletilir.
- `copilot`'in `reason` alanı okuyucuya bağlanır: `ready:false` kayıtlarda
  `usage-oneline` ve `usage-panel` `reason`'ı gösterir. (Bugün sessizce
  "veri yok" diyorlar — kullanıcı nedenini bilmiyor.)
- Kullanılmayan alanlar (`schemaVersion`, `updatedAt`, `tierLabel`, token
  sayaçları) **silinmez**; ileriye dönük tüketiciler için korunur ve
  belgelenir.

### 6.5 `docs/usage-schema.md`

Yeni dosya: her alan, tipi, hangi kolektörün ürettiği, okuyucusu, ve "5 agent'ın
kolektörü yok" gerçeği. README §"Known Limitations" bunu özetleyecek.

---

## 7. Faz 2 — Testler + CI

### 7.1 `--prefix`

```bash
./install.sh --prefix DIR      # tüm yolları DIR altına yazar
./uninstall.sh --prefix DIR    # DIR altından kaldırır
```

Bu tek başına yeni bir kurulum modu değil, **testlerin izole çalışmasını
sağlayan** bir mekanizma. Davranış:

- `--prefix` verilirse `BIN_DIR`, `FISH_DIR`, `SYSTEMD_DIR`, `APPS_DIR`,
  `FUZZEL_DIR`, `ICON_DIR`, `PLASMOID_DIR` ve config/state dizinleri
  `DIR/...` altına yönlendirilir. `DIR` yoksa oluşturulur.
- `__HOME__` placeholder genişletmesi `DIR` olur — böylece plasmoid ve desktop
  dosyaları test prefix'ini gösterir.
- `--prefix` verildiğinde systemd `enable`/`daemon-reload` **çalıştırılmaz**
  ve preflight'in `systemctl`/`kbuildsycoca6`/`desktop-file-validate`
  adımları atlanır (test ortamında systemd-user oturumu olmayabilir).
  `--check` ve `--prefix` birlikte kullanılabilir.
- `DIR` içindeki yollar `__HOME__` yerine gerçek `DIR` string'iyle yazılır; bu,
  desktop dosyalarının geçerli kalmasını sağlar (mutlak yol).

`uninstall.sh --prefix` mevcut davranışı korur, ancak §7.3'teki yeni kod
config'i de kaldırır (aşağıya bak).

### 7.2 `tests/test.sh` — repo-relative

`BIN="$HOME/.local/bin"` → `BIN="${CACHY_AGENT_TEST_PREFIX:-$REPO/src/bin}"`, ve
`export PATH="$BIN:$PATH"` böylece mevcut PATH tabanlı çağrılar
(`cachy-agent --help`, `cachy-agent usage`) doğru binary'yi bulur.

Her grup yeni kurulum bağımlılığına göre sınıflandırılır:

| Grup | Yeni davranış |
|---|---|
| 1 `bash -n` + `py_compile` | `src/bin` üzerinden; çıplak checkout'ta çalışır |
| 2 `--help` | PATH'ten; çalışır |
| 3a/b/c `default` | `XDG_CONFIG_HOME` geçici dizine yönlendirilir → **gerçek config'e dokunmaz** (bugün `:28,32` gerçek `$HOME/.config` okuyor) |
| 4 `--prompt` argümansız | çalışır |
| 5 `--pick` uydurma | çalışır |
| 6a `usage-update` exit 0 | çalışır |
| 6b ≥3 geçerli JSON | **sahte kolektörlerle** (§7.3) |
| 7 `usage` exit 0 | çalışır |
| 8 systemd + `is-active` | ortam yoksa **SKIP** (CI'da systemd-user yok) |
| 9 `desktop-file-validate` | komut yoksa **SKIP** |
| 10 menü stub'ı | mevcut stub mekanizması korunur, `$BIN` artık repo |
| **11 (yeni)** `agents.conf` parse | geçerli config → `list` doğru; bozuk config → exit 1 + stderr; `check` geçerli/bozuk fixture |
| **12 (yeni)** `WORKDIR` | config'ten okunur; yoksa `~/Projeler` geriye uyumu |
| **13 (yeni)** `install/uninstall --prefix` | geçici prefix'e kur → dosyaları doğrula → uninstall → geriye kalan kontrol |

`SKIP` yeni bir sonuç tipidir: `PASS`/`FAIL` yanında, özet satırında ayrı
sayılır ve **exit code'u etkilemez**.

### 7.3 Sahte kolektörler (test 6b)

Test, `usage-update`'i `$BIN` içindeki `cachy-agent-usage-<id>` script'lerini
arıyor. Test 6b için bunların yerine geçici bir dizinde **sabit JSON üreten
stub'lar** konur:

```bash
# stub: cachy-agent-usage-opencode
printf '{"schemaVersion":1,"id":"opencode","name":"opencode","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"","limits":[],"todayPrompts":1,"todaySessions":1,"todayTotalTokens":0,"totalPrompts":1,"totalSessions":1}\n'
```

`usage-update` `BIN_DIR`'ı `~/.local/bin`'den alıyor (`usage-update:9`) — bu
**sabit bir yol** ve testte override edilemez. Çözüm: `usage-update`'in
`BIN_DIR`'ı `CACHY_AGENT_BIN_DIR` env değişkeniyle ezilebilir hale getirilir
(varsayılan `~/.local/bin`). Bu, testlere gerçek bir seam verir ve satır 9'daki
sabit yol bir de yapılandırılabilir hale gelir.

Böylece test 6b: network yok, credential yok, gerçek agent yok. Doğruladığı şey
`usage-update`'in **orkestrasyon mantığı**: JSON geçerliliği, atomik yazım,
sessiz atlama, dosya sayısı.

Ayrıca 6b artık `<3` durumunda `FAIL` yerine doğru mesajla `FAIL` verir ama
**nedenini** belirtir: `stub dizini bulunamadı` vs `geçersiz JSON: <dosya>`.

### 7.4 `tests/smoke.sh` temizliği

- `:25` `find "$REPO_DIR/src" -name '__pycache__' -exec rm -rf {} +` — smoke testi
  bir **yazma** yapıyor. Kaldırılır; `.gitignore` devralır.
- `py_compile` `:23` de `__pycache__` üretir. `-B` bayrağıyla (`PYTHONDONTWRITEBYTECODE=1`)
  çalıştırılır.
- `:42` `bash "$REPO_DIR/src/bin/cachy-agent" --version`'a güveniyor; Faz 1'de
  `cachy-agent:111`'deki `$HOME/Projeler/cachy-agent/VERSION` fallback'i
  kaldırılır (`VERSION` `install.sh` ile birlikte `~/.local/bin/VERSION`'a
  gider ya da `--version` yalnızca `../VERSION`'a bakar).
- Yeni: `shellcheck` varsa `src/bin` + `install.sh` + `uninstall.sh` üzerinde
  çalıştırılır. `shellcheck` yoksa atlanır (bu makinede yok).

### 7.5 `.gitignore`

```
__pycache__/
*.pyc
```

### 7.6 CI

`.github/workflows/ci.yml`:

```yaml
name: ci
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install deps
        run: sudo apt-get update && sudo apt-get install -y shellcheck desktop-file-utils
      - name: smoke
        run: ./tests/smoke.sh
      - name: test
        run: ./tests/test.sh
```

`smoke.sh` CI'da `systemd-analyze verify` çalıştırır — ubuntu-latest'te
`systemd-analyze` mevcut, `systemd-analyze verify` user unit'leri doğrulayabilir.
Doğrulayamazsa smoke `FAIL` verir; bu durumda CI adımı `systemd-analyze`'ın
varlığını kontrol edip yoksa atlar.

Not: `smoke.sh:28` `src/` içinde `/home/` arar — bu, `__HOME__` placeholder'ın
çalıştığını garanti eder. Korunur.

---

## 8. Faz 4 — Dokümantasyon

### 8.1 `README.md` / `README.tr.md`

Düzeltmeler:

| Mevcut | Yeni |
|---|---|
| "Two-part catalog — global definitions + per-project overrides, merged at menu build time" | "Tek katalog dosyası — `~/.config/cachy-agent/agents.conf`. Tüm menüler, script'ler ve plasmoid buradan okur." |
| "Guided setup flow — interactive first-run installer that checks dependencies and writes config" | "`install.sh` bağımlılıkları denetler ve katalog dosyasını yazar. **Kısayol kaydı manueldir** (aşağıya bak)." |
| "The installer … registers the global shortcut" | "Kısayol KDE tarafında tanımlanır: Sistem Ayarları › Klavye › Kısayollar › cachyAgent › Başlat." |
| "> Placeholder — add a real screenshot" | Satır silinir (görüntü mevcut) |
| "Agent quota is not checked programmatically" | Genişletilir: hangi agent'ın kota verisi **var** (`codex`, `copilot`), hangisinin **yok** (`agy`, `claude`, `crush`, `cursor-agent`, `grok` — kolektörleri yok) |
| — | Yeni: `agents.conf` formatı (§5.1) ve `WORKDIR` |
| — | Yeni: `./tests/smoke.sh` ve `./tests/test.sh` nasıl koşar |

`README.tr.md` birebir aynı düzeltmelerle senkronlanır. İki dosya elde
tutulması bir süre sonra yük olacak — ama şimdilik iki dilli README'nin
kendisi bir özellik; **tek dosyaya indirmek kapsam dışı.**

### 8.2 `docs/agents.md`

`agents.conf` referansı: format, alanlar, kaçış kuralları, `WORKDIR`,
yeni agent nasıl eklenir (iki adım: config satırı + varsa
`src/bin/cachy-agent-usage-<id>`), `--seed`'in neden config'e taşınmadığı.

### 8.3 `docs/usage-schema.md`

§6.4'teki tablo; alan sözleşmesi; `ready:false` kayıtlarında `reason`.

### 8.4 `CHANGELOG.md` + `VERSION`

0.1.0 → 0.2.0. Girdiler: tek katalog dosyası, `--prefix`, repoya bağlanan
testler, sahte kolektörlerle network'süz test, CI, gömülü Python'un kaldırılması,
`XDG_STATE_HOME` düzeltmesi, ölü fallback'lerin temizlenmesi, **README'deki
yanlış vaatlerin düzeltilmesi**.

---

## 9. Riskler

| Risk | Etki | Azaltma |
|---|---|---|
| `prompt_flag` değerleri gerçek CLI'larla eşleşmiyor (config elle yazıldıysa) | Orta — agent açılmıyor | §5.1 tablosu mevcut koddan birebir çıkarıldı; Faz 1'de her agent `--help` ile doğrulanır. `check` geçersiz bayrak biçimini (ör. `-` ile başlamayan `prompt_flag`) yakalar |
| `install.sh --prefix` geriye uyumsuzluk yaratır | Düşük | `--prefix` opsiyonel; verilmediğinde **hiçbir yol değişmez**. Test 13 tam olarak bunu doğrular |
| 6 script'in `cachy-agent-agents` çağrısı yazması, ama `install.sh` bu yeni dosyayı kurmadan eski kurulumda çalışmaz | Orta | `install.sh` `src/bin/*` glob'uyla kopyalar, yeni dosya otomatik gider. Ama **mevcut kurulum kullanıcıda `install.sh` çalıştırmadan bozulur** — CHANGELOG'a "yeniden kurun" notu düşer |
| Config bozulursa menü boş görünür | Düşük | §5.2: parse hatası exit 1 + stderr; tüketiciler `|| true` ile yutar ama kullanıcı mesajı görür |
| CI'da `systemd-analyze verify` davranışı farklı | Düşük | smoke.sh bu komutun yokluğunda atlar (§7.6) |

## 10. Tanım — Bitti

Bu çalışma şunlar doğrulandığında bitti sayılır:

1. `src/` içinde 8 agent'ın hardcoded listesi **kalmaz** (`grep -rn 'agy claude codex'
   src/` → 0 eşleşme, `agents.conf` hariç).
2. `src/` içinde `python3 -c` gömülü komutu **kalmaz**.
3. `./tests/test.sh` temiz bir checkout'ta, kurulum yapmadan, ağa ve
   credential'e dokunmadan exit 0 verir.
4. `README.md` ve `README.tr.md` içinde kodla çelişen hiçbir iddia kalmaz.
5. `cachy-agent-agents check` geçerli bir config için exit 0, bozuk bir config
   için exit 1.
6. CI her push'ta yeşil.
7. `VERSION` = `0.2.0`, `CHANGELOG.md` gerçek değişiklikleri listeler.
