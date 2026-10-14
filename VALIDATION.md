# Levels 0.1.6 beta validation

- Apple silicon Release build and strict nested signatures verified; sandbox stays enabled. The zero-budget beta is ad-hoc signed and not Apple-notarized.
- 82 regression tests in 20 suites cover audio lifecycle, persistence, limiter, reset level, silent audio detection, helper replacement, stable row order, and existing routing policies.
- Native Output, Input, and Settings renders inspected in dark/light and Solid/Liquid Glass. No divider lines or app counter; each app has a right-aligned Reset below its slider.
- Shared Options menu and preference persistence checked. Settings opened, closed, and reopened three times using the same window; it is never opened automatically.
- Live Core Audio probe measured a quiet tone, digital silence on a continuously open stream, and resumed tone. All three states matched. Passive measurement uses unmuted taps with asynchronous setup; it does not change native playback.
- DMG integrity and app-only archive checks verified. The DMG includes an Applications link, first-launch instructions, a Privacy & Security shortcut, and upstream/Sparkle notices.
- Ed25519 update archive signature and size verified against the embedded public key; altered bytes rejected. The private key remains in Keychain.

Physical HDMI/DisplayPort keyboard controls, Bluetooth quality, and broader device/sleep/wake tests remain pending. A fresh first launch on another Mac is unverified; unnotarized browser downloads may require Apple's per-app Open Anyway approval. Source/build/signature checks do not remove that requirement.

Live in-app update verified: an older connected 0.1.5 build checked the public feed, downloaded, installed, and relaunched the exact 0.1.6 Release executable. Strict signatures and saved volume/mute/routing/appearance choices remained intact. The four public release assets matched their local bytes; the deployed public feed matched the generated XML.


## Levels 0.1.7 / build 9 — compact mixer

Optimized arm64 Release build and strict nested signatures passed. 86 tests in 20 suites passed. Native dark/light Solid/Glass Output and Input renders were inspected. An isolated native popup-button check verified selected-device labels, full menu choices, routing actions, and unchanged app volume/mute settings. The Settings window passed three open/close/reopen cycles.

Output controls use a thin flat button surface instead of the system's large rounded bezel. Master/input percentages sit directly beside their sliders. Shorter slider travel, slightly thicker tracks/thumbs, compact aligned rows, selected-device labels, hidden scroll indicators, and the collapsed Other apps drawer are included. Known audio apps retain session presence without stale process IDs. Audio processing and permissions are unchanged.

Physical monitor, Bluetooth, sleep/wake, and another-Mac first-launch behavior still need broader beta testing. The beta remains sandboxed and ad-hoc signed, with no Gatekeeper bypass. Update archive signing and public-feed verification are performed before rollout.


### Published update verification

Published v0.1.7-beta from source commit 0c3e04e. Four public release assets were downloaded without credentials and matched their local package bytes and lengths. The live HTTPS appcast matched the signed generated XML exactly. An isolated 0.1.6/build 7 app using the shipping Sparkle runtime checked, downloaded, installed and relaunched 0.1.7/build 9. Installed executable bytes matched the final Release app; strict signatures passed. Saved app volume, mute, routing, feature and appearance choices were preserved. Device last-used timestamps refreshed normally on relaunch. The exact shipping app was restored to the normal project build location. Physical hardware and another-Mac first-launch checks remain pending.
