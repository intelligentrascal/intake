import AppKit
import SwiftUI
import IntakeCore

struct MenuBarLabel: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Image(nsImage: templateIcon)
            .accessibilityLabel(model.menuBarAccessibilityLabel)
            .accessibilityValue(ringAccessibilityValue)
    }

    /// Dense 16pt template glyphs (Watching vs Paused). `MenuBarExtra` follows the
    /// system menu bar; macOS has no supported API to pin extras to the primary
    /// display only (no Thaw-style multi-bar manager). While the offline model
    /// downloads, the glyph sits inside a progress ring; a pending setup
    /// reminder adds a monochrome dot. Both stay part of the template image.
    private var templateIcon: NSImage {
        let name = model.isPaused ? "MenuBarIconPaused" : "MenuBarIconWatching"
        let base = NSImage(named: name) ?? NSImage(size: NSSize(width: 16, height: 16))
        let offline = model.offlineModel
        var ring: MenuBarIconRenderer.Ring?
        if offline.isVerifying {
            ring = .verifying
        } else if offline.machine.isActive {
            ring = .progress(
                Double(offline.ringPercent) / 100,
                paused: offline.isDownloadPaused || offline.isWaitingForNetwork
            )
        }
        return MenuBarIconRenderer.image(base: base, ring: ring, dot: offline.setup.reminderDotPending)
    }

    private var ringAccessibilityValue: String {
        let offline = model.offlineModel
        if offline.isVerifying { return "Verifying model" }
        guard offline.machine.isActive else { return "" }
        if offline.isDownloadPaused || offline.isWaitingForNetwork { return "Downloading model, paused" }
        return "Downloading model, \(offline.ringPercent) percent"
    }
}

/// Draws the menu bar template image: optional download ring around the
/// Watching/Paused glyph (scaled to 56%), optional reminder dot.
nonisolated enum MenuBarIconRenderer {
    enum Ring: Equatable {
        case progress(Double, paused: Bool)
        case verifying
    }

    static func image(base: NSImage, ring: Ring?, dot: Bool) -> NSImage {
        let size = NSSize(width: 16, height: 16)
        let image = NSImage(size: size, flipped: false) { rect in
            let ink = NSColor.black
            if let ring {
                let lineWidth: CGFloat = 1.5
                let circleRect = rect.insetBy(dx: lineWidth / 2, dy: lineWidth / 2)
                let track = NSBezierPath(ovalIn: circleRect)
                track.lineWidth = lineWidth
                ink.withAlphaComponent(0.28).setStroke()
                track.stroke()
                let center = NSPoint(x: rect.midX, y: rect.midY)
                let radius = circleRect.width / 2
                switch ring {
                case .progress(let fraction, let paused):
                    let clamped = min(max(fraction, 0), 1)
                    if clamped > 0 {
                        let arc = NSBezierPath()
                        // From 12 o'clock, clockwise.
                        arc.appendArc(withCenter: center, radius: radius, startAngle: 90, endAngle: 90 - 360 * clamped, clockwise: true)
                        arc.lineWidth = lineWidth
                        arc.lineCapStyle = .round
                        ink.withAlphaComponent(paused ? 0.5 : 1).setStroke()
                        arc.stroke()
                    }
                case .verifying:
                    let dashed = NSBezierPath(ovalIn: circleRect)
                    dashed.lineWidth = lineWidth
                    var pattern: [CGFloat] = [2, 2]
                    dashed.setLineDash(&pattern, count: 2, phase: 0)
                    ink.setStroke()
                    dashed.stroke()
                }
                let glyph = rect.width * 0.56
                base.draw(in: NSRect(x: rect.midX - glyph / 2, y: rect.midY - glyph / 2, width: glyph, height: glyph))
            } else {
                base.draw(in: rect)
            }
            if dot {
                let dotSize: CGFloat = 5
                let dotRect = NSRect(x: rect.maxX - dotSize, y: rect.maxY - dotSize, width: dotSize, height: dotSize)
                // Clear a hairline around the dot so it reads against the glyph.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(ovalIn: dotRect.insetBy(dx: -1, dy: -1)).fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                ink.setFill()
                NSBezierPath(ovalIn: dotRect).fill()
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// The same dot as a small template image for the Set Up menu item.
    static func dotImage() -> NSImage {
        let image = NSImage(size: NSSize(width: 8, height: 8), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1.5, dy: 1.5)).fill()
            return true
        }
        image.isTemplate = true
        return image
    }
}

struct MenuBarContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Text(model.statusTitle)
        Text(model.statusSubtitle)
        Divider()
        OfflineModelMenuItems()
        Button(model.isPaused ? "Resume Organizing" : "Pause Organizing") {
            model.togglePaused()
        }
        OrganizeExistingMenu()
        if !model.recentActivity.isEmpty {
            Divider()
            ForEach(model.recentActivity) { entry in
                Button(menuTitle(for: entry)) {
                    model.reveal(entry)
                }
            }
        }
        Divider()
        Button("Open Activity") {
            model.openActivity()
        }
        Button("Open Cleanup") {
            model.openSettings(pane: .cleanup)
        }
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Send Feedback…") {
            model.openSettings(pane: .feedback)
        }
        Divider()
        Button("Quit Intake") {
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Recent rows for files still waiting on the offline model say so.
    private func menuTitle(for entry: ActivityEntry) -> String {
        if let path = entry.url?.standardizedFileURL.path,
           model.offlineModel.queuedPaths.contains(path) {
            return "\(entry.fileName) · Waiting to rename"
        }
        return entry.menuTitle
    }
}

/// Offline model rows (SPEC §8.4, §8.5, §9.4; PM rulings 2 and 9). Menu style
/// renders only Text / Button / Divider, so progress is a text row and the
/// ring lives in the menu bar icon.
struct OfflineModelMenuItems: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        let offline = model.offlineModel
        if let title = offline.menuDownloadTitle {
            Text(title)
            if !offline.isVerifying {
                if offline.isDownloadPaused {
                    Button("Resume Download") { offline.resumeDownload() }
                } else {
                    Button("Pause Download") { offline.pauseDownload() }
                        .disabled(offline.isWaitingForNetwork)
                }
                Button("Cancel Download…") {
                    offline.openSetup(step: .downloading)
                    offline.cancelConfirmationPresented = true
                }
            }
            Divider()
        } else if offline.showsMenuSetUpItem {
            Button {
                offline.openSetup(step: .recommendation)
            } label: {
                if offline.setup.reminderDotPending {
                    Label {
                        Text("Set Up Offline Renaming…")
                    } icon: {
                        Image(nsImage: MenuBarIconRenderer.dotImage())
                    }
                    .accessibilityLabel("Set Up Offline Renaming, new")
                } else {
                    Text("Set Up Offline Renaming…")
                }
            }
            Divider()
        }
        if !offline.queueItems.isEmpty {
            Text(OfflineRenameQueue.menuLine(count: offline.queueItems.count, reason: offline.queueReason))
            Button(OfflineRenameQueue.renameButtonTitle(count: offline.queueItems.count)) {
                offline.renameNow()
            }
            .disabled(offline.isRenamingQueue)
            Divider()
        }
    }
}

/// Organize Existing… — a plain button with one watch folder, a menu of
/// "All Watch Folders" plus each folder with several.
struct OrganizeExistingMenu: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        Group {
            if model.hasMultipleWatchFolders {
                Menu(OrganizeExistingCopy.menuTitle) {
                    Button("All Watch Folders") {
                        model.requestOrganizeExisting()
                    }
                    Divider()
                    ForEach(model.watchFolderControllers, id: \.profileID) { controller in
                        Button(controller.displayName) {
                            model.requestOrganizeExisting(profileID: controller.profileID)
                        }
                        .disabled(controller.accessLost)
                    }
                }
            } else {
                Button(OrganizeExistingCopy.menuTitle) {
                    model.requestOrganizeExisting()
                }
            }
        }
        .disabled(model.isOrganizeExistingDisabled)
    }
}
