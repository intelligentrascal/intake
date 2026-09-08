import AppKit
import SwiftUI

@main
struct IntakeApp: App {
    @NSApplicationDelegateAdaptor(IntakeAppDelegate.self) private var appDelegate

    var body: some Scene {
        let model = appDelegate.model
        let _ = model.showsInMenuBar
        let _ = model.isPaused

        MenuBarExtra(isInserted: menuBarInserted) {
            MenuBarContentView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environment(model)
                .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .appSettings) {
                Button(model.isPaused ? "Resume Organizing" : "Pause Organizing") {
                    model.togglePaused()
                }
            }
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

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        model.bringPrimaryWindowForward()
        return true
    }
}
