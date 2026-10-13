#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_DERIVED_DATA="${LEVELS_DERIVED_DATA:-/private/tmp/LevelsDerivedData}"
xcodebuild -project "$PROJECT_ROOT/Levels.xcodeproj" -scheme Levels -clonedSourcePackagesDirPath "$PROJECT_ROOT/Vendor/SourcePackages" \
  -configuration Debug -derivedDataPath "$LEVELS_DERIVED_DATA" build
mkdir -p "$PROJECT_ROOT/dist"
ditto "$LEVELS_DERIVED_DATA/Build/Products/Debug/Levels.app" "$PROJECT_ROOT/dist/Levels.app"
codesign --verify --deep --strict "$PROJECT_ROOT/dist/Levels.app"
printf '\nBuilt: %s\n' "$PROJECT_ROOT/dist/Levels.app"
