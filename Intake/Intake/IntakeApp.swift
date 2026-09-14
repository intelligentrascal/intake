import AppKit
import SwiftUI
import IntakeCore

@main
struct IntakeApp: App {
    @NSApplicationDelegateAdaptor(IntakeAppDelegate.self) private var appDelegate

    var body: some Scene {
        let model = appDelegate.model
        let _ = model.showsInMenuBar
        let _ = model.isPaused

        Window("Activity", id: IntakeSceneID.activity) {
            ActivityWindowView()
                .environment(model)
                .background(ActivityWindowOpenBridge().environment(model))
        }
        .defaultSize(width: 640, height: 520)
        .windowResizability(.contentMinSize)
        // Activity is not a launch surface. Open via Open Activity / menu / openActivity().
        .defaultLaunchBehavior(.suppressed)
        .defaultPosition(.center)
        .commands {
            CommandGroup(after: .appSettings) {
                Button(model.isPaused ? "Resume Organizing" : "Pause Organizing") {
                    model.togglePaused()
                }
                Button(OrganizeExistingCopy.menuTitle) {
                    model.requestOrganizeExisting()
                }
                .disabled(model.isOrganizingExisting || model.watchFolderBookmarkLost)
                Button("Activity") {
                    model.openActivity()
                }
            }
        }

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContentView()
                .environment(model)
                .background(ActivityWindowOpenBridge().environment(model))
                .background(SettingsOpenBridge().environment(model))
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 480)
                .background(ActivityWindowOpenBridge().environment(model))
                .background(SettingsOpenBridge().environment(model))
        }
    }

    private var menuBarInserted: Binding<Bool> {
        Binding(
            get: { appDelegate.model.showsInMenuBar },
            set: { appDelegate.model.setShowsInMenuBar($0) }
        )
    }
}

@MainActor
final class IntakeAppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_ notification: Notification) {
        model.applicationDidFinishLaunching()
    }

    /// Dock icon click / reopen. SwiftUI often does NOT forward this when a Window
    /// scene exists; with Activity `.defaultLaunchBehavior(.suppressed)`, Dock can
    /// present nothing. Always open Settings and return `false`.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        DispatchQueue.main.async { [model] in
            model.bringPrimaryWindowForward()
        }
        return false
    }

    /// Dock click often lands here instead of reopen when a suppressed Window scene
    /// exists. If Dock icon is shown and Settings is not visible, front Settings.
    func applicationDidBecomeActive(_ notification: Notification) {
        guard model.showsInDock else { return }
        guard !model.isSettingsWindowVisible else { return }
        DispatchQueue.main.async { [model] in
            model.bringPrimaryWindowForward()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
