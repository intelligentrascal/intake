# IN-05 — Intake Dock visibility + Thaw-inspired behaviors

**From:** Product Manager → Firstmate  
**Task:** IN-05  
**Ground truth:** [docs/PRODUCT.md](https://github.com/intelligentrascal/intake/blob/main/docs/PRODUCT.md), [docs/DESIGN.md](https://github.com/intelligentrascal/intake/blob/main/docs/DESIGN.md), [Thaw README/features](https://github.com/thaw-app/Thaw) (inspiration only — **GPL-3.0; do not copy source**)  
**North star:** Beautiful finished native Mac app (SwiftUI + Apple HIG). Downloads organizer — not a menu-bar manager clone.

---

## 1) Product decisions — Dock, menu bar, LSUIElement

### Captain bar (non-negotiable)
1. User **must be able to see Intake in the Dock**.
2. User **must have options to hide** Dock presence and/or menu-bar extra.
3. Thaw informs polish and *utility patterns*; Intake stays a Downloads organizer.

### Defaults (v1)
| Surface | Default | Rationale |
|---|---|---|
| **Dock** | **ON** | Captain requirement; finished-app presence; Settings/Activity/Cleanup are real windows, not tray-only. Matches HIG expectation that apps with multi-pane Settings and document-like queues behave as regular apps. |
| **Menu bar (`MenuBarExtra`)** | **ON** | Already in DESIGN.md — status + quick pause/resume without bringing a window forward. Complements Dock, does not replace it. |

### LSUIElement / activation policy
- **Do not ship with `LSUIElement=1` as the permanent Info.plist default.** That forces agent-only (no Dock) and fights the captain bar.
- Implement Dock show/hide via **runtime activation policy** (AppKit):  
  - Dock visible → `NSApplication.ActivationPolicy.regular`  
  - Dock hidden → `.accessory` (menu-bar-capable agent style) while keeping `MenuBarExtra` if enabled  
- Persist preference in UserDefaults; apply on launch and when the toggle changes.
- **Relaunch:** Prefer live policy switch. If a platform edge case requires relaunch, Settings copy must say so explicitly (one sentence) and offer **Relaunch Intake**.

### HIG-correct hide pattern (decide)
| Pattern | Verdict |
|---|---|
| Dock-only utility (no menu bar) | Allowed if user turns menu bar off and leaves Dock on. |
| Menu-bar-only (Dock off) | Allowed — classic Mac utility; still HIG-valid when Settings remain reachable from the extra. |
| **Both off** | **Forbidden.** Leaves no chrome except Finder/Spotlight. Settings must block the second hide with a clear explanation. |
| Separate “Quit” vs “Hide Dock icon” | Keep Quit in menu bar / Dock menu as normal; hiding Dock is not Quit. |

**Decision:** Independent toggles for Dock and Menu bar; **at least one must stay ON**. This is the HIG-correct dual-chrome pattern used by many Mac utilities without becoming a Thaw-style bar manager.

### Settings copy (General pane — proposed)
Place under **General** (DESIGN IA item 1), after watch folder / launch at login / pause:

**Appearance in macOS**
- **Show in Dock** — `On` by default. Help: “Keep Intake in the Dock so it’s easy to open Settings, Activity, and Cleanup.”
- **Show in menu bar** — `On` by default. Help: “Status and pause/resume without opening a window.”
- Validation alert if user tries to turn off the last remaining surface:  
  **Title:** “Keep one way to open Intake”  
  **Body:** “Turn off Dock or the menu bar, not both — otherwise there’s no icon to reopen Settings.”  
  **Buttons:** OK (revert the change)

Optional footnote if relaunch required: “Changing Dock visibility may need a quick relaunch.”

### Menu bar extra behavior when Dock is on
- Menu bar shows status (Watching / Paused / Needs attention) + Pause/Resume + Organize Existing… + Open Activity + Open Cleanup + Settings… + Quit.
- Clicking the Dock icon opens the **Activity** window (IN-08). Settings remains ⌘, / **Settings…**.

---

## 2) Thaw → Intake feature mapping

Inspiration from Thaw’s public README/feature list only. **Reject anything that turns Intake into a menu-bar item manager.** No GPL source reuse.

| Thaw idea | Intake adaptation | Verdict |
|---|---|---|
| Declutter / hide *other apps’* menu bar icons | Not our job | **Reject** — Thaw’s core product |
| Always-hidden menu bar *section*, hover/scroll reveal of bar items | N/A | **Reject** |
| Style bar (tint, gradient, shadow, shapes, wallpaper tint) | N/A | **Reject** — visual chrome for the system bar |
| Thaw Bar / notch secondary bar | N/A | **Reject** |
| Screen Recording for live icon capture | N/A | **Reject** — Intake needs FS access, not screen capture |
| Triggers (battery, Wi‑Fi, Focus, scripts → reveal icons) | Optional later: Focus/Do Not Disturb → auto-pause ingest | **Later** — Focus-linked pause only; no icon triggers |
| **Zen mode** (conceal + lock reveals; auto on present/share) | **Pause organizing** — one action stops watch/rename/route; optional auto-pause while screen sharing / presenting if detectable without invasive perms | **Steal pattern (v1 = manual Pause; later = auto)** |
| **Profiles** (save config; bind to display/Space/Focus) | **Rule / watch profiles** — e.g. Work vs Personal watch folder + rule set | **Later** (v1.x) |
| Import/export profiles | Export/import rules JSON | **Later** |
| **Search** menu bar items | **Search Activity + Cleanup** lists (name, path, type) | **v1 polish / early v1.1** |
| **Hotkeys** | Global hotkey: Pause/Resume; Open Cleanup; Open Activity | **Later** (after Dock+Settings solid) |
| **Launch at login** | Already in DESIGN General | **v1** (already planned) |
| **Simple Mode** Settings | Keep Settings IA shallow (5 panes); avoid Thaw’s dual Simple/Advanced unless complexity explodes | **Steal spirit — already aligned** |
| Tools pane (diagnostics, resets, onboarding replay) | About + Reset rules / Clear activity (careful) | **Later** |
| **Deep links** (`thaw://…`) | `intake://pause`, `intake://resume`, `intake://open-settings`, `intake://open-cleanup`, `intake://open-activity` for Shortcuts / Raycast later | **v1 stub or v1.1** |
| Raycast / launcher integrations | Document URL scheme; community extension later | **Later** |
| Privacy: no tracking / no account | Already PRODUCT principle | **Keep** (already ours) |
| Signed/notarized, light footprint | Release bar for finished Mac app | **Keep as quality bar** (engineering, not feature) |
| Multilingual 20 locales | English v1; localize folder names later per PRODUCT | **Later** |
| Groups/spacers of menu bar items | N/A | **Reject** |

---

## 3) Prioritized scope

### v1 (this track — Dock/visibility + essential Thaw patterns)
1. **Dock default ON** + Settings toggle Show in Dock  
2. **Menu bar default ON** + Settings toggle Show in menu bar  
3. **Mutual exclusion guard** (cannot disable both)  
4. Activation-policy implementation (no permanent `LSUIElement=1`)  
5. Menu bar: status + Pause/Resume + open Settings/Activity/Cleanup + Quit  
6. Launch at login (existing plan)  
7. Pause organizing = Zen-inspired calm (manual)  
8. Settings polish: system `Form`, clear help strings (Thaw mood: density without clutter)

### Later (post-v1)
- Activity + Cleanup search  
- `intake://` deep links (+ Shortcuts)  
- Global hotkeys  
- Focus / screen-share auto-pause  
- Watch/rule profiles + import/export  
- Diagnostics / reset tools  
- Localization beyond EN  
- Raycast extension  

### Explicit non-goals (still)
- Managing or restyling other apps’ menu bar items  
- Copying Thaw GPL UI/source  
- Finder replacement, cloud sync of contents, Windows/Linux (PRODUCT non-goals)

---

## 4) Acceptance criteria — Dock show/hide

1. **Fresh install:** Intake appears in the Dock while watching is active or Settings is open; `LSUIElement` is not permanently forcing agent-only.  
2. **Show in Dock = On:** App uses regular activation policy; Dock icon visible; clicking it brings Intake forward (Settings or primary window).  
3. **Show in Dock = Off** (menu bar still On): Dock icon disappears; menu bar extra remains; Settings still reachable from the extra.  
4. **Show in menu bar = Off** (Dock still On): No `MenuBarExtra`; Dock icon remains; Pause/Resume available from the app menu / Settings.  
5. **Attempt to disable the last remaining surface:** Toggle does not stick; alert “Keep one way to open Intake” shown; previous state restored.  
6. **Persistence:** Both toggles survive quit/relaunch.  
7. **Quit ≠ hide Dock:** Quitting removes process; turning Dock off does not quit.  
8. **HIG/accessibility:** Toggles are standard Settings switches with help text; VoiceOver labels meaningful; Reduce Motion respected for any transition.  
9. **No Thaw scope creep:** No APIs or UI for hiding/moving *other* menu bar items; no Screen Recording permission prompted for Dock/menu chrome.  
10. **Docs:** PRODUCT/DESIGN updated to state Dock default ON + dual toggles + at-least-one rule (Intake Dev / docs follow-on — not this PM file’s code work).

---

## 5) Designer / Intake Dev handoff notes

- **Designer:** Settings General “Appearance in macOS” group; alert copy; menu bar status glyphs (Watching / Paused / Attention); Dock icon still the app icon (no custom Dock badge required in v1).  
- **Intake Dev:** Activation policy + `MenuBarExtra` lifecycle; guardrail; do not set `LSUIElement` permanently in Info.plist; MIT codebase only — no Thaw source.  
- **Captain:** Visibility bar met: Dock visible by default, hide options for Dock and/or menu bar without orphaning the app.

---

## Handoff
- **Firstmate:** Assign Intake Dev + Designer from this doc.  
- **PM:** No code. Further scope clar on request only.
