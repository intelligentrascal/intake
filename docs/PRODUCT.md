# Intake — Product

## Purpose

Intake keeps `~/Downloads` (or a folder you choose) from becoming a junk drawer. When a file arrives, Intake renames it so a human can read it, then routes it into a typed folder — creating that folder only when the first matching file needs it. Empty Intake-managed folders can go away after cleanup.

## Users

People on macOS who download constantly and want the folder to stay navigable without babysitting it.

## Principles

1. **Lazy folders** — never pre-create empty category folders.
2. **Rename before route** — clarity first; Arc-like sensible names.
3. **Rules over magic** — deterministic extension/type rules by default; AI is opt-in assist.
4. **Private by default** — local FS only unless the user enables a provider.
5. **Reversible cleanup** — surface candidates; user files away or deletes; no silent mass delete.
6. **Native citizen** — Dock + menu bar + Settings; Apple HIG; no web chrome cosplay.

## Findability

Users discover Intake from the **Dock** (on by default) and the **menu bar** (on by default, dense 16pt soft-catch template icon). Dock click, reopen, and a normal launch bring **Settings** forward (last pane or General). Activity is an audit window opened from the menu bar (**Open Activity**) or General. First-run shows a one-time tip: Intake lives in the Dock and the menu bar. Show in Dock / Show in menu bar can each be turned off, but **not both** — there must always be an icon that reopens Intake.

**Automatic organizing** is the Settings control for the live watcher (on by default). The menu bar still uses Watching / Paused with Pause / Resume. Delete is never silent. AI is never on by default.

## Default taxonomy (under the watch folder)

| Folder | Typical contents |
|---|---|
| Documents | pdf, doc, docx, pages, txt, rtf, odt, md |
| Spreadsheets | xls, xlsx, numbers, csv, tsv |
| Presentations | ppt, pptx, key, odp (Google Slides often arrives as pdf/pptx) |
| Images | png, jpg, jpeg, heic, webp, gif, svg, tiff |
| Video | mp4, mov, m4v, mkv, webm |
| Audio | mp3, m4a, wav, aiff, flac |
| Archives | zip, 7z, rar, tar, gz |
| Installers | dmg, pkg (may share Archives via rules) |
| Other | unmatched types (folder only if something lands here) |

Users can edit rules: extensions, destination folder name, enable, order (drag), add/delete custom rules. Built-in categories keep a stable id; renaming a folder name applies to **new** routes only (existing folders are not mass-renamed). Conflicting extensions resolve by list order (first enabled match wins). Empty folders are never pre-created.

The Rules pane also shows **on-device suggestions** from the watch-folder root histogram and Activity (skipped / Other). Accept creates or updates a persisted rule; Dismiss hides for 30 days; Never suppresses that extension until reset. Suggestions need repeating uncovered types (8 hits, or 5 in 14 days). Cold start is empty — no fake examples. Computation is local; no network; no file contents.

## Core flows

### Ingest
1. Detect new stable file in watch folder (ignore partial downloads / `.download` / Quarantine churn).
2. If **Automatic organizing** is on, wait until **Wait before organizing** has passed since that **stable** moment (`stableAt` — not when the first byte appeared). Default is **2 hours**. Presets: Immediately, 15 minutes, 1 hour, 2 hours, 1 day. Immediately files as soon as the file is stable. While waiting, Intake stays silent (no Activity spam). If the file is moved or deleted before the wait ends, the pending item is dropped. Changing the wait re-evaluates from the same `stableAt`.
3. Propose rename → apply (with undo window if feasible).
4. Match rule → ensure destination folder exists → move.
5. Log to Activity.

### Organize existing
Manual one-shot from the menu bar (**Organize Existing…**) or Settings → General. Scans **watch-folder root only** (does not recurse into Intake-managed category folders). Applies the same ignore policy and rename → route → Activity pipeline as live ingest, and **does not wait** for Wait before organizing. Confirmation before run; cancel stops scheduling new files. Allowed when Automatic organizing is off (does not turn watching back on). Never runs automatically on launch. Lazy folders only.

### Activity
Chronological **audit trail** of rename / move / skip / error (plus cleanup delete and empty-folder removal). It is **not** the Dock default. It is not the Cleanup queue. Rows persist across launches. Double-click a row, or use Reveal in Finder (toolbar or context menu) to open it in Finder. Context menu also copies the path. Selecting a row does not reveal it.

### Cleanup
1. Scan Intake-managed paths (and optionally loose files still in watch root).
2. Files not opened/modified for *N* days appear in Cleanup — a **decision queue**, never merged with Activity.
3. Actions: **File Away** (pick folder), **Delete** (confirm; Intake moves it to Trash), **Keep** (snooze / exclude).
4. After moves/deletes, remove empty Intake-created category folders.

### AI
Optional **OpenRouter** provider: Keychain API key, base URL, model. Master AI suggestions toggle and OpenRouter stay **off by default**. Network runs only when both are on, and only on rule miss / Other — filename and extension, not file contents. Ollama, Claude CLI, Cursor agent CLI (`agent` and/or `cursor` on PATH), and Codex CLI rows show **Available** vs **Not installed** from a PATH check; they are not called for suggestions yet.

## Chrome

| Surface | Default | Notes |
|---|---|---|
| Dock | **On** | Regular activation policy. Clicking the Dock icon (or launching like a normal app) brings **Settings** forward. Hiding the Dock does not quit. |
| Menu bar | **On** | Status, pause/resume, Organize Existing…, Open Activity, Settings…, Quit. Dense 16pt template glyphs (Watching vs Paused). No wait countdown. The extra follows the system menu bar; macOS does not offer a supported way to pin it to every display. |
| Both off | **Forbidden** | Alert: “Keep one way to open Intake.” |

Do **not** ship a permanent `LSUIElement=1` Info.plist default. Dock visibility uses runtime `NSApplication.ActivationPolicy` (`.regular` vs `.accessory`). Settings stay reachable via Dock click, ⌘,, and **Settings…**.

## Non-goals (v1)

- Full Finder replacement
- Cloud sync of file contents for organizing
- Windows/Linux
- Copying Thaw or other GPL UI source
- Managing or restyling other apps’ menu bar items
- React / web mesh or shadcn chrome

## Success

Downloads root stays mostly empty of sorted types; category folders exist only when populated; Cleanup makes “I haven’t touched this in weeks” actionable without fear.
