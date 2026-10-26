"""Capture the production SwiftUI views with isolated fictional data, on a booted simulator.

Usage: python3 scripts/capture-screenshots.py DEVICE_ID /path/to/IronScan.app
Build Debug for the simulator first. No participant data, camera capture, or cloud sync is used.
"""
import json
import shutil
import subprocess
import sys
import tempfile
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
device, app = sys.argv[1:3]
config = json.loads(subprocess.check_output([
    "node", "--input-type=module", "-e",
    "import {config} from './src/config.ts'; console.log(JSON.stringify(config))",
], cwd=root))
bundle_id = subprocess.check_output([
    "/usr/libexec/PlistBuddy", "-c", "Print:CFBundleIdentifier", str(Path(app) / "Info.plist")
], text=True).strip()

def sim(*args: str) -> None:
    subprocess.run(["xcrun", "simctl", *args], check=True)

sim("install", device, app)
sim("status_bar", device, "override", "--time", "9:41", "--dataNetwork", "wifi",
    "--wifiMode", "active", "--wifiBars", "3", "--batteryState", "charged", "--batteryLevel", "100")
for screen in config["copy"]["screens"]:
    if screen["kind"] != "capture":
        continue
    subprocess.run(["xcrun", "simctl", "terminate", device, bundle_id], capture_output=True)
    sim("launch", device, bundle_id, "--tutorial-capture", f"--tutorial-screen={screen['short'].lower()}")
    time.sleep(4)
    output = root / "public" / config["assets"]["screenshots"] / screen["file"]
    output.parent.mkdir(parents=True, exist_ok=True)
    # CoreSimulator's screenshot service cannot write into protected Documents folders.
    temporary = Path(tempfile.mkdtemp(prefix="ironscan-capture-")) / screen["file"]
    sim("io", device, "screenshot", str(temporary))
    shutil.copyfile(temporary, output)
    temporary.unlink()
    temporary.parent.rmdir()
    print(f"Captured {screen['short']}: {output}", flush=True)
