# Levels 0.1.9 beta

Pausing Spotify or another audio app no longer leaves its controls blocked.

## What changed

- Idle apps and stopped audio engines are treated as normal pauses. Native playback stays available; fresh samples reapply the saved volume when playback resumes.
- Genuine tap or device failures restore native playback and retry automatically, with a delay that increases up to 30 seconds if a driver keeps failing. You do not need to move the slider or reset the app.
- Recovery is independent for each app. New audio helpers reconnect immediately. Reset, quit and sleep cancel obsolete retries.
- During a genuine failure, the status says Reconnecting. Saved volume, mute and output choices are retained.
- The watchdog checks less frequently than 0.1.8 while keeping the silent-playback safeguards.

## Install or update

Choose Options → Updates → Check for Updates. The same tested app is in the downloadable beta DMG. Updates are verified with Levels' signing key and installation requires approval.

This release keeps the same Apple Development signing certificate as 0.1.8. It does not reset audio permissions or scan paired Bluetooth devices on startup. macOS controls permission persistence. It is not Apple-notarized; a first browser-downloaded launch may still require [Apple's Open Anyway approval](https://support.apple.com/102445).

## Requirements and privacy

Apple silicon, macOS 15+. Liquid Glass requires macOS 26+. Per-app audio adjustment requires System Audio Recording permission. Audio is processed locally, never saved or uploaded. Automatic checks preserve existing opt-outs; the white update indicator remains available.

Regression checks cover pause/resume grace, silent streams, delayed retries, independent apps and helper replacement. Native hardware tests exercise an engine stop/resume and an injected active callback stall. Broader Bluetooth, external monitor and sleep/wake listening tests remain pending.

Built by heyjoseluna. Inspired by Ahmed Gagan. MIT and Sparkle notices are included.
