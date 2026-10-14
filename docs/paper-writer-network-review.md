# Targeted paper writer network review

**Captured, E127 (reviewed 2026-10-14):** the 2026-10-13 spare report completed in 15.696s with six source hashes matching Windows CRLF checkout bytes. Both unchanged broad rules map to the Tailscale interface. No configuration changed. Do not repeat this collector merely to pursue phone portal access: the owner uses Telegram only on the phone. External reachability/VPN ACLs remain unproven, and effective-access policy is not marked complete. Next is [isolated Telegram/writer integration](telegram-paper-review-integration.md); real credential activation remains gated. The older next-script text below is historical.

HBA staging is accepted at 100% within its bounded scope (E125): the four writer rules were applied, PostgreSQL reported zero parse errors, and a fresh application connection succeeded. The writer remains NOLOGIN. **Do not rerun Apply, remove the private backup or restart the service for this step.**

The remaining access review concerns two broad firewall allow entries in the saved restriction report. They permit Any program/service, Any protocol/port and Any remote address, limited to particular local IPv4/IPv6 addresses and Domain/Private profiles. The report does not identify the adapters owning those addresses. Do not infer a public exposure, Tailscale ownership or safe exclusion from the address strings alone.

## What the existing evidence establishes

The saved 126-rule candidate set contains 47 specific-program selectors, 77 Any-program selectors with a package restriction, and two Any-program entries without a package restriction. These are inventory counts, not an effective-access verdict. A package is a separate application condition; Any program alone does not mean that a rule permits every application. [Microsoft application-filter documentation](https://learn.microsoft.com/powershell/module/netsecurity/get-netfirewallapplicationfilter).

The two selected rule identities are `{974B68F8-3C84-465F-A460-844587E9EB43}` and `{AD00E124-1653-417F-B894-E01EA777B23E}`. Both were absent from the older baseline; that does not establish when or why they were created. No unrelated rule is approved for deletion or modification.

## The next script

`GetPaperWriterNetworkReview.ps1` verifies the exact accepted staging and restriction reports, then runs a bounded metadata-only child process. It reads the two rules using their real CIM objects and all seven associated filters, maps literal local addresses to interface indices/adapters and connection profiles, reads firewall profile settings, and identifies current PostgreSQL listener processes. It reads the selected rules again to report drift. Missing IDs, addresses, adapters or connection profiles remain findings rather than assumed permissions.

The address mapping uses parsed IPv4/IPv6 equality, not string guesses or hostname resolution. Non-literal selectors require review. Address lookup covers the default network compartment; empty observations do not prove absence from every compartment. [Microsoft IP-address documentation](https://learn.microsoft.com/en-us/powershell/module/nettcpip/get-netipaddress). Hidden adapters are included in the bounded adapter inventory. [Microsoft adapter documentation](https://learn.microsoft.com/en-us/powershell/module/netadapter/get-netadapter).

This is not a new 126-rule scan: it enumerates rule identities twice to handle missing/disabled IDs safely, but queries detailed filters only for the two selected rules. Limits: 2,000 rule identities, two detailed rules, 256 addresses, 128 adapters, 64 connection profiles, three firewall profiles, 2,048 listening rows and 16 port-5432 listeners. The child has a 120-second soft deadline and 150-second process limit with ten-second heartbeat; process shutdown/output draining may add a short cleanup interval. Each checkpoint is at most 2 MiB, with at most five checkpoints. One final report embeds the last valid checkpoint, source hashes, timings and findings. No automatic retry.

No database connection, password prompt, Docker call, network probe, HBA/firewall edit, credential creation, model run or application restart occurs. The only output is one `paper-writer-network-review-*.json`. It contains private network metadata and should be shared privately. Raw provider errors, process command lines, full environment and MAC addresses are excluded. Early import/output-path failures can prevent a report; otherwise caught errors retain the available evidence.

## Run on the spare laptop

Use PowerShell 7 as Administrator under the usual owner account, after a clean fast-forward pull of the reviewed commit. Keep normal services running. No rebuild is needed. The accepted files must remain unchanged at these paths, or supply their actual locations using the two named parameters:

```powershell
$parameters = @{
    StagingReportPath = 'C:\MarketBrainData\Review\paper-writer-hba-stage-20261013-183806-e7f2eb4166c8.json'
    RestrictionReportPath = 'C:\MarketBrainData\Review\paper-writer-restriction-20261013-121046-dbd532c96a9d.json'
}
foreach ($inputFile in $parameters.Values) {
    if (-not (Test-Path -LiteralPath $inputFile -PathType Leaf)) {
        throw "Existing report not found: $inputFile. Locate it; do not rerun staging."
    }
}
& '.\ops\windows\GetPaperWriterNetworkReview.ps1' @parameters
```

Expected collection status: `NETWORK_REVIEW_CAPTURED_ACTIVATION_BLOCKED`. This means the observations were captured, not that the access policy is approved. Share the single printed JSON even on failure. No separate transcript is required.

## Verification and next decision

E126 records 225 offline assertions across 17 collector and seven parent-runner scenarios on PowerShell 5.1 and 7.6.6. Coverage includes no matching rules, one missing rule, disabled/drifting rules, unknown address selectors, missing fields/adapters/profiles, IPv6 normalization, provider errors, limits, bad evidence, malformed/unsafe child reports, timeout and exit failure. Actual Windows network calls are mocked; this does not replace spare verification. Generated report fixtures are removed after success.

This work completes part of the existing access-review findings process; it is not a new percentage denominator. Access review remains 80%, staging is now 100%, and the full paper-first roadmap remains 12.4%. No predictor-performance credit follows.

After review, either retain the rules under the explicitly accepted private topology or propose a narrowly scoped restriction with rollback that preserves intended remote access. Do not alter the rules automatically. A material topology/policy choice requires owner approval. Then prepare real credential custody and positive/negative authentication proof as a separately authorized package; application wiring and money/order operations remain later gates. External reachability, VPN ACLs, proxy/NAT behavior, and third-party firewall enforcement are not proven by this collector.
