#!/usr/bin/env bash
# Launch the verification build against the scratch watch folder and record its PID.
#   scripts/launch.sh            (run scripts/build.sh first)
# Ready when: the menu bar extra of OUR pid reads "Watching" / "New files in IntakeVerifyInbox"
# and the process holds an open descriptor on the scratch inbox.
# Writes .verify-intake/run/current.env (PID, RUN_ID, EVIDENCE) and creates the
# evidence folder .verify-intake/evidence/<RUN_ID>/ (kept by cleanup).
# Refuses to start a second verification instance; never touches the installed app.
source "$(dirname "$0")/lib.sh"

[[ -x "$APP_BIN" && -x "$AXDRIVE" ]] || die "no verification build — run scripts/build.sh"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" == "$VERIFY_BUNDLE_ID" ]] \
  || die "$APP is not the verification bundle id — rebuild with scripts/build.sh"

existing=$(pid_for_bundle "$VERIFY_BUNDLE_ID")
[[ -z "$existing" ]] || die "a verification instance is already running (pid $existing). Run scripts/doctor.sh, or scripts/cleanup.sh if it is yours."

installed=$(pid_for_bundle "$INSTALLED_BUNDLE_ID")
if [[ -n "$installed" ]]; then
  log "installed Intake is running as pid $installed ($INSTALLED_BUNDLE_ID) — leaving it alone; the verification build uses its own container"
fi

PROFILE_ARG=$(profile_arg_hex)
start_app() {
  open -n "$APP" --args \
    -intake.watchFolderProfiles "$PROFILE_ARG" \
    -intake.didShowMenuBarTip YES
  local pid="" i
  for i in $(seq 1 40); do
    pid=$(pid_for_bundle "$VERIFY_BUNDLE_ID")
    [[ -n "$pid" ]] && break
    sleep 0.25
  done
  [[ -n "$pid" ]] || die "verification build did not start"
  echo "$pid"
}

stop_pid() {
  local pid="$1" i
  is_our_pid "$pid" || die "refusing to stop pid $pid: not the verification build"
  kill -TERM "$pid"
  for i in $(seq 1 40); do kill -0 "$pid" 2>/dev/null || return 0; sleep 0.25; done
  die "pid $pid did not exit after SIGTERM"
}

# First launch only: macOS creates the sandbox container when the app starts,
# and the inbox must live inside it. Start once (the profile points at the
# not-yet-existing inbox, so nothing is watched), let the container appear,
# stop that pid, then create the inbox.
if [[ ! -d "$INBOX" ]]; then
  if [[ ! -d "$CONTAINER/Data" ]]; then
    log "bootstrapping sandbox container $CONTAINER"
    boot=$(start_app)
    for _ in $(seq 1 40); do [[ -d "$CONTAINER/Data/Library" ]] && break; sleep 0.25; done
    stop_pid "$boot"
  fi
  mkdir -p "$INBOX"
fi

RUN_ID="$(date +%Y%m%d-%H%M%S)"
EVIDENCE="$EVIDENCE_ROOT/$RUN_ID"
mkdir -p "$EVIDENCE" "$(dirname "$RUN_ENV")"
PID=$(start_app)
cat > "$RUN_ENV" <<ENV
PID=$PID
RUN_ID=$RUN_ID
EVIDENCE=$EVIDENCE
ENV
{
  echo "run_id: $RUN_ID"
  echo "pid: $PID"
  echo "app: $APP"
  echo "bundle_id: $VERIFY_BUNDLE_ID"
  echo "git: $(git -C "$REPO_ROOT" rev-parse HEAD) $(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"
  echo "inbox: $INBOX"
  echo "installed_app_pid_at_launch: ${installed:-none}"
  echo "launched_at: $(date '+%Y-%m-%d %H:%M:%S %Z')"
} > "$EVIDENCE/run.txt"

# Ready check: our pid's menu bar extra shows the scratch inbox, and the
# watcher has the inbox open.
for _ in $(seq 1 40); do
  if "$AXDRIVE" "$PID" extra-items 2>/dev/null | grep -q "New files in $INBOX_NAME" \
     && lsof -p "$PID" 2>/dev/null | grep -q "$INBOX"; then
    log "ready: pid $PID watching $INBOX"
    log "evidence → $EVIDENCE"
    exit 0
  fi
  sleep 0.5
done
die "pid $PID started but never reported watching $INBOX_NAME — run scripts/doctor.sh, then scripts/cleanup.sh"
