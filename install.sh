#!/usr/bin/env bash
# install.sh - cachy-agent kurulumu (idempotent: tekrar çalışınca bozmaz, yedek almaz)
# Kullanım: ./install.sh [--check]
#   --check : sadece preflight raporu verir, kurulum yapmaz.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/src"

# dep -> kontrol komutu -> pacman paketi
DEPS=(
  "alacritty|command -v alacritty|alacritty"
  "fish|command -v fish|fish"
  "mise|command -v mise|mise"
  "python-gi|python3 -c 'import gi'|python-gobject"
  "journalctl|command -v journalctl|systemd"
  "kwriteconfig6|command -v kwriteconfig6|kconfig"
  "fuzzel|command -v fuzzel|fuzzel"
)

MISSING_PKGS=()

preflight() {
  local fail=0
  echo "== preflight =="
  local entry name check pkg
  for entry in "${DEPS[@]}"; do
    IFS='|' read -r name check pkg <<< "$entry"
    if eval "$check" >/dev/null 2>&1; then
      echo "  [OK]      $name"
    else
      echo "  [EKSİK]   $name (paket: $pkg)"
      MISSING_PKGS+=("$pkg")
      fail=1
    fi
  done
  if [[ $fail -ne 0 ]]; then
    echo "Kurulum için öneri: sudo pacman -S ${MISSING_PKGS[*]}"
  else
    echo "Tüm bağımlılıklar mevcut."
  fi
  return $fail
}

if [[ "${1:-}" == "--check" ]]; then
  if preflight; then exit 0; else exit 1; fi
fi

if ! preflight; then
  echo
  read -rp "Eksik bağımlılıklar var. Kuruluma devam edilsin mi? [e/H] " ans || true
  case "${ans:-}" in
    [Ee]*) ;;
    *) echo "Vazgeçildi. Önce eksikleri kur: sudo pacman -S ${MISSING_PKGS[*]}"; exit 1 ;;
  esac
fi
echo

BIN_DIR="$HOME/.local/bin"
FISH_DIR="$HOME/.config/fish/conf.d"
SYSTEMD_DIR="$HOME/.config/systemd/user"
APPS_DIR="$HOME/.local/share/applications"
FUZZEL_DIR="$HOME/.config/fuzzel"
ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.cachyagent.usage"

mkdir -p "$BIN_DIR" "$FISH_DIR" "$SYSTEMD_DIR" "$APPS_DIR" "$FUZZEL_DIR" "$ICON_DIR" "$PLASMOID_DIR"

echo "== dosyalar kopyalanıyor =="
# bin (çalıştırılabilir bayrağıyla)
for f in "$SRC"/bin/*; do
  cp -f "$f" "$BIN_DIR/$(basename "$f")"
  chmod +x "$BIN_DIR/$(basename "$f")"
  echo "  bin: $(basename "$f")"
done

# fish (conf.d otomatik source'lanır, ek ayar gerekmez)
cp -f "$SRC/fish/cachy-agent.fish" "$FISH_DIR/cachy-agent.fish"
echo "  fish: conf.d otomatik source'lanıyor (yeni shell'de a/ga aktif)"

# systemd (repo'da %{...} yok, düz kopya)
for f in "$SRC"/systemd/*; do
  cp -f "$f" "$SYSTEMD_DIR/$(basename "$f")"
  echo "  systemd: $(basename "$f")"
done

# __HOME__ placeholder'lı dosyalar -> gerçek $HOME yazılır
for f in "$SRC"/applications/*.desktop; do
  sed "s|__HOME__|$HOME|g" "$f" > "$APPS_DIR/$(basename "$f")"
  echo "  applications: $(basename "$f")"
done
cp -f "$SRC/fuzzel/fuzzel.ini" "$FUZZEL_DIR/fuzzel.ini"
echo "  fuzzel: fuzzel.ini"
cp -f "$SRC/icons/cachy-agent.svg" "$ICON_DIR/cachy-agent.svg"
echo "  icons: cachy-agent.svg"

# plasmoid (tümü, placeholder genişletmeli)
rm -rf "$PLASMOID_DIR"
mkdir -p "$PLASMOID_DIR"
(cd "$SRC/plasmoid/org.cachyagent.usage" && find . -type f | while read -r f; do
  mkdir -p "$PLASMOID_DIR/$(dirname "$f")"
  sed "s|__HOME__|$HOME|g" "$f" > "$PLASMOID_DIR/$f"
done)
echo "  plasmoid: org.cachyagent.usage"

echo "== doğrula + etkinleştir =="
if command -v desktop-file-validate >/dev/null 2>&1; then
  desktop-file-validate "$APPS_DIR"/cachy-agent*.desktop && echo "  desktop dosyaları geçerli"
else
  echo "  (atlandı: desktop-file-validate yok)"
fi
if command -v kbuildsycoca6 >/dev/null 2>&1; then
  kbuildsycoca6 >/dev/null 2>&1 || true
  echo "  kbuildsycoca6 çalıştı"
fi
systemctl --user daemon-reload
systemctl --user enable --now cachy-crash-watch.service
systemctl --user enable --now cachy-agent-usage-refresh.service
systemctl --user enable --now cachy-agent-usage-refresh.timer
echo "  servisler etkin: cachy-crash-watch.service, cachy-agent-usage-refresh.service/.timer"

echo
echo "Kurulum tamam. Yeni bir terminalde 'a' / 'ga' çalışır."
echo "Kısayol (SUPER+SHIFT+CTRL+A): Sistem Ayarları > Klavye > Kısayollar > cachy-agent.desktop > Başlat."
