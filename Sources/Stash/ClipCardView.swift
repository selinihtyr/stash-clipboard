import Store
import SwiftUI

struct ClipCardView: View {
    let clip: Clip
    let isSelected: Bool

    private var typeLabel: String {
        switch clip.kind {
        case .text: return "METİN"
        case .image: return "GÖRSEL"
        case .link: return "BAĞLANTI"
        case .file: return "DOSYA"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(typeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .kerning(0.6)
                    .foregroundStyle(Theme.label)
                Spacer()
                if clip.pinned {
                    Image(systemName: "pin.fill").font(.system(size: 9))
                        .foregroundStyle(Theme.accent)
                }
            }
            content
            if let source = clip.sourceName {
                Text(source)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.label.opacity(0.8))
                    .lineLimit(1)
            }
        }
        .padding(12)
        .frame(width: Theme.cardWidth,
               height: isSelected ? Theme.cardHeightSelected : Theme.cardHeight,
               alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 11)
                .fill(isSelected ? Theme.cardFillSelected : Theme.cardFill))
        .overlay(
            RoundedRectangle(cornerRadius: 11)
                .stroke(isSelected ? Theme.cardStrokeSelected : Theme.cardStroke, lineWidth: 1))
        .shadow(color: .black.opacity(isSelected ? 0.4 : 0), radius: 10, y: 6)
        .animation(.easeOut(duration: 0.12), value: isSelected)
    }

    @ViewBuilder private var content: some View {
        if clip.kind == .image {
            if let path = clip.imagePath, let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
            } else {
                // Budanmış veya kayıp görsel: kart yalan söylemesin.
                Text("görsel artık saklanmıyor")
                    .font(.system(size: 11)).foregroundStyle(Theme.label)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } else {
            Text(clip.text ?? "")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.body)
                .lineLimit(6)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
