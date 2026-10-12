#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import secrets
import subprocess
import tempfile


def run(arguments, **kwargs):
    result = subprocess.run(arguments, capture_output=True, text=True, **kwargs)
    if result.returncode:
        raise SystemExit(f"Signing check failed at {Path(arguments[0]).name}: {result.stderr[-2000:]}")
    return result.stdout


identity = os.environ["SIGNING_IDENTITY"]
signing_keychain = os.environ["SIGNING_KEYCHAIN"]
requirement = f'identifier "io.github.calendar-bar" and certificate leaf = H"{identity}"'
with tempfile.TemporaryDirectory(prefix="calendar-signing-check-") as directory:
    root = Path(directory)
    data_keychain = root / "fictional.keychain-db"
    password = secrets.token_urlsafe(32)
    result = subprocess.run(["security", "create-keychain", "-p", password, str(data_keychain)], capture_output=True)
    if result.returncode:
        raise SystemExit("Cannot create isolated fixture keychain")
    try:
        applications = []
        for name, updated, signing_identity in [("Initial", False, identity), ("Updated", True, identity), ("Unrelated", False, "-")]:
            app = root / f"{name}.app"
            binary = app / "Contents/MacOS/Probe"
            binary.parent.mkdir(parents=True)
            main = root / "main.swift"
            main.write_bytes(Path("Tests/SigningProbe.swift").read_bytes())
            compiler = ["swiftc", str(main), "Sources/CalendarBar/KeychainAccess.swift", "-o", str(binary)]
            if updated:
                compiler.extend(["-D", "UPDATE"])
            run(compiler)
            with (app / "Contents/Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleExecutable": "Probe", "CFBundleIdentifier": "io.github.calendar-bar", "CFBundlePackageType": "APPL"}, file)
            signing = ["codesign", "--force", "--timestamp=none", "--sign", signing_identity, "--identifier", "io.github.calendar-bar"]
            if signing_identity != "-":
                signing.extend(["--keychain", signing_keychain, "--requirements", "=designated => " + requirement])
            run(signing + [str(app)])
            applications.append((app, binary))
        initial, updated, unrelated = applications
        assert initial[1].read_bytes() != updated[1].read_bytes()
        for app, _ in [initial, updated]:
            run(["codesign", "--verify", "--strict", "--test-requirement", "=" + requirement, str(app)])
        print(run([str(initial[1]), str(data_keychain), "create", str(unrelated[0])]).strip())
        print("Legacy update denied:", run([str(updated[1]), str(data_keychain), "denied"]).strip())
        print(run([str(initial[1]), str(data_keychain), "migrate"]).strip())
        print("Restart:", run([str(initial[1]), str(data_keychain), "read"]).strip())
        print("Update:", run([str(updated[1]), str(data_keychain), "read"]).strip())
        print("Reconnection:", run([str(updated[1]), str(data_keychain), "replace"]).strip())
        print("After reconnection restart:", run([str(initial[1]), str(data_keychain), "updated-value"]).strip())
        print("After reconnection update:", run([str(updated[1]), str(data_keychain), "updated-value"]).strip())
        print("Forgery:", run([str(unrelated[1]), str(data_keychain), "denied"]).strip())
        print("8 real Keychain migration checks passed; authorization UI disabled; fictional data only.")
    finally:
        subprocess.run(["security", "delete-keychain", str(data_keychain)], check=True, capture_output=True)
