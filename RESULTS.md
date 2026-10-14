# Measured results — 14 October 2026

`bare` displays a static scroll view; `moving` adds an accessible thumb moving at 6 pt/s to the same view. Its label and identifier stay fixed.

| Mode | Pre-swipe screen-static requests | Pre-swipe hierarchy requests | Native dispatch after command start | Scroll result |
| --- | ---: | ---: | ---: | --- |
| `bare` | 1 | 0 | 0.233 s | PASS; first scrolled event at 10.667 pt |
| `moving` | 19 | 11 started / 11 completed | 8.049 s | PASS; first scrolled event at 10.667 pt |

Both runs report 1398×2034 pixels and 466×678 points. Initial and final screenshot dimensions agree. Both helpers exit 0, both JUnit cases are SUCCESS, and neither reaches its 180-second watchdog. Post-gesture hierarchy requests are excluded from the table.

The moving pre-dispatch hierarchy reads total 2.447 seconds; recorded status-bar phases account for 1.781 seconds. Native request timestamps and the Maestro swipe-command start define the intervals. The source's 3-second screenshot gate, comparison loop and pauses also contribute; the total wait is not just hierarchy execution time.

## Evidence references

`evidence/summary.json` records each request's original native-log line number, completed-query durations, swipe-command line, native dispatch request, and fixture touch/scroll events. `evidence/{bare,moving}/` contains the complete native stream, root Maestro log, wrapper output, fixture events, JUnit, installation log and run/capture receipts. `evidence/REDACTION.md` explains the path/device-ID replacement in public copies.

`evidence/session.json` records the dedicated simulator, initial geometry, host environment and each verified native listener. The actual native executable matches the simulator runner embedded in the official driver JAR. IPv4/IPv6 ports were free before each flow; the runner checked simulator identity and executable hash during startup.

## Release and environment

Official Maestro release archive SHA-256: `5384593cb4e7a106489e75a821d157dd43f4e438df6bc308b72e82c685e1283a`. The GitHub API asset digest and official `checksums_sha256.txt` both match. The global CLI was not changed. Release preparation receipts precede execution; live runtime checks appear in each capture receipt and the session record.

| Tested artifact | SHA-256 |
| --- | --- |
| `maestro-client.jar` | `7c07b0625f44f10a1c1dc8657f7d498cca316677444b7fd9a5f45668cfb69f5b` |
| `maestro-ios-driver.jar` | `5316a3f28d2d50319138f9e2f46bbc817b8fc0e328aa7277ed50375ad291c34e` |
| Live native simulator runner | `be0619b1e43124ef40de6d42b8149ecb503be2fffda08f13323efbac3e65c597` |

Environment: macOS 27.0.1 (26A434), arm64; Xcode 27.1 (27A9269), iOS 27.1 simulator; Maestro logs Java 17, with host OpenJDK 17.0.19+0; `disableAnimations=false`. Host one-minute load was high: bare 331.52→460.55, moving 476.53→529.00. These are two observed controls, not a timing benchmark. The primary finding is eleven versus zero pre-dispatch hierarchy queries at equal geometry.

The source/run/flow hashes and all public evidence hashes are pinned in `MANIFEST.json`. The UIKit source and portable build/run helpers remain unchanged from the tested fixture.
