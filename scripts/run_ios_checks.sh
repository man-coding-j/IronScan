#!/usr/bin/env bash
set -euo pipefail

IOS_DESTINATION="${IOS_DESTINATION:-}"
if [ -z "$IOS_DESTINATION" ] || [ "$IOS_DESTINATION" = "generic/platform=iOS Simulator" ]; then
  echo "Detecting available iPhone simulator..."
  device_line=$(xcrun simctl list devices available | grep -m1 -E 'iPhone' || true)
  if [ -z "$device_line" ]; then
    echo "No available iPhone simulators found."
    exit 1
  fi
  device_name=$(echo "$device_line" | sed -E 's/^[[:space:]]*([^\(]+) \([0-9A-Fa-f-]+\).*/\1/' | sed -E 's/[[:space:]]+$//')
  IOS_DESTINATION="platform=iOS Simulator,name=${device_name},OS=latest"
  echo "Using detected simulator: $device_name"
fi

DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/IronScanDerivedData}"
IOS_CHECK_ACTION="${IOS_CHECK_ACTION:-build}"

xcodebuild \
  -project Apps/IronScan/IronScan.xcodeproj \
  -scheme IronScan \
  -destination "$IOS_DESTINATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  "$IOS_CHECK_ACTION"
