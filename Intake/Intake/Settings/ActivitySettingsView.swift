import SwiftUI

struct ActivitySettingsView: View {
    var body: some View {
        Form {
            Section {
                ActivityPaneBody()
            } footer: {
                Text("The Activity window is Intake’s home. Double-click a row to reveal it in Finder, or use Reveal in Finder.")
            }
        }
        .formStyle(.grouped)
        .padding()
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
            ActivityListView()
                .frame(minHeight: 280)
        }
    }
}
