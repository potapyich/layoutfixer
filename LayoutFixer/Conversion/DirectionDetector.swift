enum ConversionDirection {
    case enToRu
    case ruToEn
}

struct DirectionDetector {
    func detectDirection(_ text: String) -> ConversionDirection? {
        var latinCount = 0
        var cyrillicCount = 0
        for scalar in text.unicodeScalars {
            if scalar.value >= 0x0041 && scalar.value <= 0x007A { latinCount += 1 }
            if scalar.value >= 0x0400 && scalar.value <= 0x04FF { cyrillicCount += 1 }
        }
        if latinCount == 0 && cyrillicCount == 0 { return nil }
        return latinCount >= cyrillicCount ? .enToRu : .ruToEn
    }
}
