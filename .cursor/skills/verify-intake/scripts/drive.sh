#!/usr/bin/env bash
# Drive the recorded verification instance — and only it. Every command first
# re-checks that the recorded PID is still the verification build.
#
#   scripts/drive.sh status                      menu bar extra title + items (status, Pause/Resume, recent Activity rows)
#   scripts/drive.sh extra <item title>          choose a menu bar extra item, e.g. "Open Activity", "Settings…", "Pause Organizing"
#   scripts/drive.sh menu <menu> <item>          choose a main-menu item, e.g. menu Intake "Settings…" / menu Intake Activity
#   scripts/drive.sh press <label>               press a button / sidebar row / menu item in an open window, e.g. press AI
#   scripts/drive.sh windows                     AX windows (title, frame, CG window id) — empty while the Mac is locked
#   scripts/drive.sh cgwindows [all]             on-screen WindowServer windows of the pid (works while locked; all = include hidden)
#   scripts/drive.sh tree [depth]                AX tree of every window
#   scripts/drive.sh wait-window <title> [secs]  e.g. wait-window AI 10
#   scripts/drive.sh wait-text <text> [secs]     e.g. wait-text "Quarterly Report Q1.pdf" 10
#   scripts/drive.sh value-of <label>            text field value, e.g. value-of "Name template"
#   scripts/drive.sh drop <file> [as-name]       copy a file into the scratch watch folder, the way a finished download lands
#   scripts/drive.sh wait-file <name> [secs]     wait until <name> exists in the scratch watch folder root
#   scripts/drive.sh inbox                       list the scratch watch folder (recursive)
#   scripts/drive.sh activity                    the stored Activity log of the verification build, as JSON
source "$(dirname "$0")/lib.sh"
require_our_pid

cmd="${1:-}"; shift || true
case "$cmd" in
  status)     exec "$AXDRIVE" "$PID" extra-items ;;
  extra)      exec "$AXDRIVE" "$PID" extra-press "$1" ;;
  menu)       exec "$AXDRIVE" "$PID" menu-press "$1" "$2" ;;
  press|wait-window|wait-text|value-of)
              exec "$AXDRIVE" "$PID" "$cmd" "$@" ;;
  windows|cgwindows|tree)
              exec "$AXDRIVE" "$PID" "$cmd" "$@" ;;
  drop)
    src="$1"; name="${2:-$(basename "$1")}"
    [[ -f "$src" ]] || die "no such file: $src"
    [[ "$name" != */* ]] || die "as-name must be a bare file name"
    # Write under a dot-name first, then rename into place: the watcher ignores
    # nothing it can see half-written, and the final name appears complete.
    cp "$src" "$INBOX/.verify-drop-$$"
    mv "$INBOX/.verify-drop-$$" "$INBOX/$name"
    log "dropped $name into $INBOX" ;;
  wait-file)
    name="$1"; secs="${2:-15}"
    for _ in $(seq 1 $((secs * 4))); do
      [[ -e "$INBOX/$name" ]] && { log "present: $name"; exit 0; }
      sleep 0.25
    done
    die "timed out after ${secs}s waiting for $name in $INBOX" ;;
  inbox)
    (cd "$INBOX" && find . -mindepth 1 -print0 | sort -z | xargs -0 ls -ld) ;;
  activity)
    defaults export "$VERIFY_BUNDLE_ID" - | python3 -c '
import json, plistlib, sys
d = plistlib.loads(sys.stdin.buffer.read())
raw = d.get("intake.activity")
print(json.dumps(json.loads(raw) if raw else [], indent=2, ensure_ascii=False))' ;;
  *) sed -n '2,20p' "$0"; exit 2 ;;
esac
