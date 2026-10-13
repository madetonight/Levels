# Levels updates

Levels uses Sparkle 2.10.0 with a public HTTPS feed at https://madetonight.github.io/Levels/appcast.xml. GitHub Pages serves `docs/` from `main`; GitHub Releases hosts the downloads. Keep this repository public while using these URLs. Never embed a GitHub token in the app.

## Customer experience

Install 0.1.5/build 6 manually when upgrading from 0.1.4 or earlier: 0.1.3 and earlier have no feed address, and 0.1.4 is superseded because of a packaged launch-signing issue. From the connected build, Options → Updates → Check for Updates fetches new releases. Automatically check for updates is opt-in and checks daily. Users approve each installation; silent installation and system profiling are disabled. The same menu is available by right-clicking the menu-bar icon.

This beta is ad-hoc signed and not Apple-notarized. Sparkle's free Ed25519 archive signatures verify updates; they do not establish Apple Gatekeeper trust. First-launch instructions still apply.

## Publish the next update

1. Change `MARKETING_VERSION` and increase `CURRENT_PROJECT_VERSION` in both project.yml and the included Xcode project. Never reuse a build number or replace an archive already referenced by the feed.
2. Update Resources/Beta-Release-Notes.md and Resources/Install-ReadMe.txt. Run Scripts/test.sh, Scripts/package-dmg.sh, then Scripts/package-beta.sh.
3. Run `Scripts/prepare-update.sh https://github.com/madetonight/Levels/releases/download/vVERSION-beta/` with the actual tag version. Approve the native Keychain prompt if needed. The private key remains in Keychain under account `com.joseluna.levels.updates`; retain this key for every release. Only its public key ships with the app.
4. The script verifies the Release signature, creates an app-only ZIP, generates the signed feed with embedded notes, preserves older feed entries, and verifies the archive with the app's public key. It also confirms changed archive bytes are rejected. Outputs are in dist/Updates/VERSION. Nothing is uploaded automatically.
5. Publish the matching source commit and GitHub pre-release. Upload the DMG and optional beta ZIP from dist/Beta, plus the exact signed ZIP and combined SHA256SUMS.txt from dist/Updates/VERSION. The beta ZIP may be uploaded too, but it is a different filename. Verify the public download and its size/checksum before advertising it.
6. Only after the archive is available, copy dist/Updates/VERSION/appcast.xml to docs/appcast.xml and publish that file. Do not edit the generated XML after signing. Wait for GitHub Pages deployment and verify the public feed is the new file.
7. Test a real older connected build: check, download, installation/relaunch, and retained volume/mute/routing/appearance choices. Keep verification evidence in the project. Local signing/build checks alone do not prove installation works on another Mac.

For rollback, remove the faulty newest feed item and regenerate/sign the feed before publication. Sparkle does not downgrade already upgraded users; ship the fix with a higher build number. Keep previously referenced archives available. GitHub's pre-release label does not filter Sparkle updates: this initial feed is explicitly for the beta audience. When stable releases are introduced, choose a separate feed or implement Sparkle channel selection first.

## Configuration and security

Resources/Info.plist contains SUFeedURL and SUPublicEDKey. Archive verification occurs before extraction. The approved app-scoped installer services are com.joseluna.levels-spks and com.joseluna.levels-spki; the app remains sandboxed. The downloader helper handles update networking. Updates do not change audio-access permissions or auto-mute playback.

Official guides: https://sparkle-project.org/documentation/publishing/ and https://sparkle-project.org/documentation/sandboxing/

## Free beta signing compatibility

Scripts/package-dmg.sh explicitly builds with ad-hoc signing and Hardened Runtime disabled for this zero-budget beta. The app sandbox, strict signatures, and Sparkle archive verification remain enabled; no debug-access or library-validation exception is added. Ad-hoc signatures have no Apple Team ID, so Hardened Runtime library validation cannot load the ad-hoc Sparkle framework. Developer ID archive builds retain the project’s Hardened Runtime setting and need helpers signed by the same Apple team. No system security setting is changed.
