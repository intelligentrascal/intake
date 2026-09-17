import Foundation

/// Shared enablement rules for the Feedback → GitHub Issue form.
public enum FeedbackFormValidation: Sendable {
    public static func canSubmit(title: String, details: String) -> Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
