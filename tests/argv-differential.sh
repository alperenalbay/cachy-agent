#!/usr/bin/env bash
# tests/argv-differential.sh — run_agent'ın her ajan için ürettiği argv'yi
# ÖLÇER ve tests/fixtures/argv-baseline.md'deki değerlerle karşılaştırır.
#
# Bu araç davranışın golden file'ıdır (spec §8.1/§8.2): refactor öncesi
# ölçülen 18 değeri kilitler, refactor sonrası hepsi birebir aynı olmalıdır.
# Sapma = davranış değişti; bu durumda KOD düzeltilir, beklenti tablosu değil.
#
# Yöntem: her ajan PATH'te bir stub ile gölgelenir. Stub çağrıldığında argv'sini
# $ARGV_LOG'a yazar. GERÇEK ajan CLI'ları hiç çalışmaz: ağ yok, credential yok,
# ajanın kendi config dosyasına dokunma yok. agy iki stub diziniyle ölçülür
# (§5.4.1): stub_agyA --help çıktısında izin bayrağı VAR, stub_agyB YOK.
#
# Kullanım:
#   argv-differential.sh [--check|--emit] [--agent <id>]
#     --check     (varsayılan) ölç, baseline ile karşılaştır; sapmada exit 1
#     --emit      ölç ve tests/fixtures/argv.txt'ye yaz
#     --agent ID  yalnızca o ajanın ölçümleri (test 14 agy için kullanır)
#
# Ruling 2: PATH ve CACHY_AGENT_CONFIG KENDİSİ kurar. tests/test.sh'in
# yaptığı PATH'e bağımlı değildir; tek başına da doğru ölçer.
#
# -e KULLANILMAZ: sapmada exit 1 döner, araç bu yüzden -e ile yaşamaz.
set -uo pipefail

REPO="$(cd "$(dirname "$0")/.." && pwd)"
export PATH="$REPO/src/bin:$PATH"
# Katalog: repodaki GERÇEK config. Kullanıcının kurulu config'i değil —
# ölçüm her makinede aynı olsun, ama config'in gerçekten üretilen argv'yi
# belirlediği görülsün (refactor bu okumayı yapan taraf).
export CACHY_AGENT_CONFIG="$REPO/src/config/agents.conf"

usage() {
  printf 'kullanım: %s [--check|--emit] [--agent <id>]\n' "$(basename "$0")" >&2
}

MOD=check
FILTRE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)  MOD=check; shift || true ;;
    --emit)   MOD=emit;  shift || true ;;
    --agent)  FILTRE="${2:-}"; shift || true; shift || true ;;
    -h|--help) usage; exit 0 ;;
    *) printf 'bilinmeyen argüman: %s\n' "$1" >&2; usage; exit 2 ;;
  esac
done

if [[ ! -r "$CACHY_AGENT_CONFIG" ]]; then
  printf 'argv-differential: config okunamıyor: %s\n' "$CACHY_AGENT_CONFIG" >&2
  exit 2
fi

SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT
mkdir -p "$SCRATCH/cwd"            # run_agent'in cd'si tetiklenmesin diye $HOME dışı
ARGV_LOG="$SCRATCH/argv.log"
STDERR_LOG="$SCRATCH/stderr.log"
export ARGV_LOG

# stub_yaz <dizin> <ajan> [--help metni]
# --help metni boşsa stub --help'e düşmez (o ajan için yardım metni sorulmaz).
stub_yaz() {
  local d="$1" ajan="$2" yardim="$3"
  mkdir -p "$d"
  {
    printf '#!/usr/bin/env bash\n'
    printf '# argv yakalama stub (gerçek ajan çalıştırılmaz)\n'
    if [[ -n "$yardim" ]]; then
      printf 'if [[ "${1:-}" == "--help" ]]; then\n'
      printf '  printf "%%s\\n" "%s"\n' "$yardim"
      printf '  exit 0\n'
      printf 'fi\n'
    fi
    printf 'printf "%s" >> "$ARGV_LOG"\n' "$ajan"
    printf 'for x in "$@"; do printf " [%%s]" "$x" >> "$ARGV_LOG"; done\n'
    printf 'printf "\\n" >> "$ARGV_LOG"\n'
    printf 'exit 0\n'
  } > "$d/$ajan"
  chmod +x "$d/$ajan"
}

# §5.4.1: iki dal. A dalında izin bayrağı YOKSA run_agent bayrakları düşürüp
# çıplak çağırır; bu iki yardım metni o koşulu tetikler.
AGY_YARDIM_A="Options: --dangerously-skip-permissions --effort low --prompt PROMPT"
AGY_YARDIM_B="Options: --prompt PROMPT"

for a in opencode claude codex crush copilot cursor-agent grok; do
  stub_yaz "$SCRATCH/stub_$a" "$a" ""
done
stub_yaz "$SCRATCH/stub_agyA" agy "$AGY_YARDIM_A"
stub_yaz "$SCRATCH/stub_agyB" agy "$AGY_YARDIM_B"

# olc <stub dizini> <ajan> [ek argümanlar...] -> ölçülen argv (tek satır)
olc() {
  local stub="$1" ajan="$2"; shift 2
  : > "$ARGV_LOG"; : > "$STDERR_LOG"
  ( cd "$SCRATCH/cwd" && PATH="$stub:$PATH" cachy-agent --inline "$ajan" "$@" ) \
      >/dev/null 2>"$STDERR_LOG"
  # Stub "<ajan> [arg] [arg]" yazar; köşeli parantezler argüman SINIRLARINI
  # görünür kılar (bir bayrak iki parçaya bölünse fark edilir). Baseline
  # tablosu ise boşlukla ayrılmış düz metin tutar. Bu yüzden ajan adı
  # atılır, sonra "[x]" -> "x" normalize edilir; sonuç argv-baseline.md'deki
  # hücrelerle BİREBİR aynı olur.
  local satir
  satir=$(head -n 1 "$ARGV_LOG")
  satir="${satir#"$ajan"}"
  satir="${satir# }"
  satir=$(printf '%s' "$satir" | sed 's/\[\([^]]*\)\]/\1/g')
  printf '%s' "$satir"
}

# Beklenen değerler argv-baseline.md'den SABİT string olarak (spec §8.2).
# agy burada YOK: iki dalı vardır, ayrı ele alınır.
beklenen_prompt() {   # ajanın "bayrak" kısmı, PROMPT eklenmeden
  case "$1" in
    opencode)     printf '%s' '--auto --prompt' ;;
    claude)       printf '%s' '--permission-mode auto -p' ;;
    codex)        printf '%s' '--approve-for-me' ;;
    crush)        printf '%s' '--yolo' ;;
    copilot)      printf '%s' '--allow-all' ;;
    cursor-agent) printf '%s' '--yolo --trust' ;;
    grok)         printf '%s' '--permission-mode bypassPermissions' ;;
    *)            return 1 ;;
  esac
}
beklenen_promptsuz() {
  case "$1" in
    opencode)     printf '%s' '--auto' ;;
    claude)       printf '%s' '--permission-mode auto' ;;
    codex)        printf '%s' '--approve-for-me' ;;
    crush)        printf '%s' '--yolo' ;;
    copilot)      printf '%s' '--allow-all' ;;
    cursor-agent) printf '%s' '--yolo --trust' ;;
    grok)         printf '%s' '--permission-mode bypassPermissions' ;;
    *)            return 1 ;;
  esac
}

# SAYAÇ TUTARLILIĞI: --check bir sapma bulmasa bile kaç ölçüm yaptığını bildirir.
# Test 14/15 bu sayıya bakar; aksi hâlde 0 ölçümle de geçebilirdi.
BEKLENEN_TUM=18
BEKLENEN_AGY=4

declare -a ETIKET=() BEKLENEN=() GELEN=()
N=0
SAPMA=0

# kaydet <etiket> <ajan> <beklenen argv> <stub dizini> [ek argümanlar...]
kaydet() {
  local etiket="$1" ajan="$2" bek="$3" stub="$4"; shift 4
  local gelen
  gelen=$(olc "$stub" "$ajan" "$@")
  ETIKET+=("$etiket"); BEKLENEN+=("$bek"); GELEN+=("$gelen")
  N=$((N+1))
  [[ "$gelen" == "$bek" ]] || SAPMA=$((SAPMA+1))
  return 0
}

filtre_ok() { [[ -z "$FILTRE" || "$FILTRE" == "$1" ]]; }

# 7 ajan x 2 (promptlu / promptsuz) = 14 ölçüm
for a in opencode claude codex crush copilot cursor-agent grok; do
  filtre_ok "$a" || continue
  kaydet "$a+prompt" "$a" "$(beklenen_prompt "$a") PROMPT" "$SCRATCH/stub_$a" PROMPT
  kaydet "$a"        "$a" "$(beklenen_promptsuz "$a")"       "$SCRATCH/stub_$a"
done

# agy: iki dal x 2 = 4 ölçüm (§5.4.1)
if filtre_ok agy; then
  kaydet "agy+A+prompt" agy "--dangerously-skip-permissions --effort low --prompt PROMPT" "$SCRATCH/stub_agyA" PROMPT
  kaydet "agy+A"        agy "--dangerously-skip-permissions"                          "$SCRATCH/stub_agyA"
  kaydet "agy+B+prompt" agy "--prompt PROMPT"                                         "$SCRATCH/stub_agyB" PROMPT
  kaydet "agy+B"        agy ""                                                       "$SCRATCH/stub_agyB"
fi

beklenen_adet=$BEKLENEN_TUM
[[ "$FILTRE" == "agy" ]] && beklenen_adet=$BEKLENEN_AGY

if [[ "$MOD" == "emit" ]]; then
  out="$REPO/tests/fixtures/argv.txt"
  {
    printf '# argv.txt — tests/argv-differential.sh --emit çıktısı\n'
    printf '# BU DOSYA KAYNAK DEĞİLDİR: golden file argv-baseline.md içidir.\n'
    printf '# sütunlar: <ölçüm> | <baseline> | <ölçülen>\n'
    for ((i=0; i<N; i++)); do
      printf '%s | %s | %s\n' "${ETIKET[i]}" "${BEKLENEN[i]}" "${GELEN[i]}"
    done
  } > "$out"
  printf 'argv: %d ölçüm -> %s\n' "$N" "$out"
  exit 0
fi

# --check
for ((i=0; i<N; i++)); do
  [[ "${GELEN[i]}" == "${BEKLENEN[i]}" ]] && continue
  printf 'FAIL: %s baseline "%s" != ölçülen "%s"\n' \
         "${ETIKET[i]}" "${BEKLENEN[i]}" "${GELEN[i]}"
  # Boş log genellikle "stub hiç çağrılmadı" demektir; sebebi stderr'de ara.
  if [[ -z "${GELEN[i]}" ]]; then
    printf '       (stub çağrılmadı — stderr: %s)\n' "$(head -n 1 "$STDERR_LOG")"
  fi
done

if [[ "$N" -ne "$beklenen_adet" ]]; then
  printf 'FAIL: ölçüm sayısı %d, beklenen %d\n' "$N" "$beklenen_adet"
  SAPMA=$((SAPMA+1))
fi

if [[ "$SAPMA" -ne 0 ]]; then
  printf 'argv: %d ölçümden %d tanesi sapmada\n' "$N" "$SAPMA"
  exit 1
fi
printf 'argv: %d ölçüm tamam\n' "$N"
exit 0
