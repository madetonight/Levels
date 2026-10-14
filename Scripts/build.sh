#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_DERIVED_DATA="${LEVELS_DERIVED_DATA:-/private/tmp/LevelsDerivedData}"
LEVELS_CONFIGURATION="${LEVELS_CONFIGURATION:-Debug}"
# Owner-approved certificate selection stays local; cloned workspaces can
# supply their own identity. No private key or certificate is stored here.
if [ -z "${LEVELS_SIGNING_IDENTITY:-}" ] && [ -f "$PROJECT_ROOT/.release-signing" ]; then
  LEVELS_SIGNING_IDENTITY="$(cat "$PROJECT_ROOT/.release-signing")"
fi
LEVELS_BUILD_FLAGS=()
case "$LEVELS_CONFIGURATION" in
  Debug) ;;
  Release) LEVELS_BUILD_FLAGS=("CODE_SIGN_IDENTITY=${LEVELS_SIGNING_IDENTITY:--}" ENABLE_HARDENED_RUNTIME=NO) ;;
  *) echo 'LEVELS_CONFIGURATION must be Debug or Release.' >&2; exit 2 ;;
esac
xcodebuild -project "$PROJECT_ROOT/Levels.xcodeproj" -scheme Levels -clonedSourcePackagesDirPath "$PROJECT_ROOT/Vendor/SourcePackages" \
  -configuration "$LEVELS_CONFIGURATION" -derivedDataPath "$LEVELS_DERIVED_DATA" "${LEVELS_BUILD_FLAGS[@]}" build
mkdir -p "$PROJECT_ROOT/dist"
ditto "$LEVELS_DERIVED_DATA/Build/Products/$LEVELS_CONFIGURATION/Levels.app" "$PROJECT_ROOT/dist/Levels.app"
codesign --verify --deep --strict "$PROJECT_ROOT/dist/Levels.app"
printf '\nBuilt: %s\n' "$PROJECT_ROOT/dist/Levels.app"
