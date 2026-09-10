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

## Notes

- Dock and menu bar are on by default. General → Appearance in macOS toggles them independently; both cannot be off.
- Menu bar extra shows status, pause/resume, Organize Existing…, Open Activity, Settings…, and Quit. Dense 16pt template icons (Watching vs Paused) replace the earlier thin glyphs.
- Settings sidebar: General, Rules, Cleanup, Activity, AI, About. Dock / launch opens the Activity window, not Settings.
- The watcher ignores partial downloads, `.download` bundles, and quarantine metadata-only events, then renames and routes by extension. **Organize Existing…** applies the same pipeline to loose files already in the watch-folder root (not category folders). Enabled rules and Activity persist across launches.
- Cleanup scans unused files and supports File Away, Keep, and Delete. AI providers are listed as off-by-default placeholders and are not called.
