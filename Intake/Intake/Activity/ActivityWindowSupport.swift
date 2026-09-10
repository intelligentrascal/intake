import AppKit
import SwiftUI

enum IntakeSceneID {
    static let activity = "activity"
}

extension Notification.Name {
    static let intakeOpenActivity = Notification.Name("intake.openActivity")
}

extension NSWindow {
    var isIntakeActivityWindow: Bool {
        identifier?.rawValue == IntakeSceneID.activity
    }
}

/// Stamps the SwiftUI Activity window so Dock reopen can find it without duplicates.
struct ActivityWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.identifier = NSUserInterfaceItemIdentifier(IntakeSceneID.activity)
            window.minSize = NSSize(width: 520, height: 420)
            window.setFrameAutosaveName("intake.activity")
            window.isReleasedWhenClosed = false
            window.title = "Activity"
        }
    }
}

/// Former AppKit hosting fallback removed — it SEGVd (objc_retain) on macOS 26.
/// Do not restore an `NSHostingController` path here. Activity opens only via
/// SwiftUI `openWindow` / `openActivity()`, never as a launch/reopen surface.
@MainActor
enum ActivityWindowFallback {
    static func presentIfPossible() {
        if let existing = NSApp.windows.first(where: \.isIntakeActivityWindow) {
            if existing.isMiniaturized {
                existing.deminiaturize(nil)
            }
            existing.makeKeyAndOrderFront(nil)
        }
        // Safe no-op when no SwiftUI Activity window exists yet.
    }
}

/// Bridges AppKit reopen / Dock clicks to SwiftUI `openWindow(id:)`.
struct ActivityWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(AppModel.self) private var model

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onChange(of: model.activityWindowRequestID) { _, _ in
                openWindow(id: IntakeSceneID.activity)
            }
            .onReceive(NotificationCenter.default.publisher(for: .intakeOpenActivity)) { _ in
                openWindow(id: IntakeSceneID.activity)
            }
    }
}
