# Zero-budget Levels beta

The current downloadable beta is 0.1.9/build 13, Apple silicon, macOS 15+. It uses the verified optimized Release app, an owner-approved Apple Development certificate, and no Apple notarization. Publishing this beta does not require paid Apple Developer membership. Self-signed or Sparkle update signatures do not create Gatekeeper trust.

The certificate selection is kept in the ignored local `.release-signing` file.
The private key stays in Keychain. Keep the same identity for later owner releases;
a fresh clone can set `LEVELS_SIGNING_IDENTITY` to its own certificate or `-`.
Changing identity may require audio permission once. This does not provide notarization.

## Build and package

After source changes run `Scripts/package-dmg.sh`; run relevant regressions with `Scripts/test.sh`. Then run `Scripts/package-beta.sh`. The latter packages the existing Release app without changing its code signature, runtime, entitlements, or saved user preferences.

The output in dist/Beta contains the drag-to-Applications DMG, app-only ZIP, SHA256SUMS.txt, INSTALL.txt, RELEASE-NOTES.md, and package-details.json. The DMG includes the app, Applications shortcut, installation instructions, beta notes, upstream MIT/Sparkle notices, and volume icon. It does not include source, keys, personal preferences, or audio recordings.

## Published release

The updated sample is prepared as v0.1.9-beta. Publish its verified DMG, ZIP, and checksums at https://github.com/madetonight/Levels/releases/tag/v0.1.9-beta. No signing key or credential belongs in the repository.

For subsequent releases:

Use the public `madetonight/Levels` repository. Create a GitHub release tagged `v0.1.9-beta`, title `Levels 0.1.9 beta`, and mark it as a pre-release. Use dist/Beta/RELEASE-NOTES.md for the description. Upload the DMG, optional ZIP, and SHA256SUMS.txt. Publishing binaries does not require uploading local source or developer credentials. Keep the beta label and unnotarized-install notice visible next to the download.

## Verify a fresh installation

Download the public DMG in a browser on a second Mac. Verify its checksum, copy the app to Applications, eject the image, then attempt launch. If blocked, follow Apple's per-app Open Anyway flow in System Settings → Privacy & Security. Do not tell customers to disable Gatekeeper or remove quarantine in Terminal. Company-managed Macs may prevent exceptions.

Test first launch, menu-bar icon, audio permission, saved volume/mute, independent outputs, quitting, sleep/wake, reconnect, and manual replacement by a later beta. Avoid claiming cross-Mac compatibility until this has been performed. Local signature and DMG checks do not establish downloaded first-launch behavior.

## Updates

The connected beta uses https://madetonight.github.io/Levels/appcast.xml. Earlier releases through 0.1.4 need manual installation of this build first. Updates are then checked inside Levels; daily checks default on for new installs, with saved opt-outs retained and installation requires approval. Sparkle archive signatures are free and separate from Apple signing. See UPDATES.md for publishing and verification steps.


## First-launch trust and the zero-budget constraint

Apple's normal trusted browser-download path uses a Developer ID Application certificate and notarization. Apple Development certificates, ad-hoc signatures, self-signed certificates, and Sparkle update signatures do not replace that path. Packaging as a DMG or ZIP does not change Gatekeeper approval.

Developer ID certificates require Apple Developer Program membership. A membership fee waiver is available to qualifying nonprofit, educational, and government legal entities; individuals and single-person businesses are excluded. A trusted project sponsor with an existing membership is another possible funding arrangement, but no sponsor is configured. This project cannot promise direct first launch of an unnotarized download on a default Mac.

Sources: https://developer.apple.com/help/glossary/developer-id-certificate/ ; https://developer.apple.com/help/account/membership/fee-waivers/ ; https://support.apple.com/102445 . The beta retains Apple's per-app approval flow and the installer shortcut.
