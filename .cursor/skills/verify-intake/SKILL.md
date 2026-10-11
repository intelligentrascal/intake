---
name: verify-intake
description: "Drive the Intake macOS menu-bar app (SwiftUI, sandboxed) the way a user does and capture proof: an isolated Debug build with its own bundle id and scratch watch folder, PID-bound Accessibility driving of the menu bar extra, main menu and Settings/Activity windows, filesystem side effects, and the stored Activity log. Use when you need to prove Intake UI or rename/filing behavior on the Mac, before claiming a fix works, or for /maintain-verification-skill."
---

# Verify Intake

Intake is a sandboxed SwiftUI menu-bar + Dock app (bundle id `app.intake.Intake`, Xcode project `Intake/Intake.xcodeproj`, scheme `Intake`, macOS 26+). A user touches four surfaces: files landing in a **watch folder** (renamed/filed with no UI), the **menu bar extra**, the **Settings** window (seven panes), and the **Activity** window. This skill builds a separate copy of the app, drives it through Accessibility bound to its PID, and keeps the proof.

Read [`features/README.md`](features/README.md) for the per-feature recipes and [`docs/FEATURE-MAP.md`](../../../docs/FEATURE-MAP.md) for the full navigation map (every pane, menu item and shortcut). All commands below run from the repo root on the Mac; `S=.cursor/skills/verify-intake/scripts`.

## Isolation: why this never touches the installed app

The owner's daily Intake (`~/Applications/Intake.app`, bundle id `app.intake.Intake`) is usually running and watching the real `~/Downloads`. Everything Intake stores is `UserDefaults.standard` inside its sandbox container (watch folders `intake.watchFolderProfiles`, Activity `intake.activity`, Undo `intake.undoStack`, rules, AI settings), and the OpenRouter key lives in Keychain. Two copies with the same bundle id would share all of it and both would watch `~/Downloads`. So the verification build is a different app:

| | Installed app (never touched) | Verification build |
|---|---|---|
| Bundle id | `app.intake.Intake` | `app.intake.Intake.verify` (xcodebuild override, no project change) |
| Name in Dock / Launch Services | Intake | **Intake Verify** (`INFOPLIST_KEY_CFBundleDisplayName` override) |
| Container / preferences | `~/Library/Containers/app.intake.Intake` | `~/Library/Containers/app.intake.Intake.verify` |
| Watch folder | `~/Downloads` (+ whatever the owner added) | `~/Library/Containers/app.intake.Intake.verify/Data/IntakeVerifyInbox` only |
| OpenRouter Keychain service | `app.intake.Intake.openrouter` | `app.intake.Intake.verify.openrouter` (service is derived from the bundle id) |
| Lives at | `~/Applications/Intake.app` | `.verify-intake/DerivedData/Build/Products/Debug/Intake.app` (git-ignored) |

The watch folder is pinned with a launch argument, `-intake.watchFolderProfiles <hex JSON>`: values in the argument domain beat stored preferences, so even the very first launch never falls back to the default `~/Downloads` profile. The inbox sits inside the verification container, which the sandboxed build can always read and write — no folder picker or bookmark needed.

Hard rules:

- **Never run `scripts/install-local.sh`.** It replaces `~/Applications/Intake.app`.
- **Never use `osascript`/System Events to drive Intake.** System Events resolves a process by *name*, and both copies' processes are named `Intake`: a click aimed at the verification PID lands on the installed app (this happened while this skill was written — the menu opened was the owner's). Drive only through `scripts/drive.sh`, which calls `axdrive` with the recorded PID.
- **Never send keystrokes** (⌘, ⌘1–⌘7, ⌘Q…) with `System Events keystroke`/`key code`: they go to whatever app is frontmost. Press the element instead (`drive.sh press AI`, `drive.sh menu Intake "Settings…"`).
- **Never kill by name.** Only `cleanup.sh` stops anything, and only the PID `launch.sh` recorded after re-checking it is the verification binary.
- Do not toggle **Open at login** (registers the verification build as a login item), **Notifications** (system permission prompt), or OpenRouter / AI suggestions with a real key in the verification build.

Both copies run side by side; you will see two Intake icons in the menu bar (the owner uses Thaw, which may hide both off-screen — `axdrive` still reaches ours) and an "Intake Verify" icon in the Dock.

## Launch

```bash
S=.cursor/skills/verify-intake/scripts
$S/build.sh    # xcodebuild Debug → .verify-intake/DerivedData, bundle id app.intake.Intake.verify; compiles .verify-intake/bin/axdrive (~15 s incremental)
$S/launch.sh   # starts it with the scratch watch-folder profile; records PID/RUN_ID/EVIDENCE in .verify-intake/run/current.env
```

`launch.sh` refuses if a verification instance is already running, logs (but never touches) the installed app's PID, and on the very first run bootstraps the sandbox container (start once, let macOS create the container, stop that PID, create `IntakeVerifyInbox`). **Ready** when it prints `ready: pid <PID> watching …/IntakeVerifyInbox` — the PID's menu bar extra reads `Watching` / `New files in IntakeVerifyInbox` and the process holds an open descriptor on the inbox. Launch opens the Settings window (General) because Show in Dock defaults on; the one-time "Intake lives in the Dock and menu bar" tip is skipped with `-intake.didShowMenuBarTip YES`.

Rebuild (`build.sh`) after any code change before launching; doctor warns when the build is older than the checkout. Teardown is `cleanup.sh` (below).

## Doctor

```bash
$S/doctor.sh   # read-only; exit 0 = safe to drive, exit 1 = do not drive
```

Checks: the installed app's PID (reported, never driven); the recorded PID is alive, runs `.verify-intake/…/Intake.app/Contents/MacOS/Intake`, and Launch Services lists it under `app.intake.Intake.verify`; the build's bundle id/version and checkout SHA; the scratch inbox exists and the PID has it open; the PID does **not** have `~/Downloads` open; it was launched with `-intake.watchFolderProfiles`; the PID-bound menu bar extra answers; Accessibility is granted to the app running the shell; and whether the Mac's screen is locked.

Run it before the first drive, after anything surprising, and after every failed drive. A `WARN … screen is LOCKED` line means window contents and window screenshots are unavailable (see Gotchas) — menu bar extra, filesystem and stored-Activity proof still work.

## Drive

`scripts/drive.sh` re-checks the PID on every call, then:

| User action | Command | Observable result |
|---|---|---|
| Look at the menu bar extra | `$S/drive.sh status` | `status item: Intake watching`, then items: `[Watching]`, `[New files in IntakeVerifyInbox]`, `[Pause Organizing]`, `[Organize Existing…]`, up to 5 recent rows `[<file> · Renamed]`, `[Open Activity]`, `[Open Cleanup]`, `[Settings…]`, `[Send Feedback…]`, `[Quit Intake]` |
| Choose a menu bar extra item | `$S/drive.sh extra "Open Activity"` (or `"Pause Organizing"`, `"Resume Organizing"`, `"Open Cleanup"`, `"Send Feedback…"`, `"Organize Existing…"`) | window appears / status flips |
| Intake menu ▸ Settings… (⌘,) | `$S/drive.sh menu Intake "Settings…"` | Settings window titled after the pane (`General`, `AI`, …) |
| Intake menu ▸ Activity / Pause Organizing / Organize Existing… | `$S/drive.sh menu Intake Activity` | Activity window |
| Pick a Settings pane (sidebar row; ⌘1–⌘7) | `$S/drive.sh press AI` (`General`, `Rules`, `Cleanup`, `Activity`, `AI`, `Feedback`, `About`) | window title becomes the pane name; `drive.sh wait-window AI 10` |
| Read a field | `$S/drive.sh value-of "Name template"` | expected on a fresh build: `value="{date} {type} {organization} {subject}" … enabled=false` (default template; content-aware rename is off) |
| Wait for UI text | `$S/drive.sh wait-text "Quarterly Report Q1.pdf" 10` | exit 0 when any element shows it |
| Inspect UI | `$S/drive.sh windows`, `$S/drive.sh cgwindows`, `$S/drive.sh tree 30` | AX windows / WindowServer windows (`<id> \| <title> \| frame`) / full AX tree |
| A download finishes in the watch folder | `$S/drive.sh drop <file> [name]` then `$S/drive.sh wait-file "<expected name>" 15` | the file is renamed in the inbox root (stable after ~2 s dwell) |
| See the folder / the log | `$S/drive.sh inbox`, `$S/drive.sh activity` | `ls -ld` of every inbox entry; stored Activity rows as JSON (`kind`, `beforePath`, `afterPath`, `renameSource`, `detail`) |

Live-proven so far (2026-10-09, screen locked): `status`, `extra` (`Open Activity`, `Settings…`), `menu Intake "Settings…"`, `cgwindows`, `drop`, `wait-file`, `inbox`, `activity`. The window-content commands (`press`, `value-of`, `wait-window`, `wait-text`, `windows`, `tree`) and window screenshots need an unlocked screen and have not yet been exercised live; their handles below come straight from the code. Treat the first unlocked run as their proof and fix this skill if a handle is off. First unlocked run (2026-10-11, 1.4.0 offline-model branch): `press` (buttons, sidebar rows, disclosure triangles), `wait-window`, `wait-text`, `tree` and per-window screenshots all worked.

Stable handles come from the code: menu titles (`MenuBarContentView.swift`, `IntakeApp.swift` `CommandGroup`), sidebar rows' `accessibilityLabel(pane.title)` (`SettingsRootView.swift`), control titles (`Toggle("…")`, `TextField("Name template", …)`), and window titles (Settings window = pane title, `Window("Activity")`). The app ships no `accessibilityIdentifier`s; none were needed.

`drop` writes to a dot-name in the inbox and renames it into place, the way a browser finishes a download. Default profile: Rename when download finishes **on**, Automatic organizing **on**, Wait before organizing **2 hours** — so a dropped file is renamed immediately and *not* filed during a run. To prove filing, use Organize Existing (it ignores Wait) — see `features/organize-existing.md`.

## Evidence

```bash
$S/evidence.sh snapshot before         # numbered folder: menu-bar-extra.txt, inbox.txt, activity.json, cgwindows.txt, ax-windows.txt, ax-tree.txt, window-*.png
$S/evidence.sh note "dropped quarterly-report-q1.pdf via drive.sh drop"
$S/evidence.sh path                    # .verify-intake/evidence/<RUN_ID>/
```

Evidence lives in **`.verify-intake/evidence/<RUN_ID>/`** (git-ignored, never removed by cleanup); `run.txt` there records PID, build path, bundle id, git SHA and the installed app's PID at launch. Screenshots are taken per window by CGWindowID (`screencapture -x -o -l<id>`) — never full-screen, so nothing else on the owner's screen is captured. Failures are written to `screenshot-errors.txt` in the snapshot, not hidden.

Proof standards for Intake:

- Exercise the real user path: a file landing in the watch folder, a menu item, a sidebar row. Never write the app's preferences to fake a state (the launch-time watch-folder argument is the only seeded state).
- Capture the action and the result: snapshot **before**, do the action (and `note` it), snapshot **after**.
- Verify side effects alongside the UI: the inbox listing (file renamed/moved), and the stored Activity JSON (`kind: renamed`, `renameSource: titleCase`, before/after paths). The menu bar extra's recent rows and the Activity window are the visible half.
- No mocks exist or are needed. Content-aware rename with the OpenRouter provider sends file text off the Mac — never drive it in verification. The on-device provider (**On this Mac**, Foundation Models) stays on the Mac; when the model is unavailable, turning the feature on shows a warning label in the AI pane and files keep their Title Case name — that warning is the observable result.

## Cleanup

```bash
$S/cleanup.sh                 # stop the recorded PID, empty IntakeVerifyInbox, `defaults delete app.intake.Intake.verify`, remove run/current.env
$S/cleanup.sh --purge-build   # …and delete .verify-intake/DerivedData and bin/
ls .verify-intake/evidence/   # evidence survives
```

Cleanup sends SIGTERM only to the recorded PID after re-checking it is the verification binary under `app.intake.Intake.verify`; it never escalates, never names the installed app's domain, and refuses (with the PID) if an unrecorded verification instance is still up. It ends by confirming the run's evidence folder still exists. Run it after every failed iteration too.

## Helpers

All in `.cursor/skills/verify-intake/scripts/` (executable; `lib.sh` is sourced by the others):

| Script | Invocation | Purpose |
|---|---|---|
| `build.sh` | `$S/build.sh` | isolated Debug build + `axdrive` compile; refuses if the bundle id is not `app.intake.Intake.verify` |
| `launch.sh` | `$S/launch.sh` | container bootstrap, launch with scratch profile, record PID, ready check |
| `doctor.sh` | `$S/doctor.sh` | read-only health/identity check |
| `drive.sh` | `$S/drive.sh <status\|extra\|menu\|press\|wait-window\|wait-text\|value-of\|windows\|cgwindows\|tree\|drop\|wait-file\|inbox\|activity>` | every drive action, PID-bound |
| `evidence.sh` | `$S/evidence.sh snapshot <label>` / `note "<text>"` / `path` | proof capture into the evidence folder |
| `cleanup.sh` | `$S/cleanup.sh [--purge-build]` | teardown that keeps evidence |
| `axdrive.swift` | built to `.verify-intake/bin/axdrive`; `axdrive <pid> <command>` (see header) | Accessibility API bound to one PID — the reason System Events is not used |
| `lib.sh` | sourced | paths, bundle ids, PID identity checks |

## Gotchas

- **Locked screen.** When the Mac is locked, macOS returns stub elements for an app's `AXWindows` and `screencapture` fails with `could not create image from window`; full-screen captures are black. The menu bar extra, main menu presses, the filesystem and `drive.sh activity` still work. Window-content steps (`press`, `value-of`, `tree`, screenshots) need the owner to unlock; report them as blocked, not passed.
- **Screen Recording permission** for the app running the shell (e.g. Grok Bot / Terminal) is needed for window screenshots; it cannot be checked while locked. If screenshots fail on an unlocked Mac, that permission is the missing piece (System Settings › Privacy & Security › Screen & System Audio Recording).
- **Accessibility permission** for the app running the shell is required; doctor reports it.
- Same process name: never use anything that addresses "Intake" by name (System Events processes, `pkill`, `killall`, `osascript 'tell application "Intake"'`) — any of them can hit the installed app.
- `open -b app.intake.Intake` and Spotlight resolve to the installed app; the verification build is opened by path only.
- Settings panes keep the last selection in `intake.settingsPane`; cleanup resets preferences, so each run starts on General.
- Rename on stable waits for a non-zero file to stay unchanged ~2 s; zero-byte files are never renamed. Hidden (dot) files and partial-download extensions (`.crdownload`, `.part`, `.download`, …) are ignored.
- The watch-folder profile is pinned by the launch argument, so settings changes to the folder made in General (Rename / Automatic organizing / Wait) are written to preferences but re-read from the argument on next launch; prove such toggles within one run.
- Docs order vs code: `docs/DESIGN.md` lists About before Feedback, but the sidebar (and ⌘6/⌘7) is `… AI, Feedback, About` (`SettingsPane.allCases`).

## Maintenance

Keep the map honest with `/maintain-verification-skill` (pstack): it audits each `features/*.md` against source and re-drives every feature with this skill. Edit only this directory (and `docs/FEATURE-MAP.md`, which the features README links as the map of record) during a maintenance pass.
