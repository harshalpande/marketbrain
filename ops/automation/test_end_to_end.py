"""Local-only real TLS/PowerShell integration. No broker, VPS or application calls."""
import argparse
import hashlib
import json
from pathlib import Path
import secrets
import socket
import ssl
import subprocess
import sys
import tempfile
import time

parser = argparse.ArgumentParser()
parser.add_argument("--pwsh", required=True)
parser.add_argument("--openssl", required=True)
parser.add_argument("--test-script", choices=["Test-AutomationClient.ps1", "Test-AutomationQueuedExecution.ps1"], default="Test-AutomationClient.ps1")
args = parser.parse_args()
source = Path(__file__).parent.resolve()
with tempfile.TemporaryDirectory(prefix="marketbrain-automation-test-") as name:
    folder = Path(name)
    subprocess.run([args.openssl, "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=localhost", "-keyout", str(folder / "server.key"), "-out", str(folder / "server.crt")], check=True, capture_output=True)
    der = ssl.PEM_cert_to_DER_cert((folder / "server.crt").read_text())
    client = {"pin": hashlib.sha256(der).hexdigest().upper(), "worker": secrets.token_hex(32), "controller": secrets.token_hex(32)}
    (folder / "client.json").write_text(json.dumps(client))
    (folder / "server.json").write_text(json.dumps({role: hashlib.sha256(client[role].encode()).hexdigest() for role in ("worker", "controller")}))
    # Refuse to exercise an unrelated listener.
    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 18443))
    process = subprocess.Popen([sys.executable, str(source / "relay.py"), "--directory", str(folder)])
    try:
        time.sleep(1)
        if process.poll() is not None:
            raise RuntimeError("Fixture relay did not start")
        subprocess.run([args.pwsh, "-NoProfile", "-File", str(source / args.test_script), "-FixtureDirectory", str(folder)], check=True, timeout=90)
    finally:
        process.terminate()
        process.wait(timeout=10)
