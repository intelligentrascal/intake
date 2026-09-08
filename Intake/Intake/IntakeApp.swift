import SwiftUI

@main
struct IntakeApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environment(model)
        } label: {
            MenuBarLabel()
                .environment(model)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsRootView()
                .environment(model)
                .frame(minWidth: 680, minHeight: 460)
        }
    }
}
