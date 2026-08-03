import Foundation

public enum PasteFilter: String, CaseIterable, Sendable, Codable {
    case plainText
    case collapseWhitespace
    case straightenQuotes
}

/// Filtreleri verilen sırayla uygular. Sıra anlamlıdır: bir filtrenin çıktısı
/// bir sonrakinin girdisidir ve kullanıcı ayarlarda sırayı değiştirebilir.
public func apply(_ filters: [PasteFilter], to text: String) -> String {
    filters.reduce(text) { partial, filter in
        switch filter {
        case .plainText:
            return partial
        case .collapseWhitespace:
            return partial
                .components(separatedBy: .whitespacesAndNewlines)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .straightenQuotes:
            var out = partial
            for (curly, straight) in [("\u{201C}", "\""), ("\u{201D}", "\""),
                                      ("\u{2018}", "'"), ("\u{2019}", "'")] {
                out = out.replacingOccurrences(of: curly, with: straight)
            }
            return out
        }
    }
}
