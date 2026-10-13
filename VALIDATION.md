# Validation for Levels 0.1.4 beta

- Optimized arm64 Release build passes; strict nested signatures and DMG checksum are verified.
- 69 regression tests in 18 suites pass, including per-app settings, routing policy, tap lifecycle, sleep resource teardown, and close/reopen cancellation.
- The shipped HTTPS update feed and existing public signing key are embedded in the app. Automatic checks remain opt-in; installation requires approval and profiling is disabled.
- The final update ZIP passes Ed25519 verification with the public key shipped in Levels. Changing archive bytes fails verification.
- The Output Apps heading is removed; no search field, title subtitle, or footer labels are present. Appearance and options ordering are preserved.
- This beta is ad-hoc signed and not Apple-notarized. Public packages include first-launch instructions, licensing notices, and checksums.

Simultaneous app routing to headphones and Mac speakers was verified on the development Mac. Browser-downloaded first launch on another Mac, sleep/wake, reconnect, and end-to-end update installation require separate verification. Earlier builds through 0.1.3 have no feed URL and require manual installation of this connected beta.
