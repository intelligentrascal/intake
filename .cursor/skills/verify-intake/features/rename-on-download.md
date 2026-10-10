# Rename when download finishes

When a file finishes arriving in a watch folder's root, Intake renames it in place to a readable Title Case name (structural clean-up, small-word exceptions, a small allowlist such as `Q1`, `macOS`) without waiting for Wait before organizing, and records a `Renamed` row in Activity that can be undone.

## Sub-features

- `rename-titlecase` turns `quarterly-report-q1.pdf` into `Quarterly Report Q1.pdf` in the same folder.
- `rename-activity` adds a `renamed` Activity row (`renameSource: titleCase`) and a `<name> · Renamed` row in the menu bar extra.
- `rename-no-file-yet` leaves the file where it is: with the default 2-hour Wait it is not filed into `Documents` during the run.
- `rename-ignored` never renames hidden (dot) files, zero-byte placeholders, or partial downloads (`.crdownload`, `.part`, `.download`, …).
- `rename-collision` adds ` 2` only when a different file already holds the name (APFS case-insensitive compare).
- `rename-toggle-off` with General ▸ Rename when download finishes off, the file keeps its name.

## How to get to it (user POV)

- A browser or Finder drops a finished file into a watch folder (default `~/Downloads`; in verification, `IntakeVerifyInbox`).
- The setting lives in Settings ▸ General ▸ watch folder ▸ **Rename when download finishes** (on by default).

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0; the inbox is empty (`$S/drive.sh inbox` prints nothing).
- A non-empty fixture exists, e.g. `printf '%%PDF-1.4\n%% verify-intake fixture\n' > .verify-intake/quarterly-report-q1.pdf`.

- **Before.** Run `$S/evidence.sh snapshot before`. `menu-bar-extra.txt` shows `[Watching]`, `[New files in IntakeVerifyInbox]` and no recent rows; `activity.json` is `[]`.
- **Download lands.** Run `$S/drive.sh drop .verify-intake/quarterly-report-q1.pdf quarterly-report-q1.pdf` and `$S/evidence.sh note "dropped quarterly-report-q1.pdf"`.
- **Renamed.** Run `$S/drive.sh wait-file "Quarterly Report Q1.pdf" 15`. Exit 0 within ~3 s; `$S/drive.sh inbox` lists only `./Quarterly Report Q1.pdf` (not in a `Documents` folder).
- **Shown in the menu bar.** Run `$S/drive.sh status`. A row `[Quarterly Report Q1.pdf · Renamed]` appears between `[Organize Existing…]` and `[Open Activity]`.
- **Stored in Activity.** Run `$S/drive.sh activity`. One row: `kind: renamed`, `renameSource: titleCase`, `beforePath …/quarterly-report-q1.pdf`, `afterPath …/Quarterly Report Q1.pdf`, `detail: Renamed quarterly-report-q1.pdf to Quarterly Report Q1.pdf`.
- **Activity window.** Run `$S/drive.sh extra "Open Activity"` then `$S/drive.sh wait-text "Quarterly Report Q1.pdf" 10` (needs an unlocked screen).
- **Proof.** Run `$S/evidence.sh snapshot after-rename`. The snapshot holds the inbox listing, the Activity JSON, the menu bar extra, and `window-Activity.png` when the screen is unlocked.

## Gotchas

- Stability needs ~2 s of unchanged size/mtime after the last write; `wait-file` instead of `sleep`.
- A zero-byte file is never renamed (it looks like a browser placeholder). Use a fixture with content.
- `drop` writes `.verify-drop-<pid>` first; dot files are ignored, so only the final name is seen.
- Do not expect filing: Wait before organizing is 2 hours in the baseline profile. Use Organize Existing to prove filing.
- Content-aware rename is off by default; with it on, a second `renamed` row (`renameSource` content-aware) may follow — see `ai-content-aware-rename.md`.
