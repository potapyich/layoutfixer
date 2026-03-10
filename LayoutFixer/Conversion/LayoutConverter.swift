struct LayoutConverter {

    // MARK: - Generic conversion between any two layout IDs

    /// Converts `text` typed in `sourceID` layout into `targetID` layout.
    ///
    /// Uses QWERTY as the universal intermediate:
    ///   source → QWERTY → target
    ///
    /// Lookup is substring-based so "com.apple.keylayout.Russian-PC" matches
    /// the "Russian-PC" entry. If a layout has no entry it is treated as QWERTY
    /// (identity), which is correct for all EN/QWERTY variants.
    func convert(_ text: String, from sourceID: String, to targetID: String) -> String {
        let toQwerty   = LayoutMapping.toQwertyMap(for: sourceID)  ?? [:]  // source → QWERTY
        let fromQwerty = LayoutMapping.qwertyMap(for: targetID)    ?? [:]  // QWERTY → target
        return String(text.map { ch in
            let q = toQwerty[ch] ?? ch
            return fromQwerty[q] ?? q
        })
    }

    // MARK: - Legacy interface (kept for unit tests)

    func convert(_ text: String, direction: ConversionDirection) -> String {
        let map = direction == .enToRu ? LayoutMapping.qwertyToRu : LayoutMapping.ruToQwerty
        return String(text.map { map[$0] ?? $0 })
    }
}
