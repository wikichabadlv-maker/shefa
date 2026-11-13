import AudioToolbox
import UIKit

/// Short sounds and taps that reward an action. Sounds follow the iPhone's
/// ring switch: on silent, only the tap is felt.
enum Feedback {
    enum Sound: String, CaseIterable {
        case done, add, celebrate, bell
    }

    static let soundsKey = "soundsOn"

    private static var ids: [Sound: SystemSoundID] = [:]

    private static var soundsOn: Bool {
        UserDefaults.standard.object(forKey: soundsKey) as? Bool ?? true
    }

    static func play(_ sound: Sound) {
        guard soundsOn else { return }
        if ids[sound] == nil, let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "wav") {
            var id: SystemSoundID = 0
            AudioServicesCreateSystemSoundID(url as CFURL, &id)
            ids[sound] = id
        }
        if let id = ids[sound] {
            AudioServicesPlaySystemSound(id)
        }
    }

    static func tap() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Finishing something: a rising chime and a firm tap.
    static func done() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play(.done)
    }

    static func added() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        play(.add)
    }

    static func celebrate() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        play(.celebrate)
    }
}
