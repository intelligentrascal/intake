import Foundation

/// Maps the notification digest settings (IN-10) onto storage: a master
/// toggle (off by default) plus per-type toggles for Filed, Errors, and
/// Cleanup (each on by default once the master toggle is on). Follows
/// `AutomaticOrganizingPreference` / `RenameWhenDownloadFinishesPreference`.
public enum NotificationPreferences: Sendable {
    public static let masterKey = "intake.notifications.enabled"
    public static let filedKey = "intake.notifications.filed"
    public static let errorsKey = "intake.notifications.errors"
    public static let cleanupKey = "intake.notifications.cleanup"

    /// Default is off — no permission prompt until the user opts in.
    public static func isMasterEnabled(_ stored: Bool?) -> Bool {
        stored ?? false
    }

    public static func isFiledEnabled(_ stored: Bool?) -> Bool {
        stored ?? true
    }

    public static func isErrorsEnabled(_ stored: Bool?) -> Bool {
        stored ?? true
    }

    public static func isCleanupEnabled(_ stored: Bool?) -> Bool {
        stored ?? true
    }

    public static func isMasterEnabled(in defaults: UserDefaults) -> Bool {
        isMasterEnabled(defaults.object(forKey: masterKey) as? Bool)
    }

    public static func isFiledEnabled(in defaults: UserDefaults) -> Bool {
        isFiledEnabled(defaults.object(forKey: filedKey) as? Bool)
    }

    public static func isErrorsEnabled(in defaults: UserDefaults) -> Bool {
        isErrorsEnabled(defaults.object(forKey: errorsKey) as? Bool)
    }

    public static func isCleanupEnabled(in defaults: UserDefaults) -> Bool {
        isCleanupEnabled(defaults.object(forKey: cleanupKey) as? Bool)
    }

    public static func persistMaster(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: masterKey)
    }

    public static func persistFiled(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: filedKey)
    }

    public static func persistErrors(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: errorsKey)
    }

    public static func persistCleanup(_ enabled: Bool, to defaults: UserDefaults) {
        defaults.set(enabled, forKey: cleanupKey)
    }
}
