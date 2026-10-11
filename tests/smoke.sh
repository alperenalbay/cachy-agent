#!/usr/bin/env bash
# tests/smoke.sh - repo sağlık kontrolü (kurulum yapmaz)
# Kullanım: ./tests/smoke.sh   (repo kökünden ya da buradan)
set -euo pipefail
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
fail=0
skipc=0

ok()   { echo "  [OK] $1"; }
bad()  { echo "  [HATA] $1"; fail=1; }
skip() { skipc=$((skipc+1)); echo "  [ATLANDI] $1"; }

# smoke testi repo'ya HİÇBİR ŞEY yazmaz.  Bütün geçici çıktı buraya gider;
# EXIT trap'i ile iş bitince silinir.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "== bash -n (bash shebang'li dosyalar) =="
while IFS= read -r f; do
  [[ -e "$f" ]] || continue
  head -1 "$f" | grep -q 'bash' || continue
  # fish ve python dosyaları bash değildir
  case "$f" in *.fish|*.py) continue;; esac
  if bash -n "$f" 2>&1; then ok "bash -n: ${f#"$REPO_DIR"/}"; else bad "bash -n: ${f#"$REPO_DIR"/}"; fi
done < <(find "$REPO_DIR" -maxdepth 3 -type f \( -name '*.sh' -o -path '*/src/bin/*' \) ! -path '*__pycache__*')

echo "== python derleme =="
# NOT: Brief'in önerdiği PYTHONDONTWRITEBYTECODE=1 İŞE YARAMAZ.  Bu değişken
# yalnızca 'import' sırasındaki örtük bytecode yazımını kapatır; py_compile
# açıkça yazdığı için __pycache__ yine oluşur (Python 3.14'te ölçüldü).
# Bunun yerine çıktıyı doğrudan geçici dizine yönlendiriyoruz: derleme
# semantiği aynı kalır, repo'ya hiçbir dosya düşmez.
for f in "$REPO_DIR"/src/bin/*.py; do
  [[ -e "$f" ]] || continue
  if python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' \
       "$f" "$tmp/pyc/$(basename "$f").pyc" 2>&1; then
    ok "py_compile: $(basename "$f")"
  else
    bad "py_compile: $(basename "$f")"
  fi
done

echo "== hardcode taraması (src içinde /home/ kalmamalı) =="
if grep -rn --exclude-dir=__pycache__ '/home/' "$REPO_DIR/src/" 2>&1; then
  bad "src/ içinde gerçek ev-dizini yolu var"
else
  ok "src/ temiz (gerçek /home/ yolu yok)"
fi

echo "== __HOME__ placeholder =="
for f in "$REPO_DIR"/src/applications/*.desktop "$REPO_DIR"/src/plasmoid/org.cachyagent.usage/contents/ui/main.qml; do
  if grep -q '__HOME__' "$f"; then ok "placeholder var: ${f#"$REPO_DIR"/}"; else bad "placeholder YOK: ${f#"$REPO_DIR"/}"; fi
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
# systemd-analyze CI koşucusunda yoksa bu kontrol ATLANIR (skip), ne geçer
# ne kalır sayılır: eksik araç asla sahte bir yeşil ya da sahte bir kırmızı
# üretmemelidir.
if ! command -v systemd-analyze >/dev/null 2>&1; then
  skip "systemd-analyze yok"
else
  for u in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
    if systemd-analyze verify "$REPO_DIR/src/systemd/$u" 2>&1; then ok "verify: $u"; else bad "verify: $u"; fi
  done
fi

echo "== desktop doğrulama =="
if command -v desktop-file-validate >/dev/null 2>&1; then
  for f in "$REPO_DIR"/src/applications/*.desktop; do
    sed "s|__HOME__|$HOME|g" "$f" > "$tmp/$(basename "$f")"
    if desktop-file-validate "$tmp/$(basename "$f")" 2>&1; then ok "validate: $(basename "$f")"; else bad "validate: $(basename "$f")"; fi
  done
else
  skip "desktop-file-validate yok"
fi

if [[ $fail -eq 0 ]]; then
  echo "SMOKE: GEÇTİ ($skipc atlandı)"
else
  echo "SMOKE: KALDI ($skipc atlandı)"
fi
exit $fail
