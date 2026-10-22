#Requires -Version 5.1
# Native Git Bash parsing/quoting and disposable file-staging checks, NOT real sudo/PTY tests.
param([string]$BashPath=(Join-Path $env:LOCALAPPDATA 'Programs\Git\bin\bash.exe'))
$ErrorActionPreference='Stop'; Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'PaytmTunnelVerification.ps1')
if(-not (Test-Path -LiteralPath $BashPath)){throw 'Provide -BashPath to an existing Git Bash executable'}
function BashCheck([string]$Source,[switch]$SyntaxOnly) {
    $info=New-Object Diagnostics.ProcessStartInfo
    $info.FileName=$BashPath; $info.Arguments=if($SyntaxOnly){'--noprofile --norc -n'}else{'--noprofile --norc -s'}
    $info.UseShellExecute=$false; $info.CreateNoWindow=$true
    $info.RedirectStandardInput=$true; $info.RedirectStandardOutput=$true; $info.RedirectStandardError=$true
    $process=New-Object Diagnostics.Process; $process.StartInfo=$info
    try {
        [void]$process.Start()
        $out=$process.StandardOutput.ReadToEndAsync();$err=$process.StandardError.ReadToEndAsync()
        $process.StandardInput.Write($Source.Replace("`r`n","`n"));$process.StandardInput.Close()
        if(-not $process.WaitForExit(15000)){$process.Kill();[void]$process.WaitForExit(5000);throw 'Native Bash test timed out'}
        [pscustomobject]@{Exit=$process.ExitCode;Out=$out.Result;Err=$err.Result}
    } finally {$process.Dispose()}
}
function UnquoteLauncher([string]$Payload) {
    $prefix='sudo -n env SSH_CONNECTION="$SSH_CONNECTION" bash -c '
    $suffix=" </dev/tty`n"
    if(-not $Payload.StartsWith($prefix) -or -not $Payload.EndsWith($suffix)){throw 'Launcher boundary changed'}
    $Payload.Substring($prefix.Length,$Payload.Length-$prefix.Length-$suffix.Length)
}
$payload=Get-TunnelServerPayload ('a'*32)
Write-Host 'Launcher check 1/5: complete payload syntax'
$result=BashCheck $payload -SyntaxOnly
if($result.Exit -ne 0){throw $result.Err}
$quoted=UnquoteLauncher $payload
Write-Host 'Launcher check 2/5: native shell quote round-trip'
$result=BashCheck ("printf '%s' "+$quoted+"`n")
$escape="'"+'"'+"'"+'"'+"'"
$decoded=$quoted.Substring(1,$quoted.Length-2).Replace($escape,"'")
if($result.Exit -ne 0 -or $result.Out -cne $decoded){throw 'Native shell quoting changed the staging script'}

# No privilege escalation. Mock only id/SUDO_USER to reach the actual non-TTY guard.
$prefix="id() { printf '0\n'; }`nexport SUDO_USER=marketbrain-admin`n"
Write-Host 'Launcher check 3/5: non-terminal refusal'
$result=BashCheck ($prefix+$decoded)
if($result.Exit -eq 0 -or $result.Err -notmatch 'stdin must be the PuTTY terminal' -or $result.Out.Contains('Private script verified')){throw 'Non-terminal execution was not refused before staging'}

# Actual mktemp/cat/hash/chmod/bash execution of a harmless fixture, under a disposable
# directory. Terminal presence/redirection is explicitly substituted in these two tests.
$body="printf '%s\n' 'fixture-output'`nexit 7`n"
$fixtureQuote=UnquoteLauncher (New-TunnelFileLauncher $body)
$fixture=$fixtureQuote.Substring(1,$fixtureQuote.Length-2).Replace($escape,"'")
$fixture=$fixture.Replace('[ -t 0 ]','true').Replace('</dev/tty','</dev/null').Replace('mktemp -d /tmp/marketbrain-tunnel-script-XXXXXXXX','mktemp -d "$mb_fixture_root/stage-XXXXXXXX"')
$setup=@'
mb_fixture_root=$(mktemp -d)
cleanup_fixture() {
    case "${mb_script_dir:-}" in
        "$mb_fixture_root"/stage-*)
            rm -f -- "$mb_script_dir/window.sh"
            rmdir -- "$mb_script_dir" ;;
    esac
    rmdir -- "$mb_fixture_root"
}
trap cleanup_fixture EXIT
'@
Write-Host 'Launcher check 4/5: staged harmless file and exit-code preservation'
$result=BashCheck ($prefix+$setup+"`n"+$fixture)
if($result.Exit -ne 7 -or $result.Out -notmatch '(?m)^fixture-output\r?$' -or $result.Err){throw "Staged fixture/cleanup failed: $($result.Err)"}
Write-Host 'Launcher check 5/5: checksum rejection'
$result=BashCheck ($prefix+$setup+"`n"+$fixture.Replace("'fixture-output'","'fixture-tampered'"))
if($result.Exit -eq 0 -or $result.Exit -eq 7 -or $result.Out.Contains('Private script verified') -or $result.Out.Contains('fixture-tampered')){throw 'Corrupted staged bytes were executed'}
Write-Host 'PASS: 5 native Bash launcher checks (syntax, exact quoting, non-TTY refusal, staged fixture, hash mismatch). No actual sudo, SSH or VPS operation.'
