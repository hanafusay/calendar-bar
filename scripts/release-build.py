#!/usr/bin/env python3
import base64
import os
from pathlib import Path
import secrets
import subprocess
import tempfile


def run(arguments, **kwargs):
    result = subprocess.run(arguments, capture_output=True, **kwargs)
    if result.returncode:
        raise SystemExit(f"Release signing failed at {Path(arguments[0]).name}; secret output suppressed.")
    return result.stdout


archive = os.environ.pop("CALENDAR_SIGNING_P12")
archive_password = os.environ.pop("CALENDAR_SIGNING_PASSWORD")
with tempfile.TemporaryDirectory(prefix="calendar-release-") as directory:
    root = Path(directory)
    os.chmod(root, 0o700)
    p12 = root / "identity.p12"
    p12.write_bytes(base64.b64decode(archive, validate=True))
    os.chmod(p12, 0o600)
    keychain = root / "signing.keychain-db"
    keychain_password = secrets.token_urlsafe(40)
    run(["security", "create-keychain", "-p", keychain_password, str(keychain)])
    try:
        run(["security", "set-keychain-settings", "-lut", "3600", str(keychain)])
        run(["security", "unlock-keychain", "-p", keychain_password, str(keychain)])
        run(["security", "import", str(p12), "-k", str(keychain), "-P", archive_password, "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,codesign:", "-s", "-k", keychain_password, str(keychain)])
        run(["sudo", "security", "add-trusted-cert", "-d", "-r", "trustRoot", "-p", "codeSign", "-a", "/usr/bin/codesign", "-k", str(keychain), "Resources/SigningCertificate.pem"])
        certificate = subprocess.check_output([
            "openssl", "x509", "-in", "Resources/SigningCertificate.pem", "-noout", "-fingerprint", "-sha1"
        ], text=True).strip().split("=", 1)[1].replace(":", "")
        environment = dict(os.environ, SIGNING_IDENTITY=certificate, SIGNING_KEYCHAIN=str(keychain))
        subprocess.run(["python3", "scripts/check-signing.py"], env=environment, check=True)
        subprocess.run(["./create-dmg.sh"], env=environment, check=True)
    finally:
        try:
            run(["sudo", "security", "remove-trusted-cert", "-d", "Resources/SigningCertificate.pem"])
        finally:
            run(["security", "delete-keychain", str(keychain)])
