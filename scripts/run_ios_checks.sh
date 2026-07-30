#!/usr/bin/env bash
set -euo pipefail

IOS_DESTINATION="${IOS_DESTINATION:-generic/platform=iOS Simulator}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-/tmp/IronScanDerivedData}"
IOS_CHECK_ACTION="${IOS_CHECK_ACTION:-build}"

xcodebuild \
  -project Apps/IronScan/IronScan.xcodeproj \
  -scheme IronScan \
 -destination 'platform=iOS Simulator,name=iPhone 15' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  "$IOS_CHECK_ACTION"
