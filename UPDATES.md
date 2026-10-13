# Levels updates

The app uses Sparkle 2.10.0. Both Options entry points offer an Updates submenu with Check for Updates and Automatically check for updates. Automatic checks default off, check daily when enabled, and never silently install an update. Installation requires the user's approval. System profiling is disabled.

The user selected `madetonight/Levels` as the public beta release location. It is now public. Returning it to private later will break update downloads unless releases and the feed move to a public host first. Do not put a GitHub access token into the app.

## Current state

- Sparkle is integrated and the manual/automatic controls are implemented.
- A dedicated signing key exists in macOS Keychain under account `com.joseluna.levels.updates`; only its public key is in Resources/Info.plist. Never export the private key into this project or upload it with releases.
- No SUFeedURL has been set because no public feed has been published. The app does not make update requests in this state; a manual check explains that updates have not been published. The automatic-check preference can be selected and remembered for when publishing is configured.
- The user approved the two app-scoped Sparkle installer service exceptions, and they are applied in Resources/Levels.entitlements. The sandbox remains enabled. Resources/Sparkle-Installer-Permissions.patch preserves the exact reviewed change.
- The first zero-budget beta is ad-hoc signed and unnotarized. Developer ID/notarization is not required to upload it, but normal first-launch acceptance requires them. Installation instructions explain Apple's per-app Open Anyway flow.

## Publish a release

1. Retain the approved installer permissions. They permit contact with `com.joseluna.levels-spks` and `com.joseluna.levels-spki`, as required by Sparkle's sandboxed installer. It does not grant additional audio permissions or disable the sandbox.
2. Set `SUFeedURL` in Resources/Info.plist to the real public HTTPS URL of `appcast.xml`. Keep SUPublicEDKey unchanged. Check that the URL works without a GitHub login. A public GitHub release asset is suitable; a private repository's asset is not.
3. Increase CURRENT_PROJECT_VERSION for every update and set MARKETING_VERSION in project.yml and the included Xcode project. This updater-enabled test build is 0.1.2/build 3, higher than 0.1.0/build 1. Existing builds without an updater need this first release installed manually.
4. For a zero-budget beta, retain the verified ad-hoc signatures and disclose that Apple has not notarized it. For a later Developer ID release, use Xcode Archive/Export to sign the app and Sparkle helpers, notarize, and staple before making the final archive. Do not claim an ad-hoc beta is notarized. Both paths require real old-to-new installation tests before live updates are advertised.
5. Run `Scripts/prepare-update.sh` with the real public release-download directory URL (ending in `/`). This creates a ZIP containing only Levels.app and an EdDSA-signed appcast locally under dist/Updates. The tool reads the signing key from Keychain; do not pass or print private-key material.
6. Upload that ZIP and release notes as GitHub release assets, then upload/replace `appcast.xml` at the stable feed URL. Upload the archive first so the feed never advertises a missing download. The script does not upload anything or publish a GitHub release.
7. Test from an installed older updater-enabled build in Applications: manual check, automatic check, installation/relaunch, invalid-signature rejection, and retention of audio/appearance preferences. Do not test installation while running the app from a read-only DMG.

The update feed describes the build number, version, minimum macOS/hardware, archive URL, byte size, and signature. Sparkle verifies the archive before extraction; never remove its signing verification or switch the feed to HTTP.

Official guides: https://sparkle-project.org/documentation/ and https://sparkle-project.org/documentation/sandboxing/
