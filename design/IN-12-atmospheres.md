# IN-12 · Intake atmospheres — three directions (captain pick later)
**Product:** Intake · **From:** Designer → Firstmate → Intake Dev  
**Context:** PR #8 God Rays rejected. Need **three drastically different** native SwiftUI/HIG atmospheres — not three tints of rays.  
**No merge. No React / WKWebView / Paper web shaders.**  
**Process:** Dev implements all three as previewable styles → screenshots in chat → **then** captain picks (never blind).

---

## Shared constraints (all three)
- SwiftUI only: `MeshGradient`, materials (`ultraThinMaterial` etc.), subtle `TimelineView` / phase animators — or static.
- Content (Forms, Tables, lists) stays on **readable scrims**; atmosphere is behind chrome, not under body text.
- Honor **Reduce Motion** → static; **Increase Contrast** / Reduce Transparency → flatter solid or system background.
- Palette may use deep neutrals + restrained accent; avoid rainbow god-rays, lens flares, hard beams.
- Apply primarily to **Activity window** and optionally **Settings window chrome**; never menu bar / Dock icon.

---

## A — Quiet Mesh (refined utility)
**Idea:** Low-amplitude MeshGradient wash — charcoal / graphite with one soft cool accent blob (teal or muted indigo, not neon purple beams). Almost “finished Mac Settings” calm.

| Where | Treatment |
|---|---|
| Settings sidebar | Near-system sidebar; mesh only in **window** behind split (≤10% influence) |
| Settings detail | Grouped Form on system grouped background — **no** mesh under controls |
| Activity | Full-bleed quiet mesh behind list; empty state on material card |

**Motion:** Static by default; optional glacial control-point drift only if motion allowed (period ≥12s).  
**A11y:** Reduce Motion / Increase Contrast → solid `#0E0E12` (or system window). Reduce Transparency → opaque fill, no material stack.  
**Why Intake:** Filing downloads is a trust job — atmosphere should feel composed and private, not cinematic.

---

## B — Soft Aurora Vignette (no rays)
**Idea:** Edge-weighted aurora: soft vertical/elliptical color fields that **fall off toward center** (vignette), like northern light behind frosted glass — **no spokes, no god rays, no center burst**.

| Where | Treatment |
|---|---|
| Settings | Aurora only in **titlebar/toolbar bleed** or window margins; detail stays crisp |
| Activity | Stronger aurora at edges; center list on `ultraThinMaterial` / solid panel |

**Palette sketch:** deep black base; mint/teal and cool violet as **soft blobs** (low chroma), feathered.  
**Motion:** Slow opacity crossfade between 2–3 gradient layers (if motion on); never rotating beams.  
**A11y:** Reduce Motion → single static vignette; Increase Contrast → remove color blobs, keep dark vignette only or system bg.  
**Why Intake:** Suggests “settling / soft catch” brand without looking like a wallpaper engine or video overlay.

---

## C — Material First (almost no decoration)
**Idea:** Atmosphere = **system materials and hierarchy**, not illustration. Window uses standard macOS materials; optional 1pt separator rhythm; zero MeshGradient / zero aurora.

| Where | Treatment |
|---|---|
| Settings | Stock NavigationSplitView + grouped Form — reference Apple System Settings density |
| Activity | `List` / `Table` on window background; empty `ContentUnavailableView` only |

**Motion:** None (or system default only).  
**A11y:** Best case path — follows HIG automatically; still respect Reduce Transparency.  
**Why Intake:** Captain may prefer “perfect Mac utility” over any branded glow; this is the honest baseline to judge A/B against.

---

## Implementation note for Intake Dev
Expose an internal enum e.g. `IntakeAtmosphere: quietMesh | softAurora | materialFirst` (Debug/Settings → Appearance or hidden flag) so Firstmate can screenshot A/B/C side-by-side on Activity + Settings before captain chooses **one**.

## Out of scope
God Rays / hard beams / lens flares; web shaders; changing app icon; merging.

## Blockers
None for direction. Captain pick waits on preview screenshots.
