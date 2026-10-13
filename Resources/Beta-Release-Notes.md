# Levels 0.1.3 beta

A compact macOS menu-bar mixer for per-app volume, mute, and separate audio outputs.

**Requirements:** Apple silicon Mac, macOS 15 or later. Native Liquid Glass requires macOS 26 or later.

## Download and install

Download `Levels-0.1.3-beta-arm64.dmg`, open it, and drag Levels to Applications. Quit any previous copy before replacing it. Eject the image and launch Levels from Applications. It lives in the menu bar; no main window opens automatically.

**This beta is not Apple-notarized.** It uses a free ad-hoc signature, so macOS normally blocks the first launch of an internet download. If you trust the download, follow [Apple's instructions](https://support.apple.com/102445): attempt to open Levels, then visit System Settings → Privacy & Security → Open Anyway and confirm. Approval may be restricted on managed Macs.

## Changes in this sample

- Restored the previous Output list: neutral idle apps are hidden by default; adjusted apps remain accessible, with an option to show inactive audio apps.
- Corrected the About credit to heyjoseluna.
- Removed the Volume mixer subtitle and the footer's privacy phrase and Dark/Light label, giving the app list more space.
- Retained the Apps heading, San Francisco typography, and the unified Appearance menu from the previous sample.

## Features

- Per-app volume and mute, with remembered settings.
- Different output devices for different apps, including simultaneous playback.
- Master output selection and volume; input selection and supported microphone gain.
- Solid or Liquid Glass surfaces; light or dark appearance.
- The same Options menu from the panel or a right-click on the menu-bar icon.

## Audio access

macOS System Audio Recording permission is needed for per-app control. Audio is processed locally, never saved or uploaded. macOS displays its privacy indicator while access is active. Levels must stay running for adjusted app levels to apply. Quitting restores native playback and can make a muted or reduced-volume app louder.

## Beta status and feedback

Sleep/wake recovery and external-device reconnection still need broader testing. Multiple-output playback and independent controls were verified on the development Mac; compatibility on other Macs and a fresh browser-downloaded installation remain unverified.

Update controls are included, but no live feed has been published. Replace the app manually for this beta. No purchase activation or subscription is required.

Report bugs at https://github.com/madetonight/Levels/issues with your macOS version, Mac model, audio devices, and steps to reproduce. For sleep bugs, include whether quitting Levels restores audio. Do not attach private audio recordings.

Built by heyjoseluna. Inspired by Ahmed Gagan. Upstream MIT and Sparkle notices are included in the DMG and app.
