import AppKit
import SwiftUI
import IntakeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: templateIcon)
            .accessibilityLabel(model.menuBarAccessibilityLabel)
    }

    /// Dense 16pt template glyphs (Watching vs Paused). `MenuBarExtra` follows the
    /// system menu bar; macOS has no supported API to pin extras to the primary
    /// display only (no Thaw-style multi-bar manager).
    private var templateIcon: NSImage {
        let name = model.isPaused ? "MenuBarIconPaused" : "MenuBarIconWatching"
        let image = NSImage(named: name) ?? NSImage(size: NSSize(width: 16, height: 16))
        image.isTemplate = true
        image.size = NSSize(width: 16, height: 16)
        return image
    }
}

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.statusTitle)
        Text(model.statusSubtitle)
        Divider()
        Button(model.isPaused ? "Resume Organizing" : "Pause Organizing") {
            model.togglePaused()
        }
        OrganizeExistingMenu()
        if !model.recentActivity.isEmpty {
            Divider()
            ForEach(model.recentActivity) { entry in
                Button(entry.menuTitle) {
                    model.reveal(entry)
                }
            }
        }
        Divider()
        Button("Open Activity") {
            model.openActivity()
        }
        Button("Open Cleanup") {
            model.openSettings(pane: .cleanup)
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Send Feedback…") {
            model.openSettings(pane: .feedback)
        }
        Divider()
        Button("Quit Intake") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

/// Organize Existing… — a plain button with one watch folder, a menu of
/// "All watch folders" plus each folder with several.
struct OrganizeExistingMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.hasMultipleWatchFolders {
                Menu(OrganizeExistingCopy.menuTitle) {
                    Button("All watch folders") {
                        model.requestOrganizeExisting()
                    }
                    Divider()
                    ForEach(model.watchFolderControllers, id: \.profileID) { controller in
                        Button(controller.displayName) {
                            model.requestOrganizeExisting(profileID: controller.profileID)
                        }
                        .disabled(controller.accessLost)
                    }
                }
            } else {
                Button(OrganizeExistingCopy.menuTitle) {
                    model.requestOrganizeExisting()
                }
            }
        }
        .disabled(model.isOrganizeExistingDisabled)
    }
}
