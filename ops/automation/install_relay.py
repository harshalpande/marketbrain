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


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True).stdout


if os.geteuid() != 0:
    raise SystemExit("Run with sudo")
root = Path("/opt/marketbrain-automation")
state = Path("/var/lib/marketbrain-automation")
unit = Path("/etc/systemd/system/marketbrain-automation.service")
if root.exists() or state.exists() or unit.exists():
    raise SystemExit("Existing installation found. Do not overwrite it; inspect its service first.")
for command in ("openssl", "systemctl", "useradd", "ss"):
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
run("systemctl", "is-active", "--quiet", "marketbrain-automation.service")
print("Relay installed on TCP 18443. Existing gateway, SSH and firewall configuration unchanged.")
print("Copy each PRIVATE pairing line ONLY to the corresponding laptop. Never share these lines in chat or reports.")
for role, token in tokens.items():
    print(role.upper() + "_PAIRING=" + json.dumps({"role": role, "url": "https://130.250.191.137:18443", "pin": fingerprint, "token": token}, separators=(",", ":")))
print("Pairing tokens are displayed once. The relay retains only their hashes.")
