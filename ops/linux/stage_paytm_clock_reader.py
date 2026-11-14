#!/usr/bin/python3
"""Stage a locked, keyless VPS clock identity. Does not edit/reload sshd."""
import base64
import hashlib
import json
import os
import pathlib
import pwd
import re
import stat
import subprocess
import time

NAME = "marketbrain-health"
HOME = pathlib.Path("/var/lib/marketbrain-health")
PROGRAM = pathlib.Path("/usr/local/libexec/marketbrain-clock-reader.py")
FINGERPRINT = "SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI"


def run(args, timeout=10):
    result = subprocess.run(args, capture_output=True, text=True, timeout=timeout,
                            env={"PATH": "/usr/sbin:/usr/bin:/sbin:/bin", "LC_ALL": "C"})
    if result.returncode:
        raise RuntimeError("CLOCK_STAGE_NATIVE_FAILED")
    return result.stdout.strip()


def absent(path):
    if path.exists() or path.is_symlink():
        raise RuntimeError("CLOCK_STAGE_PATH_EXISTS")


def owned_directory(path):
    value = path.lstat()
    if not stat.S_ISDIR(value.st_mode) or value.st_uid != 0 or value.st_mode & 0o022:
        raise RuntimeError("CLOCK_STAGE_PARENT_UNSAFE")


def exclusive_file(path, content, mode):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, mode)
    with os.fdopen(fd, "wb") as stream:
        stream.write(content)
        stream.flush()
        os.fsync(stream.fileno())
    os.chmod(path, mode)


def stage(payload, expected_hash, run_id):
    start = time.monotonic()
    report = dict(version=1, runId=run_id, status="REVIEW_REQUIRED", failure=None,
                  accountCreated=False, passwordLocked=False, programVerified=False,
                  allowedCommandVerified=False, deniedCommandVerified=False,
                  keylessVerified=False, sshConfigurationChanged=False,
                  sshAccessEnabled=False, ordersEnabled=False)
    try:
        if os.geteuid() != 0 or not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise RuntimeError("CLOCK_STAGE_ROOT_OR_RUN_ID")
        content = base64.b64decode(payload, validate=True)
        if hashlib.sha256(content).hexdigest() != expected_hash:
            raise RuntimeError("CLOCK_STAGE_PAYLOAD_HASH")
        if FINGERPRINT not in run(["/usr/bin/ssh-keygen", "-lf", "/etc/ssh/ssh_host_rsa_key.pub", "-E", "sha256"]).split():
            raise RuntimeError("CLOCK_STAGE_HOST_IDENTITY")
        try:
            pwd.getpwnam(NAME)
        except KeyError:
            pass
        else:
            raise RuntimeError("CLOCK_STAGE_ACCOUNT_EXISTS")
        absent(HOME)
        absent(PROGRAM)
        owned_directory(HOME.parent)
        owned_directory(PROGRAM.parent.parent)
        if not PROGRAM.parent.exists():
            PROGRAM.parent.mkdir(mode=0o755)
        owned_directory(PROGRAM.parent)
        for tool in ("/usr/bin/python3", "/usr/bin/timedatectl", "/usr/sbin/useradd", "/usr/sbin/runuser"):
            if not os.access(tool, os.X_OK):
                raise RuntimeError("CLOCK_STAGE_TOOL_MISSING")
        run(["/usr/sbin/useradd", "--system", "--user-group", "--no-create-home",
             "--home-dir", str(HOME), "--shell", "/bin/sh", "--password", "!", NAME])
        report["accountCreated"] = True
        HOME.mkdir(mode=0o755)
        (HOME / ".ssh").mkdir(mode=0o755)
        exclusive_file(HOME / ".ssh/authorized_keys", b"", 0o600)
        exclusive_file(PROGRAM, content, 0o755)
        record = pwd.getpwnam(NAME)
        if record.pw_dir != str(HOME) or record.pw_shell != "/bin/sh" or record.pw_uid == 0:
            raise RuntimeError("CLOCK_STAGE_ACCOUNT_CONTRACT")
        if run(["/usr/bin/id", "-G", NAME]).split() != [str(record.pw_gid)]:
            raise RuntimeError("CLOCK_STAGE_GROUPS")
        if run(["/usr/bin/passwd", "-S", NAME]).split()[1] != "L":
            raise RuntimeError("CLOCK_STAGE_PASSWORD_NOT_LOCKED")
        report["passwordLocked"] = True
        if hashlib.sha256(PROGRAM.read_bytes()).hexdigest() != expected_hash:
            raise RuntimeError("CLOCK_STAGE_PROGRAM_DRIFT")
        report["programVerified"] = True
        if (HOME / ".ssh/authorized_keys").stat().st_size != 0:
            raise RuntimeError("CLOCK_STAGE_KEYS_PRESENT")
        report["keylessVerified"] = True
        prefix = ["/usr/sbin/runuser", "-u", NAME, "--", "/usr/bin/env", "-i"]
        output = run(prefix + ["SSH_ORIGINAL_COMMAND=marketbrain-clock " + run_id,
                              "/usr/bin/python3", "-I", str(PROGRAM)], 5)
        if not re.fullmatch(r"MB_CLOCK_V1\|" + run_id + r"\|[0-9]{13}\|(yes|no)", output):
            raise RuntimeError("CLOCK_STAGE_RECEIPT")
        report["allowedCommandVerified"] = True
        denied = subprocess.run(prefix + ["SSH_ORIGINAL_COMMAND=id", "/usr/bin/python3", "-I", str(PROGRAM)],
                                capture_output=True, text=True, timeout=5)
        if denied.returncode != 1 or denied.stdout:
            raise RuntimeError("CLOCK_STAGE_DENIAL")
        report["deniedCommandVerified"] = True
        report["status"] = "CLOCK_READER_STAGED_KEY_AND_SSH_POLICY_PENDING"
    except Exception as error:
        code = str(error)
        report["failure"] = code if re.fullmatch(r"CLOCK_STAGE_[A-Z_]+", code) else "CLOCK_STAGE_FAILED"
    report["elapsedSeconds"] = round(time.monotonic() - start, 3)
    return report
