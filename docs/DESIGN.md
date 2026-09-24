# Intake — Design

## Foundation

- **Platform:** macOS 26+
- **UI:** SwiftUI + AppKit only where needed (menu bar, open panels, activation policy)
- **Authority:** [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- **Mood board:** [Thaw](https://github.com/thaw-app/Thaw) for density and settings polish — **do not copy GPL source**

## Chrome

- Dock **on** by default (app icon: soft-catch document in a U cradle). Users may hide it; menu bar can remain. Dock click / launch / reopen bring **Settings** forward — not Activity. Activity is a separate window via **Open Activity**.
- `MenuBarExtra` **on** by default for status + quick pause/resume, using a monochrome **template** soft-catch glyph (`isTemplate = true`). Watching vs Paused are distinct dense 16pt silhouettes (thick cradle; Paused uses two pause bars). Pause / Resume verbs stay on the menu; Settings uses **Automatic organizing**. No wait countdown in the menu bar.
- `Settings` scene with a plain `HStack` sidebar (⌘, / Settings…) — not `NavigationSplitView` or `List(selection:)`, which never received clicks under the Settings scene. Sidebar 192pt of `.plain` Buttons that set `selectedSettingsPane` (the single source of truth); the container is an accessibility list ("Settings sections", `.isSelected` on the current row) and ↑/↓ move between panes; no "Intake" header. Keyboard shortcuts ⌘1–⌘7 jump between panes. Grouped Forms without extra outer padding that clips tables.
- Prefer system `Form` / `List` / `Table` / `Inspector`, grouped form style, section footers
- SF Symbols for chrome icons; custom app + menu-bar icons only
- Respect light/dark, accent color, Dynamic Type, Reduce Motion
- Independent **Show in Dock** / **Show in menu bar** toggles; at least one must stay on

## Settings IA (v1)

1. General — four sections: **Watch folder(s)** (status: Watching / Paused / Organizing off / Needs access; each folder's **Automatic organizing**, **Rename when download finishes**, **Wait before organizing** sit with that folder), **Existing files** (Organize Existing…, **Open Activity**), **Notifications**, **Startup and appearance** (**Open at login**, Show in Dock, Show in menu bar)
2. Rules — editable filing rules, drag order (⌥⌘↑/↓), custom rules, on-device suggestions; delete (⌘⌫) and reset confirm
3. Cleanup — threshold shown once: “Unused for [field] days” with a Stepper beside the field (rescan debounced ~0.5 s), include roots, multi-select decision queue with context menu (Quick Look, Reveal in Finder, File Away, Keep, Delete…); double-click/Space for Quick Look
4. Activity — audit trail of ingest and cleanup (open the dedicated window from here or the menu)
5. AI — **Content-aware rename** section first (off by default: toggle, naming provider picker On this Mac | OpenRouter, PDFs / Images toggles, Name template field with a token caption, **Try on a File…** with inline result); **OpenRouter setup** disclosure (key, base URL, model) shown only when OpenRouter is enabled; folder suggestions toggle; **Intake spend** section with reset; account/cost info shows whenever OpenRouter enabled; privacy text and "file contents leave this Mac" line are provider-conditional
6. About — license, links; privacy text describes actual data flow based on selected naming provider
7. Feedback — email field notes it's included in public GitHub issue

### Watch folders

General → first section, titled **Watch folder** (one) or **Watch folders** (several). One row per folder: SF Symbol `folder` (or `exclamationmark.triangle.fill` in warning color when access is lost), display name, path in caption (middle-truncated, selectable with one folder — not selectable when the row is a DisclosureGroup label with several, so clicking the row toggles it instead of starting a text selection), trailing status text (Watching / Paused / Organizing off / Needs access, each with a `.help` tooltip spelling out what that state means and whether renaming still runs) and an `ellipsis.circle` borderless menu: Show in Finder, Change Folder…, Pause Organizing / Resume Organizing, Remove… (destructive, confirmed; disabled for the last folder). Lost access adds an inline row: “Intake can’t see this folder” + **Grant Access…**. Below the rows: **Add Folder…** — a menu with “Screenshots (<folder>)…” and “Choose Folder…” when the screenshot location isn’t watched yet, otherwise a plain button. Refused folders (overlap, category folder, cap of 5) show an alert “Can’t use this folder” with the reason. Each folder's organizing settings live with its row — never behind a separate folder picker. With one folder, **Automatic organizing**, **Rename when download finishes** and **Wait before organizing** follow the row inline. With several, each row is a native `DisclosureGroup` (collapsed by default) whose content is that folder's **Name** field plus the same three controls. Automatic organizing, Rename and Wait each carry a one-line subtitle instead of a footer, so the three ways to stop filing (Pause, Automatic organizing off, and — for the immediate rename only — Rename when download finishes off) read as distinct: Automatic organizing's subtitle says filing stops but files stay put; Rename's says it runs independently of Automatic organizing. Pause Organizing / Resume Organizing stays in the row menu — a temporary halt that behaves like Automatic organizing off (filing stops, renaming can still run) without changing the Automatic organizing setting itself; the three states keep separate meanings. Activity gets a toolbar **Folder** menu picker (All Watch Folders / each folder) and Cleanup a **Watch folder** picker, both only with several folders. The all-folders choice reads **All Watch Folders** on every surface (Organize Existing menu, Cleanup, Activity, rules). The rule editor gets an **Applies to** section (All Watch Folders / Specific folders with a toggle per folder).

### Wait before organizing

General → each watch folder's settings, under Automatic organizing and Rename. Native menu `Picker` (`.pickerStyle(.menu)`). Title **Wait before organizing**. Values: **Immediately**, **15 minutes**, **1 hour**, **2 hours** (default), **1 day**. Subtitle: “New downloads stay put this long so you can open them before they’re filed.” When Automatic organizing is off, the picker stays visible but dimmed; the value is retained. Live watcher only; clock starts at `stableAt` after the stability debounce. Wait gates **filing into folders**, not the local rename-on-stable step.

### Rename when download finishes

General → each watch folder's settings, between Automatic organizing and Wait before organizing. Native `Toggle`. Title **Rename when download finishes**. Default **On**. Subtitle: “Renames on this Mac as soon as the download is stable, on its own — whether or not Automatic organizing is on.” (Wait's subtitle covers the filing delay.) Stays enabled when Automatic organizing is off (rename in root, no auto move). Local `FileNameNormalizer` only — not AI / OpenRouter.

### Automatic organizing

General → each watch folder's settings, above Rename when download finishes. Native `Toggle`. Title **Automatic organizing**. Default **On**. Subtitle: “Files new downloads into folders. Off: files stay where they land.” Turning it off (or pausing the folder) stops filing only — the independent Rename toggle can still rename files in place.

## Activity

SwiftUI `Window("Activity", id: "activity")` with `.defaultLaunchBehavior(.suppressed)` — audit trail, not the Dock default. Launch / Dock reopen still bring **Settings**. Activity opens only via Open Activity / menu / `openActivity()`. Chronological list: renamed / moved / skipped / error (and cleanup delete / empty-folder notes). Empty: ContentUnavailableView "No activity yet". Double-click or Reveal in Finder (toolbar or context menu) opens the file — Reveal resolves through the row's before/after path chain so a renamed-then-moved file still opens where it actually is, falling back to its last known parent folder; selection alone does not reveal. Context menu: Reveal / Copy path. Persists across launches with a cap.

The same list (`ActivityListView`) is embedded read-only in Settings → Activity (`showsRevealToolbarItem: false`): no toolbar there, since an `NSToolbar` on the Settings window would grow its title bar and shift every pane's content on switch. Settings keeps Reveal via double-click and the context menu (Control-click).

Native **MeshGradient** atmosphere on the Activity background (near-black + `#1D16E9` @ ~34%). Reduce Motion / Increase Contrast / Reduce Transparency → static wash or solid `surface`. Optional faint Settings wash behind the split view. Never React, WKWebView, or Paper web shaders.

## Cleanup

Queue of candidates with age, size, path. Multi-select; context menu: Quick Look (or double-click/Space), Reveal in Finder, File Away, Keep (snooze), Delete (with confirmation; Intake moves to Trash). Actions on single or multiple selected items. After actions, prune empty Intake-managed folders. Delete key opens confirmation dialog.

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
