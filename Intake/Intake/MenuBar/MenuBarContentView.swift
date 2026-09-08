import AppKit
import SwiftUI
import IntakeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(systemName: model.menuBarSymbol)
            .symbolRenderingMode(.hierarchical)
            .accessibilityLabel(model.menuBarAccessibilityLabel)
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
        Divider()
        Button("Quit Intake") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
