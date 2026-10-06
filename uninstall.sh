#!/usr/bin/env bash
# uninstall.sh - cachy-agent kaldırma
# - Kopyalanan dosyaları siler, servisleri disable eder, kglobalshortcutsrc girdisini temizler.
# - Skill/config kalıntıları SORULARAK temizlenir.
# - Kullanıcı verisine (default-agent, mute) SORMADAN dokunulmaz.
# Kullanım: ./uninstall.sh [--prefix DIR]
#   --prefix DIR : install.sh --prefix ile kurulan ağacı kaldırır (spec §7.1).
#                  Gerçek $HOME'e, systemd-user oturumuna ve kglobalshortcutsrc
#                  dosyasına DOKUNMAZ. Prefix altındaki config KOŞULSUZ silinir
#                  (test izolasyonu); prefix verilmezse sorulur.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/src"

# --- argüman ayrıştırma ------------------------------------------------------
# install.sh ile AYNI biçim (--prefix DIR ve --prefix=DIR); yoksa test 13c'de
# uninstall çalıştırırken install'ın anlamadığı bir argümanı geçersiz sayıp
# hata vermek kullanıcıyı yarı kurulumda bırakırdı.
PREFIX=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "uninstall.sh: --prefix bir dizin ister (ör. --prefix /tmp/cachy-pfx)" >&2
        exit 2
      fi
      PREFIX="$2"
      shift
      ;;
    --prefix=*)
      if [[ -z "${1#--prefix=}" ]]; then
        echo "uninstall.sh: --prefix bir dizin ister (ör. --prefix /tmp/cachy-pfx)" >&2
        exit 2
      fi
      PREFIX="${1#--prefix=}"
      ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "uninstall.sh: bilinmeyen argüman: $1" >&2
      echo "Kullanım: ./uninstall.sh [--prefix DIR]" >&2
      exit 2
      ;;
  esac
  shift
done

# --- yol haritası -----------------------------------------------------------
# PREFIX boşken BU BLOK BİREBİR v0.1.0'da olduğu gibi kalır. Not: burada
# CONFIG_DIR/STATE_DIR düz $HOME yollarıdır (install.sh XDG_CONFIG_HOME'a
# saygı gösterir). Bu asimetri v0.1.0'dan gelir ve bu görev kapsamında
# düzeltilmedi — değiştirmek "prefix verilmediğinde hiçbir yol değişmez"
# sözleşmesini ihlal ederdi. Bkz. task-4-report.md Endişeler.
if [[ -n "$PREFIX" ]]; then
  BIN_DIR="$PREFIX/bin"
  FISH_DIR="$PREFIX/config/fish/conf.d"
  SYSTEMD_DIR="$PREFIX/config/systemd/user"
  APPS_DIR="$PREFIX/applications"
  FUZZEL_DIR="$PREFIX/config/fuzzel"
  ICON_DIR="$PREFIX/icons"
  PLASMOID_DIR="$PREFIX/plasmoids/org.cachyagent.usage"
  CONFIG_DIR="$PREFIX/config/cachy-agent"
  STATE_DIR="$PREFIX/state/cachy-agent"
else
  BIN_DIR="$HOME/.local/bin"
  FISH_DIR="$HOME/.config/fish/conf.d"
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  APPS_DIR="$HOME/.local/share/applications"
  FUZZEL_DIR="$HOME/.config/fuzzel"
  ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
  PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.cachyagent.usage"
  CONFIG_DIR="$HOME/.config/cachy-agent"
  STATE_DIR="$HOME/.local/state/cachy-agent"
fi

if [[ -z "$PREFIX" ]]; then
  echo "== servisler durduruluyor =="
  for u in cachy-crash-watch.service cachy-agent-usage-refresh.service cachy-agent-usage-refresh.timer; do
    systemctl --user disable --now "$u" 2>/dev/null || true
    rm -f "$SYSTEMD_DIR/$u"
    echo "  kaldırıldı: $u"
  done
  systemctl --user daemon-reload 2>/dev/null || true
else
  # --prefix kipinde systemctl ÇAĞRILMAZ. Kaldırılacak unit dosyaları prefix'in
  # İÇİNDE olduğu halde `disable --now` GERÇEK oturumdaki servisleri durdururdu:
  # test, kullanıcının çalışan kurulumunu kapatırdı. Dosyalar yine de silinir.
  for f in "$SRC"/systemd/*; do
    rm -f "$SYSTEMD_DIR/$(basename "$f")"
    echo "  silindi: $SYSTEMD_DIR/$(basename "$f")"
  done
  echo "  (atlandı: --prefix kipi — systemctl --user çalıştırılmadı)"
fi

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
# fuzzel.ini karşılaştırması: kullanıcı değiştirdiyse DOKUNULMAZ.
# (Prefix altındaki fuzzel.ini'yi de aynı kurala bağlıyoruz: kimse elle
# değiştirmediği sürece prefix'e ait olan silinir.)
if [[ -f "$SRC/fuzzel/fuzzel.ini" && -f "$FUZZEL_DIR/fuzzel.ini" ]] \
  && cmp -s "$SRC/fuzzel/fuzzel.ini" "$FUZZEL_DIR/fuzzel.ini"; then
  rm -f "$FUZZEL_DIR/fuzzel.ini"
  echo "  silindi: fuzzel/fuzzel.ini (repo ile aynıydı)"
else
  echo "  (atlandı: fuzzel.ini kullanıcı tarafından değiştirilmiş ya da yok)"
fi
rm -f "$ICON_DIR/cachy-agent.svg" && echo "  silindi: icons/cachy-agent.svg"
rm -rf "$PLASMOID_DIR" && echo "  silindi: plasmoid/org.cachyagent.usage"

# --- config (ajans kataloğu) -------------------------------------------------
# v0.1.0'da kaldırılacak bir config dosyası yoktu; v0.2.0'da install.sh
# agents.conf yazdığı için uninstall da onu kaldırmak ZORUNDA (aksi halde
# kaldırma sonrası menü "config yok" der ve exit 1 verir).
if [[ -n "$PREFIX" ]]; then
  # Prefix altındaki config test izolasyonu için KOŞULSUZ silinir: aynı prefix
  # ile yeniden kurulum denemek, önceki koşumun config'ini görmemeli.
  # Gerçek $HOME'taki config'e dokunulmaz — o kullanıcının verisidir.
  rm -f "$CONFIG_DIR/agents.conf"
  echo "  silindi: config/agents.conf (--prefix: koşulsuz)"
fi

echo "== kısayol girdisi temizleniyor =="
if [[ -n "$PREFIX" ]]; then
  # CI'da kglobalshortcutsrc yoktur; prefix kurulumu gerçek oturumun kısayol
  # kaydına dokunmamalıdır. O dosya $HOME altında, prefix dışında.
  echo "  (atlandı: --prefix kipi — kglobalshortcutsrc dokunulmadı)"
else
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
fi

ask() { # ask <soru> <yol...>
  local prompt="$1"; shift
  read -rp "$prompt [e/H] " ans || true
  case "${ans:-}" in
    [Ee]*) rm -rf "$@"; echo "  silindi: $*";;
    *) echo "  (korundu: $*)";;
  esac
}

echo "== isteğe bağlı kalıntılar (sorularak) =="
if [[ -n "$PREFIX" ]]; then
  # Prefix dışındaki kalıntılara dokunulmaz: skill ~/.config/opencode altında,
  # durum verisi prefix'te. Sorulmaz, çünkü TTY yoktur ve cevap "korundu"
  # olurdu; daha kötüsü bir test koşumunun kullanıcının skill'ini silmesi olurdu.
  echo "  (atlandı: --prefix kipi — skill/durum kalıntıları sorulmadı)"
else
  # Değişkenler yukarıda tanımlandı; --prefix BOŞKEN tam olarak v0.1.0'daki
  # yollara eşittir (bkz. task-4-report.md Step 7 kanıtı). Aynı yolu iki kez
  # yazmamak, "prefix verilmediğinde yol değişti" kazasını önler.
  [[ -e "$CONFIG_DIR" ]] \
    && ask "Config dizini silinsin mi? (default-agent + mute DAHİL: $CONFIG_DIR)" "$CONFIG_DIR" \
    || echo "  (yok: ~/.config/cachy-agent)"
  [[ -e "$HOME/.config/opencode/skills/diagnose-crash" ]] \
    && ask "diagnose-crash skill'i silinsin mi?" "$HOME/.config/opencode/skills/diagnose-crash" \
    || echo "  (yok: diagnose-crash skill)"
  [[ -e "$STATE_DIR" ]] \
    && ask "Durum/kullanım verileri silinsin mi? ($STATE_DIR)" "$STATE_DIR" \
    || echo "  (yok: ~/.local/state/cachy-agent)"
fi

echo
echo "Kaldırma tamam."