# Levels 0.1.6 audio features

This release includes the audio enhancements below. The authoritative package and signed feed are prepared by the scripts described in UPDATES.md.

## App boost

App sliders now range from 0–200%, with a unity marker and an orange boost segment. Existing positions below 100% retain the same cube-law gain. Above 100%, gain is linear amplitude (200% = 2×, approximately +6 dB), not perceived loudness. A linked-channel peak limiter with instant attack, 80 ms release, and a 0.98 digital ceiling protects boosted Float32 audio. Quiet audio below the ceiling remains linear; already distorted source audio cannot be repaired by boosting. No lookahead latency is added. Gain smoothing, mute, routing, and persistence remain independent. At unity with no mute, route, or software-master reduction, native playback needs no tap.

## HDMI / DisplayPort volume

Enable Options → Settings… → Audio → Software volume for HDMI / DisplayPort. This feature defaults off. It applies only to HDMI/DisplayPort devices whose HAL endpoint has no writable hardware master volume. Volume and mute are remembered per device UID; per-app settings stay independent. Apps pinned to another output are unaffected. Returning the software master to unmuted 100% removes taps for otherwise-neutral apps.

Keyboard support uses a media-key-only event tap while the fixed digital output is the default and software control is enabled. Use Enable volume keys… to approve Accessibility in System Settings. Hardware-controllable devices and unrelated keys keep native behavior. Volume up/down change the master by 1/16 (Shift+Option uses 1/64); mute toggles only that software master. A transient nonactivating HUD shows its level. If macOS refuses the event tap, the UI reports that keys are unavailable and the slider remains usable. This path still needs testing with a real monitor and approved Accessibility access. The app sandbox remains enabled; no new entitlements were added.

Software volume requires existing System Audio Recording permission for process taps and requires Levels to remain running. Multi-output aggregates and older multi-device app routes are outside this new software-master control path; their existing behavior is preserved. Quitting restores native playback, as with per-app volume control.

## Bluetooth microphone preference

Enable Keep Mac microphone with Bluetooth in Options → Settings… → Audio. It defaults off. When Bluetooth output is in use and the system chooses a Bluetooth input, Levels prefers the available built-in microphone. A currently selected non-Bluetooth mic, including USB audio interfaces, stays selected. Explicitly choosing a Bluetooth mic inside Levels turns the preference off so it is not immediately reversed.

This changes the macOS default input; it does not record the mic or override a call app that explicitly selects its own input device. It does not guarantee a fixed sample rate or codec. Apple's explanation of Bluetooth listening/talking modes: https://support.apple.com/102217

## Validation and later hardware check

82 tests in 20 suites passed, including limiter peak containment, stereo balance, quiet-audio amplification, release recovery, independent persisted controls, fixed-output eligibility, microphone choice, and media-key packet decoding. The optimized Release build, strict nested signatures, sandbox, saved choices, and native menu/light/dark render checks passed. The new preview stays running from dist/Levels.app. Preview images are in dist/audio-feature-preview; the machine-readable verification is dist/audio-feature-validation.json.

The user deferred monitor and Bluetooth hardware testing. Later: play on a fixed HDMI/DisplayPort output, enable software volume, grant Accessibility, and try up/down/mute and the HUD. Switch to built-in speakers and check that native keys still work; an app pinned to other headphones should retain its level. At software 100% unmuted, neutral apps should return to native playback. With Bluetooth output, enable the mic preference and verify default input stays built-in; selecting a USB mic must keep it, and selecting a Bluetooth mic in Levels must disable the preference. Listen to boosted quiet audio, test mute and independent routing, and repeat sleep/wake before publishing a new beta.
