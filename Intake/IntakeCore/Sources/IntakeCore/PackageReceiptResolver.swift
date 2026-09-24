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
public struct PackageReceiptResolver: Sendable {
    public init() {}

    /// The installed app this package's receipt says it put on disk, if the
    /// receipt database is readable and has a matching, still-installed
    /// package identifier.
    public func installedApp(
        forPackageAt packageURL: URL,
        fileManager: FileManager = .default
    ) -> InstalledAppMatcher.InstalledApp? {
        guard let identifier = packageIdentifier(at: packageURL) else { return nil }
        guard let (volume, location) = installLocation(forIdentifier: identifier) else { return nil }
        guard let appPath = appBundlePath(forIdentifier: identifier, volume: volume, location: location) else {
            return nil
        }
        let appURL = URL(fileURLWithPath: appPath)
        return InstalledAppMatcher.installedApps(in: [appURL.deletingLastPathComponent()], fileManager: fileManager)
            .first { $0.url.standardizedFileURL == appURL.standardizedFileURL }
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
