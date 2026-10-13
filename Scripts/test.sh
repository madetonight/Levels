#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_DERIVED_DATA="${LEVELS_DERIVED_DATA:-/private/tmp/LevelsDerivedData}"
xcodebuild -project "$PROJECT_ROOT/Levels.xcodeproj" -scheme Levels -clonedSourcePackagesDirPath "$PROJECT_ROOT/Vendor/SourcePackages" \
  -configuration Debug -derivedDataPath "$LEVELS_DERIVED_DATA" test
