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

## Veri
- [ ] Şifre yöneticisinden bir parola kopyala. Geçmişte görünmemeli.
- [ ] Bir kart numarası kopyala. Kartta maskeli görünmeli.
- [ ] 20-30 ekran görüntüsü kopyala, Ayarlar'da disk boyutunun büyüdüğünü gör.
- [ ] "Tümünü temizle" sonrası sabitlenen kartların kaldığını doğrula.
