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
- Settings sidebar: General, Rules, Cleanup, Activity, AI, About. Dock / launch / reopen opens **Settings**, not Activity. Activity is optional via Open Activity.
- General → Organizing uses **Automatic organizing** (not Pause) and **Wait before organizing** (default 2 hours; Immediately / 15 minutes / 1 hour / 2 hours / 1 day). Organize Existing does not wait.
- The watcher ignores partial downloads, `.download` bundles, and quarantine metadata-only events, then waits until the file is stable and **Wait before organizing** has elapsed, then renames and routes by editable rules. **Organize Existing…** applies the same pipeline immediately to loose files already in the watch-folder root (not category folders). Enabled rules, custom rules, and Activity persist across launches.
- Rules can be edited, reordered, and extended; on-device suggestions stay local (no network, no file contents).
- Cleanup scans unused files and supports File Away, Keep, and Delete. OpenRouter is the first opt-in AI provider (Keychain). Other providers are PATH-detected (Available / Not installed) and not called yet.
