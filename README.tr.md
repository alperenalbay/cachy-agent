# cachyAgent

KDE / CachyOS için agentic katman: hızlı başlatıcı menüsü, bağımlılık denetleyen kurulum, tek-seferlik tanı (diagnose) içeren çökme bildirimi, Plasma widget'lı yerel kullanım takibi ve genel kısayol.

## Özellikler

- **Katalog tabanlı menü** — agent'lar tek bir `agents.conf` dosyasından gelir; tüm script'ler ve plasmoid oradan okur. Agent eklemek tek satır.
- **Bağımlılık denetleyen kurulum** — `install.sh` gereksinimleri denetler, betikleri kurar ve `agents.conf`'u yazar (yalnızca dosya yoksa; böylece düzenlemeleriniz yeniden kurulumda korunur).
- **Çökme bildirimi + tanı** — `crash-watch` yardımcısı anormal çıkışları yakalar, masaüstü bildirimi gönderir ve tek-seferlik `diagnose` çalışması önerir.
- **Kullanım takibi + plasmoid** — `codex`, `copilot` ve `opencode` için yerel toplayıcılar; Plasma 6 plasmoid'i son kullanımı gösterir.
- **Genel kısayol** — Plasma'da her yerden agent menüsünü açan tek tuş kombinasyonu (elle kaydedilir, aşağıya bakın).

## Gereksinimler

- CachyOS / Arch Linux
- KDE Plasma 6
- `fuzzel`
- `alacritty`
- `fish`
- `mise`

## Kurulum

```bash
./install.sh
```

Kurulum betiği gereksinimleri denetler, menü betiklerini kurar, `agents.conf` dosyası yoksa yazar, plasmoid'i kurar ve çökme izleyiciyi etkinleştirir. **Genel kısayolu kaydetmez** — bunu bir kez elle yapın: Sistem Ayarları › Klavye › Kısayollar › cachyAgent › Başlat.

## Kullanım

Agent menüsünü aç (birini seç):

- **Genel kısayola** bas (yukarıdaki elle kayıt), veya
- **Plasma panel simgesine** tıkla / başlatıcı girdisini çalıştır, veya
- Terminalde `a` yaz.

Örnekler:

```bash
# agent menüsünü aç
a

# agy (ikinci takma ad)
ga
```

Çökme akışı:

1. Agent işlemi anormal şekilde kapanır.
2. `crash-watch` bir masaüstü bildirimi gösterir.
3. Bildirimdeki eylemi onayla, log ve ortamı toplayan tek-seferlik `diagnose` çalışır.

## Ekran Görüntüsü

![agent menüsü](docs/screenshot-menu.png)

## Kaldırma

```bash
./uninstall.sh
```

`install.sh` ile kurulan menü girdilerini, kısayolu, plasmoid'i ve çökme izleyiciyi kaldırır.

## Yapılandırma

Tüm agent'lar tek dosyada: `~/.config/cachy-agent/agents.conf`.

```ini
# Format: id=görünen_ad|install|flags|prompt_flag|login
claude=Claude Code|npm i -g @anthropic-ai/claude-code|--permission-mode auto|-p|claude login
codex=Codex|npm i -g @openai/codex|--approve-for-me|-|codex login
```

- `install`, `cachy-agent-install <id>` komutunun onayınızdan sonra çalıştırdığı komuttur; `-` "otomatik kurulum yok" demektir (agent paket yöneticisi dışından gelir).
- `flags` her açılışta geçirilir.
- `prompt_flag`, agent'ın prompt'u nasıl aldığıdır (`--prompt`, `-p`); `-` prompt'un konumsal verildiği anlamına gelir.
- `login`, açılış başarısızsa gösterilen ipucudur; `-` giriş gerekmez demektir.

Dilediğiniz gibi düzenleyin — `install.sh` dosyayı yalnızca yoksa yazar, yani yeniden kurulum düzenlemelerinizi korur. `WORKDIR=` satırı `a`/`ga`'nın açılacağı dizini belirler (varsayılan `~/Projeler`). Tam referans: `docs/agents.md`.

## Testler

```bash
./tests/smoke.sh                  # repo sağlığı: sözdizimi, yer tutucular, unit dosyaları
./tests/test.sh                   # tam süit; hiçbir kurulum gerektirmeden çalışır
./tests/argv-differential.sh --check   # agent açılış argv'si ölçülmüş tabana karşı
```

Süit, temiz checkout'tan ağa, kimlik bilgisine ve gerçek agent CLI'lerine dokunmadan çalışır.

## Bilinen Sınırlar

- Kolektörü olmayan agent'ların kotası programatik olarak denetlenmez — kullanımı el ile izle.
- Kullanım izleme 8 katalog agent'ından yalnız 3'ü için kolektör içerir (`opencode`, `codex`, `copilot`); diğer beşi (`agy`, `claude`, `crush`, `cursor-agent`, `grok`) izlenmez — bkz. `docs/usage-schema.md`.
- Claude tabanlı agent'lar için `claude login` gerekir; kurulum CLI'nin varlığını doğrular ama senin yerine giriş yapamaz.
