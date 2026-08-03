# Stash — macOS pano yöneticisi

**Tarih:** 2026-08-04
**Durum:** Tasarım onaylandı, uygulama planı bekliyor

## Amaç

macOS'ta kopyalama geçmişini kart biçiminde gösteren, ekranın altına yapışık bir şeritten çalışan pano yöneticisi. Açık kaynak, herkesin kaynaktan kurabileceği bir araç.

Sebep: macOS'ta yerleşik pano geçmişi yok. Ücretsiz seçenekler (Maccy, Flycut) liste tabanlı ve görsel içeriği kötü gösteriyor; kart arayüzü sunan uygulamalar (Paste, Pastebot) ücretli. Stash bu boşluğu dolduruyor.

**İsim notu:** GitHub'da `stashapp/stash` adlı, ilgisiz ve popüler bir proje var. İsim bilinçli olarak seçildi; arama karışıklığını azaltmak için repo adı `stash-clipboard`, uygulama adı `Stash`.

## Kapsam

**v1'de var:**

- Metin, görsel, bağlantı ve dosya kopyalarının geçmişi
- Ekranın altına yapışık kart şeridi (300px, "çok ferah")
- Yazarak arama
- Doğrudan yapıştırma (öndeki uygulamaya)
- Sabitleme ve kullanıcı tanımlı raflar
- Yapıştırma filtreleri (düz metne çevir, boşluk temizle, akıllı tırnak düzelt)
- Hassas içerik koruması
- Elle temizleme (kart, son bir saat, tümü)

**v1'de yok:**

- Cihazlar arası senkron (iCloud). Ücretli geliştirici hesabı ve sunucu tarafı karmaşıklığı gerektiriyor, karşılığında v1 hedefine bir şey katmıyor.
- Otomatik saklama sınırı (süre/sayı). Silme kararı kullanıcıda.
- Mac App Store dağıtımı. Doğrudan yapıştırma ve Erişilebilirlik izni sandbox ile çelişiyor; Still Running gibi kaynaktan kurulum.

## Kararlar ve gerekçeleri

| Karar | Gerekçe |
|---|---|
| Alt şerit, 300px | Bir bakışta ~7 kart görünür; tarama kaydırmaya baskın gelir. Ortadaki panel daha büyük kart verirdi ama çalışılan içeriği kapatır. |
| SwiftPM + SwiftUI, Xcode projesi yok | `still-running` reposunda çalışan, test edilmiş kalıp. `.xcodeproj` merge çatışması yok, modül başına test hedefi var. |
| Üçüncü taraf bağımlılık yok | Still Running ile aynı duruş. Gizlilik iddiası olan bir araçta bağımlılık yüzeyi = denetlenecek yüzey. |
| Yoklama ile pano dinleme | macOS pano değişikliği bildirmez. `NSPasteboard.changeCount` ~0.5s aralıkla yoklanır; bütün pano yöneticilerinin yaptığı bu. |
| `RegisterEventHotKey` | Global kısayol için izin gerektirmiyor. `CGEventTap` gerektirirdi. |
| Varsayılan kısayol ⌥⌘V | ⌘⇧V global olarak kaydedilirse her uygulamadaki "biçimlendirmeyi eşleyerek yapıştır" gölgelenir. Ayarlanabilir. |
| Otomatik saklama sınırı yok | Kullanıcı kararı (2026-08-03 oturumu). Tek istisna aşağıdaki disk supabı. |

## Mimari

Modüller, Still Running'deki gibi SwiftPM hedefleri olarak ayrılır. Her modülün tek bir işi ve kendi test hedefi vardır.

| Modül | Sorumluluk | Bağımlılık |
|---|---|---|
| `PasteboardKit` | Pano yoklama, değişim tespiti, tip çözümleme, hassas tip eleme. Çıktısı saf `Clip` değeri. | — |
| `Store` | SQLite + disk kalıcılığı, sorgular, silme, disk kullanımı. | — |
| `HotKey` | Global kısayol kaydı ve çakışma raporlama. | — |
| `PasteEngine` | Panoya geri yazma, sentetik ⌘V, izin durumu. | — |
| `Filters` | Yapıştırma anı metin dönüşümleri (saf fonksiyonlar). | — |
| `StashCore` | Durum koordinasyonu, şerit görünüm modeli, ayarlar, panel sunumu. | Yukarıdakiler |
| `Stash` | Çalıştırılabilir: AppDelegate, menü çubuğu, `NSPanel`, SwiftUI görünümleri. | `StashCore` |

Sınır kuralı: **`PasteboardKit` diski bilmez, `Store` panoyu bilmez.** İkisini `StashCore` bağlar. Böylece pano yoklaması gerçek pano olmadan, saklama gerçek kopyalama olmadan test edilebilir.

### Veri akışı

```
NSPasteboard ──(0.5s yoklama)──> PasteboardKit
                                      │  Clip (saf değer)
                                      ▼
                                  StashCore ──> Store ──> SQLite + disk
                                      │
                                 (⌥⌘V)│
                                      ▼
                                  NSPanel (şerit)
                                      │  seçim
                                      ▼
                        Filters ──> PasteEngine ──> NSPasteboard + sentetik ⌘V
```

## Veri modeli

```
Clip
  id            UUID
  createdAt     Date
  kind          text | image | link | file
  text          String?       (metin içeriği; kind == file ise dosyanın URL'i)
  imagePath     String?       (görselin diskteki yolu)
  sourceApp     String?       (bundle id) + görünen ad
  pinned        Bool
  shelfId       UUID?         (boşsa "Tümü")
  contentHash   String        (tekrar kopyalamada yeni kayıt açmaz, mevcudu öne alır)
  byteSize      Int
```

`sourceApp` kopyalama anında öndeki uygulamadan alınır ve kartta gösterilir — hangi kart olduğunu hatırlatmanın en ucuz yolu.

### Disk düzeni

```
~/Library/Application Support/Stash/     (izinler 0700)
├── stash.sqlite       metadata
├── images/<uuid>.png  orijinal görsel
└── thumbs/<uuid>.jpg  kart önizlemesi
```

Arama: `text` sütununda `LIKE` sorgusu. Birkaç bin satırda yeterince hızlı; FTS5 kurulumunun karmaşıklığına girilmiyor.

### Silme ve disk supabı

Otomatik süre veya sayı sınırı yok. Kullanıcı eylemleri: tek kartı sil, son bir saati sil, tümünü temizle.

Tek otomatik davranış: `images/` dizini 2 GB'ı aşarsa en eski **görsel dosyaları** silinir — dizin 1,5 GB'ın altına inene kadar. (Eşiğin hemen altında durulsaydı her yeni görselde budama tetiklenirdi.) Sabitlenmiş kartların görselleri budanmaz. Kart kaydı ve metni kalır, kart "görsel artık saklanmıyor" durumuna geçer. Ayarlarda kaplanan alan her zaman görünür.

## Kullanım akışı

1. ⌥⌘V → şerit alttan yukarı kayar (~180ms). Odak çalınmaz; öndeki uygulama önde kalır.
2. ← → ile gezinme; yazmaya başlayınca üstte arama alanı belirir ve kartlar süzülür.
3. ↵ → kart panoya yazılır ve öndeki uygulamaya yapıştırılır, şerit kapanır.
4. ⌘1…⌘9 → o sıradaki kartı doğrudan yapıştır.
5. ⌥↵ → filtrelenmiş yapıştır (ayarlarda açık olan bütün filtreler sırayla uygulanır).
6. ⌃P sabitle · ⌃S rafa taşı · ⌫ sil · ⇥ sekmeler arası geçiş · Esc kapat.

Şerit farenin bulunduğu ekranda açılır. Dışarı tıklama, Esc veya uygulama değişimi kapatır.

**Sekmeler:** `Tümü` · `Sabitlenen` · `Görseller` · ardından kullanıcının oluşturduğu raflar. İlk üçü sabittir ve silinemez — `Sabitlenen` `pinned` alanına, `Görseller` `kind == image` koşuluna bakar, ikisi de raf değildir. Raflar ayarlarda oluşturulup silinir; bir kart ⌃S ile rafa taşınır ve `shelfId` alanına yazılır. Bir kart aynı anda tek rafta bulunur.

**Pencere davranışı:** `NSPanel`, `.nonactivatingPanel` stili, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]`. Bu ikisi Space zıplamasını ve tam ekran uygulamaların üstünde görünmeme sorununu baştan engeller.

## Görsel dil

Koyu plum panel (`#3A2D50` → `#211D2D` degrade), mor vurgu (`#A06CF5`), buzlu cam. Kartlar 162×200px, seçili kart 224px'e büyür. Tip etiketi mono ve küçük (`GÖRSEL`, `METİN`, `BAĞLANTI`), içerik altında.

Tek tema: koyu. Açık tema v1'de yok.

## Ayarlar

Menü çubuğu ikonundan açılan tek pencere. Ayarlanabilenler:

- Global kısayol (varsayılan ⌥⌘V)
- Açılışta başlat
- Aktif yapıştırma filtreleri ve sıraları
- Kaydedilmeyecek uygulamalar (kara liste)
- Raf oluştur / sil / yeniden adlandır
- Kaplanan disk alanı (salt okunur) + "Tümünü temizle" ve "Son bir saati temizle"
- Erişilebilirlik izni durumu + izin verme kısayolu

Değerler `UserDefaults`'ta tutulur; raflar veritabanında.

## Gizlilik

Public bir araçta bu iddiaların kaynaktan doğrulanabilir olması gerekir.

- **Ağ kodu yok.** Uygulama hiçbir ağ çağrısı içermez. README'de belirtilir.
- **Şifre yöneticileri kaydedilmez:** `org.nspasteboard.ConcealedType`, `TransientType`, `AutoGeneratedType` işaretli pano içerikleri es geçilir.
- **Uygulama kara listesi:** belirtilen uygulamalardan gelen kopyalar hiç kaydedilmez. Varsayılan: 1Password, Keychain Access.
- **Desen maskeleme:** kart numarası benzeri diziler ve yüksek entropili token'lar kartta maskeli görünür (`•••• 4242`), tıklayınca açılır. Kaydedilir ama omuz üstünden okunmaz.
- **Veritabanı şifreli değil**, FileVault'a güvenilir. README bunu açıkça yazar; gizlilik iddiasını olduğundan büyük göstermek en kötü hata olurdu.

## Hata durumları

| Durum | Davranış |
|---|---|
| Erişilebilirlik izni yok | Uygulama çalışır; ↵ yapıştırmak yerine kopyalar. Şeritte açıklama + "İzin ver" düğmesi. |
| İzin sonradan kaldırıldı | Her yapıştırma öncesi kontrol; sessizce kopyalamaya düşer. |
| Kısayol başka uygulamada kayıtlı | Kayıt başarısız olur; ayarlarda uyarı ve yeni kombinasyon istenir. Sessiz ölü kısayol olmaz. |
| Disk yazma hatası | Kayıt atlanır, menü çubuğu ikonu uyarır, uygulama çökmez. |
| Görsel dosyası kayıp | Kart "görsel bulunamadı" durumuna geçer, silinebilir. |
| SQLite bozuk | Dosya yedeklenir, yeni veritabanı açılır, kullanıcıya bildirilir. Veri kaybı gizlenmez. |

## Test

Modül başına test hedefi:

- `PasteboardKitTests` — pano bir protokolün arkasında; sahte pano ile changeCount senaryoları, tip çözümleme, gizli tip eleme, tekrar kopyalama (dedupe)
- `StoreTests` — geçici dizinde gerçek SQLite: ekleme, arama, sabitleme, silme, 2 GB budaması, dizin izinlerinin 0700 olması
- `FiltersTests` — saf fonksiyonlar, girdi/çıktı tabloları
- `PasteEngineTests` — izin yokken kopyalamaya düşme
- `HotKeyTests` — kayıt ve çakışma
- `StashCoreTests` — seçim, süzme, raf geçişleri

**Elle QA (otomatikleştirilemez):** odağın çalınmaması, iki ekranlı kurulum, tam ekran uygulama üstünde açılma, Space değişimi, izin verme akışının ilk çalıştırmada gerçekten çalışması. Pencere yönetimi bu işin en kırılgan yeri; gerçek makinede sürülecek.

## Dağıtım

Still Running kalıbı: `scripts/bundle.sh` ile `.app` üretimi, kaynaktan kurulum talimatı, README + LICENSE + CHANGELOG. DMG yok, notarization yok.
