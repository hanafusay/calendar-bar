#!/usr/bin/env python3
import os
from pathlib import Path
import plistlib
import re
import secrets
import shlex
import subprocess
import tempfile


def run(arguments, **kwargs):
    try:
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=60, **kwargs)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"Fictional signing check timed out at {Path(arguments[0]).name}")
    if result.returncode:
        raise SystemExit(f"Signing check failed at {Path(arguments[0]).name}: {result.stdout[-1000:]} {result.stderr[-1000:]}")
    return result.stdout


if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
    raise SystemExit("Credential fixture requires a disposable runner; it changes only that runner's default keychain.")
identity = os.environ["SIGNING_IDENTITY"]
signing_keychain = os.environ["SIGNING_KEYCHAIN"]
requirement = f'identifier "io.github.calendar-bar" and certificate leaf = H"{identity}"'
original_default = shlex.split(run(["security", "default-keychain", "-d", "user"]))[0]
original_list = shlex.split(run(["security", "list-keychains", "-d", "user"]))
with tempfile.TemporaryDirectory(prefix="calendar-signing-check-", dir=Path.home() / "Library/Keychains") as directory:
    root = Path(directory)
    keychain = root / "fictional.keychain-db"
    password = secrets.token_urlsafe(32)
    subprocess.run(["security", "create-keychain", "-p", password, str(keychain)], capture_output=True, check=True)
    try:
        applications = []
        for name, updated, signer in [("Initial", False, identity), ("Updated", True, identity), ("Forgery", False, "-")]:
            app = root / f"{name}.app"
            binary = app / "Contents/MacOS/Probe"
            binary.parent.mkdir(parents=True)
            main = root / "main.swift"
            main.write_bytes(Path("Tests/SigningProbe.swift").read_bytes().replace(b"import CredentialProtocol\n", b""))
            run(["swiftc", str(main), "Sources/CredentialProtocol/CredentialProtocol.swift", "-o", str(binary)] + (["-D", "UPDATE"] if updated else []))
            with (app / "Contents/Info.plist").open("wb") as file:
                plistlib.dump({"CFBundleExecutable": "Probe", "CFBundleIdentifier": "io.github.calendar-bar", "CFBundlePackageType": "APPL", "CFBundleVersion": "2" if updated else "1"}, file)
            run(["python3", "scripts/credential-service.py", str(app / "Contents/XPCServices")])
            signing = ["codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", signer, "--identifier", "io.github.calendar-bar"]
            if signer != "-":
                signing += ["--keychain", signing_keychain, "--requirements", "=designated => " + requirement]
            run(signing + [str(app)])
            applications.append((app, binary))
        initial, updated, forgery = applications
        assert initial[1].read_bytes() != updated[1].read_bytes()
        helper = initial[0] / "Contents/XPCServices/CalendarCredentials.xpc"
        def cdhash(app, architecture=None):
            result = subprocess.run(["codesign", "--display", "--verbose=4"] + (["--arch", architecture] if architecture else []) + [str(app)], capture_output=True, text=True, check=True)
            return re.search(r"^CDHash=([0-9a-f]+)$", result.stderr, re.MULTILINE).group(1)
        assert cdhash(initial[0]) != cdhash(updated[0])
        assert cdhash(helper) == cdhash(updated[0] / "Contents/XPCServices/CalendarCredentials.xpc")
        print(run([str(initial[1]), "create-legacy", str(keychain), str(helper)]).strip(), flush=True)
        # Only fictional data on a disposable runner simulates the initial human permission.
        result = subprocess.run(["security", "set-generic-password-partition-list", "-S", ",".join("cdhash:" + item for item in [cdhash(initial[0]), cdhash(helper, "arm64"), cdhash(helper, "x86_64")]),
                                 "-a", "google", "-s", "io.github.calendar-bar.credentials", "-k", password, str(keychain)], capture_output=True, timeout=45)
        if result.returncode:
            raise SystemExit("Cannot authorize fictional fixture helper")
        run(["security", "default-keychain", "-d", "user", "-s", str(keychain)])
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain)])
        for binary, operation in [(initial[1], "read"), (initial[1], "read"), (updated[1], "read"),
                                  (forgery[1], "deny-read"), (forgery[1], "deny-save"), (forgery[1], "deny-remove"),
                                  (updated[1], "read"), (updated[1], "save"), (initial[1], "read-updated"), (updated[1], "read-updated"), (updated[1], "remove"), (updated[1], "missing")]:
            print(f"Checking {binary.parent.parent.parent.name}: {operation}", flush=True)
            try:
                print(run([str(binary), operation]).strip(), flush=True)
            except SystemExit:
                for process in subprocess.check_output(["pgrep", "-x", "CalendarCredentials"], text=True).split():
                    diagnostic = subprocess.run(["codesign", "--display", "--verbose=4", process], capture_output=True, text=True)
                    print(diagnostic.stderr, flush=True)
                diagnostic = subprocess.run(["log", "show", "--last", "2m", "--style", "compact", "--predicate", 'process == "securityd" AND eventMessage CONTAINS[c] "partition"'], capture_output=True, text=True)
                print(diagnostic.stdout[-3000:], flush=True)
                raise
        print("11 real XPC and Keychain checks passed with fictional data, differing hosts and the identical signed helper.", flush=True)
    finally:
        run(["security", "default-keychain", "-d", "user", "-s", original_default])
        run(["security", "list-keychains", "-d", "user", "-s", *original_list])
        subprocess.run(["security", "delete-keychain", str(keychain)], capture_output=True, check=True)
