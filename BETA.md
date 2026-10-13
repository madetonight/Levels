# Zero-budget Levels beta

The first downloadable beta is 0.1.5/build 6, Apple silicon, macOS 15+. It uses the verified optimized Release app, free ad-hoc signing, and no Apple notarization. Publishing this beta does not require paid Apple Developer membership. Self-signed or Sparkle update signatures do not create Gatekeeper trust.

## Build and package

After source changes run `Scripts/package-dmg.sh`; run relevant regressions with `Scripts/test.sh`. Then run `Scripts/package-beta.sh`. The latter packages the existing Release app without changing its code signature, runtime, entitlements, or saved user preferences.

The output in dist/Beta contains the drag-to-Applications DMG, app-only ZIP, SHA256SUMS.txt, INSTALL.txt, RELEASE-NOTES.md, and package-details.json. The DMG includes the app, Applications shortcut, installation instructions, beta notes, upstream MIT/Sparkle notices, and volume icon. It does not include source, keys, personal preferences, or audio recordings.

## Published release

The updated sample is prepared as v0.1.5-beta. Publish its verified DMG, ZIP, and checksums at https://github.com/madetonight/Levels/releases/tag/v0.1.5-beta. No signing key or credential belongs in the repository.

For subsequent releases:

Use the public `madetonight/Levels` repository. Create a GitHub release tagged `v0.1.5-beta`, title `Levels 0.1.5 beta`, and mark it as a pre-release. Use dist/Beta/RELEASE-NOTES.md for the description. Upload the DMG, optional ZIP, and SHA256SUMS.txt. Publishing binaries does not require uploading local source or developer credentials. Keep the beta label and unnotarized-install notice visible next to the download.

## Verify a fresh installation

Download the public DMG in a browser on a second Mac. Verify its checksum, copy the app to Applications, eject the image, then attempt launch. If blocked, follow Apple's per-app Open Anyway flow in System Settings → Privacy & Security. Do not tell customers to disable Gatekeeper or remove quarantine in Terminal. Company-managed Macs may prevent exceptions.

Test first launch, menu-bar icon, audio permission, saved volume/mute, independent outputs, quitting, sleep/wake, reconnect, and manual replacement by a later beta. Avoid claiming cross-Mac compatibility until this has been performed. Local signature and DMG checks do not establish downloaded first-launch behavior.

## Updates

The connected beta uses https://madetonight.github.io/Levels/appcast.xml. Earlier releases through 0.1.4 need manual installation of this build first. Updates are then checked inside Levels; daily checking is opt-in and installation requires approval. Sparkle archive signatures are free and separate from Apple signing. See UPDATES.md for publishing and verification steps.
