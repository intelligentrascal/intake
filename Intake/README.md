# Intake.app

Native macOS menu-bar app. Open `Intake.xcodeproj` in Xcode (macOS 26+) and run the Intake scheme.

## Layout

```text
Intake.xcodeproj     # app target, local IntakeCore package
Intake/              # SwiftUI + AppKit chrome (MenuBarExtra, Settings)
IntakeCore/          # taxonomy, ignore policy, rename-then-route
```

## Core tests

From this directory:

```sh
swift test --package-path IntakeCore
```

## Notes

- Menu bar extra shows status and pause/resume. Settings uses a sidebar: General, Rules, Cleanup, AI, About.
- The watcher ignores partial downloads, `.download` bundles, and quarantine metadata-only events, then renames and routes by extension.
- AI providers are listed as off-by-default placeholders and are not called.
