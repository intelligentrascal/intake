# Activity window

Activity is Intake's audit trail: one row per rename, move, skip, error, cleanup delete or empty-folder removal, newest first, persisted across launches. From a row the user can reveal the file in Finder, copy its path, or undo a rename/move. It is a separate window (`Activity`), never shown at launch, and the same list is embedded read-only in Settings ▸ Activity.

## Sub-features

- `activity-open` opens the `Activity` window from every entry point.
- `activity-empty` shows `No activity yet` / "When Intake renames or files a download, it shows up here." with no rows.
- `activity-rows` lists rows with file name, subtitle, destination folder (for moves) and an `Undo` button on renamed/moved rows.
- `activity-reveal` toolbar `Reveal in Finder` (enabled with a selection), double-click, or context menu `Reveal in Finder`.
- `activity-copy` context menu `Copy path`.
- `activity-undo` row `Undo` / context menu `Undo` restores the previous name or location; `Undo` toast after an action reads `Renamed to <name>` / `Moved to <folder>` / `Filed as <name> in <folder>`.
- `activity-toolbar` `Pause` ⇄ `Resume` and `Settings` toolbar items; a `Folder` picker (`All Watch Folders` + each folder) only with several watch folders.
- `activity-settings-pane` Settings ▸ Activity embeds the list with an `Open Activity` button in the section header, no toolbar.

## How to get to it (user POV)

- Menu bar extra ▸ `Open Activity`.
- Intake menu ▸ `Activity`.
- Settings ▸ General ▸ Existing files ▸ `Open Activity`; Settings ▸ Activity ▸ `Open Activity`.
- A notification digest's `Show Activity` action (only with Notifications on).

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0 with no `screen is LOCKED` warning (window contents need an unlocked screen).
- For rows, run the `rename-on-download` recipe first.

- **Empty state.** On a fresh launch run `$S/drive.sh extra "Open Activity"`, `$S/drive.sh wait-window Activity 10`, `$S/drive.sh wait-text "No activity yet" 5`.
- **Main menu entry.** Close nothing; run `$S/drive.sh menu Intake Activity`. The same single `Activity` window is front (`$S/drive.sh windows` shows one `Activity`).
- **Row appears.** After a drop, run `$S/drive.sh wait-text "Quarterly Report Q1.pdf" 10`. The AX tree (`$S/drive.sh tree 30`) shows a row labelled `Quarterly Report Q1.pdf, …`.
- **Settings pane entry.** Run `$S/drive.sh extra "Settings…"`, `$S/drive.sh press Activity`, `$S/drive.sh wait-window Activity 10` (the Settings window is now titled `Activity` too — check `cgwindows` shows two windows named `Activity` when both are open).
- **Undo.** Use the `Undo` button on the row (`$S/drive.sh press Undo`), then `$S/drive.sh wait-file quarterly-report-q1.pdf 10`. The inbox holds the original name again; `$S/drive.sh activity` keeps the history.
- **Proof.** Run `$S/evidence.sh snapshot activity` after each state. `window-Activity.png`, `ax-tree.txt` and `activity.json` must agree.

## Gotchas

- The window stays suppressed at launch by design; only the entry points above open it.
- Settings and the standalone window can both be titled `Activity`; use `cgwindows` ids, not titles alone, when screenshotting.
- Each row is one combined accessibility element (`accessibilityElement(children: .combine)`); if `press Undo` finds no separate button, use the row's context menu in a visible session or prove Undo from the toast.
- `Reveal in Finder` / double-click open Finder windows on the owner's screen; capture and close them, or prove reveal by the enabled state only.
- Undo can be refused (`Too old to undo`, `Can’t undo — file not found.`, `Can’t undo — something else is using that name.`); a disabled `Undo` with that help text is the observable result.
