#!/usr/bin/env bash
# Capture proof into the run's evidence folder (.verify-intake/evidence/<RUN_ID>/), which cleanup keeps.
#
#   scripts/evidence.sh snapshot <label>   capture a numbered snapshot: menu bar extra, scratch inbox listing,
#                                          stored Activity JSON, window lists, AX tree, and a PNG of every
#                                          window the verification pid owns (never the whole screen)
#   scripts/evidence.sh note "<text>"      append a timestamped line to notes.txt (the action you just took, the command, the result)
#   scripts/evidence.sh path               print the evidence folder
source "$(dirname "$0")/lib.sh"

cmd="${1:-}"; shift || true
case "$cmd" in
  path) load_run; echo "$EVIDENCE"; exit 0 ;;
  note)
    load_run
    printf '%s  %s\n' "$(date '+%H:%M:%S')" "$*" >> "$EVIDENCE/notes.txt"
    log "noted"; exit 0 ;;
  snapshot) ;;
  *) sed -n '2,8p' "$0"; exit 2 ;;
esac

label="${1:?usage: evidence.sh snapshot <label>}"
require_our_pid
n=$(find "$EVIDENCE" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
dir="$EVIDENCE/$(printf '%02d' $((n + 1)))-$label"
mkdir -p "$dir"
D="$SKILL_DIR/scripts/drive.sh"

date '+%Y-%m-%d %H:%M:%S %Z' > "$dir/captured_at.txt"
"$D" status    > "$dir/menu-bar-extra.txt" 2>&1 || true
"$D" inbox     > "$dir/inbox.txt"          2>&1 || true
"$D" activity  > "$dir/activity.json"      2>&1 || true
"$D" cgwindows > "$dir/cgwindows.txt"      2>&1 || true
"$D" windows   > "$dir/ax-windows.txt"     2>&1 || true
"$D" tree 30   > "$dir/ax-tree.txt"        2>&1 || true

shots=0
while IFS='|' read -r wid title _; do
  wid=$(echo "$wid" | tr -d ' '); title=$(echo "$title" | sed 's/^ *//; s/ *$//')
  [[ -n "$wid" && -n "$title" ]] || continue
  out="$dir/window-$(echo "$title" | tr -c 'A-Za-z0-9' '-' | sed 's/-*$//').png"
  if err=$(screencapture -x -o -l"$wid" "$out" 2>&1) && [[ -s "$out" ]]; then
    shots=$((shots + 1))
  else
    echo "window $wid ($title): screencapture failed: ${err:-no image written}" >> "$dir/screenshot-errors.txt"
  fi
done < "$dir/cgwindows.txt"

log "snapshot → $dir ($shots window screenshot(s))"
[[ -f "$dir/screenshot-errors.txt" ]] && { log "screenshot problems:"; cat "$dir/screenshot-errors.txt"; }
exit 0
