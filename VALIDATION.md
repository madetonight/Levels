# Validation for Levels 0.1.2 beta

- Debug and optimized arm64 Release builds pass; strict nested signatures are checked.
- 69 regression tests in 18 suites pass, including per-app settings, routing policy, tap lifecycle, sleep resource teardown, and close/reopen cancellation.
- Native offscreen light/dark renders show the Apps heading, no search field, and Idle status for silent apps.
- The isolated shared Options harness validates Dark / Light / separator / Solid / Liquid Glass order, independent stored color/material choices, and Updates immediately above About Levels.
- The beta has a free ad-hoc signature and is not notarized. It needs per-app first-launch approval where allowed by macOS. Public archives include instructions, licensing notices, and checksums.

Hardware and permission behavior require separate verification. Simultaneous app routing to headphones and Mac speakers was verified on the development Mac. Browser-downloaded first launch on another Mac, sleep/wake, reconnect, and end-to-end update installation remain unverified. The update feed is not enabled.
