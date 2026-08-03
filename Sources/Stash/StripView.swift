import StashCore
import SwiftUI

struct StripView: View {
    @ObservedObject var model: StripModel
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    // LazyHStack, brief'teki düz HStack yerine: StripModel 300
                    // klibe kadar yüklüyor, düz HStack tümünü anında kurar —
                    // her görsel kart NSImage(contentsOfFile:) ile tam boyutlu
                    // bir ekran görüntüsünü senkron çözer. Panel her açılışta
                    // anında hissetmeli; LazyHStack sadece görünüm alanına
                    // yakın kartları kurar.
                    LazyHStack(alignment: .bottom, spacing: 14) {
                        ForEach(Array(model.visible.enumerated()), id: \.element.id) { index, clip in
                            ClipCardView(clip: clip, isSelected: index == model.selectedIndex)
                                .id(clip.id)
                                .onTapGesture { model.select(index: index) }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.bottom, 22)
                }
                .onChange(of: model.selectedIndex) { _, new in
                    guard model.visible.indices.contains(new) else { return }
                    withAnimation(.easeOut(duration: 0.15)) {
                        proxy.scrollTo(model.visible[new].id, anchor: .center)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            LinearGradient(colors: [Theme.panelTop, Theme.panelBottom],
                           startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .top) {
            Rectangle().fill(Color.white.opacity(0.16)).frame(height: 1)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 16, topTrailingRadius: 16))
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Stash").font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white).kerning(0.5)
            if !model.query.isEmpty {
                Text(model.query)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.accent)
            }
            Spacer()
            if model.visible.isEmpty {
                Text(model.query.isEmpty
                     ? "Henüz bir şey kopyalamadın."
                     : "Eşleşen kart yok.")
                    .font(.system(size: 12)).foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 17)
    }
}
