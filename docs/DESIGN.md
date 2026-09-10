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

1. General — watch folder, organize existing, **Automatic organizing**, **Wait before organizing**, Open at login, appearance in macOS (Dock / menu bar)
2. Rules — editable taxonomy, drag order, custom rules, on-device suggestions
3. Cleanup — duration threshold, include roots, decision queue
4. Activity — audit trail of ingest and cleanup (open the dedicated window from here or the menu)
5. AI — suggestions off by default; OpenRouter is the first real provider (Keychain key)
6. About — license, links

### Wait before organizing

General → Organizing, directly under Automatic organizing. Native menu `Picker` (`.pickerStyle(.menu)`). Title **Wait before organizing**. Values: **Immediately**, **15 minutes**, **1 hour**, **2 hours** (default), **1 day**. Footer: “New downloads stay in the folder until this time has passed, so you can open them before Intake files them.” When Automatic organizing is off, the picker stays visible but dimmed; the value is retained. Live watcher only; clock starts at `stableAt` after the stability debounce.

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
