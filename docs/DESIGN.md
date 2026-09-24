# Intake — Design

## Foundation

- **Platform:** macOS 26+
- **UI:** SwiftUI + AppKit only where needed (menu bar, open panels, activation policy)
- **Authority:** [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- **Mood board:** [Thaw](https://github.com/thaw-app/Thaw) for density and settings polish — **do not copy GPL source**

## Chrome

- Dock **on** by default (app icon: soft-catch document in a U cradle). Users may hide it; menu bar can remain. Dock click / launch / reopen bring **Settings** forward — not Activity. Activity is a separate window via **Open Activity**.
- `MenuBarExtra` **on** by default for status + quick pause/resume, using a monochrome **template** soft-catch glyph (`isTemplate = true`). Watching vs Paused are distinct dense 16pt silhouettes (thick cradle; Paused uses two pause bars). Pause / Resume verbs stay on the menu; Settings uses **Automatic organizing**. No wait countdown in the menu bar.
- `Settings` scene with `NavigationSplitView` sidebar (⌘, / Settings…). Sidebar 160–240pt; `List(selection:)` is the single source of truth (`selectedSettingsPane`). Grouped Forms without extra outer padding that clips tables.
- Prefer system `Form` / `List` / `Table` / `Inspector`, grouped form style, section footers
- SF Symbols for chrome icons; custom app + menu-bar icons only
- Respect light/dark, accent color, Dynamic Type, Reduce Motion
- Independent **Show in Dock** / **Show in menu bar** toggles; at least one must stay on

## Settings IA (v1)

1. General — watch folders, organize existing, **Automatic organizing**, **Rename when download finishes**, **Wait before organizing** (per folder), Open at login, appearance in macOS (Dock / menu bar)
2. Rules — editable taxonomy, drag order, custom rules, on-device suggestions
3. Cleanup — duration threshold, include roots, decision queue
4. Activity — audit trail of ingest and cleanup (open the dedicated window from here or the menu)
5. AI — **Content-aware rename** section first (off by default: toggle, naming provider picker On this Mac | OpenRouter, PDFs / Images toggles, Name template field with a token caption, **Try on a File…** with inline result, warning-colored availability message when the selected provider can't run; footer copy differs by provider); then suggestions off by default; OpenRouter is the first real provider (Keychain key)
6. About — license, links

### Watch folders

General → first section, titled **Watch folder** (one) or **Watch folders** (several). One row per folder: SF Symbol `folder` (or `exclamationmark.triangle.fill` in warning color when access is lost), display name, path in caption (middle-truncated, selectable), trailing status text (Watching / Paused / Needs access) and an `ellipsis.circle` borderless menu: Show in Finder, Change Folder…, Pause / Resume, Remove… (destructive, confirmed; disabled for the last folder). Lost access adds an inline row: “Intake can’t see this folder” + **Grant Access…**. Below the rows: **Add Folder…** — a menu with “Screenshots (<folder>)…” and “Choose Folder…” when the screenshot location isn't watched yet, otherwise a plain button. Refused folders (overlap, category folder, cap of 5) show an alert “Can’t use this folder” with the reason. The Organizing section edits one folder: with several, a **Folder** menu picker and a **Name** field sit at its top. Activity gets a toolbar **Folder** menu picker (All Folders / each folder) and Cleanup a **Watch folder** picker, both only with several folders. The rule editor gets an **Applies to** section (All watch folders / Specific folders with a toggle per folder).

### Wait before organizing

General → Organizing, directly under Automatic organizing. Native menu `Picker` (`.pickerStyle(.menu)`). Title **Wait before organizing**. Values: **Immediately**, **15 minutes**, **1 hour**, **2 hours** (default), **1 day**. Footer: “New downloads stay in the folder until this time has passed, so you can open them before Intake files them.” When Automatic organizing is off, the picker stays visible but dimmed; the value is retained. Live watcher only; clock starts at `stableAt` after the stability debounce. Wait gates **filing into folders**, not the local rename-on-stable step.

### Rename when download finishes

General → Organizing, next to Automatic organizing / Wait before organizing. Native `Toggle`. Title **Rename when download finishes**. Default **On**. Footer: “Renames the file as soon as the download is stable — on this Mac only. Wait before organizing still delays filing into folders.” Stays enabled when Automatic organizing is off (rename in root, no auto move). Local `FileNameNormalizer` only — not AI / OpenRouter.

## Activity

SwiftUI `Window("Activity", id: "activity")` with `.defaultLaunchBehavior(.suppressed)` — audit trail, not the Dock default. Launch / Dock reopen still bring **Settings**. Activity opens only via Open Activity / menu / `openActivity()`. Chronological list: renamed / moved / skipped / error (and cleanup delete / empty-folder notes). Empty: ContentUnavailableView “No activity yet”. Double-click or Reveal in Finder (toolbar or context menu) opens the file; selection alone does not. Context menu: Reveal / Copy path. Persists across launches with a cap.

Native **MeshGradient** atmosphere on the Activity background (near-black + `#1D16E9` @ ~34%). Reduce Motion / Increase Contrast / Reduce Transparency → static wash or solid `surface`. Optional faint Settings wash behind the split view. Never React, WKWebView, or Paper web shaders.

## Cleanup

Queue of candidates with age, size, path. Primary: File Away. Secondary: Keep (snooze). Destructive: Delete (confirm with filename; Intake moves it to Trash). After actions, prune empty Intake-managed folders.

## Tokens (product layer)

Use system semantic colors first. Product roles:

| Role | Use |
|---|---|
| `ink` | Primary label (system label) |
| `ink-secondary` | Secondary label |
| `surface` | Window / grouped background |
| `accent` | System accent |
| `danger` | Delete |
| `success` | Completed ingest |
| `warning` | Skipped / needs attention (system orange) |

Spacing: 8pt grid. Settings detail content width ~480–560pt. Sidebar 160–240pt. Prefer system text styles (title, headline, body, caption). Prefer `.formStyle(.grouped)`.

## Do / Don’t

**Do:** one primary action per view; plain language; reversible destructive paths; grouped Forms with helpful footers; ContentUnavailableView empty states; native MeshGradient on Activity.  
**Don’t:** web card grids, purple AI hero chrome on forms, shadcn/Material, dense custom chrome that fights macOS, copying Thaw GPL UI, React/web mesh ports.
