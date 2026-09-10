# IN-09 · Intake design handoff (polish + visual direction)
**Product:** Intake · **For:** Intake Dev via Firstmate · **Task:** IN-09-design  
**Platform:** macOS · SwiftUI · Apple HIG only — **never** web/shadcn/React  
**Code:** Designer does not ship app code  

**Supersedes IN-08 §2 on primary window:** Dock/launch → **Settings** (not Activity). Activity stays a separate window via **Open Activity**.

---

## 1) Settings / Rules — sidebar bug + polish

### Likely bugs to fix (inspect on Mac)
- Sidebar **selection highlight** missing, sticky, or wrong pane when switching (esp. into **Rules**).
- Row **spacing / hit targets** uneven vs system Settings apps.
- Detail column: extra `.padding()` on grouped `Form` can double-inset and clip Tables (Rules).

### Spec
| Surface | Direction |
|---|---|
| Sidebar | Standard `List(selection:)` + `.listStyle(.sidebar)`; system selection tint; 160–240pt width; SF Symbol + title only |
| Selection | Single source of truth (`selectedSettingsPane`); tapping Rules must show Rules detail immediately |
| Detail | Grouped Form; prefer system content margins — drop redundant outer padding if it fights Form |
| Rules table | Keep On / Folder / Extensions; min height ~280; readable extension column; footer unchanged in spirit |
| Density | Thaw-*quality* (mood only): tight sections, clear footers — no GPL copy |

### Rules polish copy
- Header: `Default taxonomy`
- Footer: `Rules match by file extension. Folders appear only when a file is routed there.`
- Suggestions block: see §5 (above or below the table).

### Accept
- [ ] Every sidebar row selects cleanly; highlight matches selected pane
- [ ] Rules table not clipped; looks like a native Settings detail
- [ ] No custom web cards / purple chrome in chrome UI

---

## 2) Automatic organizing toggle

### Replace
- Remove user-facing **Pause organizing** as the primary mental model.

### Add
| Control | Spec |
|---|---|
| Toggle label | `Automatic organizing` |
| ON | Watching + rename/route (current “not paused”) |
| OFF | Paused — no new ingest (Catch up / Organize Existing may still run per product rules) |
| Section | General → Organizing (with Open at login) |
| Footer | `When on, Intake watches the folder and files new downloads. Turn off to leave files alone.` |

### Menu bar (unchanged states, denser glyphs)
- ON → **Watching** + dense Watching template  
- OFF → **Paused** + dense Paused template  
- Menu verb: prefer **Pause Organizing** / **Resume Organizing** still OK (action language) while Settings shows Automatic organizing (state language). Or mirror: menu **Turn Off Automatic Organizing** — **prefer keep Pause/Resume** for brevity; Settings owns the positive framing.

### Binding
- Implement as positive toggle; persist same underlying paused flag inverted in UI only, or rename storage — Dev choice; UX must read ON = filing.

### Accept
- [ ] Settings shows Automatic organizing; no “Pause organizing” toggle label
- [ ] Menu bar Watching/Paused still clear at 16pt

---

## 3) Dock / launch → Settings primary

### Behavior (replaces IN-08 Activity-primary)
| Event | Opens |
|---|---|
| Cold launch (Dock) | **Settings** window (last pane or General) |
| Dock click / `applicationShouldHandleReopen` | **Settings** forward |
| ⌘, / Settings… | Settings |
| Open Activity (menu / General button) | Separate **Activity** window |
| Cleanup | Via Settings sidebar (or Open Cleanup if present) |

### Copy tweaks
- Appearance footer: mention Settings, not only Activity — e.g. `Keep Intake in the Dock so it’s easy to open Settings. The menu bar shows status without opening a window.`

### Accept
- [ ] Dock never opens Activity by default
- [ ] Activity only via explicit Open Activity
- [ ] Dual chrome rules (IN-05) unchanged

---

## 4) MeshGradient background (Paper Design–inspired, native only)

### Look (captain)
- Dark blacks + purple `#1D16E9` at **~34% alpha** (`#1d16e957`)
- Distortion / swirl / grain feel — **SwiftUI `MeshGradient`** and/or light Metal; **never React / Paper web embed**

### Where it sits (proposal)
| Priority | Placement | Why |
|---|---|---|
| **1 — Use** | **Activity window** full-bleed background behind list / empty state | Expressive window; Settings stay calm and readable |
| **2 — Optional** | Settings **window** behind NavigationSplitView at **very low** opacity (≤12% mesh contribution) | Subtle brand without fighting Form contrast |
| **Don’t** | Inside grouped Form rows, menu bar, or Dock icon | Legibility / HIG |

Content (lists, empty states, tables) sits on **system materials / vibrancy or solid scrim** so text stays AA. Mesh is atmosphere, not a text backdrop.

### Reduce Motion / accessibility
- If `accessibilityReduceMotion` **or** Increase Contrast: **static** dark wash (same black + purple tint), no animated mesh points.
- Prefer `MeshGradient` with static control points when motion reduced; optional ultra-subtle idle drift only when motion allowed (≤ slow).

### Tokens
- Base: near-black `oklch` / sRGB ~`#0A0A0C`–`#121218`
- Accent blob: `#1D16E9` @ 0.34
- Optional second cool gray blob for depth — no rainbow, no shadcn purple hero

### Accept
- [ ] Native MeshGradient (or Metal) only
- [ ] Activity shows mesh; Settings optional subtle
- [ ] Reduce Motion → static wash; body text contrast OK

---

## 5) Rules suggestions UI (coordinate with PM PRD)

**No PM PRD file found in repo/docs at handoff time** — use this UI shell; Intake Dev / PM align field names when PRD lands.

### Placement
Rules pane, **above** Default taxonomy table:

### Empty / placeholder
```
Suggestions
No suggestions yet
Intake will propose rules when it sees patterns it can’t file confidently.
```
`ContentUnavailableView` or section footer style — native, not a marketing card.

### When suggestions exist
Section **Suggestions** with rows:

| Element | Spec |
|---|---|
| Leading | SF Symbol (e.g. `lightbulb` or category icon) |
| Title | Proposed folder or rule name |
| Subtitle | Why / sample extensions / example filename |
| Trailing | **Accept** (prominent or borderless prominent) · **Dismiss** (secondary) |
| Density | One suggestion per row; ≥44pt height |

**Copy**
- Accept → adds/enables rule (per PRD)
- Dismiss → removes suggestion (per PRD)
- Footer: `Suggestions never change files until you accept.`

### Out of scope until PRD
AI copy generation, ranking, networking — UI only.

### Accept
- [ ] Empty state + Accept/Dismiss row layout in Rules
- [ ] Wired or clearly stubbed to PM contract

---

## Do / Don’t
**Do:** SwiftUI Settings, WindowGroup, MeshGradient, system List/Table/Form.  
**Don’t:** React, Paper Design web runtime, shadcn, CSS mesh ports, web card grids.

## Blockers
- PM rules-suggestions PRD not in tree — UI shell specified; confirm fields when PRD arrives.

## File
`/workspace/fm-intake/IN-09-design-handoff.md`
