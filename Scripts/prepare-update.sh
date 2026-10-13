#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPARKLE_TOOLS="$PROJECT_ROOT/Vendor/SourcePackages/artifacts/sparkle/Sparkle/bin"
LEVELS_DOWNLOAD_PREFIX="${1:-}"
python3 - "$LEVELS_DOWNLOAD_PREFIX" <<'PY'
import sys
from urllib.parse import urlsplit
url=urlsplit(sys.argv[1])
if url.scheme!='https' or not url.hostname or url.username or url.password or url.fragment or not sys.argv[1].endswith('/'):
    raise SystemExit('Pass the public HTTPS release-download directory URL, ending in /. No credentials are allowed.')
PY
LEVELS_RELEASE_APP="$PROJECT_ROOT/dist/Release/Levels.app"
codesign --verify --deep --strict "$LEVELS_RELEASE_APP"
LEVELS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LEVELS_RELEASE_APP/Contents/Info.plist")"
LEVELS_UPDATE_DIR="$PROJECT_ROOT/dist/Updates/$LEVELS_VERSION"
mkdir -p "$LEVELS_UPDATE_DIR"
LEVELS_ARCHIVE="$LEVELS_UPDATE_DIR/Levels-$LEVELS_VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$LEVELS_RELEASE_APP" "$LEVELS_ARCHIVE"
# Preserve published entries and their original download URLs.
if [ -f "$PROJECT_ROOT/docs/appcast.xml" ]; then
  cp "$PROJECT_ROOT/docs/appcast.xml" "$LEVELS_UPDATE_DIR/appcast.xml"
fi
cp "$PROJECT_ROOT/Resources/Beta-Release-Notes.md" "$LEVELS_UPDATE_DIR/Levels-$LEVELS_VERSION-arm64.md"
"$SPARKLE_TOOLS/generate_appcast" --account com.joseluna.levels.updates \
  --download-url-prefix "$LEVELS_DOWNLOAD_PREFIX" --maximum-deltas 0 --maximum-versions 0 \
  --embed-release-notes --link https://github.com/madetonight/Levels/releases \
  "$LEVELS_UPDATE_DIR"
DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}" \
  xcrun swift "$PROJECT_ROOT/Scripts/verify-update.swift" \
  "$LEVELS_ARCHIVE" "$LEVELS_UPDATE_DIR/appcast.xml" "$LEVELS_RELEASE_APP/Contents/Info.plist"
python3 - "$PROJECT_ROOT" "$LEVELS_VERSION" "$LEVELS_ARCHIVE" <<'PY'
import hashlib, sys
from pathlib import Path
root, version, archive = Path(sys.argv[1]), sys.argv[2], Path(sys.argv[3])
files = [root / 'dist/Beta' / f'Levels-{version}-beta-arm64.{extension}' for extension in ['dmg', 'zip']]
files = [p for p in files if p.is_file()] + [archive]
(archive.parent / 'SHA256SUMS.txt').write_text(''.join(
    f'{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.name}\n' for p in files))
PY
printf '\nSigned update files are prepared locally in %s. Nothing was uploaded.\n' "$LEVELS_UPDATE_DIR"
