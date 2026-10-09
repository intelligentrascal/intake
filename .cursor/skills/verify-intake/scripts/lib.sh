# shellcheck shell=bash
# Shared paths and guards for the verify-intake helpers. Sourced, never run.
# Every helper binds to ONE process: the PID launch.sh recorded for the
# verification build. Nothing here looks processes up by name.

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_ROOT="$(cd "$SKILL_DIR/../../.." && pwd)"

# Everything the skill creates lives under one git-ignored directory.
VERIFY_ROOT="${INTAKE_VERIFY_ROOT:-$REPO_ROOT/.verify-intake}"
DERIVED_DATA="$VERIFY_ROOT/DerivedData"
APP="$DERIVED_DATA/Build/Products/Debug/Intake.app"
APP_BIN="$APP/Contents/MacOS/Intake"
AXDRIVE="$VERIFY_ROOT/bin/axdrive"
RUN_ENV="$VERIFY_ROOT/run/current.env"
EVIDENCE_ROOT="$VERIFY_ROOT/evidence"

# Verification identity. A distinct bundle id gives the build its own sandbox
# container, preferences, Activity, Undo stack, Launch Services entry and
# (with OpenRouterKeychain deriving its service from the bundle id) its own
# Keychain item, so it never shares state with the installed app.
VERIFY_BUNDLE_ID="app.intake.Intake.verify"
VERIFY_DISPLAY_NAME="Intake Verify"
INSTALLED_BUNDLE_ID="app.intake.Intake"

CONTAINER="$HOME/Library/Containers/$VERIFY_BUNDLE_ID"
# Scratch watch folder inside the verification container: the sandboxed build
# can always read/write its own container, so no folder picker or
# security-scoped bookmark is needed, and it is nowhere near ~/Downloads.
INBOX="$CONTAINER/Data/IntakeVerifyInbox"
INBOX_NAME="IntakeVerifyInbox"

log() { printf '[verify-intake] %s\n' "$*"; }
die() { printf '[verify-intake] ERROR: %s\n' "$*" >&2; exit 1; }

# pid of a running app by bundle id, or empty. lsappinfo matches the exact
# bundle id, so the installed app and the verification build never collide.
pid_for_bundle() {
  lsappinfo info -only pid -app "$1" 2>/dev/null | sed -n 's/.*"pid"=\([0-9][0-9]*\).*/\1/p' | head -1
}

# The watch-folder profile handed to the app as a launch argument. Values in
# the NSArgumentDomain win over stored preferences, so the build never falls
# back to its default watch folder (~/Downloads), even on its first launch.
profile_arg_hex() {
  local json
  json=$(printf '[{"automaticOrganizing":true,"displayName":"%s","id":"primary","isPaused":false,"organizingWait":7200,"path":"%s","renameWhenDownloadFinishes":true}]' "$INBOX_NAME" "$INBOX")
  printf '<%s>' "$(printf '%s' "$json" | xxd -p | tr -d '\n')"
}

# Load the recorded run (PID, RUN_ID, EVIDENCE). Fails when nothing was launched.
load_run() {
  [[ -f "$RUN_ENV" ]] || die "no recorded run at $RUN_ENV — run scripts/launch.sh first"
  # shellcheck disable=SC1090
  source "$RUN_ENV"
  [[ -n "${PID:-}" && -n "${RUN_ID:-}" && -n "${EVIDENCE:-}" ]] || die "incomplete run file $RUN_ENV"
}

# True when $1 is a live process running the verification build's binary AND
# Launch Services reports it under the verification bundle id.
is_our_pid() {
  local pid="$1" exe
  [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null || return 1
  exe=$(ps -o comm= -p "$pid" 2>/dev/null || true)
  [[ "$(cd "$(dirname "$exe")" 2>/dev/null && pwd -P)/$(basename "$exe")" == "$(cd "$(dirname "$APP_BIN")" && pwd -P)/Intake" ]] || return 1
  [[ "$(pid_for_bundle "$VERIFY_BUNDLE_ID")" == "$pid" ]] || return 1
}

require_our_pid() {
  load_run
  is_our_pid "$PID" || die "recorded PID $PID is not the running verification build ($APP_BIN, $VERIFY_BUNDLE_ID). Run scripts/doctor.sh; relaunch with scripts/launch.sh."
}
