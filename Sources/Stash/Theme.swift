import SwiftUI

enum Theme {
    static let panelTop = Color(red: 0x3A/255, green: 0x2D/255, blue: 0x50/255)
    static let panelBottom = Color(red: 0x21/255, green: 0x1D/255, blue: 0x2D/255)
    static let accent = Color(red: 0xA0/255, green: 0x6C/255, blue: 0xF5/255)
    static let cardFill = Color.white.opacity(0.08)
    static let cardStroke = Color.white.opacity(0.11)
    static let cardFillSelected = Color.white.opacity(0.17)
    static let cardStrokeSelected = Color.white.opacity(0.45)
    static let label = Color(red: 0xA9/255, green: 0x9F/255, blue: 0xC0/255)
    static let body = Color(red: 0xCD/255, green: 0xC6/255, blue: 0xDC/255)

    static let cardWidth: CGFloat = 162
    static let cardHeight: CGFloat = 200
    static let cardHeightSelected: CGFloat = 224

    // Şeridin iç ölçüleri. StripView bunları birebir kullanıyor; burada tek
    // yerde durmalarının sebebi aşağıdaki stripHeight.
    static let headerHeight: CGFloat = 26
    static let headerTopPadding: CGFloat = 17
    static let contentSpacing: CGFloat = 14
    static let stripBottomPadding: CGFloat = 22

    /// Şerit yüksekliği TÜRETİLİR, sabit değil.
    ///
    /// Daha önce 300 yazıyordu ve tasarımla uyumluydu — ta ki başlığa arama
    /// alanı eklenene kadar. Başlık 26px büyüdü, toplam 303'e çıktı ve seçili
    /// kart panelin dışına taşıp kırpıldı; kimse fark etmedi çünkü sayı
    /// bağımsızdı. Türetince başlık ya da kart ölçüsü değişse de şerit
    /// kendini ayarlar.
    static var stripHeight: CGFloat {
        headerTopPadding + headerHeight + contentSpacing
            + cardHeightSelected + stripBottomPadding
    }
}
