import Foundation

/// Maps “Rename when download finishes” (Arc Tidy–style local rename on stable).
/// Default is on. Missing key must not be read with `UserDefaults.bool`, which is false.
public enum RenameWhenDownloadFinishesPreference: Sendable {
    public static let currentKey = "intake.renameWhenDownloadFinishes"

    public static func isEnabled(_ stored: Bool?) -> Bool {
        stored ?? true
    }

    public static func isEnabled(in defaults: UserDefaults) -> Bool {
        isEnabled(defaults.object(forKey: currentKey) as? Bool)
    }

    public static func persist(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: currentKey)
    }
}
