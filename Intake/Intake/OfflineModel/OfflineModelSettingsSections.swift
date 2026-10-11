import AppKit
import SwiftUI
import IntakeCore

/// Settings › AI › "Offline model" card and "Run the offline model" (SPEC
/// §8.4, §9.4, §11, §13). Native Form rows only. Model names appear only in
/// "About this model".
struct OfflineModelSettingsSections: View {
    @Environment(AppModel.self) private var model
    @State private var showsDeleteConfirmation = false
    @State private var showsCancelConfirmation = false

    private var offline: OfflineModelController { model.offlineModel }

    var body: some View {
        Section {
            card
        } header: {
            Text("Offline model")
        }
        .alert(deleteTitle, isPresented: $showsDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
            Button("Delete Model", role: .destructive) { offline.deleteModel() }
        } message: {
            Text(deleteMessage)
        }
        .alert("Cancel the download?", isPresented: $showsCancelConfirmation) {
            Button("Cancel Download", role: .destructive) { offline.cancelDownload() }
            Button("Keep Downloading", role: .cancel) {}
                .keyboardShortcut(.defaultAction)
        } message: {
            Text("You can resume it from Settings within 24 hours.")
        }
        if offline.isModelInstalled {
            runSettingSection
        }
    }

    // MARK: Card

    @ViewBuilder
    private var card: some View {
        if offline.isUnsupported {
            Label(OfflineModelRecommendation.unsupportedTitle, systemImage: "cpu")
                .font(.headline)
            Text(OfflineModelRecommendation.unsupportedMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else if offline.isVerifying {
            tierHeader(offline.machine.tier)
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking the download…").foregroundStyle(.secondary)
            }
        } else if offline.machine.isActive {
            downloadingRows
        } else if let tier = offline.setup.installedTier, let problem = offline.modelProblem {
            tierHeader(tier)
            switch problem {
            case .damaged:
                warning("The model file is missing or damaged. Download it again.")
                Button("Download \(OfflineModelManifest.entry(for: tier).sizeLabel)") { download(tier) }
            case .loadFailed:
                warning("The model couldn't start. Try a smaller size.")
                changeSizeMenu(current: tier)
            }
        } else if let entry = offline.installedEntry {
            readyRows(entry)
        } else {
            notDownloadedRows
        }
    }

    @ViewBuilder
    private func readyRows(_ entry: OfflineModelManifestEntry) -> some View {
        tierHeader(entry.tier)
        Text("\(entry.sizeLabel) on disk · Runs on this Mac. File contents never leave it.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        LabeledContent("Status") {
            Text(offline.isModelLoaded ? "In memory" : "Unloaded to save memory")
        }
        if !offline.queueItems.isEmpty {
            LabeledContent {
                Button(OfflineRenameQueue.renameButtonTitle(count: offline.queueItems.count)) {
                    offline.renameNow()
                }
                .disabled(offline.isRenamingQueue)
            } label: {
                Text(OfflineRenameQueue.settingsLine(count: offline.queueItems.count, reason: offline.queueReason))
                if offline.queueReason == .waitingForPower, offline.runSetting == .smart {
                    Text("On battery, Smart renames single new files and saves the rest for when you plug in.")
                }
            }
        }
        if let note = offline.overflowNote {
            Text(note).font(.callout).foregroundStyle(.secondary)
        }
        HStack {
            changeSizeMenu(current: entry.tier)
            Button("Delete Model") { showsDeleteConfirmation = true }
        }
        LabeledContent("About this model") {
            HStack(spacing: 6) {
                Text("\(entry.modelName) · \(entry.license)")
                Link("View", destination: entry.licenseURL)
            }
        }
    }

    @ViewBuilder
    private var downloadingRows: some View {
        let state = offline.machine.phase
        tierHeader(offline.machine.tier)
        ProgressView(value: offline.downloadFraction)
            .progressViewStyle(.linear)
            .accessibilityLabel("Downloading \(offline.machine.tier.map(offline.tierName) ?? "") model")
            .accessibilityValue(offline.progressText)
        Text(statusLine(state))
            .font(.callout)
            .foregroundStyle(.secondary)
            .monospacedDigit()
        HStack {
            if offline.isDownloadPaused {
                Button("Resume") { offline.resumeDownload() }
            } else {
                Button("Pause") { offline.pauseDownload() }
                    .disabled(offline.isWaitingForNetwork)
            }
            Button("Cancel Download…") { showsCancelConfirmation = true }
        }
    }

    private func statusLine(_ phase: OfflineModelDownloadMachine.Phase) -> String {
        switch phase {
        case .paused(_, let bytes): "Paused at \(OfflineModelFormat.bytes(bytes))"
        case .waitingForNetwork: "Paused — waiting for network"
        case .waitingForUnmetered: "Waiting for Wi-Fi"
        default: offline.progressText
        }
    }

    @ViewBuilder
    private var notDownloadedRows: some View {
        let recommended = offline.recommendation?.recommendedTier
        if let partial = offline.resumablePartial {
            tierHeader(partial.tier)
            Text("Download cancelled. You can resume it until \(partial.cancelledAt.addingTimeInterval(RetainedPartialDownload.retention).formatted(date: .omitted, time: .shortened)).")
                .foregroundStyle(.secondary)
            Button("Resume Download") { download(partial.tier) }
                .buttonStyle(.borderedProminent)
        } else if let recommended {
            let entry = OfflineModelManifest.entry(for: recommended)
            Text("Rename files from their contents on this Mac, offline. \(Text("Recommended: \(offline.tierName(recommended)), \(entry.sizeLabel).").bold())")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("Download \(entry.sizeLabel)") { download(recommended) }
                    .buttonStyle(.borderedProminent)
                if offline.architecture == .appleSilicon {
                    otherSizesMenu(title: "Other Sizes…", excluding: recommended)
                }
            }
        } else if let message = offline.recommendation?.noSpaceMessage {
            warning("\(message) \(OfflineModelRecommendation.noSpaceNoneMessage)")
            Button("Try Again") { offline.refreshHardware() }
        } else {
            Text("Checking this Mac…").foregroundStyle(.secondary)
                .task { offline.refreshHardware() }
        }
    }

    private func changeSizeMenu(current: OfflineModelTier) -> some View {
        otherSizesMenu(title: "Change Size…", excluding: current)
            .disabled(offline.architecture == .intel)
    }

    private func otherSizesMenu(title: String, excluding: OfflineModelTier) -> some View {
        Menu(title) {
            ForEach(offline.recommendation?.options ?? []) { option in
                if option.tier != excluding {
                    Button {
                        download(option.tier)
                    } label: {
                        Text(option.line.text)
                        if let reason = option.disabledReason {
                            Text(reason.text)
                        }
                    }
                    .disabled(!option.isEnabled)
                }
            }
        }
        .fixedSize()
    }

    private func download(_ tier: OfflineModelTier) {
        offline.startDownload(tier)
        // The metered question and low-space detail live in the setup window.
        switch offline.machine.phase {
        case .confirmingMetered, .idle, .failed:
            offline.openSetup(step: .recommendation)
        default:
            break
        }
    }

    // MARK: Run setting

    private var runSettingSection: some View {
        @Bindable var offline = offline
        return Section {
            Picker("Run the offline model", selection: $offline.runSetting) {
                ForEach(OfflineModelRunSetting.allCases) { setting in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(setting.title)
                        Text(setting.help)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .tag(setting)
                    .padding(.vertical, 2)
                }
            }
            .pickerStyle(.radioGroup)
            .labelsHidden()
        } header: {
            Text("Run the offline model")
        }
    }

    // MARK: Pieces

    private func tierHeader(_ tier: OfflineModelTier?) -> some View {
        Label {
            Text(tier.map(offline.tierName) ?? "Offline model").font(.headline)
        } icon: {
            Image(systemName: gaugeSymbol(tier))
        }
    }

    private func gaugeSymbol(_ tier: OfflineModelTier?) -> String {
        switch tier {
        case .lite: "gauge.with.dots.needle.33percent"
        case .standard: "gauge.with.dots.needle.50percent"
        case .best: "gauge.with.dots.needle.67percent"
        case nil: "gauge.with.dots.needle.0percent"
        }
    }

    private func warning(_ text: String) -> some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(IntakeColor.warning)
        }
        .font(.callout)
    }

    private var deleteTitle: String {
        let name = offline.setup.installedTier.map(offline.tierName) ?? ""
        return "Delete the \(name) model?"
    }

    private var deleteMessage: String {
        let size = offline.installedEntry?.sizeLabel ?? ""
        return "This frees \(size). New files keep getting tidy Title Case names until you download a model again."
    }
}

/// One-time sheet on the Settings window for people updating to 1.4
/// (SPEC §8.5, PM ruling 1): Set Up… / Not Now. No checkbox here.
struct OfflineUpgradeSheet: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("New: rename files offline")
                .font(.title2.bold())
            Text("Intake can now name PDFs and images from their contents with a model that runs on this Mac. Nothing is uploaded.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 400)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not Now") { model.offlineModel.upgradeSheetChoseNotNow() }
                    .keyboardShortcut(.cancelAction)
                Button("Set Up…") { model.offlineModel.upgradeSheetChoseSetUp() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }
}
