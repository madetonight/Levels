#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_RENDER_DIR="${LEVELS_RENDER_DIR:-/private/tmp/LevelsNativeRender}"
LEVELS_RENDER_BUNDLE="$LEVELS_RENDER_DIR/LevelsRender.app"
mkdir -p "$LEVELS_RENDER_BUNDLE/Contents/MacOS" "$LEVELS_RENDER_BUNDLE/Contents/Resources"
cp "$PROJECT_ROOT/dist/Levels.app/Contents/Resources/Assets.car" "$LEVELS_RENDER_BUNDLE/Contents/Resources/Assets.car"
mkdir -p "$LEVELS_RENDER_BUNDLE/Contents/Frameworks"
ditto "$PROJECT_ROOT/dist/Levels.app/Contents/Frameworks/Sparkle.framework" "$LEVELS_RENDER_BUNDLE/Contents/Frameworks/Sparkle.framework"
cat > "$LEVELS_RENDER_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.joseluna.levels-render</string>
<key>CFBundleExecutable</key><string>LevelsRender</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
xcrun swiftc -swift-version 6 -D RENDER_SHOTS -parse-as-library \
  -sdk "$(xcrun --show-sdk-path)" -target arm64-apple-macos15.0 \
  "$PROJECT_ROOT"/Sources/Audio/*.swift "$PROJECT_ROOT/Sources/MixerView.swift" \
  "$PROJECT_ROOT/Sources/AppUpdateController.swift" "$PROJECT_ROOT/Sources/UpdateConfiguration.swift" \
  -F "$PROJECT_ROOT/Vendor/SourcePackages/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64" -framework Sparkle \
  -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  "$PROJECT_ROOT/Scripts/RenderHarness.swift" -o "$LEVELS_RENDER_BUNDLE/Contents/MacOS/LevelsRender"
"$LEVELS_RENDER_BUNDLE/Contents/MacOS/LevelsRender" "${1:-$PROJECT_ROOT/dist/appearance}"
