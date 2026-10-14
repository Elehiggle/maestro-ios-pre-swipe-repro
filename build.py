#!/usr/bin/env python3
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import subprocess
import time

ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description="Build the native UIKit swipe fixture for iOS Simulator.")
parser.add_argument("--sdk", default=os.environ.get("REPRO_SDK", "iphonesimulator"))
parser.add_argument("--arch", choices=["arm64", "x86_64"], default=platform.machine())
args = parser.parse_args()
app = ROOT / "build/SwipeWaitFixture.app"
app.mkdir(parents=True, exist_ok=True)
(ROOT / "logs").mkdir(exist_ok=True)
sdk = subprocess.check_output(["xcrun", "--sdk", args.sdk, "--show-sdk-path"], text=True, timeout=30).strip()
command = ["xcrun", "swiftc", "-sdk", sdk, "-target", args.arch + "-apple-ios15.0-simulator",
           "-module-cache-path", str(ROOT / "build/ModuleCache"), str(ROOT / "source/main.swift"),
           "-o", str(app / "SwipeWaitFixture")]
start = time.time()
code = None
error = None
with (ROOT / "logs/build.log").open("w") as log:
    try:
        code = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=180).returncode
        if code == 0:
            (app / "Info.plist").write_bytes((ROOT / "source/Info.plist").read_bytes())
            code = subprocess.run(["codesign", "--force", "--sign", "-", str(app)],
                                  stdout=log, stderr=subprocess.STDOUT, timeout=30).returncode
    except (OSError, subprocess.TimeoutExpired) as failure:
        error = str(failure)
receipt = {"command": command, "sdk": sdk, "developerDirectory": os.environ.get("DEVELOPER_DIR"),
           "startWall": start, "endWall": time.time(), "exitCode": code, "error": error,
           "sourceSha256": hashlib.sha256((ROOT / "source/main.swift").read_bytes()).hexdigest(),
           "infoPlistSha256": hashlib.sha256((ROOT / "source/Info.plist").read_bytes()).hexdigest()}
if code == 0:
    receipt["executableSha256"] = hashlib.sha256((app / "SwipeWaitFixture").read_bytes()).hexdigest()
(ROOT / "build/receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
print(json.dumps(receipt, indent=2))
raise SystemExit(code if code is not None else 1)
