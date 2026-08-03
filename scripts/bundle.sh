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

# Ad-hoc imza: geliştirici sertifikası olmadan uygulamayı çalıştırılabilir
# kılan tek yol bu. Ama TCC izni imzanın CDHash'ine bağlanır ve kaynak
# değişince hash de değişir — yani her kod değişikliğinden sonra
# Erişilebilirlik izni yeniden onaylanmalı. Bunu ortadan kaldırmak istersen
# gerçek çözüm sabit bir self-signed geliştirici sertifikasıdır (`--sign -`
# yerine); bu script'in işi değil.
codesign --force --sign - --timestamp=none "$APP"

echo "Built $APP"
