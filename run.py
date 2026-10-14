#!/usr/bin/env python3
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import signal
import socket
import stat
import subprocess
import tempfile
import time
import uuid

ROOT = Path(__file__).resolve().parent
APP = "dev.maestro.swipewaitfixture"
parser = argparse.ArgumentParser(description="Install and run one fixture swipe on an explicitly selected booted simulator.")
parser.add_argument("--udid", default=os.environ.get("REPRO_UDID"), help="Simulator UUID (or REPRO_UDID).")
parser.add_argument("--mode", choices=["bare", "moving"], default="moving")
parser.add_argument("--maestro", default=os.environ.get("REPRO_MAESTRO", "maestro"), help="Stock Maestro 2.11.0 executable.")
parser.add_argument("--port", type=int, default=int(os.environ.get("REPRO_PORT", "22147")))
args = parser.parse_args()
try:
    udid = str(uuid.UUID(args.udid))
except (ValueError, TypeError, AttributeError):
    parser.error("Supply a simulator UUID with --udid or REPRO_UDID.")
if not 1024 <= args.port <= 65535:
    parser.error("Port must be between 1024 and 65535.")
cli = shutil.which(args.maestro)
if cli is None:
    parser.error("Maestro was not found. Install stock Maestro 2.11.0 or supply --maestro.")
app = ROOT / "build/SwipeWaitFixture.app"
if not (app / "SwipeWaitFixture").is_file() or not (ROOT / "build/receipt.json").is_file():
    parser.error("Run python3 build.py first.")
build = json.loads((ROOT / "build/receipt.json").read_text())
if build.get("exitCode") != 0 or hashlib.sha256((app / "SwipeWaitFixture").read_bytes()).hexdigest() != build.get("executableSha256"):
    parser.error("Fixture build failed or changed; rebuild before running.")
lock_directory = Path(tempfile.gettempdir()) / ("maestro-swipewait-fixture-" + str(os.getuid()))
lock_directory.mkdir(mode=0o700, exist_ok=True)
if lock_directory.is_symlink() or lock_directory.stat().st_uid != os.getuid() or stat.S_IMODE(lock_directory.stat().st_mode) != 0o700:
    parser.error("The fixture lock directory must be owned by this user with mode 0700.")
lock = os.open(lock_directory / (udid + ".lock"), os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW, 0o600)
try:
    fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
except BlockingIOError:
    parser.error("Another fixture run owns this simulator.")
# The lock spans preflight, installation, flow execution and receipt collection.
with socket.socket() as check:
    check.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    check.bind(("127.0.0.1", args.port))
devices = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "--json"], text=True, timeout=30))
selected = [(runtime, device) for runtime, entries in devices["devices"].items() for device in entries
            if device["udid"].lower() == udid.lower()]
if len(selected) != 1 or ".iOS-" not in selected[0][0] or selected[0][1]["state"] != "Booted":
    parser.error("Select an available, booted iOS Simulator. Boot it before running this fixture.")
# Maestro requires the canonical spelling returned by simctl.
udid = selected[0][1]["udid"]
version = subprocess.check_output([cli, "--version"], text=True, stderr=subprocess.STDOUT, timeout=30).strip()
if version != "2.11.0":
    parser.error("This stock-CLI control requires Maestro 2.11.0; detected: " + version)
logs = ROOT / "logs"
logs.mkdir(exist_ok=True)
run = Path(tempfile.mkdtemp(prefix=args.mode + "-", dir=logs))
home = Path(tempfile.mkdtemp(prefix="maestro-swipewait-java-", dir="/private/tmp"))
env = os.environ.copy()
env["MAESTRO_OPTS"] = "-Duser.home=" + str(home)
env["MAESTRO_CLI_NO_ANALYTICS"] = "1"
env["MAESTRO_CLI_ANALYSIS_NOTIFICATION_DISABLED"] = "true"
command = [cli, "--verbose", "--udid", udid, "--driver-host-port", str(args.port), "test",
           "--no-ansi", "--format", "JUNIT", "--output", str(run / "junit.xml"),
           "--debug-output", str(run / "debug"), str(ROOT / "flows" / (args.mode + ".yaml"))]
receipt = {"command": command, "appId": APP, "device": selected[0][1], "runtime": selected[0][0],
           "maestroVersion": version, "maestroExecutable": str(Path(cli).resolve()),
           "host": {"system": platform.system(), "release": platform.release(), "machine": platform.machine(), "macOS": platform.mac_ver()[0]},
           "buildReceipt": build, "mode": args.mode, "port": args.port, "watchdogSeconds": 180,
           "javaHome": str(home),
           "flowSha256": hashlib.sha256((ROOT / "flows" / (args.mode + ".yaml")).read_bytes()).hexdigest(),
           "hostLoadBefore": os.getloadavg(), "startWall": time.time()}
# Record installed artifact hashes when the CLI uses the standard layout.
lib = Path(cli).resolve().parent.parent / "lib"
receipt["cliArtifactHashes"] = {name: hashlib.sha256((lib / name).read_bytes()).hexdigest()
                                for name in ["maestro-client.jar", "maestro-ios-driver.jar"] if (lib / name).is_file()}
(run / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
code = 1
process = None

def interrupted(signum, frame):
    raise KeyboardInterrupt

signal.signal(signal.SIGTERM, interrupted)
try:
    with (run / "install.log").open("w") as install:
        subprocess.run(["xcrun", "simctl", "install", udid, str(app)], check=True, timeout=60,
                       stdout=install, stderr=subprocess.STDOUT)
    with (run / "console.log").open("w") as console:
        process = subprocess.Popen(command, cwd=ROOT, env=env, stdout=console, stderr=subprocess.STDOUT, start_new_session=True)
        try:
            code = process.wait(timeout=180)
            receipt["timedOut"] = False
        except subprocess.TimeoutExpired:
            receipt["timedOut"] = True
            os.killpg(process.pid, signal.SIGTERM)
            try:
                code = process.wait(timeout=10)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                code = process.wait(timeout=10)
except KeyboardInterrupt:
    code = 130
    receipt["interrupted"] = True
except (OSError, subprocess.SubprocessError) as failure:
    receipt["error"] = str(failure)
finally:
    if process is not None and process.poll() is None:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait(timeout=10)
    try:
        container = Path(subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, APP, "data"], text=True, timeout=15).strip())
        shutil.copy2(container / "Documents/events.jsonl", run / "app-events.jsonl")
    except (OSError, subprocess.SubprocessError) as failure:
        receipt["appEventCopyError"] = str(failure)
    receipt.update({"exitCode": code, "endWall": time.time(), "hostLoadAfter": os.getloadavg()})
    (run / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    fcntl.flock(lock, fcntl.LOCK_UN)
    os.close(lock)
print("Results:", run)
print(json.dumps(receipt, indent=2))
raise SystemExit(code)
