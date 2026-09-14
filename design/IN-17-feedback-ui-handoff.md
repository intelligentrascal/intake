# IN-17 · Intake Feedback UI (v1.1.0)
**Product:** Intake · **Auth:** Option D — prefilled GitHub new-issue in browser (no server, no PAT)  
**From:** Designer → Firstmate → Intake Dev · **No Designer app code**  
**Mocks:** `assets/in-17-feedback/`

---

## IA
- Settings sidebar: add **Feedback** (SF Symbol `bubble.left.and.bubble.right` or `envelope`) — place before **About** (after AI is fine).
- Menu bar: **Send Feedback…** (opens Settings → Feedback).
- About: link **Send Feedback…** → same pane.

---

## Settings → Feedback (grouped Form)

| Section | Control | Copy (EN) |
|---|---|---|
| Type | `Picker` segmented or menu | Labels: `Feature` · `Bug` · `Urgent` |
| | Footer | `Urgent is for broken organizing or data-loss risk — not general questions.` |
| Title | `TextField` required | Placeholder: `Short summary` |
| Details | `TextEditor` required | Placeholder: `What happened, what you expected, steps if it’s a bug` |
| Email | `TextField` optional | Label: `Email (optional)` · Footer: `Only if you want a reply. Not required to open a GitHub issue.` |
| Diagnostics | `Toggle` default **On** for Bug/Urgent, **Off** for Feature (or On always — prefer On for Bug/Urgent) | Label: `Include diagnostics` · Footer: `App version, macOS version, and recent Activity lines. Stays on this Mac until you submit; pasted into the issue body. No file contents.` |
| Screenshots | Thumbnails + actions | See § Screenshots |
| Submit | `.borderedProminent` | `Open GitHub Issue` (prefer over vague “Submit” — sets expectation) |

**Validation:** Title + Details non-empty before open. Empty → inline or disable button.

---

## Screenshots (no API upload)

### In-app
- **Add…** → `NSOpenPanel` images (png/jpeg/heic)
- **Paste** → read image from pasteboard
- Per thumb: **Remove**
- Cap e.g. 3–5 images; show count

### On Submit (Option D)
1. Build GitHub `issues/new` URL with query `title` + `body` (type, details, email if any, diagnostics block, Intake/macOS versions).
2. If screenshots present: copy image(s) to **NSPasteboard** (multi-image if supported; else first image + note in body).
3. `NSWorkspace.shared.open(url)`.
4. Show native alert or banner:  
   **Title:** `Almost done`  
   **Body:** `GitHub opened with your text. Paste screenshots into the issue with ⌘V (they’re on your clipboard).`  
   **Buttons:** `OK` · optional `Don’t show again`

### Issue body template (sketch)
```
### Type
Bug

### Details
…

### Contact
email or “none”

### Diagnostics
Intake x.y (build) · macOS … 
(recent activity lines if opted in)

### Screenshots
Paste from clipboard (⌘V) — Intake copied N image(s).
```

---

## Menu bar / About
- After Settings…: **Send Feedback…** → `openSettings(pane: .feedback)`
- About section Links: `Send Feedback…` same action

---

## A11y
- Labels on all fields; screenshots list accessible names `Screenshot 1 of N`
- Submit announces “Opens in browser”
- Reduce Motion: no decorative animation on submit

---

## Avoid
Web/shadcn forms, embedded WKWebView GitHub login, storing PAT, uploading to third-party, implying screenshots auto-attach on GitHub without paste.

## Accept
- [ ] Feedback pane with type/title/details/email/diagnostics/screenshots
- [ ] Open GitHub Issue prefills; pasteboard path documented in UI
- [ ] Menu bar + About entry points
- [ ] Native Form only

## Mocks
- `settings-feedback-pane.png` — Settings Feedback Form
- `pasteboard-github-flow.png` — clipboard → GitHub paste instruction
