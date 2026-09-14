#!/usr/bin/env bash
# Copy Intake.app into ~/Applications so Spotlight / Launchpad / `open -b` resolve a
# stable bundle (not a DerivedData Debug path that vanishes between builds).
set -euo pipefail

DEST_DIR="${HOME}/Applications"
DEST="${DEST_DIR}/Intake.app"
BUNDLE_ID="app.intake.Intake"
LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

resolve_source() {
  if [[ $# -ge 1 && -n "${1:-}" ]]; then
    echo "$1"
    return
  fi
  local found
  found="$(
    find "${HOME}/Library/Developer/Xcode/DerivedData" \
      -path '*/Build/Products/Debug/Intake.app' \
      -type d 2>/dev/null \
      | xargs -I{} stat -f '%m %N' {} 2>/dev/null \
      | sort -nr \
      | head -1 \
      | cut -d' ' -f2-
  )"
  if [[ -z "${found}" ]]; then
    echo "error: no Intake.app given and none found under DerivedData Debug" >&2
    echo "usage: $0 /path/to/Intake.app" >&2
    exit 1
  fi
  echo "${found}"
}

unregister_other_intake_apps() {
  # Drop Launch Services registrations for other Intake.app paths so Spotlight
  # and `open -b` stick to ~/Applications (DerivedData wins otherwise).
  if [[ ! -x "${LSREGISTER}" ]]; then
    return
  fi
  local path
  while IFS= read -r path; do
    [[ -z "${path}" ]] && continue
    # Never unregister the destination we are about to (re)register.
    if [[ "${path}" == "${DEST}" ]]; then
      continue
    fi
    echo "Unregistering ${path}"
    "${LSREGISTER}" -u "${path}" 2>/dev/null || true
  done < <(
    # Known build products
    find "${HOME}/Library/Developer/Xcode/DerivedData" \
      -path '*/Build/Products/*/Intake.app' -type d 2>/dev/null || true
    # Any other registered copies under home (best-effort; ignore failures)
    mdfind "kMDItemCFBundleIdentifier == '${BUNDLE_ID}'" 2>/dev/null || true
  )
}

SRC="$(resolve_source "${1:-}")"
if [[ ! -d "${SRC}" ]]; then
  echo "error: not an app bundle: ${SRC}" >&2
  exit 1
fi

unregister_other_intake_apps

mkdir -p "${DEST_DIR}"
rm -rf "${DEST}"
ditto "${SRC}" "${DEST}"
xattr -dr com.apple.quarantine "${DEST}" 2>/dev/null || true

if [[ -x "${LSREGISTER}" ]]; then
  "${LSREGISTER}" -f "${DEST}"
fi

echo "Installed ${DEST}"
echo "Launch: open -b ${BUNDLE_ID}"
echo "     or open \"${DEST}\""
