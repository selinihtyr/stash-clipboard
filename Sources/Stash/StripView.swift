import StashCore
import SwiftUI

struct StripView: View {
    @ObservedObject var model: StripModel

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.contentSpacing) {
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
                    .padding(.bottom, Theme.stripBottomPadding)
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
            ForEach(tabs, id: \.self) { entry in
                Text(entry.title)
                    .font(.system(size: 12))
                    .padding(.horizontal, 13).padding(.vertical, 4)
                    .background(Capsule().fill(model.tab == entry.tab
                                               ? Theme.accent : Color.white.opacity(0.1)))
                    .foregroundStyle(model.tab == entry.tab ? .white : Theme.body)
                    .onTapGesture {
                        model.tab = entry.tab
                        try? model.reload()
                    }
            }
            searchField
            Spacer()
            if model.visible.isEmpty {
                Text(model.query.isEmpty
                     ? "Henüz bir şey kopyalamadın."
                     : "Eşleşen kart yok.")
                    .font(.system(size: 12)).foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, Theme.headerTopPadding)
    }

    // Odağı buraya taşıyan gerçek bir NSTextField yok: yakalama klavye
    // olaylarını panel seviyesinde (StripPanel.onKey) alıyor, bu görünüm
    // sadece o durumu yansıtıyor. Bu yüzden alan tıklanabilir/odaklanabilir
    // görünmemeli — kullanıcı tıklamadan yazmaya başladığını anlamalı, o
    // yüzden yer tutucu talimat değil davet gibi konuşuyor.
    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(model.query.isEmpty ? Theme.label : Theme.accent)
            if model.query.isEmpty {
                Text("yazmaya başla, arasın")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.label)
            } else {
                Text(model.query)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Theme.body)
                    .lineLimit(1)
                // Metin canlı bir giriş olduğunu belli etsin diye yanıp
                // sönen bir imleç: gerçek bir NSTextField olmadığından tek
                // "bu düzenlenebilir" sinyali bu.
                BlinkingCaret()
                Spacer(minLength: 4)
                // ⌫'nin bu metni sildiğini söylüyor: aksi halde kullanıcı
                // yanlış yazdığında geri almanın yolunu tahmin etmek zorunda
                // kalır.
                Image(systemName: "delete.left")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.label)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: Theme.headerHeight)
        // Genişlik sabit: boş/dolu arası geçişte şeridin geri kalanı
        // (sekmeler, boş durum metni) yer değiştirmesin diye.
        .frame(width: 210, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.cardFill))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.cardStroke))
    }

    struct TabEntry: Hashable { let title: String; let tab: StripTab }

    private var tabs: [TabEntry] {
        // İlk üçü sabit ve silinemez: raf değiller, kayıt üzerindeki alanlara
        // bakan süzgeçler.
        [TabEntry(title: "Tümü", tab: .all),
         TabEntry(title: "Sabitlenen", tab: .pinned),
         TabEntry(title: "Görseller", tab: .images)]
        + model.shelves.map { TabEntry(title: $0.name, tab: .shelf($0.id)) }
    }
}

/// Sabit bir NSTextField'ın imlecini taklit eder: aramanın yazı yazılabilir,
/// canlı bir alan olduğunu tek bakışta anlatan tek sinyal bu, çünkü altında
/// gerçek bir metin alanı yok (bkz. StripView.searchField üstündeki not).
private struct BlinkingCaret: View {
    @State private var visible = true

    var body: some View {
        Rectangle()
            .fill(Theme.accent)
            .frame(width: 1.5, height: 13)
            .opacity(visible ? 1 : 0)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.6).repeatForever(autoreverses: true)) {
                    visible.toggle()
                }
            }
    }
}
