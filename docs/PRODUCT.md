# Intake — Product

## Purpose

Intake keeps `~/Downloads` (or a folder you choose) from becoming a junk drawer — and, since 1.4, up to five **watch folders** such as Desktop or Screenshots. When a file arrives, Intake renames it so a human can read it, then routes it into a typed folder inside the watch folder it came from — creating that folder only when the first matching file needs it. Empty Intake-managed folders can go away after cleanup.

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

**Watch folders (v1.4):** Settings → General lists every watch folder with its status (Watching / Paused / Needs access) and a per-folder menu: Show in Finder, Change Folder…, Pause / Resume, Remove…. **Add Folder…** offers the system screenshot location (the `com.apple.screencapture` `location` setting when present, otherwise Desktop) as a one-click start, and **Choose Folder…** for anything else; access is always granted through the folder picker (sandbox). Each folder has its own **Automatic organizing**, **Rename when download finishes** and **Wait before organizing** — the Organizing section edits the folder picked at its top — plus a display name. A folder is rejected if it is the same as, inside, or contains another watch folder, or is one of Intake's category folders (including a date subfolder in one). Soft cap of **5** folders. The last folder can't be removed. Pausing, removing or losing access to one folder leaves the others running; a folder whose access was lost shows **Intake can't see this folder** with **Grant Access…**.

**Upgrading from 1.2/1.3:** the single watch folder, its bookmark, its Rename / Wait / Automatic organizing settings and its pending Wait queue become watch folder #1 on first launch, unchanged. Older Activity rows count as folder #1. With one folder, Settings, the menu bar and Activity read as before.

**Notifications (v1.4, digest):** a master toggle in Settings → General, **off by default**, plus per-type toggles for Filed, Errors, and Cleanup. Turning the master toggle on is the only time Intake asks for notification permission — it is never requested at launch or for an off toggle. Rather than one notification per file, filing entries batch into a single digest that flushes after 5 minutes with no new filings or at 50 entries, whichever comes first, and shows counts by destination folder. A digest covering exactly one filed item offers **Undo** (through the existing Undo path) alongside **Show Activity**, which every digest offers. Errors are always delivered on their own, immediately but throttled to at most one digest a minute. A finished Cleanup scan is summarized once, covering only items not already notified about. Rename-only entries (no move) are left out of the Filed digest by default. System Focus modes and notification settings apply as usual.

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

### Rule conditions (v1.3)

A rule can carry an optional list of **conditions**, all combined with AND, in addition to its extension set:

- **Source domain** — matches the file's host or any parent domain, ignoring case (a rule for `bank.com` matches `secure.bank.com`).
- **Name contains / starts with / matches wildcard** (`*`, `?`) — matches the file name without its extension, ignoring case.
- **Size at least / at most** — matches by file size in bytes.

A rule's extension set can be left empty to mean "any type," but only once it has at least one condition — a rule with no extensions and no conditions can't be saved. Conditions are edited in the rule editor's **Conditions** section, which also shows recently seen source domains as a hint. Rules saved before 1.3 decode with an empty condition list and behave exactly as before.

**Source domain** comes from the where-from download metadata macOS/browsers already write on a file (the `kMDItemWhereFroms` extended attribute) — the first URL's host, or the referrer's host if the first has none. This is local file-system metadata only; Intake never makes a network request to resolve it. A file with no where-from metadata (e.g. copied in by hand) simply fails any source-domain condition and falls through to the next rule.

First-enabled-rule-wins by list order is unchanged. The Rules pane flags rules that can **never be reached** because an earlier enabled rule already matches everything they would — reorder the more specific rule first to fix it. Activity rows show the file's source domain when known.

The Rules pane also shows **on-device suggestions** from the watch-folder root histogram and Activity (skipped / Other). Accept creates or updates a persisted rule; Dismiss hides for 30 days; Never suppresses that extension until reset. Suggestions need repeating uncovered types (8 hits, or 5 in 14 days). Cold start is empty — no fake examples. Computation is local; no network; no file contents. Suggestions always propose extension-only rules.

### Rule scope (v1.4)

Rules stay one global ordered list. Each rule applies to **All watch folders** (the default, and what every rule saved before 1.4 loads as) or to **specific folders** chosen in the rule editor's **Applies to** section (shown once there are two or more folders, or when a rule is already scoped). Each watch folder is organized with the rule list narrowed to the rules in its scope — first-enabled-match-wins by list order is unchanged — so a Screenshots rule scoped to Desktop never touches Downloads. Conflict and unreachable-rule hints only compare rules whose scopes overlap. Removing a watch folder drops it from every rule's scope; a rule left with no folder is turned off (and reset to all folders) rather than silently widened.

### Date subfolders (v1.4)

A rule can organize files into **date-based subfolders** within its destination folder:

- **None** (default) — no subfolder: `Images/photo.jpg`.
- **By year** — yearly subfolder: `Images/2026/photo.jpg`.
- **By year and month** — monthly subfolder: `Images/2026-09/photo.jpg`.

The date comes from:
- For live ingest: the file's **stable moment** (`stableAt`), the timestamp when Intake first detected the download was complete.
- For Organize Existing: the file's **date added** (modification date), falling back to **creation date** if unavailable.

Subfolders use the **Gregorian calendar** in the user's current time zone, formatted zero-padded (`YYYY` or `YYYY-MM`). Subfolders are created **lazily** only when the first matching file needs them — the preview marks them as **New folder**. Changing a rule's pattern affects **new filings only**; existing folders keep their structure. Empty date subfolders are removed by the **Cleanup** job the same way managed category folders are, including nested empty subfolders. Undo works through absolute before/after paths, so moving a file out of a date subfolder and running cleanup will remove the empty subfolder.

## Core flows

### Ingest
Each watch folder runs this flow on its own — its own watcher, Wait queue, security-scoped access and settings — filing into category folders inside that watch folder.

1. Detect new stable file in watch folder (ignore partial downloads such as `.crdownload` / `.part` / `.download` / `.duckload` and torrent / aria2 / yt-dlp partials, plus Quarantine churn). A repeated stable event for a file Intake already renamed or moved is dropped.
2. If **Rename when download finishes** is on (default), rename in place in the watch-folder root with the local, deterministic normalizer (structural clean, then **always** Title Case with small-word exceptions and a small allowlist such as `macOS` / `Q1`). Activity: `renamed` (file still in root). This does **not** wait. Files already inside category folders are not renamed. If the toggle is off, skip this step. One incoming file gives at most one renamed file: a collision suffix (`Name 2`) is added only when a *different* file already holds the name. Names compare like APFS (case-insensitive), so a case-only rename never collides with itself and `invoice.pdf` holds `Invoice.pdf`. If the name is held by a file with identical content, the suffixed name is kept and nothing is deleted.
   - **Content-aware rename** (off by default, see AI): right after the Title Case rename, if the file's type is selected, a background job reads it on this Mac and proposes a name such as `2026-09-14 Invoice Acme.pdf`. A name that passes validation is applied as a **second** `renamed` row with rename source **content-aware** (undoable like any rename); any rejection keeps the Title Case name and writes nothing. Follows the folder's **Rename when download finishes** setting.
3. If **Automatic organizing** is on, wait until **Wait before organizing** has passed since that **stable** moment (`stableAt` — not when the first byte appeared). Default is **2 hours**. Presets: Immediately, 15 minutes, 1 hour, 2 hours, 1 day. Wait gates **routing/filing only**. Immediately files as soon as the file is stable (right after step 2 when Rename is on). While waiting, Intake stays silent aside from the rename in step 2. If the file is moved or deleted before the wait ends, the pending item is dropped. Changing the wait re-evaluates from the same `stableAt`. Automatic organizing Off still allows step 2; it does not auto-move.
4. Match rule → ensure destination folder exists → move. With a content-aware job running, filing waits for its name or **30 seconds**, whichever comes first, so rules (including name conditions) see the richer name; if the name arrives after the file was filed, the file is renamed in place in its category folder. Name from step 2 is preserved unless a collision suffix is needed. If Rename was off, rename still happens here when filing (legacy couple). Activity: `moved`.
5. Log to Activity. Optional OpenRouter (when enabled) still suggests a **folder** for Other only — it does not rename.

### Organize existing
Manual one-shot from the menu bar (**Organize Existing…**) or Settings → General. With several watch folders it's a menu: **All Watch Folders** or one folder; each folder is scanned and previewed with its own scoped rules, and the preview names the folder on each group. Scans **watch-folder root only** (does not recurse into Intake-managed category folders). Applies the same ignore policy and rename → route → Activity pipeline as live ingest, and **does not wait** for Wait before organizing. Allowed when Automatic organizing is off (does not turn watching back on). Never runs automatically on launch. Lazy folders only.

**Preview before Apply.** Any run with at least one eligible file opens a preview instead of the old confirmation alert. Every eligible file is mapped through the same rename/route pipeline live ingest uses and shown grouped by destination folder, with a count per folder and **New folder** marked for a destination that doesn't exist yet. Collision suffixes (`Name 2`) are computed by simulating the destination listing case-insensitively, so the preview matches what Apply actually produces. With content-aware rename on, the preview reads eligible files on this Mac (up to 40 per run; Organize waits until reading finishes) and shows their content-aware names, marked **Named from contents**; rules match against that name and Apply writes the Title Case and content-aware `renamed` rows before the `moved` row. Files left out of `eligible` are listed with why: **Still downloading**, **Ignored**, or **Empty placeholder**. The user can exclude a single file or an entire folder group before applying; excluded files are left untouched. **Cancel** closes the preview without touching anything — building it never writes to disk. **Organize** applies only the files still selected: each one is re-checked immediately before it's touched, and a file that was moved/deleted or whose size no longer matches what the preview saw is logged to Activity as `skipped` (not an error) instead of being filed. Activity and Undo behave exactly as they do for a live-ingest rename/move.

### Activity
Chronological **audit trail** of rename / move / skip / error (plus cleanup delete and empty-folder removal). It is **not** the Dock default. It is not the Cleanup queue. Rows persist across launches. Double-click a row, or use Reveal in Finder (toolbar or context menu) to open it in Finder. Context menu also copies the path. Selecting a row does not reveal it. Each row records the watch folder it came from (rows from before 1.4 count as folder #1); with several folders, rows name their folder and the toolbar has a folder filter (All Folders or one folder).

### Cleanup
1. Scan Intake-managed paths (and optionally loose files still in watch root). With several watch folders, Cleanup scans **All Folders** or the one picked at the top of the pane; File Away, Keep and Delete act within the folder the item was found in.
2. Files not opened/modified for *N* days appear in Cleanup — a **decision queue**, never merged with Activity. Each row shows why it's there:
   - **Stale** — unopened/unmodified for the threshold, same as before.
   - **Duplicate** — same size, then a matching content hash, as another file in the watch root or an Intake-managed folder. The oldest file (by date added, then shortest name) is kept as the original; the row names it. Hashes are cached by path, size and modification date so unchanged files are never re-hashed.
   - **Abandoned download** — an incomplete-download extension (`.crdownload`, `.part`, etc.) whose size and modification date haven't changed for 24 hours. An actively-downloading file is never flagged.
   - **Installer** — a `.dmg`/`.pkg`/`.mpkg` in the watch-folder root or the Installers folder whose app is already on disk: the row names the matched app. The installer's base name is normalized (version numbers, arch tokens like `arm64`/`x86_64`, and words like "installer"/"setup" stripped) and compared against the display and bundle names of apps in `/Applications` and `~/Applications`; the match only counts when the app's date is after the installer's. `.pkg`/`.mpkg` prefer the installed package receipt (via `pkgutil`) when it's readable, falling back to the same name match otherwise. A `.dmg` whose disk image is currently mounted is skipped rather than flagged — Intake never mounts an image itself. **Keep** on an installer snoozes it (e.g. to hold onto it for another Mac).
   
   Duplicate, abandoned-download and installer rows skip the stale-days threshold — they show up regardless of age.
3. Actions: **File Away** (pick folder), **Delete** (confirm; Intake moves it to Trash), **Keep** (snooze / exclude) — same for every reason. Nothing is ever deleted without the user confirming.
4. After moves/deletes, remove empty Intake-created category folders.

### AI
**Content-aware rename.** Off by default. Text is always extracted on this Mac (PDF text layer first, then Vision for scanned PDFs — first 2 pages — and images; files over 50 MB and encrypted PDFs are skipped; at most 4,000 characters). A **naming provider** then turns that text into fields: **On this Mac** (default) uses Apple's Foundation Models (`SystemLanguageModel`, macOS 26) so **file contents never leave the Mac**; **OpenRouter** sends the extracted text to your OpenRouter model (requires OpenRouter enabled + Keychain API key) — **contents leave the Mac** when that provider is selected. Both paths return date, document type, organization, subject and a confidence; Intake then renders a deterministic **template** — tokens `{date} {type} {organization} {subject} {original}`, default `{date} {type} {organization}` — dropping empty tokens and dangling separators, accepting only real ISO `YYYY-MM-DD` dates, stripping path separators and control characters, applying the normalizer's clean-up (short all-caps acronyms like `IRS` stay), and capping the name at 80 characters. The result is rejected when empty, only generic words ("Document", a bare date), or under the confidence threshold (0.6); **any rejection keeps the Title Case name**. The extension is always preserved and collision rules match the Title Case rename. Settings (AI pane): master toggle, naming provider picker, file types (PDFs, Images; both by default), template field, **Try on a File…**, and a message when the selected provider isn't ready.

Optional **OpenRouter** for folder suggestions: Keychain API key, base URL, model. Master AI suggestions toggle and OpenRouter stay **off by default**. Folder suggestions send filename and extension only (never file contents) on rule miss / Other. The same OpenRouter account powers content-aware rename when that naming provider is selected.

**OpenRouter cost tracking**: When AI suggestions and OpenRouter are both enabled, Intake fetches and displays your API key usage, account limits, and remaining credits on the OpenRouter pane. Intake also tracks its own spending: total spend across all time and spend in the current calendar month, with a reset button. Each suggestion's cost is recorded. Cost lookups run at most once per minute (after key entry or when the AI settings pane opens) and only to the configured base URL.

**Error messages**: 401 (invalid key) and 402 (out of credit) get friendly messages in Settings.

Ollama, Claude CLI, Cursor agent CLI (`agent` and/or `cursor` on PATH), and Codex CLI rows show **Available** vs **Not installed** from a PATH check; they are not called for suggestions yet.

## Chrome

| Surface | Default | Notes |
|---|---|---|
| Dock | **On** | Regular activation policy. Clicking the Dock icon (or launching like a normal app) brings **Settings** forward. Hiding the Dock does not quit. |
| Menu bar | **On** | Status, pause/resume, Organize Existing…, Open Activity, Settings…, Quit. Status summarizes every watch folder: "Watching" / "Paused" with one folder (as in 1.2), "Watching 3" with the folder names (and how many are paused) with several, "Attention" when a folder needs access. Pause / Resume act on all folders; Resume also turns Automatic organizing back on when no folder would be organizing otherwise. Dense 16pt template glyphs (Watching vs Paused). No wait countdown. The extra follows the system menu bar; macOS does not offer a supported way to pin it to every display. |
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
