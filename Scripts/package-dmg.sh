#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_RELEASE_DATA="${LEVELS_RELEASE_DATA:-/private/tmp/LevelsReleaseDerivedData}"
LEVELS_RELEASE_DIR="$PROJECT_ROOT/dist/Release"
LEVELS_STAGE="$(mktemp -d "$PROJECT_ROOT/dist/.levels-package.XXXXXX")"
trap 'rm -rf "$LEVELS_STAGE"' EXIT

xcodebuild -project "$PROJECT_ROOT/Levels.xcodeproj" -scheme Levels -clonedSourcePackagesDirPath "$PROJECT_ROOT/Vendor/SourcePackages" \
  -configuration Release -derivedDataPath "$LEVELS_RELEASE_DATA" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO build

mkdir -p "$LEVELS_RELEASE_DIR"
ditto "$LEVELS_RELEASE_DATA/Build/Products/Release/Levels.app" "$LEVELS_STAGE/Levels.app"
codesign --verify --deep --strict "$LEVELS_STAGE/Levels.app"
LEVELS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LEVELS_STAGE/Levels.app/Contents/Info.plist")"
LEVELS_DMG="$PROJECT_ROOT/dist/Levels-$LEVELS_VERSION-arm64.dmg"
LEVELS_ZIP="$LEVELS_RELEASE_DIR/Levels-$LEVELS_VERSION-arm64.zip"

ln -s /Applications "$LEVELS_STAGE/Applications"
cp "$PROJECT_ROOT/Resources/Install-ReadMe.txt" "$LEVELS_STAGE/Read Me.txt"
mkdir "$LEVELS_STAGE/Licenses"
cp "$PROJECT_ROOT/LICENSE" "$LEVELS_STAGE/Licenses/Fader-MIT-License.txt"
cp "$PROJECT_ROOT/UPSTREAM.md" "$LEVELS_STAGE/Licenses/Attribution.txt"
cp "$PROJECT_ROOT/Vendor/SourcePackages/artifacts/sparkle/Sparkle/LICENSE" "$LEVELS_STAGE/Licenses/Sparkle-License.txt"
cp "$LEVELS_STAGE/Levels.app/Contents/Resources/AppIcon.icns" "$LEVELS_STAGE/.VolumeIcon.icns"
SetFile -a C "$LEVELS_STAGE"

ditto "$LEVELS_STAGE/Levels.app" "$LEVELS_RELEASE_DIR/Levels.app"
codesign --verify --deep --strict "$LEVELS_RELEASE_DIR/Levels.app"
ditto -c -k --sequesterRsrc --keepParent "$LEVELS_RELEASE_DIR/Levels.app" "$LEVELS_ZIP"
hdiutil create -volname "Levels $LEVELS_VERSION" -srcfolder "$LEVELS_STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$LEVELS_DMG"
hdiutil verify "$LEVELS_DMG"
shasum -a 256 "$LEVELS_DMG" > "$LEVELS_DMG.sha256"

printf '\nRelease app: %s\nDMG: %s\nZIP: %s\n' "$LEVELS_RELEASE_DIR/Levels.app" "$LEVELS_DMG" "$LEVELS_ZIP"
