# Intake

**Native macOS Downloads organizer.** Files arrive, Intake renames them sensibly, then files them into typed folders — only creating folders when needed, and removing empty ones after cleanup.

Free and open source ([MIT](LICENSE)). Private by design: watching and organizing stay on your Mac. Optional AI is off by default.

## Download

**[Download Intake-0.1.0.dmg from the Latest Release](https://github.com/intelligentrascal/intake/releases/latest)**

- Requires **macOS 26+**
- Developer ID signed and **notarized** — open the DMG, drag `Intake.app` to Applications, then launch
- First external tester build — expect sharp edges; please [file Issues](https://github.com/intelligentrascal/intake/issues)

### Quick tester ask

Install from the DMG, grant folder access if prompted, drop a few messy downloads (underscores, camelCase, `(1)` dupes), try Wait vs Organize Existing, and file one Issue with: macOS version, what you expected, what happened, and a screenshot if UI. Do **not** paste API keys or full home-directory paths in public issues.

## What it does

1. **Watch** `~/Downloads` (configurable) in the background
2. **Rename** new downloads to something human-readable (Arc-style clarity, Title Case)
3. **Route** by rules into lazy folders (`Documents`, `Presentations`, `Images`, …)
4. **Cleanup** — untouched files past a duration show up for File away / Delete / Keep
5. **Optional AI** — OpenRouter when enabled (Keychain) is the working provider. Ollama / Claude / Cursor / Codex CLIs are detected on PATH (Available vs Not installed) and not called yet. Off by default.

## Design

Native **SwiftUI** + **Apple Human Interface Guidelines**. Product tokens and screens: [docs/PRODUCT.md](docs/PRODUCT.md), [docs/DESIGN.md](docs/DESIGN.md).

[Thaw](https://github.com/thaw-app/Thaw) is a **mood board** for polish only. Thaw is GPL-3.0 — we do **not** copy its source.

## Requirements

- macOS 26+
- For building from source: Xcode (current stable supporting macOS 26 SDK)

## Build from source

```text
Intake/                 # Xcode app (MenuBarExtra + Settings)
Intake/IntakeCore/      # rules, taxonomy, ingest stubs
docs/                   # PRODUCT, DESIGN
.github/                # issue templates
LICENSE                 # MIT
```

Open `Intake/Intake.xcodeproj`. Core logic can be tested with `swift test --package-path Intake/IntakeCore`.

After an Xcode Debug build, register a stable Apps target:

```sh
./scripts/install-local.sh
```

Then Spotlight / `open -b app.intake.Intake` launch `~/Applications/Intake.app`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
