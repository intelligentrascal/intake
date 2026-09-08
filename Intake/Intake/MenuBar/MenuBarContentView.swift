import AppKit
import SwiftUI
import IntakeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: templateIcon)
            .accessibilityLabel(model.menuBarAccessibilityLabel)
    }

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
        if !model.recentActivity.isEmpty {
            Divider()
            ForEach(model.recentActivity) { entry in
                Button(entry.menuTitle) {
                    model.reveal(entry.url)
                }
            }
        }
        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        if model.showsInDock {
            Button("Open Activity") {
                model.openSettings(pane: .activity)
            }
            Button("Open Cleanup") {
                model.openSettings(pane: .cleanup)
            }
        }
        Divider()
        Button("Quit Intake") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
