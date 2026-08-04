#!/usr/bin/env bash
# Builds "Stash.app" from the SwiftPM executable.
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/build/Stash.app"

swift build -c "$CONFIG" --package-path "$ROOT"
BIN_PATH="$(swift build -c "$CONFIG" --package-path "$ROOT" --show-bin-path)"

# Çalışan kopyanın bundle'ını silmek kendi çalıştırılabilirini altından çeker:
# macOS binary'yi tembel sayfalar, ihtiyaç duyduğu bir sonraki sayfa yok olur
# ve süreç bus error alır. Önce kapatıyoruz.
if pgrep -x Stash >/dev/null 2>&1; then
    osascript -e 'quit app id "social.selin.stash"' >/dev/null 2>&1 || pkill -x Stash || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
        pgrep -x Stash >/dev/null 2>&1 || break
        sleep 0.3
    done
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/Stash" "$APP/Contents/MacOS/Stash"
cp "$ROOT/Sources/Stash/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/Sources/Stash/AppIcon.icns" "$APP/Contents/Resources/AppIcon.icns"

# Kopyalama/yapıştırma sesleri de aynı sebeple SwiftPM kaynak işlemesinden
# değil, buradan elle kopyalanıyor (bkz. Package.swift'teki exclude notu).
# CREDITS.txt de yanlarında gidiyor: klasör repo dışına kopyalanırsa lisans
# şartları da onunla birlikte taşınsın diye (CC-BY 3.0, bkz. README).
mkdir -p "$APP/Contents/Resources/Sounds"
cp "$ROOT/Sources/Stash/Resources/Sounds/copy.wav" "$APP/Contents/Resources/Sounds/copy.wav"
cp "$ROOT/Sources/Stash/Resources/Sounds/paste.wav" "$APP/Contents/Resources/Sounds/paste.wav"
cp "$ROOT/Sources/Stash/Resources/Sounds/CREDITS.txt" "$APP/Contents/Resources/Sounds/CREDITS.txt"

# İmza kimliği seçimi. Bu bir kolaylık değil, izinlerin kalıcılığı meselesi:
# Erişilebilirlik izni imzaya bağlanır. Ad-hoc imzada bağlanacak sabit bir
# kimlik olmadığı için TCC CDHash'e düşer, o da her kod değişikliğinde değişir —
# yani her derlemeden sonra izni yeniden vermek gerekir. Gerçek bir sertifikayla
# imzalarsak kimlik sabit kalır ve izin derlemeler arasında yaşar.
#
# Sıra: elle verilen kimlik > makinedeki ilk geliştirici sertifikası > ad-hoc.
# Sertifikası olmayan biri (kaynaktan kuran çoğu kişi) yine ad-hoc'a düşer ve
# uygulama çalışır; sadece izni her güncellemede yeniden vermesi gerekir.
IDENTITY="${STASH_SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null \
        | awk -F'"' '/Apple Development|Developer ID Application/ {print $2; exit}')"
fi

if [ -n "$IDENTITY" ]; then
    echo "İmzalanıyor: $IDENTITY"
    codesign --force --sign "$IDENTITY" --timestamp=none "$APP"
else
    echo "İmzalanıyor: ad-hoc (sertifika bulunamadı — izinler her derlemede sıfırlanır)"
    codesign --force --sign - --timestamp=none "$APP"
fi

echo "Built $APP"
