"""Loopback-only real Windows OpenSSH regression; requires paramiko in a test venv."""
import argparse
import json
import pathlib
import socket
import subprocess
import tempfile
import threading

import paramiko


class FixtureServer(paramiko.ServerInterface):
    def __init__(self, expected):
        self.expected = expected
        self.executed = threading.Event()

    def get_allowed_auths(self, username):
        return "publickey"

    def check_auth_publickey(self, username, key):
        return (paramiko.AUTH_SUCCESSFUL if username == "marketbrain-health"
                and key == self.expected else paramiko.AUTH_FAILED)

    def check_channel_request(self, kind, chanid):
        return paramiko.OPEN_SUCCEEDED if kind == "session" else paramiko.OPEN_FAILED_ADMINISTRATIVELY_PROHIBITED

    def check_channel_exec_request(self, channel, command):
        if command != b"fixture-clock":
            return False
        self.executed.set()
        return True


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--pwsh", required=True)
    args = parser.parse_args()
    root = pathlib.Path(tempfile.mkdtemp(prefix="clock native path with spaces "))
    host = paramiko.RSAKey.generate(2048)
    user = paramiko.RSAKey.generate(2048)
    wrong = paramiko.RSAKey.generate(2048)
    private = root / "fixture user key"
    user.write_private_key_file(str(private))
    helper = pathlib.Path(__file__).with_name("PaytmClockLogin.ps1").resolve()
    script = root / "invoke fixture.ps1"
    script.write_text('''param($Helper,$Known,$Key,$Port,$Mode)
$ErrorActionPreference='Stop'
. $Helper
# Synthetic fixture key only: native Windows OpenSSH requires a private ACL.
$sid=[Security.Principal.WindowsIdentity]::GetCurrent().User
$acl=[Security.AccessControl.FileSecurity]::new()
$acl.SetAccessRuleProtection($true,$false);$acl.SetOwner($sid)
$acl.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new($sid,'FullControl','Allow'))
[IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Key),$acl)
$a=@(Get-ClockLoginSshArguments $Known $Key)
$a[-1]='marketbrain-health@127.0.0.1'
if($Mode -eq 'old-unquoted'){
 for($i=0;$i -lt $a.Count;$i++){if($a[$i].StartsWith('UserKnownHostsFile=')){$a[$i]='UserKnownHostsFile='+$Known.Replace('\\','/')}}
}
$r=Invoke-ClockLoginNative "$env:WINDIR/System32/OpenSSH/ssh.exe" (@('-p',$Port)+$a+@('fixture-clock')) 15
$r|ConvertTo-Json -Compress
''')
    results = []
    try:
        for mode in ("old-unquoted", "quoted", "wrong-pin"):
            listener = socket.socket()
            listener.bind(("127.0.0.1", 0))
            listener.listen(1)
            listener.settimeout(20)
            port = listener.getsockname()[1]
            known = root / "known hosts"
            selected = wrong if mode == "wrong-pin" else host
            known.write_text(f"[127.0.0.1]:{port} {selected.get_name()} {selected.get_base64()}\n")
            server = FixtureServer(user)
            errors = []

            def serve():
                transport = None
                try:
                    conn, _ = listener.accept()
                    transport = paramiko.Transport(conn)
                    transport.add_server_key(host)
                    transport.start_server(server=server)
                    channel = transport.accept(10)
                    if channel and server.executed.wait(5):
                        channel.sendall(b"FIXTURE_CLOCK_OK\n")
                        channel.send_exit_status(0)
                        channel.close()
                except (EOFError, ConnectionResetError, paramiko.SSHException):
                    pass  # Expected client disconnect on host verification rejection.
                except Exception as exc:
                    errors.append(str(exc))
                finally:
                    if transport:
                        transport.close()
                    listener.close()

            worker = threading.Thread(target=serve, daemon=True)
            worker.start()
            completed = subprocess.run([args.pwsh, "-NoProfile", "-File", str(script),
                                        str(helper), str(known), str(private), str(port), mode],
                                       capture_output=True, text=True, timeout=25)
            worker.join(15)
            assert completed.returncode == 0, completed.stderr
            result = json.loads(completed.stdout)
            if mode == "quoted":
                assert result["exitCode"] == 0 and result["stdout"].strip() == "FIXTURE_CLOCK_OK", result
                assert server.executed.is_set()
            else:
                assert result["exitCode"] == 255 and "Host key verification failed" in result["stderr"], result
                assert not server.executed.is_set()
            assert not worker.is_alive() and not errors, errors
            results.append({"case": mode, "exitCode": result["exitCode"], "passed": True})
        print(json.dumps({"tests": results, "scope": "Loopback only, disposable synthetic keys, real Windows ssh.exe"}))
    finally:
        private.unlink(missing_ok=True)  # Delete only our generated fixture key.


if __name__ == "__main__":
    main()

