#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-"$ROOT_DIR/.derivedData/UnitTests"}"
BUILD_DIR="$DERIVED_DATA_PATH/Build/Products"
CONFIGURATION="${CONFIGURATION:-Debug}"

cd "$ROOT_DIR"

xcodebuild build \
  -project Pods/Pods.xcodeproj \
  -scheme GRDB.swift \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  BUILD_DIR="$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO

xcodebuild build \
  -project Pods/Pods.xcodeproj \
  -scheme Pods-musetype \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  BUILD_DIR="$BUILD_DIR" \
  CODE_SIGNING_ALLOWED=NO

xcodebuild test \
  -project fastv.xcodeproj \
  -scheme musetype \
  -configuration "$CONFIGURATION" \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO
