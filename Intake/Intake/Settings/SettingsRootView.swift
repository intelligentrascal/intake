import AppKit
import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @AppStorage(AtmosphereStyle.defaultsKey) private var atmosphereRaw = AtmosphereStyle.shippingDefault.rawValue

    private var atmosphere: AtmosphereStyle {
        AtmosphereStyle.resolve(atmosphereRaw)
    }

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
                    AtmosphereBackground(style: atmosphere, surface: .settingsDetail)
                }
        }
        .background {
            AtmosphereBackground(style: atmosphere, surface: .settingsWindow, animated: true)
        }
        .background {
            SettingsWindowConfigurator(title: model.selectedSettingsPane.title)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
                .accessibilityHidden(true)
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

private struct SettingsSidebar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Intake")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.top, 12)
                .padding(.bottom, 6)
                .accessibilityAddTraits(.isHeader)

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
                .foregroundStyle(.primary)
                .accessibilityLabel(pane.title)
                .accessibilityAddTraits(model.selectedSettingsPane == pane ? .isSelected : [])
                .accessibilityHint("Show \(pane.title) settings")
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .background {
            if reduceTransparency {
                Color(nsColor: .windowBackgroundColor).opacity(0.92)
            } else {
                Rectangle().fill(.ultraThinMaterial)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Settings sidebar")
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
