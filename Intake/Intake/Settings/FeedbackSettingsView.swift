import AppKit
import SwiftUI
import UniformTypeIdentifiers
import IntakeCore

struct FeedbackSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var feedbackType: FeedbackIssueType = .feature
    @State private var titleText = ""
    @State private var detailsText = ""
    @State private var emailText = ""
    /// Product rule: Diagnostics Toggle default Off (ignore Designer “On for Bug/Urgent”).
    @State private var includeDiagnostics = false
    @State private var screenshots: [FeedbackScreenshot] = []
    @State private var showDoneAlert = false
    @State private var doneAlertHadScreenshots = false
    @State private var validationMessage: String?
    /// Driven via onChange so Form + text fields reliably invalidate the submit button.
    @State private var canSubmit = false

    private let maxScreenshots = 3

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $feedbackType) {
                    ForEach(FeedbackIssueType.allCases) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Feedback type")
            } footer: {
                Text("Urgent is for broken organizing or data-loss risk — not general questions.")
            }

            Section {
                TextField("Short summary", text: $titleText)
                    .accessibilityLabel("Title")
                TextField(
                    "What happened, what you expected, steps if it’s a bug",
                    text: $detailsText,
                    axis: .vertical
                )
                .lineLimit(5...12)
                .accessibilityLabel("Details")
            } header: {
                Text("Report")
            }

            Section {
                TextField("Email (optional)", text: $emailText)
                    .textContentType(.emailAddress)
                    .accessibilityLabel("Email optional")
            } footer: {
                Text("Included in the public GitHub issue. Leave blank if you’d rather not share it.")
            }

            Section {
                Toggle("Include diagnostics", isOn: $includeDiagnostics)
                    .accessibilityLabel("Include diagnostics")
            } footer: {
                Text("App version, macOS version, and recent Activity lines. Stays on this Mac until you submit; pasted into the issue body. No file contents.")
            }

            Section {
                if screenshots.isEmpty {
                    Text("No screenshots yet")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(screenshots.enumerated()), id: \.element.id) { index, shot in
                        HStack(spacing: 12) {
                            Image(nsImage: shot.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                .accessibilityHidden(true)
                            Text("Screenshot \(index + 1) of \(screenshots.count)")
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Remove", role: .destructive) {
                                screenshots.removeAll { $0.id == shot.id }
                            }
                            .accessibilityLabel("Remove screenshot \(index + 1)")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Screenshot \(index + 1) of \(screenshots.count)")
                    }
                }
                HStack {
                    Button("Add…") { addScreenshotsFromPanel() }
                        .disabled(screenshots.count >= maxScreenshots)
                    Button("Paste") { pasteScreenshot() }
                        .disabled(screenshots.count >= maxScreenshots)
                }
                Text("\(screenshots.count) of \(maxScreenshots)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Screenshots")
            } footer: {
                Text("Don’t capture windows with private documents or API keys. Screenshots stay on this Mac until you paste them into GitHub.")
            }

            Section {
                Button("Open GitHub Issue") {
                    submit()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit)
                .accessibilityHint("Opens in browser")
                if let validationMessage {
                    Text(validationMessage)
                        .foregroundStyle(IntakeColor.warning)
                }
            } footer: {
                Text("Opens a prefilled GitHub Issue in your browser. No account token is stored in Intake. Issues on this repo are public.")
            }
        }
        .formStyle(.grouped)
        .onChange(of: titleText) { _, _ in refreshCanSubmit() }
        .onChange(of: detailsText) { _, _ in refreshCanSubmit() }
        .alert("Almost done", isPresented: $showDoneAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            if doneAlertHadScreenshots {
                Text("GitHub opened with your text. Paste screenshots into the issue with ⌘V (they’re on your clipboard).")
            } else {
                Text("GitHub opened with your text. Add any screenshots on the issue page if needed.")
            }
        }
    }

    private func refreshCanSubmit() {
        canSubmit = FeedbackFormValidation.canSubmit(title: titleText, details: detailsText)
    }

    private func submit() {
        validationMessage = nil
        refreshCanSubmit()
        guard FeedbackFormValidation.canSubmit(title: titleText, details: detailsText) else {
            validationMessage = "Add a title and details before opening GitHub."
            return
        }

        let draft = FeedbackIssueDraft(
            type: feedbackType,
            title: titleText,
            details: detailsText,
            email: emailText,
            includeDiagnostics: includeDiagnostics,
            diagnosticsText: includeDiagnostics ? model.feedbackDiagnosticsText() : nil,
            screenshotCount: screenshots.count
        )
        guard let url = FeedbackIssueComposer.makeURL(for: draft) else {
            validationMessage = "Add a title and details before opening GitHub."
            return
        }

        if !screenshots.isEmpty {
            copyScreenshotsToPasteboard(screenshots.map(\.image))
        }

        NSWorkspace.shared.open(url)

        doneAlertHadScreenshots = !screenshots.isEmpty
        showDoneAlert = true
    }

    private func addScreenshotsFromPanel() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .webP, .tiff, .gif]
        panel.message = "Choose up to \(maxScreenshots - screenshots.count) screenshot(s)"
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard screenshots.count < maxScreenshots else { break }
            if let image = NSImage(contentsOf: url) {
                screenshots.append(FeedbackScreenshot(image: image))
            }
        }
    }

    private func pasteScreenshot() {
        guard screenshots.count < maxScreenshots else { return }
        let pb = NSPasteboard.general
        if let image = NSImage(pasteboard: pb) {
            screenshots.append(FeedbackScreenshot(image: image))
            return
        }
        validationMessage = "No image on the clipboard. Copy a screenshot, then Paste."
    }

    private func copyScreenshotsToPasteboard(_ images: [NSImage]) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if images.count == 1, let image = images.first {
            pb.writeObjects([image])
            return
        }
        // Multi-image: write all NSImages; GitHub’s web UI typically pastes the first.
        pb.writeObjects(images)
    }
}

private struct FeedbackScreenshot: Identifiable {
    let id = UUID()
    let image: NSImage
}

extension AppModel {
    /// Diagnostics block for feedback (versions + recent Activity). Paths redacted.
    func feedbackDiagnosticsText() -> String {
        let info = Bundle.main.infoDictionary
        let marketing = info?["CFBundleShortVersionString"] as? String ?? "0.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersionString
        var lines: [String] = ["Intake \(marketing) (\(build)) · macOS \(os)"]
        let recent = Array(activity.prefix(8))
        if !recent.isEmpty {
            lines.append("Recent Activity:")
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .short
            for entry in recent {
                let stamp = formatter.string(from: entry.date)
                let raw = "\(stamp) · \(entry.verb) · \(entry.detail)"
                lines.append(FeedbackIssueComposer.redactHomePaths(in: raw))
            }
        }
        return lines.joined(separator: "\n")
    }
}
