import ApplicationServices

struct AXTextReader {
    func focusedElement() -> AXUIElement? {
        let systemWide = AXUIElementCreateSystemWide()
        var focusedApp: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedApplicationAttribute as CFString,
            &focusedApp
        ) == .success, let app = focusedApp else { return nil }

        var focusedElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            app as! AXUIElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        ) == .success else { return nil }

        return (focusedElement as! AXUIElement)
    }

    func fullText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXValueAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    func selectionRange(of element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        ) == .success, let axValue = value else { return nil }

        var range = CFRange()
        guard AXValueGetValue(axValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    func selectedText(of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &value
        ) == .success else { return nil }
        return value as? String
    }

    func lastWord(of element: AXUIElement) -> (text: String, range: CFRange)? {
        guard let fullText = fullText(of: element),
              let selRange = selectionRange(of: element),
              selRange.length == 0 else { return nil }

        let caretLocation = selRange.location
        guard caretLocation > 0 else { return nil }

        let chars = Array(fullText.utf16)
        guard caretLocation <= chars.count else { return nil }

        var wordStart = caretLocation
        var idx = caretLocation - 1
        while idx >= 0 {
            let ch = chars[idx]
            // space, tab, newline, carriage return
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                break
            }
            wordStart = idx
            if idx == 0 { break }
            idx -= 1
        }

        let wordLength = caretLocation - wordStart
        guard wordLength > 0 else { return nil }

        let range = CFRange(location: wordStart, length: wordLength)
        let start = fullText.utf16.index(fullText.utf16.startIndex, offsetBy: wordStart)
        let end = fullText.utf16.index(start, offsetBy: wordLength)
        let word = String(fullText.utf16[start..<end]) ?? ""
        guard !word.isEmpty else { return nil }

        return (word, range)
    }
}
