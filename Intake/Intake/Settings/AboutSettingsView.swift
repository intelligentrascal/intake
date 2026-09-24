import AppKit
import SwiftUI
import IntakeCore

struct AboutSettingsView: View {
    @Environment(AppModel.self) private var model

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
                Button("Send Feedback…") {
                    model.openSettings(pane: .feedback)
                }
            } header: {
                Text("Links")
            }
            Section {
                Text(privacyText)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Privacy")
            }
        }
        .formStyle(.grouped)
    }

    /// Must match what the AI pane actually does: OpenRouter naming sends extracted text off this Mac.
    private var privacyText: String {
        let base = "Watching, renaming, and filing stay on this Mac. Rule suggestions are computed on-device from Activity and the watch folder. AI is opt-in and off by default; OpenRouter folder suggestions send only file names."
        let rename = model.contentAwareRename
        if rename.isEnabled && rename.provider == .openRouter {
            return base + " Content-aware rename is set to OpenRouter, so text extracted from your PDFs and images is sent to OpenRouter."
        }
        if rename.provider == .openRouter {
            return base + " Content-aware rename reads files on this Mac; contents leave it only if you turn on content-aware rename, which is set to use OpenRouter."
        }
        return base + " Content-aware rename reads files on this Mac; contents leave it only if you choose OpenRouter as the naming provider."
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
