# Organize Existing

Organize Existing is the manual one-shot for files already sitting in a watch-folder root: it previews the rename and destination folder for every eligible file, lets the user exclude files or whole groups, and on `Organize` renames and files them (ignoring Wait before organizing), logging Activity rows. `Cancel` writes nothing.

## Sub-features

- `organize-open` opens the preview from the menu bar extra, the Intake menu, or Settings ▸ General ▸ Existing files.
- `organize-nothing` with no loose files, an alert `Nothing to organize` / "There are no loose files in your watch folders." (`OK`).
- `organize-preview` groups by destination (`Documents`, `Images`, …) with counts and `New folder` for folders that don't exist yet; `<n> selected` footer.
- `organize-exclude` per-file / per-group `Exclude <name>` / `Include <name>` toggles.
- `organize-cancel` `Cancel` (Esc) closes the preview with no changes.
- `organize-apply` `Organize` (Return) files the selected files: `Filing loose files` progress, then Activity rows `Renamed` and `Moved`.
- `organize-ineligible` files listed as `Still downloading`, `Ignored`, or `Empty placeholder` are not touched.

## How to get to it (user POV)

- Menu bar extra ▸ `Organize Existing…` (a submenu `All Watch Folders` / each folder with several folders).
- Intake menu ▸ `Organize Existing…`.
- Settings ▸ General ▸ Existing files ▸ `Organize Existing…`.

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0 with no `screen is LOCKED` warning (the preview is a sheet).
- Loose files in the inbox that the live watcher already knows, e.g. drop `quarterly-report-q1.pdf` and wait for `Quarterly Report Q1.pdf` (rename-on-download), plus a second fixture `IMG_0001.png` with content.

- **Nothing to organize.** On an empty inbox run `$S/drive.sh extra "Organize Existing…"` then `$S/drive.sh wait-text "Nothing to organize" 5`; `$S/drive.sh press OK`.
- **Preview.** With files present run `$S/drive.sh extra "Organize Existing…"` then `$S/drive.sh wait-text "selected" 10`. The AX tree shows groups `Documents` and `Images` (marked `New folder`).
- **Cancel.** Run `$S/drive.sh press Cancel`. `$S/drive.sh inbox` is unchanged.
- **Apply.** Reopen the preview and run `$S/drive.sh press Organize`. `$S/drive.sh wait-file "Documents/Quarterly Report Q1.pdf" 15`; `$S/drive.sh inbox` shows `./Documents/…` and `./Images/…`; `$S/drive.sh activity` gains `moved` rows.
- **Proof.** `$S/evidence.sh snapshot organize-preview` before pressing `Organize`, `$S/evidence.sh snapshot organize-done` after.

## Gotchas

- It never runs on launch and does not wait for Wait before organizing; the live watcher's 2-hour Wait in the baseline is unaffected.
- The preview reads files for content-aware names only when content-aware rename is on (up to 40 files) — keep it off for deterministic previews.
- A file changed between preview and Apply is logged `skipped`, not an error.
- Category folders are created only when the first file needs them; an empty inbox never gains folders.
