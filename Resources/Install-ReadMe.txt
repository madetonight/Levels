LEVELS 0.1.4 — PUBLIC BETA (NOT NOTARIZED)

A menu-bar volume mixer for your Mac.

Requirements
Apple silicon Mac (M-series), macOS 15 or later.
Liquid Glass appearance requires macOS 26 or later.

Install
1. Quit any running copy of Levels.
2. Drag Levels.app onto the Applications shortcut in this disk image.
3. Eject the disk image and open Levels from Applications.
4. If macOS blocks the first launch, open System Settings → Privacy & Security.
   Find the message about Levels, choose Open Anyway, and confirm if you trust
   the download. This approves Levels specifically; do not disable Gatekeeper.
   Apple instructions: https://support.apple.com/102445
5. Click the Levels icon in the menu bar. No app window opens automatically.

Output
Click the device name under Master Volume to choose the Mac's default output.
Each application's slider adjusts its volume; its speaker button toggles mute.
Use the output selector below an app's slider to choose where that app plays.
Different apps can play through different outputs simultaneously.

Input
Select a microphone and adjust its gain when supported by the device.

Appearance
Options → Appearance offers Dark or Light, then Solid or Liquid Glass.
The same options menu opens by right-clicking the Levels menu-bar icon.

Audio access and privacy
Per-app volume, mute, and routing need macOS System Audio Recording permission.
Levels processes selected apps' audio locally in real time. It does not save
audio recordings or upload audio. macOS displays a privacy indicator while
audio access is active. Your volume, mute, and output choices are remembered.

Release status
This beta uses a free ad-hoc signature. It is not signed with Apple Developer
ID or notarized. macOS normally blocks the first launch of a browser download;
Apple's Open Anyway flow may be available. Managed Macs can restrict it.
Downloading beta software means accepting unfinished behavior. Start with
low playback volume, especially when testing mute or external output devices.
Sleep/wake and external-device reconnection still need broader live testing.
This build has no purchase activation or license-key validation. Options →
Updates offers a manual update check and a remembered automatic-check setting.
The public update feed is https://madetonight.github.io/Levels/appcast.xml.
Install this beta manually if upgrading from 0.1.3 or earlier. Future versions
can be installed inside Levels using Options → Updates → Check for Updates.
Enable Automatically check for updates for daily checks. Levels verifies each
update archive and asks before installation; it never installs silently.
It does not ask for an account or subscription.

Credits
Built by heyjoseluna. Inspired by Ahmed Gagan.
Audio engine adapted from Fader by pantafive under the MIT license.
See the Licenses folder and the license included inside Levels.app.
Update framework: Sparkle Project. Its license is in the Licenses folder.
