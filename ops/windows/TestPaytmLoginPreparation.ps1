#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$OutputDirectory = 'C:\MarketBrainData\Review',
    [string]$JavaBinDirectory,
    [ValidateRange(10,300)][int]$TimeoutSeconds = 120
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'NumericalEvaluationEngineering.ps1')
$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$id = [guid]::NewGuid().ToString('N')
$timer = [Diagnostics.Stopwatch]::StartNew()
$work = $null
$workCreated = $false
$report = [ordered]@{
    version='PAYTM_LOGIN_PREPARATION_V1'; runId=$id; status='RUNNING'
    createdAtUtc=[DateTime]::UtcNow.ToString('o'); elapsedSeconds=0
    powerShellVersion=$PSVersionTable.PSVersion.ToString()
    scope='NATIVE_SYNTHETIC_CORE_ONLY'; springHttpTestsRunHere=$false
    providerCallsPerformed=$false; realAuthenticationPerformed=$false
    applicationRestarted=$false; databaseWritesPerformed=$false; ordersCreated=0
    manifest=[ordered]@{}; events=@(); steps=@(); result=$null; failure=$null; cleanupFailure=$null
}
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$path = Join-Path (Resolve-Path -LiteralPath $OutputDirectory).Path ('paytm-login-preparation-{0}-{1}.json' -f (Get-Date -Format 'yyyyMMdd-HHmmss'),$id.Substring(0,12))
if ($path.Length + 41 -ge 260 -or (Test-Path -LiteralPath $path)) { throw 'Choose a shorter, unique evidence path.' }
function Save-Report { $report.elapsedSeconds=$timer.Elapsed.TotalSeconds; Save-NumericalHistoryReport $report $path -Compact }
function Progress([int]$Percent, [string]$Detail) {
    Write-Host "[$Percent%] $Detail"
    Write-Progress -Activity 'Paytm synthetic login preparation' -PercentComplete $Percent -Status $Detail
    $report.events += @{percent=$Percent; detail=$Detail; atUtc=[DateTime]::UtcNow.ToString('o')}
    Save-Report
}
function Run([string]$Stage, [string]$Executable, [string[]]$Arguments) {
    $r = Invoke-EvaluationProcess $Executable $Arguments $TimeoutSeconds
    $report.steps += @{stage=$Stage; process=$r}; Save-Report
    if ($r.timedOut -or $r.exitCode -ne 0) { throw "Stage failed: $Stage. See embedded output; no automatic retry." }
    return $r
}
try {
    Progress 0 'Synthetic core checks only. No keys, VPS, Docker, database or running application required.'
    $revision = Run 'revision' 'git' @('-C',$root,'rev-parse','HEAD')
    $report.manifest.revision=$revision.stdout.Trim()
    $core = 'marketbrain-service/src/main/java/in/marketbrain/marketdata/paytm/PaytmLoginPreparation.java'
    $verifier = 'marketbrain-service/src/test/java/in/marketbrain/marketdata/paytm/PaytmLoginPreparationVerification.java'
    $files = @($core,$verifier,
        'marketbrain-service/src/main/java/in/marketbrain/marketdata/paytm/PaytmCallbackRehearsalController.java',
        'marketbrain-service/src/test/java/in/marketbrain/marketdata/paytm/PaytmLoginPreparationTest.java',
        'marketbrain-service/src/test/java/in/marketbrain/marketdata/paytm/PaytmCallbackRehearsalControllerTest.java',
        'ops/windows/TestPaytmLoginPreparation.ps1','ops/windows/NumericalEvaluationEngineering.ps1',
        'ops/windows/NumericalHistoryEvidence.ps1')
    foreach ($file in $files) { $report.manifest[$file]=(Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash }
    if (-not $JavaBinDirectory) {
        $compiler = Get-Command javac.exe -CommandType Application -ErrorAction Stop | Select-Object -First 1
        $JavaBinDirectory = Split-Path -Parent $compiler.Source
    }
    $java = Join-Path $JavaBinDirectory 'java.exe'
    $javac = Join-Path $JavaBinDirectory 'javac.exe'
    if (-not (Test-Path -LiteralPath $java -PathType Leaf) -or -not (Test-Path -LiteralPath $javac -PathType Leaf)) {
        throw 'JDK 21+ java.exe and javac.exe are required in the same bin directory. No automatic installation.'
    }
    $version = Run 'jdk-version' $javac @('-version')
    if (($version.stdout + $version.stderr) -notmatch 'javac\s+(\d+)' -or [int]$Matches[1] -lt 21) { throw 'JDK 21+ is required.' }
    $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $work = Join-Path $tempRoot ('marketbrain-paytm-test-' + $id)
    if (Test-Path -LiteralPath $work) { throw 'Refusing to reuse a temporary class directory.' }
    New-Item -ItemType Directory -Path $work | Out-Null
    $workCreated = $true
    Progress 25 'Compiling only the dependency-free login guard and synthetic verifier using JDK 21 compatibility.'
    $null = Run 'compile' $javac @('-J-Xmx256m','-encoding','UTF-8','--release','21','-d',$work,(Join-Path $root $core),(Join-Path $root $verifier))
    Progress 55 'Testing expiry, wrong browser, replay, malformed input, restart and concurrent callbacks.'
    $run = Run 'synthetic-checks' $java @('-Xmx128m','-cp',$work,'in.marketbrain.marketdata.paytm.PaytmLoginPreparationVerification','--synthetic-only')
    $report.result = $run.stdout | ConvertFrom-Json
    Save-Report
    $expected = @('challenge_entropy_shape_and_redaction','fixed_https_login_origin',
        'invalid_login_key_2','invalid_login_key_3','invalid_login_key_4','invalid_login_key_5','invalid_login_key_6',
        'invalid_login_state','valid_then_replay_denied','wrong_browser_does_not_consume_valid_challenge',
        'missing_browser_denied','unknown_state_denied','expiry_boundary_denied','before_expiry_allowed',
        'clock_rollback_denied','restart_invalidates_challenges','bounded_capacity_and_expired_cleanup',
        'malformed_query_0','malformed_query_1','malformed_query_2','malformed_query_3','malformed_query_4',
        'malformed_query_5','malformed_query_6','malformed_query_7','malformed_query_8','malformed_query_9',
        'malformed_query_10','malformed_query_11','null_query_denied',
        'invalid_token_30','invalid_token_31','invalid_token_32','invalid_token_33','invalid_token_34',
        'duplicate_token_denied','encoded_key_and_reversed_order','concurrent_callback_has_one_winner')
    Progress 85 'Checking exact test identities, outcomes, timings and unchanged source hashes.'
    $r=$report.result
    if ($r.version -cne 'PAYTM_LOGIN_CORE_V1' -or $r.syntheticOnly -isnot [bool] -or -not $r.syntheticOnly -or
        ($r.checkCount -isnot [int] -and $r.checkCount -isnot [long]) -or
        ($r.failedCheckCount -isnot [int] -and $r.failedCheckCount -isnot [long]) -or
        $r.checkCount -ne 38 -or $r.failedCheckCount -ne 0 -or @($r.checks).Count -ne 38) { throw 'Unexpected synthetic report contract.' }
    $seen=@{}
    foreach ($check in $r.checks) {
        if ($expected -cnotcontains $check.name -or $seen.ContainsKey($check.name) -or
            $check.passed -isnot [bool] -or -not $check.passed -or
            ($check.elapsedNanos -isnot [long] -and $check.elapsedNanos -isnot [int]) -or $check.elapsedNanos -lt 0) {
            throw 'Missing, duplicate, failed or malformed check.'
        }
        $seen[$check.name]=$true
    }
    foreach ($file in $files) {
        if ((Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash -cne $report.manifest[$file]) { throw 'Source changed during verification.' }
    }
    $report.status='SYNTHETIC_CORE_PASSED_REAL_AUTHENTICATION_BLOCKED'
    Progress 100 'Core rehearsal passed. Spring HTTP checks are local evidence; real login, gateway and quotes remain unverified.'
} catch {
    $report.status='FAILED'; $report.failure=$_.Exception.Message
} finally {
    if ($report.status -eq 'RUNNING') { $report.status='INTERRUPTED'; $report.failure='Interrupted before completion.' }
    # Only this invocation's generated class files; never touch application or existing evidence directories.
    if ($workCreated -and $work -and (Test-Path -LiteralPath $work)) {
        try {
            $resolved=(Resolve-Path -LiteralPath $work).Path
            $expectedWork=[IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-paytm-test-' + $id)))
            if ($resolved -cne $expectedWork -or (Get-Item -LiteralPath $work).Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Temporary directory identity changed; retained for review.'
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        } catch { $report.cleanupFailure=$_.Exception.Message }
    }
    $timer.Stop(); Save-Report
    Write-Progress -Activity 'Paytm synthetic login preparation' -Completed
    Write-Progress -Activity 'Numerical evaluation engineering' -Completed
    Write-Host ('{0}; elapsed={1:N2}s' -f $report.status,$timer.Elapsed.TotalSeconds)
    if ($report.cleanupFailure) { Write-Warning 'Temporary classes were retained; see cleanupFailure in the report.' }
    Write-Host "Share this ONE file: $path"
}
if ($report.status -ne 'SYNTHETIC_CORE_PASSED_REAL_AUTHENTICATION_BLOCKED') { throw $report.failure }
