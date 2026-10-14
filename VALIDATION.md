# Levels 0.1.6 beta validation

- Apple silicon Release build and strict nested signatures verified; sandbox stays enabled. The zero-budget beta is ad-hoc signed and not Apple-notarized.
- 82 regression tests in 20 suites cover audio lifecycle, persistence, limiter, reset level, silent audio detection, helper replacement, stable row order, and existing routing policies.
- Native Output, Input, and Settings renders inspected in dark/light and Solid/Liquid Glass. No divider lines or app counter; each app has a right-aligned Reset below its slider.
- Shared Options menu and preference persistence checked. Settings opened, closed, and reopened three times using the same window; it is never opened automatically.
- Live Core Audio probe measured a quiet tone, digital silence on a continuously open stream, and resumed tone. All three states matched. Passive measurement uses unmuted taps with asynchronous setup; it does not change native playback.
- DMG integrity and app-only archive checks verified. The DMG includes an Applications link, first-launch instructions, a Privacy & Security shortcut, and upstream/Sparkle notices.
- Ed25519 update archive signature and size verified against the embedded public key; altered bytes rejected. The private key remains in Keychain.

Physical HDMI/DisplayPort keyboard controls, Bluetooth quality, and broader device/sleep/wake tests remain pending. A fresh first launch on another Mac is unverified; unnotarized browser downloads may require Apple's per-app Open Anyway approval. Source/build/signature checks do not remove that requirement.
