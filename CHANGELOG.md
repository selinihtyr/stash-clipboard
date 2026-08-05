# Changelog

## 0.2.0

**Düzeltildi — kısayolu değiştirmek işe yaramıyordu.** Ayarlar'dan yeni bir
kombinasyon seçmek onu diske yazıyor ve ekranda gösteriyordu, ama kaydı
değiştirmiyordu: şerit yeniden başlatılana kadar hâlâ ESKİ kısayolla açılıyordu.
Sebep, "önceki kombinasyon"un ayarlar mağazasından okunmasıydı — ayarlar
penceresi mağazayı bildirimden önce güncellediği için karşılaştırma her zaman
"değişmedi" diyordu.

**Yeni — uygulama kendini güncelliyor.** Menüde "Check for Updates…". Günde bir
GitHub'a yeni sürüm olup olmadığı soruluyor (Ayarlar > Updates'ten kapatılabilir);
bulununca menü öğesi "Update to X…" oluyor, tıklayınca indirilip yerine
kuruluyor ve Stash yeniden açılıyor. Silip yeniden indirmek yok.

- İnen bundle, imzası Stash'in yayın kimliğine (ekip `HN964HX2UA`) uymazsa
  reddediliyor ve siliniyor — indirilen kod, doğrulanmadan çalıştırılmıyor.
- Sürüm ve bundle kimliği de kontrol ediliyor: eski bir zip'i yeni diye sunmak
  (downgrade) geçmiyor.
- Takas, Stash kapandıktan sonra bağımsız bir betikle yapılıyor; kopyalama
  başarısız olursa eski kopya geri konuyor.
- Uygulamanın bulunduğu yer yazılabilir değilse, KAPANMADAN önce söylüyor.
- Bu, uygulamanın ağa çıktığı tek yer (bkz. README, Gizlilik).

## 0.1.0 — yayınlanmadı

İlk sürüm.

- Metin, görsel, bağlantı ve dosya kopyalarının geçmişi
- Ekranın altına yapışık kart şeridi, ⌥⌘V ile açılır
- Yazarak arama
- Doğrudan yapıştırma (Erişilebilirlik izniyle), izinsizse panoya kopyalama
- Sabitleme ve raflar
- Yapıştırma filtreleri: düz metin, boşluk temizleme, akıllı tırnak düzeltme
- Hassas içerik koruması: iş birliği tipleri, uygulama kara listesi, desen maskeleme
- Elle temizleme; görseller 2 GB'ı aşarsa en eskiler budanır
- Açılışta başlatma (`SMAppService`, yalnızca `/Applications`'a kurulu bundle için)
