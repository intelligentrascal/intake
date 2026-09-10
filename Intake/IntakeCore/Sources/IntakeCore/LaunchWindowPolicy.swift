/// Dock / launch presents Settings. Activity is never restored as the launch surface.
public enum LaunchWindowPolicy: Sendable {
    /// Always hide restored Activity windows at launch, even when Settings is shown.
    public static let hidesActivityAtLaunch = true

    public static func presentsSettings(showsInDock: Bool, isFirstRun: Bool) -> Bool {
        showsInDock || isFirstRun
    }
}
