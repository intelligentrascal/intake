# Intake — Design

## Foundation

- **Platform:** macOS 26+
- **UI:** SwiftUI + AppKit only where needed (menu bar, open panels, activation policy)
- **Authority:** [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- **Mood board:** [Thaw](https://github.com/thaw-app/Thaw) for density and settings polish — **do not copy GPL source**

## Chrome

- Dock **on** by default (app icon: soft-catch document in a U cradle). Users may hide it; menu bar can remain.
- `MenuBarExtra` **on** by default for status + quick pause/resume, using a monochrome **template** soft-catch glyph (`isTemplate = true`). Watching vs Paused are distinct silhouettes.
- `Settings` scene with `NavigationSplitView` sidebar
- Prefer system `Form` / `List` / `Table` / `Inspector`, grouped form style, section footers
- SF Symbols for chrome icons; custom app + menu-bar icons only
- Respect light/dark, accent color, Dynamic Type, Reduce Motion
- Independent **Show in Dock** / **Show in menu bar** toggles; at least one must stay on

## Settings IA (v1)

1. General — watch folder, launch at login, pause, appearance in macOS (Dock / menu bar)
2. Rules — taxonomy + rename patterns
3. Cleanup — duration threshold, include roots, decision queue
4. Activity — audit trail of ingest and cleanup
5. AI — providers off by default
6. About — license, links

## Activity

Chronological list: renamed / moved / skipped / error (and cleanup delete / empty-folder notes). Double-click or Reveal in Finder (toolbar or context menu) opens the file; selection alone does not. Context menu: Reveal / Copy path. Persists across launches with a cap.

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

**Do:** one primary action per view; plain language; reversible destructive paths; grouped Forms with helpful footers; ContentUnavailableView empty states.  
**Don’t:** web card grids, purple AI gradients, shadcn/Material, dense custom chrome that fights macOS, copying Thaw GPL UI.
