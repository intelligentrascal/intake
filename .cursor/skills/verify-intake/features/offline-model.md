# Offline model (offline renaming setup)

Since 1.4, content-aware rename defaults to the **Offline model** provider: a model Intake downloads once and runs on this Mac. The `Set Up Offline Renaming` window walks through O1 welcome → O2 recommended size (or **Choose another size…**) → O3 download → O4 checking → O5 ready, with a **Use the offline model for renaming** checkbox. Until a model is installed, the menu bar extra shows `Set Up Offline Renaming…`; while one downloads, it shows a `Downloading model · <n>%` row and the icon draws a progress ring. Settings ▸ AI shows an **Offline model** card and, once installed, **Run the offline model** (`Smart (recommended)` / `Always` / `Only when plugged in`). Files that can't be renamed yet wait in a queue and show as `Waiting to rename` in the menu and Activity.

## Sub-features

- `offline-menu-item` with the provider on Offline model and no model installed, the menu bar extra has exactly one top-level `Set Up Offline Renaming…` item (no submenu); choosing it opens the setup window at O2.
- `offline-o2` O2 names one recommended size with its verbatim tier line (`Best — 2.5 GB download · most accurate`, `Standard — 1.28 GB download · accurate for everyday files`, `Lite (CPU) — 533 MB · renames when plugged in`); `Choose another size…` shows a radio list with `Recommended` and disabled-reason captions (Intel lists Lite (CPU) only; 8 GB Macs disable Best).
- `offline-skip` `Skip for Now` closes the window; content-aware rename stays off and files keep Title Case names.
- `offline-download` O3 `Downloading <tier> model` with progress (`1.2 GB of 2.5 GB · about 3 minutes left`), `Pause` / `Resume`, `Cancel Download` → alert `Cancel the download? You can resume it from Settings within 24 hours.` (`Keep Downloading` default / `Cancel Download`). Metered connections ask first (`Wait for Wi-Fi` default).
- `offline-menu-download` while downloading: menu rows `Downloading model · <n>%` (or `· Paused at <size>`, `Checking the download…`), `Pause Download` / `Resume Download`, `Cancel Download…` (opens the setup window to confirm). `Set Up Offline Renaming…` is hidden.
- `offline-ready` O5 `Use the offline model for renaming` (on for new and Apple Intelligence users, off for OpenRouter users), `Done`. Settings ▸ AI card: `<size> on disk · Runs on this Mac. File contents never leave it.`, `Status` (`In memory` / `Unloaded to save memory`), `Change Size…`, `Delete Model`, `About this model` (the only place model names appear).
- `offline-queue` a file that can't be renamed now (battery, heat, memory, Low Power Mode) gets its Title Case name, a menu line `<n> files waiting to rename · <reason>` with `Rename Now` / `Rename All Now`, and an Activity `Waiting to rename` row with `Rename Now`. A deferred rename logs `Renamed after filing · in <folder>` with Undo.
- `offline-upgrade` an upgrader from 1.3.x sees the one-time sheet `New: rename files offline` (`Set Up…` / `Not Now`) over Settings ▸ AI.
- `offline-reminder` 7 days after Skip, once: a notification (`Set Up…` / `Not Now`) only if notifications are already allowed, otherwise a monochrome dot on the menu bar icon and the `Set Up Offline Renaming…` item.

## How to get to it (user POV)

- First launch opens the setup window by itself (after about half a second).
- Menu bar extra ▸ `Set Up Offline Renaming…`.
- Settings ▸ AI (⌘5) ▸ Offline model card ▸ `Download <size>` / `Other Sizes…` / `Change Size…`.
- Upgrade sheet `Set Up…`; reminder notification `Set Up…`.

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0 with no `screen is LOCKED` warning.
- Fresh preferences (run `$S/cleanup.sh` before `$S/launch.sh`).
- A real download needs network and 0.5–2.5 GB of disk. Without them, stop at O2/O3 and report the download steps unreachable.

- **Menu item.** Run `$S/drive.sh status`. The list contains `[Set Up Offline Renaming…]` once and no submenu for it.
- **Open setup.** Run `$S/drive.sh extra "Set Up Offline Renaming…"`, then `$S/drive.sh wait-window "Set Up Offline Renaming" 10`. `$S/drive.sh wait-text "Choose another size…" 5` passes; `wait-text "download ·" 5` (or `"533 MB ·"` on Intel) finds the recommended tier line.
- **Tier list.** Run `$S/drive.sh press "Choose another size…"` (an `AXDisclosureTriangle`; `axdrive press` accepts it), then `$S/evidence.sh snapshot offline-o2`. `window-Set Up Offline Renaming.png` and `ax-tree.txt` show the radio list and the `Recommended` caption.
- **Skip.** Run `$S/drive.sh press "Skip for Now"`. `$S/drive.sh cgwindows` no longer lists the setup window; `status` still lists `[Set Up Offline Renaming…]`.
- **Download (network only).** Reopen setup, press the `Download <size>` button, wait `wait-text "left" 30`, then `$S/drive.sh status`: a `Downloading model · <n>%` row, `Pause Download`, `Cancel Download…`, and no `Set Up Offline Renaming…`. Press `Cancel Download` in the window; `wait-text "Cancel the download? You can resume it from Settings within 24 hours." 5`; press `Keep Downloading` (or `Cancel Download` to end the run).
- **Settings card.** Run `$S/drive.sh extra "Settings…"`, `$S/drive.sh press AI`, `$S/drive.sh wait-window AI 10`, then `wait-text "Offline model" 5`. Snapshot `offline-settings`.
- **Proof.** `$S/evidence.sh snapshot <name>` after each state; `menu-bar-extra.txt` holds the menu rows, the window PNGs show the setup screens.

## Gotchas

- The verification build stores models in its own container (`~/Library/Containers/app.intake.Intake.verify/Data/Library/Application Support/Intake/Models`). `cleanup.sh` resets preferences but not that folder; delete the model with `Delete Model` (or remove the folder) if a run must start without one.
- A finished download installs only after the SHA-256 check and a self-test that loads the model, which can take tens of seconds; wait on `wait-text "Use the offline model for renaming" 120`, not a sleep.
- Battery, heat and Low Power Mode change whether files rename right away or queue. Record power state (`pmset -g batt`) with the evidence; on AC with nothing else going on, new files rename at once and no `Waiting to rename` row appears.
- Do not leave a large download running between recipes; cancel it (the partial is kept for 24 h) or let it finish.
- The reminder needs 7 days since Skip and is not drivable in a single run; report it as unreachable.
- `launch.sh` passes `-intake.didShowMenuBarTip YES`, and `OfflineModelMigration.isUpgrade` counts that key as a prior install, so a fresh verification container takes the **upgrade** path: the `New: rename files offline` sheet over Settings ▸ AI instead of O1. Drive `Set Up…` there to reach O2. O1 (first-run auto-open) is not reachable with the current launch arguments.
- The `Naming provider` pop-up has no AX title; AXPress on it does not open its menu from `axdrive`, so read the selected value from `ax-tree.txt` (`AXPopUpButton value="Offline model"`).
- Live-proven 2026-10-11 (unlocked, Apple silicon, 32 GB): upgrade sheet, O2 recommendation and tier list, Skip for Now, the menu item reopening O2, and the Settings card (not downloaded). No download was started.
