#!/usr/bin/env python3
import base64
import os
from pathlib import Path
import secrets
import shlex
import subprocess
import tempfile


def run(arguments, **kwargs):
    try:
        result = subprocess.run(arguments, capture_output=True, timeout=45, **kwargs)
    except subprocess.TimeoutExpired:
        raise SystemExit(f"Release signing timed out at {Path(arguments[0]).name}; secret output suppressed.")
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
    original_keychains = shlex.split(run(["security", "list-keychains", "-d", "user"]).decode())
    run(["security", "create-keychain", "-p", keychain_password, str(keychain)])
    try:
        run(["security", "set-keychain-settings", "-lut", "3600", str(keychain)])
        run(["security", "unlock-keychain", "-p", keychain_password, str(keychain)])
        run(["security", "import", str(p12), "-k", str(keychain), "-P", archive_password, "-T", "/usr/bin/codesign"])
        run(["security", "set-key-partition-list", "-S", "apple-tool:,codesign:", "-s", "-k", keychain_password, str(keychain)])
        run(["security", "list-keychains", "-d", "user", "-s", str(keychain), *original_keychains])
        print("Signing keychain imported and configured.", flush=True)
        run(["sudo", "security", "add-trusted-cert", "-d", "-r", "trustRoot", "-p", "codeSign", "-k", str(keychain), "Resources/SigningCertificate.pem"])
        print("Code signing certificate registered on disposable runner.", flush=True)
        print(run(["security", "find-identity", "-v", "-p", "codesigning", str(keychain)]).decode(), flush=True)
        certificate = subprocess.check_output([
            "openssl", "x509", "-in", "Resources/SigningCertificate.pem", "-noout", "-fingerprint", "-sha1"
        ], text=True).strip().split("=", 1)[1].replace(":", "")
        environment = dict(os.environ, SIGNING_IDENTITY=certificate, SIGNING_KEYCHAIN=str(keychain))
        subprocess.run(["python3", "scripts/check-signing.py"], env=environment, check=True)
        subprocess.run(["./create-dmg.sh"], env=environment, check=True)
    finally:
        try:
            try:
                result = subprocess.run([
                    "sudo", "security", "remove-trusted-cert", "-d", "Resources/SigningCertificate.pem"
                ], capture_output=True, timeout=10)
                if result.returncode:
                    print("Certificate trust will be discarded with the disposable runner.", flush=True)
            except subprocess.TimeoutExpired:
                print("Certificate trust cleanup did not respond; disposable runner will be discarded.", flush=True)
        finally:
            try:
                run(["security", "list-keychains", "-d", "user", "-s", *original_keychains])
            finally:
                run(["security", "delete-keychain", str(keychain)])
