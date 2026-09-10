import Foundation

/// Maps the positive “Automatic organizing” toggle onto storage, including the
/// legacy `intake.paused` key (`automaticOrganizing = !paused`).
public enum AutomaticOrganizingPreference: Sendable {
    public static let currentKey = "intake.automaticOrganizing"
    public static let legacyPausedKey = "intake.paused"

    /// Default is on (watcher filing). Legacy paused=true becomes off.
    public static func isEnabled(automaticOrganizing: Bool?, legacyPaused: Bool?) -> Bool {
        if let automaticOrganizing {
            return automaticOrganizing
        }
        if let legacyPaused {
            return !legacyPaused
        }
        return true
    }

    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        isEnabled(
            automaticOrganizing: defaults.object(forKey: currentKey) as? Bool,
            legacyPaused: defaults.object(forKey: legacyPausedKey) as? Bool
        )
    }

    public static func persist(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: currentKey)
        defaults.set(!enabled, forKey: legacyPausedKey)
    }
}
