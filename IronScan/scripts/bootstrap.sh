#!/usr/bin/env bash
set -euo pipefail

# Resolve paths from the technical workspace even when invoked from the repository root.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

command -v uv >/dev/null || { echo "Install uv before bootstrapping." >&2; exit 1; }
command -v xcodebuild >/dev/null || { echo "Install Xcode before bootstrapping the iOS project." >&2; exit 1; }

uv sync --all-groups
python3 scripts/check_repository_layout.py
xcodebuild -resolvePackageDependencies -project Apps/IronScan/IronScan.xcodeproj -scheme IronScan -onlyUsePackageVersionsFromResolvedFile
echo "IronScan development environment is ready."
