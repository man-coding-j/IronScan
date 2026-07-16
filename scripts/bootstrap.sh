#!/usr/bin/env bash
set -euo pipefail

command -v uv >/dev/null || { echo "Install uv before bootstrapping." >&2; exit 1; }
command -v xcodegen >/dev/null || { echo "Install XcodeGen before generating the iOS project." >&2; exit 1; }

uv sync --all-groups
xcodegen generate --spec Apps/IronScan/project.yml --project Apps/IronScan
echo "IronScan development environment is ready."
