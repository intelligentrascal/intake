# Intake.app

Native macOS app (Dock + menu bar). Open `Intake.xcodeproj` in Xcode (macOS 26+) and run the Intake scheme.

## Layout

```text
Intake.xcodeproj     # app target, local IntakeCore package
Intake/              # SwiftUI + AppKit chrome (MenuBarExtra, Settings, Dock policy)
IntakeCore/          # taxonomy, ignore policy, rename-then-route, activity, cleanup
```

## Core tests

From this directory:

```sh
swift test --package-path IntakeCore
```


## Install for Spotlight / Apps

Xcode Run only registers the DerivedData Debug bundle, which Spotlight may not keep as a stable Apps target. After a successful build:

```sh
# from repo root
./scripts/install-local.sh
# or:
./scripts/install-local.sh /path/to/Build/Products/Debug/Intake.app
```

That copies into `~/Applications/Intake.app`, refreshes Launch Services, and you can open with Spotlight or:

```sh
open -b app.intake.Intake
```

Dock must stay on (default) so cold launch presents Settings (`activationPolicy` `.regular`).

## Notes

- Dock and menu bar are on by default. General → Appearance in macOS toggles them independently; both cannot be off.
- Menu bar extra shows status, pause/resume, Organize Existing…, Open Activity, Settings…, and Quit. Dense 16pt template icons (Watching vs Paused) replace the earlier thin glyphs.
- Settings sidebar: General, Rules, Cleanup, Activity, AI, About. Dock / launch / reopen opens **Settings**, not Activity. Activity is optional via Open Activity.
- General → Organizing uses **Automatic organizing** (not Pause), **Rename when download finishes** (default on; local rename as soon as the file is stable), and **Wait before organizing** (default 2 hours; Immediately / 15 minutes / 1 hour / 2 hours / 1 day). Wait delays filing into folders only. Organize Existing does not wait.
- The watcher ignores partial downloads, `.download` bundles, and quarantine metadata-only events. Once the file is stable, Intake can rename it in the watch-folder root, then waits until **Wait before organizing** has elapsed before routing by editable rules. **Organize Existing…** applies the combined rename → route pipeline immediately to loose files already in the watch-folder root (not category folders). Enabled rules, custom rules, and Activity persist across launches.
- Rules can be edited, reordered, and extended; on-device suggestions stay local (no network, no file contents).
- Cleanup scans unused files and supports File Away, Keep, and Delete. OpenRouter is the first opt-in AI provider (Keychain). Other providers are PATH-detected (Available / Not installed) and not called yet.
