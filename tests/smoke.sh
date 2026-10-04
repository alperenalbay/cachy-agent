#!/usr/bin/env bash
# tests/smoke.sh - repo sağlık kontrolü (kurulum yapmaz)
# Kullanım: ./tests/smoke.sh   (repo kökünden ya da buradan)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail=0

ok()   { echo "  [OK] $1"; }
bad()  { echo "  [HATA] $1"; fail=1; }

echo "== bash -n (bash shebang'li dosyalar) =="
while IFS= read -r f; do
  [[ -e "$f" ]] || continue
  head -1 "$f" | grep -q 'bash' || continue
  # fish ve python dosyaları bash değildir
  case "$f" in *.fish|*.py) continue;; esac
  if bash -n "$f" 2>&1; then ok "bash -n: ${f#$REPO_DIR/}"; else bad "bash -n: ${f#$REPO_DIR/}"; fi
done < <(find "$REPO_DIR" -maxdepth 3 -type f \( -name '*.sh' -o -path '*/src/bin/*' \) ! -path '*__pycache__*')

echo "== python derleme =="
for f in "$REPO_DIR"/src/bin/*.py; do
  [[ -e "$f" ]] || continue
  if python3 -m py_compile "$f" 2>&1; then ok "py_compile: $(basename "$f")"; else bad "py_compile: $(basename "$f")"; fi
done
find "$REPO_DIR/src" -name '__pycache__' -type d -exec rm -rf {} + 2>/dev/null || true

echo "== hardcode taraması (src içinde /home/ kalmamalı) =="
if grep -rn --exclude-dir=__pycache__ '/home/' "$REPO_DIR/src/" 2>&1; then
  bad "src/ içinde gerçek ev-dizini yolu var"
else
  ok "src/ temiz (gerçek /home/ yolu yok)"
fi

echo "== __HOME__ placeholder =="
for f in "$REPO_DIR"/src/applications/*.desktop "$REPO_DIR"/src/plasmoid/org.cachyagent.usage/contents/ui/main.qml; do
  if grep -q '__HOME__' "$f"; then ok "placeholder var: ${f#$REPO_DIR/}"; else bad "placeholder YOK: ${f#$REPO_DIR/}"; fi
done

echo "== --version =="
if [[ -f "$REPO_DIR/VERSION" ]] && grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' "$REPO_DIR/VERSION"; then
  ok "VERSION: $(cat "$REPO_DIR/VERSION")"
  if [[ "$(bash "$REPO_DIR/src/bin/cachy-agent" --version 2>&1)" == "$(cat "$REPO_DIR/VERSION")" ]]; then
    ok "--version VERSION ile eşleşiyor"
  else
    bad "--version çıktısı VERSION ile eşleşmiyor"
  fi
else
  bad "VERSION dosyası eksik/bozuk"
fi

echo "== systemd birimleri =="
for u in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
  if systemd-analyze verify "$REPO_DIR/src/systemd/$u" 2>&1; then ok "verify: $u"; else bad "verify: $u"; fi
done

echo "== desktop doğrulama =="
if command -v desktop-file-validate >/dev/null 2>&1; then
  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
  for f in "$REPO_DIR"/src/applications/*.desktop; do
    sed "s|__HOME__|$HOME|g" "$f" > "$tmp/$(basename "$f")"
    if desktop-file-validate "$tmp/$(basename "$f")" 2>&1; then ok "validate: $(basename "$f")"; else bad "validate: $(basename "$f")"; fi
  done
else
  echo "  (atlandı: desktop-file-validate yok)"
fi

if [[ $fail -eq 0 ]]; then echo "SMOKE: GEÇTİ"; else echo "SMOKE: KALDI"; fi
exit $fail
