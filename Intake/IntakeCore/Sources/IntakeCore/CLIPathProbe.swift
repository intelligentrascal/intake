import Foundation

/// PATH lookup for optional CLIs. v1 is detection-only: no process is launched.
public enum CLIPathProbe: Sendable {
    /// Directories GUI apps often miss because `ProcessInfo` PATH is thinner than a login shell.
    public static let commonInstallDirectories: [String] = [
        NSHomeDirectory() + "/.local/bin",
        "/opt/homebrew/bin",
        "/opt/homebrew/sbin",
        "/usr/local/bin",
        "/usr/local/sbin",
    ]

    /// Merges `ProcessInfo` PATH with common install dirs (and optional extras).
    /// Order: process PATH entries first, then common dirs not already listed.
    public static func searchPath(
        processPath: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        extraDirectories: [String] = commonInstallDirectories
    ) -> String {
        var seen = Set<String>()
        var ordered: [String] = []
        func append(_ raw: String) {
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            let standardized = URL(fileURLWithPath: trimmed, isDirectory: true).path
            if seen.insert(standardized).inserted {
                ordered.append(standardized)
            }
        }
        for entry in processPath.split(separator: ":", omittingEmptySubsequences: true) {
            append(String(entry))
        }
        for directory in extraDirectories {
            append(directory)
        }
        return ordered.joined(separator: ":")
    }

    /// True when `command` is an executable in one of the `PATH` directories.
    /// Names that look like paths (`/` or `\`) are never considered.
    public static func isExecutableOnPath(
        _ command: String,
        path: String,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> Bool {
        guard isSimpleCommandName(command) else { return false }
        for directory in path.split(separator: ":", omittingEmptySubsequences: true) {
            let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
                .appendingPathComponent(command)
                .path
            if isExecutable(candidate) {
                return true
            }
        }
        return false
    }

    private static func isSimpleCommandName(_ command: String) -> Bool {
        !command.isEmpty && !command.contains("/") && !command.contains("\\")
    }
}

/// Optional local CLIs listed in Settings → AI. Not used for suggestions yet.
public enum OtherAIProvider: String, CaseIterable, Sendable, Identifiable {
    case ollama
    case claude
    case cursor
    case codex

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .ollama: "Ollama (local)"
        case .claude: "Claude CLI"
        case .cursor: "Cursor agent CLI"
        case .codex: "Codex CLI"
        }
    }

    public var detail: String {
        switch self {
        case .ollama: "Local models, when installed"
        case .claude: "Uses the claude command if present"
        case .cursor: "Uses the agent or cursor command if present"
        case .codex: "Uses the codex command if present"
        }
    }

    /// Binaries probed on PATH. Cursor checks both `agent` and `cursor`.
    public var commandNames: [String] {
        switch self {
        case .ollama: ["ollama"]
        case .claude: ["claude"]
        case .cursor: ["agent", "cursor"]
        case .codex: ["codex"]
        }
    }
}

public struct OtherAIProviderPresence: Equatable, Sendable, Identifiable {
    public var provider: OtherAIProvider
    public var foundCommands: [String]

    public var id: String { provider.id }
    public var isAvailable: Bool { !foundCommands.isEmpty }

    public var statusTitle: String {
        isAvailable ? "Available" : "Not installed"
    }

    /// Names the binaries actually found — used for Cursor (`agent` and/or `cursor`).
    public var foundOnPathDetail: String? {
        guard !foundCommands.isEmpty else { return nil }
        if foundCommands.count == 1 {
            return "Found \(foundCommands[0]) on PATH"
        }
        let head = foundCommands.dropLast().joined(separator: ", ")
        return "Found \(head) and \(foundCommands.last!) on PATH"
    }

    public init(provider: OtherAIProvider, foundCommands: [String]) {
        self.provider = provider
        self.foundCommands = foundCommands
    }
}

public enum OtherAIProviderDetector: Sendable {
    public static func presence(
        for provider: OtherAIProvider,
        path: String,
        isExecutable: (String) -> Bool
    ) -> OtherAIProviderPresence {
        let found = provider.commandNames.filter { name in
            CLIPathProbe.isExecutableOnPath(name, path: path, isExecutable: isExecutable)
        }
        return OtherAIProviderPresence(provider: provider, foundCommands: found)
    }

    /// Scans ProcessInfo PATH plus common Homebrew / `~/.local/bin` install dirs.
    /// Detection-only — never launches a CLI or login shell.
    public static func scan(
        path: String = CLIPathProbe.searchPath(),
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> [OtherAIProviderPresence] {
        OtherAIProvider.allCases.map {
            presence(for: $0, path: path, isExecutable: isExecutable)
        }
    }
}
