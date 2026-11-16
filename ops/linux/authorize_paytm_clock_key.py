"""Loaded after clock staging/policy helpers. Authorize one reviewed public key only."""
PUBLIC_KEY = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIB/0obZcN+dR0yxN6IWDvIsk37mxi6VbQfmlacUR/jk4 marketbrain-clock-reader"
KEY_LINE = 'restrict,command="/usr/bin/python3 -I /usr/local/libexec/marketbrain-clock-reader.py" ' + PUBLIC_KEY + "\n"


def authorize_key(expected_reader, run_id):
    watch = time.monotonic()
    report = dict(version=1, runId=run_id, status="REVIEW_REQUIRED", failure=None,
                  rollbackFailure=None, keyInstalled=False, effectivePolicyVerified=False,
                  readerVerified=False, publicKeyReadable=False, passwordLocked=False,
                  rollbackVerified=False, sshReloaded=False, privateKeyTransferred=False,
                  loginTested=False, ordersEnabled=False)
    target = HOME / ".ssh/authorized_keys"
    temp = HOME / (".ssh/.clock-key-" + run_id)
    old_mode = None
    temp_owned = False
    try:
        if os.geteuid() != 0 or not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise RuntimeError("CLOCK_KEY_ROOT_OR_RUN_ID")
        connection = os.environ.get("SSH_CONNECTION", "").split()
        if len(connection) != 4:
            raise RuntimeError("CLOCK_KEY_SSH_CONNECTION_REQUIRED")
        peer, local = str(ipaddress.ip_address(connection[0])), str(ipaddress.ip_address(connection[2]))
        if FINGERPRINT not in run(["/usr/bin/ssh-keygen", "-lf", "/etc/ssh/ssh_host_rsa_key.pub", "-E", "sha256"]).split():
            raise RuntimeError("CLOCK_KEY_HOST_IDENTITY")
        owned_directory(HOME);owned_directory(HOME / ".ssh")
        safe_file(PROGRAM);safe_file(target);safe_file(POLICY_PATH)
        if POLICY_PATH.read_bytes() != POLICY.encode():
            raise RuntimeError("CLOCK_KEY_POLICY_FILE_DRIFT")
        if hashlib.sha256(PROGRAM.read_bytes()).hexdigest() != expected_reader:
            raise RuntimeError("CLOCK_KEY_READER_DRIFT")
        report["readerVerified"] = True
        record = pwd.getpwnam(NAME)
        if record.pw_uid == 0 or record.pw_dir != str(HOME) or record.pw_shell != "/bin/sh":
            raise RuntimeError("CLOCK_KEY_ACCOUNT_DRIFT")
        if run(["/usr/bin/id", "-G", NAME]).split() != [str(record.pw_gid)]:
            raise RuntimeError("CLOCK_KEY_GROUP_DRIFT")
        if run(["/usr/bin/passwd", "-S", NAME]).split()[1] != "L":
            raise RuntimeError("CLOCK_KEY_PASSWORD_NOT_LOCKED")
        report["passwordLocked"] = True
        run(["/usr/sbin/sshd", "-t"])
        actual = effective(NAME, peer, local)
        if any(actual.get(k) != v for k, v in EXPECTED.items()) or actual.get("usepam") != "yes":
            raise RuntimeError("CLOCK_KEY_EFFECTIVE_POLICY_OR_PAM")
        report["effectivePolicyVerified"] = True
        if target.read_bytes():
            raise RuntimeError("CLOCK_KEY_AUTHORIZATION_NOT_EMPTY")
        old_mode = stat.S_IMODE(target.stat().st_mode)
        absent(temp)
        exclusive_file(temp, KEY_LINE.encode(), 0o644)
        temp_owned = True
        safe_file(target)
        if target.read_bytes():
            raise RuntimeError("CLOCK_KEY_CONCURRENT_CHANGE")
        os.replace(temp, target)
        temp_owned = False
        report["keyInstalled"] = True
        if target.read_bytes() != KEY_LINE.encode():
            raise RuntimeError("CLOCK_KEY_WRITTEN_CONTENT")
        safe_file(target)
        # sshd opens authorized_keys as the target user: a root-owned public file needs read permission.
        run(["/usr/sbin/runuser", "-u", NAME, "--", "/usr/bin/test", "-r", str(target)])
        report["publicKeyReadable"] = True
        report["status"] = "CLOCK_PUBLIC_KEY_AUTHORIZED_LOGIN_AND_CUSTODY_PENDING"
    except Exception as error:
        code = str(error)
        report["failure"] = code if re.fullmatch(r"CLOCK_(KEY|POLICY|STAGE)_[A-Z_]+", code) else "CLOCK_KEY_AUTHORIZATION_FAILED"
        if report["keyInstalled"]:
            try:
                safe_file(target)
                if target.read_bytes() != KEY_LINE.encode():
                    raise RuntimeError("CLOCK_KEY_ROLLBACK_DRIFT")
                absent(temp)
                exclusive_file(temp, b"", old_mode)
                temp_owned = True
                os.replace(temp, target)
                temp_owned = False
                report["rollbackVerified"] = target.read_bytes() == b""
            except Exception:
                report["rollbackFailure"] = "CLOCK_KEY_ROLLBACK_REVIEW_REQUIRED"
    finally:
        # Only this run's exact newly written public-key temporary file may be removed.
        if temp_owned and temp.exists():
            try:
                safe_file(temp)
                if temp.read_bytes() not in (KEY_LINE.encode(), b""):
                    raise RuntimeError("drift")
                temp.unlink()
            except Exception:
                report["rollbackFailure"] = "CLOCK_KEY_TEMP_REVIEW_REQUIRED"
    report["elapsedSeconds"] = round(time.monotonic() - watch, 3)
    return report
