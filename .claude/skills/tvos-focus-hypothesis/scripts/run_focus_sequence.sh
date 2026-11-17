#!/usr/bin/env bash
# Run a remote sequence through XCUITest, then copy the app's [FOCUS] log.
#
# Usage: run_focus_sequence.sh <out.log> [hypothesis] [sequence]
#   hypothesis: value for -FocusHypothesis (e.g. H20, or "" for baseline)
#   sequence:   custom steps (see FocusProblemUITests/FocusSequenceUITests.swift); default = standard protocol
# Env:
#   SIM_UDID   simulator to use (default: the Apple TV 4K 4th gen tvOS 27.2 simulator used so far)
#   DEVICE_ID  run on a real Apple TV instead (paired with Xcode, signing set up). The log is copied
#              with `xcrun devicectl`. Not tried yet on this project.
set -euo pipefail

OUT="${1:?usage: run_focus_sequence.sh <out.log> [hypothesis] [sequence]}"
HYP="${2:-}"
UDID="${SIM_UDID:-A6D2C8DB-078A-4B23-9306-2DE168DF9CDE}"
REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
BUNDLE_ID="FocusProblem.FocusProblem"

if [[ -n "${3:-}" ]]; then
  SEQ="$3"
else
  # Standard protocol: reach S2, 5× (Down into S3, wait, Up), go to the bottom, 5× (Up into S3, wait, Down).
  SEQ="down*3 wait1"
  for _ in 1 2 3 4 5; do SEQ+=" down wait2 up wait1"; done
  SEQ+=" down*4 wait1"
  for _ in 1 2 3 4 5; do SEQ+=" up wait2 down wait1"; done
fi

if [[ -n "${DEVICE_ID:-}" ]]; then
  DESTINATION="platform=tvOS,id=$DEVICE_ID"
  EXTRA=(-allowProvisioningUpdates)
else
  DESTINATION="platform=tvOS Simulator,id=$UDID"
  EXTRA=()
fi

XCB_LOG="${OUT%.log}.xcodebuild.txt"
cd "$REPO"
TEST_RUNNER_FOCUS_SEQUENCE="$SEQ" TEST_RUNNER_FOCUS_HYPOTHESIS="$HYP" \
  xcodebuild test -project FocusProblem.xcodeproj -scheme FocusUITests \
  -destination "$DESTINATION" ${EXTRA[@]+"${EXTRA[@]}"} \
  -only-testing:FocusProblemUITests/FocusSequenceUITests/testRunSequence > "$XCB_LOG" 2>&1 || {
    echo "xcodebuild test failed, see $XCB_LOG" >&2
    grep -E "error:|failed" "$XCB_LOG" | head -20 >&2
    exit 1
  }

if [[ -n "${DEVICE_ID:-}" ]]; then
  xcrun devicectl device copy from --device "$DEVICE_ID" \
    --domain-type appDataContainer --domain-identifier "$BUNDLE_ID" \
    --source Library/Caches/focus-log.txt --destination "$OUT" > /dev/null
else
  CONTAINER="$(xcrun simctl get_app_container "$UDID" "$BUNDLE_ID" data)"
  cp "$CONTAINER/Library/Caches/focus-log.txt" "$OUT"
fi
echo "OK: $(wc -l < "$OUT") [FOCUS] lines → $OUT (hypothesis='${HYP}')"
