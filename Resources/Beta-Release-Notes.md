# Levels 0.1.8 beta

Safe audio handoff, a compact mixer, and quiet update notifications.

## What changed

- Startup no longer mutes native playback before the replacement audio path delivers real samples. Stalled callbacks release the tap and restore native playback; saved levels and routes are retained.
- Process taps use their own appended input buffer rather than a physical microphone stream. Passive meters remain nonmuting.
- This beta uses the owner’s stable Apple Development certificate. The first switch may require audio access approval once; later builds keep the same signing identity. It is not Apple-notarized.

- A small white update-available dot appears on the menu-bar icon and Options button. The Updates menu offers the available version. Scheduled checks use a gentle indicator; manual checks open the install dialog.
- Automatic update checks are enabled for new installs. Existing choices, including an explicit opt-out, are preserved. Installation still requires approval.
- Full selected-output names appear in wider thin buttons below each app slider. Playback status sits beside the app name and uses Playing/Idle wording, while mute and zero-volume states remain distinct.
- San Francisco typography for Master volume; the larger master percentage shares the app-percentage column. Sliders retain their travel and aligned controls.
- Ordinary volume, routing, startup, sleep recovery and device-change handling no longer scan paired Bluetooth devices. Connected Bluetooth outputs remain available through Core Audio. Direct Bluetooth access waits for an explicit connect/disconnect action.
- Saved volume, mute, routing and appearance choices are retained.

## Install or update

Already using a connected beta (0.1.5 or later)? Choose Options → Updates → Check for Updates. Daily checks are optional, and installation requires your approval. Saved volume, mute, routing, and appearance choices are retained. Update archives are verified with Levels' dedicated signing key.

First install: download the beta DMG, drag Levels to Applications, eject the image, and open Levels. The DMG includes an Open Privacy & Security shortcut to make Apple's first-launch approval easier to reach. Levels lives in the menu bar; Settings opens only when requested.

**Zero-budget, not Apple-notarized.** macOS may block a browser-downloaded first launch. If you trust Levels, follow [Apple's Open Anyway instructions](https://support.apple.com/102445). A free ad-hoc or updater signature cannot replace Apple notarization. Managed Macs may restrict approval. No system security setting is disabled.

## Requirements and privacy

Apple silicon, macOS 15+. Native Liquid Glass requires macOS 26+. Per-app controls and signal detection need System Audio Recording permission. Audio is processed locally and never saved or uploaded. Passive measurement exists only while the mixer is visible and does not mute or reroute native playback. A process with an adjusted level or route still needs its control tap while Levels is running. Quitting restores native playback.

## Beta testing

Automated checks cover independent reset, saved preferences, silent audio, signal detection, helper churn, limiter behavior, and existing audio regressions. Physical HDMI/DisplayPort keyboard controls, Bluetooth codec quality, and broader hardware sleep/wake testing remain pending.

Report bugs at https://github.com/madetonight/Levels/issues with Mac model, macOS version, devices, and reproduction steps. Please do not upload private recordings.

Built by heyjoseluna. Inspired by Ahmed Gagan. MIT and Sparkle notices are included.
