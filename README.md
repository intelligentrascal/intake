# Intake

**Native macOS Downloads organizer.** Files arrive, Intake renames them sensibly, then files them into typed folders — only creating folders when needed, and removing empty ones after cleanup.

Free and open source. Private by design: watching and organizing stay on your Mac.

> Status: SwiftUI menu-bar scaffold with taxonomy, ignore policy, and rename-then-route stubs.

## What it does

1. **Watch** `~/Downloads` (configurable) in the background
2. **Rename** new downloads to something human-readable (Arc-style clarity)
3. **Route** by rules into lazy folders (`Documents`, `Presentations`, `Images`, …)
4. **Cleanup** — untouched files past a duration show up for File away / Delete / Keep
5. **Optional AI** (later) — mix local Ollama and optional Claude / Cursor / Codex CLIs for suggestions when rules aren’t enough

## Design

Native **SwiftUI** + **Apple Human Interface Guidelines**. Product tokens and screens: [docs/PRODUCT.md](docs/PRODUCT.md), [docs/DESIGN.md](docs/DESIGN.md).

[Thaw](https://github.com/thaw-app/Thaw) is a **mood board** for polish only. Thaw is GPL-3.0 — we do **not** copy its source.

## Requirements

- macOS 26+
- Xcode (current stable supporting macOS 26 SDK)

## Repo layout

```text
Intake/                 # Xcode app (MenuBarExtra + Settings)
Intake/IntakeCore/      # rules, taxonomy, ingest stubs
docs/                   # PRODUCT, DESIGN
.github/                # issue templates
LICENSE                 # MIT
```

Open `Intake/Intake.xcodeproj`. Core logic can be tested with `swift test --package-path Intake/IntakeCore`.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE)
