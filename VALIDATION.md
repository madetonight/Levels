# Validation for Levels 0.1.5 beta

- Optimized arm64 Release build passes and stays running after Finder launch; strict nested signatures and DMG checksum are verified.
- 69 regression tests in 18 suites pass, including per-app settings, routing policy, tap lifecycle, sleep resource teardown, and close/reopen cancellation.
- The shipped HTTPS update feed and existing public signing key are embedded in the app. Automatic checks remain opt-in; installation requires approval and profiling is disabled.
- The final update ZIP passes Ed25519 verification with the public key shipped in Levels. Changing archive bytes fails verification.
- The Output Apps heading is removed; no search field, title subtitle, or footer labels are present. Appearance and options ordering are preserved.
- This beta is ad-hoc signed and not Apple-notarized. Public packages include first-launch instructions, licensing notices, and checksums.

Simultaneous app routing to headphones and Mac speakers was verified on the development Mac. Browser-downloaded first launch on another Mac, sleep/wake, and reconnect still require separate verification. Builds through 0.1.3 have no feed URL; 0.1.4 is superseded due to a packaged launch-signing issue. Install 0.1.5 manually to bootstrap updates. The free beta packaging disables Hardened Runtime for ad-hoc compatibility while preserving the sandbox and signature verification.

## Live updater verification

An isolated older connected bundle (0.1.3/build 4) using the shipping Sparkle runtime checked the public HTTPS feed, downloaded 0.1.5/build 6, completed Install and Relaunch, and relaunched the actual Release app. The installed executable matched the packaged Release binary and passed strict signature verification. Five saved audio/appearance preference keys were unchanged. The older test harness started no audio taps; this validates the installer and relaunch flow on the development Mac, not first launch on every customer Mac. Altered archive bytes were rejected separately using the bundled public key.
