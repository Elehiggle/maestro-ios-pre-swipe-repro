# iOS: eleven hierarchy queries before swipe dispatch on a moving-view fixture

## Problem

Stock Maestro 2.11.0 performs eleven full hierarchy queries before dispatching a swipe in the moving-view fixture. The static control needs none. Both controls scroll successfully.

## Reproduce

Clone [the native UIKit reproduction](https://github.com/Elehiggle/maestro-ios-pre-swipe-repro), then use macOS, Python 3, Xcode, Java and Maestro 2.11.0:

```sh
python3 build.py --sdk iphonesimulator
python3 run.py --udid SIMULATOR_UUID --mode bare --port FREE_PORT
python3 run.py --udid SIMULATOR_UUID --mode moving --port FREE_PORT
```

Use a dedicated booted simulator at the same display state and orientation for both modes, with a free port for each run. `bare` displays a static scroll view; `moving` adds an accessible thumb moving at 6 pt/s to the same view. Its label and identifier stay fixed.

Both flows use:

```yaml
- swipe:
    start: 50%, 75%
    end: 50%, 35%
    duration: 700
    waitToSettleTimeoutMs: 500
```

## Observed

Measured on 2026-10-14, with equal **1398×2034 pixel / 466×678 point** geometry and verified official CLI/native runner bytes:

| Mode | Pre-swipe hierarchy queries | Command start → native swipe request | Result |
| --- | ---: | ---: | --- |
| Static | 0 | 0.233 s | PASS; real touch and scroll |
| Moving | 11, all completed | 8.049 s | PASS; real touch and scroll |

The counts cover only swipe-command start through native `/swipeV2` receipt. The moving run's eleven queries consumed 2.447 s, including 1.781 s of status-bar collection. Neither run reached the helper's 180 s watchdog.

## Expected and source path

Provide a documented way to bound or skip pre-swipe settling for continuous animations. The [500 ms option](https://docs.maestro.dev/reference/commands-available/swipe) concerns best-effort waiting after the swipe.

[IOSDriver.swipe](https://github.com/mobile-dev-inc/Maestro/blob/cli-2.11.0/maestro-client/src/main/java/maestro/drivers/IOSDriver.kt#L270) separately calls settling before dispatch. Its [screen-static gate](https://github.com/mobile-dev-inc/Maestro/blob/cli-2.11.0/maestro-client/src/main/java/maestro/drivers/IOSDriver.kt#L503-L507) falls back to [an initial hierarchy read and ten comparisons](https://github.com/mobile-dev-inc/Maestro/blob/cli-2.11.0/maestro-client/src/main/java/maestro/utils/ScreenshotUtils.kt#L58-L70). In `moving`, the thumb's pixels and accessibility bounds change continuously. A fix should preserve static-screen and finite-transition behavior; a deadline alone cannot interrupt a slow native query.

## Environment and evidence

Maestro 2.11.0 official release; Java 17 (host OpenJDK 17.0.19); macOS 27.0.1 arm64; Xcode 27.1 beta; iPhone Duo simulator on iOS 27.1. `disableAnimations=false`. Recorded host load was high, so these times describe this pair rather than a benchmark.

The reproduction includes complete logs, fixture events, JUnit, build/run/capture receipts and official-release checksums in `evidence/`, plus a file manifest. Public copies replace only local paths and device IDs. Both runs use the same native runner hash. See [RESULTS.md](https://github.com/Elehiggle/maestro-ios-pre-swipe-repro/blob/main/RESULTS.md) for request/dispatch evidence and artifact hashes.
