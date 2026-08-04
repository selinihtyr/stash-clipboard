#!/usr/bin/env bash
# generate_icon.swift'in çizdiği PNG'leri iconutil ile tek bir .icns'e
# derler ve uygulama hedefinin okuduğu yere kopyalar. Ayrı bir adım: PNG
# üretimi salt Swift/AppKit, .icns derlemesi ise sisteme özgü bir CLI aracı
# (iconutil) — ikisini aynı script'e karıştırmak PNG üretiminin
# test edilebilirliğini (ya da başka platformlarda yeniden kullanımını)
# gereksiz yere iconutil'e bağlar.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICONSET="$ROOT/build/AppIcon.iconset"
ICNS_OUT="$ROOT/build/AppIcon.icns"
DEST="$ROOT/Sources/Stash/AppIcon.icns"

swift "$ROOT/scripts/generate_icon.swift" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$ICNS_OUT"
cp "$ICNS_OUT" "$DEST"

echo "Yazıldı: $DEST"
