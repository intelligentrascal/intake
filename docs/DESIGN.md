# Intake — Design

## Foundation

- **Platform:** macOS 26+
- **UI:** SwiftUI + AppKit only where needed (menu bar, open panels)
- **Authority:** [Apple Human Interface Guidelines](https://developer.apple.com/design/human-interface-guidelines/)
- **Mood board:** [Thaw](https://github.com/thaw-app/Thaw) for density and settings polish — **do not copy GPL source**

## Chrome

- `MenuBarExtra` for status + quick pause/resume
- `Settings` scene with `NavigationSplitView` sidebar
- Prefer system `Form` / `List` / `Table` / `Inspector`
- SF Symbols for chrome icons; custom app icon separately
- Respect light/dark, accent color, Dynamic Type, Reduce Motion

## Settings IA (v1)

1. General — watch folder, launch at login, pause  
2. Rules — taxonomy + rename patterns  
3. Cleanup — duration threshold, include roots  
4. AI — providers off by default  
5. About — license, links  

## Activity

Chronological list: renamed / moved / skipped / error. Selectable row → reveal in Finder.

## Cleanup

Queue of candidates with age, size, path. Primary: File away. Secondary: Delete (confirm). Tertiary: Keep.

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

Spacing: 8pt grid. Prefer system text styles (title, headline, body, caption).

## Do / Don’t

**Do:** one primary action per view; plain language; reversible destructive paths.  
**Don’t:** web card grids, purple AI gradients, shadcn/Material, dense custom chrome that fights macOS.
