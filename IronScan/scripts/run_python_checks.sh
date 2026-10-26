#!/usr/bin/env bash
set -euo pipefail

# Resolve paths from the technical workspace even when invoked from the repository root.
cd "$(dirname "${BASH_SOURCE[0]}")/.."

uv run ruff check .
uv run mypy .
uv run pytest
