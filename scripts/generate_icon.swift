#!/usr/bin/env swift
//
// Stash'in uygulama simgesini üretir. Bir görsel aracı yerine kod olarak
// tutuyoruz ki Theme.swift'teki palet değişince simge de aynı kaynaktan
// yeniden üretilebilsin — elde tutulan bir PNG'nin gerçekten hangi
// renklerden geldiğini kimse hatırlamak zorunda kalmaz.
//
// Ürün, tek başına bir simgeye indirgenecekse "üst üste kartlar"dan başka
// bir şey değil (bkz. StripView'daki gerçek kartlar) — o yüzden burada da
// tam olarak o motifi çiziyoruz: arkada soluk/hatlı bir kart, önde dolu
// accent mor bir kart. Tek bir S harfi ya da jenerik pano glifi yok; ikisi
// de bu uygulamaya özgü hiçbir şey söylemiyor.
//
// 16×16'da okunabilirlik asıl kısıt olduğu için sahne değil, tek bir güçlü
// silüet (iki kart) çiziliyor; boyuttan bağımsız aynı çizim kodu her
// piksel boyutunda tekrar çalıştırılıyor, büyük boyutlarda ekstra detay
// eklenmiyor — büyükte iyi görünüp küçükte bulanıklaşan bir tasarımdan
// kaçınmanın tek yolu bu.
//
// Kullanım: scripts/generate_icon.sh çağırır; tek başına da çalışır:
//   swift scripts/generate_icon.swift [çıktı-iconset-dizini]

import AppKit
import Foundation

// Theme.swift'teki sabitlerle birebir aynı: yeni bir renk icat etmiyoruz,
// SwiftUI.Color'ın burada erişimi olmayan aynı hex değerlerini NSColor
// olarak tekrar tanımlıyoruz.
enum Palette {
    static let panelTop = NSColor(calibratedRed: 0x3A / 255.0, green: 0x2D / 255.0,
                                  blue: 0x50 / 255.0, alpha: 1)
    static let panelBottom = NSColor(calibratedRed: 0x21 / 255.0, green: 0x1D / 255.0,
                                     blue: 0x2D / 255.0, alpha: 1)
    static let accent = NSColor(calibratedRed: 0xA0 / 255.0, green: 0x6C / 255.0,
                                blue: 0xF5 / 255.0, alpha: 1)
}

struct IconSpec { let name: String; let pixels: Int }

// macOS'in .icns içinde istediği tam set: 16/32/128/256/512, her biri 1× ve
// 2×. Bazı dosya adları piksel olarak birbirinin aynısı (16@2x == 32) ama
// iconutil ayrı adlandırılmış dosyalar bekliyor.
let specs: [IconSpec] = [
    IconSpec(name: "icon_16x16", pixels: 16),
    IconSpec(name: "icon_16x16@2x", pixels: 32),
    IconSpec(name: "icon_32x32", pixels: 32),
    IconSpec(name: "icon_32x32@2x", pixels: 64),
    IconSpec(name: "icon_128x128", pixels: 128),
    IconSpec(name: "icon_128x128@2x", pixels: 256),
    IconSpec(name: "icon_256x256", pixels: 256),
    IconSpec(name: "icon_256x256@2x", pixels: 512),
    IconSpec(name: "icon_512x512", pixels: 512),
    IconSpec(name: "icon_512x512@2x", pixels: 1024),
]

func draw(size: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                               bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                               isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let s = CGFloat(size)

    // Bu düz bir .icns — bir asset catalog / Icon Composer belgesi değil —
    // yani sistem üzerine kendi köşe yuvarlaklığını ve gölgesini
    // uygulamıyor. İkisini de burada elle çiziyoruz, klasik macOS simge
    // kuralına uyarak: kenara kadar dolu bir tuval değil, dolgulu bir
    // döşeme.
    context.cgContext.clear(CGRect(x: 0, y: 0, width: s, height: s))

    let margin = s * 0.06
    let tileRect = CGRect(x: margin, y: margin, width: s - margin * 2, height: s - margin * 2)
    let tileRadius = tileRect.width * 0.22
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: tileRadius, yRadius: tileRadius)

    context.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.012)
    shadow.shadowBlurRadius = s * 0.02
    shadow.set()
    let gradient = NSGradient(starting: Palette.panelTop, ending: Palette.panelBottom)!
    gradient.draw(in: tilePath, angle: -45)
    context.restoreGraphicsState()

    // StripView'ın gerçek panelindeki üst kenar aydınlığını tekrarlıyor —
    // aynı yüzeyin parçası olduğunu, jenerik bir mor kare olmadığını
    // hissettirsin.
    context.saveGraphicsState()
    tilePath.addClip()
    let highlightRect = CGRect(x: tileRect.minX, y: tileRect.maxY - s * 0.012,
                               width: tileRect.width, height: s * 0.012)
    NSColor.white.withAlphaComponent(0.16).setFill()
    NSBezierPath(rect: highlightRect).fill()
    context.restoreGraphicsState()

    // Motif: iki üst üste kart. Arkadaki soluk dolgulu + belirgin hatlı
    // (Theme.cardFill/cardStroke'un aynısı değil ama aynı ailede — koyu
    // döşeme üstünde 16px'te seçilsin diye biraz daha opak), öndeki dolu
    // accent mor. Üçüncü bir kart eklemedik: 16×16'da üçüncü kenar
    // silüeti değil, bulanıklık üretir.
    let cardWidth = tileRect.width * 0.46
    let cardHeight = cardWidth / 0.8
    let cardRadius = cardWidth * 0.16
    let offset = cardWidth * 0.24

    func cardPath(dx: CGFloat, dy: CGFloat) -> NSBezierPath {
        let rect = CGRect(x: tileRect.midX + dx - cardWidth / 2,
                          y: tileRect.midY + dy - cardHeight / 2,
                          width: cardWidth, height: cardHeight)
        return NSBezierPath(roundedRect: rect, xRadius: cardRadius, yRadius: cardRadius)
    }

    let back = cardPath(dx: offset, dy: offset)
    NSColor.white.withAlphaComponent(0.18).setFill()
    back.fill()
    NSColor.white.withAlphaComponent(0.42).setStroke()
    back.lineWidth = max(1, s * 0.008)
    back.stroke()

    let front = cardPath(dx: -offset, dy: -offset)
    Palette.accent.setFill()
    front.fill()

    NSGraphicsContext.current = nil
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let arguments = CommandLine.arguments
let outputPath = arguments.count > 1 ? arguments[1] : "build/AppIcon.iconset"
let outputURL = URL(fileURLWithPath: outputPath)
try? FileManager.default.removeItem(at: outputURL)
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

for spec in specs {
    let rep = draw(size: spec.pixels)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("PNG üretilemedi: \(spec.name)\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: outputURL.appendingPathComponent("\(spec.name).png"))
}

print("iconset yazıldı: \(outputURL.path)")
