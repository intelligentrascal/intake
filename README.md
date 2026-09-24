# Intake

A native macOS Downloads organizer — tidy names when downloads finish, then file into folders on your schedule.

**License:** MIT · **Requires:** macOS 26+ · **Privacy:** local by default; network only if you turn on optional AI or open Feedback to GitHub.

## Download

Get the latest **notarized** DMG from [**Releases**](https://github.com/intelligentrascal/intake/releases/latest):

1. Download `Intake-1.3.2.dmg` (or newer)
2. Open the DMG and drag **Intake** to Applications
3. Launch Intake; grant folder access if prompted

Signed with Developer ID and notarized by Apple — double-click should work without Gatekeeper workarounds.

## What it does

- Watches your Downloads folder (configurable)
- **Rename when download finishes** (Title Case + product allowlist like `macOS` / `iPhone`)
- **Wait before organizing** so fresh downloads stay findable before filing
- **Organize Existing…** one-shot for what’s already in the watch folder
- **Undo** recent Intake renames/moves from Activity
- Menu bar + Dock; Settings for rules, cleanup, AI (optional OpenRouter), and **Feedback** (opens a prefilled GitHub Issue)

## Build from source

```bash
./scripts/install-local.sh
# or open Intake/Intake.xcodeproj in Xcode
```

See [CONTRIBUTING.md](CONTRIBUTING.md) and [docs/PRODUCT.md](docs/PRODUCT.md).

## Security

Report vulnerabilities via [SECURITY.md](SECURITY.md).
