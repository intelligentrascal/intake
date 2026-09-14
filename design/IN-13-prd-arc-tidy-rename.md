# IN-13 — Arc Tidy–style rename on download (PRD)

**Product:** Intake only (not QuoteRight)  
**From:** Product Manager → Firstmate  
**Task id:** IN-13-prd  
**Option:** **A only** (reject B/C)  
**Grounding:** current `docs/PRODUCT.md` ingest (wait then rename+route), `FileNameNormalizer`, `IngestPipeline`, live watcher Wait before organizing.

---

## Problem

Today, after a download becomes stable, **Wait before organizing** (default 2h) blocks the **entire** ingest — including local `FileNameNormalizer` rename — so noisy CDN names sit in Downloads for hours.

Captain wants Arc Browser Tidy Downloads behavior: **rename as soon as the file is stable**, then file into folders only after Wait.

## Outcome

Rename when download finishes (Arc Tidy), not only when organizing into folders. Wait still delays filing. Local normalizer only. OpenRouter unchanged (folder suggest for Other only; **no AI rename**).

## Ship Option A

1. On stable download in watch-folder **root**: if toggle **Rename when download finishes** is On → **rename in place** via existing `FileNameNormalizer` (local, deterministic). Activity: `renamed` (still in root).
2. **Wait before organizing** gates **routing/filing only** (move into lazy category folder). Clock still from `stableAt`. Activity: `moved` later.
3. Wait = Immediately → rename then route back-to-back.
4. **Automatic organizing Off** + Rename On → still rename in root; **no** auto move.
5. Rename Off → no early rename; organize path may still rename when filing (legacy couple).
6. **OpenRouter unchanged** — folder suggest for Other only; **no AI rename**.
7. Ignore policy / partial downloads unchanged. Do not rename files already inside category folders.

## Settings (General → Organizing)

- **Label (exact):** `Rename when download finishes`
- **Default:** On
- **Placement:** near Automatic organizing / Wait before organizing
- **Footer (exact):** `Renames the file as soon as the download is stable — on this Mac only. Wait before organizing still delays filing into folders.`
- Persist preference (UserDefaults key `intake.renameWhenDownloadFinishes`). Avoid “AI rename” / cloud language.

## Acceptance

1. Rename On: after stability, watch-root file gets normalized name **before** Wait elapses.
2. After Wait, file routes per rules; name preserved unless collision suffix.
3. Wait = Immediately → rename then route without multi-hour gap.
4. Rename Off → no early rename.
5. Auto Off + Rename On → rename in root, no auto move.
6. OpenRouter unchanged (no rename).
7. Ignore/partial unchanged; wait from `stableAt`.
8. `docs/PRODUCT.md` ingest steps: rename-on-stable, then wait, then route.
9. Unit tests for split pipeline (rename stage vs route stage).

## Out

- Option B / C
- AI / cloud rename
- Changing ignore policy or partial-download handling
- Restoring ActivityWindowFallback NSHosting path
