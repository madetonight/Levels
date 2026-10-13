#!/bin/bash
set -euo pipefail

# Package the existing optimized Release app. Rebuild with package-dmg.sh
# after source changes; this script never re-signs or alters the app.
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LEVELS_APP="$PROJECT_ROOT/dist/Release/Levels.app"
LEVELS_BETA_DIR="$PROJECT_ROOT/dist/Beta"
test -d "$LEVELS_APP" || { echo 'Build the Release app with Scripts/package-dmg.sh first.' >&2; exit 1; }
codesign --verify --deep --strict "$LEVELS_APP"
python3 - "$LEVELS_APP" <<'PY'
import plistlib, subprocess, sys
result = subprocess.run(['codesign', '-d', '--entitlements', '-', '--xml', sys.argv[1]], check=True, capture_output=True)
entitlements = plistlib.loads(result.stdout)
if not entitlements.get('com.apple.security.app-sandbox') or entitlements.get('com.apple.security.get-task-allow'):
    raise SystemExit('Use a sandboxed Release app without debug access. Rebuild with Scripts/package-dmg.sh.')
PY
LEVELS_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$LEVELS_APP/Contents/Info.plist")"
mkdir -p "$LEVELS_BETA_DIR"
LEVELS_STAGE="$(mktemp -d "$PROJECT_ROOT/dist/.levels-beta.XXXXXX")"
trap 'rm -rf "$LEVELS_STAGE"' EXIT

ditto "$LEVELS_APP" "$LEVELS_STAGE/Levels.app"
ln -s /Applications "$LEVELS_STAGE/Applications"
cp "$PROJECT_ROOT/Resources/Install-ReadMe.txt" "$LEVELS_STAGE/Read Me.txt"
cp "$PROJECT_ROOT/Resources/Beta-Release-Notes.md" "$LEVELS_STAGE/Beta Notes.md"
mkdir "$LEVELS_STAGE/Licenses"
cp "$PROJECT_ROOT/LICENSE" "$LEVELS_STAGE/Licenses/Fader-MIT-License.txt"
cp "$PROJECT_ROOT/UPSTREAM.md" "$LEVELS_STAGE/Licenses/Attribution.txt"
cp "$PROJECT_ROOT/Vendor/SourcePackages/artifacts/sparkle/Sparkle/LICENSE" "$LEVELS_STAGE/Licenses/Sparkle-License.txt"
cp "$LEVELS_APP/Contents/Resources/AppIcon.icns" "$LEVELS_STAGE/.VolumeIcon.icns"
SetFile -a C "$LEVELS_STAGE"

LEVELS_DMG="$LEVELS_BETA_DIR/Levels-$LEVELS_VERSION-beta-arm64.dmg"
LEVELS_ZIP="$LEVELS_BETA_DIR/Levels-$LEVELS_VERSION-beta-arm64.zip"
ditto -c -k --sequesterRsrc --keepParent "$LEVELS_APP" "$LEVELS_ZIP"
hdiutil create -volname "Levels $LEVELS_VERSION Beta" -srcfolder "$LEVELS_STAGE" \
  -fs HFS+ -format UDZO -imagekey zlib-level=9 -ov "$LEVELS_DMG"
hdiutil verify "$LEVELS_DMG"
cp "$PROJECT_ROOT/Resources/Install-ReadMe.txt" "$LEVELS_BETA_DIR/INSTALL.txt"
cp "$PROJECT_ROOT/Resources/Beta-Release-Notes.md" "$LEVELS_BETA_DIR/RELEASE-NOTES.md"

python3 - "$LEVELS_APP" "$LEVELS_DMG" "$LEVELS_ZIP" <<'PY'
import hashlib, json, plistlib, subprocess, sys
from pathlib import Path
app, dmg, archive = map(Path, sys.argv[1:])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
files = [p for p in app.rglob('*') if p.is_file() and not p.is_symlink()]
hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in [dmg, archive]}
(dmg.parent / 'SHA256SUMS.txt').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()))
details = {
    'name': 'Levels', 'channel': 'beta',
    'version': info['CFBundleShortVersionString'], 'build': info['CFBundleVersion'],
    'architecture': 'arm64', 'minimum_macos': info['LSMinimumSystemVersion'],
    'bundle_id': info['CFBundleIdentifier'], 'notarized': False,
    'signing': 'ad-hoc; Apple Developer ID not used',
    'dmg_file': dmg.name, 'dmg_bytes': dmg.stat().st_size,
    'zip_file': archive.name, 'zip_bytes': archive.stat().st_size,
    'app_logical_bytes': sum(p.stat().st_size for p in files),
    'app_file_count': len(files), 'sha256': hashes,
    'contents': ['Levels.app', 'Applications', 'Read Me.txt', 'Beta Notes.md', 'Licenses', '.VolumeIcon.icns'],
    'checks': ['Strict app signature verified', 'DMG checksum valid'],
    'first_launch': 'macOS normally blocks a downloaded unnotarized app; per-app Open Anyway approval may be available',
    'downloaded_installation_verified': False,
    'live_updates': 'Not configured; replace beta manually',
}
(dmg.parent / 'package-details.json').write_text(json.dumps(details, indent=2) + '\n')
print(json.dumps({k: details[k] for k in ['version', 'dmg_bytes', 'zip_bytes', 'app_logical_bytes']}, indent=2))
PY
printf '\nPrepared beta files: %s\nNothing was uploaded.\n' "$LEVELS_BETA_DIR"
