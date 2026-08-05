# Elle QA

Otomatik test edilemeyen davranışlar. Her sürümden önce gerçek makinede.

## Odak
- [ ] Bir metin editöründe yazarken ⌥⌘V'ye bas. Editörün başlık çubuğu
      soluklaşmamalı, imleç yanıp sönmeye devam etmeli.
- [ ] ↵ ile yapıştır. Metin editöre girmeli, Stash'e değil.

## Ekranlar
- [ ] İki ekranlı kurulumda fareyi ikinci ekrana götür, ⌥⌘V. Şerit farenin
      olduğu ekranda açılmalı.
- [ ] Ekran çözünürlüğünü değiştir, tekrar dene.

## Space ve tam ekran
- [ ] Tam ekran bir uygulamada ⌥⌘V. Şerit üstte açılmalı, Space değişmemeli.
- [ ] Şerit açıkken Space değiştir. Şerit önceki Space'e takılıp kalmamalı.

## İzin
- [ ] Erişilebilirlik iznini kaldır, uygulamayı yeniden başlat, ↵ ile yapıştır.
      "Panoya kopyalandı" uyarısı çıkmalı, uygulama çökmemeli.
- [ ] İzni ver, uygulamayı yeniden başlatmadan tekrar dene. Yapıştırmalı.
- [ ] Kaynaktan yeniden derleyip `/Applications`'a yeniden kur (imza
      değişir). Önceden verdiğin Erişilebilirlik izni sessizce geçersiz
      kalmalı — yapıştırma yerine panoya kopyalamaya düşmeli. İzni listeden
      kaldırıp yeniden eklemek düzeltmeli.

## Kısayol çakışması
- [ ] ⌥⌘V'yi kullanan başka bir uygulama açıkken Stash'i başlat. Uyarı
      penceresi çıkmalı, sessiz kalmamalı.

## Açılışta başlat
- [ ] Ayarlar'da "Açılışta başlat"ı aç. Sistem Ayarları → Genel → Giriş
      Öğeleri listesinde Stash görünmeli.
- [ ] Oturumu kapat/aç ya da yeniden başlat. Stash kendiliğinden açılmalı.
- [ ] Sistem Ayarları'ndan Giriş Öğeleri listesinden Stash'i kapat, Stash
      Ayarları'na geri dön. Anahtar kapalı görünmeli (durum gerçekten
      okunuyor, önbelleklenmiş bir değer değil).
- [ ] `/Applications` dışına (ör. Masaüstü) kopyalanmış bir kopyada anahtarı
      dene. Kayıt başarısız olursa bir hata penceresi çıkmalı ve anahtar
      açık göstermemeli.

## Ekran görüntüsü klasörü izleme
- [ ] Ayarlar'da "Ekran görüntüsü klasörünü izle"yi ilk kez aç. Bir izin
      istemi çıkmalı (Masaüstü/Belgeler için).
- [ ] İzni ver, ⌘⇧4 (ya da ⇧⌘4) ile bir ekran görüntüsü al. Bir kart olarak
      geçmişe düşmeli; kaynağı "Ekran görüntüsü" yazmalı, `loginwindow`
      değil.
- [ ] Aynı görüntüyü sonra panoya kopyala (ör. Önizleme'de aç, ⌘A, ⌘C).
      Geçmişte İKİ kart değil, aynı kart görünmeye devam etmeli.
- [ ] Masaüstüne (ya da ayarlı klasöre) sıradan bir PNG/ekran görüntüsü
      OLMAYAN bir dosya bırak. Geçmişe düşmemeli.
- [ ] İzni reddet (ya da `tccutil reset SystemPolicyDesktopFolder
      social.selin.stash` ile sıfırlayıp yeniden dene). Anahtar
      kendiliğinden kapanmalı, görünür bir uyarı çıkmalı — sessizce "açık"
      görünüp arka planda çalışmayan bir anahtar kalmamalı.
- [ ] `defaults write com.apple.screencapture location ~/Downloads`
      (ardından `killall SystemUIServer`) ile ekran görüntüsü hedefini
      değiştir, Stash'i yeniden başlatmadan tekrar ⌘⇧4 dene. Yeni klasörden
      yakalamalı.
      (Bitince `defaults delete com.apple.screencapture location` ile geri al.)
- [ ] Anahtarı kapat. O andan sonra alınan ekran görüntüleri geçmişe
      düşmemeli.

## Veri
- [ ] Şifre yöneticisinden bir parola kopyala. Geçmişte görünmemeli.
- [ ] Bir kart numarası kopyala. Kartta maskeli görünmeli.
- [ ] 20-30 ekran görüntüsü kopyala, Ayarlar'da disk boyutunun büyüdüğünü gör.
- [ ] "Tümünü temizle" sonrası sabitlenen kartların kaldığını doğrula.

## Kısayol
- [ ] Ayarlar > Shortcut > Change ile yeni bir kombinasyon seç. Pencereyi kapat
      ve YENİDEN BAŞLATMADAN yeni kısayola bas: şerit açılmalı.
- [ ] Aynı oturumda eski kısayola bas: hiçbir şey olmamalı. (0.1.0'daki hata
      tam buydu — yeni kısayol ekranda görünüyor, kayıtlı olan eskisi kalıyordu.)
- [ ] `open -n /Applications/Stash.app` ile ZORLA ikinci bir kopya aç. Tek
      kopya kalmalı (`pgrep -x Stash | wc -l` = 1) ve kısayol çalışmaya devam
      etmeli. (0.2.0 öncesi: iki kopya aynı kombinasyonu kaydediyor, eski
      kopya ölürken yuvayı boşaltıyor ve kısayol sessizce ölüyordu.)
- [ ] Ekranı uyut (`pmset displaysleepnow`), uyandır ve kısayola bas. Şerit
      açılmalı. (0.2.0 öncesi: animasyon çalışmadığı için panel ekranın
      altında takılı kalıyor, "açık" sayıldığı için de bir daha hiç
      görünmüyordu — menüden bile.)
- [ ] Erişilebilirlik > Ekran > "Hareketi azalt" açıkken de şerit açılmalı.
- [ ] Başka bir uygulamanın kullandığı bir kombinasyonu seç (ör. ⌘Boşluk).
      Uyarı çıkmalı ve ESKİ kısayol çalışmaya devam etmeli — kısayolsuz
      kalınmamalı.

## Güncelleme
- [ ] Menüde "Check for Updates…" var. Hiç sürüm yayınlanmamışken tıkla:
      "No release has been published yet" demeli, kırmızı bir arıza gibi
      görünmemeli.
- [ ] Ayarlar > Updates anahtarını kapat, uygulamayı yeniden başlat ve
      `nettop`/Little Snitch ile bak: kendiliğinden hiçbir istek çıkmamalı.
- [ ] Yayınlanmış bir sürümden ESKİ bir sürüm çalıştır (Info.plist'te sürümü
      düşürüp derle). Menü öğesi "Update to X…" olmalı; tıkla, indirsin,
      Stash kapanıp yeni sürümle geri açılmalı. Menüdeki sürüm yeni olmalı.
- [ ] Güncellemeden sonra pano geçmişi ve raflar yerinde olmalı (veriler
      `~/Library/Application Support/Stash/`, bundle'ın içinde değil).
- [ ] `/Applications` yerine salt okunur bir yere kopyalanmış bir Stash'te
      güncellemeyi dene: KAPANMADAN önce "can't update in place" demeli.
- [ ] Bozuk bir zip yayınla (ya da başka bir uygulamayı Stash.zip diye koy):
      "wasn't signed by the same identity" deyip reddetmeli, çalışan kopya
      olduğu gibi kalmalı.
