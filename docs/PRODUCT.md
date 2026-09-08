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
6. **Native citizen** — menu bar + Settings; Apple HIG; no web chrome cosplay.

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

Users can edit rules later. Folder names are localizable later; English defaults for v1.

## Core flows

### Ingest
1. Detect new stable file in watch folder (ignore partial downloads / `.download` / Quarantine churn).
2. Propose rename → apply (with undo window if feasible).
3. Match rule → ensure destination folder exists → move.
4. Log to Activity.

### Cleanup
1. Scan Intake-managed paths (and optionally loose files still in watch root).
2. Files not opened/modified for *N* days appear in Cleanup.
3. Actions: **File away** (pick folder / rule), **Delete**, **Keep** (snooze / exclude).
4. After moves/deletes, remove empty Intake-created category folders.

### AI (phase 2)
Pluggable providers: local **Ollama**, optional CLIs (`claude`, `agent`/`cursor`, `codex`) when installed. Used for suggest-name / suggest-bucket when rules miss. Off by default; mix-and-match. Never required for core ingest.

## Non-goals (v1)

- Full Finder replacement
- Cloud sync of file contents for organizing
- Windows/Linux
- Copying Thaw or other GPL UI source

## Success

Downloads root stays mostly empty of sorted types; category folders exist only when populated; Cleanup makes “I haven’t touched this in weeks” actionable without fear.
