import Foundation

/// How well the app can convert text to/from a given layout.
enum LayoutSupport: String, Codable {
    /// Explicit character-level mapping exists. Full accuracy for letters and punctuation.
    case full
    /// Layout uses QWERTY letter positions (auto-detected via UCKeyTranslate).
    /// Letters convert with full accuracy; punctuation mapping may be imprecise.
    case qwerty
    /// Non-QWERTY layout with no mapping. Cannot convert.
    case none
}

/// Identifies a single macOS keyboard input source for display and persistence.
struct LayoutInfo: Codable, Equatable, Identifiable, Hashable {
    /// TIS source ID, e.g. "com.apple.keylayout.US"
    let id: String
    /// Display name returned by macOS, e.g. "U.S."
    let name: String
    /// Country flag emoji derived from the source's primary language.
    let flag: String

    static func flag(for languages: [String], sourceID: String = "") -> String {
        let lang = languages.first?.lowercased() ?? ""
        switch true {
        case lang.hasPrefix("en"):
            return sourceID.contains("British") || sourceID.contains("UK") ? "🇬🇧" : "🇺🇸"
        case lang.hasPrefix("ru"): return "🇷🇺"
        case lang.hasPrefix("de"): return "🇩🇪"
        case lang.hasPrefix("fr"): return "🇫🇷"
        case lang.hasPrefix("uk"): return "🇺🇦"
        case lang.hasPrefix("zh"): return "🇨🇳"
        case lang.hasPrefix("ja"): return "🇯🇵"
        case lang.hasPrefix("ko"): return "🇰🇷"
        case lang.hasPrefix("es"): return "🇪🇸"
        case lang.hasPrefix("it"): return "🇮🇹"
        case lang.hasPrefix("pl"): return "🇵🇱"
        case lang.hasPrefix("tr"): return "🇹🇷"
        case lang.hasPrefix("ar"): return "🇸🇦"
        case lang.hasPrefix("hi"): return "🇮🇳"
        case lang.hasPrefix("pt"): return "🇧🇷"
        case lang.hasPrefix("nl"): return "🇳🇱"
        case lang.hasPrefix("cs"): return "🇨🇿"
        case lang.hasPrefix("he"): return "🇮🇱"
        case lang.hasPrefix("sv"): return "🇸🇪"
        case lang.hasPrefix("nb"), lang.hasPrefix("no"): return "🇳🇴"
        case lang.hasPrefix("fi"): return "🇫🇮"
        case lang.hasPrefix("da"): return "🇩🇰"
        case lang.hasPrefix("hu"): return "🇭🇺"
        case lang.hasPrefix("ro"): return "🇷🇴"
        case lang.hasPrefix("sk"): return "🇸🇰"
        case lang.hasPrefix("hr"): return "🇭🇷"
        case lang.hasPrefix("sl"): return "🇸🇮"
        case lang.hasPrefix("et"): return "🇪🇪"
        case lang.hasPrefix("lv"): return "🇱🇻"
        case lang.hasPrefix("lt"): return "🇱🇹"
        case lang.hasPrefix("el"): return "🇬🇷"
        case lang.hasPrefix("th"): return "🇹🇭"
        case lang.hasPrefix("vi"): return "🇻🇳"
        case lang.hasPrefix("id"), lang.hasPrefix("ms"): return "🇮🇩"
        case lang.hasPrefix("ca"): return "🏴󠁥󠁳󠁣󠁴󠁿"
        case lang.hasPrefix("is"): return "🇮🇸"
        default:                   return "🌐"
        }
    }
}
