import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            // Button-based sidebar — List(selection:) was dead under Settings scene
            // (AX clicks never changed the pane / title). Buttons set the pane directly.
            VStack(alignment: .leading, spacing: 2) {
                ForEach(SettingsPane.allCases) { pane in
                    Button {
                        model.selectedSettingsPane = pane
                    } label: {
                        Label(pane.title, systemImage: pane.systemImage)
                            .labelStyle(.titleAndIcon)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .background {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(model.selectedSettingsPane == pane
                                  ? Color.accentColor.opacity(0.18)
                                  : Color.clear)
                    }
                    .foregroundStyle(model.selectedSettingsPane == pane
                                     ? Color.primary
                                     : Color.primary.opacity(0.85))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 10)
            .navigationTitle("Intake")
            .navigationSplitViewColumnWidth(min: 160, ideal: 192, max: 240)
        } detail: {
            SettingsDetailHost()
                .id(model.selectedSettingsPane)
                .navigationTitle(model.selectedSettingsPane.title)
                .environment(model)
                .frame(minWidth: 480, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .background {
            SettingsWindowConfigurator()
        }
        .onAppear {
            columnVisibility = .all
            SettingsSplitViewAutosave.resetSettingsSplitFrames()
            // Re-assert after SwiftUI applies restored split state.
            DispatchQueue.main.async {
                columnVisibility = .all
            }
        }
        .background {
            if !reduceTransparency && contrast != .increased {
                IntakeMeshBackground(style: .settingsWash, animated: false)
            }
        }
        .alert(
            "Keep one way to open Intake",
            isPresented: $model.keepOneSurfaceAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn off Dock or the menu bar, not both — otherwise there’s no icon to reopen Intake.")
        }
    }
}

private struct SettingsDetailHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        switch model.selectedSettingsPane {
        case .general:
            GeneralSettingsView()
        case .rules:
            RulesSettingsView()
        case .cleanup:
            CleanupSettingsView()
        case .activity:
            ActivitySettingsView()
        case .ai:
            AISettingsView()
        case .about:
            AboutSettingsView()
        }
    }
}

/// Clears the exact Settings NavigationSplitView autosave that leaves a dead sidebar.
enum SettingsSplitViewAutosave {
    /// Observed on Mac smoke: `NSSplitView Subview Frames com_apple_SwiftUI_Settings_window, SidebarNavigationSplitView`
    static let exactSettingsSplitKey =
        "NSSplitView Subview Frames com_apple_SwiftUI_Settings_window, SidebarNavigationSplitView"

    static func resetSettingsSplitFrames() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: exactSettingsSplitKey)
        for key in defaults.dictionaryRepresentation().keys {
            let lower = key.lowercased()
            let isSplit = lower.contains("nssplitview") || lower.contains("navigationsplit")
            let isSettings = lower.contains("com_apple_swiftui_settings")
                || lower.contains("sidebarnavigationsplitview")
                || (lower.contains("settings") && lower.contains("split"))
            if isSplit && isSettings {
                defaults.removeObject(forKey: key)
            }
        }
    }
}
