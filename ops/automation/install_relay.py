"""Run once as root on the existing VPS; relay source supplied beside this file."""
import base64
import hashlib
import json
import os
from pathlib import Path
import pwd
import secrets
import shutil
import subprocess
import http.client
import ssl
import time


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


if os.geteuid() != 0:
    raise SystemExit("Run with sudo")
root = Path("/opt/marketbrain-automation")
state = Path("/var/lib/marketbrain-automation")
unit = Path("/etc/systemd/system/marketbrain-automation.service")
if root.exists() or state.exists() or unit.exists():
    raise SystemExit("Existing installation found. Do not overwrite it; inspect its service first.")
for command in ("openssl", "systemctl", "useradd", "ss", "runuser"):
    if not shutil.which(command):
        raise SystemExit("Missing prerequisite: " + command)
if run("ss", "-H", "-ltn", "sport = :18443").strip():
    raise SystemExit("Port 18443 is occupied")
try:
    pwd.getpwnam("marketbrain-relay")
    raise SystemExit("Account already exists; inspect before installing")
except KeyError:
    pass
run("useradd", "--system", "--no-create-home", "--shell", "/usr/sbin/nologin", "marketbrain-relay")
root.mkdir(mode=0o755)
# mkdir's mode is filtered by the launcher's umask 077. The service must
# traverse this root-owned code directory; secret state remains 0700.
os.chmod(root, 0o755)
state.mkdir(mode=0o700)
shutil.copyfile(Path(__file__).with_name("relay.py"), root / "relay.py")
os.chmod(root / "relay.py", 0o644)
tokens = {role: secrets.token_hex(32) for role in ("controller", "worker")}
(state / "server.json").write_text(json.dumps({role: hashlib.sha256(token.encode()).hexdigest() for role, token in tokens.items()}))
run("openssl", "req", "-x509", "-newkey", "rsa:3072", "-sha256", "-nodes", "-days", "365", "-subj", "/CN=MarketBrain maintenance relay", "-keyout", str(state / "server.key"), "-out", str(state / "server.crt"))
cert = (state / "server.crt").read_text()
der = base64.b64decode("".join(line for line in cert.splitlines() if not line.startswith("---")))
fingerprint = hashlib.sha256(der).hexdigest().upper()
account = pwd.getpwnam("marketbrain-relay")
for path in state.iterdir():
    os.chmod(path, 0o600)
    os.chown(path, account.pw_uid, account.pw_gid)
os.chown(state, account.pw_uid, account.pw_gid)
run("runuser", "-u", "marketbrain-relay", "--", "/usr/bin/python3", "-c",
    "import os; from pathlib import Path; "
    "p=Path('/opt/marketbrain-automation/relay.py'); p.read_bytes(); "
    "assert not os.access(p, os.W_OK); "
    "assert not os.access(p.parent, os.W_OK); "
    "assert os.access('/var/lib/marketbrain-automation', os.R_OK | os.W_OK | os.X_OK)")
unit.write_text('''[Unit]
Description=MarketBrain maintenance job relay
After=network.target
[Service]
User=marketbrain-relay
Group=marketbrain-relay
ExecStart=/usr/bin/python3 /opt/marketbrain-automation/relay.py --directory /var/lib/marketbrain-automation --bind 0.0.0.0
Restart=on-failure
RestartSec=5
UMask=0077
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
ReadWritePaths=/var/lib/marketbrain-automation
MemoryMax=128M
TasksMax=16
[Install]
WantedBy=multi-user.target
''')
run("systemctl", "daemon-reload")
run("systemctl", "enable", "--now", "marketbrain-automation.service")
context = ssl.create_default_context(cafile=str(state / "server.crt"))
context.check_hostname = False  # Verify the installed certificate on loopback.
for attempt in range(10):
    connection = http.client.HTTPSConnection("127.0.0.1", 18443, timeout=2, context=context)
    try:
        connection.request("POST", "/claim", "{}", {"Content-Type": "application/json"})
        if connection.getresponse().status != 403:
            raise RuntimeError("Relay did not reject unauthenticated request")
        time.sleep(2)
        run("systemctl", "is-active", "--quiet", "marketbrain-automation.service")
        break
    except (OSError, RuntimeError, subprocess.CalledProcessError):
        if attempt == 9:
            raise SystemExit("Relay readiness failed. Preserve installation and inspect the service journal.")
        time.sleep(1)
    finally:
        connection.close()
print("Relay installed on TCP 18443. Existing gateway, SSH and firewall configuration unchanged.")
print("Copy each PRIVATE pairing line ONLY to the corresponding laptop. Never share these lines in chat or reports.")
for role, token in tokens.items():
    print(role.upper() + "_PAIRING=" + json.dumps({"role": role, "url": "https://130.250.191.137:18443", "pin": fingerprint, "token": token}, separators=(",", ":")))
print("Pairing tokens are displayed once. The relay retains only their hashes.")
