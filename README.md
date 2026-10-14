# Levels

A native macOS menu bar volume mixer. Its audio engine is adapted from [Fader](https://github.com/pantafive/fader), under the MIT license; see LICENSE and UPSTREAM.md.

## Try it

Source, assets, tests, scripts, documentation, and distributable builds are maintained in this project. Download the [latest sample beta](https://github.com/madetonight/Levels/releases/tag/v0.1.6-beta), or build locally with the scripts below.

Open `dist/Levels.app`. Left-click the three-fader icon in the menu bar to open the panel. Right-click that icon, or click the panel's top-right three-dot Options button, for the same appearance, surface, settings, and Quit menu.

Levels stays in the menu bar. Launching or reopening the app does not open a window or activate a hidden item. Reveal it through your menu bar manager, then click its icon to open the mixer. On macOS 27 it uses AppKit's expanded-interface lifecycle; earlier systems use the classic button action. Keyboard navigation uses native controls.

- **Output:** master volume, per-app volume/mute, and selected-device buttons are together here. Choose the Mac's default output in Options → Settings → Devices. System default in an app's selector follows that device. Browsers and common playback apps remain in the main list while open; other idle audio apps are in a collapsed Other apps drawer. Apps producing sound enter the main list, with a short grace period through pauses. Helper replacement retains the app until it quits, without preserving obsolete process IDs. Each app has a reset icon on the right of its slider; it restores the configurable default level (100% initially), preserving mute and output. Scrolling works without a visible scrollbar.
- **Input:** select an input and adjust gain when supported by the hardware. Shows which apps are using the microphone.
- **Settings:** the dedicated Settings window holds device choices, login, optional monitor/Bluetooth features, default reset level, and volume reset. Appearance and Updates remain separate menu choices. Right-click an app row for reset actions.

The compact 320 × 560-point mixer uses the approved sage and mint palette and real icons from each running app. The top-right three-dot Options button opens settings. Appearance offers Solid (the opaque textured background) and Liquid Glass (clear native glass on macOS 26+); the Output/Input bar follows the same surface choice. Dark/Light color and Solid/Liquid Glass material are independently selectable in one submenu. Existing System preferences continue following macOS until a color is chosen. The interface uses the default San Francisco system font. The reflective border applies to both surfaces. Reduced Transparency uses a solid background; earlier systems use a translucent material fallback for glass.

macOS requires **System Audio Recording** permission for per-app processing and playback signal detection. Audio is processed on the Mac and is never recorded to disk or uploaded. If access is denied, the panel explains how to enable Levels in Privacy & Security and retry.

Volume changes apply to the whole app, including its helper processes, rather than individual browser tabs. Output switching itself does not need audio recording permission. Fixed HDMI/DisplayPort devices can use optional software master volume enabled in Settings. Other devices without writable volume show a read-only explanation.

For simultaneous playback on different devices, connect your headphones and start Spotify and a browser video. In Output, use each app's device button to choose your headphones for Spotify and MacBook Pro Speakers for the browser. Per-app selection does not change the Mac's default output, and each app keeps its own level and mute control. Selecting System default restores normal output following. If a selected device disconnects, the app falls back to the current system output while remembering its selection. Per-app routing uses the same audio permission as per-app volume control. The user verified Spotify/headphone and browser/speaker simultaneous playback with independent volume and mute controls.

Levels must remain running for adjusted app volumes to apply. Quitting restores each app's original audio path; this can increase the volume of previously quiet or muted apps. Levels remembers settings for the next launch.

Adjusted apps stay ready during ordinary pauses; Levels does not automatically mute or park their audio. Before system sleep it releases its process taps, then rebuilds them after wake using your saved levels, mute choices, and routes. Apps at their original level with no selected route continue through their native audio path.

## Develop

Requires Apple silicon, macOS 15 or later, and Xcode with the macOS SDK. The generated `Levels.xcodeproj` is included. Sparkle 2.10.0 is pinned through Swift Package Manager; build scripts keep its checkout and artifacts in `Vendor/SourcePackages/`.

Open `Levels.xcodeproj` in Xcode, select Levels, and Run. Or:

```sh
./Scripts/build.sh
./Scripts/test.sh
```

`project.yml` is the project source of truth. If you change target membership, regenerate the Xcode project using [XcodeGen](https://github.com/yonaskolb/XcodeGen):

```sh
xcodegen generate
```

The mixer is a menu bar popover only; there is no separate window mode. Opening uses AppKit’s native transition. Closing uses a short ease-out fade with a cancellable 180 ms deadline independent of animation completion callbacks; reopening invalidates an older close request. Reduced Motion skips the fade.

To render the native interface in both themes without opening any visible windows or starting audio capture:

```sh
./Scripts/render-ui.sh
```

This standalone harness compiles with `RENDER_SHOTS`, seeds example levels, and writes Output and Input screenshots for both surfaces to `dist/appearance`. The harness is excluded from the app target and does not change saved volume or appearance preferences.

Local builds use ad-hoc signing. Distribution signing and notarization have not been configured; rebuilding may require granting macOS audio access again.

To build the optimized Apple silicon release and its drag-to-Applications disk image:

```sh
./Scripts/package-dmg.sh
```

This preserves the regular development build, places the optimized app and ZIP in `dist/Release/`, and creates `dist/Levels-0.1.5-arm64.dmg`. The image includes the app, an Applications shortcut, install/privacy notes, and MIT attribution. This package has an ad-hoc signature: it has no Developer ID distribution signature or Apple notarization and fails Gatekeeper's public-distribution assessment. Do not describe it as a notarized public installer. Package measurements and verification results are in `dist/Release/package-details.json`.

## Downloadable beta

[Download Levels 0.1.7 beta](https://github.com/madetonight/Levels/releases/tag/v0.1.7-beta). This is an unnotarized Apple silicon build and includes first-launch instructions.

Run `Scripts/package-beta.sh` to package the existing optimized app in `dist/Release/Levels.app` as a clearly labeled, unnotarized beta. After source changes, rebuild with `Scripts/package-dmg.sh` first. The beta DMG, app-only ZIP, portable checksums, release notes, and package measurements are kept in `dist/Beta/`. See BETA.md for publishing and installation validation.

## Playback status

While the mixer is visible, Levels reuses existing control taps or creates passive nonmuting taps to distinguish actual signal from a silent open stream. A 200 ms activity hold avoids flickering between audio buffers. No samples are retained. Passive taps are released when the mixer closes or the Mac sleeps; setup runs off the UI thread. If capture is unavailable, Output active reports the macOS stream flag without pretending it proves audible sound. Muted/zero-volume apps report Muted/Silent.

Pauses and audio-helper replacement retain a row while its app remains open; its label updates independently. Rows stay alphabetical. Cached rows never retain obsolete process object IDs; adjusted controls apply again when a new helper appears.

## Implementation

- SwiftUI panel hosted by an AppKit status item and transient popover.
- Core Audio process taps attenuate adjusted applications. Applications at 100%, unmuted, remain on their native audio path.
- App audio sources are grouped by bundle identifier, including browser helper processes.
- Core Audio listeners track process, device, and master-volume changes. Saved levels use local UserDefaults with coalesced writes and a final save when quitting.
- The inherited engine handles output changes, sleep/wake, and audio-service restarts.
- The interface reports failed app audio setup and failed output selection. Per-app routing is exposed in each app row. Multiple-output pairing and Bluetooth connection controls remain unexposed.
- Audio processing stays local. The new Sparkle updater uses its downloader helper for optional update-feed/archive requests; system profiling is disabled. Updates are not silently installed. There are no accounts or subscriptions, and no audio is uploaded.

## Updates

Options → Updates contains Check for Updates and Automatically check for updates. The same submenu is available from the menu-bar icon's right-click menu. Automatic checking defaults off and is remembered. Starting with 0.1.5, the app checks the public [update feed](https://madetonight.github.io/Levels/appcast.xml). Install this first connected beta manually if upgrading from 0.1.4 or earlier. Future updates are offered inside Levels, with signed archives and approval before installation. See [UPDATES.md](UPDATES.md) for the release process.

`madetonight/Levels` is public and is the selected beta release location. A later switch to private requires moving the feed and archives to a public host first. No GitHub access token is embedded. The two app-scoped Sparkle installer sandbox exceptions are applied with explicit user approval; the sandbox remains enabled. See `Resources/Sparkle-Installer-Permissions.patch` for the exact change and `UPDATES.md` for the publishing workflow. Developer ID signing and notarization are optional for publishing this zero-budget beta, but required for normal first-launch acceptance under Gatekeeper.

## Validation

See VALIDATION.md for checks performed on the local build and the remaining hardware/permission checks.
