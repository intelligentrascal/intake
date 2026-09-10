import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var model = model
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(selection: sidebarSelection) {
                ForEach(SettingsPane.allCases) { pane in
                    Label(pane.title, systemImage: pane.systemImage)
                        .tag(Optional(pane))
                        .padding(.vertical, 3)
                }
            }
            .listStyle(.sidebar)
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

    /// `List(selection:)` needs an Optional binding — a non-optional enum
    /// is the usual source of missing / sticky sidebar highlight.
    private var sidebarSelection: Binding<SettingsPane?> {
        Binding(
            get: { model.selectedSettingsPane },
            set: { pane in
                if let pane {
                    model.selectedSettingsPane = pane
                }
            }
        )
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
