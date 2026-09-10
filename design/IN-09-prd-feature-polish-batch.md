# IN-09 — Intake feature / polish batch (PRD + backlog)

**Product:** Intake (not QuoteRight)  
**From:** Product Manager → Firstmate  
**Task id:** IN-09-prd  
**Grounding:** current `docs/PRODUCT.md`, `docs/DESIGN.md`, repo state (`RoutingRule` = category + extensions + isEnabled; Rules UI = enable toggles only; AI providers = placeholders “Unavailable”; General = “Pause organizing”; Dock/launch → Activity).  
**Audience:** Firstmate → Designer + Intake Dev. No production code from PM.

---

## Sequencing (recommended)

| Priority | Items | Why | Designer before Dev? |
|---|---|---|---|
| **P0 — quick UX** | (6) Dock/launch → **Settings**; (4) **Automatic organizing** toggle (replace Pause) | Captain called these quick; unblocks correct mental model + chrome. Low design risk if copy/layout stay system Form. | **Light Designer** (copy + menu-bar status strings). Dev can start in parallel with copy freeze. |
| **P0 — Settings chrome** | (3) Settings sidebar polish / NavigationSplitView bug | Captain-reported bug; blocks trust in Rules work. | **Yes — Designer pass first** (native split, widths, selection, no web patterns). |
| **P1 — rules core** | (1) **Customizable rules** | Needed foundation; captain said customize matters but suggestions matter *more* — still ship editable rules before or with suggestions accept path. | **Yes — Designer** (edit row / sheet / add rule). Dev after wireframes. |
| **P1 — suggestions (captain “more importantly”)** | (2) **Trend-based rule suggestions** | Highest product leverage once Activity has data; depends on being able to **accept → real rule** (needs #1 or minimal accept-to-new-rule path). | **Yes — Designer** (suggestion cards/rows, empty state). Can stub analytics locally while #1 lands. |
| **P2 — atmosphere** | (5) Native **MeshGradient** background | Polish; must not fight HIG or Reduce Motion. | **Yes — Designer** (which surfaces, light/dark tokens). Dev implements native only. |
| **P2 — AI** | (7) **OpenRouter** provider | Opt-in network; heavier than toggle work; after rules/suggestions trust. | **Light Designer** (AI pane fields). Dev owns Keychain + API. |

**Suggested ship order:** P0(6→4) ∥ P0(3 Designer) → P1(1) → P1(2) → P2(5) ∥ P2(7).  
If capacity forces a cut: keep P0 + (2) with a minimal accept path that adds extension→folder rules even if full rename-pattern editor slips.

---

## 1) Customizable rules

### Problem
Rules pane today is mostly **enable checkboxes** + read-only extension lists (`RulesSettingsView`). PRODUCT promises “Users can edit rules later.” Operators cannot add extensions, rename destinations, reorder, or add a custom bucket without code.

### Outcome
User can fully manage the taxonomy that drives rename→route: edit extensions, destination folder label, enable, and order; add/remove custom rules within safe bounds.

### Editable (v1 definition)
| Field | Editable? | Notes |
|---|---|---|
| **Enable** | Yes (exists) | Persist (already). |
| **Extensions** | **Yes** | Set of lowercase extensions without dots; validate tokens; conflict warning if two enabled rules claim the same extension (first match wins by order). |
| **Destination folder name** | **Yes** | Display / folder name under watch root. Built-in categories keep a stable id; renaming changes folder name used for new routes (do not mass-rename existing folders in MVP — document). |
| **Order** | **Yes** | Drag reorder; first matching enabled rule wins. |
| **Add rule** | **Yes** | Custom id + folder name + extensions. |
| **Delete / reset** | Soft delete custom; **Reset to defaults** for built-ins. |
| Rename *patterns* (Arc-style templates) | **Later** unless already trivial | Separate from routing rules if not in model yet. |

### Acceptance
1. User can edit a rule’s extension list and save; new matching downloads route accordingly.  
2. User can reorder rules; conflicting extensions resolve by order (documented in footer).  
3. User can add a custom rule (e.g. `psd, ai` → `Design`) and disable it.  
4. Enable toggles still work; persistence across launch.  
5. Invalid extension tokens rejected with inline error.  
6. No pre-creation of empty folders (lazy folders preserved).

### Effort
**M** (model + persistence + UI). Designer before Dev.

---

## 2) Trend-based rule suggestions (**priority**)

### Problem
Default taxonomy misses niche types (e.g. many loose `.psd`). Users won’t invent rules cold. Captain: suggestions are **more important** than bare customization alone.

### Outcome
Rules pane surfaces **local, private** suggestions from observed Downloads/Activity trends; user Accept → creates/edits a rule, or Dismiss → hides for a cooldown.

### Data sources (local only)
1. **Watch-folder root** extension histogram (loose files only; same ignore policy as ingest).  
2. **Activity log** — skipped / Other / unmatched outcomes and extensions seen over time.  
3. **Existing rules** — never suggest something already covered by an enabled rule.

**Privacy:** All computation on-device. No network. No file *contents* read for suggestions (extension + optional UTI if already available). No screenshots of paths sent anywhere.

### Cold start / empty
- Fewer than **N** signal events (recommend N=8 files of same uncovered extension, or 5 within 14 days): show quiet empty — “Suggestions appear after Intake sees repeating file types.”  
- No fake examples.

### UX
- Section under Rules: **Suggested rules**.  
- Row: “Often seeing `.psd` in Downloads → add to **Images**?” or “Create folder **Design** for `.psd`, `.ai`”.  
- Actions: **Add rule** / **Not now** (dismiss 30 days) / **Never for this extension**.  
- Accept opens the customizable rule editor prefilled (depends on #1) or applies a one-tap default mapping for known types.

### Acceptance
1. With ≥N loose/Activity hits for an uncovered extension, a suggestion appears within Rules.  
2. Accept creates/enables a persisted rule that subsequent ingest uses.  
3. Dismiss hides that suggestion for cooldown; Never suppresses until reset.  
4. Covered extensions never re-suggested.  
5. Works offline; zero network.  
6. Empty/cold-start copy as above — no placeholder fake trends.

### Effort
**M**. Designer for suggestion rows; Dev for histogram + Activity join. Sequence after or tightly with #1.

---

## 3) Settings sidebar polish / bug

### Problem
Captain: sidebar bug + needs polish. Settings uses `NavigationSplitView` (DESIGN). Likely selection, width, or column collapse issues — **do not invent web chrome**.

### Outcome
Stable native Settings: sidebar selects panes reliably; widths per DESIGN (sidebar 160–240pt; detail ~480–560pt); grouped forms; no layout jump.

### Acceptance
1. Clicking each sidebar item shows the correct pane every time (General, Rules, Cleanup, Activity, AI, About).  
2. No blank detail, double-selection, or collapsed-irrecoverable sidebar on launch.  
3. Keyboard/VoiceOver can move between panes.  
4. Light/dark + Dynamic Type OK.  
5. Designer sign-off against HIG (no card grids / Material / shadcn).

### Effort
**S–M**. **Designer first**, then Dev.

---

## 4) Toggle rename: Pause → **Automatic organizing**

### Problem
“Pause organizing” is a negative control. Captain wants **Automatic organizing**: ON = watcher live; OFF = stopped. Invert `isPaused` mental model.

### Outcome
One positive toggle everywhere; menu bar status matches.

### Copy / mapping
| State | Settings toggle | Menu bar status | Menu action |
|---|---|---|---|
| Auto ON | Automatic organizing **On** | Watching (or equivalent glyph) | Turn Off Automatic Organizing… / pause affordance |
| Auto OFF | Automatic organizing **Off** | Automatic organizing off / Paused glyph OK if still clear | Turn On Automatic Organizing |

**Migration:** `automaticOrganizing = !intake.paused` (or rename key once; read old `intake.paused` if present, then write new key).

### Acceptance
1. General shows **Automatic organizing** (not Pause).  
2. ON → live watcher processes new files; OFF → no new auto ingest (Organize Existing still allowed per IN-08).  
3. Menu bar icon + labels match state.  
4. Old `paused` preference migrates correctly on upgrade.  
5. PRODUCT/DESIGN chrome strings updated (Firstmate → docs task or Dev).

### Effort
**S**. Light Designer copy.

---

## 5) Background MeshGradient (**native only**)

### Problem
Captain referenced React `@paper-design/shaders-react` MeshGradient (colors `#000000`, `#000000`, `#1d16e957`, `#000000`; distortion 0.8; swirl 0.1; grainMixer 0.54; grainOverlay 0.08; speed 1; scale 1.36). **Intake is SwiftUI** — no React/webview embed.

### Outcome
Subtle native animated mesh behind **Activity** (primary atmosphere). Settings stays system grouped (no busy shader behind forms — readability). Optional very subtle static wash only if Designer insists — default **Activity only**.

### Native approach
- Prefer SwiftUI `MeshGradient` (macOS 14+ / aligned with macOS 26 deployment) with a small set of control points approximating the purple-black field (`#1d16e9` at low alpha on black).  
- Motion: slow parameter drift approximating speed/scale — **not** a pixel-perfect React port.  
- Grain: light Metal/SwiftUI noise overlay **or** omit if it fights clarity.  
- **Reduce Motion:** freeze to static mesh or solid `surface`.  
- **Reduce Transparency / Increase Contrast:** fall back to solid semantic background.  
- Dark-first recipe from captain; provide light-mode Designer variant (do not force pure black on light Appearance).

### Acceptance
1. No WKWebView / React / npm shader in the app binary for this effect.  
2. Activity shows mesh when motion/transparency allowed; respects Reduce Motion & Reduce Transparency.  
3. Text/controls remain WCAG-ish contrast on the mesh (system materials/scrims as needed).  
4. Settings forms remain standard `surface` (no competing animation).  
5. Designer approves light + dark.

### Effort
**M**. Designer owns look; Dev owns MeshGradient/Metal.

---

## 6) Dock / launch default → **Settings** (revert IN-08 Activity-primary)

### Problem
IN-08 / current PRODUCT+DESIGN: Dock click → **Activity**. Captain now wants **Settings** as the default window on Dock/launch/reopen. Activity remains via menu **Open Activity**.

### Outcome
Normal app open → Settings scene; Activity is opt-in from menu bar / Open Activity.

### Acceptance
1. Dock click, Finder reopen, and normal launch bring **Settings** forward (last pane or General).  
2. Menu bar retains **Open Activity**.  
3. Activity window still exists and persists when opened.  
4. Update PRODUCT Findability + DESIGN Chrome bullets (Activity is audit window, not Dock default).  
5. General footer copy that today says Dock is for opening Activity → retarget to Settings.

### Effort
**S**. Docs + one launch path change. Light Designer.

---

## 7) OpenRouter as AI API provider

### Problem
AI pane lists Ollama/CLI placeholders as “Unavailable.” Captain wants **OpenRouter** as a real network provider for suggest-name / suggest-bucket when rules miss.

### Outcome
User can enable AI suggestions, store an OpenRouter API key in **Keychain**, set base URL (default OpenRouter), pick a model, and use it only when explicitly enabled — **no file contents uploaded unless AI suggestions are on and a provider is configured** (keep PRODUCT promise).

### MVP scope
- Provider row: OpenRouter — Enable, API key (secure field → Keychain), Base URL (default `https://openrouter.ai/api/v1`), Model (text field or small curated list).  
- When AI suggestions toggle off → no network.  
- When on + key valid → suggest on rule miss / Other (define 1 call site: suggest folder and/or name).  
- Errors: inline “Unauthorized / rate limit / offline” — no crash.  
- Still off by default.  
**Out:** streaming token UI polish (unless trivial); multi-provider routing matrix; sending full file bytes (metadata/name/extension only unless user opts into “include preview text” — **default off**, defer preview to later).

### Acceptance
1. Key never written to plaintext prefs/logs.  
2. With suggestions off, zero OpenRouter requests (verify in debug).  
3. With suggestions on + key, a rule-miss path can show an AI suggestion the user can accept/dismiss.  
4. Footer restates: local rules first; network only when enabled.  
5. Ollama/CLI rows may remain “later” placeholders.

### Effort
**M**. Light Designer; Dev Keychain + HTTPS.

---

## Docs follow-ons (Intake Dev or docs agent)

Update `docs/PRODUCT.md` + `docs/DESIGN.md` when P0 lands:
- Dock/launch → Settings (not Activity).  
- Automatic organizing language (retire Pause as primary).  
- Rules editable + suggestions section.  
- AI: OpenRouter as first network provider; still opt-in.

---

## Handoff

| Owner | Work |
|---|---|
| **Designer** | P0 sidebar; P1 rules editor + suggestion rows; P2 mesh (Activity); light copy for Automatic organizing + Dock→Settings; AI pane fields |
| **Intake Dev** | P0 Dock→Settings + Automatic organizing migration; P0 sidebar fixes after Designer; P1 rules CRUD; P1 suggestions engine; P2 MeshGradient; P2 OpenRouter |
| **Firstmate** | Assign tickets; gate heavy items on Designer |
| **PM** | Clar only if asked |

**Captain via Firstmate only** — this file is the backlog; no direct captain ping from PM.
