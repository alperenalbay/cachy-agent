# Changelog

## 0.2.0 — 2026-10-11

> **Yükseltme notu:** `install.sh` çalıştırılmadan önceki eski kurulumda
> `cachy-agent-agents` kurulmaz ve `cachy-agent` çalışmaz — sürüme geçerken
> önce `./install.sh` çalıştırın.

### Tek katalog kaynağı

- Yeni **`agents.conf`**: tüm agent tanımları tek dosyada
  (`id=ad|install|flags|prompt_flag|login`). Yeni agent eklemek artık tek
  satır; kod değişmez.
- Yeni **`cachy-agent-agents` CLI**: config'i okuyan tek okuyucu. Menü,
  `cachy-agent`, `cachy-agent-open`, `cachy-agent-install`,
  `cachy-agent-usage-update` ve plasmoid artık hardcoded liste taşımıyor.
- **`prompt_flag` alanı**: her CLI prompt'u farklı aldığı için agent başına
  ayrıldı (`opencode`/`agy` bayrakla, diğer beşi konumsal).
- `WORKDIR` artık config'ten okunur (`~/Projeler` varsayılanı korunur).
- `install.sh` config'i **yalnızca yoksa** yazar; kullanıcı düzenlemeleri
  yeniden kurulumda korunur.

### Kullanım davranışı

- `cachy-agent default` temiz kurulumda artık `cat:` hatası vermez; varsayılanı
  basar (v0.1.0'dan beri var olan hata).
- `cachy-agent-install` onayı TTY'siz ortamda atlanamaz; onay alınamazsa
  kurulum komutu çalışmaz.
- `cachy-agent-open` geçersiz agent'ı artık yanlış rapor etmez: config hatası,
  eksik config ve gerçekten bilinmeyen agent ayrı mesajlarla bildirilir.
- Dört tüketicide `cachy-agent-agents` mutlak yol üzerinden çözülür
  (`CACHY_AGENT_BIN_DIR`); systemd/desktop-entry ortamlarında PATH'e bağımlılık kalktı.

### Gömülü Python kaldırıldı

- Yeni **`cachy-agent-usage-fetch`**: plasmoid'in providers JSON'u ve
  `cachy-agent usage` özetini üretir. **`XDG_STATE_HOME` artık destekleniyor**
  (plasmoid `~/.local/state`'e sabitlenmişti; diğer okuyucularla tutarlı hale geldi).
- Ölü fallback'ler temizlendi (`limits[].usedPercent`, `limits[].name`,
  `today`, `total` — hiçbir kolektör üretmiyordu; `?` basıyordu).
- `ready` varsayılanı tek yerde `True` (`usage-panel` `False` idi).
- `ready:false` kayıtların `reason` alanı artık okunuyor (silinen bilgi).
- `opencode` kolektörünün hata yolları tam alan setine uyduruldu.

### Testler ve CI

- Testler **repoya bağlandı**: temiz checkout'ta, kurulum yapmadan, ağa ve
  kimlik bilgisine dokunmadan çalışır (gerçek `codex` RPC'si testten çıkarıldı).
- `install.sh`/`uninstall.sh` **`--prefix`**: testler izole dizine kurup kaldırır.
- `argv-differential.sh`: agent açılış argv'si 18 ölçümlük ölçülmüş tabana
  karşı doğrulanır — refactor davranış değiştirmişse yakalar.
- **GitHub Actions CI**: shellcheck (sürüm kısıtlı), smoke, test, argv
  doğrulaması, ve "suite repoya yazmamalı" kontrolü.
- `smoke.sh` artık repoya yazmıyor (`__pycache__` silme kaldırıldı; `py_compile`
  geçici dizine yönlendirildi) ve **kurulmamış makinede de geçer** (unit
  doğrulaması `%h` yeniden yazımı + stub'larla yapılır).
- Test 11-18: config parse/check her kuralı ayrı testle kilitli;
  `tr_TR.UTF-8` collation hatası için regresyon testi (bkz. aşağıda).

### Düzeltilen hatalar

- **tr_TR collation**: bash regex aralıkları collation'a duyarlı; Türkçe
  sıralamada `[A-Za-z0-9_-]` küçük `i`'yi içermiyordu, `copilot` reddediliyordu.
  Config parser'da `LC_COLLATE=C` sabitlendi.
- `cachy-agent-usage-fetch` `NaN`/`Infinity` sayaç ve yüzde değerlerinde
  artık patlamıyor; geçersiz değer `0`/atlanmış sayılıyor.

### Dokümantasyon

- README'de kodla çelişen iddialar düzeltildi: "two-part catalog",
  "guided setup flow", "registers the global shortcut" (kaydetmez),
  ekran görüntüsü placeholder notu (görüntü zaten vardı).
- Yeni `docs/agents.md` (config referansı, `agy` koşullu bayrakları,
  yeni agent ekleme) ve `docs/usage-schema.md` (kullanım JSON şeması,
  alan sözleşmesi, hangi agent'ın kolektörü yok).
- `.gitignore` eklendi (`__pycache__`, `*.pyc`, `.worktrees/`, üretilen argv çıktısı).

## 0.1.0 — 2026-10-04

- 8-agent menu (fuzzel picker with search + launch).
- Two-part catalog (global definitions + per-project overrides).
- Crash-watch + desktop notification with one-shot diagnose flow.
- Usage collectors + Plasma 6 plasmoid for recent usage.
- Global shortcut for opening the agent menu from anywhere.
- Security package (input validation, least-privilege defaults, local-only usage data).
