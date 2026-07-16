#!/usr/bin/env bash
set -euo pipefail

xcodegen generate --spec Apps/IronScan/project.yml --project Apps/IronScan
xcodebuild \
  -workspace IronScan.xcworkspace \
  -scheme IronScan \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  test
