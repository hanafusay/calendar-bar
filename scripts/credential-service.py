#!/usr/bin/env python3
import hashlib
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile

name = "CalendarCredentials.xpc"
archive = Path("Resources/CalendarCredentials-v1.tar.gz")
checksum = archive.with_suffix(archive.suffix + ".sha256")
certificate = subprocess.check_output([
    "openssl", "x509", "-in", "Resources/SigningCertificate.pem", "-noout", "-fingerprint", "-sha1"
], text=True).strip().split("=", 1)[1].replace(":", "").lower()
requirement = f'identifier "io.github.calendar-bar.credentials-service" and certificate leaf = H"{certificate}"'

if sys.argv[1] == "build":
    if os.environ.get("RUNNER_ENVIRONMENT") != "github-hosted":
        raise SystemExit("Bootstrap signing requires a disposable GitHub-hosted runner.")
    subprocess.run(["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64", "--product", "CalendarCredentials"], check=True)
    binary_directory = subprocess.check_output(["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64", "--show-bin-path"], text=True).strip()
    with tempfile.TemporaryDirectory() as directory:
        bundle = Path(directory) / name
        (bundle / "Contents/MacOS").mkdir(parents=True)
        shutil.copy2(Path(binary_directory) / "CalendarCredentials", bundle / "Contents/MacOS/CalendarCredentials")
        shutil.copy2("Resources/CredentialService-Info.plist", bundle / "Contents/Info.plist")
        subprocess.run(["codesign", "--force", "--options", "runtime", "--timestamp=none", "--sign", os.environ["SIGNING_IDENTITY"],
                        "--keychain", os.environ["SIGNING_KEYCHAIN"], "--requirements", "=designated => " + requirement, str(bundle)], check=True)
        archive.parent.mkdir(exist_ok=True)
        with tarfile.open(archive, "w:gz") as file:
            file.add(bundle, arcname=name)
    checksum.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + "\n")
    Path("dist").mkdir(exist_ok=True)
    shutil.copy2(archive, Path("dist") / archive.name)
    shutil.copy2(checksum, Path("dist") / checksum.name)
else:
    if not archive.exists() or not checksum.exists():
        raise SystemExit("Frozen credential service archive missing; bootstrap and review it before packaging.")
    if hashlib.sha256(archive.read_bytes()).hexdigest() != checksum.read_text().strip():
        raise SystemExit("Frozen credential service checksum mismatch.")
    destination = Path(sys.argv[1])
    destination.mkdir(parents=True, exist_ok=True)
    with tarfile.open(archive) as file:
        for member in file.getmembers():
            path = Path(member.name)
            if path.is_absolute() or ".." in path.parts or path.parts[0] != name or not (member.isfile() or member.isdir()):
                raise SystemExit("Unexpected credential service archive entry.")
        file.extractall(destination)
    subprocess.run(["codesign", "--verify", "--deep", "--strict", "--test-requirement", "=" + requirement, str(destination / name)], check=True)
