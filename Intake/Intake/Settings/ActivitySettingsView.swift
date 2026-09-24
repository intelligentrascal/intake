import SwiftUI

struct ActivitySettingsView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Form {
            Section {
                ActivityPaneBody()
            } header: {
                HStack {
                    Text("Activity")
                    Spacer()
                    Button("Open Activity") {
                        model.openActivity()
                    }
                }
            } footer: {
                Text("Double-click a row to reveal it in Finder; Control-click for more.")
            }
        }
        .formStyle(.grouped)
    }
}

private struct ActivityPaneBody: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        if model.activity.isEmpty {
            ContentUnavailableView(
                "No activity yet",
                systemImage: "list.bullet.clipboard",
                description: Text("When Intake renames or files a download, it shows up here.")
            )
            .frame(minHeight: 220)
        } else {
            ActivityListView(showsRevealToolbarItem: false)
                .frame(minHeight: 280)
        }
    }
}
