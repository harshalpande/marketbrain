# Gateway key custody: next checkpoint G2.3

## Status and purpose — 2026-10-26

E194 accepts the dedicated Windows account and real credentialed storage/empty-agent probe. G2 is now40%; do not rerun Apply, Recover, inventory or maintenance. Preserve the recovered account and archived old folder. No private SSH key is loaded yet.

The next batch must let the **restricted Windows gateway account**, not the administrator or an interactive Pageant session, authenticate with the **existing restricted VPS gateway key**. This is transport identity only, not a Paytm API secret or database-writer password. G2.3 remains pending; this document is the implementation/acceptance plan, not an import script or evidence that custody works.

## Input needed before the import handoff

Confirm only whether the owner has:

- The encrypted PuTTY `.ppk` only; or
- Also a passphrase-protected OpenSSH private-key export of that same gateway identity.

Do not share either file, its contents, passphrase or screenshot of private material. Do not generate a new identity or use the administrator PPK. Do not export a key without a passphrase or load it into the normal Windows administrator's agent. No key conversion/import command is released until the format and private staging workflow are resolved.

Public identity must match `ops/keys/paytm-gateway.pub`: **SHA256:fRekz3jjaYJxnK5dDXMzq9mDEB4Z3BEHhjfNJCx07UI**. VPS host identity remains the separately verified RSA pin **SHA256:YTQ8GV8J4qOQkY4j3dGGyCTAzyR2iX/KSJoGK0p2dKI**. These pins serve different purposes and are not interchangeable.

PuTTYgen supports exporting an existing private key to OpenSSH format, retaining passphrase protection. This is a file-format conversion, not a new server identity. See the [official PuTTY key-conversion documentation](https://www.puttyssh.org/0.83/htmldoc/Chapter8.html). Microsoft describes account-context agent storage and `ssh-add` in its [Windows OpenSSH key-management guide](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement). These capabilities do not prove this laptop's custody, scheduled execution or reboot behavior; those require actual tests.

## Planned combined implementation and verification

| Area | Required check / boundary |
|---|---|
| Identity | Revalidate accepted account SID, non-admin membership and protected storage. Never recreate/reset the account. |
| Encrypted input | Validate supported format, encryption and exact public identity before loading; reject plaintext or the administrator/wrong key. Never log private material. |
| One-time provisioning | Explicit owner consent; protected staging; import under the exact gateway account with private interactive passphrase entry. Keep passphrase out of commands/environment/reports. Preserve the encrypted offline backup. |
| Custody | Verify the expected identity only and actual signing ability in the gateway account; unexpected agent identities block the workflow without clearing unrelated keys. Test an unrelated standard-user boundary without claiming protection against a trusted machine administrator. |
| Restricted SSH authentication | Strict host pin, public-key-only authentication, no forwarding of the agent, no shell/PTY, no broad listener or direct Paytm route. Bounded connection/negative tests with owned-process cleanup. No proxy service activation as an incidental action. |
| Failure and revocation | Wrong input, bad passphrase, missing agent, wrong host/key and partial import captured safely. Removal must target only the exact approved key with explicit scope; never `ssh-add -D` or broad service resets. |
| Evidence | One compact JSON containing stage results, timings, public fingerprints and safe error codes; no private-key/passphrase/raw key-list data. |

Acceptance closes G2.3 only after reviewed protected custody and pinned restricted authentication evidence, raising G2 from40% to60%. Engineering tests alone do not close it. Actual reboot/logoff, supervised startup, managed VPS lifecycle and installed-system recovery remain separate checkpoints; do not promise indefinite unattended key persistence before testing.

No broker login, quote entitlement, Telegram approval or order authority follows from loading this key. The next downstream stages remain supervisor/task setup, managed proxy lifecycle, real recovery acceptance, then Paytm login and quotes. Live trades remain disabled while returning to paper-account integration.
