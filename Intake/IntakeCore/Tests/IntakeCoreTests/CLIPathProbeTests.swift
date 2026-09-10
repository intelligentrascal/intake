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

struct LaunchWindowPolicyTests {
    @Test
    func launchAlwaysHidesActivityAndOpensSettingsWhenDockIsOn() {
        #expect(LaunchWindowPolicy.hidesActivityAtLaunch)
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: true, isFirstRun: false))
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: false, isFirstRun: true))
        #expect(LaunchWindowPolicy.presentsSettings(showsInDock: false, isFirstRun: false) == false)
    }
}
