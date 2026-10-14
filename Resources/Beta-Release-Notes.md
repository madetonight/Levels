# Levels 0.1.7 beta

A compact mixer with thinner output buttons, shorter sliders, and a quieter app list.

## What changed

- Thin, flat output buttons show each app's selected device. Full names and the system-default choice remain available in the native menu and tooltip.
- Smaller master-volume and microphone-gain percentages sit directly beside their sliders.
- Compact, aligned app rows with a reset icon on the right of the slider. Reset restores the level from Settings (100% initially), preserving mute and output choices.
- Shorter slider travel, with a slightly thicker track and thumb. Per-app range remains 0–200%, with limiting above 100%.
- Browsers and common playback apps remain directly available. Other idle audio processes appear in a collapsed Other apps drawer; producing sound promotes an app into the main list, with a short grace period to avoid flicker.
- Known apps remain available throughout their open session even if an audio helper disappears. Cached helpers cannot create controls for obsolete process IDs.
- Scrolling works without visible scrollbars. The redundant inactive-app preference is removed.
- The master output uses the matching device symbol; MacBook speakers use a laptop icon.

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
