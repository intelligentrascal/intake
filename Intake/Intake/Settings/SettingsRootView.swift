import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pane: SettingsPane = .general

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                ForEach(SettingsPane.allCases) { item in
                    Label(item.title, systemImage: item.systemImage)
                        .tag(item)
                }
            }
            .listStyle(.sidebar)
            .navigationTitle("Intake")
            .navigationSplitViewColumnWidth(min: 160, ideal: 192, max: 240)
        } detail: {
            Group {
                switch pane {
                case .general:
                    GeneralSettingsView()
                case .rules:
                    RulesSettingsView()
                case .cleanup:
                    CleanupSettingsView()
                case .ai:
                    AISettingsView()
                case .about:
                    AboutSettingsView()
                }
            }
            .navigationTitle(pane.title)
            .environment(model)
        }
        .navigationSplitViewStyle(.balanced)
        .animation(reduceMotion ? nil : .default, value: pane)
    }
}
