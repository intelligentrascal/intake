import Foundation
import Testing
@testable import IntakeCore

struct FeedbackFormValidationTests {
    @Test
    func requiresNonEmptyTrimmedTitleAndDetails() {
        #expect(FeedbackFormValidation.canSubmit(title: "Bug", details: "Steps") == true)
        #expect(FeedbackFormValidation.canSubmit(title: "  Bug  ", details: "  Steps  ") == true)
        #expect(FeedbackFormValidation.canSubmit(title: "   ", details: "Steps") == false)
        #expect(FeedbackFormValidation.canSubmit(title: "Bug", details: "\n\t") == false)
        #expect(FeedbackFormValidation.canSubmit(title: "", details: "") == false)
    }
}
