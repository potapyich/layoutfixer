import ApplicationServices

struct AXTextWriter {
    private let reader = AXTextReader()

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

        let result = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            newText as CFTypeRef
        )

        guard result == .success else { return false }

        let newCaretLocation = range.location + convertedText.utf16.count
        var newRange = CFRange(location: newCaretLocation, length: 0)
        if let axRange = AXValueCreate(.cfRange, &newRange) {
            AXUIElementSetAttributeValue(
                element,
                kAXSelectedTextRangeAttribute as CFString,
                axRange
            )
        }

        return true
    }
}
