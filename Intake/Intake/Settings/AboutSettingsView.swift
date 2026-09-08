import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                LabeledContent("Intake") {
                    Text("Downloads organizer")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Version", value: versionString)
                LabeledContent("License", value: "MIT")
            }
            Section("Links") {
                Link("GitHub repository", destination: githubURL)
                Link("Security policy", destination: securityURL)
            }
            Section("Privacy") {
                Text("Watching, renaming, and filing stay on this Mac. AI assist is opt-in and off.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }

    private var versionString: String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(marketing) (\(build))"
    }

    private var githubURL: URL {
        URL(string: "https://github.com/intelligentrascal/intake")!
    }

    private var securityURL: URL {
        URL(string: "https://github.com/intelligentrascal/intake/blob/main/SECURITY.md")!
    }
}
