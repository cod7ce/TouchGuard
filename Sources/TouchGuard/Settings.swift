import Foundation

/// All user-facing options, persisted in UserDefaults.
final class Settings {
    static let shared = Settings()

    private enum Key {
        static let enabled = "enabled"
        static let delayMS = "delayMS"
        static let blockClicks = "blockClicks"
        static let blockMovement = "blockMovement"
        static let blockScroll = "blockScroll"
        static let allowModifierChords = "allowModifierChords"
        static let strictTrackpadOnly = "strictTrackpadOnly"
    }

    private let defaults = UserDefaults.standard

    private init() {
        defaults.register(defaults: [
            Key.enabled: true,
            Key.delayMS: 500,
            Key.blockClicks: true,
            Key.blockMovement: true,
            Key.blockScroll: true,
            Key.allowModifierChords: true,
            Key.strictTrackpadOnly: false,
        ])
    }

    /// Master switch. When false the tap stays installed but passes everything through.
    var enabled: Bool {
        get { defaults.bool(forKey: Key.enabled) }
        set { defaults.set(newValue, forKey: Key.enabled) }
    }

    /// How long after the last keystroke the trackpad stays muted.
    var delayMS: Int {
        get { defaults.integer(forKey: Key.delayMS) }
        set { defaults.set(newValue, forKey: Key.delayMS) }
    }

    var blockClicks: Bool {
        get { defaults.bool(forKey: Key.blockClicks) }
        set { defaults.set(newValue, forKey: Key.blockClicks) }
    }

    var blockMovement: Bool {
        get { defaults.bool(forKey: Key.blockMovement) }
        set { defaults.set(newValue, forKey: Key.blockMovement) }
    }

    var blockScroll: Bool {
        get { defaults.bool(forKey: Key.blockScroll) }
        set { defaults.set(newValue, forKey: Key.blockScroll) }
    }

    /// Let Cmd/Ctrl/Option/Shift chords through, so Cmd-click keeps working while typing.
    var allowModifierChords: Bool {
        get { defaults.bool(forKey: Key.allowModifierChords) }
        set { defaults.set(newValue, forKey: Key.allowModifierChords) }
    }

    /// Only mute events that are positively identified as trackpad input.
    /// Off by default: identification is a heuristic, and failing open would
    /// make the app silently do nothing.
    var strictTrackpadOnly: Bool {
        get { defaults.bool(forKey: Key.strictTrackpadOnly) }
        set { defaults.set(newValue, forKey: Key.strictTrackpadOnly) }
    }

    var delay: CFTimeInterval { CFTimeInterval(delayMS) / 1000.0 }
}
