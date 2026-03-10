import AppKit

class SoundPlayer {
    static let availableSounds: [String] = ["Tink", "Pop", "Morse", "Funk", "Bottle"]

    private var currentSound: NSSound?

    func play(name: String, volume: Double) {
        currentSound?.stop()
        guard let sound = NSSound(named: name) else { return }
        sound.volume = Float(volume)
        currentSound = sound
        sound.play()
    }
}
