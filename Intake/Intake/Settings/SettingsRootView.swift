import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        @Bindable var model = model
        HStack(spacing: 0) {
            SettingsSidebar()
                .frame(width: 192)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()

            SettingsDetailHost()
                .id(model.selectedSettingsPane)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(model)
                .background {
                    // A: no mesh under Form; B: clear detail (aurora is window-level); C: clear.
                    AtmosphereBackground(surface: .settingsDetail)
                }
        }
        .background {
            AtmosphereBackground(surface: .settingsWindow, animated: true)
        }
        .background {
            SettingsWindowConfigurator(title: model.selectedSettingsPane.title)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
        .overlay(alignment: .topLeading) {
            PaneKeyboardShortcuts()
        }
        .onAppear {
            SettingsSplitViewAutosave.resetSettingsSplitFrames()
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

/// Button-based sidebar. Do NOT swap for `List(selection:)` or
/// `NavigationSplitView`: under the SwiftUI `Settings` scene neither delivered
/// clicks (see commits 236e77e, e8577bb). Buttons set the pane directly; the
/// container carries list semantics for VoiceOver and ↑/↓ for the keyboard.
private struct SettingsSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(SettingsPane.allCases) { pane in
                let isSelected = model.selectedSettingsPane == pane
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
                        .fill(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
                }
                .foregroundStyle(.primary)
                .accessibilityLabel(pane.title)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint("Show \(pane.title) settings")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
        .padding(.bottom, 10)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor).opacity(0.92)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.upArrow) { step(-1) }
        .onKeyPress(.downArrow) { step(1) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sections")
    }

    private func step(_ delta: Int) -> KeyPress.Result {
        let panes = SettingsPane.allCases
        guard let index = panes.firstIndex(of: model.selectedSettingsPane) else { return .ignored }
        let next = index + delta
        guard panes.indices.contains(next) else { return .handled }
        model.selectedSettingsPane = panes[next]
        return .handled
    }
}

/// Hidden ⌘1…⌘7 shortcuts for jumping straight to a settings pane. Mounted as a
/// zero-size, invisible, non-hit-testable overlay so the buttons can never sit
/// above (or catch clicks meant for) real content.
private struct PaneKeyboardShortcuts: View {
    @Environment(AppModel.self) private var model
    private static let keys: [Character] = ["1", "2", "3", "4", "5", "6", "7"]

    var body: some View {
        ZStack {
            ForEach(Array(zip(Self.keys, SettingsPane.allCases)), id: \.1) { key, pane in
                Button("") { model.selectedSettingsPane = pane }
                    .keyboardShortcut(KeyEquivalent(key), modifiers: .command)
                    .focusable(false)
            }
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct SettingsDetailHost: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
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
            case .feedback:
                FeedbackSettingsView()
            case .about:
                AboutSettingsView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityLabel("\(model.selectedSettingsPane.title) settings")
    }
}

enum SettingsSplitViewAutosave {
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
