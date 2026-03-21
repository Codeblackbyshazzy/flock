import AppKit

enum SoundEffects {
    private static var tickSound: NSSound? = {
        NSSound(contentsOfFile: "/System/Library/Sounds/Tink.aiff", byReference: true)
    }()

    private static var chimeSound: NSSound? = {
        NSSound(contentsOfFile: "/System/Library/Sounds/Glass.aiff", byReference: true)
    }()

    static func playTick() {
        guard Settings.shared.soundEffectsEnabled else { return }
        tickSound?.stop()  // allow rapid re-trigger
        tickSound?.play()
    }

    static func playChime() {
        guard Settings.shared.soundEffectsEnabled else { return }
        chimeSound?.stop()
        chimeSound?.play()
    }
}
