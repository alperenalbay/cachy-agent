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
t1_ok=1; t1_msg=""
for f in "$BIN"/cachy-*; do
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
STUB=$(mktemp -d)
cp "$BIN/cachy-agent-menu" "$STUB/menu-test"
sed -i "s|/usr/bin/alacritty|$STUB/alacritty|g; s|$BIN/cachy-agent-install|$STUB/cachy-agent-install|g" "$STUB/menu-test"
cat > "$STUB/fuzzel" <<'EOF'
#!/usr/bin/env bash
printf '%s' "$FAKE_SEL"
EOF
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
chmod +x "$STUB/fuzzel" "$STUB/alacritty" "$STUB/cachy-agent-install"
export STUB_LOG="$STUB/calls.log"
export PATH="$STUB:$PATH"

# 10a. "+ x (kur)" -> install çağrısı
: > "$STUB_LOG"
FAKE_SEL="+ codex (kur)" bash "$STUB/menu-test" >/dev/null 2>&1 || true
if grep -q "cachy-agent-install" "$STUB_LOG" && grep -q "codex" "$STUB_LOG"; then ok "10a menu '+ x (kur)' install'e gider"; else bad "10a menu '+ x (kur)'" "log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi

# 10b. ayraç satırı -> sessiz exit 0, çağrı yok
: > "$STUB_LOG"
FAKE_SEL="──────────────────" bash "$STUB/menu-test" >/dev/null 2>&1; rc=$?
if [[ $rc == 0 && ! -s "$STUB_LOG" ]]; then ok "10b menu ayraç yoksayılır"; else bad "10b menu ayraç" "exit=$rc log: $(cat "$STUB_LOG" 2>/dev/null || echo BOŞ)"; fi
rm -rf "$STUB"

# 11. agents.conf parse + check
SCRATCH=$(mktemp -d)
# PFXROOT: sonraki görevlerin (13/14/15/16) kurulum/argv testleri kullanacak;
# burada ayrılır, bu blokta henüz tüketilmez.
PFXROOT=$(mktemp -d)
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

printf '\nÖzet: %d geçti, %d kaldı (toplam %d)\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[[ $FAIL == 0 ]]
