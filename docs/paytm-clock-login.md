# Clock SSH acceptance

E282 accepts the public-key authorization receipt. E283 records a Windows ssh-keyscan failure before authentication; the corrected controller does not call that scanner. The checked-in paytm-vps-host-rsa.pub is the public RSA key supplied by the operator in the earlier verified-console workflow. Its SHA256 fingerprint is checked by the existing strict RSA parser before connecting; SSH still enforces StrictHostKeyChecking against that key. A different key fails closed. No new trust-on-first-use or server algorithm changes. This next read-only batch verifies the pinned VPS RSA host key, decrypts the dedicated encrypted private key locally through native OpenSSH, requests a nonce-bound clock sample, sends an invalid command and requires the reader rejection (not merely an authentication error), then requests a second valid sample. Both samples must report NTP synchronized. No clock-offset accuracy claim is made from these interactive requests because passphrase entry contributes latency.

The controller checks both accepted receipt hashes and the encrypted key identity. User SSH configuration and agent use are disabled; the known host is fingerprint-pinned. No agent import, server change, key transfer, task installation, application restart or trading authority. Three SSH processes have a 180-second limit each (including passphrase entry), with connection/liveness limits. Each completed native result is checkpointed in one JSON, including failures. The small temporary known_hosts file is public and retained for diagnosis. Tests cover valid reply, wrong nonce, nonzero exit, extra output, actual denial, authentication-error distinction, native output capture and timeout termination. Actual Windows OpenSSH console interaction remains a spare-machine acceptance.

## Run on the spare laptop

Use interactive PowerShell 7 as the same Windows user who generated the clock key. No administrator elevation or PuTTY session is needed. Pull main with a clean working tree, then run:

```powershell
& '.\ops\windows\TestPaytmClockLogin.ps1'
```

At each native prompt enter the passphrase created specifically for marketbrain-clock-reader.openssh, not the Windows password or administrator/gateway key passphrase. It may prompt three times. Do not paste the passphrase into chat. If a prompt does not appear, allow the bounded timeout and share the JSON; do not start simultaneous tests.

Expected: CLOCK_SSH_LOGIN_AND_COMMAND_DENIAL_PASSED_CUSTODY_PENDING. Share the one paytm-clock-login JSON. No existing acceptance test needs rerunning. Next after acceptance: exact-account Windows key custody and unattended collector. G3 remains 80%, overall 14/30 (46.7%), until full checkpoint acceptance.

Six additional regressions cover the real public pin, a mutated key, complete three-request controller success without scanner calls, authentication failure versus command denial, unsynchronized VPS time and rejection before connection on a wrong pin. The original eight native/parser tests and 122 shared custody assertions also passed. These are local tests; actual SSH login and interactive passphrase handling still require the spare run.

## E284 native path regression correction

The supplied E284 report matches 6fc21cc sources and failed before user authentication. The SHA256 check of the public host key passed; native SSH reported no known RSA host key. UserKnownHostsFile is an SSH configuration value accepting multiple paths: passing it as one process argument does not quote spaces within the configuration value. The corrected argument builder quotes this path for SSH, rejects unsupported path/expansion characters, and keeps strict checking and the accepted host pin. Private-key -i remains a separate ProcessStartInfo.ArgumentList argument. No key replacement or server changes.

`test_clock_login_native.py` runs a disposable loopback SSH server with generated RSA host/client keys. It invokes the actual Windows ssh.exe through the production PowerShell argument builder and native runner, using paths containing spaces. Old unquoted configuration reproduces host verification failure; corrected configuration authenticates and executes the fixture command; a different host key fails closed. Fixture private keys are removed afterward. This test requires Paramiko in a temporary local verification virtual environment, not on the spare laptop or in the application. Eight clock tests and six controller tests also pass. Native host-verification/authentication/transport failures now have separate failure codes instead of generic invalid response.

Local test command: `python -B ops/windows/test_clock_login_native.py --pwsh <absolute-pwsh.exe-path>` (with Paramiko installed in that local test environment). No broker or VPS connections are made by this test. Rerun the same TestPaytmClockLogin.ps1 command on the spare laptop; no extra setup, PuTTY, package installation or private-key upload required.
