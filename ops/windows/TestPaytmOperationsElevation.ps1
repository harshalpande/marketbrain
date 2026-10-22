#Requires -Version 5.1
# Offline only: Start-Process is mocked; no UAC, resync, VPS or service actions.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmOperationsElevation.ps1')
$script:checks=0
function Check([bool]$Value,[string]$Label){if(-not $Value){throw "FAIL: $Label"};$script:checks++}
function Reject([scriptblock]$Action,[string]$Expected){
    $message='';try{& $Action | Out-Null}catch{$message=$_.Exception.Message}
    Check ($message.StartsWith($Expected)) $Expected
}
$script:launches=@();$script:mode='pass'
function Start-Process {
    param($FilePath,$Verb,$ArgumentList,$WorkingDirectory,[switch]$PassThru,$ErrorAction)
    $script:launches+=@{file=$FilePath;verb=$Verb;arguments=$ArgumentList;directory=$WorkingDirectory;passThru=$PassThru.IsPresent}
    if($script:mode -eq 'cancel'){throw [ComponentModel.Win32Exception]::new(1223)}
    if($script:mode -eq 'fail'){throw 'synthetic launch failure'}
    [pscustomobject]@{Id=1234}
}
# Exercise real installed runtime resolution under PS7; PS5 path discovery is mocked below.
if($PSVersionTable.PSVersion.Major -ge 7){
    $resolved=Resolve-PaytmOperationsPowerShell
    Check ($resolved -eq (Join-Path $PSHOME 'pwsh.exe')) 'single current PS7 executable'
}
function Resolve-PaytmOperationsPowerShell { 'C:\Program Files\PowerShell\7\pwsh.exe' }
$runner=Join-Path $PSScriptRoot 'ReviewPaytmOperationsFollowUp.ps1'
$evidence=Join-Path $PSScriptRoot '..\..\docs\evidence\paytm-operations-spare-review-20261022.json'
Start-PaytmOperationsElevatedReview $runner $evidence "C:\Owner's reports\review"
Check ($script:launches.Count -eq 1) 'exactly one child'
$call=$script:launches[0]
Check ($call.verb -ceq 'RunAs') 'UAC required'
Check ($call.file -eq 'C:\Program Files\PowerShell\7\pwsh.exe') 'PS7 not legacy powershell'
Check ($call.arguments -match '^-NoLogo -NoProfile -NoExit -EncodedCommand [A-Za-z0-9+/=]+$') 'single safe argument string'
Check ($call.arguments -notmatch 'ExecutionPolicy|Bypass') 'policy not bypassed'
Check ($call.directory -eq (Split-Path -Parent $runner) -and $call.passThru) 'absolute working directory'
$decoded=[Text.Encoding]::Unicode.GetString([Convert]::FromBase64String(($call.arguments -split ' ')[-1]))
Check ($decoded.Contains("C:\Owner''s reports\review")) 'apostrophe path escaped'
Check ($decoded.Contains('CONTINUE IN THIS NEW ADMINISTRATOR WINDOW')) 'unambiguous handoff'
Check ($decoded.Contains('-OperationsEvidencePath') -and $decoded.Contains('-OutputDirectory')) 'arguments retained'
Check ($decoded -notmatch 'SYNC_AND_REFRESH|resync|Set-Service|Start-Service|sudo|password') 'no consent or operations in launcher'
Check ($decoded.Contains('not test acceptance')) 'not falsely accepted'
$tokens=$null;$errors=$null
$null=[Management.Automation.Language.Parser]::ParseInput($decoded,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'generated command parses'
$unicodePath='C:\'+[char]0x20B9+' data\report.json'
$odd=New-PaytmOperationsElevatedCommand "C:\a'; throw 'bad\runner.ps1" $unicodePath "C:\out"
$ast=[Management.Automation.Language.Parser]::ParseInput($odd,[ref]$tokens,[ref]$errors)
Check ($errors.Count -eq 0) 'Unicode and metacharacters parse'
$throws=@($ast.FindAll({param($node) $node -is [Management.Automation.Language.ThrowStatementAst]},$true))
Check ($throws.Count -eq 0) 'path cannot inject throw'
Check ($odd.Contains($unicodePath)) 'Unicode preserved'
$script:mode='cancel'
Reject {Start-PaytmOperationsElevatedReview $runner $evidence 'C:\review'} 'OPS_ELEVATION_CANCELLED'
$script:mode='fail'
Reject {Start-PaytmOperationsElevatedReview $runner $evidence 'C:\review'} 'OPS_ELEVATED_LAUNCH_FAILED'
$before=$script:launches.Count
Reject {Start-PaytmOperationsElevatedReview $runner 'C:\missing-marketbrain-evidence-14cf7157.json' 'C:\review'} 'OPS_LAUNCH_INPUT_MISSING'
Check ($script:launches.Count -eq $before) 'missing evidence never launches'
function Resolve-PaytmOperationsPowerShell {throw 'OPS_POWERSHELL_7_NOT_FOUND'}
Reject {Start-PaytmOperationsElevatedReview $runner $evidence 'C:\review'} 'OPS_POWERSHELL_7_NOT_FOUND'
Check ($script:launches.Count -eq $before) 'missing runtime never launches'
Write-Host "PASS: $script:checks elevation assertions; no real UAC or operational changes."
