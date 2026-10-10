import AppKit
import SwiftUI
import IntakeCore

/// "Set Up Offline Renaming" window, O1–O5 (SPEC §8.2–8.4). One view that
/// switches on the resolved screen; no navigation stack. Copy from the mocks'
/// copy.json; tier sizes and lines from `OfflineModelManifest`.
struct OfflineSetupView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showsOtherSizes = false
    @State private var useOfflineModel = true

    private var offline: OfflineModelController { model.offlineModel }

    private var screen: OfflineOnboardingScreen {
        OfflineOnboardingScreen.resolve(
            step: offline.onboardingStep,
            recommendation: offline.recommendation,
            network: offline.networkStatus,
            download: offline.machine.phase,
            upgradeCheckboxDefault: offline.readyCheckboxDefault
        )
    }

    var body: some View {
        @Bindable var offline = offline
        VStack(spacing: 16) {
            content
        }
        .padding(24)
        .frame(width: 520, height: 460)
        .alert(meteredTitle, isPresented: meteredBinding) {
            Button("Download Anyway") { offline.meteredChoice(downloadAnyway: true) }
            Button("Wait for Wi-Fi", role: .cancel) { offline.meteredChoice(downloadAnyway: false) }
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("You're on a metered connection (like an iPhone hotspot).")
        }
        .alert("Cancel the download?", isPresented: $offline.cancelConfirmationPresented) {
            Button("Cancel Download", role: .destructive) { offline.cancelDownload() }
            Button("Keep Downloading", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("You can resume it from Settings within 24 hours.")
        }
        .onAppear {
            if offline.recommendation == nil { offline.refreshHardware() }
            useOfflineModel = offline.readyCheckboxDefault ?? true
        }
        .onDisappear {
            offline.setupWindowClosed()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case .welcome:
            welcome
        case .detecting:
            hero("cpu")
            title("Recommended for this Mac")
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking this Mac…").foregroundStyle(.secondary)
            }
            Spacer()
            footer { skipButton } trailing: { EmptyView() }
                .task { offline.refreshHardware() }
        case .recommendation(let state):
            recommendation(state)
        case .unsupported:
            hero("cpu")
            title(OfflineModelRecommendation.unsupportedTitle)
            bodyText(OfflineModelRecommendation.unsupportedMessage)
            Spacer()
            footer { EmptyView() } trailing: { closeButton(prominent: true) }
        case .downloading(let state):
            downloading(state)
        case .lowDisk(let short):
            errorHero
            title("Not enough space to finish")
            bodyText("Needs \(OfflineModelFormat.bytes(short)) more space to finish.")
            Spacer()
            footer { closeButton(prominent: false) } trailing: {
                Button("Try Again") { offline.startDownload(offline.machine.tier) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .unavailable:
            errorHero
            title("Download stopped")
            bodyText("This model is no longer available. Update Intake.")
            Spacer()
            footer { closeButton(prominent: false) } trailing: {
                Button("Check for Updates…") {
                    model.openSettings(pane: .about)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        case .verifyingChecksum, .selfTesting:
            verifying(selfTesting: screen == .selfTesting)
        case .checksumFailed(let again):
            errorHero
            title("Verifying")
            bodyText(again ? "Still not working." : "The download was damaged. Intake deleted it.")
            Spacer()
            footer {
                closeButton(prominent: false)
            } trailing: {
                if again {
                    Button("Send Feedback…") {
                        model.openSettings(pane: .feedback)
                        dismiss()
                    }
                }
                Button("Try Again") { offline.startDownload(offline.machine.tier) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        case .selfTestFailed(let smaller), .loadFailed(let smaller):
            errorHero
            title("Verifying")
            if let smaller {
                let entry = OfflineModelManifest.entry(for: smaller)
                bodyText("This model is too slow on this Mac. Try \(offline.tierName(smaller)) instead. It's smaller.")
                Spacer()
                footer { closeButton(prominent: false) } trailing: {
                    Button("Download \(offline.tierName(smaller)) (\(entry.sizeLabel))") {
                        offline.startDownload(smaller)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                }
            } else {
                bodyText("Offline renaming isn't available on this Mac. Files still get tidy names.")
                Spacer()
                footer { EmptyView() } trailing: { closeButton(prominent: true) }
            }
        case .ready(let checkboxDefault):
            ready(showsCheckbox: checkboxDefault != nil)
        }
    }

    // MARK: O1

    @ViewBuilder
    private var welcome: some View {
        hero("doc.text.magnifyingglass")
        title("Rename files by what's inside them")
        Text("Intake can read a PDF or image and give it a clear name, like \(Text("2026-03-14 Invoice Acme Rent March").italic()). It uses a small AI model that runs entirely on this Mac. Nothing is uploaded.")
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 430)
            .fixedSize(horizontal: false, vertical: true)
        Spacer()
        footer { skipButton } trailing: {
            Button("Continue") {
                offline.refreshHardware()
                offline.onboardingStep = .recommendation
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: O2

    @ViewBuilder
    private func recommendation(_ state: OfflineOnboardingScreen.RecommendationState) -> some View {
        @Bindable var offline = offline
        let rec = offline.recommendation
        hero("cpu")
        title("Recommended for this Mac")
        if let hardware = offline.hardware {
            Label(hardware.macLine, systemImage: "cpu")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let tier = offline.chosenTier {
                    tierLineText(offline.line(tier))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let options = rec?.options, options.count > 1 {
                    DisclosureGroup("Choose another size…", isExpanded: $showsOtherSizes) {
                        tierPicker(options)
                    }
                }
                Text(OfflineModelManifest.licenseLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(4)
        }
        switch state {
        case .offline:
            Label("You're offline. Intake will start the download when you're back online.", systemImage: "wifi.slash")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        case .smallerTierForSpace:
            warning([rec?.noSpaceMessage, rec?.smallerTierMessage].compactMap { $0 }.joined(separator: " "))
        case .noSpace:
            warning([rec?.noSpaceMessage, OfflineModelRecommendation.noSpaceNoneMessage].compactMap { $0 }.joined(separator: " "))
        case .waitingForWifi:
            Label("Intake will start the download on Wi-Fi.", systemImage: "wifi")
                .foregroundStyle(.secondary)
        case .normal, .confirmingMetered:
            EmptyView()
        }
        Spacer(minLength: 0)
        footer { skipButton } trailing: {
            if state == .noSpace {
                Button("Try Again") { offline.refreshHardware() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            } else if let tier = offline.chosenTier {
                let entry = OfflineModelManifest.entry(for: tier)
                Button(state == .offline ? "Download When Online" : "Download \(entry.sizeLabel)") {
                    offline.startDownload(tier, switchToOffline: nil)
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(state == .waitingForWifi)
            }
        }
    }

    private func tierPicker(_ options: [OfflineTierOption]) -> some View {
        Picker("Size", selection: tierSelection) {
            ForEach(options) { option in
                VStack(alignment: .leading, spacing: 2) {
                    tierLineText(option.line)
                    if option.tier == offline.recommendation?.recommendedTier {
                        Text("Recommended").font(.caption).foregroundStyle(.secondary)
                    }
                    if let reason = option.disabledReason {
                        Text(reason.text).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .tag(option.tier)
                .disabled(!option.isEnabled)
                .accessibilityElement(children: .combine)
                .accessibilityHint(option.disabledReason?.text ?? "")
            }
        }
        .pickerStyle(.radioGroup)
        .labelsHidden()
    }

    private var tierSelection: Binding<OfflineModelTier> {
        Binding {
            offline.chosenTier ?? .standard
        } set: { tier in
            offline.selectedTier = tier
        }
    }

    // MARK: O3

    @ViewBuilder
    private func downloading(_ state: OfflineOnboardingScreen.DownloadState) -> some View {
        @Bindable var offline = offline
        let name = offline.machine.tier.map(offline.tierName) ?? ""
        hero("arrow.down.circle")
        title("Downloading \(name) model")
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: offline.downloadFraction)
                .progressViewStyle(.linear)
                .accessibilityLabel("Downloading \(name) model")
                .accessibilityValue(offline.progressText)
            Text(downloadStatus(state))
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .frame(maxWidth: 430)
        bodyText("You can close this window. Intake keeps tidying names (Title Case) and filing as usual, and the download continues in the menu bar.")
        Spacer()
        footer {
            if state == .paused {
                Button("Resume") { offline.resumeDownload() }
            } else {
                Button("Pause") { offline.pauseDownload() }
                    .disabled(state == .waitingForNetwork)
            }
        } trailing: {
            Button("Cancel Download") { offline.cancelConfirmationPresented = true }
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        }
    }

    private func downloadStatus(_ state: OfflineOnboardingScreen.DownloadState) -> String {
        switch state {
        case .inProgress:
            return offline.machine.receivedBytes == 0 && offline.machine.resumeOffset > 0
                ? "Resuming…" : offline.progressText
        case .paused:
            return "Paused at \(OfflineModelFormat.bytes(offline.machine.receivedBytes))"
        case .waitingForNetwork:
            return "Paused — waiting for network"
        }
    }

    // MARK: O4

    @ViewBuilder
    private func verifying(selfTesting: Bool) -> some View {
        hero("doc.text.magnifyingglass")
        title("Verifying")
        VStack(alignment: .leading, spacing: 10) {
            checklistRow("Checking the download…", done: selfTesting, current: !selfTesting)
            checklistRow("Testing the model on this Mac…", done: false, current: selfTesting)
        }
        .frame(maxWidth: 430, alignment: .leading)
        Spacer()
        footer { EmptyView() } trailing: { closeButton(prominent: false) }
    }

    private func checklistRow(_ text: String, done: Bool, current: Bool) -> some View {
        HStack(spacing: 8) {
            Group {
                if done {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                } else if current {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "circle").foregroundStyle(.secondary)
                }
            }
            .frame(width: 18)
            Text(text).foregroundStyle(current || done ? .primary : .secondary)
        }
    }

    // MARK: O5

    @ViewBuilder
    private func ready(showsCheckbox: Bool) -> some View {
        Image(systemName: "checkmark.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.green)
            .accessibilityHidden(true)
        title("Offline renaming is on")
        bodyText("New PDFs and images will get clear names from their contents, on this Mac. Change this anytime in Settings › AI.")
        if showsCheckbox {
            Toggle("Use the offline model for renaming", isOn: $useOfflineModel)
                .toggleStyle(.checkbox)
                .onChange(of: useOfflineModel) { _, on in offline.setUseOfflineModel(on) }
        }
        Spacer()
        footer {
            Button("Try on a File…") {
                model.openSettings(pane: .ai)
                dismiss()
            }
        } trailing: {
            Button("Done") {
                if showsCheckbox { offline.setUseOfflineModel(useOfflineModel) }
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
    }

    // MARK: Pieces

    private func hero(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 48))
            .foregroundStyle(.tint)
            .accessibilityHidden(true)
    }

    private var errorHero: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.orange)
            .accessibilityHidden(true)
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
            .multilineTextAlignment(.center)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func bodyText(_ text: String) -> some View {
        Text(text)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 430)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        }
        .font(.callout)
    }

    /// "**Best** — 2.5 GB download · most accurate"
    private func tierLineText(_ line: OfflineTierLine) -> Text {
        Text("\(Text(line.name).bold()) — \(line.detail)")
    }

    private var skipButton: some View {
        Button("Skip for Now") {
            offline.skipForNow()
            dismiss()
        }
        .keyboardShortcut(.cancelAction)
    }

    @ViewBuilder
    private func closeButton(prominent: Bool) -> some View {
        if prominent {
            Button("Close") { dismiss() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
        } else {
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
    }

    private func footer<Leading: View, Trailing: View>(
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            leading()
            Spacer()
            trailing()
        }
    }

    private var meteredTitle: String {
        let size = offline.machine.tier.map { OfflineModelManifest.entry(for: $0).sizeLabel } ?? ""
        return "Download \(size) now?"
    }

    private var meteredBinding: Binding<Bool> {
        Binding {
            if case .confirmingMetered = offline.machine.phase { return true }
            return false
        } set: { _ in }
    }
}

/// Opens the setup window from AppKit-side requests (menu, sheet, notification).
struct OfflineSetupOpenBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: model.offlineModel.setupWindowRequestID) { _, _ in
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: OfflineModelController.setupWindowID)
            }
    }
}
