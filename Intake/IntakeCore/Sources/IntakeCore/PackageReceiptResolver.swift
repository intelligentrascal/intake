import Foundation

/// Best-effort lookup of the app a `.pkg`/`.mpkg` installer already put on
/// disk, using macOS's installed-package receipts database (`pkgutil`).
///
/// Reading a flat package's embedded identifier means shelling out to
/// `/usr/bin/xar` and `/usr/sbin/pkgutil` — either can come back empty (tool
/// missing, receipt unreadable, package isn't flat, App Sandbox denies the
/// spawned process the file access it needs). Every failure path here
/// returns `nil` rather than throwing, so callers fall back to name-based
/// matching, matching the ticket's "receipts when readable, otherwise name
/// match" scope.
///
/// The identifier lookup (an `xar` extraction plus two `pkgutil` spawns) is
/// cached by path/size/modification-date, like `DuplicateHashCache`, so
/// repeated Cleanup scans don't re-spawn processes for a `.pkg` that hasn't
/// changed. Reference-typed so one instance can be kept across scans (e.g.
/// by `AppModel`) while `CleanupScanner` itself stays a plain value type.
public final class PackageReceiptResolver: @unchecked Sendable {
    private struct Key: Hashable {
        let path: String
        let size: Int64
        let modified: Date
    }

    private let lock = NSLock()
    /// Cached resolved app bundle URL for a package's identifier — `nil`
    /// means "looked it up, no receipt match found," which is itself worth
    /// caching so an unmatched `.pkg` isn't re-spawned every scan either.
    private var resolvedAppURLs: [Key: URL?] = [:]

    public init() {}

    /// The installed app this package's receipt says it put on disk, if the
    /// receipt database is readable and has a matching, still-installed
    /// package identifier. `dateProvider` decides the returned app's `date`,
    /// same as `InstalledAppMatcher` — it's read fresh on every call (never
    /// cached), since the cache only covers the package-to-app-path lookup,
    /// not whether that app has since changed.
    public func installedApp(
        forPackageAt packageURL: URL,
        fileManager: FileManager = .default,
        dateProvider: @Sendable (URL, FileManager) -> Date = InstalledAppMatcher.defaultDate
    ) -> InstalledAppMatcher.InstalledApp? {
        guard let appURL = resolvedAppURL(forPackageAt: packageURL, fileManager: fileManager) else {
            return nil
        }
        return InstalledAppMatcher.installedApp(at: appURL, fileManager: fileManager, dateProvider: dateProvider)
    }

    private func resolvedAppURL(forPackageAt packageURL: URL, fileManager: FileManager) -> URL? {
        guard let key = cacheKey(for: packageURL, fileManager: fileManager) else {
            // Can't even read the package's own size/mtime — nothing to
            // cache against, so just resolve it directly this one time.
            return resolveAppURL(for: packageURL)
        }

        lock.lock()
        if let cached = resolvedAppURLs[key] {
            lock.unlock()
            return cached
        }
        lock.unlock()

        let resolved = resolveAppURL(for: packageURL)
        lock.lock()
        resolvedAppURLs[key] = resolved
        lock.unlock()
        return resolved
    }

    private func cacheKey(for url: URL, fileManager: FileManager) -> Key? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else {
            return nil
        }
        guard let size = values.fileSize else { return nil }
        let modified = values.contentModificationDate ?? .distantPast
        return Key(path: url.path, size: Int64(size), modified: modified)
    }

    private func resolveAppURL(for packageURL: URL) -> URL? {
        guard let identifier = packageIdentifier(at: packageURL) else { return nil }
        guard let (volume, location) = installLocation(forIdentifier: identifier) else { return nil }
        guard let appPath = appBundlePath(forIdentifier: identifier, volume: volume, location: location) else {
            return nil
        }
        return URL(fileURLWithPath: appPath)
    }

    /// Extracts the package's `Distribution` (or legacy `PackageInfo`) member
    /// from the flat (xar) archive without unpacking its payload, and reads
    /// the `identifier` it declares.
    private func packageIdentifier(at packageURL: URL) -> String? {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(
            "intake-pkginfo-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: tempDir) }
        guard (try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)) != nil else {
            return nil
        }

        for member in ["Distribution", "PackageInfo"] {
            guard run(
                "/usr/bin/xar",
                ["-x", "-f", packageURL.path, member],
                currentDirectory: tempDir
            ) != nil else { continue }
            let extracted = tempDir.appendingPathComponent(member)
            guard let data = try? Data(contentsOf: extracted),
                  let xml = String(data: data, encoding: .utf8)
            else { continue }
            if let identifier = firstAttribute(named: "identifier", in: xml) {
                return identifier
            }
            if let identifier = firstAttribute(named: "id", tag: "pkg-ref", in: xml) {
                return identifier
            }
        }
        return nil
    }

    /// `pkgutil --pkg-info-plist <id>`: succeeds only when that identifier
    /// has an installed-package receipt, confirming it's actually installed
    /// (not just present in the downloaded installer).
    private func installLocation(forIdentifier identifier: String) -> (volume: String, location: String)? {
        guard let output = run("/usr/sbin/pkgutil", ["--pkg-info-plist", identifier]),
              let data = output.data(using: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        else { return nil }
        let volume = (plist["volume"] as? String) ?? "/"
        let location = (plist["install-location"] as? String) ?? "/Applications"
        return (volume, location)
    }

    /// `pkgutil --files <id>`: lists payload paths; the first top-level
    /// `.app` is the installed app.
    private func appBundlePath(forIdentifier identifier: String, volume: String, location: String) -> String? {
        guard let output = run("/usr/sbin/pkgutil", ["--files", identifier]) else { return nil }
        for line in output.split(separator: "\n") {
            let relative = String(line)
            guard relative.hasSuffix(".app") else { continue }
            let base = URL(fileURLWithPath: volume).appendingPathComponent(location, isDirectory: true)
            return base.appendingPathComponent(relative, isDirectory: true).path
        }
        return nil
    }

    private func firstAttribute(named attribute: String, tag: String? = nil, in xml: String) -> String? {
        let tagPattern = tag.map { NSRegularExpression.escapedPattern(for: $0) } ?? "[a-zA-Z-]+"
        let pattern = "<\(tagPattern)\\b[^>]*\\b\(attribute)=\"([^\"]+)\""
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(xml.startIndex..., in: xml)
        guard let match = regex.firstMatch(in: xml, range: range),
              let valueRange = Range(match.range(at: 1), in: xml)
        else { return nil }
        return String(xml[valueRange])
    }

    /// Runs a tool and returns its stdout, or `nil` on any failure (missing
    /// binary, non-zero exit, sandbox denial).
    private func run(_ executable: String, _ arguments: [String], currentDirectory: URL? = nil) -> String? {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = currentDirectory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
