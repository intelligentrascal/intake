# AI pane: content-aware rename

Settings ▸ AI lets the user opt in to naming PDFs and images from their contents. The section is off by default; it shows a naming provider (`On this Mac` or `OpenRouter`), file-type toggles, a `Name template` whose default is `{date} {type} {organization} {subject}`, and `Try on a File…`. Below it: `Suggest folders with AI` and the `OpenRouter` section, both off by default.

## Sub-features

- `ai-defaults` fresh state: `Rename files from their contents` off; `Naming provider` = `On this Mac` (disabled); `PDFs` and `Images` toggles disabled; `Name template` = `{date} {type} {organization} {subject}` (the default value, also its placeholder), disabled; caption `Tokens: {date} {type} {organization} {subject} {original}. Empty tokens are dropped.`
- `ai-enable-ondevice` turning the toggle on with `On this Mac` enables the controls; when Apple's on-device model is unavailable a warning label explains why: `This Mac doesn’t support Apple’s on-device model, so files keep their Title Case names.`, `Turn on Apple Intelligence in System Settings to rename files from their contents.`, `The on-device model is still getting ready. …`, or `The on-device model isn’t available right now, …`.
- `ai-openrouter-confirm` choosing `OpenRouter` (or enabling while it is the provider) asks `Send file contents to OpenRouter?` with `Use OpenRouter` / `Cancel`; Cancel leaves it unchanged.
- `ai-try` `Try on a File…` opens a file panel (`Try`) and shows the name it would use; nothing is renamed.
- `ai-suggestions` `Suggest folders with AI` toggle (folder suggestions, name-only).
- `ai-openrouter` `Enable OpenRouter` (disabled until a feature needs it) reveals `OpenRouter setup` (key, Base URL, Model).

## How to get to it (user POV)

- Settings (menu bar extra ▸ `Settings…`, Intake menu ▸ `Settings…`, ⌘,, or clicking the Dock icon) ▸ sidebar `AI` (⌘5).

## Driving it with verify-intake

Preconditions:

- `$S/doctor.sh` exits 0 with no `screen is LOCKED` warning.
- Fresh preferences (run `$S/cleanup.sh` before `$S/launch.sh`).

- **Open the pane.** Run `$S/drive.sh extra "Settings…"`, then `$S/drive.sh press AI`, then `$S/drive.sh wait-window AI 10`. The Settings window title is `AI`.
- **Default template.** Run `$S/drive.sh value-of "Name template"`. The value is `{date} {type} {organization} {subject}` and the field is disabled (`enabled=false`); `$S/drive.sh wait-text "Tokens: {date} {type} {organization} {subject} {original}" 5` passes.
- **Enable on-device.** Run `$S/drive.sh press "Rename files from their contents"`. The provider picker and template field become enabled; if one of the availability warnings above appears (`$S/drive.sh wait-text "on-device model" 3` or `wait-text "Apple Intelligence" 3`), record it as the on-device availability result.
- **Turn it back off.** Press the same toggle again (or run `$S/cleanup.sh`).
- **Proof.** Run `$S/evidence.sh snapshot ai-pane`. `window-AI.png` and `ax-tree.txt` show the section with the default template.

## Gotchas

- Never choose `OpenRouter`, enable `Suggest folders with AI` with a key, or paste a key in the verification build: content goes off the Mac and costs money. The build reads Keychain service `app.intake.Intake.verify.openrouter`, so it never sees the installed app's key.
- `Try on a File…` opens a modal NSOpenPanel; only use it with a fixture inside the inbox and close the panel.
- Opening the pane refreshes on-device model availability; results differ per Mac (Apple Intelligence on/off, model downloaded).
- A user-edited template persists in `intake.contentAwareRename`; `cleanup.sh` resets it, so a fresh run always shows the default.
