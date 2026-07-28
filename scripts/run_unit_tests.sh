#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/.derivedData/UnitTests"}"
CONFIGURATION="${CONFIGURATION:-Debug}"

cd "$ROOT_DIR"

xcodebuild test \
  -project fastv.xcodeproj \
  -scheme musetype \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO
