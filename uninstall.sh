#!/usr/bin/env bash
# uninstall.sh - cachy-agent kaldırma
# - Kopyalanan dosyaları siler, servisleri disable eder, kglobalshortcutsrc girdisini temizler.
# - Skill/config kalıntıları SORULARAK temizlenir.
# - Kullanıcı verisine (default-agent, mute) SORMADAN dokunulmaz.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/src"

BIN_DIR="$HOME/.local/bin"
FISH_DIR="$HOME/.config/fish/conf.d"
SYSTEMD_DIR="$HOME/.config/systemd/user"
APPS_DIR="$HOME/.local/share/applications"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.cachyagent.usage"

echo "== servisler durduruluyor =="
for u in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
  systemctl --user disable --now "$u" 2>/dev/null || true
  rm -f "$SYSTEMD_DIR/$u"
  echo "  kaldırıldı: $u"
done
systemctl --user daemon-reload 2>/dev/null || true

echo "== kopyalanan dosyalar siliniyor =="
for f in "$SRC"/bin/*; do
  rm -f "$BIN_DIR/$(basename "$f")"
  echo "  silindi: $BIN_DIR/$(basename "$f")"
done
rm -f "$FISH_DIR/cachy-agent.fish" && echo "  silindi: fish/cachy-agent.fish"
for f in "$SRC"/applications/*.desktop; do
  rm -f "$APPS_DIR/$(basename "$f")"
  echo "  silindi: applications/$(basename "$f")"
done
if [[ -f "$SRC/fuzzel/fuzzel.ini" && -f "$HOME/.config/fuzzel/fuzzel.ini" ]] \
  && cmp -s "$SRC/fuzzel/fuzzel.ini" "$HOME/.config/fuzzel/fuzzel.ini"; then
  rm -f "$HOME/.config/fuzzel/fuzzel.ini"
  echo "  silindi: fuzzel/fuzzel.ini (repo ile aynıydı)"
else
  echo "  (atlandı: fuzzel.ini kullanıcı tarafından değiştirilmiş ya da yok)"
fi
rm -f "$ICON_DIR/cachy-agent.svg" && echo "  silindi: icons/cachy-agent.svg"
rm -rf "$PLASMOID_DIR" && echo "  silindi: plasmoid/org.cachyagent.usage"

echo "== kısayol girdisi temizleniyor =="
KGS="$HOME/.config/kglobalshortcutsrc"
if [[ -f "$KGS" ]] && grep -q '^\[services\]\[cachy-agent\.desktop\]$' "$KGS"; then
  # bölümü (başlık + altındaki anahtar satırları, bir sonraki [bölüm]'e kadar) sil
  python3 - "$KGS" <<'PY'
import sys
path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    lines = f.readlines()
out, skip = [], False
for ln in lines:
    if ln.strip() == "[services][cachy-agent.desktop]":
        skip = True
        continue
    if skip and ln.startswith("["):
        skip = False
    if not skip:
        out.append(ln)
with open(path, "w", encoding="utf-8") as f:
    f.writelines(out)
PY
  echo "  silindi: kglobalshortcutsrc [services][cachy-agent.desktop]"
else
  echo "  (yok: kglobalshortcutsrc girdisi bulunamadı)"
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then kbuildsycoca6 >/dev/null 2>&1 || true; fi

ask() { # ask <soru> <yol...>
  local prompt="$1"; shift
  read -rp "$prompt [e/H] " ans || true
  case "${ans:-}" in
    [Ee]*) rm -rf "$@"; echo "  silindi: $*";;
    *) echo "  (korundu: $*)";;
  esac
}

echo "== isteğe bağlı kalıntılar (sorularak) =="
[[ -e "$HOME/.config/cachy-agent" ]] \
  && ask "Config dizini silinsin mi? (default-agent + mute DAHİL: $HOME/.config/cachy-agent)" "$HOME/.config/cachy-agent" \
  || echo "  (yok: ~/.config/cachy-agent)"
[[ -e "$HOME/.config/opencode/skills/diagnose-crash" ]] \
  && ask "diagnose-crash skill'i silinsin mi?" "$HOME/.config/opencode/skills/diagnose-crash" \
  || echo "  (yok: diagnose-crash skill)"
[[ -e "$HOME/.local/state/cachy-agent" ]] \
  && ask "Durum/kullanım verileri silinsin mi? ($HOME/.local/state/cachy-agent)" "$HOME/.local/state/cachy-agent" \
  || echo "  (yok: ~/.local/state/cachy-agent)"

echo
echo "Kaldırma tamam."
