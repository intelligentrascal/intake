# Intake feature map

How to get around Intake — every surface, Settings pane, menu item and shortcut, and the main flows — written for an agent that has never seen the app. This is the **map of record**. Per-feature drive recipes (exact commands and the proof each step needs) live in the verification skill: [`.cursor/skills/verify-intake/features/`](../.cursor/skills/verify-intake/features/README.md), driven with [`.cursor/skills/verify-intake/SKILL.md`](../.cursor/skills/verify-intake/SKILL.md). Product intent is in [`PRODUCT.md`](PRODUCT.md), visual rules in [`DESIGN.md`](DESIGN.md); where those and the code differ, this map follows the code (file paths are given so it can be re-checked).

## Surfaces

| Surface | What it is | How a user reaches it | Source |
|---|---|---|---|
| Watch folders | Up to 5 folders (default `~/Downloads`). Files landing in a root are renamed, then filed into typed folders | Drop/download a file | `Intake/Watching/`, `IntakeCore/IngestPipeline.swift` |
| Menu bar extra | Template icon (Watching / Paused glyphs) with a status menu | Click the icon (Show in menu bar, on by default) | `Intake/MenuBar/MenuBarContentView.swift` |
| Dock icon | Regular app icon; click brings **Settings** forward (never Activity) | Dock (Show in Dock, on by default) | `IntakeApp.swift` (`applicationShouldHandleReopen`) |
| Settings window | Sidebar + 7 panes; window title = pane title | ⌘, / `Settings…` / Dock click / normal launch | `Intake/Settings/SettingsRootView.swift` |
| Activity window | Audit trail window titled `Activity`; suppressed at launch | `Open Activity`, Intake ▸ `Activity` | `Intake/Activity/ActivityWindowView.swift` |
| Sheets & alerts | Organize Existing preview/progress, rule editor, confirmations | From the actions below | `OrganizeExistingChrome.swift`, `RulesSettingsView.swift` |
| Notifications | Digests (off by default) with `Show Activity` / `Undo` | Settings ▸ General ▸ Notifications | `NotificationDigestService.swift` |

## Main menu (app menu "Intake")

Standard app menu plus, right after `Settings…` (⌘,), Intake's own items (`IntakeApp.swift` `CommandGroup(after: .appSettings)`):

| Item | Does | Shortcut |
|---|---|---|
| `Settings…` | Opens Settings (last pane, else General) | ⌘, |
| `Pause Organizing` / `Resume Organizing` | Pauses/resumes filing on every watch folder; Resume also turns Automatic organizing back on if nothing would organize | — |
| `Organize Existing…` | Organize Existing preview (a submenu `All Watch Folders` + each folder when there are several) | — |
| `Activity` | Opens the Activity window | — |
| `Quit Intake` | Quit | ⌘Q |

Other menus are the system's `Edit`, `View`, `Window`, `Help`.

## Menu bar extra

Top to bottom (`MenuBarContentView`):

1. Status title (disabled): `Watching` · `Paused` · `Attention` (with several folders: `Watching <n>` style summary). Icon accessibility label `Intake watching` / `Intake paused` / `Intake needs folder access`.
2. Status subtitle (disabled): `New files in <folder>` · `Organizing is paused · <folder>` · `<folder> needs folder access`.
3. `Pause Organizing` / `Resume Organizing`.
4. `Organize Existing…` (submenu with several folders).
5. Up to five recent Activity rows, `<file name> · <Renamed|Moved|Skipped|Error|Deleted|Removed>` — choosing one reveals it in Finder.
6. `Open Activity` · `Open Cleanup` (Settings ▸ Cleanup) · `Settings…` (⌘,) · `Send Feedback…` (Settings ▸ Feedback).
7. `Quit Intake` (⌘Q).

## Settings panes

The sidebar is a list of plain buttons (accessibility list `Settings sections`; each row's label is the pane name; ↑/↓ move between rows when the sidebar has focus). ⌘1–⌘7 jump straight to a pane. Order and shortcuts follow `SettingsPane.allCases`:

| ⌘ | Pane | Sections and key controls |
|---|---|---|
| ⌘1 | **General** | **Watch folder(s)**: one row per folder (name, path, status `Watching` / `Paused` / `Organizing off` / `Needs access`, `Actions for <folder>` menu: `Show in Finder`, `Change Folder…`, `Pause Organizing`/`Resume Organizing`, `Remove…`); lost access shows `Intake can’t see this folder` + `Grant Access…`; per-folder toggles `Automatic organizing`, `Rename when download finishes`, picker `Wait before organizing` (`Immediately`, `15 minutes`, `1 hour`, `2 hours` default, `1 day`) — inline with one folder, inside a disclosure (plus a `Name` field) with several; `Add Folder…` (menu `Screenshots (<folder>)…` / `Choose Folder…` when a screenshot location is suggested). **Existing files**: `Organize Existing…`, `Open Activity`. **Notifications**: `Notifications` master (off), `Filed`, `Errors`, `Cleanup`. **Startup and appearance**: `Open at login`, `Show in Dock`, `Show in menu bar` (turning both off shows `Keep one way to open Intake`). |
| ⌘2 | **Rules** | **Filing rules** list (built-ins: Documents, Spreadsheets, Presentations, Images, Video, Audio, Archives, Installers, Other); each row has an `Enable <folder> rule` toggle; buttons `Add Rule…`, `Edit…`, `Reset to Default`, `Delete` (⌘⌫); row context menu `Edit…`, `Move Up`, `Move Down`, `Reset to Default`, `Delete…`; reorder by drag or ⌥⌘↑ / ⌥⌘↓. **Conflicts** and **Unreachable rules** hint sections when relevant. **Suggestions** (only when present): `Accept`, `Dismiss`, `Never`, `Reset dismissed suggestions`. Rule editor sheet: `Destination folder`, `Extensions`, `Enabled`, `Subfolders` (`None`, `By year`, `By year and month`), **Conditions** (`Add Condition`; `Source is`, `Name contains`, `Name starts with`, `Name matches`, `Size at least`, `Size at most`), **Applies to** (`All Watch Folders` / `Specific folders`, shown with several folders or a scoped rule), `Cancel` / `Save`. |
| ⌘3 | **Cleanup** | `Watch folder` picker (several folders only), **Threshold** `Unused for [n] days` field + stepper, `Include loose files still in the watch folder`; **Queue** of candidates (Stale, Duplicate of …, abandoned download, `Installer for <app>`), multi-select; buttons `File Away` / `Keep` / `Delete…` (labels gain `<n> Items` with several selected); context menu `Quick Look`, `Reveal in Finder`, `File Away`, `Keep`, `Delete…`; delete confirms (`Delete` / `Cancel`) and moves to Trash. |
| ⌘4 | **Activity** | Read-only Activity list with an `Open Activity` header button; double-click or Control-click to reveal; no toolbar. |
| ⌘5 | **AI** | **Content-aware rename**: `Rename files from their contents` (off), `Naming provider` (`On this Mac` / `OpenRouter`), `PDFs`, `Images`, `Name template` (default `{date} {type} {organization} {subject}`; tokens `{date} {type} {organization} {subject} {original}`), `Try on a File…`; availability warnings for the on-device model; OpenRouter choice asks `Send file contents to OpenRouter?` (`Use OpenRouter` / `Cancel`). `Suggest folders with AI` (off). **OpenRouter**: `Enable OpenRouter`, `OpenRouter setup` disclosure (API key `Save Key`/`Replace Key`/`Remove Key…`, `Base URL`, `Model`), account info. **Intake spend** (only after spend > 0). |
| ⌘6 | **Feedback** | `Type` segmented (`Feature` / `Bug` / `Urgent`), `Title`, `Details`, `Email (optional)`, `Include diagnostics`, **Screenshots** `Add…` / `Paste` / `Remove`, `Open GitHub Issue` (opens a prefilled public issue in the browser; then `Almost done` alert). |
| ⌘7 | **About** | App name, `Downloads organizer`, `Version`, `License` (MIT), **Links** (`Security policy`, `Send Feedback…`), **Privacy** text. |

`docs/DESIGN.md` lists About before Feedback; the shipped order (and ⌘6/⌘7) is Feedback then About.

## Activity window

`Window("Activity")`, 640×520, never opened at launch. Empty state `No activity yet`. Rows: file name, subtitle, destination folder, `Undo` (renamed/moved rows; disabled with a reason such as `Too old to undo`). Toolbar: `Reveal in Finder` (needs a selection), `Pause`/`Resume`, `Settings`, and a `Folder` picker (`All Watch Folders` / each folder) with several folders. Row context menu: `Reveal in Finder`, `Copy path`, `Undo`. Double-click reveals. After a rename/move a bottom toast offers `Undo` (`Renamed to <name>`, `Moved to <folder>`, `Filed as <name> in <folder>`). Pending AI folder suggestions appear above the list as `Move <file> to <folder>?` with `Accept` / `Dismiss`.

## Keyboard shortcuts

| Shortcut | Where | Action |
|---|---|---|
| ⌘, | anywhere in Intake / menu bar extra | Settings |
| ⌘1 … ⌘7 | Settings window | General, Rules, Cleanup, Activity, AI, Feedback, About |
| ↑ / ↓ | Settings sidebar (focused) | previous / next pane |
| ⌘⌫ | Rules pane | delete selected rule (confirms) |
| ⌥⌘↑ / ⌥⌘↓ | Rules pane | move selected rule up / down |
| Delete | Cleanup queue | delete selected (confirms) |
| Space / double-click | Cleanup queue | Quick Look |
| Esc / Return | Organize Existing preview | `Cancel` / `Organize` |
| ⌘Q | anywhere | Quit Intake |

## Main flows

1. **Live ingest (per watch folder).** A stable file appears in the root (≈2 s unchanged, non-empty; dot files, `.crdownload`/`.part`/`.download` partials ignored) → if `Rename when download finishes` is on, renamed in place to Title Case (`quarterly-report-q1.pdf` → `Quarterly Report Q1.pdf`), Activity `Renamed` → if content-aware rename is on, a second content-based rename may follow → if `Automatic organizing` is on and not paused, after `Wait before organizing` (default 2 hours) the first matching rule files it into `<Category>/` (created lazily), Activity `Moved`. Recipe: [`rename-on-download.md`](../.cursor/skills/verify-intake/features/rename-on-download.md).
2. **Pause / Resume.** Menu bar extra, Intake menu, Activity toolbar, or a folder's actions menu; pausing stops filing but rename can still run. Recipe: [`menu-bar-extra.md`](../.cursor/skills/verify-intake/features/menu-bar-extra.md).
3. **Organize Existing.** Preview of renames/moves for loose root files → exclude → `Organize` or `Cancel`; ignores Wait. Recipe: [`organize-existing.md`](../.cursor/skills/verify-intake/features/organize-existing.md).
4. **Review and undo.** Activity window or Settings ▸ Activity; `Undo` restores name/location. Recipe: [`activity.md`](../.cursor/skills/verify-intake/features/activity.md).
5. **Content-aware rename (opt-in).** Settings ▸ AI; on-device by default, OpenRouter only after confirmation. Recipe: [`ai-content-aware-rename.md`](../.cursor/skills/verify-intake/features/ai-content-aware-rename.md).
6. **Rules.** Settings ▸ Rules: edit/add/reorder rules, conditions, scope, date subfolders; accept on-device suggestions.
7. **Cleanup.** Settings ▸ Cleanup (or `Open Cleanup`): decide on stale, duplicate, abandoned and installer files — File Away, Keep, Delete… (Trash, confirmed).
8. **Watch folders.** Settings ▸ General: add (folder picker grants sandbox access), change, pause, remove (not the last), grant access again.
9. **Feedback.** `Send Feedback…` → Settings ▸ Feedback → `Open GitHub Issue`.

## Where state lives

All settings are `UserDefaults` in the app's sandbox container (`~/Library/Containers/<bundle id>/Data/Library/Preferences/<bundle id>.plist`): `intake.watchFolderProfiles`, `intake.activity`, `intake.undoStack`, `intake.rules`, `intake.ruleEnabled`, `intake.contentAwareRename`, `intake.settingsPane`, `intake.showInDock`, `intake.showInMenuBar`, `intake.cleanupDays`, `intake.waitingForAge.<folder id>`, notification and OpenRouter keys. The OpenRouter API key is in Keychain (service `<bundle id>.openrouter`). The verification skill runs a separate bundle id (`app.intake.Intake.verify`) so none of this is shared with an installed copy.
