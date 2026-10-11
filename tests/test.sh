#!/usr/bin/env bash
# cachy-agent pasif test süiti — yıkıcı işlem YOK (kurulum/LLM çağrısı yapmaz).
set -u
G="\033[32m"; R="\033[31m"; Y="\033[33m"; N="\033[0m"
PASS=0; FAIL=0; SKIP=0
ok()   { PASS=$((PASS+1)); printf "${G}PASS${N}: %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "${R}FAIL${N}: %s — %s\n" "$1" "$2"; }
# ATLANDI: ortam bu ölçümü taşıyamıyor (kurulum yok, systemd oturumu yok,
# doğrulayıcı yok). SKIP exit code'u ETKİLEMEZ — yalnızca gerçek hata kırmızıdır.
skip() { SKIP=$((SKIP+1)); printf "${Y}SKIP${N}: %s\n" "$1"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"

# --- GERÇEK KULLANICI AĞACLARI: suite onlara YAZMAMALI ----------------------
# Yollar, XDG_* DEĞERLERİ EZİLMEDEN ÖNCE sabitlenir. 13h ve 17 bunları
# kullanır; ikisi de "suite gerçek config/state'i değiştirmedi" iddiasını
# ölçer. (Kullanıcı XDG_CONFIG_HOME ayarlamışsa o değer esas alınır —
# aksi halde test, ürünün asla görmediği bir dosyayı "koruyor" derdi.)
REAL_CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent"
REAL_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/cachy-agent/agents/usage"

# --- HER ŞEY GECİCİ DİZİNDE (kurulum gereksinimi yok) -----------------------
# Suite'in tek yazma kökü. `$HOME`'un altına HİÇBİR şey yazılmaz; blok 13'ün
# sahte evi ve bu dizin birlikte EXIT trap'inde silinir.
#
# Neden XDG_* dışarıda çevriliyor: `cachy-agent` config'i
#   ${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent/{agents.conf,default-agent}
# üzerinden çözer. Test 3 varsayılan ajanı okuyup YAZIYOR; bu değişken
# çevrilmezse kullanıcının gerçek ajanı değişir. `cachy-agent-agents` da aynı
# kalıbı kullanır (bkz. 11*/13g) — iki taraf aynı kökü gördüğü için sözleşme
# tutarlı kalır.
SCRATCH_ROOT="$(mktemp -d)"
SCRATCH="$SCRATCH_ROOT/genel"; mkdir -p "$SCRATCH"
export XDG_CONFIG_HOME="$SCRATCH_ROOT/config"; mkdir -p "$XDG_CONFIG_HOME/cachy-agent"
export XDG_STATE_HOME="$SCRATCH_ROOT/state";  mkdir -p "$XDG_STATE_HOME"
# Blok 13 kendi sandbox'ında XDG_*'i unset ediyor; blok sonunda geri konur.
SAVED_XDG_CONFIG="$XDG_CONFIG_HOME"
SAVED_XDG_STATE="$XDG_STATE_HOME"

# Gerçek kullanıcının durum/config ağacına dokunulmadığını kanıtlamak için
# BAŞTA parmak izi alınır (test 17). Bunlar yalnızca OKUNUR.
# `fingerprint`: dosya listesi + içerik cksum'u -> tek satır. Dizin yoksa "yok".
# İSİM ÇAKIŞMASI TUZAGI: bu iki değişken BİLEREK `_TREE` sonlu olamaz — blok
# 13'ün 13h testi `REAL_CONF_BEFORE` adını TEK DOSYANIN cksum'u için kullanıyor
# ve değeri EZİYOR. Bu sessizdir: 17b kendi ağacının parmak izi yerine 13h'nin
# tek dosya değerini karşılaştırır ve KIRMIZI olur (ölçülen hata).
fingerprint() { [[ -d "$1" ]] || { echo "yok"; return; }; (cd "$1" && find . -type f -print0 2>/dev/null | LC_ALL=C sort -z | xargs -0 -r cksum 2>/dev/null | cksum); }
REAL_STATE_TREE_BEFORE="$(fingerprint "$REAL_STATE_DIR")"
REAL_CONF_TREE_BEFORE="$(fingerprint "$REAL_CONF_DIR")"

PFXROOT="$(mktemp -d)"
trap 'rm -rf "${SCRATCH_ROOT:-}" "${PFXROOT:-}"' EXIT

# --- BIN: kurulum değil, çalışma ağacı ---------------------------------------
# `CACHY_AGENT_TEST_PREFIX` yalnızca ölçüm/deney için; varsayılan src/bin.
# DİKKAT: bu dizin yalnızca `cachy-agent` gibi TEKİL çağrılara uygundur;
# `cachy-agent-usage-update` kardeşlerini `CACHY_AGENT_BIN_DIR`'dan çözer
# (aşağıdaki 6b bloğu). Boşluğa düşmemek için her ikisi de ayrı ayrı sabit.
BIN="${CACHY_AGENT_TEST_PREFIX:-$REPO/src/bin}"
export PATH="$BIN:$PATH"
STATE="$XDG_STATE_HOME/cachy-agent/agents/usage"

# 1. sözdizimi: bash -n + py_compile
# NOT hangi ağacın sınandığı: artık YALNIZCA çalışma ağacı ($REPO/src/bin).
# v0.1.0'de burada `~/.local/bin` de taranıyordu; bu, suite'i "bu makinede
# kurulu olan sürüm"in doğruluğuna bağımlı kılıyordu — temiz checkout'ta o
# dizin yok, kurulu ağacın bozuk olması da bu deponun testi değildir.
# Kurulu ağacı tutmak isteyen kullanıcı kendi ayrı kontrolünü yapar.
t1_ok=1; t1_msg=""; t1_n=0
for f in "$REPO"/src/bin/cachy-*; do
  [[ -e "$f" ]] || continue
  case "$f" in *.py) continue;; esac
  t1_n=$((t1_n+1))
  if head -1 "$f" | grep -q bash; then
    if ! bash -n "$f" 2>/tmp/cachy-t1.err; then t1_ok=0; t1_msg="$t1_msg$(basename "$f"): $(cat /tmp/cachy-t1.err); "; fi
  fi
done
# py_compile çıktısı yanına __pycache__ bırakır; kaynak ağacı kirletmesin diye
# cfile geçici köke yazılır. (`cfile=/dev/null` Python 3.14'te FileExistsError
# veriyor: "non-regular file" — bu yüzden dosya yolu kullanılıyor.)
if ! python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
     "$REPO/src/bin/cachy-notify-action.py" "$SCRATCH_ROOT/notify.pyc" 2>/tmp/cachy-t1py.err; then
  t1_ok=0; t1_msg="$t1_msg py_compile: $(cat /tmp/cachy-t1py.err); "
fi
if [[ $t1_ok == 1 && $t1_n -gt 0 ]]; then ok "1 bash -n + py_compile ($t1_n script)"; else bad "1 bash -n + py_compile" "script=$t1_n $t1_msg"; fi

# 2. --help exit 0 + "Kullanım"
out=$(cachy-agent --help 2>&1); rc=$?
if [[ $rc == 0 && "$out" == *"Kullanım"* ]]; then ok "2 --help"; else bad "2 --help" "exit=$rc, 'Kullanım' yok"; fi

# 3. default mevcut değeri basar; uydurma exit 1 (dosyaya yazmaz)
#
# YOL İZOLE EDİLDİ: `cachy-agent` config'i
#   ${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent/{agents.conf,default-agent}
# üzerinden çözer. Suite başında XDG_CONFIG_HOME geçici köke çevrildiği için
# buradaki okuma/YAZMA testin kendi alanındadır; kullanıcının gerçek
# `default-agent` dosyasına dokunulmaz. (v0.1.0'de test 3 gerçek dosyayı
# okuyor, hatta `default` komutuyla YAZIYORDU.)
DEF_FILE="$XDG_CONFIG_HOME/cachy-agent/default-agent"
cur=$(cat "$DEF_FILE" 2>/dev/null || echo "opencode")
got=$(cachy-agent default 2>&1); rc=$?
if [[ $rc == 0 && "$got" == "$cur" ]]; then ok "3a default gösterir ($cur)"; else bad "3a default gösterir" "exit=$rc got='$got' beklenen='$cur'"; fi
# 3b. BİLİNMEYEN AD REDDEDİLMEZ (bilinmeyen agent: <ad>). `neg()` kalıbı:
# tam olarak rc=1 + stderr'da beklenen GEREKÇE. neg() blok 11'de tanımlı
# (3b'den sonra), o yüzden aynı kalıp burada elle uygulanır.
#
# NEDEN config sabitleniyor (I-3): temiz ortamda `agents.conf` YOKTUR, o zaman
# `cachy-agent-agents` "config dosyası yok" deyip exit 1 döner — koruma olsa
# da olmasa da. Yani rc=1'e bakan bir test "guard çalışıyor" ölçmez, "config
# eksik" ölçer; v0.1.0'te gerçek config var olduğu için bu test o zaman gerçekten
# korumayı ölçüyordu, izolasyonla birlikte boşa düştü. Config sabitlenince
# "bilinmeyen agent" yolu açılır ve gerekçe ölçülebilir.
#
# Neden id listesi de bekleniyor: `run_agent`'ın guard'ı
# "bilinmeyen agent: X (bilinenler: ...)", `--pick`/`default` guard'ı ise
# "bilinmeyen agent: X (...)" basar. Yalnız "bilinmeyen agent: uydurma" deseydik
# iki yol birbirini geçerdi; parantez içinin listenin KENDİSİ olması, korumanın
# `--pick` dalında olduğunu ayırt ediyor.
C3B_CFG="$REPO/tests/fixtures/agents-valid.conf"
C3B_IDS="opencode agy claude codex crush copilot cursor-agent grok"
err=$(CACHY_AGENT_CONFIG="$C3B_CFG" cachy-agent default uydurma 2>&1 >/dev/null); rc=$?
if [[ $rc -eq 1 && "$err" == "bilinmeyen agent: uydurma ($C3B_IDS)" ]]; then
  ok "3b default bilinmeyen adı reddeder (exit 1 + gerekçe)"
else
  bad "3b default uydurma" "rc=$rc (1 bekleniyordu) stderr='$err'"
fi
after=$(cat "$DEF_FILE" 2>/dev/null || echo "opencode")
if [[ "$after" == "$cur" ]]; then ok "3c default dosyası değişmedi"; else bad "3c default dosyası değişmedi" "'$cur' -> '$after'"; fi

# 3d/3e. İZOLASYONUN KENDİSİ: `default` komutu gerçekten geçici kökü okuyor.
# 3a tek başına bunu kanıtlamaz — gerçek `~/.config` okunsa da "mevcut değer"
# ile eşleşirdi. Burada `default codex` YAZILIR (geçici köke), sonra okuma
# `codex` vermek zorundadır; ardından dosya SİLİNİR ve `opencode`'a düşülür.
# Bu iki yönlü kontrol, "config yolu yanlış çözülürse" senaryosunu kırmızı
# yapar (dosya yanlış yere yazılırsa 3d okuma codex vermez; dosya temizlenmezse
# 3e opencode vermez).
printf 'codex\n' > "$DEF_FILE"
got3d=$(cachy-agent default 2>&1); rc=$?
rm -f "$DEF_FILE"
got3e=$(cachy-agent default 2>&1); rc2=$?
if [[ $rc -eq 0 && "$got3d" == "codex" ]]; then
  ok "3d default geçici config'i okuyor (XDG_CONFIG_HOME izole)"
else
  bad "3d config izolasyonu" "rc=$rc got='$got3d' (codex bekleniyordu)"
fi
# 3e, `default_agent()` fallback'ının ÖLÇÜMÜDÜR: dosya yokken komut exit 1
# verip ham `cat:` hatası basıyordu (bkz. task-5-report.md §5, ürün hatası).
if [[ $rc2 -eq 0 && "$got3e" == "opencode" ]]; then
  ok "3e default dosya yoksa opencode'a düşüyor (sıfırdan bağımsız)"
else
  bad "3e varsayılan düşüş" "rc=$rc2 got='$got3e' (opencode bekleniyordu)"
fi

# 4. --prompt argümansız exit 1 + usage
out=$(cachy-agent --prompt 2>&1); rc=$?
if [[ $rc == 1 && "$out" == *"kullanım"* ]]; then ok "4 --prompt argümansız"; else bad "4 --prompt argümansız" "exit=$rc out='$out'"; fi

# 5. --pick uydurma exit 1 + GEREKÇE
# 3b ile aynı boşluk (I-3): config sabitlenmezse `cachy-agent-agents` "config dosyası
# yok" deyip exit 1 döner ve test, koruma olmasa da geçer. Config sabitlenir ve
# `--pick`in kendi guard'ının mesajı (id listesi parantezde) beklenir —
# `run_agent`ın "(bilinenler: ...)" varyantı kabul edilmez, çünkü o yol
# --pick'in guard'ı mutant olsa bile geçerdi.
err=$(CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
      cachy-agent --pick uydurma </dev/null 2>&1 >/dev/null); rc=$?
if [[ $rc -eq 1 && "$err" == "bilinmeyen agent: uydurma ($C3B_IDS)" ]]; then
  ok "5 --pick bilinmeyen adı reddeder (exit 1 + gerekçe)"
else
  bad "5 --pick uydurma" "rc=$rc (1 bekleniyordu) stderr='$err'"
fi

# 6. usage-update exit 0 + 3 JSON geçerli
#
# AĞSIZ/ŞİFRESİZ: gerçek kolektörler ÇALIŞTIRILMAZ. `cachy-agent-usage-codex`
# `~/.codex/auth.json` okuyup AĞ RPC'si yapar; `...-opencode` de kimlik
# bilgisi ister. Bunlar v0.1.0'de gerçekten çalışıyordu — yani suite ağa,
# kimlik bilgisine ve o makinede kurulu ajan CLIs'ine bağımlıydı.
#
# Yerine `$SCRATCH_ROOT/coll/` altına SABİT JSON basan üç stub konur ve
# `CACHY_AGENT_BIN_DIR` (Task 3'ün seam'i) ile oraya yönlendirilir. Aynı
# değişken katalog okuyucusu (`cachy-agent-agents`) içindir; sahte okuyucu
# config okuma yolunu test etmezdi diye GERÇEK olan kopyalanır.
#
# Yazma hedefi de geçici: XDG_STATE_HOME suite başında yönlendirildiği için
# kullanıcının gerçek kullanım verisi ezilmez (test 17 bunu ayrıca ölçer).
SC6B="$SCRATCH_ROOT/coll"; mkdir -p "$SC6B"
cp "$REPO/src/bin/cachy-agent-agents" "$SC6B/cachy-agent-agents"
# Katalog: deponun KENDI agents.conf'i, OKUNARAK. Kullanıcının
# `~/.config/cachy-agent/agents.conf`'i değil — o dosya bu makinede başka bir
# ajan listesi taşıyor olabilir ve test onun varlığına bağımlı olmamalı.
# Katalog 8 id verir, stub'lar 3'ü -> tam olarak 3 JSON yazılmalı (ne eksik
# ne fazla: 6d bunu ayrıca ölçer).
C6B_CONF="$REPO/src/config/agents.conf"
for a in opencode codex copilot; do
  cat > "$SC6B/cachy-agent-usage-$a" <<EOF
#!/usr/bin/env bash
# Sabit JSON: hiçbir ağ çağrısı, hiçbir credential okuması yok.
printf '{"schemaVersion":1,"id":"$a","name":"STUB $a","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"test","limits":[{"label":"stub","percent":7}],"todayPrompts":3,"todaySessions":1,"todayTotalTokens":100,"totalPrompts":9,"totalSessions":4,"totalTokens":900,"reason":"stub"}'
EOF
  chmod +x "$SC6B/cachy-agent-usage-$a"
done
CACHY_AGENT_CONFIG="$C6B_CONF" CACHY_AGENT_BIN_DIR="$SC6B" \
  cachy-agent-usage-update >/dev/null 2>&1; rc=$?
if [[ $rc -eq 0 ]]; then ok "6a usage-update exit 0"; else bad "6a usage-update exit 0" "exit=$rc"; fi
n=0; badjson=""
for f in "$STATE"/*.json; do
  [[ -e "$f" ]] || break
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then n=$((n+1)); else badjson="$badjson$(basename "$f") "; fi
done
if [[ $n -ge 3 && -z "$badjson" ]]; then ok "6b $n JSON geçerli"; else bad "6b JSON geçerli" "geçerli=$n bozuk='$badjson' (en az 3 bekleniyor)"; fi

# 6d. JSON'lar GERÇEK Kolektörden değil STUB'dan geldi — ağ/credential
# kanıtı. 6b yalnızca "geçerli JSON var" diyordu; aynı dosyaları gerçek
# `cachy-agent-usage-codex` de üretebilirdi (ve `~/.codex/auth.json` okurdu).
# Burada `name` alanındaki `STUB ` işareti aranır: işaretli dosya sayısı 3'ün
# altındaysa ya da beklenmeyen dosya varsa gerçek kolektör devreye girmiştir.
d_stub=0; d_bad=""
for f in "$STATE"/*.json; do
  [[ -e "$f" ]] || break
  if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if d.get("name","").startswith("STUB ") else 1)' "$f" 2>/dev/null; then
    d_stub=$((d_stub+1))
  else
    d_bad="$d_bad$(basename "$f") "
  fi
done
if [[ $d_stub -ge 3 && -z "$d_bad" ]]; then
  ok "6d collector'lar sahte JSON basti (ağ/credential kullanilmadi)"
else
  bad "6d sahte collector kaniti" "isaretli=$d_stub gercek_cikan='$d_bad' (3 bekleniyordu)"
fi

# 6c. IZLENEN KUME config'in id listesiyle BIREBIR ayni olmali (I-4).
# 6a boştu: `mapfile` + `continue` katalog tamamen yokken de exit 0 donuyordu,
# yani hiçbir şey işlenmese de test geçerdi. Burada hem katalog hem de
# CACHY_AGENT_BIN_DIR sabitlenir; sonuç config'in id kümesiyle karşılaştırılır.
# İki yönlü: eksik iş ve FAZLA iş ikisi de yakalanır — sadece "sıfır dosya"
# diye bakmak, koleksiyonu olmayan ajanları sessizce geçerdi.
SC6=$(mktemp -d)
mkdir -p "$SC6/coll" "$SC6/state"
printf 'WORKDIR=~/Projeler\ns1=Sa|-|x|-|-\ns2=Sb|-|x|-|-\ns3=Sc|-|x|-|-\n' > "$SC6/agents.conf"
# `CACHY_AGENT_BIN_DIR` (Ruling 10) hem katalog okuyucusunun hem de
# koleksiyonların dizinidir; kurulumda ikisi de ~/.local/bin'de yan yana
# durur. Testte aynı sepete ikisini de koyuyoruz. Gerçek `cachy-agent-agents`
# kopyalanır — sahte okuyucu config okuma yolunu test etmezdi.
cp "$REPO/src/bin/cachy-agent-agents" "$SC6/coll/cachy-agent-agents"
# Her id için geçerli JSON basan sahte kolektör (gerçek ajan CLI çalışmaz).
for a in s1 s2 s3; do
  cat > "$SC6/coll/cachy-agent-usage-$a" <<EOF
#!/usr/bin/env bash
printf '{"schemaVersion":1,"id":"$a","name":"$a","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"","limits":[],"todayPrompts":0,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0,"totalTokens":0}'
EOF
  chmod +x "$SC6/coll/cachy-agent-usage-$a"
done
# Config'te OLMAYAN ama koleksiyonu OLAN ajan: dosya YAZILMAMALI.
cat > "$SC6/coll/cachy-agent-usage-gizli" <<'EOF'
#!/usr/bin/env bash
printf '{"schemaVersion":1,"id":"gizli","ready":true,"limits":[],"todayPrompts":0,"totalPrompts":0}'
EOF
chmod +x "$SC6/coll/cachy-agent-usage-gizli"
CACHY_AGENT_CONFIG="$SC6/agents.conf" CACHY_AGENT_BIN_DIR="$SC6/coll" XDG_STATE_HOME="$SC6/state" \
  cachy-agent-usage-update >/dev/null 2>&1; rc=$?
# `LC_ALL=C`: 13b-4'teki gerekçeyle aynı — karşılaştırma collation'a bağımlı
# olursa test, tr_TR altında kazara ya da kazara kırmızı olur.
got6c="$(find "$SC6/state/cachy-agent/agents/usage" -maxdepth 1 -name '*.json' -printf '%f\n' 2>/dev/null | sed 's/\.json$//' | LC_ALL=C sort | tr '\n' ' ')"
want6c="s1 s2 s3 "
if [[ $rc == 0 && "$got6c" == "$want6c" ]]; then
  ok "6c usage-update config id listesiyle birebir ayni"
else
  bad "6c usage-update katalog" "rc=$rc got='$got6c' bekleniyordu='$want6c'"
fi
rm -rf "$SC6"

# 7. cachy-agent usage exit 0
# 6b'nin ürettiği JSON'ları OKUMALI: çıktıda 6d'nin stub id'leri görünmeli.
# Yalnızca exit 0'a bakmak "kayıt yok" mesajıyla da geçerdi (kayıt yoksa
# script yine 0 döner) — yani test, verinin gerçekten okunduğunu ölçmezdi.
#
# CACHY_AGENT_BIN_DIR pin'i (Ruling 10 seam'i): `usage` alt komutu artık
# kardeş script `cachy-agent-usage-fetch`'i exec'liyor. Kurulum YOKKEN bile
# çalışma ağacından çözülmeli — suite'in "kurulum gereksinimi yok" sözü.
out7=$(CACHY_AGENT_BIN_DIR="$BIN" cachy-agent usage 2>&1); rc=$?
if [[ $rc -eq 0 && "$out7" == *"opencode: today=3"* && "$out7" == *"codex: today=3"* && "$out7" == *"copilot: today=3"* ]]; then
  ok "7 usage exit 0 + 6b kayitlarini okuyor"
else
  bad "7 usage" "rc=$rc out='$(printf '%s' "$out7" | tr '\n' ' ')'"
fi

# 8. systemd: kaynak unit'ler her yerde, KURULU/AKTIF olan ortam varsa
#
# İkiye ayrıldı. Kaynak dosyaların VARLIĞI her checkout'ta ölçülebilir ve
# ölçülmelidir (birim kaybolursa sessizce ürünü bozar). "Kurulu ve aktif" ise
# ortamın DURUMUDUR: temiz checkout'ta, CI'da, systemd'siz konteynerde yoktur
# ve yokluğu ürünün hatası değildir -> SKIP.
#
# 8b'de `systemctl --user is-active` yalnızca SORGUDUR (enable/disable/stop
# çağrısı YOKTUR) ve blok 13'ün `systemctl` stub'ı devrede değildir; yani
# gerçek oturuma yazma yapan hiçbir yol açılmaz.
for s in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
  if [[ -f "$REPO/src/systemd/$s" ]]; then
    ok "8a kaynak unit mevcut: $s"
  else
    bad "8a kaynak unit" "$REPO/src/systemd/$s yok — ürün unit'i kaybetti"
  fi
done
if command -v systemctl >/dev/null 2>&1 && [[ -d "$HOME/.config/systemd/user" ]] \
   && [[ -f "$HOME/.config/systemd/user/cachy-crash-watch.service" ]]; then
  sok=1; smsg=""
  for s in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
    [[ -f "$HOME/.config/systemd/user/$s" ]] || { sok=0; smsg="$smsg$s yok; "; }
  done
  # YALNIZCA okuma: `is-active` hiçbir servisi değiştirmez.
  st=$(systemctl --user is-active cachy-crash-watch 2>&1 || true)
  [[ "$st" == "active" ]] || { sok=0; smsg="$smsg is-active='$st'; "; }
  if [[ $sok == 1 ]]; then ok "8b servisler + crash-watch active"; else bad "8b servisler + crash-watch" "$smsg"; fi
else
  skip "8b kurulu/aktif servis kontrolu (ortam yok: systemctl veya ~/.config/systemd/user yok)"
fi

# 9. desktop-file-validate — KAYNAK dosyalar, `__HOME__` genişletilerek
# v0.1.0'da `~/.local/share/applications` KURULU olan kopyaları doğrulanıyordu;
# bu da suite'i o makinedeki kuruluma bağımlı kılıyordu. Artık kaynak ağaçtaki
# `src/applications/*.desktop` doğrulanıyor; doğrulayıcı yoksa SKIP.
#
# `__HOME__` geçici köke genişletiliyor (smoke.sh:58-64 deseni) çünkü
# doğrulayıcı Exec= yolunun biçimini kontrol eder ve placeholder'ı kabul etmez.
# Genişletme sonrası artık `__HOME__` KALMAMASI da ayrıca ölçülür: yalnızca
# "söz dizimi geçerli" demek, `__HOME__` genişletmesi bozulursa yeşil kalırdı.
if command -v desktop-file-validate >/dev/null 2>&1; then
  DV_DIR="$SCRATCH_ROOT/dv"; mkdir -p "$DV_DIR"
  dok=1; dvmsg=""; dv_n=0
  for f in "$REPO"/src/applications/*.desktop; do
    [[ -e "$f" ]] || continue
    dv_n=$((dv_n+1))
    b="$(basename "$f")"
    sed "s|__HOME__|$SCRATCH_ROOT|g" "$f" > "$DV_DIR/$b"
    if grep -q '__HOME__' "$DV_DIR/$b"; then dok=0; dvmsg="$dvmsg$b:__HOME__ kaldi; "; fi
    o=$(desktop-file-validate "$DV_DIR/$b" 2>&1); r=$?
    [[ $r -eq 0 && -z "$o" ]] || { dok=0; dvmsg="$dvmsg$b:exit=$r:$o; "; }
  done
  # SAYIM (M-1): döngü gövdesi hiç çalışmasa `dok` 1'de kalır ve test BOŞA
  # geçerdi — yani `src/applications` yanlışlıkla boşalır/kayarsa kimse
  # fark etmezdi. 13b-4 zaten beklenen .desktop kümesini tam olarak sabitliyor
  # (applications/ altında 2 dosya); burada aynı sayı ikinci kez doğrulanır.
  if [[ $dv_n -ne 2 ]]; then dok=0; dvmsg="$dvmsg bulunan=$dv_n (2 bekleniyordu); "; fi
  if [[ $dok == 1 ]]; then ok "9 desktop-file-validate (kaynak, __HOME__ genisletilmis, $dv_n dosya)"; else bad "9 desktop-file-validate" "$dvmsg"; fi
else
  skip "9 desktop-file-validate (ortam yok: desktop-file-validate komutu bulunamadi)"
fi

# 10. menu seçim mantığı (stub fuzzel/alacritty/install — gerçek çalıştırma yok)
# Artık ÇALIŞMA AĞACININ menüsü sınanır (kurulu ~/.local/bin kopyası değil):
# menü config'e bağlandığı için `cachy-agent-agents` bulunabilmeli ve katalog
# sabitlenmelidir — aksi halde test kullanıcının kendi config'ine bakar.
#
# Menü (ve open/install/usage-update) kardeş binary'leri PATH'e bakmaz;
# `BIN="${CACHY_AGENT_BIN_DIR:-$HOME/.local/bin}"` üzerinden çözerler
# (Ruling 10 — desktop entry ve systemd --user unit'inde PATH'e güvenilemez).
# Bu yüzden harness yol GÖMMEZ, `$STUB`'u `CACHY_AGENT_BIN_DIR` ile export
# eder: tek `sed` yerine tek `export`, dört çağıranın hepsi için.
STUB=$(mktemp -d)
cp "$REPO/src/bin/cachy-agent-menu" "$STUB/menu-test"
sed -i "s|/usr/bin/alacritty|$STUB/alacritty|g" "$STUB/menu-test"
# Katalog okuyucusu GERÇEK cachy-agent-agents: sahte bir okuyucu testin
# konusunu (config okuma yolu) test etmezdi.
cp "$REPO/src/bin/cachy-agent-agents" "$STUB/cachy-agent-agents"
# fuzzel stub'ı stdin'deki MENÜ LİSTESİNİ de kaydeder. Bu, listenin kaynağını
# doğrudan kanıtlar: `list` config'ten gelmiyorsa burada görünmez.
#
# FAKE_SEL_LIST: çok adımlı akış (varsayılan değiştirme iki ekran) için
# satır satır seçim. Her çağrıda bir sonraki satırı basar, çağrı sayacıyla.
# Verilmezse eski davranış (hep FAKE_SEL) korunur — mevcut testler böyle.
cat > "$STUB/fuzzel" <<'EOF'
#!/usr/bin/env bash
# Her çağrının menüsünü NUMARALI da kaydet ($STUB_MENU.<n>): akış birden çok
# ekrana çıkabiliyor ve son menü daima 1. ekranla bitmeyebilir (Esc 2.'den
# 1.'e döner). Numaralı kopya olmadan 2. ekranın İÇERİĞİ doğrulanamıyor.
_n=$(cat "$STUB_MENU_N" 2>/dev/null || printf '0'); _n=$((_n+1))
printf '%s' "$_n" > "$STUB_MENU_N"
cat > "$STUB_MENU.$_n"
cat "$STUB_MENU.$_n" > "$STUB_MENU"
if [[ -n "${FAKE_SEL_LIST:-}" ]]; then
  sed -n "${_n}p" "$FAKE_SEL_LIST"
else
  printf '%s' "$FAKE_SEL"
fi
EOF
# alacritty stub'ı YALNIZCA kendisine verilen argv'yi kaydeder, `-e` sonrasını
# çalıştırmaz. Bu yüzden "install CALLED" diye bir iz YOKTUR ve olmamalıdır:
# test, menünün hangi komutu hangi argümanla başlattığını argv üzerinden
# sınar. (Eski 10g bu stub'ın asla üretemediği bir dizgiyi arıyordu.)
cat > "$STUB/alacritty" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" >> "$STUB_LOG"
exit 0
EOF
cat > "$STUB/cachy-agent-install" <<'EOF'
#!/usr/bin/env bash
echo "INSTALL CALLED: $*" >> "$STUB_LOG"
exit 0
EOF
# '★ ... (varsayılan yap)' dalı `cachy-agent default` çağırır ve notify-send
# yolunu dener; ikisi de stub'lanır ki test gerçek varsayılan agent'ı DEĞİŞTİRMEYİ
# ve kullanıcıya bildirim GÖNDERMEYİ (assert sırasında olsa da görsel gürültü).
cat > "$STUB/cachy-agent" <<'EOF'
#!/usr/bin/env bash
# TEK ARGÜMANLI `default` = OKUMA yolu (menü mevcut varsayılanı soruyor).
# İki+ argümanlı = YAZMA yolu (menü varsayılanı değiştiriyor) -> log'a.
# Ayrım şart: okuma stdout'a değer basmalı, yoksa menü yanlış "varsayılan yok"
# sanıp hiçbir satıra tik koymaz.
if [[ "${1:-}" == "default" && $# -eq 1 ]]; then
  printf '%s\n' "${FAKE_DEFAULT:-agy}"
  exit 0
fi
printf 'DEFAULT CALLED: %s\n' "$*" >> "$STUB_LOG"
exit 0
EOF
cat > "$STUB/notify-send" <<'EOF'
#!/usr/bin/env bash
printf 'NOTIFY: %s\n' "$*" >> "$STUB_LOG"
exit 0
EOF
chmod +x "$STUB/fuzzel" "$STUB/alacritty" "$STUB/cachy-agent-install" "$STUB/cachy-agent" "$STUB/notify-send"
export STUB_LOG="$STUB/calls.log"
export STUB_MENU="$STUB/menu.txt"
export STUB_MENU_N="$STUB/menu.n"
STUB_SEL_LIST="$STUB/sel-list.txt"
export PATH="$STUB:$PATH"
# Ruling 10 seam'i: menü/open/install/usage-update kardeş binary'leri BURADAN
# çözer. `PATH`'e de ekleniyor çünkü 10l `cachy-agent-agents`'i test 11'de
# olduğu gibi bare adla çağıracak.
export CACHY_AGENT_BIN_DIR="$STUB"
export CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf"

# AGBIN: menü testlerinin "kurulu" görmesi gereken agent'lar. CI runner'ında
# agy/claude/codex/... YOKTUR; testler bunlara bağımlıysa ortam kaynaklı
# kırmızı üretirler (ölçüldü: 10n/10o). 10m zaten bu yolu kullanıyordu.
AGBIN="$(mktemp -d)"
for _ag in opencode agy claude codex crush copilot cursor-agent grok; do
  printf '#!/usr/bin/env bash\nexit 0\n' > "$AGBIN/$_ag"; chmod +x "$AGBIN/$_ag"
done

# 10a. "+ x (kur)" -> install çağrısı
: > "$STUB_LOG"
FAKE_SEL="+ Codex (kur)" bash "$STUB/menu-test" >/dev/null 2>&1 || true
if grep -q "cachy-agent-install" "$STUB_LOG" && grep -q "codex" "$STUB_LOG"; then ok "10a menu '+ x (kur)' install'e gider"; else bad "10a menu '+ x (kur)'" "log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10b. ayraç satırı -> HİÇBİR komut çağrılmaz, menüde kalınır (Esc ile çıkılır)
# FAKE_SEL_LIST kullanılır: ayraç seçimi menüyü yeniden açar, dolayısıyla fuzzel
# İKİ kez çağrılmalıdır. Düz FAKE_SEL ile sonsuz döngüye girer (ölçüldü:
# ayraç -> continue -> aynı ayraç -> ...). Beklenen davranışı iki çağrıyla
# sabitlemek hem doğru hem sonlu.
: > "$STUB_LOG"; rm -f "$STUB_MENU_N"
printf '%s\n%s\n' '──────────────────────────────' '' > "$STUB_SEL_LIST"
FAKE_DEFAULT=agy FAKE_SEL_LIST="$STUB_SEL_LIST" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
_b_n=$(cat "$STUB_MENU_N" 2>/dev/null || echo 0)
if [[ $rc == 0 && ! -s "$STUB_LOG" && "$_b_n" -eq 2 ]]; then
  ok "10b menu ayraci yoksayilir, menude kalir"
else bad "10b menu ayraç" "exit=$rc fuzzel_cağrı=$_b_n log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10c. düz agent satırı -> `cachy-agent-open` (config'de tanımlı olmalı)
: > "$STUB_LOG"
FAKE_SEL="codex" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'cachy-agent-open' "$STUB_LOG" && grep -qx 'codex' "$STUB_LOG"; then
  ok "10c menu düz ad -> -open"
else bad "10c menu düz ad" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10d. ★ satırları ARTIK ÜRETİLMİYOR — her kurulu agent yalnız BİR kez
# listelenir. Önceki hâlde menü düz liste + ★ listesi olmak üzere agent'i iki
# kez gösteriyordu (5 agent → 9+ satır) ve hangisinin varsayılan olduğu
# hiçbir yerde görünmüyordu.
: > "$STUB_LOG"
FAKE_DEFAULT=agy FAKE_SEL="" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1
if ! grep -q '★' "$STUB_MENU" && ! grep -q 'varsayılan yap' "$STUB_MENU"; then
  ok "10d menüde tekrar eden ★ satırı yok"
else bad "10d ★ tekrarı" "menu='$(tr '\n' '/' < "$STUB_MENU")'"; fi

# --- Yeni menü şekli (kullanıcı isteği): her agent TEK satır, mevcut
# varsayılan ✓ ile işaretli, varsayılan değiştirme AYRI bir adımda.
# Önceki hâlde her kurulu agent İKİ kez listeleniyordu (düz + ★), 5 agent için
# 9+ satır; ve hangisinin varsayılan olduğu HİÇBİR yerde görünmüyordu.
#
# 10n. Birinci ekran: mevcut varsayılan ✓ işaretli, düz satır YOK (tekrar yok),
#      ve "varsayılanı değiştir" adımı görünür.
: > "$STUB_LOG"
FAKE_DEFAULT=agy FAKE_SEL="" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1
_menu_n=$(cat "$STUB_MENU" 2>/dev/null)
if grep -qx '✓ agy' "$STUB_MENU" \
   && ! grep -qx 'agy' "$STUB_MENU" \
   && grep -q 'Varsayılanı değiştir' "$STUB_MENU"; then
  ok "10n menü varsayılanı ✓ ile işaretler, tekrar yok, değiştir adımı var"
else bad "10n menü ✓ işareti" "menu='$(printf '%s' "$_menu_n" | tr '\n' '/')'"; fi

# 10o. "⟲ Varsayılanı değiştir" -> İKİNCİ ekran, orada seçim varsayılanı yazar.
# İkinci ekranın İÇERİĞİ de doğrulanır: stub her menüyü numaralı saklar,
# çünkü akış birden çok ekrana çıkabiliyor ve "son menü" daima 1. ekran değil
# (Esc 2.'den 1.'e döner). Şu anki varsayılan "✓ x (şu anki)" olarak, diğerleri
# "(varsayılan yap)" ile görünmeli.
: > "$STUB_LOG"; rm -f "$STUB_MENU_N" "$STUB_MENU".*
printf '%s\n%s\n' '⟲ Varsayılanı değiştir' '  Claude Code (varsayılan yap)' > "$STUB_SEL_LIST"
FAKE_DEFAULT=agy FAKE_SEL_LIST="$STUB_SEL_LIST" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 0 ]] \
   && grep -q 'DEFAULT CALLED: default claude' "$STUB_LOG" \
   && grep -qx '✓ agy (şu anki)' "$STUB_MENU.2" \
   && grep -qx '  Claude Code (varsayılan yap)' "$STUB_MENU.2"; then
  ok "10o 'varsayılanı değiştir' ikinci ekranı açar ve seçimi yazar"
else bad "10o iki ekranlı akış" "exit=$rc ekran2='$(tr '\n' '/' < "$STUB_MENU.2" 2>/dev/null)' log=$(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi


# 10p. İkinci ekranda Esc (boş seçim) -> birinci ekrana DÖNER, çıkmaz.
# Yalnız "log boş" demek YETERSİZ: yeni akışta olmayan yolda da log boş
# kalır ve test yanlış yeşil verir (ölçüldü). Bu yüzden fuzzel'in KAÇ KEZ
# çağrıldığı sayılır: akış gerçekten ikinci ekranı açmış olmalı (2 çağrı).
: > "$STUB_LOG"; rm -f "$STUB_MENU_N"
printf '%s\n%s\n' '⟲ Varsayılanı değiştir' '' > "$STUB_SEL_LIST"
FAKE_DEFAULT=agy FAKE_SEL_LIST="$STUB_SEL_LIST" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
_p_n=$(cat "$STUB_MENU_N" 2>/dev/null || echo 0)
if [[ $rc == 0 && "$_p_n" -ge 2 && ! -s "$STUB_LOG" ]]; then
  ok "10p ikinci ekranda Esc birinciye döner"
else bad "10p Esc dönüşü" "exit=$rc fuzzel_cağrı=$_p_n log=$(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10q. ✓ satırı birinci ekranda da düz ad gibi açılır (tik ayrı bir eylem değil)
: > "$STUB_LOG"
FAKE_DEFAULT=agy FAKE_SEL="✓ agy" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'cachy-agent-open' "$STUB_LOG" && grep -qx 'agy' "$STUB_LOG"; then
  ok "10q menü '✓ x' -> x'i açar"
else bad "10q '✓ x'" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10e. CONFIG'DE OLMAYAN ad -> hicbir komut çağrılmaz, sessiz exit 0.
# Eski sabit `case` listesi yerine `known` konduğu için bu, listeden
# kaldırılmış/kataloğa hiç girmemiş bir ajanın menüye sızamamasını kilitler.
: > "$STUB_LOG"; rm -f "$STUB_MENU_N"
FAKE_DEFAULT=agy FAKE_SEL="uydurma" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc -eq 0 && ! -s "$STUB_LOG" ]]; then
  ok "10e menu bilinmeyen ad reddeder"
else bad "10e menu bilinmeyen ad" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10f. 2. ekranda ŞU ANKİ varsayılan seçilirse varsayılan YENIDEN YAZILMAZ.
# "Kendini varsayılan yap" eylemi anlamsız; eskiden menü her kurulu agent için
# bu satırı gösterdiği için mevcut varsayılan da listedeydi.
: > "$STUB_LOG"; rm -f "$STUB_MENU_N"
printf '%s\n%s\n%s\n' '⟲ Varsayılanı değiştir' '✓ agy (şu anki)' '' > "$STUB_SEL_LIST"
FAKE_DEFAULT=agy FAKE_SEL_LIST="$STUB_SEL_LIST" PATH="$STUB:$AGBIN:$PATH" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then
  ok "10f 2. ekranda şu anki varsayılan secilince yeniden yazilmaz"
else bad "10f şu anki varsayılan no-op" "exit=$rc log=$(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10g. TEK AYIRT EDİCİ TEST: listenin kaynağı config'tir, sabit literal değil.
#
# 10a'nın kör noktası: `codex` sabit listede de var, bu yüzden 10a hem sabit
# liste hem config listesiyle GEÇER — hiçbir şey ayırt etmez. Burada config'e
# YALNIZCA config-only bir id (`ozel`) konur ve iddialar üç ayrı yere bakar:
#
#   (a) MENÜ LİSTESİ (fuzzel'in stdin'i) `+ ozel (kur)` satırını İÇERİR.
#       Bu listenin `cachy-agent-agents list`'ten geldiğinin doğrudan kanıtı:
#       sabit liste geri gelse `ozel` listede hiç görünmezdi.
#   (b) Aynı listede sabit 8 isimden HİÇBİRİ yoktur. Sabit liste `ozel`'in
#       yanına eklenmiş olsaydı (ya da sabit liste geri geldiyse) bu kırılır.
#   (c) Seçim `+ ozel (kur)` alacritty'yi `cachy-agent-install ozel` ile
#       başlatır — alacritty stub'ı YALNIZCA argv'yi kaydeder, `-e` sonrasını
#       çalıştırmaz; bu yüzden "INSTALL CALLED" değil ARGV aranır.
#
# (a)+(b) birlikte "sabit liste geri gelirse kırmızı" kanıtıdır.
cat > "$STUB/ozel.conf" <<'EOF'
WORKDIR=~/Projeler
ozel=Özel Ajansı|npm i -g ozel|--yolo|--prompt|ozel login
EOF
: > "$STUB_LOG"; : > "$STUB_MENU"
CACHY_AGENT_CONFIG="$STUB/ozel.conf" FAKE_SEL="+ Özel Ajansı (kur)" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
menu_txt="$(cat "$STUB_MENU" 2>/dev/null || echo BOŞ)"
g_sabit_yok=1
for a in opencode agy claude codex crush copilot cursor-agent grok; do
  if grep -q "$a" "$STUB_MENU" 2>/dev/null; then g_sabit_yok=0; fi
done
if [[ $rc == 0 ]] \
   && grep -qx '+ Özel Ajansı (kur)' "$STUB_MENU" \
   && [[ $g_sabit_yok -eq 1 ]] \
   && grep -q 'cachy-agent-install' "$STUB_LOG" \
   && grep -qx 'ozel' "$STUB_LOG"; then
  ok "10g menu listesi config'ten (config-only id tanindi, sabit isim yok)"
else
  bad "10g menu config-only id" "exit=$rc sabit_isim_yok=$g_sabit_yok menu='$(printf '%s' "$menu_txt" | tr '\n' '/')' log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"
fi

# 10h. Ters yön: sabit listedeki bir isim config'den ÇIKARILINCA menü onu
# tanımamalı. 10e "hiç tanımadığı" ismi sınıyordu; bu, "listeden çıkarılmış"
# ismi sınıyor — yani whitelist config'e bağlı, eski sabit `case` değil.
printf 'WORKDIR=~/Projeler\nclaude=Claude Code|npm i -g x|--permission-mode auto|-p|claude login\n' > "$STUB/dar.conf"
: > "$STUB_LOG"; : > "$STUB_MENU"
CACHY_AGENT_CONFIG="$STUB/dar.conf" FAKE_SEL="codex" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then
  ok "10h menu config'den cikarilan ismi reddeder"
else
  bad "10h menu config'den cikarilan isim" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"
fi

# 10i. Config EKSİKken menü v0.1.0'de "sessizce hiçbir şey yapma" idi:
# kullanıcı kısayola basıyor, pencere açılmadan kapanıyor, sebep yok. Config'e
# bağlandıktan sonra bu yol normalden çıktı; menü artık sebebi stderr'a yazıp
# exit 1 veriyor. Sessizce kapanmaya devam etseydi kullanıcı config'inin
# kurulmadığını anlayamazdı.
: > "$STUB_LOG"
err=$(CACHY_AGENT_CONFIG="$STUB/yok-boyle.conf" FAKE_SEL="" bash "$STUB/menu-test" 2>&1 >/dev/null); rc=$?
if [[ $rc != 0 ]] && [[ "$err" == *"katalog"* || "$err" == *"liste"* ]]; then
  ok "10i menu eksik config'de sebep yaziyor (sessiz kapanma yok)"
else
  bad "10i menu eksik config" "exit=$rc (0 sessiz kapanma, sifirdan farkli bekleniyordu) stderr='$err'"
fi

# --- 10j/10k/10l: MENÜNÜN ÖTESİNDEKİ GERÇEK SCRIPT'LER ---
# 10a-10i alacritty stub'ında duruyordu (argv kaydeder, `-e` sonrasını
# ÇALIŞTIRMAZ). Bu yüzden onay sıralaması, `bash -c` çalıştırması ve login
# ipucu tablosu hiç sınanmıyordu. Aşağıdaki üç test o üç riskli yeniden
# yazımı DOĞRUDAN çalıştırır.
#
# Gerçek script'ler çalıştığı için `cachy-agent` burada HER ZAMAN BAŞARISIZ
# olan bir stub'dır (başarılı olsaydı `cachy-agent-open` ipucu yoluna hiç
# gelmezdi). Kurulum komutu da asla çalıştırılmaz: 10j/10k her ikisi de
# `bash -c`'den ÖNCE çıkıyor.
cp "$REPO/src/bin/cachy-agent-install" "$STUB/install-test"
cp "$REPO/src/bin/cachy-agent-open" "$STUB/open-test"
cat > "$STUB/cachy-agent" <<'EOF'
#!/usr/bin/env bash
# open'in hata yoluna düşmesi için: daima başarısız.
exit 7
EOF
chmod +x "$STUB/cachy-agent"

# 10j. I-1: TTY YOKKEN onay sorulmadan kurulum calismamali.
# İKİ kolu var; ikisi de aynı bulguyu farklı yerden sınıyor.
#
# (a) onay SIRASI (brief kuralı): bilinmeyen ad kullanıcıya hiç sorulmaz.
#     `uydurma` config'de yok -> `get` exit 1. 'Devam?' stdout'ta olmamalı.
#
# (b) I-1'in kendisi: config GEÇERLİ bir ajan + TTY YOK. v0.1.0'te
#     `read ... || true` EOF'u yutup `ans` boş kalınca kontrol düşüyor ve
#     kurulum SORULMADAN `bash -c` ile çalışıyordu. Burada `install` alanı
#     yalnızca `echo` (gerçek kurulum komutu DEĞİL, ağ/npm/curl yok) ve
#     bir marker dosyasına yazıyor; marker OLUŞMAMALI.
printf 'WORKDIR=~/Projeler\nkurulacak=Sahte Ajan|echo CALISTI > %s/marker.txt|-|--prompt|-\n' "$STUB" > "$STUB/tty.conf"
rm -f "$STUB/marker.txt"
out=$(CACHY_AGENT_CONFIG="$STUB/tty.conf" bash "$STUB/install-test" kurulacak </dev/null 2>&1); rc=$?
if [[ $rc -eq 1 ]] && [[ "$out" != *"Devam?"* ]] && [[ ! -e "$STUB/marker.txt" ]]; then
  ok "10j install: TTY yoksa onay almadan kurulmaz (kurulum hic calismadi)"
else
  bad "10j install TTY/onay" "rc=$rc (1 bekleniyordu) marker=$([ -e "$STUB/marker.txt" ] && echo VAR-KURULDU || echo yok) out='$out'"
fi

# (a) onay sirasi: bilinmeyen ad sorulmaz
out=$(CACHY_AGENT_CONFIG="$STUB/unknown.conf" bash "$STUB/install-test" uydurma </dev/null 2>&1); rc=$?
if [[ $rc -eq 1 ]] && [[ "$out" != *"Devam?"* ]]; then
  ok "10j-b install: bilinmeyen ad onay sorulmadan reddedilir"
else
  bad "10j-b install onay sirasi" "rc=$rc (1 bekleniyordu) out='$out'"
fi

# 10k. Harici ajan (install '-') -> otomatik kurulum yok, rc 1, onay YOK.
printf 'WORKDIR=~/Projeler\nharici=Harici Ajan|-|x|-|-\n' > "$STUB/harici.conf"
out=$(CACHY_AGENT_CONFIG="$STUB/harici.conf" bash "$STUB/install-test" harici </dev/null 2>&1); rc=$?
if [[ $rc -eq 1 ]] && [[ "$out" == *"otomatik kurulum yok"* ]] && [[ "$out" != *"Devam?"* ]]; then
  ok "10k install: harici ajan reddedilir, onay sorulmaz"
else
  bad "10k install harici ajan" "rc=$rc (1 bekleniyordu) out='$out'"
fi

# 10l. Login ipucu config'in `login` alanindan gelir — HER id icin.
# Beklenen deger fixture'dan ALINIR, script'e gomulmez; boylece tablo
# config ile birlikte degisirse test degisimi de yakalar.
l_hata=""; l_n=0
for a in $("$REPO/src/bin/cachy-agent-agents" list 2>/dev/null); do
  l_n=$((l_n+1))
  want="$("$REPO/src/bin/cachy-agent-agents" get "$a" login 2>/dev/null)"
  got=$(CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" bash "$STUB/open-test" "$a" </dev/null 2>&1 | grep 'Sonraki adım:')
  if [[ "$want" == "-" ]]; then
    okg="Sonraki adım: 'cachy-agent --inline $a' ile manuel dene"
  else
    okg="Sonraki adım: terminalde '$want' ile giriş yap"
  fi
  if [[ "$got" != "$okg" ]]; then
    l_hata="${l_hata}[${a}] got='$got' bekleniyordu='$okg'; "
  fi
done
if [[ $l_n -eq 8 && -z "$l_hata" ]]; then
  ok "10l open: 8 ajanin login ipucu config'ten"
else
  bad "10l open login ipucu" "ajan=$l_n (8 bekleniyordu) hata=$l_hata"
fi

# 10m (I-2). brief Step 6'nın İKİNCİ assertion'ı: `claude` PATH'te KURULU
# olduğunda düz satır (kur listesinde DEĞİL) seçilir ve alacritty stub'ına
# `cachy-agent-open claude` ile gider.
#
# NEDEN ÖNEMLİ (bulgu): `installed`/`missing` ayrımı — yani "bu ajan kurulu mu"
# sorusu — HİÇBİR TESTTE ölçülmüyordu. `cachy-agent-menu`in installed dizisini
# her zaman boş bırakan mutantı suite'i TAMAMEN YEŞİL bırakıyordu. 10a-10l'nin
# hepsi `FAKE_SEL`'i ZORLA veriyor; menü listesine hiç bakmıyorlar.
#
# O yüzden AYRI bir test yazmak yetmez: AYRIMIN KENDİSİ ölçülmeli. Burada üç
# şey birden sınanır:
#   (a) LİSTE: `claude` çıplak satır olarak VAR (kurulu bölümde),
#   (b) LİSTE: `+ claude (kur)` YOK — yani claude "eksik" sayılmıyor,
#   (c) YÖNLENDİRME: seçim alacritty stub'ına `-e .../cachy-agent-open claude`.
#
# (a)+(b) AYIRIMI, (c) YÖNLENDİRMEYİ ölçer. (c) tek başına YETMEZ: mutant
# altında log BİREBİR AYNI kalıyor (fuzzel stub'ı seçimi zorla verdiği için),
# yani ayrım ancak (a)/(b) ile görünür. Ölçüldü.
#
# PATH KONTROLÜ ŞART: bu makinede gerçek `claude`/`codex` KURULU. PATH
# sızdırılırsa menü, sahip olduğu makineye göre "kurulu" görür ve test sonucu
# donanıma bağımlı olurdu. Bu yüzden menü YALNIZCA kontrollü PATH ile
# çalıştırılır: $STUB (stub'lar + claude) + $SYSBIN (yalnız bash/cat/sed/tr).
# Böylece her makinede claude=KURULU, codex=EKSİK.
SYSBIN="$STUB/sysbin"; mkdir -p "$SYSBIN"
for _b in bash cat sed tr; do ln -sf "$(command -v "$_b")" "$SYSBIN/$_b"; done
# `claude` stub'ı: menünün `command -v claude` ile bulacağı "kurulu ajan".
printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/claude"; chmod +x "$STUB/claude"
: > "$STUB_LOG"; : > "$STUB_MENU"
FAKE_SEL="claude" PATH="$STUB:$SYSBIN" CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
  bash "$STUB/menu-test" >/dev/null 2>&1; m_rc=$?
menu_m="$(cat "$STUB_MENU" 2>/dev/null)"
if [[ $m_rc -eq 0 ]] \
   && grep -qE '^[[:space:]]*Claude Code$' "$STUB_MENU" \
   && ! grep -q '^+ claude (kur)$' "$STUB_MENU" \
   && grep -q 'cachy-agent-open' "$STUB_LOG" \
   && grep -qx 'claude' "$STUB_LOG"; then
  ok "10m menu kurulu ajani (claude) 'kur' listesine koymaz, -open'e yollar"
else
  bad "10m menu kurulu/missing ayrimi" "rc=$m_rc menu='$(printf '%s' "$menu_m" | tr '\n' '/')' log=$(cat "$STUB_LOG" 2>/dev/null | tr '\n' ' ')"
fi

# 10r. Menü config'teki GÖRÜNEN ADI gösterir; seçilince ID ile açılır.
# Kullanıcı isteği: menüde 'opencode' yerine 'OpenChamber' görünsün. İD
# değişmiyor (kullanım toplayıcı + argv ölçümü id'e bağlı), yalnız ETİKET.
# Bu test iki şeyi birden kilitler: listede 'Claude Code' var (görünen ad),
# `claude` id'si yok; ve seçilince argv'de `claude` geçiyor (id).
# FAKE_SEL menü satırının BİREBİR kendisidir; fuzzel listeyi birebir döndürür,
# yani baştaki hizalama boşlukları da seçimde yer alır.
: > "$STUB_LOG"; : > "$STUB_MENU"
FAKE_DEFAULT=agy FAKE_SEL="  Claude Code" PATH="$STUB:$SYSBIN" \
  CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
  bash "$STUB/menu-test" >/dev/null 2>&1; r_rc=$?
if [[ $r_rc -eq 0 ]] \
   && grep -qx '  Claude Code' "$STUB_MENU" \
   && ! grep -q 'claude' "$STUB_MENU" \
   && grep -q 'cachy-agent-open' "$STUB_LOG" && grep -qx 'claude' "$STUB_LOG"; then
  ok "10r menu gorsen adi gosterir, id ile acar"
else bad "10r gorsen ad" "rc=$r_rc menu='$(tr '\n' '/' < "$STUB_MENU")' log=$(tr '\n' ' ' < "$STUB_LOG")"; fi

# Ters yön: PATH'te OLMAYAN ajan gerçekten "kur" listesine düşmeli. Bu ikili
# ayrımın YAN yüzünü sabitler; yalnız (a)/(b) bir yönü ölçüyordu.
if grep -qx '+ Codex (kur)' "$STUB_MENU"; then
  ok "10m-2 menu eksik ajani (codex) 'kur' satiri olarak listeler"
else
  bad "10m-2 menu eksik ajan" "'+ Codex (kur)' satirinda yok"
fi

unset CACHY_AGENT_CONFIG
unset CACHY_AGENT_BIN_DIR
rm -rf "$STUB"

# 11. agents.conf parse + check
# `SCRATCH`, `PFXROOT`, `REPO` ve EXIT trap'i dosyanın BAŞINDA tanımlıdır:
# 2/3/6/7 numaralı bloklar XDG_* çevrimi yüzünden aynı geçici köke ihtiyaç
# duyuyor ve trap'in onları da temizlemesi gerekiyor. Burada YENİDEN
# tanımlanmazlar (ikinci bir mktemp, ilkini yarım bırakırdı).
AG="$REPO/src/bin/cachy-agent-agents"
FIX="$REPO/tests/fixtures"

# Negatif assertion kalıbı. `if ! cmd` YAZMA: 127 ("command not found") de
# sıfır dışıdır ve testi yanlış geçirir. Burada TAM OLARAK rc=1 ve stderr'da
# beklenen gerekçe aranır; test ancak doğru hatayla geçer.
#   $1 etiket · $2 beklenen stderr GLOB kalıbı · $3.. çalıştırılacak komut
#
# İKİ TUZAK (kopyalayanlar dikkat):
#  1. $want tırnaksız geçiyor: [[ ]] içinde GLOB olarak yorumlanır. `*` "herhangi
#     biri", AMA `?` "tek karakter", `[`/`]` karakter sınıfı, `\` kaçıştır. Yani
#     beklenen mesajda gerçekten `?` geçiyorsa `\?` yaz, aksi halde `a?c`
#     kalıbı `abc` ile de eşleşir (sessiz yanlış geçme). Harf karakterlerinden
#     oluşan düz kelimeler (`tırnak`, `WORKDIR`, `prompt_flag`) güvenlidir.
#  2. neg() rc'yi 1'e sabitler: yalnızca "exit 1 bekleniyor" testleri içindir.
#     exit 2 (kullanım hatası) veya exit 0 için KULLANILMAZ — 11aa/11ae gibi
#     o testler rc'yi elle kontrol eder.
neg() {
  local label="$1" want="$2"; shift 2
  local err rc
  err=$("$@" 2>&1 >/dev/null); rc=$?
  if [[ $rc -eq 1 && $err == *$want* ]]; then
    ok "$label"
  else
    bad "$label" "rc=$rc (1 bekleniyordu) stderr='$err' (beklenen kalip: $want)"
  fi
}

# 11a: gecerli config -> list dogru sira
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
got=$("$AG" list 2>/dev/null | tr '\n' ' ')
if [[ "$got" == "opencode agy claude codex crush copilot cursor-agent grok " ]]; then
  ok "11a list gecerli config'ten 8 id"
else bad "11a list" "got='$got'"; fi

# 11b: check gecerli config -> exit 0
if "$AG" check >/dev/null 2>&1; then ok "11b check gecerli config exit 0"; else bad "11b check gecerli" "exit=$?"; fi

# 11c: check bozuk config -> exit 1 + satir numarasi + "alan" gerekcesi
export CACHY_AGENT_CONFIG="$FIX/agents-broken.conf"
neg "11c check bozuk config exit 1 + gerekce" "*:2:*alan*" "$AG" check

# 11-empty: en az bir agent satiri olmali. Bos (veya yalnizca yorum iceren)
# config sessizce GECERLI sayiliyordu; boyle bir config ile katalog bos
# kalir, `list` bos doner ve menude hic agent gorunmez — hicbir hata
# ciktisi olmadan. Yanlislikla kirpilan config'i yakalamak icin.
_bos_conf="$SCRATCH/agents-bos.conf"; : > "$_bos_conf"
_yorum_conf="$SCRATCH/agents-yorum.conf"; printf '# sadece yorum\n' > "$_yorum_conf"
for _v in bos yorum; do
  eval "_c=\${_${_v}_conf}"
  export CACHY_AGENT_CONFIG="$_c"
  neg "11-empty ${_v} config exit 1" "*en az bir agent*" "$AG" check
done
# 11d/11e bu değişkenin agents-broken.conf olmasına dayanıyor — geri yükle
export CACHY_AGENT_CONFIG="$FIX/agents-broken.conf"

# 11d: bozuk config -> list exit 1, stderr config yolu + satir no
neg "11d list bozuk config exit 1 + yol:2" "$FIX/agents-broken.conf:2:" "$AG" list

# 11e: eksik alan -> stderr'de satir numarasi
err=$("$AG" check 2>&1 >/dev/null | head -1)
if [[ "$err" == *":2:"* ]]; then ok "11e eksik alan satir numarasiyla"; else bad "11e eksik alan" "err='$err'"; fi

# 11f: config dosyasi YOK -> exit 1 + "config dosyası yok"
export CACHY_AGENT_CONFIG="$SCRATCH/yok.conf"
neg "11f config yok exit 1" "config dosyası yok" "$AG" list

# 11t: `json` çıktısı kontrol karakteri içeren adlarda da GEÇERLİ JSON olmalı.
# Plasmoid `JSON.parse(stdout)` yapıyor (main.qml): name içinde TAB gibi bir
# kontrol karakteri kaçışlanmazsa çıktı bozulur ve agent listesi TAMAMEN
# kaybolur. `check` bu config'i doğru reddediyor ama kimse `check` çağırmıyor
# (install.sh/plasmoid/systemd hiçbir yerde çağırmıyor), yani `json` yolunun
# kendisi dayanıklı olmak zorunda — kir girdi, geçerli JSON çıksın.
TABCONF="$SCRATCH/agents-tab.conf"
printf 'myagent=Claude\tCode|cli|install|-|-|-\n' > "$TABCONF"
export CACHY_AGENT_CONFIG="$TABCONF"
if "$AG" json 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
  ok "11tab json kontrol karakterinde gecerli"
else
  bad "11tab json kontrol karakteri kacisi" "cikti parse edilemedi (TAB islenmedi)"


fi

# 11pairs. `pairs` -> "id<TAB>görünen_ad" (menü id YERİNE görünen adı gösterecek;
# çalıştırma/kurulum komutları ise id ile çalışır). İki alanı ayırmak için
# ayraç TAB: config'te alan ayracı '|' ve id'lerde TAB bulunmaz.
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"   # 11tab TAB fixture'ini birakmis olabilir
_pairs=$("$AG" pairs 2>/dev/null)
if printf '%s\n' "$_pairs" | grep -qx "$(printf 'claude\tClaude Code')" \
   && printf '%s\n' "$_pairs" | grep -qx "$(printf 'opencode\topencode')"; then
  ok "11pairs id<TAB>görünen_ad"
else bad "11pairs" "out=$(printf '%s' "$_pairs" | tr '\n' '/')"; fi

# 11g: bilinmeyen id -> get exit 1, stdout bos, stderr mesaj
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
out=$("$AG" get uydurma flags 2>/dev/null); rc=$?
err=$("$AG" get uydurma flags 2>&1 >/dev/null)
if [[ $rc -eq 1 && -z "$out" && "$err" == *"bilinmeyen agent"* ]]; then
  ok "11g bilinmeyen id exit 1 bos stdout + stderr"
else bad "11g bilinmeyen id" "rc=$rc out='$out' err='$err'"; fi

# 11h: known dogru calisir (bilinen 0, bilinmeyen 1)
if "$AG" known codex 2>/dev/null && ! "$AG" known uydurma 2>/dev/null; then ok "11h known"; else bad "11h known" "codex veya uydurma yanlis"; fi

# 11i: TUM alanlar okunur (name|install|flags|prompt_flag|login)
if [[ "$("$AG" get claude name 2>/dev/null)" == "Claude Code" \
   && "$("$AG" get claude install 2>/dev/null)" == "npm i -g @anthropic-ai/claude-code" \
   && "$("$AG" get claude flags 2>/dev/null)" == "--permission-mode auto" \
   && "$("$AG" get claude prompt_flag 2>/dev/null)" == "-p" \
   && "$("$AG" get claude login 2>/dev/null)" == "claude login" \
   && "$("$AG" get codex prompt_flag 2>/dev/null)" == "-" ]]; then
  ok "11i get bes alan + konumsal prompt_flag"
else bad "11i get alanlar" "claude name='$("$AG" get claude name 2>/dev/null)' install='$("$AG" get claude install 2>/dev/null)' flags='$("$AG" get claude flags 2>/dev/null)' pf='$("$AG" get claude prompt_flag 2>/dev/null)' login='$("$AG" get claude login 2>/dev/null)' codex_pf='$("$AG" get codex prompt_flag 2>/dev/null)'"; fi

# 11j: WORKDIR genisletilir
wd=$("$AG" workdir 2>/dev/null)
if [[ "$wd" == "$HOME/Projeler" ]]; then ok "11j WORKDIR ~ genisletildi"; else bad "11j WORKDIR" "wd='$wd'"; fi

# --- spec §5.5 check maddeleri: HER madde ayri test ---
# 11k: tirnakli flags reddi (6 alan — alan sayisi kuralini TETIKLEMEMELI)
printf 'crush=Crush|-|"--yolo" -|--prompt|-\n' > "$SCRATCH/tirnak.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/tirnak.conf"
neg "11k tirnakli flags reddedildi" "tırnak" "$AG" check

# 11l: gecersiz prompt_flag (tire ile baslamiyor) reddi
printf 'grok=Grok|-|x|bypassPermissions|-\n' > "$SCRATCH/pf.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/pf.conf"
neg "11l prompt_flag bicimi" "prompt_flag" "$AG" check

# 11m: gecersiz id karakteri reddi
printf 'bad id=x|y|z|w|v\n' > "$SCRATCH/id.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/id.conf"
neg "11m id karakteri" "geçersiz id" "$AG" check

# 11n: install bos birakilmis (parse okuma yolunda '-' sayar, check yazim hatasi der)
printf 'codex=Codex||--approve-for-me|-|x\n' > "$SCRATCH/inst.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/inst.conf"
neg "11n bos install reddedildi" "install boş bırakılmış" "$AG" check

# 11o: ikinci WORKDIR satiri reddi
printf 'WORKDIR=/a\nWORKDIR=/b\ncodex=C|x|-|--prompt|x\n' > "$SCRATCH/wd2.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wd2.conf"
neg "11o coklu WORKDIR" "WORKDIR" "$AG" check

# 11p: install icinde kacissiz | -> 7 alan, alan sayisi kurali
printf 'cursor-agent=cursor-agent|curl https://x/install | bash|--yolo --trust|-|y\n' > "$SCRATCH/pipe.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/pipe.conf"
neg "11p gecessiz | -> 7 alan" "*7 alan bulundu*" "$AG" check

# 11q: yinelenen id reddi (§5.5.2)
printf 'claude=Claude Code|x|--permission-mode auto|-p|-\nclaude=Claude Code 2|y|--permission-mode auto|-p|-\n' > "$SCRATCH/dup.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/dup.conf"
neg "11q yinelenen id" "yinelenen id" "$AG" check

# 11r: WORKDIR satiri listede GORUNMEZ (global ayar, agent degil)
# Liste BOS olsa da gecer sayilmaz: yoksa CLI yokken de bu test gecerdi.
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
got=$("$AG" list 2>/dev/null | tr '\n' ' ')
if [[ -n "$got" && "$got" != *WORKDIR* ]]; then ok "11r WORKDIR listede degil"; else bad "11r WORKDIR listeye sizdi" "got='$got'"; fi

# 11s: görünen_ad icinde " -> json kaçışı kuralı
printf 'codex=Code"X|x|-|--prompt|x\n' > "$SCRATCH/adq.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/adq.conf"
neg "11s görünen_ad tırnak" "görünen_ad" "$AG" check

# 11t: görünen_ad icinde backslash -> json kaçışı kuralı
printf 'codex=Code\\X|x|-|--prompt|x\n' > "$SCRATCH/adb.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/adb.conf"
neg "11t görünen_ad backslash" "görünen_ad" "$AG" check

# 11u: görünen_ad icinde kontrol karakteri (TAB) -> json gecersizlesirdi
printf 'codex=Code\tX|x|-|--prompt|x\n' > "$SCRATCH/adctl.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/adctl.conf"
neg "11u görünen_ad kontrol karakteri" "kontrol karakteri" "$AG" check

# 11v: ids tek satir, boslukla (gecerli fixture'a don)
export CACHY_AGENT_CONFIG="$FIX/agents-valid.conf"
got=$("$AG" ids 2>/dev/null); rc=$?
if [[ $rc -eq 0 && "$got" == "opencode agy claude codex crush copilot cursor-agent grok" ]]; then
  ok "11v ids tek satir 8 id"
else bad "11v ids" "rc=$rc got='$got'"; fi

# 11w: external = install != "-" olan 6 id (opencode ve agy harici)
got=$("$AG" external 2>/dev/null | tr '\n' ' ')
if [[ "$got" == "claude codex crush copilot cursor-agent grok " ]]; then
  ok "11w external 6 install'li id"
else bad "11w external" "got='$got'"; fi

# 11x: json gecerli JSON (plasmoid bu ciktiyi parse ediyor)
if "$AG" json 2>/dev/null | python3 -c 'import json,sys; d=json.load(sys.stdin); assert len(d["catalog"])==8; assert set(d["catalog"][0])=={"id","name","installed","external"}'; then
  ok "11x json gecerli + 8 kayit + 4 alan"
else bad "11x json" "python parse/alan sayisi basarisiz"; fi

# 11y: \| kacisi geri cozulur (bu metin cachy-agent-install'in calistiracagi metin)
got=$("$AG" get cursor-agent install 2>/dev/null)
if [[ "$got" == "curl https://cursor.com/install -fsS | bash" ]]; then
  ok "11y get install backslash-pipe kacisi cozuldu"
else bad "11y get install kacisi" "got='$got'"; fi

# 11z: flags <id> kiyayolu (§5.2)
got=$("$AG" flags grok 2>/dev/null)
if [[ "$got" == "--permission-mode bypassPermissions" ]]; then
  ok "11z flags grok"
else bad "11z flags grok" "got='$got'"; fi

# 11aa: bilinmeyen alt komut -> exit 2 (kullanim hatasi, config hatasi degil)
"$AG" zirva >/dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then ok "11aa bilinmeyen alt komut exit 2"; else bad "11aa bilinmeyen alt komut" "rc=$rc (2 bekleniyordu)"; fi

# 11ab: known <bilinmeyen> -> exit 1 + stderr mesaj (§5.2: stdout bos, mesaj stderr)
out=$("$AG" known uydurma 2>/dev/null); rc=$?
err=$("$AG" known uydurma 2>&1 >/dev/null)
if [[ $rc -eq 1 && -z "$out" && "$err" == *"bilinmeyen agent"* ]]; then
  ok "11ab known bilinmeyen exit 1 + stderr"
else bad "11ab known bilinmeyen" "rc=$rc out='$out' err='$err'"; fi

# 11ac: basarisiz sorguda stdout TAMAMEN bos, mesaj stderr'de
out=$("$AG" get uydurma name 2>/dev/null); rc=$?
err=$("$AG" get uydurma name 2>&1 >/dev/null)
if [[ $rc -eq 1 && -z "$out" && -n "$err" ]]; then
  ok "11ac basarisiz sorguda stdout bos"
else bad "11ac stdout bos" "rc=$rc out='$out' err='$err'"; fi

# 11ad: WORKDIR icinde kacissiz | -> WORKDIR tek alandir (§5.5.6)
printf 'WORKDIR=/a|/b\ncodex=C|x|-|--prompt|x\n' > "$SCRATCH/wdpipe.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wdpipe.conf"
neg "11ad WORKDIR icinde | reddedildi" "WORKDIR tek alandır" "$AG" check

# 11ae: config EKSIKKEN kullanım hatasi yine exit 2 (1 degil — §5.2)
CACHY_AGENT_CONFIG="$SCRATCH/yok.conf" "$AG" zirva >/dev/null 2>&1; rc=$?
if [[ $rc -eq 2 ]]; then ok "11ae eksik config + yazim hatasi exit 2"; else bad "11ae eksik config + yazim hatasi" "rc=$rc (2 bekleniyordu)"; fi

# 11af: Ruling 8 — bos install okuma yolunda '-', external listesinde yok
printf 'codex=Codex||--approve-for-me|-|codex login\nopencode=opencode|-|--auto|--prompt|-\n' > "$SCRATCH/emptyinst.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/emptyinst.conf"
inst=$("$AG" get codex install 2>/dev/null); rc=$?
ext=$("$AG" external 2>/dev/null | tr '\n' ' ')
if [[ $rc -eq 0 && "$inst" == "-" && -z "$ext" ]]; then
  ok "11af bos install -> '-', external bos"
else bad "11af bos install okuma yolu" "rc=$rc install='$inst' external='$ext'"; fi

# 11ag: WORKDIR satiri YOK -> geriye uyum: $HOME/Projeler (spec §5.1)
# v0.1.0 config'inde WORKDIR satiri yok; bu yol o kullanicilarin davranisini
# degistirmeden tutar. Duzlestirilirse (geriye uyum kaybi) test kirmizi olur.
printf 'codex=Codex|npm i -g @openai/codex|--approve-for-me|-|codex login\n' > "$SCRATCH/wd-yok.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wd-yok.conf"
wd=$("$AG" workdir 2>/dev/null); rc=$?
if [[ $rc -eq 0 && "$wd" == "$HOME/Projeler" ]]; then
  ok "11ag WORKDIR yok -> ~/Projeler geriye uyumu"
else bad "11ag WORKDIR yok" "rc=$rc wd='$wd' (beklenen: $HOME/Projeler)"; fi

# 11ah: bos WORKDIR= -> check reddeder, satir numarasiyla (WORKDIR bos yazilmis)
printf 'WORKDIR=\ncodex=C|x|-|--prompt|x\n' > "$SCRATCH/wd-bos.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wd-bos.conf"
neg "11ah bos WORKDIR reddedildi" "*:1:*WORKDIR boş*" "$AG" check

# 11ai: ~'li ve ~/Projeler OLMAYAN yol genisletilir (literal gecmez)
printf 'WORKDIR=~/Projeler/deneme\ncodex=C|x|-|--prompt|x\n' > "$SCRATCH/wd-tilde.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/wd-tilde.conf"
wd=$("$AG" workdir 2>/dev/null); rc=$?
if [[ $rc -eq 0 && "$wd" == "$HOME/Projeler/deneme" ]]; then
  ok "11ai ~-li baska WORKDIR genisletildi"
else bad "11ai ~ genisletme" "rc=$rc wd='$wd' (beklenen: $HOME/Projeler/deneme)"; fi

# 11aj: prompt_flag icinde tirnak reddi (spec §5.5.3'in prompt_flag yarısı;
# 11k yalnızca flags yarısını kapsıyor). 6 alan — alan sayisi kuralı tetiklenmez.
printf 'codex=Codex|x|-|"--prompt"|-\n' > "$SCRATCH/pf-tirnak.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/pf-tirnak.conf"
neg "11aj prompt_flag tirnak reddedildi" "prompt_flag içinde tırnak" "$AG" check

# 11ak: agy flags SIRASI — run_agent promptsuz çağrıda flags'ın YALNIZ ilk
# kelimesini geçirir (`${flags%% *}`, ölçülen davranış). Bayrak yanlış sırada
# başlarsa ajan sessizce KIRPILMIŞ bir bayrakla çağrılır (ör. `agy --effort`),
# çıkış kodu 0, uyarı yok. check bunu reddetmeli (spec §5.4.1).
printf 'agy=agy|-|--effort low --dangerously-skip-permissions|--prompt|-\n' > "$SCRATCH/agy-sira.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/agy-sira.conf"
neg "11ak agy flags sirasi reddedildi" "*BAŞLAMALI" "$AG" check

# 11al: dogru sira -> check GECER. Kural yanlışlıkla her agy'yi reddetmemeli;
# aksi halde 11ak "her zaman kırmızı" olur ve kuralı kanıtlamaz.
printf 'agy=agy|-|--dangerously-skip-permissions --effort low|--prompt|-\n' > "$SCRATCH/agy-sira-ok.conf"
export CACHY_AGENT_CONFIG="$SCRATCH/agy-sira-ok.conf"
if "$AG" check >/dev/null 2>&1; then ok "11al dogru agy sirasi kabul edildi"; else bad "11al dogru agy sirasi" "check dogru sirayi reddetti (kural fazla katı)"; fi

unset CACHY_AGENT_CONFIG

# 12. (Task 1'de planlandı ama atlandı) `WORKDIR` varsayılanı
# §5.1'de belirtiliyordu; test 11ag geriye uyumu zaten ölçüyor. Burada
# KONUM kazanımı yok; bilinçli olarak eklenmedi (plan §7.2'de "12 (yeni)"
# vardı ama 11ag aynı şeyi daha iyi ölçüyor ve ayrı test kazandırmaz).

# 18. usage-fetch semasi + XDG_STATE_HOME (Task 7)
#
# Plasmoid main.qml bu script'in stdout'unu JSON.parse edip providers[]/alarm
# okuyor; `cachy-agent usage` da aynı script'i summary modunda çalıştırıyor.
# İki tüketici tek sözleşmede buluşur (bkz. docs/usage-schema.md).
#
# HOME sabitlemesi (18a-18e) mutasyon kanıtıdır: eski main.qml gömülü python'u
# ~/.local/state hardcoded idi (Task 7 defekt-1). XDG_STATE_HOME'u yok sayıp
# $HOME/.local/state'e dönen bir sürüm, sahte eve (BOŞ) düşeceği için 18a/18b
# KIRMIZI olur — gerçek kullanıcının ~/.local/state içeriğine rastgele bağımlı
# olmadan, her makinede.
FXHOME="$SCRATCH_ROOT/fetch-home"; mkdir -p "$FXHOME"
FX="$SCRATCH/fetch"
mkdir -p "$FX/agents/usage"
cat > "$FX/agents/usage/codex.json" <<'J'
{"schemaVersion":1,"id":"codex","name":"Codex","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"pro","limits":[{"label":"5h","percent":0.42,"resetsAt":"2026-10-07T12:00:00Z"}],"todayPrompts":3,"todaySessions":1,"todayTotalTokens":10,"totalPrompts":9,"totalSessions":4}
J
cat > "$FX/agents/usage/copilot.json" <<'J'
{"schemaVersion":1,"id":"copilot","name":"Copilot","updatedAt":"2026-10-06T00:00:00Z","ready":false,"tierLabel":"","limits":[],"todayPrompts":0,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0,"reason":"no CLI quota command"}
J
mkdir -p "$XDG_STATE_HOME/cachy-agent/agents"
cp -r "$FX/agents/usage" "$XDG_STATE_HOME/cachy-agent/agents/"
out=$(HOME="$FXHOME" cachy-agent-usage-fetch 2>/dev/null); rc=$?
ok_json=$(printf '%s' "$out" | python3 -c 'import json,sys; d=json.load(sys.stdin); p={x["id"]:x for x in d["providers"]}; assert p["codex"]["today"]==3 and p["codex"]["total"]==9 and abs(p["codex"]["limits"][0]["percent"]-0.42)<1e-9 and d["alarm"] is False; assert p["copilot"]["name"]=="Copilot"; print("OK")' 2>&1)
if [[ $rc -eq 0 && "$ok_json" == "OK" ]]; then ok "18a fetch semasi"; else bad "18a fetch semasi" "rc=$rc py='$ok_json'"; fi
# XDG_STATE_HOME okunuyor (eski gömülü kod hardcoded ~/.local/state'e bakıyordu)
if printf '%s' "$out" | grep -q codex; then ok "18b XDG_STATE_HOME okundu"; else bad "18b XDG_STATE_HOME" "codex yok"; fi
# alarm esigi: >=0.9 (0.42 -> False 18a'da ölçüldü; 0.95 -> True burada)
cat > "$FX/agents/usage/codex.json" <<'J'
{"schemaVersion":1,"id":"codex","name":"Codex","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"","limits":[{"label":"5h","percent":0.95,"resetsAt":null}],"todayPrompts":0,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":0,"totalSessions":0}
J
cp "$FX/agents/usage/codex.json" "$XDG_STATE_HOME/cachy-agent/agents/usage/codex.json"
al=$(HOME="$FXHOME" cachy-agent-usage-fetch 2>/dev/null | python3 -c 'import json,sys; print(json.load(sys.stdin)["alarm"])' 2>/dev/null)
if [[ "$al" == "True" ]]; then ok "18c alarm esigi >=0.9"; else bad "18c alarm" "alarm=$al"; fi
# summary modu: eski `cachy-agent usage` satır formatı, bu kez GERÇEK değerlerle
# (eski gömülü tek satır limits[].usedPercent/limits[].name/today/total okuyordu;
# hiçbiri kolektörlerde yoktu — her kayıt "?" basıyordu, Task 7 defekt-2)
sum=$(HOME="$FXHOME" cachy-agent-usage-fetch summary 2>/dev/null); rc=$?
if [[ $rc -eq 0 && "$sum" == *"codex: today=0 total=0 limits[5h 95%]"* ]]; then
  ok "18d summary modu"
else
  bad "18d summary modu" "rc=$rc sum='$(printf '%s' "$sum" | tr '\n' '/')'"
fi
# ready:false + reason summary'de görünür (copilot'un reason'u hiç okunmuyordu)
if [[ "$sum" == *"copilot: veri yok (no CLI quota command)"* ]]; then
  ok "18e summary ready:false + reason gosteriyor"
else
  bad "18e summary reason" "sum='$(printf '%s' "$sum" | tr '\n' '/')'"
fi
# boş durumda stdout BOŞ DEĞİL: main.qml stdout=="" -> "boş çıktı" hatası
EMPT="$SCRATCH_ROOT/fetch-empty-state"; mkdir -p "$EMPT/cachy-agent/agents/usage"
outf=$(XDG_STATE_HOME="$EMPT" HOME="$FXHOME" cachy-agent-usage-fetch 2>/dev/null); rc=$?
if [[ $rc -eq 0 && "$outf" == '{"providers":[],"alarm":false}' ]]; then
  ok "18f bos kayitta da providers JSON basiliyor"
else
  bad "18f bos kayitta providers JSON" "rc=$rc out='$outf'"
fi
# 18g. NaN/Infinity sayaç ve percent: çökme YOK, çıktı KATI JSON (fix-round I-2)
#
# Ulaşılabilir yol: usage-update'in doğrulayıcısı json.loads'tur ve NaN/
# Infinity token'larını KABUL eder — yani böyle bir kayıt state'e yazılabilir.
# fetch iki şeyi aynı anda yapmalı: çökmemeli (ValueError: cannot convert
# float NaN to integer) ve bare NaN/Infinity token BASMAMALI (QML'in
# JSON.parse'u katıdır; bare token -> "parse hatası").
# Bare token'lar json.dumps ile ÜRETİLEMEZ; fixture elle yazılır.
NANFX="$SCRATCH_ROOT/fetch-nan-state"
mkdir -p "$NANFX/cachy-agent/agents/usage"
printf '%s\n' '{"schemaVersion":1,"id":"nanagent","name":"Nan","updatedAt":"2026-10-06T00:00:00Z","ready":true,"tierLabel":"","limits":[{"label":"5h","percent":NaN,"resetsAt":null}],"todayPrompts":NaN,"todaySessions":0,"todayTotalTokens":0,"totalPrompts":Infinity,"totalSessions":0}' > "$NANFX/cachy-agent/agents/usage/nanagent.json"
n_out=$(XDG_STATE_HOME="$NANFX" HOME="$FXHOME" cachy-agent-usage-fetch 2>/dev/null); rc=$?
n_ok=$(printf '%s' "$n_out" | python3 -c 'import json,sys
raw = sys.stdin.read()
assert "NaN" not in raw and "Infinity" not in raw, "bare token kaldi: " + raw
d = json.loads(raw, parse_constant=lambda c: (_ for _ in ()).throw(ValueError(c)))
p = d["providers"][0]
assert p["today"] == 0 and p["total"] == 0 and p["limits"] == [] and d["alarm"] is False
print("OK")' 2>&1)
n_sum=$(XDG_STATE_HOME="$NANFX" HOME="$FXHOME" cachy-agent-usage-fetch summary 2>/dev/null); n_rc=$?
if [[ $rc -eq 0 && "$n_ok" == "OK" && $n_rc -eq 0 && "$n_sum" == *"nanagent: today=0 total=0 limits[-]"* ]]; then
  ok "18g NaN/Infinity kayitinda cokme yok, katı JSON basiliyor"
else
  bad "18g NaN kayit" "rc=$rc py='$n_ok' sum_rc=$n_rc sum='$(printf '%s' "$n_sum" | tr '\n' '/')'"
fi

# 16. KRITIK-1 — config parser'ı LOCALE BAĞIMSIZ olmalı.
#
# `[[ "$id" =~ ^[A-Za-z0-9_-]+$ ]]` bash'te POSIX karakter ARALIKLARINI
# collation ile yorumlar. tr_TR.UTF-8 altında `i` ve `ı` ayrı harflerdir;
# `[A-Za-z]` içinde `I` vardır ama `i` YOKTUR. Sonuç: id `copilot` reddedilir
# ve `check` kullanıcının kendi gecerli config'inde exit 1 verir.
#
# Bu hata Task 1'den beri vardı ve görünmezdi: o zamanki testler C locale
# altında çalışıyordu. Projenin tek hedef platformu ise tr_TR — yani hata
# ürünün YALNIZ gerçek hedefinde bozuluyordu.
#
# Düzeltme `cachy-agent-agents` içinde: `unset LC_ALL` + `export LC_COLLATE=C`.
# (`LC_ALL`, `LC_COLLATE`'yi ezer; yalnız `LC_COLLATE=C` yetmezdi.)
#
# SKIP: `tr_TR.UTF-8` her CI runner'da üretilmiş olmayabilir. Locale yoksa
# test ATLANIR — exit kodu etkilemez, ama bulunduğu her yerde ÇALIŞIR.
if locale -a 2>/dev/null | grep -qi '^tr_TR\.utf-\?8$'; then
  # Not: exit kodu `$?` ile DEĞİL, `if` üzerinden alınıyor (SC2181). Arada
  # `head`/`tr` çalıştırırsak `$?` onların kodunu taşır ve test yanlış yeşil
  # olur — test.sh'in bu dosyasındaki başka onlarca testte de aynı tuzak var.
  if LC_ALL=tr_TR.UTF-8 CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
       "$AG" check >/dev/null 2>&1; then
    ok "16 check tr_TR.UTF-8 altinda gecerli config'i kabul eder"
  else
    err16=$(LC_ALL=tr_TR.UTF-8 CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
      "$AG" check 2>&1 >/dev/null | head -2 | tr '\n' ' ')
    bad "16 check tr_TR altinda basarisiz" "$err16"
  fi
  # Ters yön: locale SABİTLENMELİ, sadece reddedilmeme değil. tr collation
  # altında `ı` normal ASCII değildir; C collation'da da reddedilmesi gerekir
  # ama gerekçe farklıdır. Asıl ölçüm: i doğru kabul ediliyor.
  # `CACHY_AGENT_CONFIG` BURADA ŞART: 16b config'i ortamdan çözer
  # (${CACHY_AGENT_CONFIG:-${XDG_CONFIG_HOME:-...}/cachy-agent/agents.conf}).
  # Suite başında XDG_CONFIG_HOME geçici köke çevrildiği için — ve o kökte
  # agents.conf YOKTUR — sabitlemesiz bu çağrı "config dosyası yok" deyip boş
  # dönüyor ve test sessizce kırmızı oluyordu. (Bu, blok 11'in en sonda
  # `unset CACHY_AGENT_CONFIG` dediği için 16'ya sızıyordu.)
  got16=$(LC_ALL=tr_TR.UTF-8 CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf" \
    "$AG" get copilot name 2>/dev/null)
  if [[ "$got16" == "Copilot CLI" ]]; then
    ok "16b get tr_TR altinda dogru alan donuyor"
  else
    bad "16b get tr_TR" "got='$got16'"
  fi
  # Noktasiz i (U+0131) GERCEKTEN reddedilmeli: C collation onu ASCII harf
  # saymaz. Kabul edilseydi id bir dosya yoluna girebilirdi.
  printf 'WORKDIR=/a\ndı=I|x|-|y|-\n' > "$SCRATCH/dotless.conf"
  if LC_ALL=tr_TR.UTF-8 CACHY_AGENT_CONFIG="$SCRATCH/dotless.conf" "$AG" check >/dev/null 2>&1; then
    bad "16c noktasiz i iceren id reddedilir" "check KABUL etti (exit 0), reddetmeliydi"
  else
    ok "16c noktasiz i iceren id reddedilir"
  fi
  # Türkçe karakterli GÖRÜNEN AD parse edilebilmeli: sabitleme LC_COLLATE'yi
  # değiştirdi, LC_CTYPE'ye dokunmadı. Buradaki hata, "çözüm"ün karakter
  # işlemeyi bozduğunu gösterirdi.
  printf 'WORKDIR=/a\ncodex=Çok Özel|x|-|y|zğüşöç\n' \
    > "$SCRATCH/trchars.conf"
  got16c=$(LC_ALL=tr_TR.UTF-8 CACHY_AGENT_CONFIG="$SCRATCH/trchars.conf" "$AG" get codex login 2>/dev/null)
  if [[ "$got16c" == "zğüşöç" ]]; then
    ok "16d turkce karakterli degerler bozulmadan parse ediliyor"
  else
    bad "16d turkce karakterler" "got='$got16c'"
  fi
else
  skip "16 tr_TR.UTF-8 locale kontrolleri (ortam yok: locale -a kontrol et)"
fi

# 13. install.sh --prefix / uninstall.sh --prefix
#
# `--prefix` bir "kurulum modu" değil, **izole kurulum** mekanizması (spec §7.1):
# tüm yollar geçici bir dizinin altına yazılır.
#
# Alt dizin yapısı (plan Task 4 Step 4'te SABİTLENMİŞTİR):
#   ${PFX}/.local/bin/ · $PFX/config/cachy-agent/ · $PFX/config/fish/conf.d/
#   $PFX/config/systemd/user/ · $PFX/config/fuzzel/ · $PFX/applications/
#   $PFX/icons/ · $PFX/plasmoids/org.cachyagent.usage/
#   ($PFX/state/ YARATILMAZ — I2, aşağıda)
#
# DİKKAT (brifin kendi içinde çelişki var): planın Step 1'deki 13b snippet'i
# `$PFX/fish/conf.d` ve `$PFX/systemd/user` diyordu; hemen altındaki paragraf ve
# Step 4'ün yol haritası ikisini de `$PFX/config/...` altında sabitliyor. İki
# kaynak `config/`'li yapıda birleşiyor, snippet tek başına kalmış — uygulama ve
# test `config/`'li yapıyı kullanır (bkz. task-4-report.md, Sapma D1).
#
# `</dev/null` KALICI: install.sh eksik bağımlılıkta onay `read`'i yapıyor; TTY'li
# bir test koşumunda bu, testi süresiz bekletirdi. --prefix kipi onayı
# zaten atlar (bkz. install.sh), `</dev/null` ise bunu testte de garantiler.
#
# ============================================================================
# SANDBOX — blok 13'ün TAMAMI, bu sınırın içinde çalışır (C1)
# ============================================================================
# Bulgu: 13i kendi `systemctl` stub'ını kuruyor ama YALNIZCA kendi iki
# çağrısında kullanıyordu; 13a/13c/13e/13f `install.sh`/`uninstall.sh`'i
# ÇIPLAK çalıştırıyordu. Ölçülen sonuç (pre-Task-4 install.sh = 1678f1c):
# 13a **PASS** — eski script `--prefix`'i sessizce yok sayıp GERÇEK $HOME'a
# kuruyor ve exit 0 dönüyor. 13b tek itiraz eden testti, ama 26 dosya
# YAZILDIKTAN SONRA. Testin işi bu regresyonu YAZMADAN yakalamak.
#
# İki BAĞIMSIZ katman — ikisi de gerekli, biri diğerinin yerine geçmez:
#
#  (1) `HOME=$PFXROOT/fakehome` + XDG_* UNSET.
#      `--prefix` tamamen yok sayılsa bile script'in yazma hedefi sahte ev
#      olur. XDG_*'in unset edilmesi şart: `HOME`'u çevirmek tek başına
#      yeterli değil, `install.sh` CONFIG_DIR'ı `${XDG_CONFIG_HOME:-...}`
#      üzerinden çözer ve gerçek XDG_CONFIG_HOME kaçak yol olurdu.
#
#  (2) `systemctl` + `kbuildsycoca6` + `desktop-file-validate` stub'ı.
#      Üçü de GERÇEK sistemi değiştiren komutlar: systemd kullanıcı oturumu,
#      KDE ikon cache'i, desktop doğrulaması. Bir mutant bunları çağırırsa
#      kaydedilir.
#      Bu üçlü olmadan 13'in kendisi kullanıcının makinesini bozabilir —
#      mutation ölçümü sırasında fiilen oldu: mutant `disable --now`
#      çağırınca gerçek `cachy-crash-watch.service` durdu (bkz. rapor E6).
#      İki ayrı reviewer da aynı yere takıldı.
#
# `pfx_run` tek giriş noktasıdır: blok 13'teki HER install/uninstall çağrısı
# ondan geçer. Böylece yeni bir çağrı eklendiğinde korumasız kalmaz.
SB_STUB="$PFXROOT/stub"; mkdir -p "$SB_STUB"
for _c in systemctl kbuildsycoca6 desktop-file-validate; do
  cat > "$SB_STUB/$_c" <<EOF
#!/usr/bin/env bash
printf '%s CALISTI: %s\n' "$_c" "\$*" >> "\$SB_LOG"
exit 0
EOF
  chmod +x "$SB_STUB/$_c"
done
export SB_LOG="$PFXROOT/hostcalls.log"

# Gerçek $HOME saklanıyor: blok sonunda geri alınacak. 13h tek başına
# yeterli değil — sahte ev komple taranıyor (13j) ve PATH stub'ı çıkarılıyor.
REAL_HOME="$HOME"
# 13h GERÇEK config'i izleyecek. Yol dosyanın BAŞINDA sabitlendi (REAL_CONF_DIR)
# — burada yeniden türetmek YANLIŞ olurdu: suite başında XDG_CONFIG_HOME geçici
# köke çevrildiği için `${XDG_CONFIG_HOME:-$HOME/.config}` artık SAHTE config'i
# gösterirdi ve 13h kendi yazdığı sahte config'i "değişmedi" bulup BOŞ GEÇERdi.
REAL_CONF="$REAL_CONF_DIR/agents.conf"
REAL_CONF_BEFORE="yok"
[[ -f "$REAL_CONF" ]] && REAL_CONF_BEFORE=$(cksum < "$REAL_CONF")

export SB_HOME="$PFXROOT/fakehome"; mkdir -p "$SB_HOME"
export HOME="$SB_HOME"
unset XDG_CONFIG_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_CACHE_HOME

# pfx_run <script> <prefix> [ek args...] — blok 13'ün tek giriş noktası.
# Yazabileceği her yer $PREFIX ve $HOME(=fakehome) ile sınırlı; systemd/KDE
# stub'ı üzerinden.
pfx_run() {
  local script="$1" prefix="$2"; shift 2
  PATH="$SB_STUB:$PATH" HOME="$SB_HOME" bash "$script" --prefix "$prefix" "$@" \
    </dev/null >/dev/null 2>&1
}
: > "$SB_LOG"

PFX="$PFXROOT/pfx"
if pfx_run "$REPO/install.sh" "$PFX"; then a_rc=0; else a_rc=$?; fi
# M-1 + C1.3: 13a artık SADECE exit koduna bakmıyor; prefix ağacının gerçekten
# dolduğunu da iddia ediyor. `--prefix`'i yok sayan bir script exit 0 döndüğü
# halde burada KIRMIZI olur — çünkü ağaç boş kalır.
a_tree=1
for f in "${PFX}/.local/bin/cachy-agent" "$PFX/config/cachy-agent/agents.conf"; do
  [[ -f "$f" ]] && a_tree=0
done
if [[ $a_rc -eq 0 && $a_tree -eq 0 ]]; then
  ok "13a install --prefix exit 0 + agac $PFX altinda"
else
  bad "13a install --prefix" "rc=$a_rc agac_dolu=$((1-a_tree)) — rc=0 tek basina yeterli degil"
fi
missing=""
for f in "${PFX}/.local/bin/cachy-agent" "${PFX}/.local/bin/cachy-agent-agents" "$PFX/config/cachy-agent/agents.conf" \
         "$PFX/config/fish/conf.d/cachy-agent.fish" \
         "$PFX/applications/cachy-agent.desktop" "$PFX/applications/cachy-agent-usage.desktop" \
         "$PFX/config/systemd/user/cachy-crash-watch.service" \
         "$PFX/config/systemd/user/cachy-agent-usage-refresh.service" \
         "$PFX/config/systemd/user/cachy-agent-usage-refresh.timer" \
         "$PFX/plasmoids/org.cachyagent.usage/metadata.json" \
         "$PFX/plasmoids/org.cachyagent.usage/contents/ui/main.qml" \
         "$PFX/config/fuzzel/fuzzel.ini" "$PFX/icons/cachy-agent.svg" \
         "${PFX}/.local/bin/cachy-agent-usage-opencode" "${PFX}/.local/bin/cachy-agent-usage-codex" \
         "${PFX}/.local/bin/cachy-agent-usage-panel" "${PFX}/.local/bin/cachy-agent-usage-update" \
         "${PFX}/.local/bin/cachy-crash-watch" "${PFX}/.local/bin/cachy-notify-action.py" \
         "${PFX}/.local/bin/VERSION"; do
  [[ -f "$f" ]] || missing="$missing${f#"$PFX"/} "
done
if [[ -z "$missing" ]]; then ok "13b --prefix dosyalari yerinde"; else bad "13b --prefix" "yok: $missing"; fi

# 13b-4 (M-4): "listelenenler var" demek, ağaçta FAZLA dosya bırakılmasını
# sessizce geçirirdi. Bu yüzden ağacın TAMAMINI tarayıp beklenen listede
# olmayan dosya arıyoruz. BOŞ DİZİNLER kabul: gerçek $HOME kurulumu da öyle
# bırakır (ör. $PFX/state/ hiç oluşmadı — I2).
# `sort` de LC_ALL=C ile: aksi halde sıralama collation'a bağlı olur ve
# `cachy-agent.desktop` / `cachy-agent-usage.desktop` gibi iki satır tr_TR
# altında BAŞKA sırayla gelir — test kendi listesini yanlış bulur. (KRITIK-1'in
# test tarafındaki kardeşi: karşılaştırma da deterministik olmalı.)
got_files=$(cd "$PFX" && find . -type f | sed 's#^\./##' | LC_ALL=C sort)
want_files=$(cat <<'EOF'
.local/bin/VERSION
.local/bin/cachy-agent
.local/bin/cachy-agent-agents
.local/bin/cachy-agent-crash
.local/bin/cachy-agent-install
.local/bin/cachy-agent-menu
.local/bin/cachy-agent-open
.local/bin/cachy-agent-usage-alarm
.local/bin/cachy-agent-usage-codex
.local/bin/cachy-agent-usage-copilot
.local/bin/cachy-agent-usage-fetch
.local/bin/cachy-agent-usage-oneline
.local/bin/cachy-agent-usage-opencode
.local/bin/cachy-agent-usage-panel
.local/bin/cachy-agent-usage-update
.local/bin/cachy-crash-watch
.local/bin/cachy-notify-action.py
applications/cachy-agent-usage.desktop
applications/cachy-agent.desktop
config/cachy-agent/agents.conf
config/fish/conf.d/cachy-agent.fish
config/fuzzel/fuzzel.ini
config/systemd/user/cachy-agent-usage-refresh.service
config/systemd/user/cachy-agent-usage-refresh.timer
config/systemd/user/cachy-crash-watch.service
icons/cachy-agent.svg
plasmoids/org.cachyagent.usage/contents/ui/main.qml
plasmoids/org.cachyagent.usage/metadata.json
EOF
)
tree_diff=$(diff <(printf '%s\n' "$want_files") <(printf '%s\n' "$got_files"))
if [[ -z "$tree_diff" ]]; then
  ok "13b-4 --prefix agaci tam olarak beklenen dosyalar"
else
  bad "13b-4 --prefix agaci beklenenden farkli" "$(printf '%s' "$tree_diff" | tr '\n' '/')"
fi

# 13b-2. Ters yön: yanlış yere (config/ OLMADAN) sızan dosya olmamalı.
# Sadece "doğru yerde var" demek, install.sh'in aynı dosyayı İKİ yere birden
# yazmasını sessizce geçirirdi. `config/`'li yerleşimi iki yönden kilitliyoruz.
stray=""
for f in "$PFX/fish/conf.d/cachy-agent.fish" "$PFX/systemd/user/cachy-crash-watch.service"; do
  [[ -e "$f" ]] && stray="$stray${f#"$PFX"/} "
done
if [[ -z "$stray" ]]; then ok "13b-2 --prefix yanlis yere sizmadi"; else bad "13b-2 --prefix sizinti" "asiri: $stray"; fi

# 13b-3. `__HOME__` genişletmesi prefix'e olmalı (spec §7.1): desktop dosyası
# test prefix'ini MUTLAK yol olarak gösterir.
HOME_LEFT=""
for f in "$PFX/applications/cachy-agent.desktop" "$PFX/applications/cachy-agent-usage.desktop" \
         "$PFX/plasmoids/org.cachyagent.usage/contents/ui/main.qml"; do
  [[ -e "$f" ]] || continue
  grep -q '__HOME__' "$f" && HOME_LEFT="$HOME_LEFT$(basename "$f"):__HOME__ "
  grep -q "$PFX" "$f" || HOME_LEFT="$HOME_LEFT$(basename "$f"):prefix-yok "
done
if [[ -z "$HOME_LEFT" ]]; then ok "13b-3 __HOME__ prefix ile genisletildi"; else bad "13b-3 __HOME__ genislemesi" "$HOME_LEFT"; fi

  # 13b-5. Genişletme yapılmış olması YETMEZ: üretilen Exec/fetchCommand
  # yolları GERÇEKTEN var olmalı. Önceki hâlde binary'ler $PREFIX/bin'e
  # giderken şablonlar __HOME__/.local/bin diyordu; 13b ve 13b-3 ikisini de
  # geçiyordu ama üretilen bütün desktop/plasmoid girdileri VAR OLMAYAN bir
  # yola işaret ediyordu. Yani testler yeşildi, kurulum kırıktı.
  _yolsuz=""
  while IFS= read -r _y; do
    _y="${_y//\%U/}"; _y="${_y//\%u/}"
    [[ -x "$_y" ]] || _yolsuz="$_yolsuz $(basename "$_y") "
  done < <(grep -hoE '(Exec|fetchCommand|catalogCommand)="[^"]+"' \
             "$PFX"/applications/*.desktop \
             "$PFX"/plasmoids/org.cachyagent.usage/contents/ui/main.qml 2>/dev/null \
           | sed -E 's/^[A-Za-z]+="//; s/"$//')
  if [[ -z "$_yolsuz" ]]; then
    ok "13b-5 uretilen tum yollar var"
  else
    bad "13b-5 uretilen yol yok" "yok:$_yolsuz"
  fi

# 13k (I3). `--prefix` REDDEDİLMEDEN ÖNCE mutlaklaştırılmalı ve sed'e özel
# karakter içermemeli. Ölçülen üç sessiz bozulma:
#   --prefix relpfx        -> Exec=relpfx/…        (göreli yol, spec ihlali)
#   --prefix '/tmp/a&b\c'  -> Exec=/tmp/a__HOME__b\ (rc=0, __HOME__ bile kaldı)
#   --prefix '/tmp/a|b'    -> rc=1, teşhissiz sed patlaması
# Göreli prefix testi SANDBOX İÇİNDE ve BİR ALT-SÜREÇTE çalışmalı:
#  - göreli yol, çağıranın CWD'sine göre yorumlanır. CWD $REPO olsaydı test
#    REPOYU kirletirdi — bu turda tam olarak oldu:
#    `src/plasmoid/org.cachyagent.usage/relpfx13k/` git'in "untracked" listesine
#    düştü ve 13b-4 onu "fazladan dosya" olarak yakaladı. Test 13'ün işi de
#    tam olarak budur: kaza olmadan yakalamak.
#  - `cd` alt süreçte yapılıyor ki test.sh'in kendi CWD'si hiç değişmesin
#    (13b-4 ve 13d göreli yollarla çalışıyor).
k_exec=""
k_relative=0
k_probe="$SB_HOME/relpfx13k"
(
  cd "$SB_HOME" || exit 1
  PATH="$SB_STUB:$PATH" HOME="$SB_HOME" bash "$REPO/install.sh" --prefix relpfx13k \
    </dev/null >/dev/null 2>&1 && printf '0\n' > "$PFXROOT/.krel" \
                            || printf '1\n' > "$PFXROOT/.krel"
)
if [[ -f "$PFXROOT/.krel" ]] && [[ "$(cat "$PFXROOT/.krel")" == "0" ]]; then
  k_relative=1
fi
if [[ -f "$k_probe/applications/cachy-agent.desktop" ]]; then
  k_exec=$(grep -m1 '^Exec=' "$k_probe/applications/cachy-agent.desktop")
fi
rm -rf "$k_probe" "$PFXROOT/.krel"
# sed'e özel karakterli prefix'ler REDDEDİLMELİ:
#   &  -> sed'de "eşleşen metin"; sessizce bozuk .desktop üretirdi
#   |  -> sed'de alan ayırıcı; script'i patlatırdı (teşhissiz rc=1)
#   \  -> kaçış karakteri
# Her biri exit 2 vermeli. Bu satır MUTASYONUN KENDİSİNİ de ölçer:
# install.sh reddi kaldırırsa k_bad=1 olur.
k_bad=0
for p in "$PFXROOT/bad&x" "$PFXROOT/bad|x" "$PFXROOT/bad\\x"; do
  PATH="$SB_STUB:$PATH" HOME="$SB_HOME" bash "$REPO/install.sh" --prefix "$p" \
    </dev/null >/dev/null 2>&1 && k_bad=1
done
rm -rf "$SB_HOME/relpfx13k" "$PFXROOT/bad&x" "$PFXROOT/bad|x" "$PFXROOT/bad\\x"
if [[ $k_relative -eq 1 && "$k_exec" == Exec=/* && $k_bad -eq 0 ]]; then
  ok "13k --prefix mutlaklastirilir, sed ozel karakteri reddedilir"
else
  bad "13k --prefix normalizasyonu" "goreli_kabul=$k_relative exec='$k_exec' ozel_kabul=$k_bad"
fi

# 13l (I2). install.sh durum dizini OLUŞTURMAMALI.
# Ölçülen etki: `mkdir -p` listesinde STATE_DIR varken, temiz bir $HOME'da
# `uninstall.sh` "(yok: ~/.local/state/cachy-agent)" yerine etkileşimli
# `ask` basıyordu — kullanıcı hiç dokunmadığı bir dizin için soruya düşüyordu.
# Mutation (STATE_DIR'yi listeye geri koy) bu testi kırmızı yapıyor.
pfx_run "$REPO/install.sh" "$PFXROOT/pfx-state"
if [[ -d "$PFXROOT/pfx-state/state" ]]; then
  bad "13l install.sh state dizini olusturdu" "kullanici hic kullanmadi, uninstall soracak"
  rm -rf "$PFXROOT/pfx-state/state"
else
  ok "13l install.sh state dizini olusturmuyor (I2)"
fi
rm -rf "$PFXROOT/pfx-state"

if pfx_run "$REPO/uninstall.sh" "$PFX"; then c_rc=0; else c_rc=$?; fi
left=""
while IFS= read -r f; do
  left="$left${f#"$PFX"/} "
done < <(cd "$PFX" && find . -type f 2>/dev/null | sed 's#^\./##' | sort)
if [[ $c_rc -eq 0 && -z "$left" ]]; then
  ok "13c/13d uninstall --prefix exit 0 ve agaci tamamen temizledi"
else
  bad "13c/13d uninstall --prefix" "rc=$c_rc kaldi: $left"
fi

# 13e. ikinci calistirma (idempotans)
if pfx_run "$REPO/uninstall.sh" "$PFX"; then ok "13e uninstall iki kez calisir"; else bad "13e uninstall idempotent" "exit=$?"; fi

# 13f. `agents.conf` YALNIZCA YOKKEN yazilir; kullanicinin duzenlemesi her
# kurulumda korunur. Bu, catalog dosyasinin tek amaci: v0.1.0'da ajan listesi
# script'lerin icindeydi, kurulum hicbir seyi yazmiyordu; simdi dosya yaziliyor ve
# `cp -f` kullanilsa kullanici listenin uzerine yazilirdi.
PFX2="$PFXROOT/pfx2"
pfx_run "$REPO/install.sh" "$PFX2" || true
if [[ -f "$PFX2/config/cachy-agent/agents.conf" ]]; then
  printf '\n# kullanici duzenlemesi\n' >> "$PFX2/config/cachy-agent/agents.conf"
  before_sum=$(cksum < "$PFX2/config/cachy-agent/agents.conf")
  pfx_run "$REPO/install.sh" "$PFX2"; rc=$?
  after_sum=$(cksum < "$PFX2/config/cachy-agent/agents.conf")
  if [[ $rc -eq 0 && "$before_sum" == "$after_sum" ]]; then
    ok "13f yeniden kurulum agents.conf'i EZMIYOR (kullanici duzenlemesi korunur)"
  else
    bad "13f agents.conf ezildi" "rc=$rc once=$before_sum sonra=$after_sum"
  fi
else
  bad "13f agents.conf yazilmadi" "$PFX2/config/cachy-agent/agents.conf yok"
fi

# 13g. IZLEME KONUMU: --prefix kurulumu config'i PREFIX'in altina yaziyor,
# `cachy-agent-agents` ise config'i
#   ${CACHY_AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent/agents.conf}
# yolundan cozuyor. Iki sozlesme birbirini TUTMADI (veya tutmayacak)sa indirme
# sessizce "config yok" dersin ve menu `agent listesi alinamadi` ile exit 1
# verir. Bu test kurulan config'in ayni CLI tarafindan okunabildigini kanitlar.
if CACHY_AGENT_CONFIG="$PFX2/config/cachy-agent/agents.conf" \
     "$REPO/src/bin/cachy-agent-agents" check >/dev/null 2>&1; then
  ok "13g kurulan agents.conf cachy-agent-agents tarafindan okunuyor"
else
  bad "13g kurulan config okunamadi" "check exit=$? — indirme menu acmaz"
fi
rm -rf "$PFX2"

# 13h. --prefix KURULUMU config'i PREFIX altina yazar, `~/.config` altina DEGIL.
# Yanlislikla gercek config'i yazmak, testin calistigi makinedeki kullanicinin
# katalog dosyasini ezmektir (ve aslinda onu DUZELTIRDIĞINI sanip sessizce
# yeni ajanlarin listesini degistirmek olurdu). REAL_CONF, sandbox'a girmeden
# ÖNCE sabitlendiği için bu gerçekten kullanıcının config'idir.
REAL_CONF_AFTER="yok"
[[ -f "$REAL_CONF" ]] && REAL_CONF_AFTER=$(cksum < "$REAL_CONF")
if [[ "$REAL_CONF_BEFORE" == "$REAL_CONF_AFTER" ]]; then
  ok "13h --prefix gercek ~/.config altina YAZMADI (yalnizca prefix)"
else
  bad "13h --prefix gercek config'e dokundu" "$REAL_CONF: once=$REAL_CONF_BEFORE sonra=$REAL_CONF_AFTER"
fi

# 13i (I1). `--prefix` kurulumunda systemd VE KDE komutları ÇAĞRILMAZ
# (spec §7.1: "preflight'in systemctl/kbuildsycoca6/desktop-file-validate
# adımları atlanır").
#
# Bu bir "iyi olurdu" değil: uninstall --prefix'in prefix'teki unit dosyalarını
# silerken `systemctl --user disable --now` çağırması, dosyalar prefix'te olsa
# bile GERÇEK oturumdaki çalışan servisleri sustururdu — `bash tests/test.sh`
# kullanıcının kurulumunu kapatırdı. Mutation ölçümünde fiilen oldu.
#
# Üçü de aynı log'a yazılır; eski stub seti YALNIZCA systemctl'i kapsıyordu,
# bu yüzden kbuildsycoca6 sızıntısı (MUT-C) sessizce yeşildi.
pfx_run "$REPO/install.sh" "$PFXROOT/pfx3"
pfx_run "$REPO/uninstall.sh" "$PFXROOT/pfx3"
i_log="$(cat "$SB_LOG" 2>/dev/null || true)"
if [[ -z "$i_log" ]]; then
  ok "13i --prefix systemctl/kbuildsycoca6/desktop-file-validate cagirmiyor"
else
  bad "13i --prefix host komutu cagirdi" "$i_log"
fi

# 13j (C1'nin ikinci katmanı). `--prefix` TAMAMEN YOK SAYILSA bile hiçbir şey
# sandbox'ın dışına yazılmamalı. 13h tek bir config dosyasına bakar; burada
# sahte evin TAMAMI taranıyor. `--prefix`'i yok sayan script sahte eve yazar
# (korumasız kalsaydı gerçek eve yazardı) ve bu test KIRMIZI olur.
j_home_files=""
[[ -d "$SB_HOME" ]] && j_home_files=$(cd "$SB_HOME" && find . -type f | sed 's#^\./##' | sort)
if [[ -z "$j_home_files" ]]; then
  ok "13j --prefix yok sayilsa bile sandbox disina yazmiyor (sahte ev bos)"
else
  bad "13j --prefix sahte eve yazti" "$(printf '%s' "$j_home_files" | tr '\n' ' ')"
fi

# Blok sonu: stub dizinini PATH'ten ÇIKAR. `HOME` GERÇEK $HOME olarak kalır —
# geri alma şart: test 3/4/5/6/7/8/9 gerçek kurulumu okuyor, blok 13'ün
# sandbox'ında kalsalardı yanlış şeyi sınarlardı. `HOME`'u geri almak için
# kaydetmiş olduğumuz REAL_HOME kullanılır (sandbox $HOME'yu değiştirdi).
export PATH="${PATH#"$SB_STUB":}"
export HOME="$REAL_HOME"
# Sandbox, XDG_*'i UNSET etmişti (C1'nin (1) katmanı: gerçek XDG_CONFIG_HOME
# kaçık yol olurdu). Blok bittikten sonra GERİ konur — 14/15 kendi ortamını
# kursa da, sonraki blokların geçici köke bağlı kaldığı varsayılıyor.
export XDG_CONFIG_HOME="$SAVED_XDG_CONFIG"
export XDG_STATE_HOME="$SAVED_XDG_STATE"
unset SB_LOG
rm -rf "$SB_STUB" "$SB_HOME"

# 17c (I-1). SENTİNEL KENDİ KENDİNİ SALTANMIŞ MI?
#
# Bu blok, 17a/17b'nin ÖLÇÜMDE GEÇERLİ olduğunun kanıtıdır — asıl test değil.
# 17a/17b `REAL_CONF_DIR`/`REAL_STATE_DIR` yollarını korunan dizin sanar. Bu
# iki değişken dosyanın BAŞINDA, XDG_* ÇEVRİLMEDEN ÖNCE sabitlenmiştir; bu
# sıralama bir YORUM değil, testin tek dayandığı şeydir. Sıralama bozulursa
# (sentineller çevrimden sonra yeniden türetilirse) korunan dizin SAHTE kök
# olur, suite sahte köke yazdığı için parmak izi "değişmedi" görünür ve
# 17a/17b kullanıcının GERÇEK config/state ağacını sessizce korumasız bırakır.
#
# BU TUZAK BU DEPOYA İKİ KEZ DÜŞTÜ: Task 4'te `REAL_CONF_BEFORE` ad çakışması
# ve 13h'nin sürümü. YORUM OLARAK BIRAKILMAZ — çalıştırılıp ölçülür.
#
# Ölçülen davranış (M3b): yalnız `REAL_CONF_DIR`'i geçirmenin KIRMIZIya
# döndürdüğü, mevcut dosyada ise yeşil kaldığı — task-5-report.md §I-1.
sent_conf_dur=0; sent_state_dur=0
if [[ "$REAL_CONF_DIR" == "$XDG_CONFIG_HOME"/* || "$REAL_CONF_DIR" == "$SCRATCH_ROOT"/* || "$REAL_CONF_DIR" == "$PFXROOT"/* ]]; then
  sent_conf_dur=1
fi
if [[ "$REAL_STATE_DIR" == "$XDG_STATE_HOME"/* || "$REAL_STATE_DIR" == "$SCRATCH_ROOT"/* || "$REAL_STATE_DIR" == "$PFXROOT"/* ]]; then
  sent_state_dur=1
fi
if [[ $sent_conf_dur -eq 0 && $sent_state_dur -eq 0 ]]; then
  ok "17c sentineller kendi sahte kokunun disinda (17a/17b olcumu gecerli)"
else
  bad "17c sentineller kendi sahte kokunu koruyor" "conf=$REAL_CONF_DIR state=$REAL_STATE_DIR — 17a/17b SAHTE dizini olcuyor, gercek agac korumasiz"
fi

# 17. İZOLASYON KANITI: suite gerçek kullanıcının config/state ağacına
# DOKUNMADI. Suite'in başında alınan parmak izleriyle karşılaştırılır.
#
# Bu, "kurulum gerektirmez" iddiasının EN SOMUT ölçümü: yeşil geçmek için
# gerçek `~/.config/cachy-agent` ve `~/.local/state/cachy-agent` ağaçlarının
# içeriği (dosya listesi + cksum) değişmiş OLMAMALI. Test 3/6/7 geçici köke
# yazıyor; 13h ise tek config dosyasına bakıyordu (ağacın tamamına değil).
#
# (M-2) 17a/17b NOKTA-AN DEĞERLENDİRMEDİR, süreklilik izlemi değil: parmak izi
# suite'in BAŞINDA ve SONUNDA alınır ve karşılaştırılır. `~/.local/state/
# cachy-agent/agents/usage/*.json` dosyalarını `cachy-agent-usage-refresh.timer`
# HER 15 DAKİKADA yeniden yazar; suite ~2 saniye sürdüğü için çakışma penceresi
# çok dar. Yine de bir çakışma 17a'yı suite ile ilgisi olmayan bir sebeple
# kırmızıya döndürebilir. Yapısal çözüm (kilitleme, snapshot) bu göreve
# konu değil ve bilinçli olarak yapılmadı: 17'nin işi "suite dokunmadı"
# iddiasını ölçmek, "sistem hiç değişmiyor" iddiasını değil.
f_state_after="$(fingerprint "$REAL_STATE_DIR")"
f_conf_after="$(fingerprint "$REAL_CONF_DIR")"
if [[ "$REAL_STATE_TREE_BEFORE" == "$f_state_after" ]]; then
  ok "17a gercek ~/.local/state/cachy-agent/agents/usage degismedi"
else
  bad "17a gercek state dizini degisti" "once=$REAL_STATE_TREE_BEFORE sonra=$f_state_after"
fi
if [[ "$REAL_CONF_TREE_BEFORE" == "$f_conf_after" ]]; then
  ok "17b gercek ~/.config/cachy-agent degismedi"
else
  bad "17b gercek config dizini degisti" "once=$REAL_CONF_TREE_BEFORE sonra=$f_conf_after"
fi

# --- Task 2: argv differential (spec §8.1/§8.2) ---
# Bu ikisi GOLDEN FILE testleridir: refactor ÖNCESİ de geçerler, çünkü mevcut
# davranışı kilitlerler. Kırmızıya dönmeleri = davranış değişti demektir.
# Ölçüm aracı kendi PATH'ini ve CACHY_AGENT_CONFIG'ini kurar (Ruling 2);
# test.sh'in 10. bloktan kalan PATH'ine veya unset'e bağımlı değildir.

# 14. agy kosullu bayraklari — IKI dal (A: --help bayragı var, B: yok)
# Yalnız agy ölçümlerine daraltılır. "4 ölçüm" sayısı da doğrulanır: sayı
# yanlışsa test 0 ölçümle sessizce geçebilirdi.
agy_out=$(bash "$REPO/tests/argv-differential.sh" --check --agent agy 2>&1); rc=$?
if [[ $rc -eq 0 && "$agy_out" == "argv: 4 ölçüm tamam" ]]; then
  ok "14 agy iki dal (A: bayrakli, B: çıplak)"
else bad "14 agy iki dal" "rc=$rc out='$(printf '%s' "$agy_out" | tr '\n' ' ')'"; fi

# 15. argv differential — HER ajanin argv'si baseline ile birebir ayni
argv_out=$(bash "$REPO/tests/argv-differential.sh" --check 2>&1); rc=$?
if [[ $rc -eq 0 && "$argv_out" == "argv: 18 ölçüm tamam" ]]; then
  ok "15 argv differential (18 olcum)"
else bad "15 argv differential" "rc=$rc out='$(printf '%s' "$argv_out" | tr '\n' ' ')'"; fi

# 19. cachy-agent-crash tanı akışı: analiz çıktısı+yürüyen-sayaç gösterilmeli.
#
# Kullanıcı deneyimi hatası: ">> Detaylı analiz yükleniyor..." sonrası agent
# 1-2 dk sessiz kalıyordu; pencere donmuş gibi görünüyordu. Düzeltme: agent
# arka planda çalışırken geçen saniyeyi gösteren bir satır olmalı ve analiz
# yine de pencereye basılmalı.
#
# Stub'lar: coredumpctl/journalctl (sahte crash kaydı), cachy-agent (--prompt'a
# 3 sn uyuyup sahte analiz basar), cachy-agent-open (argümanlarını kaydeder).
# PTY şart değil — ilerleme satırı \r ile yazılır, grep 'Analiz sürüyor' bulur.
SCRATCH19=$(mktemp -d)
export STUB19_LOG="$SCRATCH19/open.log"
mkdir -p "$SCRATCH19/stub"
cat > "$SCRATCH19/stub/coredumpctl" <<'EOF'
#!/usr/bin/env bash
printf 'PID: 12345 (steam)\nSignal: 11 (SEGV) si_code: SEGV_MAPERR\n'
EOF
cat > "$SCRATCH19/stub/journalctl" <<'EOF'
#!/usr/bin/env bash
printf 'steam journal satiri\n'
EOF
cat > "$SCRATCH19/stub/cachy-agent" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "default" ]] && { printf 'agy\n'; exit 0; }
if [[ "${1:-}" == "--prompt" ]]; then sleep 5; printf 'FAKE-ANALIZ-ÇIKTISI\n'; exit 0; fi
printf 'stub-agent: %s\n' "$*" >> "$STUB19_LOG"
exit 0
EOF
cat > "$SCRATCH19/stub/cachy-agent-open" <<'EOF'
#!/usr/bin/env bash
printf 'OPEN-CALLED: %s\n' "$*" >> "$STUB19_LOG"
exit 0
EOF
chmod +x "$SCRATCH19"/stub/*
crash19_out=$(PATH="$SCRATCH19/stub:$PATH" bash "$BIN/cachy-agent-crash" 12345 steam 2>&1); rc19=$?
if [[ $rc19 -eq 0 && "$crash19_out" == *"FAKE-ANALIZ-ÇIKTISI"* ]]; then
  ok "19a crash analizi pencereye basiliyor"
else bad "19a crash analizi" "rc=$rc19 out='$(printf '%s' "$crash19_out" | tail -3 | tr '\n' '/')'"; fi
# 19b: sayaç GERÇEKTEN ilerlemeli. Önceki hâli `*" sn"*` alt dizesine
# bakıyordu; printf biçimi " sn"yi her koşulda bastığı için döngü tamamen
# öldürülse de test geçiyordu (mutasyonla kanıtlandı: 19b PASS, 19a FAIL).
# Şimdi basılan SAYILARI çıkarıp en az iki farklı ve artan değer arıyoruz.
_c19_nums=$(printf '%s' "$crash19_out" \
  | grep -oE 'Analiz sürüyor\.\.\. [0-9]{3} sn' | grep -oE '[0-9]{3}' | sort -n | uniq)
_c19_distinct=$(printf '%s' "$_c19_nums" | grep -c '[0-9]')
_c19_first=$(printf '%s' "$_c19_nums" | head -1)
_c19_last=$(printf '%s' "$_c19_nums" | tail -1)
if [[ "$_c19_distinct" -ge 2 && -n "$_c19_first" && -n "$_c19_last" && "$_c19_last" -gt "$_c19_first" ]]; then
  ok "19b sayaç ilerliyor (${_c19_first}→${_c19_last} sn)"
else bad "19b sayaç ilerlemiyor" "farklı sayı=$_c19_distinct (${_c19_first:-yok}→${_c19_last:-yok})"; fi
if grep -q "OPEN-CALLED" "$STUB19_LOG" 2>/dev/null; then
    ok "19c akış cachy-agent-open'a devrediliyor"
  else bad "19c open'a devir" "log='$(cat "$STUB19_LOG" 2>/dev/null | tr '\n' '/')'"; fi
# 19d: agent patlarsa hata mesajı + exit 1 (sessiz pencere kapanışı yok)
cat > "$SCRATCH19/stub/cachy-agent" <<'EOF'
#!/usr/bin/env bash
if [[ "${1:-}" == "default" ]]; then printf 'agy\n'; exit 0; fi
if [[ "${1:-}" == "--prompt" ]]; then echo "error: interrupted" >&2; exit 1; fi
exit 0
EOF
chmod +x "$SCRATCH19/stub/cachy-agent"
crash19b=$(PATH="$SCRATCH19/stub:$PATH" bash "$BIN/cachy-agent-crash" 12345 steam 2>&1); rc19b=$?
if [[ $rc19b -eq 1 && "$crash19b" == *"Agent çalıştırılamadı"* ]]; then
  ok "19d agent patlarsa hata mesajı + exit 1"
else bad "19d agent hata yolu" "rc=$rc19b out='$(printf '%s' "$crash19b" | tail -3 | tr '\n' '/')'"; fi
rm -rf "$SCRATCH19"

# 20. Kurulu kopya repo ile SENKRON mu (dağıtım kayması koruması).
#
# Kullanıcı iki kez "düzeltme çalışmıyor" dedi: kod worktree'de düzeltilip
# commit'lenmişti ama ~/.local/bin'e HİÇ yüklenmemişti. Tanı penceresi kurulu
# script'i çalıştırdığı için kullanıcı hep eski sürümü gördü. Suite'in
# tamamı worktree'i test eder (bilinçli tasarım, Ruling 1), dolayısıyla bu
# ayrımı yakalayan şey yoktu. Bu test onu yakalar.
#
# SKIP: uygulama kurulu değilse (temiz checkout / CI) — ürün hatası değil.
_installed_any=0
for _f in "$REPO"/src/bin/*; do
  [[ -e "$HOME/.local/bin/$(basename "$_f")" ]] && { _installed_any=1; break; }
done
if [[ $_installed_any -eq 0 ]]; then
  skip "20 kurulu kopya senkron (cachy-agent kurulu degil)"
else
  _drift=""
  for _f in "$REPO"/src/bin/*; do
    _b=$(basename "$_f")
    [[ -f "$HOME/.local/bin/$_b" ]] || { _drift="$_drift eksik:$_b "; continue; }
    cmp -s "$_f" "$HOME/.local/bin/$_b" || _drift="$_drift farkli:$_b "
  done
  # VERSION kökte duruyor ama kurulum bin'e kopyalıyor. İlk hâlde kapsam
  # dışıydı: sürüm 0.3.0'a çekilse bu koruma kırmızıya dönmüyordu.
  cmp -s "$REPO/VERSION" "$HOME/.local/bin/VERSION" \
    || _drift="$_drift farkli:VERSION "
  # __HOME__ genişletmesi gereken dosyalar (install.sh:234/247)
  for _f in "$REPO"/src/applications/*.desktop; do
    _b=$(basename "$_f")
    sed "s|__HOME__|$HOME|g" "$_f" \
      | cmp -s - "$HOME/.local/share/applications/$_b" \
      || _drift="$_drift farkli:$_b "
  done
  _pm="$HOME/.local/share/plasma/plasmoids/org.cachyagent.usage/contents/ui/main.qml"
  _ps="$REPO/src/plasmoid/org.cachyagent.usage/contents/ui/main.qml"
  if [[ -f "$_pm" && -f "$_ps" ]]; then
    sed "s|__HOME__|$HOME|g" "$_ps" | cmp -s - "$_pm" || _drift="$_drift farkli:plasmoid/main.qml "
  fi
  # düz kopyalananlar (genişletme yok, byte-byte olmalı)
  while read -r _s _d; do
    [[ -z "$_s" ]] && continue
    cmp -s "$REPO/$_s" "$HOME/$_d" || _drift="$_drift farkli:$_s "
  done <<EOF2
src/plasmoid/org.cachyagent.usage/metadata.json .local/share/plasma/plasmoids/org.cachyagent.usage/metadata.json
src/fish/cachy-agent.fish .config/fish/conf.d/cachy-agent.fish
src/fuzzel/fuzzel.ini .config/fuzzel/fuzzel.ini
src/icons/cachy-agent.svg .local/share/icons/hicolor/scalable/apps/cachy-agent.svg
src/systemd/cachy-crash-watch.service .config/systemd/user/cachy-crash-watch.service
src/systemd/cachy-agent-usage-refresh.service .config/systemd/user/cachy-agent-usage-refresh.service
src/systemd/cachy-agent-usage-refresh.timer .config/systemd/user/cachy-agent-usage-refresh.timer
EOF2
  # NOT: agents.conf BILerek karsilastirilmaz — install.sh yalnizca YOKSA
  # yazar, kullanicinin duzenlemeleri kurulu kopyada yasalidir.
  if [[ -z "$_drift" ]]; then
    ok "20 kurulu kopya repo ile senkron"
  else
    bad "20 kurulu kopya eski" "$_drift-> ./install.sh calistir"
  fi
fi

# SKIP exit code'u ETKİLEMEZ: yalnızca gerçek kırmızılar (FAIL) hata sayılır.
# Atlanan testler ortam eksikliğidir, ürün hatası değil.
printf '\nÖzet: %d geçti, %d kaldı, %d atlandı (toplam %d)\n' "$PASS" "$FAIL" "$SKIP" "$((PASS+FAIL+SKIP))"
[[ $FAIL == 0 ]]
