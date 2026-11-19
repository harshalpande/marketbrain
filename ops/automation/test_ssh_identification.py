"""Loopback-only SSH identification checks; no VPS, credentials or broker calls."""
import argparse
import json
from pathlib import Path
import socket
import subprocess
import tempfile
import threading
import time

parser = argparse.ArgumentParser()
parser.add_argument('--pwsh', required=True)
args = parser.parse_args()
source = Path(__file__).resolve().parent / 'Automation.Diagnostics.ps1'
cases = [
    ('identification', [b'SSH-2.0-fixture PRIVATE_TEXT\r\n'], 'SSH_IDENTIFICATION_RECEIVED'),
    ('fragmented', [b'Notice PRIVATE_TEXT\r\nSSH-', b'2.0-fixture\r\n'], 'SSH_IDENTIFICATION_RECEIVED'),
    ('closed', [], 'CLOSED_BEFORE_IDENTIFICATION'),
    ('silent', None, 'IDENTIFICATION_TIMEOUT'),
    ('oversize', [b'X' * 1024], 'IDENTIFICATION_BYTE_LIMIT'),
    ('invalid', [b'SSH-9.0-PRIVATE_TEXT\r\n'], 'INVALID_OR_UNSUPPORTED_IDENTIFICATION'),
]
with tempfile.TemporaryDirectory() as folder:
    script = Path(folder) / 'probe.ps1'
    script.write_text("param($Source,[int]$Port)\n. $Source\nInvoke-AutomationSshIdentification -Address 127.0.0.1 -Port $Port -DeadlineMilliseconds 500 | ConvertTo-Json -Compress\n")
    for name, chunks, expected in cases:
        listener = socket.socket()
        listener.bind(('127.0.0.1', 0))
        listener.listen(1)
        listener.settimeout(15)
        port = listener.getsockname()[1]
        errors = []
        def serve():
            try:
                with listener:
                    conn, _ = listener.accept()
                    with conn:
                        if chunks is None:
                            time.sleep(1)
                        else:
                            for chunk in chunks:
                                conn.sendall(chunk)
                                time.sleep(0.02)
                        conn.settimeout(2)
                        assert conn.recv(1024) == b'', 'Client sent protocol/authentication data'
            except Exception as exc:
                errors.append(str(exc))
        # The closed case must close immediately instead of waiting on the reader.
        if name == 'closed':
            def serve():
                try:
                    with listener:
                        conn, _ = listener.accept()
                        conn.close()
                except Exception as exc:
                    errors.append(str(exc))
        worker = threading.Thread(target=serve)
        worker.start()
        result = subprocess.run([args.pwsh, '-NoProfile', '-File', str(script), '-Source', str(source), '-Port', str(port)], capture_output=True, text=True, timeout=20)
        worker.join(5)
        assert result.returncode == 0, result.stderr
        data = json.loads(result.stdout)
        assert data['outcome'] == expected, (name, data)
        assert data['elapsedMilliseconds'] < 2500, data
        assert data['authenticationAttempted'] is False and data['hostIdentityVerified'] is False
        assert 'PRIVATE_TEXT' not in result.stdout
        assert not errors and not worker.is_alive(), (name, errors)
        print('PASS:', name)
print('PASS: bounded identification collection without client data or raw server text')
