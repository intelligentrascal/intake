import Foundation
import Testing
@testable import IntakeCore

struct AutomaticOrganizingPreferenceTests {
    @Test
    func defaultsToOnWhenNothingIsStored() {
        #expect(AutomaticOrganizingPreference.isEnabled(automaticOrganizing: nil, legacyPaused: nil))
    }

    @Test
    func migratesLegacyPausedOffToAutomaticOn() {
        #expect(
            AutomaticOrganizingPreference.isEnabled(automaticOrganizing: nil, legacyPaused: false)
        )
    }

    @Test
    func migratesLegacyPausedOnToAutomaticOff() {
        #expect(
            AutomaticOrganizingPreference.isEnabled(automaticOrganizing: nil, legacyPaused: true)
                == false
        )
    }

    @Test
    func prefersTheNewKeyOverLegacyPaused() {
        #expect(
            AutomaticOrganizingPreference.isEnabled(automaticOrganizing: true, legacyPaused: true)
        )
        #expect(
            AutomaticOrganizingPreference.isEnabled(automaticOrganizing: false, legacyPaused: false)
                == false
        )
    }

    @Test
    func roundTripsThroughUserDefaultsAndKeepsLegacyMirror() {
        let defaults = UserDefaults(suiteName: "intake.tests.automatic-organizing.\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.persistentDomainName()!) }

        defaults.set(true, forKey: AutomaticOrganizingPreference.legacyPausedKey)
        #expect(AutomaticOrganizingPreference.isEnabled(in: defaults) == false)

        AutomaticOrganizingPreference.persist(true, to: defaults)
        #expect(defaults.bool(forKey: AutomaticOrganizingPreference.currentKey))
        #expect(defaults.bool(forKey: AutomaticOrganizingPreference.legacyPausedKey) == false)
        #expect(AutomaticOrganizingPreference.isEnabled(in: defaults))
    }
}

private extension UserDefaults {
    func persistentDomainName() -> String? {
        // suiteName is not exposed; tests pass the same UUID they constructed.
        dictionaryRepresentation().isEmpty ? nil : identifierHint
    }

    private var identifierHint: String? {
        object(forKey: AutomaticOrganizingPreference.currentKey) == nil
            && object(forKey: AutomaticOrganizingPreference.legacyPausedKey) == nil
            ? nil
            : "suite"
    }
}
