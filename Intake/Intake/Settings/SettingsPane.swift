import SwiftUI

enum SettingsPane: String, CaseIterable, Identifiable, Hashable {
    case general
    case rules
    case cleanup
    case activity
    case ai
    case feedback
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .rules: "Rules"
        case .cleanup: "Cleanup"
        case .activity: "Activity"
        case .ai: "AI"
        case .feedback: "Feedback"
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .rules: "list.bullet.rectangle"
        case .cleanup: "clock.arrow.circlepath"
        case .activity: "list.bullet.clipboard"
        case .ai: "sparkles"
        case .feedback: "bubble.left.and.bubble.right"
        case .about: "info.circle"
        }
    }
}
