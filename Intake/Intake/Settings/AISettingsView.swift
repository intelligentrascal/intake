import AppKit
import SwiftUI
import IntakeCore
import UniformTypeIdentifiers

struct AISettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var apiKeyDraft = ""
    @State private var keyIsSaved = false
    @State private var keyInfo: OpenRouterKeyInfo?
    @State private var creditsInfo: OpenRouterCreditsInfo?
    /// Survives view recreation (e.g. switching settings panes) so revisiting this pane
    /// doesn't re-hit the network within the debounce window.
    private static var lastLookupTime: Date?
    @State private var isLoading = false
    @State private var showResetConfirmation = false
    @State private var showRemoveKeyConfirmation = false
    @State private var showOpenRouterNamingConfirmation = false
    @State private var isSetupExpanded = false
    @State private var trialResult: String?
    @State private var isTrying = false
    /// Set once the user confirms that OpenRouter naming sends extracted text off this Mac.
    @AppStorage("intake.contentAwareOpenRouterAcknowledged") private var openRouterNamingAcknowledged = false

    private let lookupDebounceInterval: TimeInterval = 60

    var body: some View {
        @Bindable var model = model
        Form {
            contentAwareSection
            Section {
                Toggle("Suggest folders with AI", isOn: $model.aiSuggestionsEnabled)
            } footer: {
                Text("Off by default. When no rule matches, OpenRouter suggests a folder using only a file’s name and your rule folder names — never its source, size, or contents. Suggestions don’t rename files.")
            }
            openRouterSection
            if model.openRouterSpendTracker.totalSpend > 0 {
                spendSection
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Send file contents to OpenRouter?",
            isPresented: $showOpenRouterNamingConfirmation
        ) {
            Button("Use OpenRouter") {
                openRouterNamingAcknowledged = true
                model.contentAwareRename.provider = .openRouter
                model.contentAwareRename.isEnabled = true
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Intake reads PDFs and images on this Mac, then sends the extracted text to OpenRouter to propose a name. That text leaves this Mac and is handled under OpenRouter’s and your model provider’s policies.")
        }
        .confirmationDialog(
            "Remove the OpenRouter API key?",
            isPresented: $showRemoveKeyConfirmation
        ) {
            Button("Remove Key", role: .destructive, action: removeKey)
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("The key is deleted from Keychain. Folder suggestions and OpenRouter naming stop until you add a key again.")
        }
        .onAppear {
            model.contentAwareAvailability = .current
            keyIsSaved = OpenRouterKeychain.hasKey
            isSetupExpanded = !keyIsSaved
            lookupAccountInfo()
        }
        .onChange(of: model.openRouterEnabled) { _, isOn in
            if isOn { lookupAccountInfo() }
        }
    }

    // MARK: OpenRouter

    @ViewBuilder
    private var openRouterSection: some View {
        @Bindable var model = model
        Section {
            Toggle("Enable OpenRouter", isOn: $model.openRouterEnabled)
                .disabled(!model.openRouterEnabled && !model.aiSuggestionsEnabled && !contentAwareUsesOpenRouter)
            if model.openRouterEnabled {
                DisclosureGroup("OpenRouter setup", isExpanded: $isSetupExpanded) {
                    SecureField(
                        keyIsSaved ? "Key saved in Keychain" : "API key",
                        text: $apiKeyDraft
                    )
                    .textContentType(.password)
                    .onSubmit(saveKey)
                    HStack {
                        Button(keyIsSaved ? "Replace Key" : "Save Key") {
                            saveKey()
                        }
                        .disabled(apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        if keyIsSaved {
                            Button("Remove Key…", role: .destructive) {
                                showRemoveKeyConfirmation = true
                            }
                        }
                    }
                    TextField("Base URL", text: $model.openRouterBaseURL, prompt: Text(OpenRouterConfiguration.defaultBaseURL))
                    if let baseURLIssue {
                        Label(baseURLIssue, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(IntakeColor.warning)
                            .font(.caption)
                    }
                    modelField
                }
                if isLoading {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Fetching account info…")
                            .foregroundStyle(.secondary)
                    }
                } else if let keyInfo {
                    LabeledContent("API Key", value: keyInfo.label)
                    LabeledContent("Key Usage", value: String(format: "$%.4f", keyInfo.usage))
                    LabeledContent("Remaining Limit", value: String(format: "$%.2f", keyInfo.limitRemaining))
                }
                if let creditsInfo {
                    LabeledContent("Account Credits", value: String(format: "$%.2f", creditsInfo.totalCredits))
                }
                if let status = model.openRouterStatusMessage {
                    Text(status)
                        .foregroundStyle(IntakeColor.warning)
                } else if keyIsSaved {
                    Text(readyMessage)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("OpenRouter")
        } footer: {
            Text(openRouterFooter)
        }
    }

    /// One control for the model: type any OpenRouter model ID, or pick a preset.
    private var modelField: some View {
        @Bindable var model = model
        return LabeledContent("Model") {
            HStack(spacing: 4) {
                TextField("Model", text: $model.openRouterModel, prompt: Text(OpenRouterConfiguration.defaultModel))
                    .labelsHidden()
                Menu {
                    ForEach(OpenRouterConfiguration.curatedModels, id: \.self) { name in
                        Button(name) { model.openRouterModel = name }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel("Model presets")
            }
        }
    }

    private var spendSection: some View {
        Section {
            LabeledContent("Total", value: String(format: "$%.4f", model.openRouterSpendTracker.totalSpend))
            LabeledContent("This Month", value: String(format: "$%.4f", model.openRouterSpendTracker.monthlySpend))
            Button("Reset Spend…") {
                showResetConfirmation = true
            }
            .alert("Reset Intake Spending?", isPresented: $showResetConfirmation) {
                Button("Cancel", role: .cancel) { }
                Button("Reset", role: .destructive) {
                    var tracker = model.openRouterSpendTracker
                    tracker.resetAll()
                    model.openRouterSpendTracker = tracker
                }
            } message: {
                Text("This will reset both total and monthly spending to zero.")
            }
        } header: {
            Text("Intake spend")
        }
    }

    private var contentAwareUsesOpenRouter: Bool {
        model.contentAwareRename.isEnabled && model.contentAwareRename.provider == .openRouter
    }

    private var readyMessage: String {
        switch (model.aiSuggestionsEnabled, contentAwareUsesOpenRouter) {
        case (true, true): "Ready. Used for folder suggestions and content-aware rename."
        case (true, false): "Ready. Suggestions run only on rule misses."
        case (false, true): "Ready. Used for content-aware rename."
        case (false, false): "Key saved. Turn on a feature above to use OpenRouter."
        }
    }

    private var openRouterFooter: String {
        var text = "The API key is stored in Keychain, not in preferences. Local rules run first. Folder suggestions send only a file’s name and your rule folder names."
        if contentAwareUsesOpenRouter {
            text += " Content-aware rename sends text extracted from your files."
        }
        return text
    }

    /// Advisory only: the key is sent to this address, so flag anything that isn't HTTPS.
    /// Plain HTTP to a loopback host (a local proxy) is allowed.
    private var baseURLIssue: String? {
        let trimmed = model.openRouterBaseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              let host = url.host()?.lowercased(), !host.isEmpty else {
            return "Enter a full URL, like \(OpenRouterConfiguration.defaultBaseURL)."
        }
        if scheme == "https" { return nil }
        if scheme == "http", ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host) { return nil }
        return "Use an https:// URL. Your API key is sent to this address."
    }

    // MARK: Content-aware rename

    @ViewBuilder
    private var contentAwareSection: some View {
        @Bindable var model = model
        Section {
            Toggle("Rename files from their contents", isOn: contentAwareEnabledBinding)
            Picker("Naming provider", selection: providerBinding) {
                ForEach(ContentAwareRenameProvider.allCases) { provider in
                    Text(provider.title).tag(provider)
                }
            }
            .disabled(!model.contentAwareRename.isEnabled)
            if contentAwareUsesOpenRouter {
                // Persistent status, not decoration: says plainly that contents go off-device.
                Label {
                    Text("File contents leave this Mac — extracted text is sent to OpenRouter.")
                } icon: {
                    Image(systemName: "network")
                        .foregroundStyle(IntakeColor.warning)
                }
                .font(.callout)
            }
            if let message = contentAwareAvailabilityMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(IntakeColor.warning)
                    .font(.callout)
            }
            ForEach(ContentAwareFileType.allCases) { type in
                Toggle(type.title, isOn: fileTypeBinding(type))
                    .disabled(!model.contentAwareRename.isEnabled)
            }
            TextField("Name template", text: $model.contentAwareRename.template, prompt: Text(ContentNameTemplate.defaultTemplate))
                .disabled(!model.contentAwareRename.isEnabled)
            Text("Tokens: {date} {type} {organization} {subject} {original}. Empty tokens are dropped.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("Try on a File…", action: tryOnFile)
                    .disabled(isTrying)
                if isTrying {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            if let trialResult {
                Text(trialResult)
                    .font(.callout)
                    .textSelection(.enabled)
            }
        } header: {
            Text("Content-aware rename")
        } footer: {
            Text(contentAwareFooter)
        }
    }

    /// Asks once before turning on content-aware rename while its provider is already
    /// OpenRouter and unacknowledged; until confirmed the toggle stays off.
    private var contentAwareEnabledBinding: Binding<Bool> {
        Binding {
            model.contentAwareRename.isEnabled
        } set: { newValue in
            if newValue, model.contentAwareRename.provider == .openRouter, !openRouterNamingAcknowledged {
                showOpenRouterNamingConfirmation = true
            } else {
                model.contentAwareRename.isEnabled = newValue
            }
        }
    }

    /// Asks once before switching to OpenRouter; until confirmed the picker stays on On this Mac.
    private var providerBinding: Binding<ContentAwareRenameProvider> {
        Binding {
            model.contentAwareRename.provider
        } set: { provider in
            if provider == .openRouter, !openRouterNamingAcknowledged {
                showOpenRouterNamingConfirmation = true
            } else {
                model.contentAwareRename.provider = provider
            }
        }
    }

    private var contentAwareAvailabilityMessage: String? {
        guard model.contentAwareRename.isEnabled else { return nil }
        return model.contentAwareProviderBlockMessage()
    }

    private var contentAwareFooter: String {
        switch model.contentAwareRename.provider {
        case .onDevice:
            return "Off by default. Intake reads PDFs and images on this Mac with Apple’s on-device model — file contents never leave this Mac. A name like “2026-09-14 Invoice Acme” is used only when it passes Intake’s checks; otherwise the file keeps its Title Case name. Follows each folder’s Rename when download finishes, and can be undone from Activity."
        case .openRouter:
            return "Off by default. Intake reads PDFs and images on this Mac, then sends that extracted text to OpenRouter to propose a name. Requires OpenRouter enabled and an API key below. A name is used only when it passes Intake’s checks; otherwise the file keeps its Title Case name. Follows each folder’s Rename when download finishes, and can be undone from Activity."
        }
    }

    private func fileTypeBinding(_ type: ContentAwareFileType) -> Binding<Bool> {
        Binding {
            model.contentAwareRename.fileTypes.contains(type)
        } set: { isOn in
            if isOn {
                model.contentAwareRename.fileTypes.insert(type)
            } else {
                model.contentAwareRename.fileTypes.remove(type)
            }
        }
    }

    private func tryOnFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.pdf, .image]
        panel.prompt = "Try"
        panel.message = model.contentAwareRename.provider == .openRouter
            ? "Intake reads this file on your Mac, sends the extracted text to OpenRouter, and shows the name it would use. Nothing is renamed."
            : "Intake reads this file on your Mac and shows the name it would use. Nothing is renamed."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        isTrying = true
        trialResult = nil
        Task {
            let result = await model.tryContentAwareName(for: url)
            trialResult = result
            isTrying = false
        }
    }

    private func saveKey() {
        let trimmed = apiKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        OpenRouterKeychain.save(trimmed)
        apiKeyDraft = ""
        keyIsSaved = OpenRouterKeychain.hasKey
        model.openRouterStatusMessage = nil
        keyInfo = nil
        creditsInfo = nil
        Self.lastLookupTime = nil
        lookupAccountInfo()
    }

    private func removeKey() {
        OpenRouterKeychain.delete()
        apiKeyDraft = ""
        keyIsSaved = false
        keyInfo = nil
        creditsInfo = nil
        isSetupExpanded = true
    }

    /// Account info shows for any feature using OpenRouter — not only folder suggestions.
    private func lookupAccountInfo() {
        guard model.openRouterEnabled else { return }
        guard model.aiSuggestionsEnabled || contentAwareUsesOpenRouter else { return }
        guard let key = OpenRouterKeychain.load() else { return }

        // Debounce lookups to at most once per minute
        if let lastTime = Self.lastLookupTime, Date().timeIntervalSince(lastTime) < lookupDebounceInterval {
            return
        }

        isLoading = true
        Task {
            let keyResult = await OpenRouterClient.fetchKeyInfo(
                apiKey: key,
                baseURL: model.openRouterBaseURL
            )
            let creditsResult = await OpenRouterClient.fetchCreditsInfo(
                apiKey: key,
                baseURL: model.openRouterBaseURL
            )

            await MainActor.run {
                isLoading = false
                Self.lastLookupTime = Date()

                if case .success(let info) = keyResult {
                    keyInfo = info
                } else if case .failure(let error) = keyResult {
                    model.openRouterStatusMessage = error.userMessage
                }

                if case .success(let info) = creditsResult {
                    creditsInfo = info
                } else if case .failure(let error) = creditsResult {
                    if model.openRouterStatusMessage == nil {
                        model.openRouterStatusMessage = error.userMessage
                    }
                }
            }
        }
    }
}
