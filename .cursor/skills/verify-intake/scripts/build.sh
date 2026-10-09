#!/usr/bin/env bash
# Build the isolated verification copy of Intake plus the axdrive helper.
#   scripts/build.sh
# Output: .verify-intake/DerivedData/Build/Products/Debug/Intake.app
#   bundle id app.intake.Intake.verify, display name "Intake Verify",
#   Debug config, signed to run locally (same sandbox entitlements as shipping).
# Never installs anything: does not touch ~/Applications/Intake.app and never
# calls scripts/install-local.sh.
source "$(dirname "$0")/lib.sh"

mkdir -p "$VERIFY_ROOT/bin" "$VERIFY_ROOT/run" "$EVIDENCE_ROOT"
log "building Debug → $DERIVED_DATA (log: $VERIFY_ROOT/build.log)"
if ! xcodebuild \
    -project "$REPO_ROOT/Intake/Intake.xcodeproj" \
    -scheme Intake \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA" \
    PRODUCT_BUNDLE_IDENTIFIER="$VERIFY_BUNDLE_ID" \
    "INFOPLIST_KEY_CFBundleDisplayName=$VERIFY_DISPLAY_NAME" \
    build > "$VERIFY_ROOT/build.log" 2>&1; then
  grep -E 'error:' "$VERIFY_ROOT/build.log" | head -20 >&2 || true
  die "xcodebuild failed — see $VERIFY_ROOT/build.log"
fi

id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")
[[ "$id" == "$VERIFY_BUNDLE_ID" ]] || die "built bundle id is $id, expected $VERIFY_BUNDLE_ID — refusing to continue"
ver=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist" | paste -sd' ' -)
log "built $APP ($id, version $ver, git $(git -C "$REPO_ROOT" rev-parse --short HEAD))"

log "compiling axdrive → $AXDRIVE"
swiftc -O -o "$AXDRIVE" "$SKILL_DIR/scripts/axdrive.swift" 2> "$VERIFY_ROOT/axdrive-build.log" \
  || { cat "$VERIFY_ROOT/axdrive-build.log" >&2; die "axdrive failed to compile"; }
log "build ok"
