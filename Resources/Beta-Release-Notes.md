# Levels 0.1.10 beta

A more compact mixer with clearer per-app controls.

## What changed

- Narrower output selectors fit the selected device name. Long device names wrap instead of using abbreviations.
- Smaller mixer panel with tighter side padding and less space between apps. Text remains readable and volume slider travel stays consistent.
- Mute and reset sit together below each app's volume slider, beside its output selector.
- Master and app percentages share an aligned column; the master percentage remains larger.
- Light, dark, Solid, and Liquid Glass appearances keep the same layout.

## Install or update

Choose Options → Updates → Check for Updates. The downloadable beta DMG contains the same app. Updates are verified with Levels' signing key and installation requires approval. Existing automatic-check preferences and update indicators are preserved.

This release keeps the same Apple Development signing certificate as 0.1.9. It does not reset audio permissions or change the audio engine. Saved volume, mute, output, and appearance choices are retained. It is not Apple-notarized; a first browser-downloaded launch may still require [Apple's Open Anyway approval](https://support.apple.com/102445).

## Requirements and validation

Apple silicon, macOS 15+. Liquid Glass requires macOS 26+. Audio is processed locally, never saved or uploaded.

All 95 regression tests passed. Native layout checks cover dark/light and Solid/Liquid Glass, full and wrapped output names, route selection, and Settings open/close cycles. Broader Bluetooth, external monitor, and sleep/wake listening tests remain pending.

Built by heyjoseluna. Inspired by Ahmed Gagan. MIT and Sparkle notices are included.
