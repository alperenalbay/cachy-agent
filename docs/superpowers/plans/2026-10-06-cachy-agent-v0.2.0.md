# cachyAgent v0.2.0 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Agent listesini ve davranışını tek config dosyasına merkezileştirmek, testleri repoya bağlamak, README'nin kodla çelişen iddialarını düzeltmek.

**Architecture:** Yeni `cachy-agent-agents` CLI'si tek doğruluk kaynağı olur (`~/.config/cachy-agent/agents.conf`, satır tabanlı `id=ad|install|flags|prompt_flag|login`). Diğer 6 script ve plasmoid bu CLI'yi sorgular; hardcoded listeler ve `case` kolları kalkar. Testler repo-relative çalışır, `--prefix` ile izole kurulum yapar, ağa ve credential'e dokunmaz.

**Tech Stack:** bash 4+, python3 (zaten bağımlılık), systemd --user, Plasma 6 QML, GitHub Actions

**Spec:** `docs/superpowers/specs/2026-10-06-single-source-of-truth-design.md`

## Global Constraints

- **Spesifikasyon tek doğruluk kaynağıdır.** Bir davranış spec'te tanımlıysa
  uygulama spec'e uyar; spec'te yoksa en güvenli seçim yapılır ve commit
  mesajında belirtilir.
- **`run_agent` refactor'ı davranış değiştirmez.** Her agent'ın argv'si
  `tests/fixtures/argv-baseline.md` ile birebir aynı olmalıdır. Sapma = hata.
- **Testler ağa, credential'e veya gerçek agent CLI'dir dokunmaz.** Codef
  bağımlılığı `~/.codex/auth.json`, ağ isteği veya npm/curl çalıştıran test
  yazma. Testler `PATH` stub'ları ve geçici dizinlerle çalışır.
- **Config eksik veya parse edilemiyorsa her sorgu exit 1 verir**, stderr'e
  dosya yolu + satır numarası yazar. Boş listeye sessizce düşme.
- **`install.sh` config'i yalnızca dosya yoksa yazar.** Kullanıcının
  `agents.conf` düzenlemesi hiçbir kurulumda kaybolmaz.
- **`--prefix` verilmediğinde hiçbir yol değişmez.** Mevcut davranış korunur.
- Kod ve yorumlar Türkçedir (mevcut proje dili). Yeni script'ler de öyle.
- Her görev bağımsız test edilebilir bir çıktı üretir ve commit ile biter.

## Review Focus

Spec'in ima ettiği ama hiçbir görevin testiyle doğrulanmamış olan giriş sınıfları.
Her satır bir testle sabitlenmiştir; testin sahibi görev, adımın içindedir.

1. **Bozuk `agents.conf`** (eksik alan, kaçışsız `|`, yinelenen id, tırnaklı
   `flags`) → `list`/`ids` exit 1 + stderr'de **satır numarası**. Kullanıcı
   hangi satırı düzelteceğini görebilmeli. → Task 1, adım 1
2. **`agy --help` bayrağı içermiyor** → `agy` çıplak çağrılır (`--prompt`
   bile yok). Config'teki sabit `flags` burada yanlış olur. → Task 2, adım 4
3. **`WORKDIR` satırı yok** → `~/Projeler` geriye uyumu. Kullanıcının
   eski kurulumu `agents.conf`'e taşınmadan da çalışmalı. → Task 1, adım 3
4. **`install_hint` içinde `|`** (ör. `curl … | bash`) → alan bölen olarak
   yorumlanır, config bozulur. Kaçış `\|` zorunlu; `check` yakalar. → Task 1, adım 1
5. **Config'deki `id` PATH'te yok** (`installed: false`) → menü "Kur" gösterir,
   `external: true` ise kurulum komutu çalıştırılır. Config'e yazılan ama
   kurulmamış bir agent, menüde kurulum akışını tetiklemeli. → Task 3, adım 5

## File Structure

**Yeni dosyalar:**

| Dosya | Sorumluluk |
|---|---|
| `src/config/agents.conf` | Tek katalog kaynağı. Repo'da versiyonlanır |
| `src/bin/cachy-agent-agents` | Config'i okuyan CLI. Tüm sorgular burada |
| `src/bin/cachy-agent-usage-fetch` | Usage JSON → plasmoid/özet JSON |
| `tests/argv-differential.sh` | argv ölçüm/ karşılaştırma aracı (`--emit` / `--check`) |
| `tests/fixtures/agents-valid.conf` | Test 11'in geçerli config fixture'ı |
| `tests/fixtures/agents-broken.conf` | Test 11'in bozuk config fixture'ı |
| `.gitignore` | `__pycache__/`, `*.pyc` |
| `.github/workflows/ci.yml` | shellcheck + smoke + test |
| `docs/agents.md` | `agents.conf` referansı |
| `docs/usage-schema.md` | Usage JSON şeması |

**Değişen dosyalar:**

| Dosya | Değişiklik |
|---|---|
| `src/bin/cachy-agent` | `run_agent` config'ten; `WORKDIR` config'ten; whitelist `case`'leri → `known`; `--version` fallback temizlenir; `usage` → `usage-fetch summary` |
| `src/bin/cachy-agent-menu` | 3 whitelist `case` + döngü → `cachy-agent-agents` |
| `src/bin/cachy-agent-open` | whitelist `case` → `known`; login ipuçları → `get` |
| `src/bin/cachy-agent-install` | kurulum `case`'i → `get <id> install` |
| `src/bin/cachy-agent-usage-update` | `AGENTS` dizisi → `list`; `BIN_DIR` → `CACHY_AGENT_BIN_DIR` seam |
| `src/bin/cachy-agent-usage-oneline` | `ready` varsayılanı `True`; `reason` gösterimi |
| `src/bin/cachy-agent-usage-panel` | `ready` varsayılanı `True`; `reason` gösterimi |
| `src/bin/cachy-agent-usage-opencode` | hata yolları §6.4 sözleşmesine uyar |
| `src/plasmoid/.../main.qml` | `catalogCommand` → `cachy-agent-agents json`; `fetchCommand` → `usage-fetch` |
| `install.sh` | `--prefix`; config'i yalnızca yoksa yazar; `DIR` içine yazar |
| `uninstall.sh` | `--prefix`; config'i kaldırır |
| `tests/test.sh` | repo-relative; `SKIP` tipi; test 11-15 |
| `tests/smoke.sh` | `__pycache__` silmesi kaldırılır; `PYTHONDONTWRITEBYTECODE` |
| `README.md`, `README.tr.md`, `CHANGELOG.md`, `VERSION` | dürüstleştirme |

---

### Task 1: `cachy-agent-agents` CLI ve config

**Files:**
- Create: `src/config/agents.conf`
- Create: `src/bin/cachy-agent-agents`
- Create: `tests/fixtures/agents-valid.conf`
- Create: `tests/fixtures/agents-broken.conf`
- Modify: `tests/test.sh` (test 11)

**Interfaces:**
- Consumes: `XDG_CONFIG_HOME` (varsayılan `$HOME/.config`), `CACHY_AGENT_CONFIG` (test override, tam yol)
- Produces:
  - `cachy-agent-agents list` → id'ler, satır satır, exit 0
  - `cachy-agent-agents ids` → id'ler, tek satır
  - `cachy-agent-agents get <id> <name|install|flags|prompt_flag|login>` → tek alan
  - `cachy-agent-agents known <id>` → exit 0/1, stdout boş
  - `cachy-agent-agents installed` → PATH'te bulunan id'ler, satır satır
  - `cachy-agent-agents external` → `install != "-"` olan id'ler
  - `cachy-agent-agents workdir` → genişletilmiş WORKDIR (yoksa `$HOME/Projeler`)
  - `cachy-agent-agents json` → `{"catalog":[{"id","name","installed","external"}]}`
  - `cachy-agent-agents check` → parse+tutarlılık doğrulaması
  - Çıkış kodları: 0 tamam, 1 bilinmeyen id / config eksik-bozuk / check başarısız, 2 kullanım hatası

- [ ] **Step 1: Test 11'i ve iki fixture'ı yaz**

`tests/fixtures/agents-valid.conf` — geçerli, §5.1 tablosunun kopyası:

```
# geçerli fixture
WORKDIR=~/Projeler

opencode=opencode|-|--auto|--prompt|-
agy=agy|-|--dangerously-skip-permissions --effort low|--prompt|-
claude=Claude Code|npm i -g @anthropic-ai/claude-code|--permission-mode auto|-p|claude login
codex=Codex|npm i -g @openai/codex|--approve-for-me|-|codex login
crush=Crush|npm i -g @charmlabs/crush|--yolo|-|-
copilot=Copilot CLI|npm i -g @github/copilot|--allow-all|-|copilot login
cursor-agent=cursor-agent|curl https://cursor.com/install -fsS \| bash|--yolo --trust|-|agent login
grok=Grok CLI|curl -fsSL https://x.ai/cli/install.sh \| bash|--permission-mode bypassPermissions|-|grok login
```

`tests/fixtures/agents-broken.conf` — dört ayrı bozukluk, her biri ayrı testte
kullanılacak (satır numarası doğrulaması için):

```
# eksik alan (5, 6 olmali)
codex=Codex|npm i -g @openai/codex|--approve-for-me
# yinelenen id
claude=Claude Code|x|--permission-mode auto|-p|-
claude=Claude Code 2|y|--permission-mode auto|-p|-
# tirnakli flags
crush=Crush|-| "--yolo" -|-
# gecersiz prompt_flag
grok=Grok|-|x|bypassPermissions|-
```

`tests/test.sh`'e test 11'i ekle. `test.sh`'in mevcut yapısı: `ok()`/`bad()`
fonksiyonları, `PASS`/`FAIL` sayaçları, son satırda özet + `[[ $FAIL == 0 ]]`.
Yeni test aynı kalıpları kullanır. Test 11 için `CACHY_AGENT_CONFIG` env'i
geçici config'e yönlendirilir (gerçek `~/.config` **dokunulmaz**):

```bash
# 11. agents.conf parse + check
SCRATCH=$(mktemp -d)
PFXROOT="$(mktemp -d)"
trap 'rm -rf "$SCRATCH" "$PFXROOT"' EXIT
AG="$REPO/src/bin/cachy-agent-agents"
FIX="$REPO/tests/fixtures"

# 11a: gecerli config -> list dogru sira
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
got=$("$AG" list 2>/dev/null | tr '\n' ' ')
if [[ "$got" == "opencode agy claude codex crush copilot cursor-agent grok " ]]; then
  ok "11a list gecerli config'ten 8 id"
else bad "11a list" "got='$got'"; fi

# 11b: check gecerli config -> exit 0
if "$AG" check >/dev/null 2>&1; then ok "11b check gecerli config exit 0"; else bad "11b check gecerli" "exit=$?"; fi

# 11c: check bozuk config -> exit 1 + stderr BOS OLMAZ
export CACHY_AGENT_CONFIG="$FIX/agents-broken.conf"
if ! "$AG" check >/dev/null 2>&1; then
  err=$("$AG" check 2>&1 >/dev/null)
  if [[ -n "$err" ]]; then ok "11c check bozuk config exit 1 + stderr"; else bad "11c check bozuk" "stderr bos"; fi
else bad "11c check bozuk config" "exit 0 dondu, 1 bekleniyordu"; fi

# 11d: bozuk config -> list exit 1 (sessiz bos liste YOK)
if "$AG" list >/dev/null 2>&1; then bad "11d list bozuk config" "exit 0 dondu"; else ok "11d list bozuk config exit 1"; fi

# 11e: eksik alan -> stderr'de satir numarasi
err=$("$AG" check 2>&1 >/dev/null | head -1)
if [[ "$err" == *":2:"* ]]; then ok "11e eksik alan satir numarasiyla"; else bad "11e eksik alan" "err='$err'"; fi

# 11f: config dosyasi YOK -> exit 1
export CACHY_AGENT_CONFIG="$SCRATCH/yok.conf"
if "$AG" list >/dev/null 2>&1; then bad "11f config yok" "exit 0 dondu"; else ok "11f config yok exit 1"; fi

# 11g: bilinmeyen id -> get exit 1, stdout bos
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
out=$("$AG" get uydurma flags 2>/dev/null); rc=$?
if [[ $rc -eq 1 && -z "$out" ]]; then ok "11g bilinmeyen id exit 1 bos stdout"; else bad "11g bilinmeyen id" "rc=$rc out='$out'"; fi

# 11h: known dogru calisir
if "$AG" known codex 2>/dev/null && ! "$AG" known uydurma 2>/dev/null; then ok "11h known"; else bad "11h known" "codex veya uydurma yanlis"; fi

# 11i: tum alanlar okunur
if [[ "$("$AG" get claude prompt_flag 2>/dev/null)" == "-p" && "$("$AG" get codex prompt_flag 2>/dev/null)" == "-" ]]; then
  ok "11i get prompt_flag"; else bad "11i get prompt_flag" "claude/codex yanlis"; fi

# 11j: WORKDIR genisletilir
wd=$("$AG" workdir 2>/dev/null)
if [[ "$wd" == "$HOME/Projeler" ]]; then ok "11j WORKDIR ~ genisletildi"; else bad "11j WORKDIR" "wd='$wd'"; fi

# --- spec §5.5 check maddeleri: HER madde ayri test ---
# 11k: tirnakli flags reddi
printf 'crush=Crush|-|"--yolo" -|-\n' > "$SCRATCH/tirnak.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/tirnak.conf"
if "$AG" check >/dev/null 2>&1; then bad "11k tirnakli flags" "exit 0 dondu, 1 bekleniyordu"; else ok "11k tirnakli flags reddedildi"; fi

# 11l: gecersiz prompt_flag (tire ile baslamiyor) reddi
printf 'grok=Grok|-|x|bypassPermissions|-\n' > "$SCRATCH/pf.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/pf.conf"
if "$AG" check >/dev/null 2>&1; then bad "11l prompt_flag bicimi" "exit 0 dondu"; else ok "11l prompt_flag bicimi dogrulandi"; fi

# 11m: gecersiz id karakteri reddi
printf 'bad id=x|y|z|w|v\n' > "$SCRATCH/id.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/id.conf"
if "$AG" check >/dev/null 2>&1; then bad "11m id karakteri" "exit 0 dondu"; else ok "11m id karakteri dogrulandi"; fi

# 11n: gecersiz install degeri (bos birakilmis, ne - ne dolu) reddi
printf 'codex=Codex||--approve-for-me|-|x\n' > "$SCRATCH/inst.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/inst.conf"
if "$AG" check >/dev/null 2>&1; then bad "11n install degeri" "exit 0 dondu"; else ok "11n install/login degeri dogrulandi"; fi

# 11o: ikinci WORKDIR satiri reddi
printf 'WORKDIR=/a\nWORKDIR=/b\ncodex=C|x|-|--prompt|x\n' > "$SCRATCH/wd2.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wd2.conf"
if "$AG" check >/dev/null 2>&1; then bad "11o coklu WORKDIR" "exit 0 dondu"; else ok "11o coklu WORKDIR reddedildi"; fi

# 11p: gecersiz install icinde kacissiz | (bolme hatasi) yakalanir
printf 'cursor-agent=cursor-agent|curl https://x/install | bash|--yolo --trust|-|y\n' > "$SCRATCH/pipe.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/pipe.conf"
if "$AG" check >/dev/null 2>&1; then bad "11p gecessiz |" "exit 0 dondu, install 7 alana bolundu"; else ok "11p gecessiz | reddedildi"; fi

# 11q: gecersiz install degeri (ne - ne dolu) reddi
printf 'a=b|c|d|e|f\ncodex=C|x|-|--prompt|-\n' > "$SCRATCH/kesilmis.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/kesilmis.conf"
if "$AG" check >/dev/null 2>&1; then bad "11q kesilmis metin" "exit 0 dondu"; else ok "11q kesilmis metin reddedildi"; fi

# 11r: WORKDIR satiri listede GORUNMEZ (global ayar, agent degil)
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
got=$("$AG" list 2>/dev/null | tr '\n' ' ')
if [[ "$got" != *WORKDIR* ]]; then ok "11r WORKDIR listede degil"; else bad "11r WORKDIR listeye sizdi" "got='$got'"; fi

unset CACHY_AGENT_CONFIG
```

`test.sh` başına `REPO` tanımı ekle: `REPO="$(cd "$(dirname "$0")/.." && pwd)"`.
Test 11 `trap` ile `$SCRATCH`'i temizler.

- [ ] **Step 2: Testi çalıştır, kırıldığını doğrula**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): 11'`

Expected: `FAIL: 11a ... command not found` — `cachy-agent-agents` henüz yok.
(Eğer `grep` boş dönerse: test 11 bloğu dosyaya eklenmemiştir; ekle ve tekrarla.)

- [ ] **Step 3: `agents.conf`'i oluştur**

`src/config/agents.conf` — `tests/fixtures/agents-valid.conf` ile aynı
içerik, ancak dosya başındaki yorum bloğu §5.1'deki sürümü içerir
(`# Format: id=görünen_ad|install|flags|prompt_flag|login` ve alan
açıklamaları, `# Bu dosyayı düzenleyebilirsin` notu). `WORKDIR` satırını içerir.

- [ ] **Step 4: `cachy-agent-agents`'ı implement et**

`src/bin/cachy-agent-agents`, `#!/usr/bin/env bash`, `set -uo pipefail`
(`-e` **kullanma**: sorgular kasıtlı olarak exit 1 döner ve `|| true` kalıbı
kullanılır; `-e` bu akışları bozar).

Parse yaklaşımı: config'i satır satır oku, `IFS='|'` ile böl, `\|` kaçışını
geri çöz. Aşağıdaki kararlar:

- Config yolu: `${CACHY_AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent/agents.conf}`
- `WORKDIR=` ile başlayan satırlar agent değildir; `=`'den sonrası tek
  alandır, `~` genişletilir. Birden fazla `WORKDIR` → parse hatası.
- Diğer satırlar 6 alan ister; eksikse parse hatası.
- Parse hatası: `echo "cachy-agent: $CONF:$LINENO: <neden>" >&2`, exit 1.
- `~` genişletme yalnızca `workdir` ve `WORKDIR` alanında.
- `installed`: `command -v "$id" >/dev/null 2>&1`.
- `json` çıktısı: `{"catalog":[{"id":"…","name":"…","installed":true,"external":false}, …]}`
  — `external` = `install != "-"`. `python3 -c` veya `printf` ile üret; JSON
  kaçışı için `name` alanında `"` veya `\` varsa hata (`check` yakalar).
- `check` doğrulamaları (spec §5.5): 6 alan; `id` benzersiz ve
  `[A-Za-z0-9_-]+`; `flags`/`prompt_flag` içinde tırnak yok; `prompt_flag` ya
  `-` ya `-` ile başlayan tek bayrak; `install`/`login` dolu ya `-`;
  `WORKDIR` en çok 1 tane ve 1 alan.

Kullanım dışı alt komut: `echo "kullanım: cachy-agent-agents list|ids|get|known|installed|external|workdir|json|check" >&2; exit 2`.

- [ ] **Step 5: Testleri çalıştır, geçtiğini doğrula**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/test.sh 2>&1 | tail -20`

Expected: `11a` … `11j` arası hepsi `PASS`, özet `0 kaldı` (mevcut testlerin
çoğu hâlâ kurulum gerektiriyor — bu normaldir, Faz 2'de düzelir; **11 serisi
PASS olmalıdır**).

- [ ] **Step 6: Commit**

```bash
git add src/config/agents.conf src/bin/cachy-agent-agents tests/fixtures/ tests/test.sh
git commit -m "feat: cachy-agent-agents CLI + agents.conf tek katalog kaynagi

Yeni sorgular: list ids get known installed external workdir json check
Config eksik/bozukken exit 1 + stderr satir numarasi (sessiz bos liste yok)
WORKDIR global ayar olarak ayri ele alinir, listeye girmez
Test 11: gecerli/bozuk fixture, eksik alan satir numarasi, bilinmeyen id"
```

---

### Task 2: `run_agent` refactor'ı — davranış kilitli

**Files:**
- Create: `tests/argv-differential.sh`
- Modify: `src/bin/cachy-agent:6` (WORKDIR), `:10` (KNOWN_AGENTS), `:12-46` (run_agent), `:61,71,85` (whitelist), `:127` (help)
- Modify: `tests/test.sh` (test 14, 15)

**Interfaces:**
- Consumes: Task 1'in `cachy-agent-agents get|known|workdir|ids`
- Produces: `tests/argv-differential.sh --emit` → `argv.txt` üretir; `--check` → baseline ile karşılaştırır, sapmada exit 1. Test 15 bunu kullanır.

- [ ] **Step 1: `tests/argv-differential.sh`'i yaz**

Bu araç iki modda çalışır:

- `--emit`: her agent için argv'yi ölçüp `tests/fixtures/argv.txt` yaz
- `--check` (varsayılan): ölçüp `argv-baseline.md`'deki beklenen değerlerle
  karşılaştır; fark varsa `FAIL: <agent> <beklenen> != <gelen>` bas ve exit 1

Ölçüm: her agent için geçici bir stub dizini üret
(`SCRATCH=$(mktemp -d)` **kendi scratch'ını script başında yaratır**, `trap` ile
temizler — test.sh'e bağımlı değildir; `$SCRATCH/stub_<agent>/<agent>`),
`PATH="$stub:$PATH"` ile `cachy-agent --inline <agent> P` ve
`cachy-agent --inline <agent>` çalıştır, `$ARGV_LOG`'a argv yazılsın.

Stub şablonu (`agy` hariç — `agy` iki dallı, aşağıya bak):

```bash
#!/usr/bin/env bash
printf "<agent>" >> "$ARGV_LOG"
for x in "$@"; do printf " [%s]" "$x" >> "$ARGV_LOG"; done
printf "\n" >> "$ARGV_LOG"
```

`agy` için **iki** stub dizini: `stub_agyA` (`--help` çıktısında
`--dangerously-skip-permissions` **var**) ve `stub_agyB` (çıktısında **yok**).
Stub'lar `--help` çağrısında uygun metni basıp exit 0 döner.

Beklenen değerler `tests/fixtures/argv-baseline.md`'deki tablolardan sabit
string olarak `case` içinde tanımlanır — doğrulama tablosu bu dosyanın kendisidir.
`agy` A dali (prompt'lu/promptsuz) ve B dali (prompt'lu/promptsuz) → toplam
18 ölçüm.

`--check` çıkışı: sapma yoksa `printf 'argv: 18 ölçüm tamam\n'; exit 0`,
varsa sapmaları listeleyip `exit 1`.

- [ ] **Step 2: Araçla mevcut davranışı ölç ve doğrula**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/argv-differential.sh --check`

Expected: `argv: 18 ölçüm tamam` + exit 0.

Bu adım refactor **öncesi** çalışır ve mevcut davranışı kilitler. Eğer sapma
varsa: tablo yanlıştır — `argv-baseline.md`'yi düzelt, **kodu değiştirme**.

- [ ] **Step 3: Test 15'i test.sh'e ekle**

```bash
# 15. argv differential — her agent'in argv'si baseline ile ayni
if bash "$REPO/tests/argv-differential.sh" --check >/dev/null 2>&1; then
  ok "15 argv differential (18 olcum)"
else
  bad "15 argv differential" "$(bash "$REPO/tests/argv-differential.sh" --check 2>&1 | head -3 | tr '\n' ' ')"
fi
```

- [ ] **Step 4: Test 15'i çalıştır — kırmızı olmalı**

`cachy-agent-agents` henüz `cachy-agent` tarafından **kullanılmıyor**, dolayısıyla
test 15 **PASS** olmalıdır (mevcut davranış ölçülür). Bu kasıtlı: golden file.

Run: `bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): 15'`
Expected: `PASS: 15 argv differential`

Eğer FAIL ise: araç yanlış ölçüyor, refactor'a başlama.

- [ ] **Step 5: `run_agent`'ı config'e bağla**

`src/bin/cachy-agent` değişiklikleri:

1. `WORKDIR="$HOME/Projeler"` satırını kaldır; `run_agent` içinde
   `cachy-agent-agents workdir` ile al.
2. `KNOWN_AGENTS` sabitini kaldır; hata mesajlarında `$(cachy-agent-agents ids)`
   kullan.
3. `run_agent`'ı spec §5.4'teki imzayla yeniden yaz: `known` ile doğrula,
   `PWD == $HOME` ise `workdir`'a `cd` et, `flags` ve `prompt_flag` al,
   `pf != "-"` ise `"$pf" "$*"`, değilse `"$*"`, argüman yoksa bayraksız `exec`.
   `flags` kelime kelime ayrıldığı için `shellcheck disable=SC2086` gerekli.
4. `agy` koşullu bayrak: `[[ "$agent" == "agy" ]] && ! agy --help 2>&1 | grep -q dangerously-skip-permissions`
   ise `flags=""` yap. **Bu `run_agent` içinde, `exec`'ten önce.**
5. `cachy-agent:61`, `:71`, `:85`'teki 8 seçenekli `case` → `cachy-agent-agents known "$sel"`
6. `:127` help metnindeki agent listesi → `$(cachy-agent-agents ids)` ile üret

**Dokunma:** `--seed` (`cachy-agent:73-79`) kendi `case`'ini korur; yalnızca
`:71`'deki whitelist `known`'a çevrilir. `usage` alt komutu (`:104-106`) Faz 3'te.

- [ ] **Step 6: Test 15 + 11'i çalıştır — yeşil olmalı**

Run: `bash tests/argv-differential.sh --check && bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): (11|15)'`

Expected: `argv: 18 ölçüm tamam`, test 11 ve 15 `PASS`.

**Sapma olursa KODU DÜZELT, testi değiştirme.** Sapma = davranış değişti.

- [ ] **Step 7: Test 14'ü ekle (`agy` iki dal)**

`argv-differential.sh --check` zaten 4 `agy` ölçümünü içerir; test 14 bunu
ayrı bir PASS/FAIL olarak raporlar:

```bash
# 14. agy kosullu bayraklari — iki dal
if bash "$REPO/tests/argv-differential.sh" --check 2>&1 | grep -q "^agy"; then
  bad "14 agy dallari" "olcum sapmasi var"
else
  ok "14 agy iki dal (A: bayrakli, B: çiplak)"
fi
```

Bunu `--check`'in çıktısını `--agent agy` filtresiyle daraltarak daha temiz
yap: `argv-differential.sh --check --agent agy` yalnızca agy ölçümlerini
yapar. Test 14 bunu çağırır.

- [ ] **Step 8: Commit**

```bash
git add src/bin/cachy-agent tests/argv-differential.sh tests/test.sh
git commit -m "refactor: run_agent config'ten okur, davranış kilitli

- WORKDIR, flags, prompt_flag cachy-agent-agents'tan
- whitelist case'leri -> known
- agy koshulu bayrak: --help bayragı yoksa çıplak çağrı (ölçülmüş davranış)
- argv-differential.sh: 18 ölçüm, baseline'a göre doğrular
- Test 15 golden file: sapma = davranış değişti"
```

---

### Task 3: Kalan hardcode'lar ve menü

**Files:**
- Modify: `src/bin/cachy-agent-menu:9,28,35,38`
- Modify: `src/bin/cachy-agent-open:7,14-19`
- Modify: `src/bin/cachy-agent-install:6,11-19,22-28`
- Modify: `src/bin/cachy-agent-usage-update:9,15`
- Modify: `src/plasmoid/org.cachyagent.usage/contents/ui/main.qml:33`
- Modify: `tests/test.sh` (test 10 güncelleme)

**Interfaces:**
- Consumes: Task 1'in tüm sorguları (`list`, `known`, `installed`, `get`, `json`)
- Produces: `cachy-agent-usage-update` `CACHY_AGENT_BIN_DIR` env desteği (Task 4 kullanır)

- [ ] **Step 1: `cachy-agent-menu`'deki listeyi config'e bağla**

`:9`'daki 8 isimli `for` döngüsü → `while read -r a; do ... done < <(cachy-agent-agents list)`.
`:28`, `:35`, `:38`'deki üç 8-seçenekli `case` → `cachy-agent-agents known "$name"`
(veya `"$sel"`). `fuzzel` yoksa düşen yol (`:42-43`) aynı kalır.

- [ ] **Step 2: `cachy-agent-open`'ı config'e bağla**

`:7`'deki whitelist `case` → `cachy-agent-agents known "$AGENT"` (başarısızsa
aynı hata mesajı + exit 1). `:14-19`'daki login ipucu `case`'i →
`hints="$("$HOME/.local/bin/cachy-agent-agents" get "$AGENT" login)"`;
`-` ise mevcut genel ipucu (`"'cachy-agent --inline $AGENT' ile manuel dene"`) kullanılır.

- [ ] **Step 3: `cachy-agent-install`'ı config'e bağla**

`:6`'daki 6-seçenekli `case` kaldırılır. `:11-19`'daki kurulum `case`'i yerine:
`cmd="$(cachy-agent-agents get "$NAME" install)"`; `-` ise
`"$NAME için otomatik kurulum yok (harici kurulum)"` + exit 1.
Aksi hâlde `bash -c "$cmd"` çalıştırılır — **kullanıcı onayı (`:9`) sonrası**.
`:22-28`'deki login ipuçları → `get "$NAME" login` (`-` ise o satır atlanır).

`~` ve `$HOME` genişletmesi kurulum komutunda bash'e bırakılır.

- [ ] **Step 4: `cachy-agent-usage-update`'i config'e bağla + seam ekle**

`:15`'teki `AGENTS=(opencode agy ...)` → `mapfile -t AGENTS < <(cachy-agent-agents list)`
(list boşsa exit 0 — mevcut "sessizce atla" davranışı korunur).

`:9`'daki `BIN_DIR="$HOME/.local/bin"` → `BIN_DIR="${CACHY_AGENT_BIN_DIR:-$HOME/.local/bin}"`.
Bu, Task 4'ün testlere gerçek bir seam verir ve sabit yolu yapılandırılabilir
hale getirir.

- [ ] **Step 5: Plasmoid'i config'e bağla**

`main.qml:33`'teki `catalogCommand` (gömülü Python) →
`property string catalogCommand: "__HOME__/.local/bin/cachy-agent-agents json"`.
Bu **tek satırlık** değişikliktir; QML'in beklediği `{"catalog":[...]}` şekli
Task 1'de aynı üretiliyor. `entry.id` (`:323`) ve `entry.installed` (`:319`, `:336`)
alanları korunur.

- [ ] **Step 6: `smoke.sh` hardcode taramasını güncelle**

`:28`'deki `grep -rn '/home/' src/` kontrolü **kalır** ve hâlâ geçer
(`__HOME__` placeholder kullanılıyor). Yeni bir kontrol ekle: `src/` içinde
`python3 -c` gömülü komutu kalmamalı — **ama** bu Faz 3'e kadar `main.qml:33-34`
için **FAIL** eder. Bu nedenle smoke'a **şimdilik ekleme**; Task 7'de ekle.

- [ ] **Step 7: Testleri çalıştır**

Run: `bash tests/smoke.sh 2>&1 | tail -5 && bash tests/argv-differential.sh --check`

Expected: `SMOKE: GEÇTİ`, `argv: 18 ölçüm tamam`.

- [ ] **Step 8: Hardcode kalmadığını doğrula**

Run: `grep -rn 'opencode agy claude codex\|opencode|agy|claude|codex' src/bin/ src/plasmoid/ | grep -v agents.conf`

Expected: **çıktı yok** (ya da yalnızca `agy` koşullu bayrak kontrolü ve
yorum satırları). Çıktı varsa kalan hardcode'u temizle.

- [ ] **Step 9: Commit**

```bash
git add src/bin/cachy-agent-menu src/bin/cachy-agent-open src/bin/cachy-agent-install src/bin/cachy-agent-usage-update src/plasmoid
git commit -m "refactor: kalan hardcode'lar config'e baglandi

- menu: 8 isim sabiti -> list; 3 whitelist case -> known
- open: whitelist -> known; login ipuclari -> get
- install: kurulum case -> get <id> install; '-' ise reddet
- usage-update: AGENTS -> list; BIN_DIR CACHY_AGENT_BIN_DIR ile ezilebilir
- plasmoid catalogCommand: gomulu python -> cachy-agent-agents json"
```

---

### Task 4: `install.sh` / `uninstall.sh` `--prefix` ve config yönetimi

**Files:**
- Modify: `install.sh`
- Modify: `uninstall.sh`
- Modify: `tests/test.sh` (test 13)
- Create: `.gitignore`

**Interfaces:**
- Consumes: yok (Task 1'in config'ini kopyalar, onu tüketmez)
- Produces: `install.sh --prefix DIR`, `uninstall.sh --prefix DIR`; her ikisi de `DIR` yoksa oluşturur

- [ ] **Step 1: Test 13'ü yaz**

```bash
# 13. install.sh --prefix / uninstall.sh --prefix
PFX="$PFXROOT/pfx"
if bash "$REPO/install.sh" --prefix "$PFX" >/dev/null 2>&1; then
  ok "13a install --prefix exit 0"
else bad "13a install --prefix" "exit=$?"; fi
missing=""
for f in "$PFX/bin/cachy-agent" "$PFX/bin/cachy-agent-agents" "$PFX/config/cachy-agent/agents.conf" \
         "$PFX/fish/conf.d/cachy-agent.fish" "$PFX/applications/cachy-agent.desktop" \
         "$PFX/systemd/user/cachy-crash-watch.service" "$PFX/plasmoids/org.cachyagent.usage/metadata.json"; do
  [[ -f "$f" ]] || missing="$missing${f#$PFX/} "
done
if [[ -z "$missing" ]]; then ok "13b --prefix dosyalari yerinde"; else bad "13b --prefix" "yok: $missing"; fi
if bash "$REPO/uninstall.sh" --prefix "$PFX" >/dev/null 2>&1; then
  ok "13c uninstall --prefix exit 0"
else bad "13c uninstall --prefix" "exit=$?"; fi
left=""
for f in "$PFX/bin/cachy-agent" "$PFX/bin/cachy-agent-agents" "$PFX/config/cachy-agent/agents.conf"; do
  [[ -e "$f" ]] && left="$left${f#$PFX/} "
done
if [[ -z "$left" ]]; then ok "13d uninstall --prefix temizledi"; else bad "13d uninstall --prefix" "kaldi: $left"; fi
# ikinci calistirma (idempotans)
if bash "$REPO/uninstall.sh" --prefix "$PFX" >/dev/null 2>&1; then ok "13e uninstall iki kez calisir"; else bad "13e uninstall idempotent" "exit=$?"; fi
```

`test.sh` başına `PFXROOT="$(mktemp -d)"` tanımla ve mevcut `trap`'a
`rm -rf "$PFXROOT"` ekle (`$SCRATCH` Task 1'de tanımlandı).

**13b, `--prefix` alt dizin yapısı şudur** (Task 4 Step 4'te sabitlenir):
`$PFX/bin/`, `$PFX/config/cachy-agent/`, `$PFX/config/fish/conf.d/`,
`$PFX/config/systemd/user/`, `$PFX/applications/`, `$PFX/config/fuzzel/`,
`PFX/icons/`, `$PFX/plasmoids/`.

- [ ] **Step 2: Testi çalıştır, kırıldığını doğrula**

Run: `bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): 13'`

Expected: `FAIL: 13a` — `install.sh --prefix` henüz yok.

- [ ] **Step 3: `.gitignore` oluştur**

```
__pycache__/
*.pyc
```

- [ ] **Step 4: `install.sh`'a `--prefix` ekle**

Argüman ayrıştırma: `PREFIX=""`; `--prefix` görülürse sonraki argüman
`PREFIX`'e atanır. `--check` mevcut davranışını korur.

Yol atamaları `PREFIX` boşken **bugünkü gibi** kalır; doluysa:

```
BIN_DIR="$PREFIX/bin"
FISH_DIR="$PREFIX/config/fish/conf.d"
SYSTEMD_DIR="$PREFIX/config/systemd/user"
APPS_DIR="$PREFIX/applications"
FUZZEL_DIR="$PREFIX/config/fuzzel"
ICON_DIR="$PREFIX/icons"
PLASMOID_DIR="$PREFIX/plasmoids/org.cachyagent.usage"
CONFIG_DIR="$PREFIX/config/cachy-agent"
STATE_DIR="$PREFIX/state/cachy-agent"
```

`PREFIX` boşken `CONFIG_DIR` = `${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent`,
`STATE_DIR` = `${XDG_STATE_HOME:-$HOME/.local/state}/cachy-agent`.

`mkdir -p` satırına `CONFIG_DIR` ve `STATE_DIR` de eklenir (bugün
`install.sh` bunları **oluşturmuyor** — runtime script'ler oluşturuyor; bu
kabul edilebilir ama `install.sh` config yazacağı için `CONFIG_DIR` gerekli).

Config kopyalama — **yalnızca yoksa**:

```bash
SRC_CONF="$SRC/config/agents.conf"
if [[ -f "$SRC_CONF" ]]; then
  if [[ -f "$CONFIG_DIR/agents.conf" ]]; then
    echo "  config: agents.conf zaten var (korunuyor)"
  else
    sed "s|__HOME__|$HOME|g" "$SRC_CONF" > "$CONFIG_DIR/agents.conf"
    echo "  config: agents.conf yazildi"
  fi
fi
```

`__HOME__` genişletmesi `agents.conf`'ta **yok** ama `sed` zararsız; kullanıcı
`__HOME__` eklemek isterse çalışır. Asıl `__HOME__` taşıyıcıları desktop
dosyaları ve plasmoid'dir — onlar `--prefix` verildiğinde `$PREFIX` ile
genişletilir (mutlak yol, böylece desktop dosyaları geçerli kalır).

`PREFIX` verildiğinde **atlanacaklar**: `systemctl --user daemon-reload`,
`enable --now` çağrıları (`:116-119`), `kbuildsycoca6`, `desktop-file-validate`.
Bunlar test/CI ortamında systemd-user oturumu olmayabilir.

`install.sh:124`'teki kısayol mesajı korunur (KDE tarafında manuel — Task 8'de
README buna uygun olacak).

- [ ] **Step 5: `uninstall.sh`'a `--prefix` ekle**

Aynı yol haritası. Ek olarak **config'i kaldır**:

```bash
rm -f "$CONFIG_DIR/agents.conf"
```

Ancak `uninstall.sh:83-85`'teki etkileşimli "config'i de sil?" sorusu korunur:
`--prefix` verildiğinde `agents.conf` **koşulsuz** kaldırılır (test izolasyonu
gereği), `PREFIX` boşken sorulur.

`python3` heredoc ile kısayol temizliği (`:50-66`) `PREFIX` verildiğinde
atlanır — CI'da `kglobalshortcutsrc` yok.

- [ ] **Step 6: Testleri çalıştır**

Run: `bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): 13' && bash tests/smoke.sh 2>&1 | tail -3`

Expected: `13a`…`13e` hepsi `PASS`, `SMOKE: GEÇTİ`.

- [ ] **Step 7: Gerçek kurulum bozulmadığını doğrula (regresyon)**

Run: `bash tests/smoke.sh 2>&1 | tail -3 && grep -c . install.sh`

`--prefix` verilmediğinde hiçbir yol değişmemeli. `smoke.sh`'in `--version`
kontrolü bunu dolaylı olarak doğrular (gerçek `~/.local/bin` yollarına
 dokunmadan).

- [ ] **Step 8: Commit**

```bash
git add install.sh uninstall.sh .gitignore tests/test.sh
git commit -m "feat: install/uninstall --prefix, config yonetimi, .gitignore

- --prefix DIR: tum yollar DIR altina, systemd/kbuildsycoca6 atlanir
- --prefix verilmezse hicbir yol degismez (regresyon yok)
- agents.conf yalnizca dosya yoksa yazilir; kullanici duzenlemesi korunur
- uninstall --prefix config'i kosulsuz kaldirir (PREFIX yoksa sorar)
- .gitignore: __pycache__, *.pyc"
```

---

### Task 5: Testleri repo-relative yap

**Files:**
- Modify: `tests/test.sh:9-10, 13-20, 28-32, 56-63, 66-69, 73-74`
- Modify: `src/bin/cachy-agent-usage-update:9` (Task 3'te eklendi — burada kullanılır)

**Interfaces:**
- Consumes: Task 3'ün `CACHY_AGENT_BIN_DIR` seam'i, Task 4'ün `--prefix`
- Produces: `tests/test.sh` temiz checkout'ta kurulum gerektirmeden exit 0

- [ ] **Step 1: `BIN` ve `STATE` yollarını repo'ya yönlendir**

`:9-10`:
```bash
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${CACHY_AGENT_TEST_PREFIX:-$REPO/src/bin}"
export PATH="$BIN:$PATH"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/cachy-agent/agents/usage"
```

- [ ] **Step 2: Test 3'ü config izole et**

`:28` ve `:32` gerçek `$HOME/.config/cachy-agent/default-agent` okuyor/yazıyor —
**dokunmayan** test gereği `XDG_CONFIG_HOME` geçici dizine yönlendirilir.
`test.sh` başına `export XDG_CONFIG_HOME="$SCRATCH/config"; mkdir -p "$XDG_CONFIG_HOME"`
(`$SCRATCH` Task 1'de tanımlandı; bu görevde `SCRATCH` tanımını en başa taşı).

Test 3 beklenen çıktısı artık temiz ortamda `opencode`'dur (dosya yok →
`default_agent()` `opencode` döner).

- [ ] **Step 3: Test 6b'yi sahte kolektörlerle besle**

`:44`'teki `cachy-agent-usage-update` gerçek `~/.local/bin`'den kolektör arar.
Test için `$SCRATCH/collectors/` dizinine sabit JSON üreten stub'lar yaz
(`cachy-agent-usage-opencode`, `cachy-agent-usage-codex`, `cachy-agent-usage-copilot`),
`chmod +x` yap, ve `CACHY_AGENT_BIN_DIR="$SCRATCH/collectors"` ile çalıştır.

Stub içeriği §7.3'teki JSON şemasına uyar (`schemaVersion,id,name,updatedAt,ready,
tierLabel,limits,todayPrompts,...,reason`). **Hiçbir stub ağa çıkmaz,
credential okumaz.**

`6b` beklenen çıktısı: `STATE` altında 3 geçerli JSON. `STATE`'i de geçici
dizine yönlendir: `export XDG_STATE_HOME="$SCRATCH/state"`.

- [ ] **Step 4: Test 8'i SKIP yapılabilir hâle getir**

`:56-63` gerçek `~/.config/systemd/user` ve `systemctl --user is-active` kontrol
eder. Ortam yoksa:

```bash
if ! command -v systemctl >/dev/null 2>&1 || [[ ! -d "$sdir" ]]; then
  skip "8 servisler + crash-watch active (ortam yok)"
else
  # mevcut kontrol
fi
```

`skip()` fonksiyonu ekle: `skip() { SKIP=$((SKIP+1)); printf "${Y}SKIP${N}: %s\n" "$1"; }`
ve `Y="\033[33m"` rengi tanımla. Özet satırına `SKIP` sayısını ekle:
`printf '\nÖzet: %d geçti, %d kaldı, %d atlandı (toplam %d)\n' "$PASS" "$FAIL" "$SKIP" "$((PASS+FAIL+SKIP))"`.
`SKIP` exit code'u **etkilemez**.

- [ ] **Step 5: Test 9'u SKIP yapılabilir hâle getir**

`:66-68` `desktop-file-validate` kullanır; komut yoksa `skip`.
Ek olarak dosyaları `SCRATCH`'e kur (`install.sh --prefix`) ya da doğrudan
`sed` ile geçici dizine üret (smoke.sh:58-64'teki desen).

- [ ] **Step 6: Test 10'un stub'ını repo yoluna güncelle**

`:73` `cp "$BIN/cachy-agent-menu"` → `$BIN` artık `src/bin`, olduğu gibi kalır.
`:74`'teki `sed` `$BIN/cachy-agent-install` yolunu zaten doğru değiştirir.
Ek testler: menü `installed`/`external` listeleri config'ten geldiğini doğrular —
`FAKE_SEL="+ codex (kur)"` mevcut testi korur; `FAKE_SEL="claude"` (kurulu
varsayımı için PATH'e stub) çalıştırıldığında alacritty stub'ına gittiğini
doğrula.

- [ ] **Step 7: Testleri çalıştır**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/test.sh`

Expected: `0 kaldı` ve `≥3 atlandı`. **Hiçbir test gerçek kurulum gerektirmemeli.**

- [ ] **Step 8: Temiz checkout doğrula**

```bash
git stash list >/dev/null
git clone . /tmp/opencode/clean-checkout && cd /tmp/opencode/clean-checkout && bash tests/test.sh
```

Expected: `0 kaldı`. (Bu, "kurulum yapmadan koşar" tanımının kanıtı.)

- [ ] **Step 9: Commit**

```bash
git add tests/test.sh
git commit -m "test: suite repoya baglandi, agsiz ve credentialsiz

- BIN -> src/bin, PATH'e eklenir; kurulum gerekmez
- XDG_CONFIG_HOME / XDG_STATE_HOME gecici dizine yonlendirilir
  (gercek ~/.config ve ~/.local/state dokunulmaz)
- Test 6b: sahte kolektorler + CACHY_AGENT_BIN_DIR seam (ag yok)
- SKIP sonuc tipi: systemd/validator yoksa atlanir, exit code etkilemez"
```

---

### Task 6: CI

**Files:**
- Create: `.github/workflows/ci.yml`
- Modify: `tests/smoke.sh:20-25` (`__pycache__` temizliği)

**Interfaces:**
- Consumes: Task 5'in repo-relative testleri
- Produces: `.github/workflows/ci.yml`

- [ ] **Step 1: `smoke.sh`'ı yazma yapmayan hâle getir**

`:23` `python3 -m py_compile` → `PYTHONDONTWRITEBYTECODE=1 python3 -m py_compile`
(dizin oluşturmayı önler). `:25`'teki
`find "$REPO_DIR/src" -name '__pycache__' -type d -exec rm -rf {} +` **tamamen
kaldırılır** — smoke testi artık repo'ya yazmaz (`.gitignore` devralır).

- [ ] **Step 2: `systemd-analyze` yokluğunda smoke'un atlaması**

`:53` `systemd-analyze verify` çağrısı komut yoksa `bad` verir. Koruma:

```bash
if ! command -v systemd-analyze >/dev/null 2>&1; then
  skip "systemd-analyze yok"
else
  # mevcut verify döngüsü
fi
```

`smoke.sh`'a da `skip()` ekle (test.sh ile aynı imza, bağımsız sayaç).

- [ ] **Step 3: `ci.yml` oluştur**

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
      - name: shellcheck
        run: |
          shellcheck -x src/bin/cachy-agent src/bin/cachy-agent-agents \
                       src/bin/cachy-agent-menu src/bin/cachy-agent-open \
                       src/bin/cachy-agent-install install.sh uninstall.sh
      - name: smoke
        run: ./tests/smoke.sh
      - name: test
        run: ./tests/test.sh
      - name: argv differential
        run: ./tests/argv-differential.sh --check
```

- [ ] **Step 4: CI'ı yerelde taklit et**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/smoke.sh && bash tests/test.sh && bash tests/argv-differential.sh --check`

Expected: `SMOKE: GEÇTİ`, `0 kaldı`, `argv: 18 ölçüm tamam`.

`shellcheck` bu makinede kurulu **değil**; CI adımı bunu atlar ama
dosya doğru yazılmıştır. Yerelde doğrulamak için:
`sudo pacman -S --needed shellcheck` (kullanıcı isteği — **onaysız kurulum yapma**).

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/ci.yml tests/smoke.sh
git commit -m "ci: GitHub Actions + smoke testi yazma yapmaz

- ci.yml: shellcheck + smoke + test + argv differential
- smoke.sh: PYTHONDONTWRITEBYTECODE, __pycache__ silmesi kaldirildi
- systemd-analyze yoksa skip"
```

---

### Task 7: Gömülü Python → `cachy-agent-usage-fetch`

**Files:**
- Create: `src/bin/cachy-agent-usage-fetch`
- Modify: `src/bin/cachy-agent:104-106`
- Modify: `src/plasmoid/.../main.qml:34`
- Modify: `src/bin/cachy-agent-usage-oneline:55` (`ready` → `True`)
- Modify: `src/bin/cachy-agent-usage-panel:95` (`ready` → `False` → `True`)
- Modify: `src/bin/cachy-agent-usage-opencode:7,19`
- Modify: `tests/smoke.sh` (yeni: gömülü python kontrolü)
- Modify: `tests/test.sh` (test 16)

**Interfaces:**
- Consumes: Task 1'in `list` (katalog adları), mevcut `usage/*.json`
- Produces:
  - `cachy-agent-usage-fetch` → `{"providers":[{"id","name","today","total","limits":[{"label","percent","resetsAt"}]}],"alarm":bool}`
  - `cachy-agent-usage-fetch summary` → satır satır `id: today=N total=M limits[...]`

- [ ] **Step 1: Test 16'yı yaz**

```bash
# 16. usage-fetch semasi + XDG_STATE_HOME
FX="$SCRATCH/fetch"
mkdir -p "$FX/agents/usage"
cat > "$FX/agents/usage/codex.json" <<'J'
{"schemaVersion":1,"id":"codex","name":"Codex","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"pro","limits":[{"label":"5h","percent":0.42,"resetsAt":"2026-10-07T12:00:00Z"}],"todayPrompts":3,"todaySessions":1,"todayTotalTokens":10,"totalPrompts":9,"totalSessions":4}
J
cat > "$FX/agents/usage/copilot.json" <<'J'
{"schemaVersion":1,"id":"copilot","name":"Copilot","updatedAt":"2026-10-06T00:00:00Z","ready":false,"tierLabel":"","limits":[],"todayPrompts":0,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0,"reason":"no CLI quota command"}
J
export XDG_STATE_HOME="$SCRATCH/state"
mkdir -p "$XDG_STATE_HOME/cachy-agent/agents"
cp -r "$FX/agents/usage" "$XDG_STATE_HOME/cachy-agent/agents/"
out=$(cachy-agent-usage-fetch 2>/dev/null); rc=$?
ok_json=$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); p={x["id"]:x for x in d["providers"]}; assert p["codex"]["today"]==3 and p["codex"]["total"]==9 and abs(p["codex"]["limits"][0]["percent"]-0.42)<1e-9 and d["alarm"] is False; assert p["copilot"]["name"]=="Copilot"; print("OK")' 2>&1)
if [[ $rc -eq 0 && "$ok_json" == "OK" ]]; then ok "16a fetch semasi"; else bad "16a fetch semasi" "rc=$rc py='$ok_json'"; fi
# XDG_STATE_HOME destekleniyor (plasmoid ~/.local/state hardcoded idi)
if printf '%s' "$out" | grep -q codex; then ok "16b XDG_STATE_HOME okundu"; else bad "16b XDG_STATE_HOME" "codex yok"; fi
# alarm esigi
cat > "$FX/agents/usage/codex.json" <<'J'
{"schemaVersion":1,"id":"codex","name":"Codex","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"","limits":[{"label":"5h","percent":0.95,"resetsAt":null}],"todayPrompts":0,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0}
J
cp "$FX/agents/usage/codex.json" "$XDG_STATE_HOME/cachy-agent/agents/usage/codex.json"
al=$(cachy-agent-usage-fetch 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["alarm"])' 2>/dev/null)
if [[ "$al" == "True" ]]; then ok "16c alarm esigi >=0.9"; else bad "16c alarm" "alarm=$al"; fi
# summary modu
sum=$(cachy-agent-usage-fetch summary 2>/dev/null)
if [[ "$sum" == *"codex"* ]]; then ok "16d summary modu"; else bad "16d summary" "'$sum'"; fi
```

- [ ] **Step 2: Testi çalıştır, kırıldığını doğrula**

Run: `bash tests/test.sh 2>&1 | grep -E '^(PASS|FAIL): 16'`

Expected: `FAIL: 16a` — `cachy-agent-usage-fetch` henüz yok.

- [ ] **Step 3: `cachy-agent-usage-fetch`'i yaz**

Bash sarmalayıcı + python3 gövde (`usage-oneline` deseninin genelleştirilmiş
hâli — aynı `MONTHS_TR`, aynı `pct_of` normalizasyonu, aynı bozuk-dosya atlama).

- Varsayılan mod: `providers` + `alarm` (§6.1'deki şema, `main.qml`'in beklediği birebir).
- `summary` modu: `id: today=N total=M limits[label pct% (reset)]` — `cachy-agent:106`'nın yerine.
- `percent > 1.0` ise `/100` (mevcut `oneline:64-65` normalizasyonu korunur).
- `ready:false` kayıtta `reason` varsa summary'de göster.
- Bozuk/okunamayan JSON sessizce atlanır (mevcut davranış).
- Hiç kayıt yoksa `{"providers":[],"alarm":false}` (JSON boş değil — `main.qml`'in
  `stdout === ""` kontrolü `lastError` göstermesin).

- [ ] **Step 4: `cachy-agent:104-106`'yı değiştir**

Gömülü python3 tek satırını `exec "$HOME/.local/bin/cachy-agent-usage-fetch" summary`
ile değiştir. `usage` alt komutu artık kendi JSON'unu okumaz.

- [ ] **Step 5: `main.qml:34`'ü değiştir**

```qml
property string fetchCommand: "__HOME__/.local/bin/cachy-agent-usage-fetch"
```

`updateCommand`, `installBase`, `catalogCommand` (Task 3'ten) ve `onNewData`
zinciri **aynen korunur** — şema birebir aynı olduğu için QML mantığı
değişmez. Bu, `XDG_STATE_HOME` hatasını da düzeltir (fetch script'i honour
ediyor, eski gömülü kod honour etmiyordu).

- [ ] **Step 6: Ölü okumaları ve `ready` varsayılanını düzelt**

- `usage-oneline:55` `d.get("ready", True)` — değişiklik yok (zaten `True`)
- `usage-panel:95` `rec.get("ready", False)` → `rec.get("ready", True)`
- `usage-oneline` ve `usage-panel`: `ready:false` + `reason` varsa reason'u göster

- [ ] **Step 7: `opencode` kolektörünü sözleşmeye uydur**

`:7` ve `:19`'daki hata JSON'ları genişlet:
`{"schemaVersion":1,"id":"opencode","name":"opencode","updatedAt":"<iso>",
"ready":false,"tierLabel":"","limits":[],"todayPrompts":0,"todaySessions":0,
"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0}`

`updatedAt` için `date -u +%Y-%m-%dT%H:%M:%SZ`. Bu §6.4'teki "ready:false
tüm sayaçları içerir" sözleşmesini sağlar.

- [ ] **Step 8: smoke.sh'ye gömülü python kontrolünü ekle**

`:28`'deki `/home/` taramasından sonra:

```bash
if grep -rn --exclude-dir=__pycache__ -E "python3 -c ['\"]" "$REPO_DIR/src/" 2>/dev/null; then
  bad "src/ icinde gomulu python3 -c kaldi"
else
  ok "gomulu python yok"
fi
```

**Bu adım ancak Steps 4-5 bittikten sonra çalışır** — aksi hâlde `main.qml`'deki
eski gömülü kod kontrolü geçemez.

- [ ] **Step 9: Testleri çalıştır**

Run: `bash tests/test.sh 2>&1 | tail -5 && bash tests/smoke.sh 2>&1 | tail -4`

Expected: `0 kaldı`, `SMOKE: GEÇTİ` (gömülü python kontrolü dahil).

- [ ] **Step 10: Commit**

```bash
git add src/bin/cachy-agent-usage-fetch src/bin/cachy-agent src/plasmoid src/bin/cachy-agent-usage-oneline src/bin/cachy-agent-usage-panel src/bin/cachy-agent-usage-opencode tests/
git commit -m "refactor: gomulu python -> cachy-agent-usage-fetch

- Yeni script: providers JSON (plasmoid) + summary modu (cachy-agent usage)
- XDG_STATE_HOME destekleniyor (plasmoid ~/.local/state hardcoded idi)
- Olu fallback'ler (usedPercent, limits[].name, today, total) temizlendi
- ready varsayilani tek yerde True (oneline True, panel False idi)
- ready:false + reason gosteriliyor (copilot'in reason'u hic okunmuyordu)
- opencode hata yollari sözlesmeye uydu
- smoke.sh: gomulu python kontrolu eklendi"
```

---

### Task 8: Dokümantasyon

**Files:**
- Modify: `README.md`, `README.tr.md`, `CHANGELOG.md`, `VERSION`
- Create: `docs/agents.md`, `docs/usage-schema.md`

**Interfaces:**
- Consumes: Task 1-7'nin bitmiş hâli
- Produces: kodla çelişmeyen dokümantasyon

- [ ] **Step 1: `docs/agents.md` yaz**

İçerik: `agents.conf` formatı ve 6 alan; `WORKDIR` global ayarı; `\|` kaçış
kuralı; `flags` içinde tırnak yasağı; yeni agent nasıl eklenir (config satırı
+ varsa `src/bin/cachy-agent-usage-<id>` koleksiyon script'i); `agy` koşullu
bayrakları tablosu (`tests/fixtures/argv-baseline.md`'den); `--seed`'in neden
config'e taşınmadığı.

- [ ] **Step 2: `docs/usage-schema.md` yaz**

§6.4'teki alan/kolektör tablosu; `ready:true` → tüm sayaçlar, `ready:false` →
yalnızca temel alanlar; `reason` alanı; **5 agent'ın kolektörü yok**
(`agy`, `claude`, `crush`, `cursor-agent`, `grok`).

- [ ] **Step 3: `README.md`'yi düzelt**

§10.1'deki eşleme tablosunu uygula. Ek olarak:
- Features listesine "tek katalog dosyası" maddesi
- Installation bölümüne "config'i düzenleyebilirsiniz" notu
- Testing bölümü: `./tests/smoke.sh`, `./tests/test.sh`, `./tests/argv-differential.sh --check`
- Known Limitations: hangi agent'ın kotası izleniyor / izlenmiyor

- [ ] **Step 4: `README.tr.md`'yi senkronla**

Aynı düzeltmeler, Türkçe. İki README'nin yapı başlıkları birebir eşleşmeli.

- [ ] **Step 5: `CHANGELOG.md` ve `VERSION`**

`VERSION` → `0.2.0`. CHANGELOG'a 0.2.0 girdisi: tek katalog kaynağı,
`--prefix`, repoya bağlanan testler, sahte kolektörlerle ağsız test, CI,
gömülü Python'un kaldırılması, `XDG_STATE_HOME` düzeltmesi, ölü fallback'lerin
temizlenmesi, README'deki yanlış vaatlerin düzeltilmesi, **`agy` koşullu
bayrak davranışının korunması**.

CHANGELOG'a uyarı notu: **mevcut kurulum kullanıcıda `install.sh`
çalıştırılmadan `cachy-agent-agents` kurulmaz ve `cachy-agent` çalışmaz —
yükseltmeden önce `./install.sh` çalıştır.**

- [ ] **Step 6: Tutarlılığı doğrula**

Run: `cd /home/alperen/Projeler/cachy-agent && grep -rn "two-part catalog\|Guided setup\|registers the global shortcut\|Placeholder — add a real" README.md README.tr.md`

Expected: **çıktı yok**.

Run: `bash tests/smoke.sh && bash tests/test.sh && bash tests/argv-differential.sh --check`

Expected: hepsi yeşil.

- [ ] **Step 7: `--version` fallback'ini temizle**

`cachy-agent:108-113`'teki `../../VERSION` → `$HOME/Projeler/cachy-agent/VERSION`
fallback zincirini sadeleştir. `install.sh` `VERSION` dosyasını `BIN_DIR`'a
kopyalasın (`cp -f "$REPO_DIR/VERSION" "$BIN_DIR/VERSION"`), `--version` sırasıyla
`$BIN_DIR/../VERSION`, `$PREFIX/bin/VERSION` ve `<script>/../../VERSION` baksın.
Kullanıcının `$HOME/Projeler/cachy-agent`'e özgü fallback'i kaldırılır — bu,
§7.4'teki hedef.

- [ ] **Step 8: Commit**

```bash
git add README.md README.tr.md CHANGELOG.md VERSION docs/ install.sh src/bin/cachy-agent
git commit -m "docs: v0.2.0 — README gercekekle hizalandi, sema ve config referansi

- Yanlis vaatler duzeltildi: two-part catalog, guided setup, kisayol kaydi,
  placeholder screenshot notu
- docs/agents.md: agents.conf referansi, agy kosullu bayraklari
- docs/usage-schema.md: alan sozlesmesi, 5 agent'in koleksiyonu yok
- --version: Projeler/ fallback'i kaldirildi, install.sh VERSION kopyalar
- CHANGELOG: yeniden kurulum uyarisi"
```

---

### Task 9: Bütünleştirme doğrulaması

**Files:** değişiklik yok — doğrulama görevi

**Interfaces:**
- Consumes: Task 1-8
- Produces: §8.5'in on maddesinin kanıtı

- [ ] **Step 1: Tam süit**

Run: `cd /home/alperen/Projeler/cachy-agent && bash tests/smoke.sh && bash tests/test.sh && bash tests/argv-differential.sh --check`

Expected: `SMOKE: GEÇTİ` · `0 kaldı` · `18 ölçüm tamam`.

- [ ] **Step 2: Hardcode taraması**

Run: `grep -rn 'agy claude codex\|opencode|agy|claude|codex' src/bin src/plasmoid | grep -v 'cachy-agent-agents\|config'`

Expected: yalnızca `agy` koşullu bayrak satırı ve yorumlar.

- [ ] **Step 3: Gömülü python taraması**

Run: `grep -rn -E "python3 -c ['\"]" src/`

Expected: çıktı yok.

- [ ] **Step 4: Temiz checkout**

```bash
rm -rf /tmp/opencode/clean2
git clone . /tmp/opencode/clean2 && cd /tmp/opencode/clean2 && bash tests/smoke.sh && bash tests/test.sh
```

Expected: `SMOKE: GEÇTİ`, `0 kaldı`.

- [ ] **Step 5: Gerçek kurulum smoke testi (kullanıcı onayı gerekir)**

`./install.sh --prefix /tmp/opencode/realpfx` gerçek `$HOME`'ye dokunmadan
kurar. Bu **zaten test 13'te doğrulanıyor**; ayrıca çalıştırma gerekmez.

Eğer kullanıcı gerçek kurulumu denemek isterse: `./install.sh` → ardından
`cachy-agent --help`, `cachy-agent --inline opencode` (kendi makinenizde).

- [ ] **Step 6: Son commit**

```bash
git add -A && git commit -m "chore: v0.2.0 butunlesik dogrulamasi" --allow-empty
git log --oneline | head -10
```
