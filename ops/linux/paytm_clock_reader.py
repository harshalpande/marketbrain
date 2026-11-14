#!/usr/bin/python3
"""Forced-command candidate: fixed read-only clock operation; no shell execution."""
import os
import re
import subprocess
import sys
import time


def read_clock(command, run=subprocess.run, now=time.time_ns):
    match = re.fullmatch(r"marketbrain-clock ([a-f0-9]{32})", command)
    if not match:
        raise ValueError("CLOCK_COMMAND_DENIED")
    result = run(["/usr/bin/timedatectl", "show", "-p", "NTPSynchronized", "--value"],
                 capture_output=True, text=True, timeout=2, check=False,
                 env={"PATH": "/usr/bin:/bin", "LC_ALL": "C"})
    status = result.stdout.strip()
    if result.returncode or status not in ("yes", "no"):
        raise ValueError("CLOCK_SYNC_QUERY_FAILED")
    millis = now() // 1_000_000
    if not 1_000_000_000_000 <= millis < 10_000_000_000_000:
        raise ValueError("CLOCK_TIME_RANGE")
    return f"MB_CLOCK_V1|{match[1]}|{millis}|{status}"


if __name__ == "__main__":
    try:
        print(read_clock(os.environ.get("SSH_ORIGINAL_COMMAND", "")))
    except Exception:
        print("CLOCK_READ_DENIED_OR_UNAVAILABLE", file=sys.stderr)
        sys.exit(1)
