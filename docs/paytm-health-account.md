# Windows health-account foundation

E285 accepts actual operator-controlled clock login and invalid-command rejection. This combined next step creates the separate Windows marketbrain-health account and C:\ProgramData\MarketBrainPaytmHealth storage, then launches a bounded probe as that exact SID. It does not import the clock key, copy a health token, install a task, contact the VPS, modify the shared ssh-agent service, or grant broker/order authority.

## Behavior and verification

Run elevated 64-bit PowerShell 7. The accepted login receipt is hash-bound. Preflight checks tools, local membership enumeration, absence of account/storage, running automatic ssh-agent and non-disabled secondary logon. The operator chooses/confirms a new 14+ character Windows account password through SecureString prompts (up to three confirmation attempts). It is never logged or persisted by this script; native Windows account creation receives it as SecureString. Windows password-expiration defaults remain unchanged.

The account starts disabled. Only standard Users membership is allowed. Protected root and manifest are owned by Administrators with SYSTEM/Administrators full access and account read/execute; the separate work directory gives the account Modify. Membership and ACL checks pass before enabling. The short native Windows PowerShell 5.1 bootstrap uses the proven stdin transport, avoiding earlier command-line length errors. A 60-second exact-account probe verifies SID, non-admin token, denied manifest write, work create/read/delete and empty per-account agent. No shared agent start/stop or import occurs. No assumption of scheduled/batch logon rights is made.

Partial failures preserve account/files and report the completed steps and native error code. Do not delete anything or blindly repeat Apply. Verify mode can inspect a fully installed owned account and repeat only the credential/probe check; it does not reset passwords, enable disabled accounts or repair partial storage.

Eight new tests cover health launch/source binding, preserved gateway defaults, successful setup, collision refusal, failed probe evidence, mutation-free Verify and group failure before enable. Existing account suite passes 320 assertions and 26 mocked launcher workflows plus a native wrong-identity probe. These are local checks; real Windows provisioning acceptance requires the spare receipt.

## Spare run

Open PowerShell 7 as Administrator, update clean main, then run:

```powershell
& '.\ops\windows\InstallPaytmHealthAccount.ps1'
```

Create a NEW Windows health-account password and enter it twice when prompted. Keep it in your password manager; do not use the clock-key passphrase or send it in chat. No PuTTY required. Share the one paytm-health-account JSON. Expected HEALTH_ACCOUNT_AND_STORAGE_VERIFIED_KEY_CUSTODY_PENDING.

After acceptance: import only the dedicated encrypted clock key under this exact Windows identity, verify scheduled signing/clock access, provision the restricted health token and worker, then exercise unattended lifecycle acceptance. G3 remains 80%, overall 14/30 (46.7%). No application rebuild or restart is needed here.
