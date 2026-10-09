# Menu bar extra

Intake's menu bar icon (template soft-catch glyph; Watching vs Paused variants) opens a menu with the watch status, Pause/Resume, Organize Existing…, up to five recent Activity rows, and entry points to Activity, Cleanup, Settings and Feedback, plus Quit.

## Sub-features

- `extra-status` first two rows: title `Watching` / `Paused` / `Attention` and subtitle `New files in <folder>` / `Organizing is paused · <folder>` / `… needs folder access` (disabled rows). The status item's accessibility label is `Intake watching` / `Intake paused` / `Intake needs folder access`.
- `extra-pause` `Pause Organizing` ⇄ `Resume Organizing` pauses filing on every watch folder (rename can still run).
- `extra-organize` `Organize Existing…` (a submenu with `All Watch Folders` + each folder when there are several).
- `extra-recent` up to 5 rows `<file name> · <Renamed|Moved|Skipped|Error|Deleted|Removed>`; choosing one reveals it in Finder.
- `extra-open` `Open Activity`, `Open Cleanup` (Settings ▸ Cleanup), `Settings…` (⌘,), `Send Feedback…` (Settings ▸ Feedback).
- `extra-quit` `Quit Intake` (⌘Q).

## How to get to it (user POV)

- Click the Intake icon in the menu bar (Settings ▸ General ▸ Show in menu bar, on by default).

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0.

- **Read status.** Run `$S/drive.sh status`. Output starts `status item: Intake watching`, then `[Watching] (disabled)`, `[New files in IntakeVerifyInbox] (disabled)`.
- **Pause.** Run `$S/drive.sh extra "Pause Organizing"`, then `$S/drive.sh status`. Title `Intake paused`, rows `[Paused]`, `[Organizing is paused · IntakeVerifyInbox]`, and `[Resume Organizing]`.
- **Resume.** Run `$S/drive.sh extra "Resume Organizing"`. Back to `Watching`.
- **Recent rows.** After the `rename-on-download` recipe, `status` lists `[Quarterly Report Q1.pdf · Renamed]`.
- **Open Activity.** Run `$S/drive.sh extra "Open Activity"` then `$S/drive.sh cgwindows`. A window titled `Activity` is listed.
- **Open Cleanup / Settings.** Run `$S/drive.sh extra "Open Cleanup"`; `cgwindows` lists a window titled `Cleanup`. `$S/drive.sh extra "Settings…"` brings the Settings window (titled after the current pane).
- **Proof.** Run `$S/evidence.sh snapshot menu-bar` after each state change; `menu-bar-extra.txt` holds the item list.

## Gotchas

- Two Intake icons show while the installed app runs; System Events cannot tell them apart (same process name). `drive.sh` reads ours through the PID's `AXExtrasMenuBar`, which works even when a menu bar manager (Thaw) hides the icons off-screen.
- Do not choose `Quit Intake` to stop the app in a recipe unless you are proving Quit; use `cleanup.sh` (it re-checks the PID).
- Choosing a recent row opens Finder at the file — that is a real side effect on the screen; prefer the Activity window for proof.
