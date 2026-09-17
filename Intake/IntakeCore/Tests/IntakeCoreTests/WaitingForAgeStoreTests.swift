import Foundation
import Testing
@testable import IntakeCore

struct WaitingForAgeStoreTests {
    @Test
    func encodeDecodeRoundTripPreservesPathAndStableAt() throws {
        let stableAt = Date(timeIntervalSince1970: 1_700_000_000)
        let pending = [
            PendingStableFile(
                url: URL(fileURLWithPath: "/Users/demo/Downloads/report.pdf"),
                stableAt: stableAt
            ),
            PendingStableFile(
                url: URL(fileURLWithPath: "/Users/demo/Downloads/photo.jpg"),
                stableAt: stableAt.addingTimeInterval(60)
            ),
        ]
        let data = try WaitingForAgeStore.encode(pending)
        let decoded = try WaitingForAgeStore.decode(data)
        #expect(decoded.count == 2)
        #expect(decoded[0].url.path == "/Users/demo/Downloads/report.pdf")
        #expect(decoded[0].stableAt == stableAt)
        #expect(decoded[1].url.lastPathComponent == "photo.jpg")
        #expect(decoded[1].stableAt == stableAt.addingTimeInterval(60))
    }

    @Test
    func userDefaultsSaveLoadAndClear() {
        let suite = "intake.tests.waiting-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let item = PendingStableFile(
            url: URL(fileURLWithPath: "/tmp/watch/a.pdf"),
            stableAt: Date(timeIntervalSince1970: 42)
        )
        WaitingForAgeStore.save([item], to: defaults)
        let loaded = WaitingForAgeStore.load(from: defaults)
        #expect(loaded.count == 1)
        #expect(loaded.first?.url.path == "/tmp/watch/a.pdf")
        #expect(loaded.first?.stableAt == Date(timeIntervalSince1970: 42))

        WaitingForAgeStore.clear(in: defaults)
        #expect(WaitingForAgeStore.load(from: defaults).isEmpty)
        #expect(defaults.data(forKey: WaitingForAgeStore.defaultsKey) == nil)
    }

    @Test
    func saveEmptyClearsKey() {
        let suite = "intake.tests.waiting-empty-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        WaitingForAgeStore.save(
            [PendingStableFile(url: URL(fileURLWithPath: "/tmp/x"), stableAt: Date())],
            to: defaults
        )
        #expect(defaults.data(forKey: WaitingForAgeStore.defaultsKey) != nil)
        WaitingForAgeStore.save([], to: defaults)
        #expect(defaults.data(forKey: WaitingForAgeStore.defaultsKey) == nil)
    }

    @Test
    func restoreExistingKeepsOnlyRootFilesThatStillExist() {
        let root = URL(fileURLWithPath: "/tmp/watch-root")
        let kept = PendingStableFile(
            url: root.appendingPathComponent("kept.pdf"),
            stableAt: Date(timeIntervalSince1970: 1)
        )
        let missing = PendingStableFile(
            url: root.appendingPathComponent("gone.pdf"),
            stableAt: Date(timeIntervalSince1970: 2)
        )
        let nested = PendingStableFile(
            url: root.appendingPathComponent("Documents").appendingPathComponent("nested.pdf"),
            stableAt: Date(timeIntervalSince1970: 3)
        )
        // Compare standardized paths — on macOS `/tmp` → `/private/tmp`.
        let existing: Set<String> = [kept.url.standardizedFileURL.path]
        let restored = WaitingForAgeStore.restoreExisting(
            stored: [kept, missing, nested],
            watchRoot: root
        ) { url in
            existing.contains(url.standardizedFileURL.path)
        }
        #expect(restored.count == 1)
        #expect(restored.first?.url.lastPathComponent == "kept.pdf")
    }

    @Test
    func defaultsKeyIsStableProductKey() {
        #expect(WaitingForAgeStore.defaultsKey == "intake.waitingForAge")
    }
}
