#!/usr/bin/env bash
# cachy-agent pasif test süiti — yıkıcı işlem YOK (kurulum/LLM çağrısı yapmaz).
set -u
G="\033[32m"; R="\033[31m"; N="\033[0m"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf "${G}PASS${N}: %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "${R}FAIL${N}: %s — %s\n" "$1" "$2"; }

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$REPO/src/bin:$PATH"

BIN="$HOME/.local/bin"
STATE="${XDG_STATE_HOME:-$HOME/.local/state}/cachy-agent/agents/usage"

# 1. sözdizimi: bash -n + py_compile
# NOT hangi ağacın sınandığı: $BIN = KURULU ağaç (~/.local/bin), ayrıca
# $REPO/src/bin = ÇALIŞMA ağacı. PATH'te repo önde olduğu için test 2-7 artık
# çalışma ağacını çalıştırıyor; ama kurulu ağaç da bozulmamalı. İkisi de taranır
# (yeni dosyalar — ör. cachy-agent-agents — yalnızca çalışma ağacında olabilir).
t1_ok=1; t1_msg=""
for f in "$BIN"/cachy-* "$REPO"/src/bin/cachy-*; do
  [[ -e "$f" ]] || continue
  case "$f" in *.py) continue;; esac
  if head -1 "$f" | grep -q bash; then
    if ! bash -n "$f" 2>/tmp/cachy-t1.err; then t1_ok=0; t1_msg="$t1_msg$(basename "$f"): $(cat /tmp/cachy-t1.err); "; fi
  fi
done
if ! python3 -m py_compile "$BIN/cachy-notify-action.py" 2>/tmp/cachy-t1py.err; then t1_ok=0; t1_msg="$t1_msg py_compile: $(cat /tmp/cachy-t1py.err); "; fi
if [[ $t1_ok == 1 ]]; then ok "1 bash -n + py_compile"; else bad "1 bash -n + py_compile" "$t1_msg"; fi

# 2. --help exit 0 + "Kullanım"
out=$(cachy-agent --help 2>&1); rc=$?
if [[ $rc == 0 && "$out" == *"Kullanım"* ]]; then ok "2 --help"; else bad "2 --help" "exit=$rc, 'Kullanım' yok"; fi

# 3. default mevcut değeri basar; uydurma exit 1 (dosyaya yazmaz)
cur=$(cat "$HOME/.config/cachy-agent/default-agent" 2>/dev/null || echo "opencode")
got=$(cachy-agent default 2>&1); rc=$?
if [[ $rc == 0 && "$got" == "$cur" ]]; then ok "3a default gösterir ($cur)"; else bad "3a default gösterir" "exit=$rc got='$got' beklenen='$cur'"; fi
if cachy-agent default uydurma >/dev/null 2>&1; then bad "3b default uydurma" "exit 0 döndü, 1 bekleniyordu"; else ok "3b default uydurma exit 1"; fi
after=$(cat "$HOME/.config/cachy-agent/default-agent" 2>/dev/null || echo "opencode")
if [[ "$after" == "$cur" ]]; then ok "3c default dosyası değişmedi"; else bad "3c default dosyası değişmedi" "'$cur' -> '$after'"; fi

# 4. --prompt argümansız exit 1 + usage
out=$(cachy-agent --prompt 2>&1); rc=$?
if [[ $rc == 1 && "$out" == *"kullanım"* ]]; then ok "4 --prompt argümansız"; else bad "4 --prompt argümansız" "exit=$rc out='$out'"; fi

# 5. --pick uydurma exit 1
out=$(cachy-agent --pick uydurma </dev/null 2>&1); rc=$?
if [[ $rc == 1 ]]; then ok "5 --pick uydurma"; else bad "5 --pick uydurma" "exit=$rc out='$out'"; fi

# 6. usage-update exit 0 + 3 JSON geçerli
if cachy-agent-usage-update >/dev/null 2>&1; then ok "6a usage-update exit 0"; else bad "6a usage-update exit 0" "exit=$?"; fi
n=0; badjson=""
for f in "$STATE"/*.json; do
  [[ -e "$f" ]] || break
  if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" 2>/dev/null; then n=$((n+1)); else badjson="$badjson$(basename "$f") "; fi
done
if [[ $n -ge 3 && -z "$badjson" ]]; then ok "6b $n JSON geçerli"; else bad "6b JSON geçerli" "geçerli=$n bozuk='$badjson' (en az 3 beklenir)"; fi

# 7. cachy-agent usage exit 0
if cachy-agent usage >/dev/null 2>&1; then ok "7 usage exit 0"; else bad "7 usage exit 0" "exit=$?"; fi

# 8. servis dosyaları + crash-watch active
sdir="$HOME/.config/systemd/user"
sok=1; smsg=""
for s in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
  [[ -f "$sdir/$s" ]] || { sok=0; smsg="$smsg$s yok; "; }
done
st=$(systemctl --user is-active cachy-crash-watch 2>&1 || true)
[[ "$st" == "active" ]] || { sok=0; smsg="$smsg is-active='$st'; "; }
if [[ $sok == 1 ]]; then ok "8 servisler + crash-watch active"; else bad "8 servisler + crash-watch" "$smsg"; fi

# 9. desktop-file-validate temiz
d1="$HOME/.local/share/applications/cachy-agent.desktop"
d2="$HOME/.local/share/applications/cachy-agent-usage.desktop"
dv=$(desktop-file-validate "$d1" "$d2" 2>&1); rc=$?
if [[ $rc == 0 && -z "$dv" ]]; then ok "9 desktop-file-validate"; else bad "9 desktop-file-validate" "exit=$rc out='$dv'"; fi

# 10. menu seçim mantığı (stub fuzzel/alacritty/install — gerçek çalıştırma yok)
# Artık ÇALIŞMA AĞACININ menüsü sınanır (kurulu ~/.local/bin kopyası değil):
# menü config'e bağlandığı için `cachy-agent-agents` bulunabilmeli ve katalog
# sabitlenmelidir — aksi halde test kullanıcının kendi config'ine bakar.
#
# Menü kardeş binary'leri `$HOME/.local/bin` ÜZERİNDEN mutlak yolla çağırır
# (desktop entry'den çalışıyor, PATH'e güvenemez). Tek `BIN_DIR` sabitinden
# geldikleri için test tek sed ile hepsini stub dizinine çevirir — bare adla
# çağırsalardı PATH'e bir stub koymak yetmezdi, mutlak yol oraya bakmazdı.
STUB=$(mktemp -d)
cp "$REPO/src/bin/cachy-agent-menu" "$STUB/menu-test"
sed -i "s|/usr/bin/alacritty|$STUB/alacritty|g" "$STUB/menu-test"
sed -i "s|\"\\\$HOME/.local/bin|\"$STUB|g" "$STUB/menu-test"
# Menü katalog okuyucusunu da stub dizinine koy: mutlak yolla çağırdığı için
# PATH'e bırakılan kopya ona ulaşmaz. Gerçek `cachy-agent-agents` — sahte
# değil, çünkü testin konusu tam olarak config okuma yolu.
cp "$REPO/src/bin/cachy-agent-agents" "$STUB/cachy-agent-agents"
# fuzzel stub'ı stdin'deki MENÜ LİSTESİNİ de kaydeder. Bu, listenin kaynağını
# doğrudan kanıtlar: `list` config'ten gelmiyorsa burada görünmez.
cat > "$STUB/fuzzel" <<'EOF'
#!/usr/bin/env bash
cat > "$STUB_MENU"
printf '%s' "$FAKE_SEL"
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
export PATH="$STUB:$PATH"
export CACHY_AGENT_CONFIG="$REPO/tests/fixtures/agents-valid.conf"

# 10a. "+ x (kur)" -> install çağrısı
: > "$STUB_LOG"
FAKE_SEL="+ codex (kur)" bash "$STUB/menu-test" >/dev/null 2>&1 || true
if grep -q "cachy-agent-install" "$STUB_LOG" && grep -q "codex" "$STUB_LOG"; then ok "10a menu '+ x (kur)' install'e gider"; else bad "10a menu '+ x (kur)'" "log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10b. ayraç satırı -> sessiz exit 0, çağrı yok
: > "$STUB_LOG"
FAKE_SEL="──────────────────" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then ok "10b menu ayraç yoksayılır"; else bad "10b menu ayraç" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10c. düz agent satırı -> `cachy-agent-open` (config'de tanımlı olmalı)
: > "$STUB_LOG"
FAKE_SEL="codex" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'cachy-agent-open' "$STUB_LOG" && grep -qx 'codex' "$STUB_LOG"; then
  ok "10c menu düz ad -> -open"
else bad "10c menu düz ad" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10d. "★ x (varsayılan yap)" -> `cachy-agent default x` (stub'lanır, gerçek
# varsayılan agent değişmez)
: > "$STUB_LOG"
FAKE_SEL="★ codex (varsayılan yap)" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 ]] && grep -q 'DEFAULT CALLED: default codex' "$STUB_LOG"; then
  ok "10d menu '★ x' -> default x"
else bad "10d menu '★ x'" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10e. CONFIG'DE OLMAYAN ad -> hicbir komut çağrılmaz, sessiz exit 0.
# Eski sabit `case` listesi yerine `known` konduğu için bu, listeden
# kaldırılmış/kataloğa hiç girmemiş bir ajanın menüye sızamamasını kilitler.
: > "$STUB_LOG"
FAKE_SEL="uydurma" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then ok "10e menu bilinmeyen ad reddedilir"; else bad "10e menu bilinmeyen ad" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10f. "★ " dalında config'de olmayan ad -> default ÇAĞRILMAZ
: > "$STUB_LOG"
FAKE_SEL="★ uydurma (varsayılan yap)" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then ok "10f menu '★ bilinmeyen' reddedilir"; else bad "10f menu '★ bilinmeyen'" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

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
CACHY_AGENT_CONFIG="$STUB/ozel.conf" FAKE_SEL="+ ozel (kur)" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
menu_txt="$(cat "$STUB_MENU" 2>/dev/null || echo BOŞ)"
g_sabit_yok=1
for a in opencode agy claude codex crush copilot cursor-agent grok; do
  if grep -q "$a" "$STUB_MENU" 2>/dev/null; then g_sabit_yok=0; fi
done
if [[ $rc == 0 ]] \
   && grep -qx '+ ozel (kur)' "$STUB_MENU" \
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

unset CACHY_AGENT_CONFIG
rm -rf "$STUB"

# 11. agents.conf parse + check
SCRATCH=$(mktemp -d)
# PFXROOT: sonraki görevlerin (13/14/15/16) kurulum/argv testleri kullanacak;
# burada ayrılır, bu blokta henüz tüketilmez.
PFXROOT=$(mktemp -d)
trap 'rm -rf "$SCRATCH" "$PFXROOT"' EXIT
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

# 11d: bozuk config -> list exit 1, stderr config yolu + satir no
neg "11d list bozuk config exit 1 + yol:2" "$FIX/agents-broken.conf:2:" "$AG" list

# 11e: eksik alan -> stderr'de satir numarasi
err=$("$AG" check 2>&1 >/dev/null | head -1)
if [[ "$err" == *":2:"* ]]; then ok "11e eksik alan satir numarasiyla"; else bad "11e eksik alan" "err='$err'"; fi

# 11f: config dosyasi YOK -> exit 1 + "config dosyası yok"
export CACHY_AGENT_CONFIG="$SCRATCH/yok.conf"
neg "11f config yok exit 1" "config dosyası yok" "$AG" list

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

printf '\nÖzet: %d geçti, %d kaldı (toplam %d)\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[[ $FAIL == 0 ]]
