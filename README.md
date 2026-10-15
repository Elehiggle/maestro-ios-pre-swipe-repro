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

## Record and count requests

Run this from the repository root after installing the app, using the same
`UDID`. It runs both flows again, saving each run in a new temporary directory.
The native stream uses `syslog` format, whose timestamps include a UTC offset;
Maestro's timestamps use UTC. `measure.awk` converts the native offset before
comparing them. Keep the simulator dedicated to this test while recording.

```sh
(
  set -eu
  for MODE in static moving; do
    RUN=$(mktemp -d "${TMPDIR:-/tmp}/maestro-$MODE.XXXXXX")
    printf 'Logs: %s\n' "$RUN"
    date -u '+%Y-%m-%dT%H:%M:%SZ' > "$RUN/start-utc.txt"
    xcrun simctl spawn "$UDID" log stream \
      --style syslog --level debug \
      --predicate 'process == "maestro-driver-iosUITests-Runner"' \
      > "$RUN/native.log" 2>&1 &
    CAPTURE_PID=$!
    trap 'kill -INT "$CAPTURE_PID" 2>/dev/null || true; wait "$CAPTURE_PID" 2>/dev/null || true' EXIT
    sleep 1
    kill -0 "$CAPTURE_PID"

    MAESTRO_RESULT=0
    TZ=UTC MAESTRO_OPTS="${MAESTRO_OPTS:-} -Duser.timezone=UTC" \
      maestro --verbose --udid "$UDID" test \
        --no-ansi --debug-output "$RUN/debug" "flows/$MODE.yaml" \
        > "$RUN/console.log" 2>&1 || MAESTRO_RESULT=$?
    printf '%s\n' "$MAESTRO_RESULT" > "$RUN/exit-code.txt"
    sleep 1
    kill -INT "$CAPTURE_PID" 2>/dev/null || true
    wait "$CAPTURE_PID" 2>/dev/null || true
    trap - EXIT

    CLI_LOG=$(find "$RUN/debug" -type f -name maestro.log ! -path '*/logs/*')
    test -f "$CLI_LOG"
    cp "$CLI_LOG" "$RUN/maestro.log"
    awk -f measure.awk "$RUN/maestro.log" "$RUN/native.log" > "$RUN/counts.tsv"
    cat "$RUN/counts.tsv"
    test "$MAESTRO_RESULT" -eq 0
  done
)
```

The TSV gives the two boundary timestamps in UTC, their source line numbers,
elapsed seconds, hierarchy requests and screenshot checks. The interval starts
at the CLI's `Swipe … RUNNING` entry and ends at the native driver's first
`POST /swipeV2` receipt. Each `POST /viewHierarchy` entry inside that interval
counts once; `GET /isScreenStatic` entries count separately. Requests after the
swipe receipt are excluded. This measures dispatch, not the first physical touch.

Check `exit-code.txt` is `0`; a failed flow's logs are retained for diagnosis.
The counter rejects missing or duplicate swipe boundaries and recordings that
cross UTC midnight. Use paired logs from the same run; it cannot detect every
clock mismatch or missing event. An offset-free native log must already be UTC.
The number of reads can vary: a stable comparison can return early, and host
load can affect timing and sampling.

You can also recalculate the saved iOS 26.2 samples without running the app:

```sh
SAVED=$(mktemp -d "${TMPDIR:-/tmp}/maestro-saved.XXXXXX")
unzip -q evidence/ios-26.2.zip -d "$SAVED"
awk -f measure.awk "$SAVED/3-moving/maestro.log" "$SAVED/3-moving/native.log"
```

## Inspect manually

To inspect each mode manually:

```sh
xcrun simctl terminate "$UDID" dev.maestro.swipewaitminimal
xcrun simctl launch "$UDID" dev.maestro.swipewaitminimal -mode static
xcrun simctl terminate "$UDID" dev.maestro.swipewaitminimal
xcrun simctl launch "$UDID" dev.maestro.swipewaitminimal -mode moving
```
