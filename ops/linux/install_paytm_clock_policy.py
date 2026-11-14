"""Loaded after the reviewed stage helpers. Installs only a keyless Match-User policy."""
import ipaddress

POLICY_PATH = pathlib.Path("/etc/ssh/sshd_config.d/00-marketbrain-health.conf")
POLICY = """# MarketBrain keyless clock reader
Match User marketbrain-health
    AuthenticationMethods publickey
    PubkeyAuthentication yes
    PasswordAuthentication no
    KbdInteractiveAuthentication no
    HostbasedAuthentication no
    GSSAPIAuthentication no
    AuthorizedKeysFile /var/lib/marketbrain-health/.ssh/authorized_keys
    AuthorizedKeysCommand none
    TrustedUserCAKeys none
    AuthorizedPrincipalsFile none
    AuthorizedPrincipalsCommand none
    ForceCommand /usr/bin/python3 -I /usr/local/libexec/marketbrain-clock-reader.py
    DisableForwarding yes
    AllowAgentForwarding no
    AllowTcpForwarding no
    AllowStreamLocalForwarding no
    PermitTTY no
    PermitTunnel no
    PermitUserRC no
    X11Forwarding no
Match all
"""
EXPECTED = dict(authenticationmethods="publickey", pubkeyauthentication="yes",
                passwordauthentication="no", kbdinteractiveauthentication="no",
                hostbasedauthentication="no", gssapiauthentication="no",
                authorizedkeysfile="/var/lib/marketbrain-health/.ssh/authorized_keys",
                authorizedkeyscommand="none", trustedusercakeys="none", authorizedprincipalsfile="none", authorizedprincipalscommand="none", forcecommand="/usr/bin/python3 -I /usr/local/libexec/marketbrain-clock-reader.py",
                disableforwarding="yes", allowagentforwarding="no", allowtcpforwarding="no",
                allowstreamlocalforwarding="no", permittty="no", permittunnel="no", permituserrc="no", x11forwarding="no")


def effective(user, peer, local):
    text = run(["/usr/sbin/sshd", "-T", "-C", f"user={user},host=localhost,addr={peer},laddr={local},lport=22"])
    values = {}
    for line in text.splitlines():
        key, _, value = line.partition(" ")
        values[key] = value
    return values


def safe_file(path):
    value = path.lstat()
    if not stat.S_ISREG(value.st_mode) or value.st_uid != 0 or value.st_mode & 0o022:
        raise RuntimeError("CLOCK_POLICY_FILE_UNSAFE")


def install_policy(expected_reader, run_id):
    watch = time.monotonic()
    report = dict(version=1, runId=run_id, status="REVIEW_REQUIRED", failure=None,
                  rollbackFailure=None, policyCreated=False, effectivePolicyVerified=False,
                  otherAccountsUnchanged=False, keylessVerified=False, passwordLocked=False,
                  reloaded=False, rollbackVerified=False, sshAccessEnabled=False, ordersEnabled=False)
    before = None
    try:
        if os.geteuid() != 0 or not re.fullmatch(r"[a-f0-9]{32}", run_id):
            raise RuntimeError("CLOCK_POLICY_ROOT_OR_RUN_ID")
        connection = os.environ.get("SSH_CONNECTION", "").split()
        if len(connection) != 4:
            raise RuntimeError("CLOCK_POLICY_SSH_CONNECTION_REQUIRED")
        peer, local = str(ipaddress.ip_address(connection[0])), str(ipaddress.ip_address(connection[2]))
        if FINGERPRINT not in run(["/usr/bin/ssh-keygen", "-lf", "/etc/ssh/ssh_host_rsa_key.pub", "-E", "sha256"]).split():
            raise RuntimeError("CLOCK_POLICY_HOST_IDENTITY")
        owned_directory(HOME);owned_directory(HOME / ".ssh")
        safe_file(PROGRAM);safe_file(HOME / ".ssh/authorized_keys")
        if hashlib.sha256(PROGRAM.read_bytes()).hexdigest() != expected_reader:
            raise RuntimeError("CLOCK_POLICY_READER_DRIFT")
        if (HOME / ".ssh/authorized_keys").read_bytes():
            raise RuntimeError("CLOCK_POLICY_KEYS_ALREADY_PRESENT")
        report["keylessVerified"] = True
        record = pwd.getpwnam(NAME)
        if record.pw_uid == 0 or record.pw_dir != str(HOME) or record.pw_shell != "/bin/sh":
            raise RuntimeError("CLOCK_POLICY_ACCOUNT_DRIFT")
        if run(["/usr/bin/passwd", "-S", NAME]).split()[1] != "L":
            raise RuntimeError("CLOCK_POLICY_PASSWORD_NOT_LOCKED")
        report["passwordLocked"] = True
        absent(POLICY_PATH);owned_directory(POLICY_PATH.parent)
        run(["/usr/sbin/sshd", "-t"])
        before = {u: effective(u, peer, local) for u in ("marketbrain-admin", "marketbrain-gateway", "root")}
        exclusive_file(POLICY_PATH, POLICY.encode(), 0o600)
        report["policyCreated"] = True
        run(["/usr/sbin/sshd", "-t"])
        actual = effective(NAME, peer, local)
        if any(actual.get(k) != v for k, v in EXPECTED.items()):
            raise RuntimeError("CLOCK_POLICY_EFFECTIVE_MISMATCH")
        report["effectivePolicyVerified"] = True
        if any(effective(u, peer, local) != v for u, v in before.items()):
            raise RuntimeError("CLOCK_POLICY_OTHER_ACCOUNT_CHANGED")
        report["otherAccountsUnchanged"] = True
        run(["/usr/bin/systemctl", "reload", "ssh.service"])
        run(["/usr/bin/systemctl", "is-active", "--quiet", "ssh.service"])
        report["reloaded"] = True
        report["status"] = "CLOCK_SSH_POLICY_INSTALLED_KEYLESS_CUSTODY_PENDING"
    except Exception as error:
        code = str(error)
        report["failure"] = code if re.fullmatch(r"CLOCK_(POLICY|STAGE)_[A-Z_]+", code) else "CLOCK_POLICY_FAILED"
        if report["policyCreated"]:
            try:
                safe_file(POLICY_PATH)
                if POLICY_PATH.read_bytes() != POLICY.encode():
                    raise RuntimeError("CLOCK_POLICY_ROLLBACK_DRIFT")
                POLICY_PATH.unlink()  # Only the exact newly created, hash/content-checked file.
                run(["/usr/sbin/sshd", "-t"])
                if any(effective(u, peer, local) != v for u, v in before.items()):
                    raise RuntimeError("CLOCK_POLICY_ROLLBACK_OTHER_DRIFT")
                run(["/usr/bin/systemctl", "reload", "ssh.service"])
                run(["/usr/bin/systemctl", "is-active", "--quiet", "ssh.service"])
                report["rollbackVerified"] = True
            except Exception:
                report["rollbackFailure"] = "CLOCK_POLICY_ROLLBACK_REVIEW_REQUIRED"
    report["elapsedSeconds"] = round(time.monotonic() - watch, 3)
    return report
