# Dedicated health-account clock-key custody

E286 accepts the Windows health account SID ending 1011, protected storage and exact-account empty agent. This batch imports ONLY the already accepted clock Ed25519 key into that identity's Windows SSH agent. It reuses the established parser, private-file ACL, short credentialed console bootstrap and bounded native process helpers. No gateway contract is overridden and no existing gateway key is imported, removed or enumerated in the report.

## Batch

1. Pin both account and key-preparation receipts; verify current account SID/installation run, memberships and ACLs, running automatic agent and encrypted key identity. Prompt for the existing Windows health-account password. Repeat the empty-agent probe as that account before staging.
2. Create new protected key-custody storage only if absent. Copy reviewed worker code, public key, run manifest and an encrypted private-key copy. Restrict private-file ACL to health read and SYSTEM/Administrators control. Original key remains untouched. Check that the controller account cannot sign with the clock key.
3. Open a visible health-account CLOCK KEY console. Verify exact non-admin SID and empty agent. Import with native hidden passphrase input, verify sole expected agent identity and signing; remove ONLY the clock public key, prove empty agent and failed signing, then reimport with the same passphrase and prove signing again. Each interactive import is bounded to 180 seconds; the overall child window to 480 seconds. No VPS connection is made by this custody stage.
4. Remove only this run's staged encrypted copy after hash and path checks and successful worker receipt. Launch a fresh health-account process: assert no staged private file, exact identity, sole expected agent key and successful signing. Verify controller signing remains denied. Record custody state.

No task, batch-logon permission, service setting, broker access or order authority is created. Windows SSH-agent persistence across reboot is NOT accepted by this test. Scheduled access and lifecycle remain pending. No passwords/private-key content appear in reports. A partial failure preserves staging and key state for review; never blindly rerun or clear all agent identities.

## Run

Open 64-bit PowerShell 7 as Administrator on the spare laptop, pull clean main and run:

```powershell
& '.\ops\windows\InstallPaytmHealthKeyCustody.ps1'
```

In the MAIN window enter the existing Windows marketbrain-health account password created in the previous step. Then switch to the newly opened CLOCK KEY window and enter the clock SSH-key passphrase at both prompts. This is the passphrase for marketbrain-clock-reader.openssh, not a Windows/VPS/gateway password. No PuTTY or Pageant action is required. Do not start a transcript or share key files.

Expected HEALTH_KEY_CUSTODY_PASSED_SCHEDULED_ACCESS_PENDING. Share the ONE paytm-health-key-custody JSON. Original encrypted key remains in its existing protected profile folder. On any failure, keep the report and partial state; no account/key deletion.

## Verification and progress

Thirteen local checks cover successful sequence, wrong SID/admin/plaintext/existing-key refusal, import/sign/revocation/reimport failures, correct bounded child launch, fresh-source guard and script parsing. The existing suite passes 122 shared custody assertions and nine mocked worker sequences. No real key was imported locally; spare acceptance is required. G3 remains 80%, overall14/30 (46.7%). Next: scheduled exact-account clock access, restricted health-token/collector provisioning, combined unattended lifecycle acceptance.
