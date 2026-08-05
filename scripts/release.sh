#!/usr/bin/env bash
# Yayınlanabilir bir sürüm üretir: Stash.app -> Stash.zip (+ SHA-256).
#
# Uygulamanın güncelleyicisi indirdiği bundle'ı SABİT bir ekip kimliğine karşı
# doğruluyor (bkz. Sources/Updater/SignatureCheck.swift). Yani bu betiğin
# ürettiği zip, o kimlikle imzalanmış olmak ZORUNDA — ad-hoc imzalı bir zip
# yayınlanırsa kimsenin güncellemesi kurulmaz, herkes "doğrulanamadı" uyarısı
# alır. Betik bunu sessizce geçmiyor, aşağıda kontrol ediyor.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Stash.app"
EXPECTED_TEAM="HN964HX2UA"

"$ROOT/scripts/bundle.sh" release

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
TAG="v$VERSION"
ZIP="$ROOT/build/Stash.zip"

TEAM="$(codesign -dv --verbose=4 "$APP" 2>&1 | awk -F= '/^TeamIdentifier=/ {print $2}')"
if [ "$TEAM" != "$EXPECTED_TEAM" ]; then
    echo "DUR: bundle $TEAM ile imzalı, güncelleyici $EXPECTED_TEAM bekliyor." >&2
    echo "Bu zip yayınlanırsa hiçbir kullanıcının güncellemesi kurulmaz." >&2
    echo "STASH_SIGN_IDENTITY ile doğru sertifikayı seçip tekrar deneyin." >&2
    exit 1
fi

rm -f "$ZIP"
# `ditto -c -k --keepParent`: imza mühürlerini ve genişletilmiş öznitelikleri
# koruyan tek yol. `zip` ile sıkıştırılan bir bundle'ın imzası açıldığında
# bozuk görünür ve güncelleyici onu (haklı olarak) reddeder.
ditto -c -k --keepParent "$APP" "$ZIP"

echo
echo "Sürüm : $VERSION  (etiket $TAG)"
echo "Zip   : $ZIP"
echo "SHA256: $(shasum -a 256 "$ZIP" | awk '{print $1}')"
echo "İmza  : $(codesign -dv --verbose=2 "$APP" 2>&1 | awk -F= '/^Authority=/ {print $2; exit}')"
echo
echo "Yayınlamak için (herkese açık bir işlem, geri alması zor):"
echo "  gh release create $TAG \"$ZIP\" --title \"Stash $VERSION\" --notes-file notes.md"
echo
echo "Sürüm notları KULLANICIYA UYGULAMA İÇİNDE gösteriliyor (güncelleme"
echo "penceresi \`body\` alanını basıyor) — CHANGELOG.md Türkçe, notları"
echo "İngilizce yazın."
echo
echo "Yayınlanan etiket, çalışan kopyaların gördüğü sürümdür: CHANGELOG'daki"
echo "başlıkla Info.plist'teki CFBundleShortVersionString aynı olmalı."
