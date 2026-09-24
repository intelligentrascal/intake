# Intake — Product

## Purpose

Intake keeps `~/Downloads` (or a folder you choose) from becoming a junk drawer. When a file arrives, Intake renames it so a human can read it, then routes it into a typed folder — creating that folder only when the first matching file needs it. Empty Intake-managed folders can go away after cleanup.

## Users

People on macOS who download constantly and want the folder to stay navigable without babysitting it.

## Principles

1. **Lazy folders** — never pre-create empty category folders.
2. **Rename before route** — clarity first; Arc-like sensible names (local Title Case + small-word exceptions + small product/acronym allowlist — not Arc AI).
3. **Rules over magic** — deterministic extension/type rules by default; AI is opt-in assist.
4. **Private by default** — local FS only unless the user enables a provider.
5. **Reversible cleanup** — surface candidates; user files away or deletes; no silent mass delete.
6. **Native citizen** — Dock + menu bar + Settings; Apple HIG; no web chrome cosplay.

## Findability

**Feedback (v1.1.0):** Settings → Feedback opens a prefilled GitHub Issue in the browser (Option D — no PAT, no server). Menu bar **Send Feedback…** and About **Send Feedback…** open the same pane. Diagnostics default off; screenshots copy to the pasteboard for ⌘V on GitHub.


Users discover Intake from the **Dock** (on by default) and the **menu bar** (on by default, dense 16pt soft-catch template icon). Dock click, reopen, and a normal launch bring **Settings** forward (last pane or General). Activity is an audit window opened from the menu bar (**Open Activity**) or General. First-run shows a one-time tip: Intake lives in the Dock and the menu bar. Show in Dock / Show in menu bar can each be turned off, but **not both** — there must always be an icon that reopens Intake.

**Automatic organizing** is the Settings control for the live watcher (on by default). **Rename when download finishes** (on by default) is independent: it locally normalizes the file name in the watch-folder root as soon as the download is stable. The menu bar still uses Watching / Paused with Pause / Resume. Delete is never silent. AI is never on by default.

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
1. Detect new stable file in watch folder (ignore partial downloads such as `.crdownload` / `.part` / `.download` / `.duckload` and torrent / aria2 / yt-dlp partials, plus Quarantine churn). A repeated stable event for a file Intake already renamed or moved is dropped.
2. If **Rename when download finishes** is on (default), rename in place in the watch-folder root with the local, deterministic normalizer (structural clean, then **always** Title Case with small-word exceptions and a small allowlist such as `macOS` / `Q1`). Activity: `renamed` (file still in root). This does **not** wait. Files already inside category folders are not renamed. If the toggle is off, skip this step. One incoming file gives at most one renamed file: a collision suffix (`Name 2`) is added only when a *different* file already holds the name. Names compare like APFS (case-insensitive), so a case-only rename never collides with itself and `invoice.pdf` holds `Invoice.pdf`. If the name is held by a file with identical content, the suffixed name is kept and nothing is deleted.
3. If **Automatic organizing** is on, wait until **Wait before organizing** has passed since that **stable** moment (`stableAt` — not when the first byte appeared). Default is **2 hours**. Presets: Immediately, 15 minutes, 1 hour, 2 hours, 1 day. Wait gates **routing/filing only**. Immediately files as soon as the file is stable (right after step 2 when Rename is on). While waiting, Intake stays silent aside from the rename in step 2. If the file is moved or deleted before the wait ends, the pending item is dropped. Changing the wait re-evaluates from the same `stableAt`. Automatic organizing Off still allows step 2; it does not auto-move.
4. Match rule → ensure destination folder exists → move. Name from step 2 is preserved unless a collision suffix is needed. If Rename was off, rename still happens here when filing (legacy couple). Activity: `moved`.
5. Log to Activity. Optional OpenRouter (when enabled) still suggests a **folder** for Other only — it does not rename.

### Organize existing
Manual one-shot from the menu bar (**Organize Existing…**) or Settings → General. Scans **watch-folder root only** (does not recurse into Intake-managed category folders). Applies the same ignore policy and rename → route → Activity pipeline as live ingest, and **does not wait** for Wait before organizing. Confirmation before run; cancel stops scheduling new files. Allowed when Automatic organizing is off (does not turn watching back on). Never runs automatically on launch. Lazy folders only.

### Activity
Chronological **audit trail** of rename / move / skip / error (plus cleanup delete and empty-folder removal). It is **not** the Dock default. It is not the Cleanup queue. Rows persist across launches. Double-click a row, or use Reveal in Finder (toolbar or context menu) to open it in Finder. Context menu also copies the path. Selecting a row does not reveal it.

### Cleanup
1. Scan Intake-managed paths (and optionally loose files still in watch root).
2. Files not opened/modified for *N* days appear in Cleanup — a **decision queue**, never merged with Activity. Each row shows why it's there:
   - **Stale** — unopened/unmodified for the threshold, same as before.
   - **Duplicate** — same size, then a matching content hash, as another file in the watch root or an Intake-managed folder. The oldest file (by date added, then shortest name) is kept as the original; the row names it. Hashes are cached by path, size and modification date so unchanged files are never re-hashed.
   - **Abandoned download** — an incomplete-download extension (`.crdownload`, `.part`, etc.) whose size and modification date haven't changed for 24 hours. An actively-downloading file is never flagged.
   - **Installer** — a `.dmg`/`.pkg`/`.mpkg` in the watch-folder root or the Installers folder whose app is already on disk: the row names the matched app. The installer's base name is normalized (version numbers, arch tokens like `arm64`/`x86_64`, and words like "installer"/"setup" stripped) and compared against the display and bundle names of apps in `/Applications` and `~/Applications`; the match only counts when the app's date is after the installer's. `.pkg`/`.mpkg` prefer the installed package receipt (via `pkgutil`) when it's readable, falling back to the same name match otherwise. A `.dmg` whose disk image is currently mounted is skipped rather than flagged — Intake never mounts an image itself. **Keep** on an installer snoozes it (e.g. to hold onto it for another Mac).
   
   Duplicate, abandoned-download and installer rows skip the stale-days threshold — they show up regardless of age.
3. Actions: **File Away** (pick folder), **Delete** (confirm; Intake moves it to Trash), **Keep** (snooze / exclude) — same for every reason. Nothing is ever deleted without the user confirming.
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
