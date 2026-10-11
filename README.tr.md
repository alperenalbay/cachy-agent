# cachyAgent

KDE / CachyOS için agentic katman: hızlı başlatıcı menüsü, rehberli kurulum akışı, tek-seferlik tanı (diagnose) içeren çökme bildirimi, Plasma widget'lı yerel kullanım takibi ve genel kısayol.

## Özellikler

- **8 agent menüsü** — `fuzzel` seçicide 8 yapılandırılmış agent (ara, ok tuşları, Enter ile başlat).
- **İki bölümlü katalog** — genel agent tanımları + proje bazlı geçersiz kılmalar, menü kurulurken birleştirilir.
- **Rehberli kurulum akışı** — bağımlılıkları denetleyip yapılandırmayı yazan etkileşimli ilk çalıştırma.
- **Çökme bildirimi + tanı** — `crash-watch` yardımcısı anormal çıkışları yakalar, masaüstü bildirimi gönderir ve tek-seferlik `diagnose` çalışması önerir.
- **Kullanım takibi + plasmoid** — hafif yerel toplayıcılar agent çalıştırmalarını kaydeder; Plasma 6 plasmoid'i son kullanımı gösterir.
- **Genel kısayol** — Plasma'da her yerden agent menüsünü açan tek tuş kombinasyonu.

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

Kurulum betiği yukarıdaki gereksinimleri denetler, menü betiklerini kurar, genel kısayolu kaydeder, plasmoid'i kurar ve çökme izleyiciyi etkinleştirir.

## Kullanım

Agent menüsünü aç (birini seç):

- **Genel kısayola** bas (`install.sh` ile kaydedilir), veya
- **Plasma panel simgesine** tıkla / başlatıcı girdisini çalıştır, veya
- Terminal yardımcısında `a`, rehberli sürüm için `ga` yaz.

Örnekler:

```bash
# 8-agent menüsünü aç
a

# rehberli: kurulum ipuçlu menü
ga
```

Çökme akışı:

1. Agent işlemi anormal şekilde kapanır.
2. `crash-watch` bir masaüstü bildirimi gösterir.
3. Bildirimdeki eylemi onayla, log ve ortamı toplayan tek-seferlik `diagnose` çalışır.

## Ekran Görüntüsü

![agent menüsü](docs/screenshot-menu.png)

> Yer tutucu — gerçek ekran görüntüsünü `docs/screenshot-menu.png` yoluna ekle.

## Kaldırma

```bash
./uninstall.sh
```

`install.sh` ile kurulan menü girdilerini, kısayolu, plasmoid'i ve çökme izleyiciyi kaldırır.

## Bilinen Sınırlar

- Agent kotası (örn. agy kotası) programatik olarak denetlenmez — kullanımı el ile izle.
- Kullanım izleme 8 katalog agent'ından yalnız 3'ü için kolektör içerir (`opencode`, `codex`, `copilot`); diğer beşi (`agy`, `claude`, `crush`, `cursor-agent`, `grok`) izlenmez — bkz. `docs/usage-schema.md`.
- Claude tabanlı agent'lar için `claude login` gerekir; kurulum akışı bunu doğrular ama senin yerine giriş yapamaz.
