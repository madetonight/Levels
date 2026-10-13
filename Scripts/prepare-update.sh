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
LEVELS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LEVELS_RELEASE_APP/Contents/Info.plist")"
LEVELS_UPDATE_DIR="$PROJECT_ROOT/dist/Updates/$LEVELS_VERSION"
mkdir -p "$LEVELS_UPDATE_DIR"
LEVELS_ARCHIVE="$LEVELS_UPDATE_DIR/Levels-$LEVELS_VERSION-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$LEVELS_RELEASE_APP" "$LEVELS_ARCHIVE"
"$SPARKLE_TOOLS/generate_appcast" --account com.joseluna.levels.updates \
  --download-url-prefix "$LEVELS_DOWNLOAD_PREFIX" --maximum-deltas 0 \
  "$LEVELS_UPDATE_DIR"
printf '\nSigned update files are prepared locally in %s. Nothing was uploaded.\n' "$LEVELS_UPDATE_DIR"
