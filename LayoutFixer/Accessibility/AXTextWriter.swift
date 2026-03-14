import ApplicationServices

struct AXTextWriter {
    private let reader = AXTextReader()

    /// Selects the given UTF-16 range in element via kAXSelectedTextRangeAttribute.
    /// Returns true if the AX set call succeeded.
    /// In webview-based inputs this also updates the DOM selection, enabling subsequent
    /// typeText() calls to replace exactly the right span of text.
    func selectRange(_ range: CFRange, in element: AXUIElement) -> Bool {
        var r = range
        guard let axRange = AXValueCreate(.cfRange, &r) else { return false }
        return AXUIElementSetAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, axRange
        ) == .success
    }

    /// Replaces the given UTF-16 range with convertedText via a full kAXValueAttribute write.
    /// NOTE: in Chromium-based webview panels this updates the AX tree but NOT the visible DOM.
    /// Prefer selectRange() + caller-side typeText() for those environments.
    /// Returns true on success.
    func write(convertedText: String, replacing range: CFRange, in element: AXUIElement) -> Bool {
        guard let fullText = reader.fullText(of: element) else { return false }

        let utf16 = fullText.utf16
        guard range.location >= 0,
              range.location + range.length <= utf16.count else { return false }

        let startIdx = utf16.index(utf16.startIndex, offsetBy: range.location)
        let endIdx = utf16.index(startIdx, offsetBy: range.length)

        var newText = String(utf16[..<startIdx])!
        newText += convertedText
        newText += String(utf16[endIdx...])!

        return AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        ) == .success
    }

    /// Sets cursor (or selection) after a write.
    /// Call this after an async yield to avoid being overridden by the host app's
    /// internal async cursor reset that follows a kAXValueAttribute write.
    func positionCursor(after convertedText: String, replacing range: CFRange,
                        in element: AXUIElement, selectResult: Bool) {
        // selectResult=true  → keep the converted text selected (user had a selection)
        // selectResult=false → place cursor at end of replacement (lastWord path)
        var newRange = selectResult
            ? CFRange(location: range.location, length: convertedText.utf16.count)
            : CFRange(location: range.location + convertedText.utf16.count, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }
    }
}
