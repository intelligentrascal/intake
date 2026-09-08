# IN-08 · Intake design handoff (menu bar density + Activity primary)
**Product:** Intake · **For:** Intake Dev (via Firstmate) · **No app code from Designer**

---

## 1) Menu bar soft-catch @ 16pt (denser / more findable)

### Problem
Current Watching/Paused templates are thin and similar at 16pt; easy to miss on dual-display menu bars (notch gap, camera housing, per-display extras).

### Direction (keep soft-catch metaphor)
- **More ink:** thicker U cradle; larger document; drop fine interior rules if they vanish at 16pt.
- **Paused ≠ subtle slots:** use **two thick pause bars** above the same cradle (not hollowed doc). Watching vs Paused must be obvious in ≤0.5s at arm’s length.
- Still **template** (black silhouette, transparent, `isTemplate = true`). No color in the bar.
- Optical size: fill ~14×14 of the 16×16 box (1pt margin); avoid hairline arms.

### Assets to fold in
| File | Use |
|---|---|
| `assets/MenuBarIcon-Watching-dense-16.svg` | Watching |
| `assets/MenuBarIcon-Paused-dense-16.svg` | Paused |

Replace the production imageset SVGs with these (or refine further after Retina screenshot). Keep accessibility labels: `Intake watching` / `Intake paused`.

### Dual-display reality note
- Menu bar extras are **per display** that shows a menu bar; users often lose the icon when the “wrong” screen is primary or when the bar is crowded.
- Design implication: Dock remains the reliable home (IN-05). Menu bar is **status + pause**, not the only launch path.
- Optional later (out of IN-08 scope): “Needs attention” state still uses the same dense silhouette + subtitle text — don’t rely on a tiny badge alone across displays.
- Verify on **built-in + external** if available: light/dark menu bar, notch MacBook, and a non-notch display.

### Accept
- [ ] Watching vs Paused distinguishable at 16pt screenshot
- [ ] Template renders correctly light/dark menu bar
- [ ] No tray/folder silhouette regression

---

## 2) Dock click / launch → **Activity** primary window

### Job
Opening Intake from Dock (or relaunch) lands on the **audit trail**, not Settings. Settings stays ⌘, / menu **Settings…**.

### Chrome (HIG / SwiftUI only)
- Prefer a real **`Window("Activity", id: …)`** / `WindowGroup` for Activity — not stuffing Activity only inside the Settings NavigationSplitView as the “main app.”
- Settings scene remains for General / Rules / Cleanup / Activity-list-can-stay-linked / AI / About — but **Dock reopen must not** only call `showSettingsWindow`.
- `applicationShouldHandleReopen` / Dock click → bring **Activity window** forward (create if needed).
- Cold launch (Dock icon) → same: show Activity.
- Menu bar: keep Pause/Resume; add **Open Activity** whenever useful (not only when Dock on — at least when Activity is primary). Settings… stays ⌘,.

### Window title & content
| State | Title | Body |
|---|---|---|
| Empty | `Activity` | `ContentUnavailableView`: “No activity yet” / “When Intake renames or files a download, it shows up here.” |
| Populated | `Activity` | Chronological list (IN-03 row design); select/Reveal; context Reveal / Copy path |
| Optional subtitle | — | Sidebar-free; toolbar optional: Pause/Resume toggle, Settings button |

Min size ~520×420; remember position. Reduce Motion: no theatrical open animation.

### Reopen behavior
1. Dock click, Activity already open → order front (don’t spawn duplicates).
2. Dock click, Activity closed → reopen Activity (empty or last scroll OK).
3. Dock click while Settings open → still prefer Activity front; don’t close Settings unless needed.
4. Menu **Settings…** / ⌘, → Settings only.
5. Quit ends all; next launch → Activity again.

### Avoid
- Web dashboards, shadcn cards, marketing chrome.
- Making Settings the Dock home again.
- Multiple Activity windows.

### Accept
- [ ] Fresh launch & Dock reopen → Activity window
- [ ] ⌘, → Settings
- [ ] Empty + populated states match copy above
- [ ] Dual-display: Activity appears on the display where the user clicked Dock if possible (system default OK)

---

## Out of scope
AI providers, Cleanup redesign, new taxonomy, Thaw GPL.

## Blockers
None. Dense SVGs ready under `/workspace/fm-intake/assets/`.
