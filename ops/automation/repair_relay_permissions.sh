#!/bin/bash
# Existing installation only. Preserve credentials, certificate and queue.
set -eu
test "$(id -u)" = 0 || { echo 'Run with sudo'; exit 1; }
code=/opt/marketbrain-automation
test -d "$code" && test ! -L "$code"
test -f "$code/relay.py" && test ! -L "$code/relay.py"
test "$(stat -c %u "$code")" = 0
test "$(stat -c %u "$code/relay.py")" = 0
test "$(systemctl show marketbrain-automation.service -p User --value)" = marketbrain-relay
echo 'Before: public program permissions (no credentials printed)'
stat -c '%a %U:%G %n' "$code" "$code/relay.py"
systemctl stop marketbrain-automation.service
chmod 0755 "$code"
chmod 0644 "$code/relay.py"
runuser -u marketbrain-relay -- /usr/bin/python3 -c 'import os; from pathlib import Path; p=Path("/opt/marketbrain-automation/relay.py"); p.read_bytes(); assert not os.access(p,os.W_OK); assert not os.access(p.parent,os.W_OK); print("SERVICE_CODE_READ_OK_NOT_WRITABLE")'
systemctl reset-failed marketbrain-automation.service
systemctl start marketbrain-automation.service
# Verify real TLS and HTTP, not the transient systemctl startup state.
/usr/bin/python3 - <<'PY'
import http.client, ssl, time, subprocess
context = ssl.create_default_context(cafile='/var/lib/marketbrain-automation/server.crt')
context.check_hostname = False  # Trust the exact existing local certificate.
last = None
for attempt in range(10):
    connection = http.client.HTTPSConnection('127.0.0.1', 18443, timeout=2, context=context)
    try:
        connection.request('POST', '/claim', '{}', {'Content-Type': 'application/json'})
        response = connection.getresponse()
        if response.status != 403:
            raise RuntimeError('Unauthenticated request was not denied')
        time.sleep(2)
        subprocess.run(['systemctl', 'is-active', '--quiet', 'marketbrain-automation.service'], check=True)
        print('RELAY_TLS_READY_AUTHENTICATION_REQUIRED')
        break
    except Exception as error:
        last = type(error).__name__
        time.sleep(1)
    finally:
        connection.close()
else:
    raise SystemExit('Relay readiness failed: ' + str(last) + '; inspect service journal, do not reinstall')
PY
systemctl show marketbrain-automation.service -p ActiveState -p SubState -p NRestarts
ss -H -ltn 'sport = :18443'
echo 'REPAIR_COMPLETE: existing pairing and job data retained.'
