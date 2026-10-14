# Levels 0.1.6 beta

A cleaner menu-bar mixer with independent app reset and more accurate playback status.

## What changed

- Reset below each app slider, on the right. Choose its default level in Settings → App volumes; it starts at 100%. Reset preserves mute and output choices.
- Minimal Output and Input tabs without divider lines or the app counter.
- Playing now uses real audio signal activity when measurement is available. Silent open streams show Idle; if measurement is unavailable, the honest fallback is Output active.
- Short pauses and browser audio-helper replacements retain the row briefly. Alphabetical ordering keeps apps from jumping when playback changes.
- A dedicated Settings window for device selection, login, inactive apps, monitor volume, Bluetooth microphone preference, and reset preferences. Appearance and Updates remain in the Options menu.
- Per-app boost up to 200% with a peak limiter; optional software volume and keyboard support for fixed HDMI/DisplayPort outputs; optional Mac microphone preference for Bluetooth headphones.

## Install or update

Already using the connected beta (0.1.5)? Choose Options → Updates → Check for Updates. Daily checks are optional, and installation requires your approval. Saved volume, mute, routing, and appearance choices are retained. Update archives are verified with Levels' dedicated signing key.

First install: download the beta DMG, drag Levels to Applications, eject the image, and open Levels. The DMG includes an Open Privacy & Security shortcut to make Apple's first-launch approval easier to reach. Levels lives in the menu bar; Settings opens only when requested.

**Zero-budget, not Apple-notarized.** macOS may block a browser-downloaded first launch. If you trust Levels, follow [Apple's Open Anyway instructions](https://support.apple.com/102445). A free ad-hoc or updater signature cannot replace Apple notarization. Managed Macs may restrict approval. No system security setting is disabled.

## Requirements and privacy

Apple silicon, macOS 15+. Native Liquid Glass requires macOS 26+. Per-app controls and signal detection need System Audio Recording permission. Audio is processed locally and never saved or uploaded. Passive measurement exists only while the mixer is visible and does not mute or reroute native playback. A process with an adjusted level or route still needs its control tap while Levels is running. Quitting restores native playback.

## Beta testing

Automated checks cover independent reset, saved preferences, silent audio, signal detection, helper churn, limiter behavior, and existing audio regressions. Physical HDMI/DisplayPort keyboard controls, Bluetooth codec quality, and broader hardware sleep/wake testing remain pending.

Report bugs at https://github.com/madetonight/Levels/issues with Mac model, macOS version, devices, and reproduction steps. Please do not upload private recordings.

Built by heyjoseluna. Inspired by Ahmed Gagan. MIT and Sparkle notices are included.
