import Foundation
import Testing
@testable import IntakeCore

struct NotificationPreferencesTests {
    @Test
    func masterDefaultsToOffWhenNothingStored() {
        #expect(NotificationPreferences.isMasterEnabled(nil) == false)
    }

    @Test
    func perTypeTogglesDefaultToOnWhenNothingStored() {
        #expect(NotificationPreferences.isFiledEnabled(nil))
        #expect(NotificationPreferences.isErrorsEnabled(nil))
        #expect(NotificationPreferences.isCleanupEnabled(nil))
    }

    @Test
    func roundTripsThroughUserDefaults() {
        let suiteName = "intake.tests.notifications.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        #expect(NotificationPreferences.isMasterEnabled(in: defaults) == false)
        #expect(NotificationPreferences.isFiledEnabled(in: defaults))
        #expect(NotificationPreferences.isErrorsEnabled(in: defaults))
        #expect(NotificationPreferences.isCleanupEnabled(in: defaults))

        NotificationPreferences.persistMaster(true, to: defaults)
        NotificationPreferences.persistFiled(false, to: defaults)
        NotificationPreferences.persistErrors(false, to: defaults)
        NotificationPreferences.persistCleanup(false, to: defaults)

        #expect(NotificationPreferences.isMasterEnabled(in: defaults))
        #expect(NotificationPreferences.isFiledEnabled(in: defaults) == false)
        #expect(NotificationPreferences.isErrorsEnabled(in: defaults) == false)
        #expect(NotificationPreferences.isCleanupEnabled(in: defaults) == false)
    }
}
