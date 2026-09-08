# IN-03 · Intake design handoff (finished Mac app bar)
**Product:** Intake (native macOS Downloads organizer)  
**From:** Designer → Firstmate → Intake Dev (+ captain summary via Firstmate)  
**Grounded in:** `docs/PRODUCT.md`, `docs/DESIGN.md`, current Settings / MenuBar scaffold (`~/code/intake`)  
**Platform:** macOS 26+ · SwiftUI · Apple HIG (not web / not shadcn)  
**Code:** Designer does not ship app code. Intake Dev implements.  
**Assets:** `/workspace/fm-intake/assets/`

---

## Captain-facing summary (Firstmate may forward)

Intake must feel like a finished Mac utility, not a scaffold. Design direction:

1. **Icon** — “soft catch”: a document settling into a rounded U cradle (intake / landing). Distinct from folder, tray, and download-into-box clichés. Light + dark app-icon concepts + monochrome menu-bar templates delivered.
2. **Settings** — keep NavigationSplitView IA (General / Rules / Cleanup / AI / About). Raise density and copy to Thaw-*quality* polish (grouped Form, footers, empty states) without copying GPL source.
3. **Menu bar + Dock** — status, pause/resume, recent activity (Reveal), Settings…, Quit; soft-catch template in the bar; Dock on by default (IN-05). Replace generic `tray.and.arrow.down`.
4. **Activity + Cleanup** — clear rows, serious empty states, File Away primary / Keep secondary / Delete destructive with confirm.
5. **Hard rule** — native citizen only. No web card grids, purple AI chrome, or shadcn patterns on Intake.

---

## 0) Deepen PRODUCT / DESIGN (proposed doc deltas)

### PRODUCT.md add
- **Findability:** Users discover Intake from the **menu bar**. First-run should flash the menu-bar icon (or open the menu once) so the affordance is learned.
- **Activity is the audit trail** of rename/move/skip/error; Cleanup is the **decision queue** for untouched files — never merge them into one ambiguous list.
- **Trust copy:** Pause is always one click away; Delete never silent; AI never on by default.

### DESIGN.md replace/expand tokens + chrome
Keep system semantic colors first. Expand:

| Role | Use |
|---|---|
| `ink` / `ink-secondary` | Primary / secondary labels |
| `surface` | Window / grouped background |
| `accent` | System accent (user’s) |
| `danger` | Delete only |
| `success` | Completed ingest (subtle) |
| `warning` | Skipped / needs attention (system orange) |

Spacing: **8pt grid**. Settings detail content width comfortable ~480–560pt. Sidebar 160–240pt (already). Prefer `.formStyle(.grouped)`. SF Symbols for chrome; **custom** app + menu-bar icons only.

**Thaw-quality (mood only, no GPL copy):** tight grouped sections; helpful section footers; ContentUnavailableView empties; one clear primary per pane; no decorative web chrome.

---

## 1) App icon + menu bar template

### Metaphor (locked)
**Soft catch / landing** — a single document settles into a rounded **U cradle**. Reads as “intake.”  
**Avoid:** folder, inbox tray, download arrow into a box, clipboard, sparkles/AI orb.

### App icon (macOS 26 squircle-safe)
- Keep silhouette in **center ~80%**; no edge-critical detail (mask + layered glass will clip).
- Light: mint/teal cradle + warm white document (dog-ear OK if soft).
- Dark: charcoal/glass cradle with soft teal rim light + bright document.
- No wordmark on the icon.
- Production: provide Icon Composer / asset catalog layers from concepts; export standard macOS icon set.

**Concepts (PNG):**
- `assets/intake-app-icon-light.png`
- `assets/intake-app-icon-dark.png`

### Menu bar template (monochrome, 16–18pt)
- Black silhouette, transparent background; `isTemplate = true` so macOS paints correctly in light/dark menu bar.
- States: **Watching** (cradle + doc) · **Paused** (same silhouette with pause cue, or cradle + pause bars).
- Do **not** use filled colorful SF Symbol `tray.and.arrow.down.fill` long-term (generic + fights brand).

**SVG templates:**
- `assets/MenuBarIcon-Watching.svg` (18pt detail)
- `assets/MenuBarIcon-Watching-simple.svg` (16pt preferred if detail muddies)
- `assets/MenuBarIcon-Paused.svg`

**Accessibility labels:** `Intake watching` / `Intake paused` (already close in AppModel).

### Asset production brief (if refining outside these files)
1. Trace soft-catch silhouette at 16 / 18 / 32 pt; check legibility at actual menu-bar size on Retina.
2. App icon: build layered Icon Composer document from light concept; derive dark appearance.
3. Validate squircle mask preview in Xcode; no hairline at corners.

---

## 2) Settings UX polish

### IA (unchanged order)
1. General  
2. Rules  
3. Cleanup  
4. AI  
5. About  

Sidebar: `Label` + SF Symbol per pane (keep system symbols for sidebar; custom icon is Dock/app only).

### Global Form patterns
- `.formStyle(.grouped)` everywhere settings content lives (Rules should move from free VStack into Form + Section for consistency).
- Section **headers** short nouns; **footers** one helpful sentence (Thaw-quality).
- Primary buttons: system prominent where it’s the pane’s main action (`Choose…` is secondary to path display; Cleanup’s **File Away** is primary).
- Density: default control size; avoid oversized custom cards; 8–12pt between stacked controls inside a section is enough.
- Window: Settings scene; remember last pane if cheap.

### Per-pane spec

#### General
| Element | Spec |
|---|---|
| Section Watch folder | `LabeledContent("Folder")` truncated middle path + text selection |
| Actions | `Choose…` · `Show in Finder` (secondary) |
| Section Organizing | Toggles: `Pause organizing` · `Open at login` |
| Footer | Keep existing explainer (stable download → rename → lazy folder) |
| Empty/error | If bookmark lost: banner “Intake can’t see the watch folder” + Choose… |
| Section Appearance in macOS (IN-05) | Toggles `Show in Dock` (default On) · `Show in menu bar` (default On). Block turning both off. |

**Copy (EN)**  
- Footer: `Intake waits until a download is stable, then renames it and files it into a typed folder. Folders appear only when needed.`

#### Rules
| Element | Spec |
|---|---|
| Intro footer | Extension rules; lazy folders |
| Table | On (checkbox) · Folder (Label+symbol) · Extensions |
| Empty | N/A (defaults always present) |
| Future | “Add rule” out of v1 polish unless already planned — don’t stub fake buttons |

**Copy**  
- Header: `Default taxonomy`  
- Footer: `Unmatched types go to Other, and only if something lands there.`

#### Cleanup (settings = threshold + queue — see also §4)
| Element | Spec |
|---|---|
| Threshold | Stepper “Unused for N days” (1…365) |
| Include root | Toggle with clear label |
| Queue | Table or list; empty → ContentUnavailableView |
| Actions | File Away (primary) · Keep · Delete (destructive) |

**Copy**  
- Empty title: `No cleanup candidates`  
- Empty body: `Files not opened or modified for {N} days will show up here.`  
- Prefer “File Away” spelling consistency (title case in buttons).

#### AI
| Element | Spec |
|---|---|
| Master toggle | Off by default |
| Providers | List with status Available / Not installed / Unavailable — never purple “AI” hero |
| Footer | Local-first privacy sentence |

**Copy**  
- Toggle: `Suggest names and folders with AI`  
- Helper: `Off by default. Core organizing uses extension rules only.`  
- Privacy: `Intake does not send file contents to a network service unless you enable a provider.`

#### About
App name + short tagline, version, MIT, links, privacy blurb. Optional small app icon at top (system About style), not a marketing landing.

### What “Thaw-quality” means here
- Grouped forms that feel inevitable on macOS  
- Empty states that teach the job  
- Footers instead of modal help  
- No custom tab bars, no dashboard cards, no gradient sidebars  

### What it does **not** mean
- Copying Thaw layouts, assets, or GPL code  
- Matching Thaw’s exact colors or icons  

---

## 3) Menu bar experience

### Job
Glance status, pause safely, jump to a recent file, open Settings — without a dock-dependent main window.

### Dropdown structure (top → bottom)
1. **Status title** — `Watching` / `Paused` (bold via default menu header if using MenuBarExtra section APIs; else plain Text)  
2. **Subtitle** — `New files in Downloads` / `Organizing is paused · Downloads`  
3. Divider  
4. **Pause Organizing** / **Resume Organizing** (verb + object)  
5. Divider (only if recent non-empty)  
6. **Recent activity** (up to 5) — each row = filename + short verb (`Renamed`, `Moved`, `Skipped`, `Error`); click → Reveal in Finder  
7. Divider  
8. **Settings…** (`⌘,`)  
9. Divider  
10. **Quit Intake** (`⌘Q`)

### Findability
- First launch: open menu bar extra once OR show a one-time Settings tip: `Intake lives in the menu bar — look for the soft-catch icon near Control Center.`  
- Prefer custom template icon over tray SF Symbol so it’s recognizable next to system items.  
- **Dock (per IN-05 / captain):** Dock **ON** by default with the same soft-catch app icon; menu bar **ON** by default. Independent toggles in General (“Show in Dock” / “Show in menu bar”); **forbid both off** with alert *Keep one way to open Intake*. Do not ship permanent `LSUIElement=1`. See `/workspace/fm-intake/IN-05-product-dock-thaw.md` for product copy.

### States
| State | Menu bar glyph | Title |
|---|---|---|
| Watching | Soft-catch | Watching |
| Paused | Soft-catch paused | Paused |
| Error (bookmark/permission) | Soft-catch + caution if needed, or keep glyph + subtitle `Needs folder access` | Attention |

### Avoid
Long paragraphs in the menu; nested submenus for v1; badges that scream; animating the template icon constantly (Reduce Motion).

---

## 4) Activity + Cleanup

### Activity (audit trail)
**Where:** Prefer a dedicated area — either Settings → add **Activity** pane **or** a section under General. Recommendation: **sixth sidebar item “Activity”** between Cleanup and AI **or** after General. If IA must stay at 5 panes, put a compact Activity list at bottom of General. **Preferred:** add Activity pane (update DESIGN IA).

**Row design**
- Leading: SF Symbol by kind (`checkmark.circle` moved, `pencil` renamed, `forward` skipped, `exclamationmark.triangle` error) — monochrome hierarchical  
- Title: final filename  
- Subtitle: `Renamed · 2:41 PM` / `Moved to Documents · Yesterday`  
- Trailing: optional folder name  
- Action: select → Reveal; context menu Reveal / Copy path  

**Empty**  
- Title: `No activity yet`  
- Body: `When Intake renames or files a download, it shows up here.`  
- Symbol: `list.bullet.clipboard` (or soft-catch if custom)

**Errors**  
- Show reason in subtitle; don’t fail silently.

### Cleanup (decision queue)
**Row / table columns:** Name · Age (relative) · Size · Path (secondary, middle truncate)  

**Selection actions**
| Priority | Action | Notes |
|---|---|---|
| Primary | **File Away** | Opens folder picker or rule destination; then remove from queue |
| Secondary | **Keep** | Snooze / exclude from cleanup for now |
| Destructive | **Delete** | `confirmationDialog` with filename; copy: `This cannot be undone from Intake.` |

**Multi-select (nice):** File Away / Keep / Delete apply to selection; Delete confirm lists count.

**Empty:** existing ContentUnavailableView pattern — keep; fix “File Away” casing in description to match buttons.

**After actions:** remove empty Intake-created category folders (product principle) — no extra scary UI; optional subtle status `Removed empty folder Documents` in Activity.

---

## 5) Do / Don’t (Intake ≠ web)

### Do
- SwiftUI `Form` / `Table` / `List` / `NavigationSplitView` / `MenuBarExtra` / `SettingsLink`  
- System materials, accent, typography (`.title`, `.headline`, `.body`, `.caption`)  
- One primary action per view  
- Plain language; reversible destructive paths  
- Template menu-bar icon; HIG spacing  
- Light/dark; Dynamic Type; Reduce Motion; VoiceOver labels on icon and rows  

### Don’t
- shadcn/Radix card grids, rounded marketing sections inside Settings  
- Purple AI gradients, “sparkle spam,” glassmorphism dashboards  
- Custom CSS-like chrome that fights macOS  
- Pre-creating empty category folders in UI mockups  
- Copying Thaw (or any GPL) UI source  
- Applying QuoteRight web patterns to Intake  

---

## Accessibility (macOS HIG + WCAG 2.2 AA adapted)
- Menu bar icon: accessibility label always  
- All icon-only controls have labels  
- Delete confirmations keyboard reachable  
- Contrast: system labels on grouped backgrounds (avoid custom gray-on-gray)  
- Don’t convey pause/watch by color alone — glyph + title text  

---

## Acceptance criteria (Intake Dev)
- [ ] Soft-catch app icon in asset catalog (light/dark as appropriate); squircle-safe  
- [ ] Menu bar uses template soft-catch SVG/PDF; Watching vs Paused distinguishable at 16–18pt  
- [ ] Settings panes use grouped Form patterns + footers; Rules consistency fixed  
- [ ] Menu structure matches §3; Settings… and Quit with shortcuts  
- [ ] Activity rows + empty state; Cleanup empty + File Away / Keep / Delete confirm  
- [ ] No web/shadcn chrome; no Thaw source  
- [ ] PR includes before/after (or Preview) screenshots: menu bar + Settings General + Cleanup empty/populated  

---

## Out of scope
Wiring AI providers for real; full Finder replacement; Windows; inventing new taxonomy folders beyond PRODUCT.

## Blockers
None. Assets ready under `/workspace/fm-intake/assets/`.

---

## File index
| Path | What |
|---|---|
| `IN-03-design-handoff.md` | This handoff |
| `assets/intake-app-icon-light.png` | App icon concept (light) |
| `assets/intake-app-icon-dark.png` | App icon concept (dark) |
| `assets/MenuBarIcon-Watching.svg` | Menu bar template |
| `assets/MenuBarIcon-Watching-simple.svg` | Simpler 16pt template |
| `assets/MenuBarIcon-Paused.svg` | Paused template |
| `PRODUCT.md` / `DESIGN.md` | Copies of current docs (source of truth remains repo `docs/`) |
