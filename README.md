# Minimal iOS pre-swipe comparison

A plain UIKit scroll view and an accessible blue dot. Both modes have the same
views, labels, identifiers, and display link. In `moving`, the dot moves at
6 pt/s, reversing every 30 seconds without jumping. In `static`, it stays still.
The dot stays outside the scroll view; content changes only when scrolled.

The two flows differ only in `mode`. Each checks that the second content row is
offscreen, performs one swipe, and checks that the row becomes visible. The
500 ms setting controls best-effort settling after the swipe.

## Build and install

Requires macOS, Xcode and Maestro 2.11.0. Run from this directory with an iPhone
17 Pro simulator on iOS 26.2, matching [Maestro's own test configuration](https://github.com/mobile-dev-inc/Maestro/blob/cli-2.11.0/.github/workflows/test-e2e.yaml#L490-L491).
Keep Maestro's default animations-enabled behavior.

```sh
SDK="$(xcrun --sdk iphonesimulator --show-sdk-path)"
ARCH="$(uname -m)"
APP="$PWD/build/SwipeWaitMinimal.app"
mkdir -p "$APP" "$PWD/build/ModuleCache"
xcrun swiftc -sdk "$SDK" -target "$ARCH-apple-ios15.0-simulator" \
  -module-cache-path "$PWD/build/ModuleCache" source/main.swift \
  -o "$APP/SwipeWaitMinimal"
cp source/Info.plist "$APP/Info.plist"
codesign --force --sign - "$APP"
xcrun simctl list devices available
```

Replace the UUID below with a dedicated, booted iPhone simulator. Commands use
the selected Xcode installation; set `DEVELOPER_DIR` first if needed.

```sh
UDID="REPLACE_WITH_SIMULATOR_UUID"
xcrun simctl install "$UDID" "$APP"
maestro --udid "$UDID" test flows/static.yaml
maestro --udid "$UDID" test flows/moving.yaml
```

To inspect each mode manually:

```sh
xcrun simctl terminate "$UDID" dev.maestro.swipewaitminimal
xcrun simctl launch "$UDID" dev.maestro.swipewaitminimal -mode static
xcrun simctl terminate "$UDID" dev.maestro.swipewaitminimal
xcrun simctl launch "$UDID" dev.maestro.swipewaitminimal -mode moving
```

