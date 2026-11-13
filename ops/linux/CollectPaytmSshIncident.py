"""Read-only historical SSH metadata. No raw journal messages leave this process."""
import base64
import datetime as dt
import json
import re
import subprocess

SINCE = "2026-11-13 13:30:00 UTC"
UNTIL = "2026-11-13 13:35:00 UTC"
LIMIT = 2000


def summarize(rows):
    gateway_pids = {str(r.get("_PID", "")) for r in rows
                    if "marketbrain-gateway" in str(r.get("MESSAGE", ""))}
    gateway_pids.discard("")
    events = []
    throttling = 0
    for row in rows:
        message = str(row.get("MESSAGE", ""))
        pid = str(row.get("_PID", ""))
        throttle = bool(re.search(r"maxstartups|throttl|drop connection|penalt", message, re.I))
        throttling += int(throttle)
        if pid not in gateway_pids and not throttle:
            continue
        kind = "OTHER_RELATED_EVENT"
        for pattern, label in (
            (r"Accepted publickey for marketbrain-gateway", "GATEWAY_KEY_ACCEPTED"),
            (r"session opened", "SESSION_OPENED"),
            (r"session closed", "SESSION_CLOSED"),
            (r"disconnect|connection closed|connection reset|broken pipe", "DISCONNECTED"),
            (r"timed out|timeout", "TIMEOUT"),
            (r"forward.*(denied|refused)|administratively prohibited", "FORWARD_DENIED"),
        ):
            if re.search(pattern, message, re.I):
                kind = label
                break
        if throttle:
            kind = "THROTTLE_OR_PENALTY_EVENT"
        timestamp = int(row["__REALTIME_TIMESTAMP"])
        event = {"serverUtc": dt.datetime.fromtimestamp(timestamp / 1e6, dt.timezone.utc).isoformat(),
                 "serverPid": int(pid) if pid.isdigit() else None, "kind": kind,
                 "gatewayPidRelated": pid in gateway_pids}
        # Retain only gateway connection tuples, never unrelated scanners' addresses or messages.
        if pid in gateway_pids:
            match = re.search(r"(?:from|for|by) (\d{1,3}(?:\.\d{1,3}){3}) port (\d+)", message)
            if match:
                event.update(clientAddress=match[1], clientPort=int(match[2]))
        events.append(event)
    return {"gatewayProcessIds": sorted(gateway_pids), "events": events,
            "throttleOrPenaltyEventCount": throttling}


def collect():
    report = {"version": 1, "kind": "PAYTM_SSH_INCIDENT_V1", "since": SINCE, "until": UNTIL,
              "readOnly": True, "success": False, "historicalCauseEstablished": False,
              "clockSynchronizationVerified": False}
    try:
        result = subprocess.run(["journalctl", "-u", "ssh.service", "--since", SINCE,
                                 "--until", UNTIL, "--utc", "--no-pager", "-o", "json",
                                 "-n", str(LIMIT + 1)], capture_output=True, text=True, timeout=20)
        report["journalExitCode"] = result.returncode
        if result.returncode != 0:
            raise RuntimeError("JOURNAL_QUERY_FAILED")
        if len(result.stdout) > 8_000_000:
            raise RuntimeError("JOURNAL_OUTPUT_OVERSIZE")
        rows = [json.loads(line) for line in result.stdout.splitlines() if line.strip()]
        report.update(rowCount=len(rows), possiblyTruncated=len(rows) > LIMIT)
        report.update(summarize(rows))
        report["success"] = bool(rows) and len(rows) <= LIMIT
        if not report["success"]:
            report["failure"] = "JOURNAL_EMPTY_OR_TRUNCATED"
    except Exception as exc:
        report["failureType"] = type(exc).__name__
    report["capturedServerUtc"] = dt.datetime.now(dt.timezone.utc).isoformat()
    return report


if __name__ == "__main__":
    encoded = base64.b64encode(json.dumps(collect(), separators=(",", ":")).encode()).decode()
    print("BEGIN_PAYTM_SSH_INCIDENT")
    for offset in range(0, len(encoded), 100):
        print(encoded[offset:offset + 100])
    print("END_PAYTM_SSH_INCIDENT")
