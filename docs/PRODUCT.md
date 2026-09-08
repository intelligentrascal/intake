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

Users discover Intake from the **Dock** (on by default) and the **menu bar** (on by default, soft-catch template icon). First-run shows a one-time tip: Intake lives in the menu bar. Show in Dock / Show in menu bar can each be turned off, but **not both** — there must always be an icon that reopens Settings.

Pause is always one click away. Delete is never silent. AI is never on by default.

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

Users can edit rules later. Folder names are localizable later; English defaults for v1. Enabled rules persist across launches.

## Core flows

### Ingest
1. Detect new stable file in watch folder (ignore partial downloads / `.download` / Quarantine churn).
2. Propose rename → apply (with undo window if feasible).
3. Match rule → ensure destination folder exists → move.
4. Log to Activity.

### Activity
Chronological **audit trail** of rename / move / skip / error (plus cleanup delete and empty-folder removal). It is not the Cleanup queue. Rows persist across launches. Select a row to Reveal in Finder.

### Cleanup
1. Scan Intake-managed paths (and optionally loose files still in watch root).
2. Files not opened/modified for *N* days appear in Cleanup — a **decision queue**, never merged with Activity.
3. Actions: **File Away** (pick folder), **Delete** (confirm), **Keep** (snooze / exclude).
4. After moves/deletes, remove empty Intake-created category folders.

### AI (phase 2)
Pluggable providers: local **Ollama**, optional CLIs (`claude`, `agent`/`cursor`, `codex`) when installed. Used for suggest-name / suggest-bucket when rules miss. Off by default; mix-and-match. Never required for core ingest.

## Chrome

| Surface | Default | Notes |
|---|---|---|
| Dock | **On** | Regular activation policy. Clicking the Dock icon brings Settings (or the last Settings pane) forward. Hiding the Dock does not quit. |
| Menu bar | **On** | Status, pause/resume, recent activity (Reveal), Settings…, Quit. Optional Open Activity / Open Cleanup while Dock is on. |
| Both off | **Forbidden** | Alert: “Keep one way to open Intake.” |

Do **not** ship a permanent `LSUIElement=1` Info.plist default. Dock visibility uses runtime `NSApplication.ActivationPolicy` (`.regular` vs `.accessory`).

## Non-goals (v1)

- Full Finder replacement
- Cloud sync of file contents for organizing
- Windows/Linux
- Copying Thaw or other GPL UI source
- Managing or restyling other apps’ menu bar items

## Success

Downloads root stays mostly empty of sorted types; category folders exist only when populated; Cleanup makes “I haven’t touched this in weeks” actionable without fear.
