import AppKit
import SwiftUI

struct AboutSettingsView: View {
    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    Image(nsImage: NSApplication.shared.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Intake")
                            .font(.headline)
                        Text("Downloads organizer")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                LabeledContent("Version", value: versionString)
                LabeledContent("License", value: "MIT")
            }
            Section {
                Link("GitHub repository", destination: githubURL)
                Link("Security policy", destination: securityURL)
            } header: {
                Text("Links")
            }
            Section {
                Text("Watching, renaming, and filing stay on this Mac. Rule suggestions are computed on-device from Activity and the watch folder. AI assist is opt-in, off by default, and uses OpenRouter only when you enable it — file contents are not uploaded.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
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
