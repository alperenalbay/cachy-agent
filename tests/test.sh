#!/usr/bin/env bash
# cachy-agent pasif test süiti — yıkıcı işlem YOK (kurulum/LLM çağrısı yapmaz).
set -u
G="\033[32m"; R="\033[31m"; N="\033[0m"
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf "${G}PASS${N}: %s\n" "$1"; }
bad()  { FAIL=$((FAIL+1)); printf "${R}FAIL${N}: %s — %s\n" "$1" "$2"; }

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

printf '\nÖzet: %d geçti, %d kaldı (toplam %d)\n' "$PASS" "$FAIL" "$((PASS+FAIL))"
[[ $FAIL == 0 ]]
