LEVELS 0.1.8 — PUBLIC BETA (NOT NOTARIZED)

A menu-bar volume mixer for your Mac.

Requirements
Apple silicon Mac (M-series), macOS 15 or later.
Liquid Glass appearance requires macOS 26 or later.

Install
1. Quit any running copy of Levels.
2. Drag Levels.app onto the Applications shortcut in this disk image.
3. Eject the disk image and open Levels from Applications.
4. If macOS blocks the first launch, open the included Open Privacy & Security
   shortcut (or System Settings → Privacy & Security).
   Find the message about Levels, choose Open Anyway, and confirm if you trust
   the download. This approves Levels specifically; do not disable Gatekeeper.
   Apple instructions: https://support.apple.com/102445
5. Click the Levels icon in the menu bar. No app window opens automatically.

Output
Use Options → Settings → Devices to choose the Mac's default output.
Each application's slider adjusts its volume; its speaker button toggles mute.
Use the selected-device button below an app's slider to choose where it plays.
Different apps can play through different outputs simultaneously. Each app has
a reset icon on the right of its slider. It restores the default level
chosen in Settings → App volumes (100% initially), preserving mute and output.
Other idle audio apps are tucked into the Other apps drawer. Scrolling remains
available without a visible scrollbar.

Input
Select a microphone and adjust its gain when supported by the device.

Appearance
Options → Appearance offers Dark or Light, then Solid or Liquid Glass.
The same options menu opens by right-clicking the Levels menu-bar icon.

Audio access and privacy
Per-app volume, mute, and routing need macOS System Audio Recording permission.
Levels processes selected apps' audio locally in real time. While the mixer is
open, passive nonmuting taps distinguish sound from silent open streams. They
are released when the mixer closes. Playing/Idle describe signal when measured, falling back to macOS output activity
when measurement is unavailable. It does not save
audio recordings or upload audio. macOS displays a privacy indicator while
audio access is active. Your volume, mute, and output choices are remembered.

Release status
This beta uses an Apple Development certificate with a stable signing identity.
It is not signed with Apple Developer ID or notarized. The first transition to
this certificate may require audio permission again. macOS normally blocks the first launch of a browser download;
Apple's Open Anyway flow may be available. Managed Macs can restrict it.
Downloading beta software means accepting unfinished behavior. Start with
low playback volume, especially when testing mute or external output devices.
Sleep/wake and external-device reconnection still need broader live testing.
This build has no purchase activation or license-key validation. Options →
Updates offers a manual update check and a remembered automatic-check setting.
The public update feed is https://madetonight.github.io/Levels/appcast.xml.
Install this beta manually if upgrading from 0.1.4 or earlier. Future versions
can be installed inside Levels using Options → Updates → Check for Updates.
Automatic daily checks default on for new installs; your saved choice is kept.
A small white dot on the menu-bar icon and Options button indicates an available
update. Options → Updates identifies its version. Levels verifies each
update archive and asks before installation; it never installs silently.
It does not ask for an account or subscription.

Credits
Built by heyjoseluna. Inspired by Ahmed Gagan.
Audio engine adapted from Fader by pantafive under the MIT license.
See the Licenses folder and the license included inside Levels.app.
Update framework: Sparkle Project. Its license is in the Licenses folder.
