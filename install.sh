#!/usr/bin/env bash
# install.sh - cachy-agent kurulumu (idempotent: tekrar çalışınca bozmaz, yedek almaz)
# Kullanım: ./install.sh [--check] [--prefix DIR]
#   --check : sadece preflight raporu verir, kurulum yapmaz.
#   --prefix DIR : TÜM yolları DIR altına yazar (spec §7.1). Test/CI içindir:
#                  gerçek $HOME'e, systemd-user oturumuna ve KDE cache'ine
#                  dokunmadan kurulum denemeyi sağlar. systemd enable/daemon-reload,
#                  kbuildsycoca6 ve desktop-file-validate ATLANIR.
#                  VERİLMEDİĞİNDE HİÇBİR YOL DEĞİŞMEZ (geriye uyum sözleşmesi).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$REPO_DIR/src"

# --- argüman ayrıştırma ------------------------------------------------------
PREFIX=""
CHECK=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      CHECK=1
      ;;
    --prefix)
      # Değer eksikse sessizce BOŞ PREFIX'e düşmüyoruz: bu, kullanıcının
      # "--prefix" yazıp unuttuğunda farkında olmadan GERÇEK $HOME'a kurması
      # demekti. Kullanım hatası = exit 2 (cachy-agent-agents ile aynı sözleşme).
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "install.sh: --prefix bir dizin ister (ör. --prefix /tmp/cachy-pfx)" >&2
        exit 2
      fi
      PREFIX="$2"
      shift
      ;;
    --prefix=*)
      if [[ -z "${1#--prefix=}" ]]; then
        echo "install.sh: --prefix bir dizin ister (ör. --prefix /tmp/cachy-pfx)" >&2
        exit 2
      fi
      PREFIX="${1#--prefix=}"
      ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "install.sh: bilinmeyen argüman: $1" >&2
      echo "Kullanım: ./install.sh [--check] [--prefix DIR]" >&2
      exit 2
      ;;
  esac
  shift
done

# --- PREFIX normalizasyonu (spec §7.1: "mutlak yol") --------------------------
# PREFIX, `__HOME__` placeholder'larının genişletme değeridir ve dolayısıyla
# desktop dosyalarının Exec= satırına, plasmoid'in komut satırına yazılır.
# İki tehlike var:
#
#  1. GÖRELI YOL. `--prefix relpfx` Exec= satırına `relpfx/.local/bin/…`
#     yazar; spec §7.1 "mutlak yol" diyor ve göreli Exec= geçersizdir.
#  2. sed KAÇIŞI. Genişletme `sed "s|__HOME__|$PREFIX|g"` ile yapılır; yol
#     içindeki `&` "eşleşen metin", `|` alan ayırıcı, `\` kaçış karakteridir.
#     Ölçülen SESSİZ bozulma:
#       --prefix '/tmp/f3/a&b\c' -> Exec=/tmp/f3/a__HOME__b\/.local/bin/…
#         rc=0 ve `__HOME__` bile KALDI: kullanıcıya geçerli görünen ama
#         işlevsiz bir .desktop üretildi.
#       --prefix '/tmp/f2/a|b'   -> rc=1, teşhisi olmayan sed hatası.
#     Üçü de exit 2 ile ve sebebiyle reddedilir.
if [[ -n "$PREFIX" ]]; then
  # sed'in kaçış karakteri `printf '\134'` ile üretiliyor: kaynak dosyada `'\'`
  # yazmak shellcheck'e "tırnak kaçışı" sanılıyor (SC1003, yanlış pozitif).
  BS="$(printf '\134')"
  case "$PREFIX" in
    *'|'*|*'&'*|*"$BS"*)
      printf 'install.sh: --prefix yolu boru, & veya backslash iceremez (sed kacisi)\n' >&2
      printf '  verilen: %s\n' "$PREFIX" >&2
      exit 2
      ;;
  esac
  # Var ama bir DOSYA ise açık hata (M-5): `mkdir -p` çıplak bir
  # "Not a directory" basıp `set -e` ile script'i öldürürdü; sebebi görünmezdi.
  # Dokstring "DIR yoksa oluşturur" diyordu, artık "dizin olmalı" de diyor.
  if [[ -e "$PREFIX" && ! -d "$PREFIX" ]]; then
    printf 'install.sh: --prefix bir dizin olmalı, dosya var: %s\n' "$PREFIX" >&2
    exit 2
  fi
  # Spec §7.1: "DIR yoksa oluşturulur." Sonraki adımlarda da mkdir var, ama
  # mutlaklaştırma burada dizinin var olmasını gerektiriyor (cd/pwd).
  mkdir -p -- "$PREFIX" || {
    printf 'install.sh: --prefix dizini oluşturulamadı: %s\n' "$PREFIX" >&2
    exit 2
  }
  # MUTLAKLAŞTIR. `cd --` seçenek-benzeri dizin adlarında (ör. `-weird`)
  # hata vermesin diye `--` kullanılır. Sembolik bağı da çözer.
  PREFIX="$(cd -- "$PREFIX" && pwd)"
fi

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

if [[ $CHECK -eq 1 ]]; then
  if preflight; then exit 0; else exit 1; fi
fi

if ! preflight; then
  if [[ -n "$PREFIX" ]]; then
    # --prefix kipi etkileşimsizdir (test/CI). TTY olmayan bir ortamda `read`
    # ya kalıcı bekler ya da soruyu hiç göstermeden vazgeçer; ikisi de bu
    # kipte yanlıştır. Eksikler raporlandı, kurulum yine de devam eder:
    # --prefix'in varlık sebebi tam da "sistem bağımlılıkları olmadan da
    # dosyaları yerine koyabilmek"tir (spec §7.1).
    echo "  (--prefix kipi: eksikler yalnızca raporlandı, kurulum devam ediyor)"
  else
    echo
    read -rp "Eksik bağımlılıklar var. Kuruluma devam edilsin mi? [e/H] " ans || true
    case "${ans:-}" in
      [Ee]*) ;;
      *) echo "Vazgeçildi. Önce eksikleri kur: sudo pacman -S ${MISSING_PKGS[*]}"; exit 1 ;;
    esac
  fi
fi
echo

# --- yol haritası -----------------------------------------------------------
# PREFIX boşken BU BLOK BİREBİR v0.1.0'daki gibi kalmalı. Burada bir yol bile
# "düzelttim" diye değiştirilirse, o kullanicinin kurulumu sessizce başka
# yere taşınır (bkz. test 13 ve task-4-report.md Step 7 kanıtı).
if [[ -n "$PREFIX" ]]; then
  # spec §7.1: __HOME__ placeholder genişletmesi DIR olur; böylece desktop
  # dosyaları ve plasmoid test prefix'ini GÖSTERİR ve mutlak yol olarak
  # geçerli kalır. Config altındaki conf.d/systemd/fuzzel aynı sebepten
  # $PREFIX/config/... altındadır (XDG ağacının aynası).
  HOME_SUB="$PREFIX"
  # __HOME__ placeholder'ı $PREFIX'e genişler ve şablonlar
  # `__HOME__/.local/bin/...` diyor. Bu yüzden BIN_DIR de aynı olmalı;
  # `$PREFIX/bin` iken üretilen desktop/plasmoid girdileri VAR OLMAYAN bir
  # yola işaret ediyordu (test 13b-3 yalnız __HOME__ kalıntısına bakıyordu,
  # yolun var olduğuna değil).
  BIN_DIR="$PREFIX/.local/bin"
  FISH_DIR="$PREFIX/config/fish/conf.d"
  SYSTEMD_DIR="$PREFIX/config/systemd/user"
  APPS_DIR="$PREFIX/applications"
  FUZZEL_DIR="$PREFIX/config/fuzzel"
  ICON_DIR="$PREFIX/icons"
  PLASMOID_DIR="$PREFIX/plasmoids/org.cachyagent.usage"
  CONFIG_DIR="$PREFIX/config/cachy-agent"
else
  HOME_SUB="$HOME"
  BIN_DIR="$HOME/.local/bin"
  FISH_DIR="$HOME/.config/fish/conf.d"
  SYSTEMD_DIR="$HOME/.config/systemd/user"
  APPS_DIR="$HOME/.local/share/applications"
  FUZZEL_DIR="$HOME/.config/fuzzel"
  ICON_DIR="$HOME/.local/share/icons/hicolor/scalable/apps"
  PLASMOID_DIR="$HOME/.local/share/plasma/plasmoids/org.cachyagent.usage"
  # Bu ikisi v0.1.0'da install.sh'te HİÇ yoktu (runtime script'ler kendi
  # oluşturuyordu). Yollar burada tanımlanıyor çünkü install artık config'i
  # kendisi yazıyor; CLI de config'i tam olarak bu çözümlemeden arıyor:
  #   ${CACHY_AGENT_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent/agents.conf}
  CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/cachy-agent"
fi

# I2: STATE_DIR listeden CIKARILDI — ne ataniyor ne olusturuluyor.
#  1. install.sh durum dizinine HICBIR SEY yazmiyor; durum dizini runtime
#     script'lerin isidir ve v0.1.0'da install.sh'te hic yoktu.
#  2. Erken yaratmak, uninstall.sh'nin temiz $HOME'daki
#     "(yok: ~/.local/state/cachy-agent)" satirini etkilesimli `ask`'e
#     donusturuyordu — kullanici hic dokunmadigi bir dizin icin soruya
#     dusuyordu. uninstall.sh kendi STATE_DIR'ini kendisi tanimliyor.
mkdir -p "$BIN_DIR" "$FISH_DIR" "$SYSTEMD_DIR" "$APPS_DIR" "$FUZZEL_DIR" "$ICON_DIR" "$PLASMOID_DIR" "$CONFIG_DIR"

echo "== dosyalar kopyalanıyor =="
# bin (çalıştırılabilir bayrağıyla)
# Bu glob cachy-agent, cachy-agent-agents ve cachy-agent-usage-* koleksiyonlarını
# da kapsar. Dört çağıran (menu/open/install/usage-update) kardeş binary'leri
# `BIN="${CACHY_AGENT_BIN_DIR:-$HOME/.local/bin}"` üzerinden arar; eksik dosya
# çalışma anında SESSİZCE atlanır, bu yüzden hepsi aynı sepette olmalıdır.
for f in "$SRC"/bin/*; do
  cp -f "$f" "$BIN_DIR/$(basename "$f")"
  chmod +x "$BIN_DIR/$(basename "$f")"
  echo "  bin: $(basename "$f")"
done
# VERSION: `cachy-agent --version` kurulumdan bağımsız sürümü raporlasın diye
# bin dizinine kopyalanır. Kullanıcı repoyu taşırsa fallback kırılmaz.
if [[ -f "$REPO_DIR/VERSION" ]]; then
  cp -f "$REPO_DIR/VERSION" "$BIN_DIR/VERSION"
  echo "  bin: VERSION"
fi

# fish (conf.d otomatik source'lanır, ek ayar gerekmez)
cp -f "$SRC/fish/cachy-agent.fish" "$FISH_DIR/cachy-agent.fish"
echo "  fish: conf.d otomatik source'lanıyor (yeni shell'de a/ga aktif)"

# systemd (repo'da %{...} yok, düz kopya)
for f in "$SRC"/systemd/*; do
  cp -f "$f" "$SYSTEMD_DIR/$(basename "$f")"
  echo "  systemd: $(basename "$f")"
done

# __HOME__ placeholder'lı dosyalar -> gerçek yol yazılır ($HOME ya da $PREFIX)
for f in "$SRC"/applications/*.desktop; do
  sed "s|__HOME__|$HOME_SUB|g" "$f" > "$APPS_DIR/$(basename "$f")"
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
  sed "s|__HOME__|$HOME_SUB|g" "$f" > "$PLASMOID_DIR/$f"
done)
echo "  plasmoid: org.cachyagent.usage"

# --- config (ajans kataloğu) -------------------------------------------------
# v0.1.0'da ajan listesi script'lerin İÇİNDEYDİ ve install.sh config'e hiç
# dokunmuyordu; v0.2.0'da tek doğruluk kaynağı ~/.config/cachy-agent/agents.conf
# (spec §5.1) ve menü oradan okuyor. Bu blok OLMASAYDI, Task 1-3'den sonra
# HİÇBİR mevcut kurulum bozulurdu: menü preflight'ı "config yok" der, `agent
# listesi alınamadı` basar ve exit 1 verir.
#
# "Yalnızca yoksa yaz" kuralı (spec §7.3) KATALOG DOSYASININ ANLAMIDIR: ajan
# listesi artık kullanıcının düzenleyebildiği bir dosya. `cp -f` kullanılsaydı
# her yeniden kurulum kullanıcının listesini sessizce geri alırdı.
SRC_CONF="$SRC/config/agents.conf"
if [[ -f "$SRC_CONF" ]]; then
  if [[ -f "$CONFIG_DIR/agents.conf" ]]; then
    echo "  config: agents.conf zaten var (korunuyor)"
  else
    # agents.conf'ta şu an __HOME__ YOK; sed zararsız ve kullanıcı ileride
    # eklemek isterse çalışır. Asıl taşıyıcılar desktop dosyaları ve plasmoid.
    sed "s|__HOME__|$HOME_SUB|g" "$SRC_CONF" > "$CONFIG_DIR/agents.conf"
    echo "  config: agents.conf yazildi -> $CONFIG_DIR/agents.conf"
  fi
else
  echo "  config: src/config/agents.conf YOK, atlandı (menü katalog okuyamaz!)"
fi

echo "== doğrula + etkinleştir =="
if [[ -n "$PREFIX" ]]; then
  # Test/CI ortamında systemd-user oturumu olmayabilir ve KDE cache'i
  # (kbuildsycoca6) kullanıcının gerçek oturumuna aittir. Prefix kurulumu
  # bunları YAPMAZ; dosyalar yine de yerine konur (spec §7.1).
  echo "  (atlandı: --prefix kipi — desktop-file-validate, kbuildsycoca6 ve systemctl --user çalıştırılmadı)"
else
  if command -v desktop-file-validate >/dev/null 2>&1; then
    # `cmd && echo` DEVRESİNE GİRMEZ: set -e yalnız && zincirinin SOLU
    # BAŞARISIZ olduğunda tetiklenmez. Ölçüldü: `set -e; false && echo X`
    # script'i öldürmüyor. Yani geçersiz desktop girdisi kurulumu düşürmeden
    # geçiyor ve kullanıcıya HİÇBİR şey söylenmiyordu — oysa geçersiz
    # girdi menü simgesinin/kısayolun görünmemesi demek.
    if desktop-file-validate "$APPS_DIR"/cachy-agent*.desktop; then
      echo "  desktop dosyaları geçerli"
    else
      echo "  UYARI: desktop dosyaları GEÇERSİZ (yukarıdaki hataya bak)" >&2
    fi
  else
    echo "  (atlandı: desktop-file-validate yok)"
  fi
  if command -v kbuildsycoca6 >/dev/null 2>&1; then
    # `|| true` + koşulsuz echo, başarısızlıkta da "çalıştı" diyordu.
    if kbuildsycoca6 >/dev/null 2>&1; then
      echo "  kbuildsycoca6 çalıştı"
    else
      echo "  UYARI: kbuildsycoca6 başarısız — KDE önbelleği yenilenmedi," >&2
      echo "         yeni simge/plasmoid görünmeyebilir" >&2
    fi
  fi
  systemctl --user daemon-reload
  systemctl --user enable --now cachy-crash-watch.service
  systemctl --user enable --now cachy-agent-usage-refresh.service
  systemctl --user enable --now cachy-agent-usage-refresh.timer
  echo "  servisler etkin: cachy-crash-watch.service, cachy-agent-usage-refresh.service/.timer"
fi

echo
echo "Kurulum tamam. Yeni bir terminalde 'a' / 'ga' çalışır."
echo "Kısayol (SUPER+SHIFT+CTRL+A): Sistem Ayarları > Klavye > Kısayollar > cachy-agent.desktop > Başlat."