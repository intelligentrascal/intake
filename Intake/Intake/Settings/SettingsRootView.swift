import SwiftUI

struct SettingsRootView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedSettingsPane) {
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
            .navigationTitle(model.selectedSettingsPane.title)
            .environment(model)
            .frame(maxWidth: 560, alignment: .topLeading)
        }
        .navigationSplitViewStyle(.balanced)
        .animation(reduceMotion ? nil : .default, value: model.selectedSettingsPane)
        .alert(
            "Intake lives in the Dock and menu bar",
            isPresented: $model.showFirstRunTip
        ) {
            Button("OK") {
                model.acknowledgeFirstRunTip()
            }
        } message: {
            Text("Look for the soft-catch icon in the Dock and near Control Center.")
        }
        .alert(
            "Keep one way to open Intake",
            isPresented: $model.keepOneSurfaceAlert
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Turn off Dock or the menu bar, not both — otherwise there’s no icon to reopen Settings.")
        }
    }
}
