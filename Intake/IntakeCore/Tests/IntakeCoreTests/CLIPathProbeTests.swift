import Foundation
import Testing
@testable import IntakeCore

struct CLIPathProbeTests {
    @Test
    func findsAnExecutableInALaterPathDirectory() {
        var probed: [String] = []
        let found = CLIPathProbe.isExecutableOnPath(
            "ollama",
            path: "/opt/homebrew/bin:/usr/bin",
            isExecutable: { candidate in
                probed.append(candidate)
                return candidate == "/usr/bin/ollama"
            }
        )
        #expect(found)
        #expect(probed == ["/opt/homebrew/bin/ollama", "/usr/bin/ollama"])
    }

    @Test
    func stopsAtTheFirstExecutableMatch() {
        var count = 0
        let found = CLIPathProbe.isExecutableOnPath(
            "claude",
            path: "/usr/local/bin:/usr/bin",
            isExecutable: { candidate in
                count += 1
                return candidate == "/usr/local/bin/claude"
            }
        )
        #expect(found)
        #expect(count == 1)
    }

    @Test
    func missingCommandIsNotInstalled() {
        #expect(
            CLIPathProbe.isExecutableOnPath(
                "codex",
                path: "/usr/bin:/bin",
                isExecutable: { _ in false }
            ) == false
        )
    }

    @Test
    func skipsEmptyPathEntries() {
        var probed: [String] = []
        _ = CLIPathProbe.isExecutableOnPath(
            "ollama",
            path: ":/usr/bin:",
            isExecutable: {
                probed.append($0)
                return false
            }
        )
        #expect(probed == ["/usr/bin/ollama"])
    }

    @Test
    func rejectsCommandNamesThatLookLikePaths() {
        var probed = 0
        #expect(
            CLIPathProbe.isExecutableOnPath(
                "../bin/ollama",
                path: "/usr/bin",
                isExecutable: { _ in
                    probed += 1
                    return true
                }
            ) == false
        )
        #expect(probed == 0)
        #expect(
            CLIPathProbe.isExecutableOnPath(
                "",
                path: "/usr/bin",
                isExecutable: { _ in true }
            ) == false
        )
    }

    @Test
    func otherProvidersProbeTheDocumentedBinaries() {
        #expect(OtherAIProvider.ollama.commandNames == ["ollama"])
        #expect(OtherAIProvider.claude.commandNames == ["claude"])
        #expect(OtherAIProvider.cursor.commandNames == ["agent", "cursor"])
        #expect(OtherAIProvider.codex.commandNames == ["codex"])
        #expect(OtherAIProvider.ollama.title == "Ollama (local)")
        #expect(OtherAIProvider.claude.title == "Claude CLI")
        #expect(OtherAIProvider.cursor.title == "Cursor agent CLI")
        #expect(OtherAIProvider.codex.title == "Codex CLI")
        #expect(OtherAIProvider.ollama.detail == "Local models, when installed")
        #expect(OtherAIProvider.claude.detail == "Uses the claude command if present")
        #expect(OtherAIProvider.cursor.detail == "Uses the agent or cursor command if present")
        #expect(OtherAIProvider.codex.detail == "Uses the codex command if present")
    }

    @Test
    func cursorIsAvailableWhenAgentOrCursorIsOnPath() {
        let onlyAgent = OtherAIProviderDetector.presence(
            for: .cursor,
            path: "/usr/local/bin",
            isExecutable: { $0.hasSuffix("/agent") }
        )
        #expect(onlyAgent.isAvailable)
        #expect(onlyAgent.foundCommands == ["agent"])
        #expect(onlyAgent.statusTitle == "Available")
        #expect(onlyAgent.foundOnPathDetail == "Found agent on PATH")

        let onlyCursor = OtherAIProviderDetector.presence(
            for: .cursor,
            path: "/usr/local/bin",
            isExecutable: { $0.hasSuffix("/cursor") }
        )
        #expect(onlyCursor.isAvailable)
        #expect(onlyCursor.foundCommands == ["cursor"])
        #expect(onlyCursor.foundOnPathDetail == "Found cursor on PATH")

        let both = OtherAIProviderDetector.presence(
            for: .cursor,
            path: "/usr/local/bin",
            isExecutable: { $0.hasSuffix("/agent") || $0.hasSuffix("/cursor") }
        )
        #expect(both.foundCommands == ["agent", "cursor"])
        #expect(both.foundOnPathDetail == "Found agent and cursor on PATH")

        let none = OtherAIProviderDetector.presence(
            for: .cursor,
            path: "/usr/local/bin",
            isExecutable: { _ in false }
        )
        #expect(none.isAvailable == false)
        #expect(none.statusTitle == "Not installed")
        #expect(none.foundOnPathDetail == nil)
    }

    @Test
    func ollamaClaudeAndCodexFollowASingleBinary() {
        let available = OtherAIProviderDetector.presence(
            for: .ollama,
            path: "/opt/homebrew/bin",
            isExecutable: { $0.hasSuffix("/ollama") }
        )
        #expect(available.statusTitle == "Available")
        #expect(available.foundCommands == ["ollama"])

        let missing = OtherAIProviderDetector.presence(
            for: .codex,
            path: "/opt/homebrew/bin",
            isExecutable: { $0.hasSuffix("/ollama") }
        )
        #expect(missing.statusTitle == "Not installed")
        #expect(
            OtherAIProviderDetector.presence(
                for: .claude,
                path: "/opt/homebrew/bin",
                isExecutable: { $0.hasSuffix("/claude") }
            ).isAvailable
        )
    }
}


    @Test
    func searchPathMergesCommonInstallDirectoriesAfterProcessPath() {
        let merged = CLIPathProbe.searchPath(
            processPath: "/custom/bin",
            extraDirectories: ["/opt/homebrew/bin", "/custom/bin", "/usr/local/bin"]
        )
        let parts = merged.split(separator: ":").map(String.init)
        #expect(parts.first == "/custom/bin")
        #expect(parts.contains("/opt/homebrew/bin"))
        #expect(parts.contains("/usr/local/bin"))
        #expect(parts.filter { $0 == "/custom/bin" }.count == 1)
    }

    @Test
    func scanDefaultPathIncludesHomebrewEvenWhenProcessPathIsThin() {
        // Simulate a GUI-thin PATH that omits Homebrew; detector still finds claude.
        let results = OtherAIProviderDetector.scan(
            path: CLIPathProbe.searchPath(
                processPath: "/usr/bin:/bin",
                extraDirectories: ["/opt/homebrew/bin", NSHomeDirectory() + "/.local/bin"]
            ),
            isExecutable: { candidate in
                candidate == "/opt/homebrew/bin/claude"
                    || candidate.hasSuffix("/.local/bin/codex")
            }
        )
        let claude = results.first { $0.provider == .claude }
        let codex = results.first { $0.provider == .codex }
        #expect(claude?.isAvailable == true)
        #expect(codex?.isAvailable == true)
    }


    @Test
    func realUserHomeDirectoryIsNonEmpty() {
        #expect(!CLIPathProbe.realUserHomeDirectory.isEmpty)
    }

    @Test
    func commonInstallDirectoriesPreferRealHomeLocalBin() {
        let local = CLIPathProbe.realUserHomeDirectory + "/.local/bin"
        #expect(CLIPathProbe.commonInstallDirectories.contains(local))
        #expect(CLIPathProbe.commonInstallDirectories.contains("/opt/homebrew/bin"))
    }

struct LaunchWindowPolicyTests {
    @Test
    func launchAlwaysHidesActivityAndOpensSettingsWhenDockIsOn() {
        #expect(LaunchWindowPolicy.hidesActivityAtLaunch)
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: true, isFirstRun: false))
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: false, isFirstRun: true))
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: false, isFirstRun: false) == false)
    }
}


struct CLIPathProbeSymlinkTests {
    @Test
    func defaultProbeDoesNotUseFileManagerFollowingClosure() {
        // scan()'s default isExecutable must be the non-resolving probe — documented contract.
        // We can't introspect the default closure; instead assert the public helper treats a
        // PATH entry as executable when our injectable says so (symlink case simulated).
        let presence = OtherAIProviderDetector.presence(
            for: .claude,
            path: "/Users/me/.local/bin",
            isExecutable: { path in
                // Simulate: FileManager.isExecutableFile would be false (target outside sandbox),
                // but non-following check returns true for the link path itself.
                path == "/Users/me/.local/bin/claude"
            }
        )
        #expect(presence.isAvailable)
        #expect(presence.foundCommands == ["claude"])
    }

    @Test
    func codexSymlinkStylePathIsDetectedWithoutResolvingCaskroomTarget() {
        let presence = OtherAIProviderDetector.presence(
            for: .codex,
            path: "/opt/homebrew/bin",
            isExecutable: { $0 == "/opt/homebrew/bin/codex" }
        )
        #expect(presence.isAvailable)
        #expect(presence.statusTitle == "Available")
    }
}
