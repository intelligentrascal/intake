# IN-14 — Arc Tidy research + Intake rename formatting

**Product:** Intake (not QuoteRight)  
**From:** Product Manager → Firstmate  
**Task id:** IN-14-arc-tidy-research  
**Context:** IN-13 shipped rename-on-stable; captain says names are readable but **poorly cased** (smoke: `arc Tidy Camel Case Report …`, `board Update deck final.pptx`). Goal: Arc-like tidy = readable **and** well-formatted.  
**No code** — research + PRD only.

---

## 1) How Arc Tidy Downloads works (public evidence)

Sources (not an official algorithm dump — Arc does not publish a rule sheet):

| Source | What it states / shows |
|---|---|
| [Arc Help — Arc Max](https://resources.arc.net/hc/en-us/articles/19335160678679-Arc-Max-Boost-Your-Browsing-with-AI) | Tidy Downloads is an **Arc Max (AI)** feature (macOS); runs automatically on downloads when enabled; undo by clicking the download name; disable under Settings → Max |
| [TidBITS](https://tidbits.com/2023/10/06/arc-web-browser-introduces-focused-ai-features/) | Renames awkward auto-generated names into something more readable; bottom-left toast; curved-arrow **revert** |
| [appsntips example](https://www.appsntips.com/news/arc-browser-unveils-arc-max-ai-features/) | `macOS_All_New_Features` → **`macOS Sonoma features`** — implies **page/context-aware** shorten, not only underscore→space + Title Case |
| [Herman White](https://hwhite.dev/blog/arc-max) | Often replaces underscores with spaces; can rename files that already had useful names |
| [r/ArcBrowser](https://www.reddit.com/r/ArcBrowser/comments/17eitjx/how_can_i_prevent_arc_from_changing_downloaded/) | Users report: unwanted **translation**, **removal of trailing numbers**, pain on **GitHub** exact filenames; want reliable undo / off switch |

### Inferred Arc behaviors (high confidence vs low)

| Behavior | Confidence | Notes |
|---|---|---|
| AI / model rename (not a pure local caser) | **High** | Marketed as Arc Max AI |
| Underscores → spaces; more readable spacing | **High** | Multiple writeups |
| Extension preserved | **High** | Standard; AI omit-ext guarded in similar tools |
| Shorten / drop machine IDs, hashes, noise | **Medium–high** | User + press descriptions |
| Uses **download page / tab context** | **Medium** | Sonoma example cannot come from filename alone |
| Title Case as a hard rule | **Low** | Official docs never say “Title Case”; AI output varies (`macOS Sonoma features` is closer to **sentence-ish** with product casing) |
| Toast + one-click undo | **High** | Help + TidBITS |
| Opt-in (Max) and can annoy power users | **High** | Reddit |

**Important for Intake:** Matching Arc *pixel-for-pixel* means **AI + browse context**. Intake is a Downloads FS watcher — no tab title by default, and PRODUCT says **rules over magic / private by default**. IN-14 should **raise local formatting quality** to feel Arc-tidy in the Finder sense, and treat true Arc AI semantics as an **optional later** (OpenRouter), not the default rename path.

### Arc extras Intake still misses (beyond rename-on-stable + folder filing)

1. **Notification toast + revert** after rename (TidBITS / Help).  
2. **Context-aware shorten** from the page that initiated the download (browser-only).  
3. **Aggressive de-noising** (strip tracking IDs) — Intake normalizer is structural, not semantic.  
4. Max-style “this is AI” positioning — Intake should stay honest: local tidy vs optional AI.

---

## 2) Why Intake looks weak today (repo)

`FileNameNormalizer.titleCaseIfAllLowercase` only Title-Cases when **every letter is lowercase**. After camelCase splits / mixed tokens, names like `arc Tidy Camel Case Report` and `board Update deck final` **keep irregular casing**.

Structural cleans already good: `_`/`+`/`%20` → spaces, kebab→words, camel split, strip `(1)` / `copy`, keep digit-digit date hyphens, preserve extension case.

**Gap = consistent word casing after clean**, plus small polish (acronyms, tiny words, version tokens).

---

## 3) PRD — Rename formatting rules (local normalizer)

### Outcome
After structural clean, every renamed base name is **consistently formatted** so Finder lists look intentional — without requiring network/AI for the default path.

### Recommended casing policy
**Title Case with exceptions** (see open decisions §4 — this is the PM recommendation):

1. Split into words on spaces (after existing clean).  
2. Capitalize the **first letter** of each word; leave the rest lowercase **unless** exception applies.  
3. **Small words** (lowercase unless first or last word): `a, an, the, and, or, but, for, nor, as, at, by, in, of, on, to, vs, via`.  
4. **Acronym / product allowlist** (keep known casing): e.g. `PDF` not in base (ext separate); in base: `AI, API, CPU, GPU, iOS, macOS, iPhone, iPad, ID, URL, HTTP, HTTPS, Q1–Q4, OKRs` — start small, expand via tests.  
5. **Version / build tokens:** preserve `v1`, `v2.3`, `b12`, bare `Q1` style; do not force `V1`.  
6. **ALL-CAPS words ≤ 4 letters** that look like acronyms (optional heuristic) — or stick to allowlist only for v1 predictability. **PM lean:** allowlist-only in v1 to avoid `USA`/`NASA` luck and `THIS` mistakes.  
7. **Emoji / non-letters:** keep; do not strip.  
8. **Extension:** never Title-Case the extension; leave as on disk.  
9. **No-op:** if cleaned name equals original base (already tidy), still apply casing pass so mixed mess gets fixed — unless Rename toggle off.

### Pipeline order (unchanged structure, stronger finish)
percent/plus → `_`→space → non-date `-`→space → camel split → strip `(n)`/`copy` → collapse whitespace → **`applyTitleCasePolicy` (new; always)** → reattach extension.

### Acceptance examples (before → after)

| Input (base + ext) | After IN-14 |
|---|---|
| `arc_Tidy_Camel_Case_Report.pdf` | `Arc Tidy Camel Case Report.pdf` |
| `board Update deck final.pptx` | `Board Update Deck Final.pptx` |
| `quarterly-report-q1.pdf` | `Quarterly Report Q1.pdf` (already) |
| `macOS_All_New_Features.pdf` | `MacOS All New Features.pdf` **or** `macOS All New Features.pdf` if `macOS` on allowlist — **prefer allowlist → `macOS All New Features.pdf`** |
| `TeamNotes.md` | `Team Notes.md` |
| `Invoice-2024-01-15.pdf` | `Invoice 2024-01-15.pdf` |
| `Report (1).pdf` | `Report.pdf` |
| `Family photo.heic` | `Family Photo.heic` (Title Case; small-word N/A) |
| `the_end_of_the_world.txt` | `The End of the World.txt` (small words) |
| `HELLO_WORLD.ZIP` | `Hello World.ZIP` (ext preserved) |

Also add regression tests for captain smoke strings.

### Non-goals (this slice)
- AI rename / page-title context  
- Translating filenames  
- Stripping version numbers by default (Arc users complained)  
- Toast UI (track as follow-on polish)

### Effort
**S** for casing policy + tests; **S–M** if toast/undo added later.

---

## 4) Open product choices (captain decision)

| # | Choice | Options | **PM recommendation** |
|---|---|---|---|
| **C1** | Casing style | **Title Case + small-word exceptions** vs **Sentence case** (first word only) vs **Always Title Case every word** (no small-word list) | **Title Case + small-word exceptions.** Best Finder scannability; closer to “polished document” names. Sentence case (`Board update deck final`) feels unfinished for multi-word downloads. Arc’s AI sometimes lands sentence-ish (`macOS Sonoma features`) — we should not pretend local rules equal Arc AI. |
| **C2** | `macOS` / `iPhone` style | Allowlist preserved casing vs force `Macos` | **Allowlist** for common Apple/tech tokens. |
| **C3** | Already “nice” mixed names | Always re-case vs leave if “looks human” | **Always run casing policy** after clean — fixes captain’s mixed mess; rare false positives acceptable with Undo later. |
| **C4** | Closer to Arc AI later | Keep local-only vs optional OpenRouter “Tidy name” | **Local default forever for on-download rename.** Optional AI tidy later as explicit opt-in (name suggestion), not silent on every file — PRODUCT private-by-default. |

**Blocker for Dev:** need captain call on **C1** (and optionally C2). If silent, Dev should ship **PM recommendation (C1 + C2 allowlist + C3 always)**.

---

## 5) Handoff

- **Firstmate → captain:** C1 casing decision (Title+small words recommended).  
- **Firstmate → Intake Dev:** implement §3 after C1 freeze (or PM default).  
- **Designer:** none required for normalizer; optional later toast/undo chrome.  
- **PM:** idle unless clar.

**Honesty:** Arc Tidy is **AI + context**; Intake should market **local tidy formatting**, not “Arc AI rename.”
