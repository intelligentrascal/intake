# IN-08 — Intake: Organize existing Downloads (manual one-shot)

**Product:** Intake (not QuoteRight)  
**From:** Product Manager → Firstmate  
**Task id:** IN-08-prd  
**Grounding:** [docs/PRODUCT.md](https://github.com/intelligentrascal/intake/blob/main/docs/PRODUCT.md) (ingest: rename → route → Activity; lazy folders; reversible; rules over magic), [docs/DESIGN.md](https://github.com/intelligentrascal/intake/blob/main/docs/DESIGN.md) (MenuBarExtra, Settings, Activity).  
**Builder:** Intake Dev (in progress). Designer owns chrome/findability follow-ons noted below.

---

## Problem

Live watcher only handles **new** arrivals in the watch folder. Files already sitting in `~/Downloads` (or the configured root) stay a junk drawer until touched again. Users who install Intake mid-mess need a deliberate catch-up — without surprising auto-sweeps on launch.

## Outcome

User can run a **manual one-shot** that applies the same rename-then-route ingest rules to **current loose files in the watch-folder root**, logs to Activity, creates category folders only when needed (lazy folders), and never auto-runs on launch.

## Scope (MVP)

**In**
- Entry points (at least one primary; prefer both if cheap):
  1. Menu bar: **Organize Existing…**
  2. Activity (or General Settings): same action as a button
- Confirmation before run: plain copy — what will be scanned (watch root only), that rename+move will apply, undo/Activity visibility if available.
- Scan **watch-folder root only** (not recursive into Intake-managed category folders already created — avoids re-processing filed items). Skip partial downloads / ignore policy (same as live ingest: `.download`, unstable, Quarantine churn per PRODUCT).
- For each eligible file: same pipeline as ingest — propose/apply rename → match rule → ensure dest folder → move → Activity log (renamed / moved / skipped / error).
- Progress UI: determinate if count known, else indeterminate + cancel.
- Cancel: stop scheduling new files; in-flight file finishes or safely aborts without corrupt half-moves.
- **Auto-on-launch: no.** No launch agent one-shot; no “run organize when app starts” default or hidden flag in v1.

**Out**
- Recursively re-organizing inside `Documents/`, `Images/`, etc.
- Silent mass delete
- AI naming (phase 2)
- Changing Cleanup semantics
- Auto-run on launch or on watch-folder change beyond live new-file ingest

## UX copy (suggested)

- Button / menu: **Organize Existing…**
- Confirm title: **Organize files already in Downloads?** (use actual watch folder name if not Downloads)
- Body: “Intake will rename and file items sitting in the watch folder root using your current rules. Files already in category folders are left alone. You can follow every change in Activity.”
- Buttons: **Organize** (primary) / **Cancel**
- Done: “Organized N files. S skipped. E errors.” + **Show Activity**

## Acceptance criteria

1. With loose files in watch root, user runs Organize Existing → eligible files renamed/routed per current rules; Activity shows one row per outcome.
2. Files already inside Intake category folders under the watch root are **not** re-processed.
3. Ignored/partial download patterns match live ingest ignore policy (skipped, logged if useful).
4. Empty category folders are **not** pre-created; folders appear only when a file needs them (PRODUCT lazy folders).
5. User can cancel mid-run; no orphaned temp names / half-moved files left undocumented.
6. Quitting and relaunching Intake does **not** start Organize Existing automatically.
7. Pause organizing (if engaged) either disables the action with explanation **or** requires resume first — pick one; document in UI (prefer: action available but confirm warns that watching is paused / one-shot still runs — PM default: **one-shot allowed while paused**, does not unpause watcher).
8. EN copy ships; no fake progress counts.

## Effort (rough)

**S–M** for Intake Dev if ingest pipeline is reusable; UI is confirm + progress + menu/Activity entry.

---

## Open UX gaps (brief for Designer — not blocking IN-08 ship)

Captain-noted; product framing for Designer later (do not block Organize Existing MVP):

| # | Gap | Product intent |
|---|---|---|
| 1 | **Menu bar icon findability** (dual-display; template rendering may be faint) | Status extra must stay discoverable: prefer template image that reads in light/dark on all displays; consider monochrome SF Symbol asset tuned for menu bar; document dual-display behavior (extra follows menu bar of the display where it was placed / system default — no Thaw-style multi-bar manager). |
| 2 | **Dock / launch → primary window** | Per IN-05, Dock is default ON. Captain: Dock/launch should open a **real primary window**, not Settings-only. **Activity is the v1 primary** (chronological proof of value). Settings remains secondary (⌘, / menu). Update IN-05 handoff: Dock click → **Activity**; menu bar keeps Pause + Open Activity / Cleanup / Settings. |

Designer can take these as IN-08 adjacent polish tickets after Organize Existing lands.

---

## Handoff

- **Firstmate → Intake Dev:** build to acceptance above.  
- **Firstmate → Designer:** gaps 1–2 when capacity.  
- **PM:** idle unless clar needed.
