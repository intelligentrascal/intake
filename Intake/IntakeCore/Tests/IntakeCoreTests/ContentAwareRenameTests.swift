import Foundation
import Testing
@testable import IntakeCore

// MARK: Fakes

private struct FakeExtractor: ContentTextExtractor {
    var text: String?
    func text(from url: URL, maximumCharacters: Int) async -> String? {
        text.map { String($0.prefix(maximumCharacters)) }
    }
}

private struct FakeNamer: ContentNamer {
    var result: ContentNamingFields?
    func fields(for input: ContentNamingInput) async -> ContentNamingFields? {
        result
    }
}

/// Records what the namer was given, to prove the text cap.
private actor InputRecorder {
    var inputs: [ContentNamingInput] = []
    func record(_ input: ContentNamingInput) { inputs.append(input) }
}

private struct RecordingNamer: ContentNamer {
    let recorder: InputRecorder
    var result: ContentNamingFields?
    func fields(for input: ContentNamingInput) async -> ContentNamingFields? {
        await recorder.record(input)
        return result
    }
}

private let invoiceFields = ContentNamingFields(
    date: "2026-09-14",
    documentType: "invoice",
    organization: "ACME",
    subject: "September hosting",
    confidence: 0.9
)

private func makeTempWatchFolder() throws -> URL {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
        "intake-content-rename-\(UUID().uuidString)",
        isDirectory: true
    )
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
}

// MARK: Template rendering + validation

struct ContentNameTemplateTests {
    @Test
    func defaultTemplateRendersDateTypeOrganization() {
        let template = ContentNameTemplate()
        #expect(
            template.outcome(for: invoiceFields, currentFileName: "Inv 88123.pdf")
                == .accepted("2026-09-14 Invoice ACME.pdf")
        )
    }

    @Test
    func allTokensIncludingOriginalRender() {
        let template = ContentNameTemplate(template: "{date} - {type} - {organization} - {subject} ({original})")
        let base = template.renderBaseName(fields: invoiceFields, originalBaseName: "Inv 88123")
        #expect(base == "2026-09-14 - Invoice - ACME - September Hosting (Inv 88123)")
    }

    @Test
    func emptyTokensAndDanglingSeparatorsAreDropped() {
        let template = ContentNameTemplate(template: "{date} - {type} - {organization}")
        let noDate = ContentNamingFields(documentType: "Receipt", organization: "Blue Bottle", confidence: 0.9)
        #expect(template.renderBaseName(fields: noDate, originalBaseName: "x") == "Receipt - Blue Bottle")

        let noMiddle = ContentNamingFields(date: "2026-01-02", organization: "Blue Bottle", confidence: 0.9)
        #expect(template.renderBaseName(fields: noMiddle, originalBaseName: "x") == "2026-01-02 - Blue Bottle")

        let onlyFirst = ContentNamingFields(date: "2026-01-02", documentType: "Statement", confidence: 0.9)
        #expect(template.renderBaseName(fields: onlyFirst, originalBaseName: "x") == "2026-01-02 - Statement")

        let placeholders = ContentNamingFields(
            date: "", documentType: "Statement", organization: "N/A", subject: "  ", confidence: 0.9
        )
        #expect(ContentNameTemplate().renderBaseName(fields: placeholders, originalBaseName: "x") == "Statement")
    }

    @Test
    func unknownTokensAreRemovedNotLeaked() {
        let template = ContentNameTemplate(template: "{type} {bogus} {organization}")
        #expect(template.renderBaseName(fields: invoiceFields, originalBaseName: "x") == "Invoice ACME")
    }

    @Test
    func datesMustBeRealISODates() {
        #expect(ContentNameTemplate.validatedISODate("2026-09-14") == "2026-09-14")
        #expect(ContentNameTemplate.validatedISODate("2024-02-29") == "2024-02-29")
        #expect(ContentNameTemplate.validatedISODate("2025-02-29") == nil)
        #expect(ContentNameTemplate.validatedISODate("2026-13-01") == nil)
        #expect(ContentNameTemplate.validatedISODate("2026-04-31") == nil)
        #expect(ContentNameTemplate.validatedISODate("14/09/2026") == nil)
        #expect(ContentNameTemplate.validatedISODate("September 14, 2026") == nil)
        #expect(ContentNameTemplate.validatedISODate("2026-9-14") == nil)
        #expect(ContentNameTemplate.validatedISODate("0001-01-01") == nil)

        var fields = invoiceFields
        fields.date = "2026-02-30"
        #expect(
            ContentNameTemplate().outcome(for: fields, currentFileName: "a.pdf")
                == .accepted("Invoice ACME.pdf")
        )
    }

    @Test
    func pathSeparatorsAndControlCharactersAreStripped() {
        let fields = ContentNamingFields(
            date: "2026-09-14",
            documentType: "Invoice\n\t",
            organization: "../Acme/Corp:Ltd\u{0007}",
            confidence: 0.9
        )
        let outcome = ContentNameTemplate().outcome(for: fields, currentFileName: "a.pdf")
        let name = try? #require(outcome.acceptedFileName)
        #expect(name == "2026-09-14 Invoice Acme Corp Ltd.pdf")
        #expect(name?.contains("/") == false)
        #expect(name?.contains(":") == false)
        #expect(name?.hasPrefix(".") == false)
    }

    @Test
    func lengthIsCappedAtAWordBoundaryAndExtensionKept() {
        let fields = ContentNamingFields(
            documentType: "Agreement",
            organization: "The Extraordinarily Long Named International Holding Company of Greater Metropolitan Areas",
            subject: nil,
            confidence: 0.95
        )
        let name = ContentNameTemplate().outcome(for: fields, currentFileName: "x.pdf").acceptedFileName
        let unwrapped = try? #require(name)
        #expect(unwrapped?.hasSuffix(".pdf") == true)
        let base = String(unwrapped?.dropLast(4) ?? "")
        #expect(base.count <= ContentNameTemplate.maximumBaseNameLength)
        #expect(base.hasSuffix(" ") == false)
        #expect(base.hasPrefix("Agreement The Extraordinarily"))
    }

    @Test
    func normalizerCleanupAppliesButShortAcronymsSurvive() {
        let fields = ContentNamingFields(
            documentType: "tax_form",
            organization: "IRS",
            subject: "w2 SUMMARY",
            confidence: 0.9
        )
        let template = ContentNameTemplate(template: "{type} {organization} {subject}")
        #expect(template.renderBaseName(fields: fields, originalBaseName: "x") == "Tax Form IRS W2 Summary")
    }

    @Test
    func rejectsNilLowConfidenceEmptyAndGeneric() {
        let template = ContentNameTemplate()
        #expect(template.outcome(for: nil, currentFileName: "a.pdf") == .rejected(.noResult))

        var low = invoiceFields
        low.confidence = 0.3
        #expect(template.outcome(for: low, currentFileName: "a.pdf") == .rejected(.lowConfidence))

        var nan = invoiceFields
        nan.confidence = .nan
        #expect(template.outcome(for: nan, currentFileName: "a.pdf") == .rejected(.lowConfidence))

        let empty = ContentNamingFields(subject: "Something", confidence: 0.9)
        #expect(template.outcome(for: empty, currentFileName: "a.pdf") == .rejected(.empty))

        let generic = ContentNamingFields(date: "2026-09-14", documentType: "Document", organization: "Unknown", confidence: 0.9)
        #expect(template.outcome(for: generic, currentFileName: "a.pdf") == .rejected(.generic))

        let dateOnly = ContentNamingFields(date: "2026-09-14", confidence: 0.9)
        #expect(template.outcome(for: dateOnly, currentFileName: "a.pdf") == .rejected(.generic))
    }

    @Test
    func emptyTemplateFallsBackToDefault() {
        #expect(ContentNameTemplate(template: "   ").template == ContentNameTemplate.defaultTemplate)
    }
}

// MARK: Settings

struct ContentAwareRenameSettingsTests {
    @Test
    func offByDefaultWithPDFAndImages() {
        let settings = ContentAwareRenameSettings()
        #expect(settings.isEnabled == false)
        #expect(settings.fileTypes == [.pdf, .images])
        #expect(settings.template == "{date} {type} {organization}")
        #expect(settings.isEligible(URL(fileURLWithPath: "/tmp/a.pdf")) == false)
    }

    @Test
    func eligibilityFollowsSelectedTypes() {
        var settings = ContentAwareRenameSettings(isEnabled: true, fileTypes: [.pdf])
        #expect(settings.isEligible(URL(fileURLWithPath: "/tmp/a.PDF")))
        #expect(settings.isEligible(URL(fileURLWithPath: "/tmp/a.png")) == false)
        #expect(settings.isEligible(URL(fileURLWithPath: "/tmp/a.zip")) == false)
        settings.fileTypes = [.images]
        #expect(settings.isEligible(URL(fileURLWithPath: "/tmp/a.heic")))
    }

    @Test
    func roundTripsThroughUserDefaultsAndMissingKeyIsDefault() {
        let suite = "intake.tests.content-aware.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ContentAwareRenameSettings.load(from: defaults) == ContentAwareRenameSettings())

        let custom = ContentAwareRenameSettings(isEnabled: true, fileTypes: [.images], template: "{type} {subject}")
        custom.save(to: defaults)
        #expect(ContentAwareRenameSettings.load(from: defaults) == custom)
    }

    @Test
    func providerDefaultsToOnDeviceAndRoundTrips() {
        let suite = "intake.tests.content-aware.provider.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ContentAwareRenameSettings.load(from: defaults).provider == .onDevice)

        let openRouter = ContentAwareRenameSettings(
            isEnabled: true,
            provider: .openRouter,
            fileTypes: [.pdf],
            template: "{date} {type}"
        )
        openRouter.save(to: defaults)
        let loaded = ContentAwareRenameSettings.load(from: defaults)
        #expect(loaded.provider == .openRouter)
        #expect(loaded.isEnabled)
        #expect(loaded.fileTypes == [.pdf])

        // Legacy JSON without provider key stays on-device.
        let legacy = #"{"isEnabled":true,"fileTypes":["pdf"],"template":"{date}"}"#.data(using: .utf8)!
        defaults.set(legacy, forKey: ContentAwareRenameSettings.defaultsKey)
        #expect(ContentAwareRenameSettings.load(from: defaults).provider == .onDevice)
    }
}

// MARK: Renamer (extract → name → validate)

struct ContentAwareRenamerTests {
    private let enabled = ContentAwareRenameSettings(isEnabled: true)

    @Test
    func invoicePDFGetsAContentName() async throws {
        let root = try makeTempWatchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("Inv 88123.pdf")
        try Data("%PDF".utf8).write(to: file)

        let renamer = ContentAwareRenamer(
            settings: enabled,
            extractor: FakeExtractor(text: "ACME Corp — Invoice #88123 — 14 September 2026"),
            namer: FakeNamer(result: invoiceFields)
        )
        #expect(await renamer.proposal(for: file) == .proposed("2026-09-14 Invoice ACME.pdf"))
    }

    @Test
    func fallsBackWhenOffUnselectedEmptyOrNoText() async throws {
        let root = try makeTempWatchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("a.pdf")
        try Data("%PDF".utf8).write(to: pdf)
        let zip = root.appendingPathComponent("a.zip")
        try Data("PK".utf8).write(to: zip)
        let placeholder = root.appendingPathComponent("empty.pdf")
        try Data().write(to: placeholder)

        let off = ContentAwareRenamer(
            settings: ContentAwareRenameSettings(),
            extractor: FakeExtractor(text: "x"),
            namer: FakeNamer(result: invoiceFields)
        )
        #expect(await off.proposal(for: pdf) == .fallback(.notEligible))

        let on = ContentAwareRenamer(
            settings: enabled,
            extractor: FakeExtractor(text: "x"),
            namer: FakeNamer(result: invoiceFields)
        )
        #expect(await on.proposal(for: zip) == .fallback(.notEligible))
        #expect(await on.proposal(for: placeholder) == .fallback(.unreadable))
        #expect(await on.proposal(for: root.appendingPathComponent("gone.pdf")) == .fallback(.unreadable))

        let blank = ContentAwareRenamer(
            settings: enabled,
            extractor: FakeExtractor(text: "   \n"),
            namer: FakeNamer(result: invoiceFields)
        )
        #expect(await blank.proposal(for: pdf) == .fallback(.noText))
    }

    @Test
    func fallsBackOnNilAndLowConfidence() async throws {
        let root = try makeTempWatchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("a.pdf")
        try Data("%PDF".utf8).write(to: pdf)

        let none = ContentAwareRenamer(settings: enabled, extractor: FakeExtractor(text: "hi"), namer: FakeNamer(result: nil))
        #expect(await none.proposal(for: pdf) == .fallback(.rejected(.noResult)))

        var low = invoiceFields
        low.confidence = 0.2
        let unsure = ContentAwareRenamer(settings: enabled, extractor: FakeExtractor(text: "hi"), namer: FakeNamer(result: low))
        #expect(await unsure.proposal(for: pdf) == .fallback(.rejected(.lowConfidence)))
    }

    @Test
    func extractedTextIsCappedBeforeReachingTheNamer() async throws {
        let root = try makeTempWatchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("a.pdf")
        try Data("%PDF".utf8).write(to: pdf)
        let recorder = InputRecorder()
        let renamer = ContentAwareRenamer(
            settings: enabled,
            extractor: FakeExtractor(text: String(repeating: "a", count: 20_000)),
            namer: RecordingNamer(recorder: recorder, result: invoiceFields)
        )
        _ = await renamer.proposal(for: pdf)
        let inputs = await recorder.inputs
        #expect(inputs.count == 1)
        #expect(inputs.first?.text.count == ContentNamingInput.maximumTextCharacters)
        #expect(inputs.first?.facts.fileExtension == "pdf")
    }

    @Test
    func originalTokenUsesTheOverriddenCurrentName() async throws {
        let root = try makeTempWatchFolder()
        defer { try? FileManager.default.removeItem(at: root) }
        let pdf = root.appendingPathComponent("inv_88123.pdf")
        try Data("%PDF".utf8).write(to: pdf)
        let renamer = ContentAwareRenamer(
            settings: ContentAwareRenameSettings(isEnabled: true, template: "{type} {original}"),
            extractor: FakeExtractor(text: "x"),
            namer: FakeNamer(result: invoiceFields)
        )
        #expect(
            await renamer.proposal(for: pdf, currentFileName: "Inv 88123.pdf")
                == .proposed("Invoice Inv 88123.pdf")
        )
    }
}

// MARK: Pipeline seam: content rename, Activity, Undo, collisions

struct ContentAwareIngestPipelineTests {
    @Test
    func contentRenameAfterTitleCaseWritesASecondRenamedRowAndUndoRestores() async throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let download = root.appendingPathComponent("inv_88123.pdf")
        try Data("%PDF-1.7 invoice".utf8).write(to: download)

        let pipeline = IngestPipeline(watchFolder: root)
        let titleCase = try pipeline.applyRenameInPlace(at: download, fileManager: fileManager)
        #expect(titleCase.url.lastPathComponent == "Inv 88123.pdf")
        #expect(titleCase.entries.first?.renameSource == .titleCase)

        let renamer = ContentAwareRenamer(
            settings: ContentAwareRenameSettings(isEnabled: true),
            extractor: FakeExtractor(text: "ACME invoice"),
            namer: FakeNamer(result: invoiceFields)
        )
        let proposed = try #require(await renamer.proposal(for: titleCase.url).fileName)
        let content = try pipeline.applyContentRename(at: titleCase.url, to: proposed, fileManager: fileManager)

        #expect(content.url.lastPathComponent == "2026-09-14 Invoice ACME.pdf")
        let entry = try #require(content.entries.first)
        #expect(entry.kind == .renamed)
        #expect(entry.renameSource == .contentAware)
        #expect(entry.beforePath == titleCase.url.path)
        #expect(entry.afterPath == content.url.path)

        var undo = UndoService()
        for row in titleCase.entries + content.entries {
            undo.push(try #require(UndoService.makeAction(from: row)))
        }
        #expect(undo.performLast(fileManager: fileManager) == .success(restoredURL: titleCase.url.standardizedFileURL))
        #expect(fileManager.fileExists(atPath: titleCase.url.path))
        #expect(undo.performLast(fileManager: fileManager) == .success(restoredURL: download.standardizedFileURL))
        #expect(fileManager.fileExists(atPath: download.path))
    }

    @Test
    func contentRenameRespectsCaseInsensitiveCollisionsAndKeepsExtension() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let holder = root.appendingPathComponent("2026-09-14 invoice acme.pdf")
        try Data("other".utf8).write(to: holder)
        let file = root.appendingPathComponent("Inv 88123.pdf")
        try Data("mine".utf8).write(to: file)

        let pipeline = IngestPipeline(watchFolder: root)
        // A proposal with a different (or no) extension still keeps the real one.
        let result = try pipeline.applyContentRename(
            at: file,
            to: "2026-09-14 Invoice ACME.txt",
            fileManager: fileManager
        )
        #expect(result.url.lastPathComponent == "2026-09-14 Invoice ACME 2.pdf")
        #expect(fileManager.fileExists(atPath: holder.path))
    }

    @Test
    func caseOnlyContentRenameDoesNotCollideWithItself() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("invoice acme.pdf")
        try Data("mine".utf8).write(to: file)
        let result = try IngestPipeline(watchFolder: root)
            .applyContentRename(at: file, to: "Invoice ACME.pdf", fileManager: fileManager)
        #expect(result.url.lastPathComponent == "Invoice ACME.pdf")
    }

    @Test
    func alreadyFiledFileIsRenamedInPlaceInItsCategoryFolder() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("Inv 88123.pdf")
        try Data("%PDF".utf8).write(to: file)
        let pipeline = IngestPipeline(watchFolder: root)
        let moved = try pipeline.applyRoute(at: file, fileManager: fileManager)
        let filed = try #require(moved.first?.url)
        #expect(filed.deletingLastPathComponent().lastPathComponent == "Documents")

        let result = try pipeline.applyContentRename(
            at: filed,
            to: "2026-09-14 Invoice ACME.pdf",
            fileManager: fileManager
        )
        #expect(result.url.deletingLastPathComponent().standardizedFileURL == filed.deletingLastPathComponent().standardizedFileURL)
        #expect(result.url.lastPathComponent == "2026-09-14 Invoice ACME.pdf")
        #expect(result.entries.first?.destinationFolder == "Documents")
        #expect(result.entries.first?.renameSource == .contentAware)
    }

    @Test
    func writeGateAndOutsideFilesAreLeftAlone() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        let outside = try makeTempWatchFolder()
        defer {
            try? fileManager.removeItem(at: root)
            try? fileManager.removeItem(at: outside)
        }
        let empty = root.appendingPathComponent("empty.pdf")
        try Data().write(to: empty)
        let stranger = outside.appendingPathComponent("a.pdf")
        try Data("x".utf8).write(to: stranger)
        let pipeline = IngestPipeline(watchFolder: root)

        #expect(try pipeline.applyContentRename(at: empty, to: "Invoice ACME.pdf", fileManager: fileManager).entries.isEmpty)
        #expect(fileManager.fileExists(atPath: empty.path))
        #expect(try pipeline.applyContentRename(at: stranger, to: "Invoice ACME.pdf", fileManager: fileManager).entries.isEmpty)
        #expect(fileManager.fileExists(atPath: stranger.path))
    }

    @Test
    func rulesSeeTheContentNameWhenFilingAfterIt() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let file = root.appendingPathComponent("Scan 0001.pdf")
        try Data("%PDF".utf8).write(to: file)
        let invoices = RoutingRule(
            id: "custom-invoices",
            folderName: "Invoices",
            extensions: ["pdf"],
            conditions: [.nameContains("invoice")]
        )
        let pipeline = IngestPipeline(watchFolder: root, rules: [invoices] + DefaultTaxonomy.rules)

        let content = try pipeline.applyContentRename(at: file, to: "2026-09-14 Invoice ACME.pdf", fileManager: fileManager)
        let moved = try pipeline.applyRoute(at: content.url, fileManager: fileManager)
        #expect(moved.first?.destinationFolder == "Invoices")
    }

    @Test
    func olderActivityRowsWithoutRenameSourceStillDecode() throws {
        let json = """
        [{"id":"\(UUID().uuidString)","date":"2026-01-01T00:00:00Z","kind":"renamed","detail":"Renamed a to b","fileName":"b.pdf"}]
        """
        let rows = try ActivityLog.decode(Data(json.utf8))
        #expect(rows.count == 1)
        #expect(rows.first?.renameSource == nil)

        let row = ActivityEntry(kind: .renamed, detail: "x", fileName: "x.pdf", renameSource: .contentAware)
        let decoded = try ActivityLog.decode(try ActivityLog.encode([row]))
        #expect(decoded.first?.renameSource == .contentAware)
    }
}

// MARK: Organize Existing preview uses content names

struct ContentAwareOrganizePreviewTests {
    @Test
    func previewShowsAndApplyUsesContentAwareNames() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let invoice = root.appendingPathComponent("inv_88123.pdf")
        try Data("%PDF invoice".utf8).write(to: invoice)
        let notes = root.appendingPathComponent("team_notes.md")
        try Data("notes".utf8).write(to: notes)

        let pipeline = IngestPipeline(watchFolder: root)
        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: pipeline,
            contentAwareNames: [invoice.standardizedFileURL: "2026-09-14 Invoice ACME.pdf"],
            fileManager: fileManager
        )
        let items = preview.groups.flatMap(\.items)
        let invoiceItem = try #require(items.first { $0.plan.sourceURL == invoice.standardizedFileURL })
        #expect(invoiceItem.plan.renamedFileName == "2026-09-14 Invoice ACME.pdf")
        #expect(invoiceItem.contentAwareFileName == "2026-09-14 Invoice ACME.pdf")
        let notesItem = try #require(items.first { $0.plan.sourceURL == notes.standardizedFileURL })
        #expect(notesItem.plan.renamedFileName == "Team Notes.md")
        #expect(notesItem.contentAwareFileName == nil)

        let result = OrganizeExistingProcessor(watchFolder: root).applyPreview(items: items, fileManager: fileManager)
        #expect(result.summary.organized == 2)
        #expect(fileManager.fileExists(atPath: invoiceItem.plan.destinationURL.path))
        let renames = result.entries.filter { $0.kind == .renamed && $0.url?.pathExtension == "pdf" }
        #expect(renames.map(\.renameSource) == [.titleCase, .contentAware])
    }

    @Test
    func previewSimulatesCollisionsForContentNames() throws {
        let fileManager = FileManager.default
        let root = try makeTempWatchFolder()
        defer { try? fileManager.removeItem(at: root) }
        let a = root.appendingPathComponent("a.pdf")
        let b = root.appendingPathComponent("b.pdf")
        try Data("a".utf8).write(to: a)
        try Data("b".utf8).write(to: b)
        let scan = OrganizeExistingScanner(watchFolder: root).scan(fileManager: fileManager)
        let preview = OrganizeExistingPreviewBuilder.build(
            scan: scan,
            pipeline: IngestPipeline(watchFolder: root),
            contentAwareNames: [
                a.standardizedFileURL: "Invoice ACME.pdf",
                b.standardizedFileURL: "invoice acme.pdf",
            ],
            fileManager: fileManager
        )
        let names = preview.groups.flatMap(\.items).map(\.plan.renamedFileName).sorted()
        #expect(names == ["Invoice ACME.pdf", "invoice acme 2.pdf"])
    }
}

// MARK: Filing hold + timeout

struct ContentRenameTrackerTests {
    @Test
    func filingWaitsForTheContentNameUntilTheTimeout() {
        let start = Date(timeIntervalSince1970: 1_000)
        let file = URL(fileURLWithPath: "/tmp/w/Inv 88123.pdf")
        var tracker = ContentRenameTracker(timeout: 30)
        let id = tracker.begin(for: file, at: start)

        #expect(tracker.shouldHoldFiling(file, now: start))
        #expect(tracker.shouldHoldFiling(file, now: start.addingTimeInterval(29.9)))
        #expect(tracker.nextRelease(now: start.addingTimeInterval(10)) == 20)
        // Timeout: filing proceeds with the Title Case name.
        #expect(tracker.shouldHoldFiling(file, now: start.addingTimeInterval(30)) == false)
        #expect(tracker.nextRelease(now: start.addingTimeInterval(31)) == nil)

        // The job keeps running; a late result finds the file where it was filed.
        let filed = URL(fileURLWithPath: "/tmp/w/Documents/Inv 88123.pdf")
        tracker.noteMoved(from: file, to: filed)
        #expect(tracker.finish(id) == filed)
        #expect(tracker.isEmpty)
    }

    @Test
    func unrelatedFilesAreNeverHeld() {
        var tracker = ContentRenameTracker(timeout: 30)
        let now = Date()
        tracker.begin(for: URL(fileURLWithPath: "/tmp/w/a.pdf"), at: now)
        #expect(tracker.shouldHoldFiling(URL(fileURLWithPath: "/tmp/w/b.pdf"), now: now) == false)
    }

    @Test
    func restartingAJobForTheSameFileReplacesTheOldOne() {
        var tracker = ContentRenameTracker(timeout: 30)
        let now = Date()
        let file = URL(fileURLWithPath: "/tmp/w/a.pdf")
        let first = tracker.begin(for: file, at: now)
        let second = tracker.begin(for: file, at: now.addingTimeInterval(5))
        #expect(first != second)
        #expect(tracker.jobs.count == 1)
        #expect(tracker.finish(first) == nil)
        #expect(tracker.finish(second) == file.standardizedFileURL)
    }
}
