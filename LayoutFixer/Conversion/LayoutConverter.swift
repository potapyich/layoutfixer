struct LayoutConverter {
    func convert(_ text: String, direction: ConversionDirection) -> String {
        let map = direction == .enToRu ? LayoutMapping.qwertyToRu : LayoutMapping.ruToQwerty
        return String(text.map { map[$0] ?? $0 })
    }
}
