#!/usr/bin/env bash
# Tear down what launch.sh started; keep the evidence.
#   scripts/cleanup.sh               stop the recorded verification pid, empty the scratch inbox,
#                                    reset the verification build's preferences (Activity, Undo, settings)
#   scripts/cleanup.sh --purge-build also delete the verification build and axdrive
# Kills only the recorded PID after re-checking it is the verification build.
# Never touches the installed app, ~/Downloads, or .verify-intake/evidence/.
source "$(dirname "$0")/lib.sh"

if [[ -f "$RUN_ENV" ]]; then
  # shellcheck disable=SC1090
  source "$RUN_ENV"
  if is_our_pid "${PID:-}"; then
    log "stopping verification pid $PID"
    kill -TERM "$PID"
    for _ in $(seq 1 40); do kill -0 "$PID" 2>/dev/null || break; sleep 0.25; done
    kill -0 "$PID" 2>/dev/null && die "pid $PID did not exit after SIGTERM — not escalating; investigate"
  elif [[ -n "${PID:-}" ]] && kill -0 "$PID" 2>/dev/null; then
    log "recorded pid $PID is alive but is NOT the verification build — leaving it alone"
  fi
fi

stray=$(pid_for_bundle "$VERIFY_BUNDLE_ID")
[[ -z "$stray" ]] || die "another verification instance (pid $stray) is still running and was not recorded by this run — stop it yourself after checking 'ps -o comm= -p $stray'"

if [[ -d "$INBOX" ]]; then
  find "$INBOX" -mindepth 1 -delete
  log "emptied scratch inbox $INBOX"
fi
# Only the verification domain; the installed app's app.intake.Intake domain is never named here.
[[ "$VERIFY_BUNDLE_ID" == "app.intake.Intake.verify" ]] || die "unexpected verification bundle id $VERIFY_BUNDLE_ID"
defaults delete "$VERIFY_BUNDLE_ID" >/dev/null 2>&1 || true
log "reset preferences of $VERIFY_BUNDLE_ID"
rm -f "$RUN_ENV"

if [[ "${1:-}" == "--purge-build" ]]; then
  rm -rf "$DERIVED_DATA" "$VERIFY_ROOT/bin" "$VERIFY_ROOT/build.log" "$VERIFY_ROOT/axdrive-build.log"
  log "removed verification build"
fi

if [[ -n "${EVIDENCE:-}" ]]; then
  [[ -d "$EVIDENCE" ]] || die "evidence folder $EVIDENCE is gone after cleanup"
  log "evidence kept: $EVIDENCE ($(find "$EVIDENCE" -type f | wc -l | tr -d ' ') files)"
fi
log "cleanup done"
