#!/usr/bin/env bash
# Read-only health check: is the recorded instance the verification build, and is it safe to drive?
#   scripts/doctor.sh
# Exit 0 = drive it. Exit 1 = do not drive (each FAIL line says why).
# Never starts, stops, or clicks anything.
source "$(dirname "$0")/lib.sh"
set +e

fails=0
ok()   { printf 'ok    %s\n' "$*"; }
warn() { printf 'WARN  %s\n' "$*"; }
bad()  { printf 'FAIL  %s\n' "$*"; fails=$((fails + 1)); }

installed=$(pid_for_bundle "$INSTALLED_BUNDLE_ID")
if [[ -n "$installed" ]]; then
  ok "installed Intake running as pid $installed ($(ps -o comm= -p "$installed")) — not ours, never driven"
else
  ok "installed Intake not running"
fi

if [[ ! -f "$RUN_ENV" ]]; then
  bad "no recorded run ($RUN_ENV) — run scripts/launch.sh"
else
  # shellcheck disable=SC1090
  source "$RUN_ENV"
  if is_our_pid "${PID:-}"; then
    ok "pid $PID is the verification build ($VERIFY_BUNDLE_ID, $APP_BIN)"
  else
    bad "recorded pid ${PID:-?} is not a live verification build — relaunch (scripts/cleanup.sh; scripts/launch.sh)"
  fi
  [[ -n "$installed" && "${PID:-}" == "$installed" ]] && bad "recorded pid is the installed app — never drive it"
  [[ -d "${EVIDENCE:-/nonexistent}" ]] && ok "evidence folder $EVIDENCE" || bad "evidence folder missing (${EVIDENCE:-unset})"
fi

if [[ -x "$APP_BIN" ]]; then
  info=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" | paste -sd' ' -)
  ok "build: $info, built $(stat -f '%Sm' "$APP_BIN"), checkout $(git -C "$REPO_ROOT" rev-parse --short HEAD)"
  [[ "$APP_BIN" -nt "$REPO_ROOT/.git/HEAD" ]] || warn "build is older than the last checkout change — rebuild with scripts/build.sh if the code changed"
else
  bad "no verification build at $APP — run scripts/build.sh"
fi

[[ -d "$INBOX" ]] && ok "scratch inbox $INBOX" || bad "scratch inbox missing ($INBOX)"

if [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
  if lsof -p "$PID" 2>/dev/null | grep -q "$INBOX"; then ok "watcher has the scratch inbox open"; else bad "pid $PID is not watching $INBOX"; fi
  if lsof -p "$PID" 2>/dev/null | awk '{print $NF}' | grep -qx "$HOME/Downloads"; then bad "pid $PID has ~/Downloads open — stop and clean up now"; else ok "not watching ~/Downloads"; fi
  args=$(ps -o args= -p "$PID")
  [[ "$args" == *"-intake.watchFolderProfiles"* ]] && ok "launched with the scratch watch-folder profile argument" || bad "launched without -intake.watchFolderProfiles"
  if status=$("$AXDRIVE" "$PID" extra-items 2>&1); then
    ok "menu bar extra (pid-bound): $(echo "$status" | sed -n '2,3p' | sed 's/^ *\[//; s/\].*$//' | paste -sd'|' -)"
  else
    bad "cannot read the menu bar extra of pid $PID: $status"
  fi
fi

if [[ -x "$AXDRIVE" ]]; then
  "$AXDRIVE" "$$" windows >/dev/null 2>&1; rc=$?
  if [[ $rc -ne 3 ]]; then ok "Accessibility granted to the process running these commands"; else bad "Accessibility not granted to the app running this shell (System Settings › Privacy & Security › Accessibility)"; fi
fi

locked=$(ioreg -n Root -d1 -a | plutil -extract IOConsoleUsers.0.CGSSessionScreenIsLocked raw -o - - 2>/dev/null || echo unknown)
if [[ "$locked" == "true" ]]; then
  warn "the Mac's screen is LOCKED: window-level Accessibility (Settings/Activity contents) and window screenshots are unavailable. Menu bar extra + filesystem + stored-Activity evidence still work."
else
  ok "screen unlocked (screen lock state: $locked)"
fi

if (( fails > 0 )); then echo "doctor: $fails problem(s) — do not drive"; exit 1; fi
echo "doctor: healthy"
