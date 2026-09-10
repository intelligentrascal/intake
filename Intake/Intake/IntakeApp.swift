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
        .defaultLaunchBehavior(.presented)
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

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
