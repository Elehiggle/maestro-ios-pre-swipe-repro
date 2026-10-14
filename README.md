# iOS moving-view swipe reproduction

`bare` displays a static scroll view; `moving` adds an accessible thumb moving at 6 pt/s to the same view. Its label and identifier stay fixed. Maestro makes eleven pre-swipe hierarchy queries in `moving` and none in `bare`; both controls scroll successfully. [Measured results and complete evidence](RESULTS.md) use stock Maestro 2.11.0 and equal screen geometry.

## Clone, build and run

Use macOS, Python 3, full Xcode with an iOS Simulator SDK, Java, and stock Maestro 2.11.0:

```sh
git clone https://github.com/Elehiggle/maestro-ios-pre-swipe-repro.git
cd maestro-ios-pre-swipe-repro
python3 build.py --sdk iphonesimulator
```

Choose a dedicated booted iOS simulator. Replace `SIMULATOR_UUID` and `FREE_PORT`, keep the same display state/orientation, and use a free port for each run:

```sh
python3 run.py --udid SIMULATOR_UUID --mode bare --port FREE_PORT
python3 run.py --udid SIMULATOR_UUID --mode moving --port FREE_PORT
```

`--maestro PATH` selects an isolated stock CLI. The helper installs only `dev.maestro.swipewaitfixture`, locks the selected simulator during its run, checks the build hash, and keeps logs/receipts under `logs/`.

Each flow makes one 700 ms swipe and checks actual scroll offset. The helper's 180-second watchdog covers the whole Maestro invocation; the flow's 500 ms option concerns best-effort waiting after the swipe.

For complete native request evidence, start a separate capture before each mode and stop it after the run:

```sh
xcrun simctl spawn SIMULATOR_UUID log stream --style compact --level debug \
  --predicate 'process == "maestro-driver-iosUITests-Runner"' > native-stream.log 2>&1
```

Copy app events before another launch resets them. Compare only equal native pixel/grid dimensions. Query counts and dispatch events establish behavior; elapsed time depends on the host/runtime. [Issue draft](issue.md), [results](RESULTS.md), [public evidence redaction](evidence/REDACTION.md), and `MANIFEST.json` describe the included pair.
