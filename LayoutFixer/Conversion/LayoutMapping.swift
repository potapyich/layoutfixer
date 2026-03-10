/// Physical QWERTY key → target layout character mappings.
///
/// All mappings use **US QWERTY as the universal intermediate**.
/// Converting between any two layouts is done in two steps:
///   source → QWERTY (layoutToQwerty)   then   QWERTY → target (qwertyToLayout)
///
/// # Supported layouts
///
/// | Layout        | TIS ID pattern                           | Notes                              |
/// |---------------|------------------------------------------|------------------------------------|
/// | EN (base)     | keylayout.US, ABC, British, …           | Identity — no mapping needed       |
/// | RU Russian    | keylayout.Russian, Russian-PC, …        | Full 66+ pair mapping              |
/// | DE German     | keylayout.German                         | QWERTZ y/z swap + umlauts         |
/// | FR French     | keylayout.French, French-PC              | AZERTY q/a w/z swaps + accents    |
/// | ES Spanish    | keylayout.Spanish, Spanish-ISO           | QWERTY + ñ at ; key               |
/// | IT Italian    | keylayout.Italian, Italian-Pro           | QWERTY + accented vowels           |
/// | PT Portuguese | keylayout.Portuguese, PortugueseBrazilian| QWERTY + ç at ; key               |
/// | SV Swedish    | keylayout.Swedish, Swedish-Pro           | QWERTY + å ä ö at right side      |
/// | FI Finnish    | keylayout.Finnish, Finnish-Extended      | Identical to Swedish               |
/// | NO Norwegian  | keylayout.Norwegian, NorwegianExtended   | QWERTY + å ø æ at right side      |
/// | DA Danish     | keylayout.Danish                         | QWERTY + å æ ø at right side      |
///
/// # Number-row mappings
/// French AZERTY uses unshifted number keys for accented chars (&, é, ", etc.).
/// These are intentionally excluded because mapping digits/common symbols would
/// cause false conversions of legitimate digit characters in text.
///
/// # Dead keys
/// Layouts that use dead-accent keys (Spanish ´, Portuguese ~, etc.) are partially
/// supported. The dead key character itself is mapped; composed characters (á, ã, …)
/// produced by dead key + vowel sequences cannot be mapped via this approach.

enum LayoutMapping {

    // =========================================================================
    // MARK: - Russian
    // =========================================================================

    static let qwertyToRu: [Character: Character] = [
        "q": "й", "w": "ц", "e": "у", "r": "к", "t": "е",
        "y": "н", "u": "г", "i": "ш", "o": "щ", "p": "з",
        "[": "х", "]": "ъ",
        "a": "ф", "s": "ы", "d": "в", "f": "а", "g": "п",
        "h": "р", "j": "о", "k": "л", "l": "д", ";": "ж",
        "'": "э",
        "z": "я", "x": "ч", "c": "с", "v": "м", "b": "и",
        "n": "т", "m": "ь", ",": "б", ".": "ю", "/": ".",
        // Uppercase
        "Q": "Й", "W": "Ц", "E": "У", "R": "К", "T": "Е",
        "Y": "Н", "U": "Г", "I": "Ш", "O": "Щ", "P": "З",
        "{": "Х", "}": "Ъ",
        "A": "Ф", "S": "Ы", "D": "В", "F": "А", "G": "П",
        "H": "Р", "J": "О", "K": "Л", "L": "Д", ":": "Ж",
        "\"": "Э",
        "Z": "Я", "X": "Ч", "C": "С", "V": "М", "B": "И",
        "N": "Т", "M": "Ь", "<": "Б", ">": "Ю", "?": ",",
    ]

    // =========================================================================
    // MARK: - German QWERTZ
    // =========================================================================

    /// Physical QWERTY key positions → German QWERTZ characters.
    /// Main changes: y↔z swap; umlauts ä ö ü at right-side punctuation keys.
    static let qwertyToDe: [Character: Character] = [
        "y": "z",  "Y": "Z",
        "z": "y",  "Z": "Y",
        ";": "ö",  ":": "Ö",
        "'": "ä",  "\"": "Ä",
        "[": "ü",  "{": "Ü",
        "-": "ß",
        "/": "-",  "?": "_",
        "]": "+",  "}": "*",
        "\\": "#", "|": "°",
    ]

    // =========================================================================
    // MARK: - French AZERTY
    // =========================================================================

    /// Physical QWERTY key positions → French AZERTY characters.
    /// Main changes: q↔a and w↔z letter swaps; m moved to ; key;
    /// punctuation row reordered (, ; : ! at m , . / positions).
    /// Number row excluded to avoid false conversion of digit characters.
    static let qwertyToFr: [Character: Character] = [
        // Letter swaps
        "q": "a",  "Q": "A",
        "a": "q",  "A": "Q",
        "w": "z",  "W": "Z",
        "z": "w",  "Z": "W",
        // Home row right side: ; → m, ' → ù
        ";": "m",  ":": "M",
        "'": "ù",  "\"": "%",
        // Bottom row right side: m → ,  , → ;  . → :  / → !
        "m": ",",  "M": "?",
        ",": ";",  "<": ".",
        ".": ":",  ">": "/",
        "/": "!",  "?": "§",
        // Bracket row
        "[": "^",  "{": "¨",
        "]": "$",  "}": "£",
        "\\": "*", "|": "µ",
    ]

    // =========================================================================
    // MARK: - Spanish
    // =========================================================================

    /// Physical QWERTY key positions → Spanish ISO characters.
    /// QWERTY letter arrangement is kept. Main addition: ñ at ; key.
    /// Dead-key sequences (´ + vowel → á) are not mappable via this approach.
    static let qwertyToEs: [Character: Character] = [
        ";": "ñ",  ":": "Ñ",
        "'": "´",  "\"": "¨",  // dead acute / diaeresis
        "[": "`",  "{": "^",
        "]": "+",  "}": "*",
        "\\": "ç", "|": "Ç",
        "`": "\\", "~": "|",
    ]

    // =========================================================================
    // MARK: - Italian
    // =========================================================================

    /// Physical QWERTY key positions → Italian keyboard characters.
    /// QWERTY letter arrangement is kept. Right-side keys carry accented vowels.
    static let qwertyToIt: [Character: Character] = [
        "[": "è",  "{": "é",
        "]": "+",  "}": "*",
        ";": "ò",  ":": "ç",
        "'": "à",  "\"": "°",
        "\\": "ù", "|": "§",
        "/": "-",  "?": "_",
        "`": "\\", "~": "|",
    ]

    // =========================================================================
    // MARK: - Portuguese (Brazil & Europe)
    // =========================================================================

    /// Physical QWERTY key positions → Portuguese keyboard characters.
    /// QWERTY letter arrangement is kept. Main addition: ç at ; key.
    static let qwertyToPt: [Character: Character] = [
        ";": "ç",  ":": "Ç",
        "'": "´",  "\"": "¨",  // dead acute / diaeresis
        "[": "~",  "{": "`",   // dead tilde (for ã õ) / dead grave — NOT "´" (would duplicate above)
        "]": "[",  "}": "{",
        "\\": "]", "|": "}",
        "/": ";",  "?": ":",
    ]

    // =========================================================================
    // MARK: - Nordic layouts (Swedish / Finnish / Norwegian / Danish)
    // =========================================================================

    /// Physical QWERTY key positions → Swedish characters.
    /// QWERTY letter arrangement is kept. Right side: å ä ö.
    /// Finnish keyboard is identical to Swedish.
    static let qwertyToSv: [Character: Character] = [
        "[": "å",  "{": "Å",
        ";": "ö",  ":": "Ö",
        "'": "ä",  "\"": "Ä",
        "]": "¨",  "}": "^",   // dead diaeresis / circumflex
        "\\": "'", "|": "*",
    ]

    /// Physical QWERTY key positions → Norwegian characters.
    /// QWERTY letter arrangement is kept. Right side: å ø æ.
    static let qwertyToNo: [Character: Character] = [
        "[": "å",  "{": "Å",
        ";": "ø",  ":": "Ø",
        "'": "æ",  "\"": "Æ",
        "]": "¨",  "}": "^",
        "\\": "@", "|": "*",
    ]

    /// Physical QWERTY key positions → Danish characters.
    /// QWERTY letter arrangement is kept. Right side: å æ ø.
    static let qwertyToDa: [Character: Character] = [
        "[": "å",  "{": "Å",
        ";": "æ",  ":": "Æ",
        "'": "ø",  "\"": "Ø",
        "]": "¨",  "}": "^",
        "\\": "'", "|": "*",
    ]

    // =========================================================================
    // MARK: - Auto-generated inverses
    // =========================================================================

    static let ruToQwerty: [Character: Character] = inverse(of: qwertyToRu)
    static let deToQwerty: [Character: Character] = inverse(of: qwertyToDe)
    static let frToQwerty: [Character: Character] = inverse(of: qwertyToFr)
    static let esToQwerty: [Character: Character] = inverse(of: qwertyToEs)
    static let itToQwerty: [Character: Character] = inverse(of: qwertyToIt)
    static let ptToQwerty: [Character: Character] = inverse(of: qwertyToPt)
    static let svToQwerty: [Character: Character] = inverse(of: qwertyToSv)
    static let noToQwerty: [Character: Character] = inverse(of: qwertyToNo)
    static let daToQwerty: [Character: Character] = inverse(of: qwertyToDa)

    /// Builds the inverse of a layout mapping.
    /// When two QWERTY keys map to the same target character (e.g. two dead-accent
    /// keys that visually look the same), the first encountered wins and no crash occurs.
    private static func inverse(of map: [Character: Character]) -> [Character: Character] {
        Dictionary(map.map { ($0.value, $0.key) }, uniquingKeysWith: { first, _ in first })
    }

    // =========================================================================
    // MARK: - Multi-layout registry
    // =========================================================================
    //
    // Maps TIS source ID → character table for that layout.
    // US QWERTY and its variants are the base (identity) and are NOT listed here.
    // An absent ID means "treat as QWERTY" (identity mapping).
    //
    // Pattern keys are checked via String.contains(); add all known variant IDs.

    static let qwertyToLayout: [String: [Character: Character]] = {
        var m: [String: [Character: Character]] = [:]
        // Russian
        for id in ["Russian", "Russian-PC", "RussianWin"] { m[id] = qwertyToRu }
        // Ukrainian (uses same Cyrillic positions as Russian on macOS)
        for id in ["Ukrainian", "Ukrainian-PC"] { m[id] = qwertyToRu }
        // German
        for id in ["German", "German-DIN"] { m[id] = qwertyToDe }
        // French
        for id in ["French", "French-PC", "French-Numerical"] { m[id] = qwertyToFr }
        // Spanish
        for id in ["Spanish", "Spanish-ISO", "Spanish-Latin"] { m[id] = qwertyToEs }
        // Italian
        for id in ["Italian", "Italian-Pro"] { m[id] = qwertyToIt }
        // Portuguese
        for id in ["Portuguese", "PortugueseBrazilian", "PortugueseISO"] { m[id] = qwertyToPt }
        // Swedish / Finnish (identical layout)
        for id in ["Swedish", "Swedish-Pro", "Finnish", "Finnish-Extended",
                   "Finnish-Sami"] { m[id] = qwertyToSv }
        // Norwegian
        for id in ["Norwegian", "NorwegianExtended", "NorwegianSami"] { m[id] = qwertyToNo }
        // Danish
        for id in ["Danish"] { m[id] = qwertyToDa }
        return m
    }()

    static let layoutToQwerty: [String: [Character: Character]] = {
        var m: [String: [Character: Character]] = [:]
        for id in ["Russian", "Russian-PC", "RussianWin"]       { m[id] = ruToQwerty }
        for id in ["Ukrainian", "Ukrainian-PC"]                  { m[id] = ruToQwerty }
        for id in ["German", "German-DIN"]                      { m[id] = deToQwerty }
        for id in ["French", "French-PC", "French-Numerical"]   { m[id] = frToQwerty }
        for id in ["Spanish", "Spanish-ISO", "Spanish-Latin"]   { m[id] = esToQwerty }
        for id in ["Italian", "Italian-Pro"]                     { m[id] = itToQwerty }
        for id in ["Portuguese", "PortugueseBrazilian", "PortugueseISO"] { m[id] = ptToQwerty }
        for id in ["Swedish", "Swedish-Pro", "Finnish", "Finnish-Extended",
                   "Finnish-Sami"]                              { m[id] = svToQwerty }
        for id in ["Norwegian", "NorwegianExtended", "NorwegianSami"] { m[id] = noToQwerty }
        for id in ["Danish"]                                     { m[id] = daToQwerty }
        return m
    }()

    // =========================================================================
    // MARK: - Lookup helpers
    // =========================================================================

    /// Mapping table from QWERTY → `layoutID`, matched by substring.
    static func qwertyMap(for layoutID: String) -> [Character: Character]? {
        qwertyToLayout.first(where: { layoutID.contains($0.key) })?.value
    }

    /// Mapping table from `layoutID` → QWERTY, matched by substring.
    static func toQwertyMap(for layoutID: String) -> [Character: Character]? {
        layoutToQwerty.first(where: { layoutID.contains($0.key) })?.value
    }

    /// True if an explicit character-level mapping table exists for this layout ID.
    static func hasExplicitMapping(for layoutID: String) -> Bool {
        qwertyToLayout.keys.contains(where: { layoutID.contains($0) })
    }

    /// True if the layout has a known full mapping (explicit OR QWERTY base).
    /// For the full three-tier check including runtime QWERTY detection, use
    /// `InputSourceManager.shared.support(for:)`.
    static func hasMapping(for layoutID: String) -> Bool {
        isQwertyBase(layoutID) || hasExplicitMapping(for: layoutID)
    }

    /// English/QWERTY-family layouts — they are the conversion base (identity).
    static func isQwertyBase(_ id: String) -> Bool {
        ["US", "ABC", "British", "Australian", "Canadian",
         "QWERTY", "Dvorak", "Colemak"].contains(where: { id.contains($0) })
    }
}
