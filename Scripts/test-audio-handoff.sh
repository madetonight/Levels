#!/bin/bash
set -euo pipefail
PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
LEVELS_AUDIO_TEST_DIR="$PROJECT_ROOT/dist/audio-handoff-test"
LEVELS_AUDIO_TEST_APP="$LEVELS_AUDIO_TEST_DIR/Levels.app"
LEVELS_TONE_APP="$LEVELS_AUDIO_TEST_DIR/PlaybackProbe.app"
if [ -z "${LEVELS_SIGNING_IDENTITY:-}" ] && [ -f "$PROJECT_ROOT/.release-signing" ]; then
  LEVELS_SIGNING_IDENTITY="$(cat "$PROJECT_ROOT/.release-signing")"
fi
mkdir -p "$LEVELS_AUDIO_TEST_DIR" "$LEVELS_TONE_APP/Contents/MacOS"
ditto "$PROJECT_ROOT/dist/Levels.app" "$LEVELS_AUDIO_TEST_APP"
python3 - "$LEVELS_TONE_APP" <<'PY'
from pathlib import Path
import plistlib,sys
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'com.joseluna.levels.playback-probe','CFBundleExecutable':'PlaybackProbe','CFBundlePackageType':'APPL','LSUIElement':True}))
PY
codesign -d --entitlements - --xml "$PROJECT_ROOT/dist/Levels.app" > "$LEVELS_AUDIO_TEST_DIR/entitlements.plist" 2> "$LEVELS_AUDIO_TEST_DIR/signature.log"
xcrun swiftc -swift-version 6 -parse-as-library "$PROJECT_ROOT/Scripts/PlaybackProbe.swift" -o "$LEVELS_TONE_APP/Contents/MacOS/PlaybackProbe"
xcrun swiftc -swift-version 6 -D RENDER_SHOTS -parse-as-library -target arm64-apple-macos15.0 "$PROJECT_ROOT"/Sources/Audio/*.swift "$PROJECT_ROOT/Scripts/AudioHandoffHarness.swift" -o "$LEVELS_AUDIO_TEST_APP/Contents/MacOS/Levels"
codesign --force --sign - "$LEVELS_TONE_APP"
codesign --force --sign "${LEVELS_SIGNING_IDENTITY:--}" --entitlements "$LEVELS_AUDIO_TEST_DIR/entitlements.plist" "$LEVELS_AUDIO_TEST_APP"
codesign --verify --deep --strict "$LEVELS_AUDIO_TEST_APP"
# Launch the generator separately: the shipping sandbox cannot spawn a tool
# from an arbitrary workspace folder. Never relax the app's sandbox for a test.
python3 - "$LEVELS_AUDIO_TEST_DIR" <<'PY'
from pathlib import Path
import json,subprocess,sys
root=Path(sys.argv[1])
proofs={}
for mode in ['active-stall','idle-resume','auto-recovery']:
    with (root/f'{mode}-tone.log').open('w') as log:
        args=[str(root/'PlaybackProbe.app/Contents/MacOS/PlaybackProbe'),'--continuous']
        if mode=='idle-resume': args.append('--pause-engine')
        tone=subprocess.Popen(args,stdout=log,stderr=log)
        try:
            args=[str(root/'Levels.app/Contents/MacOS/Levels')]
            if mode=='idle-resume': args.append('--idle-resume')
            if mode=='auto-recovery': args.append('--auto-recovery')
            result=subprocess.run(args,capture_output=True,text=True,timeout=40)
        finally:
            if tone.poll() is None: tone.terminate();tone.wait()
    (root/f'{mode}.log').write_text(result.stdout+result.stderr)
    proof=json.loads(result.stdout.splitlines()[0]);proofs[mode]=proof
    print(json.dumps({mode:proof},indent=2))
    if result.returncode or not proof.get('passed'):
        (root/'result.json').write_text(json.dumps(proofs,indent=2)+'\n')
        raise SystemExit('Audio handoff FAILED')
(root/'result.json').write_text(json.dumps(proofs,indent=2)+'\n')
PY
