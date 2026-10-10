# Intake verification map

This directory is the maintained source for verifying Intake's user-facing behavior with the `verify-intake` skill. Read this index, then use the matching feature file as the recipe. The consolidated navigation map of record — every Settings pane, menu item, shortcut and main flow — is [`docs/FEATURE-MAP.md`](../../../../docs/FEATURE-MAP.md); these files are the per-feature drive recipes and must not contradict it.

## Baseline preconditions

- Build and launch only the verification copy: `S=.cursor/skills/verify-intake/scripts; $S/build.sh && $S/launch.sh` (bundle id `app.intake.Intake.verify`, display name `Intake Verify`).
- Its only watch folder is `IntakeVerifyInbox` at `~/Library/Containers/app.intake.Intake.verify/Data/IntakeVerifyInbox`, with Rename when download finishes on, Automatic organizing on, Wait before organizing 2 hours.
- Preferences start empty (cleanup runs `defaults delete app.intake.Intake.verify`): no Activity, built-in rules only, content-aware rename off, OpenRouter off, Notifications off.
- `$S/doctor.sh` exits 0 before the first drive and after any failed drive.
- Never drive the installed app (`app.intake.Intake`), never touch `~/Downloads`, never address Intake by process name.

## Driving conventions

- Every action goes through `$S/drive.sh` (PID-bound Accessibility via `axdrive`). No System Events, no synthetic keystrokes.
- Prefer menu titles, sidebar row labels and control titles exactly as written in code; keep quoted strings literal (they use `…` U+2026, not three dots).
- A file "arriving" is `$S/drive.sh drop <file> <name>`; wait on the filesystem (`wait-file`), not a sleep.
- Start each recipe from the baseline; run `$S/cleanup.sh` between recipes that leave files or settings behind.

## Proof and skip reporting

- `$S/evidence.sh snapshot before`, act (`$S/evidence.sh note "<action + command>"`), `$S/evidence.sh snapshot after`.
- UI proof: window PNG (per-window capture) plus `menu-bar-extra.txt` / `ax-tree.txt` from the snapshot.
- Side-effect proof: `inbox.txt` (names and locations) and `activity.json` (stored rows) from the same snapshot.
- Evidence stays in `.verify-intake/evidence/<RUN_ID>/` after cleanup.
- If a step needs an unlocked screen, Screen Recording, Apple Intelligence, or network, report it as unreachable with the command tried and the missing prerequisite. Do not report it verified through another entry point.

## Feature entry contract

Each feature file starts with an H1 and one paragraph describing the user-visible behavior, then exactly four H2s in order: `Sub-features`, `How to get to it (user POV)`, `Driving it with verify-intake`, `Gotchas`. Keep implementation details out unless they are a stable handle or a trap.

## Features

- [Rename when download finishes](./rename-on-download.md) — a file landing in a watch folder gets a Title Case name, logged to Activity. **Proven live.**
- [Menu bar extra](./menu-bar-extra.md) — status, Pause/Resume, Organize Existing…, recent Activity rows, Open Activity / Cleanup / Settings / Feedback, Quit. **Proven live** (status, recent rows, Open Activity).
- [Activity window](./activity.md) — the audit trail, Reveal, Copy path, Undo.
- [AI pane: content-aware rename](./ai-content-aware-rename.md) — default name template, naming provider, file types, Try on a File…, OpenRouter gating.
- [Organize Existing](./organize-existing.md) — preview, exclude, Cancel / Organize for files already in the watch-folder root.
- [Offline model](./offline-model.md) — `Set Up Offline Renaming…`, the setup window (O1–O5), download / pause / cancel, the Settings ▸ AI card and Run the offline model, `Waiting to rename` rows.

Not yet mapped (see `docs/FEATURE-MAP.md` for their UI): Rules editor and suggestions, Cleanup queue, General watch-folder management, Notifications, Feedback, About.
