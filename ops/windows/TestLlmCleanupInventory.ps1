# Offline unit/integration checks. No actual model, hardware, process, service or broker inspection.
#Requires -Version 5.1
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1')
$checks=0
function Assert-Inventory([bool]$Condition,[string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
}
$testRoot=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-inventory-test-'+[guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $testRoot)
Write-Host 'Offline fixtures only. No inference or runtime collection.'
foreach ($uri in @('https://127.0.0.1:11434','http://example.com:11434','http://user:secret@localhost:11434','http://localhost:11434/path','http://localhost:11434/?secret=x')) {
    $rejected=$false
    try { [void](Assert-LlmInventoryLoopback $uri) } catch { $rejected=$true }
    Assert-Inventory $rejected ('Unsafe URL accepted: '+$uri)
}
Assert-Inventory ((Assert-LlmInventoryLoopback 'http://127.0.0.1:11434') -eq 'http://127.0.0.1:11434') 'Valid loopback URL rejected.'

# Mock only the HTTP command; exercise the real allowlist and projection.
$script:apiMode='valid'
$script:apiCalls=[Collections.Generic.List[string]]::new()
function Invoke-RestMethod {
    param($Uri,$Method,$TimeoutSec,$MaximumRedirection,$ErrorAction)
    $script:apiCalls.Add($Uri)
    Assert-Inventory ($Method -eq 'Get' -and $TimeoutSec -eq 3 -and $MaximumRedirection -eq 0) 'Unbounded or mutating HTTP request.'
    if ($script:apiMode -eq 'offline') { throw 'SECRET_TEST_VALUE must not be exported' }
    if ($script:apiMode -eq 'invalid') { return [pscustomobject]@{version='not-models'} }
    if ($script:apiMode -eq 'empty') { return [pscustomobject]@{models=@()} }
    [pscustomobject]@{models=@([pscustomobject]@{name='test:1b';digest='fixture';size=123;secret='SECRET_TEST_VALUE';details=[pscustomobject]@{parameter_size='1B';quantization_level='Q4'}})}
}
$api=@(Get-LlmInventoryOllama 'http://127.0.0.1:11434' 3)
Assert-Inventory ($api.Count -eq 2 -and $api[0].models.Count -eq 1) 'Model list shape incorrect.'
Assert-Inventory (($api | ConvertTo-Json -Depth 8) -notmatch 'SECRET_TEST_VALUE') 'Unapproved API fields leaked.'
Assert-Inventory (($script:apiCalls -join ',') -eq 'http://127.0.0.1:11434/api/tags,http://127.0.0.1:11434/api/ps') 'Unexpected API endpoint.'
foreach ($mode in @('offline','invalid','empty')) {
    $script:apiMode=$mode
    $api=@(Get-LlmInventoryOllama 'http://localhost:11434' 3)
    $expected=if($mode -eq 'empty'){'AVAILABLE'}else{'UNKNOWN_UNAVAILABLE_OR_INVALID'}
    Assert-Inventory ($api[0].status -eq $expected -and $api[0].models.Count -eq 0) ('Wrong unknown/empty handling: '+$mode)
    Assert-Inventory (($api | ConvertTo-Json -Depth 8) -notmatch 'SECRET_TEST_VALUE') 'Error body leaked.'
}

$modelRoot=Join-Path $testRoot 'models'
[void](New-Item -ItemType Directory -Path (Join-Path $modelRoot 'nested'))
[IO.File]::WriteAllText((Join-Path $modelRoot 'one.gguf'),'fixture-not-a-model')
[IO.File]::WriteAllText((Join-Path $modelRoot 'nested/two.gguf'),'fixture-not-a-model')
[IO.File]::WriteAllText((Join-Path $modelRoot 'secret.env'),'SECRET_TEST_VALUE')
$scan=Get-LlmInventoryFiles @($modelRoot,$modelRoot,(Join-Path $testRoot 'missing')) 100 10 5
Assert-Inventory ($scan.files.Count -eq 2 -and -not $scan.partial) 'Nested or duplicate-root GGUF scan failed.'
Assert-Inventory (($scan | ConvertTo-Json -Depth 8) -notmatch 'SECRET_TEST_VALUE') 'Scan read file content.'
Assert-Inventory (@($scan.roots | Where-Object status -eq 'MISSING').Count -eq 1) 'Missing root not recorded.'
$scan=Get-LlmInventoryFiles @($modelRoot) 1 10 5
Assert-Inventory ($scan.partial -and $scan.limitReached -and $scan.entriesInspected -le 1) 'Entry limit not enforced.'
$scan=Get-LlmInventoryFiles @($modelRoot) 100 0 5
Assert-Inventory ($scan.partial -and $scan.depthLimited -and $scan.files.Count -eq 1) 'Depth limit not enforced.'
$scan=Get-LlmInventoryFiles @([IO.Path]::GetPathRoot($testRoot)) 100 10 5
Assert-Inventory ($scan.accessErrors -eq 1 -and $scan.files.Count -eq 0) 'Drive root not rejected.'
$outside=Join-Path $testRoot 'outside'
[void](New-Item -ItemType Directory -Path $outside)
[IO.File]::WriteAllText((Join-Path $outside 'never-follow.gguf'),'fixture')
[void](New-Item -ItemType Junction -Path (Join-Path $modelRoot 'junction') -Target $outside)
$scan=Get-LlmInventoryFiles @($modelRoot) 100 10 5
Assert-Inventory ($scan.partial -and $scan.skippedDirectoryLinks -eq 1 -and $scan.files.Count -eq 2) 'Directory junction followed.'

$repo=Join-Path $testRoot 'repo'
[void](New-Item -ItemType Directory -Path (Join-Path $repo 'ops/windows'))
[IO.File]::WriteAllText((Join-Path $repo '.env'),'SECRET_TEST_VALUE')
[IO.File]::WriteAllText((Join-Path $repo 'compose.yaml'),'MARKETBRAIN_OLLAMA_BASE_URL: SECRET_TEST_VALUE')
[IO.File]::WriteAllText((Join-Path $repo 'ops/windows/fixture.ps1'),"# qwen2.5-1.5b SECRET_TEST_VALUE")
$references=Get-LlmInventoryReferences $repo
Assert-Inventory ($references.references.Count -eq 2) 'Reference hints missing.'
Assert-Inventory (($references | ConvertTo-Json -Depth 8) -notmatch 'SECRET_TEST_VALUE') 'Config content leaked.'

$report=[pscustomobject]@{updatedAtUtc=$null;sections=[ordered]@{};timingsSeconds=[ordered]@{};warnings=[Collections.Generic.List[string]]::new();value=1}
Invoke-LlmInventoryStage $report 'failure' {throw 'SECRET_TEST_VALUE'}
Assert-Inventory ($report.sections['failure'].status -eq 'UNKNOWN' -and $report.warnings.Count -eq 1) 'Stage failure was not isolated.'
Assert-Inventory (($report | ConvertTo-Json -Depth 8) -notmatch 'SECRET_TEST_VALUE') 'Stage failure text leaked.'
$file=Join-Path $testRoot 'atomic.json'
Save-LlmInventoryReport $report $file
$report.value=2
Save-LlmInventoryReport $report $file
Assert-Inventory ((Get-Content $file -Raw -Encoding UTF8 | ConvertFrom-Json).value -eq 2) 'Atomic report replacement failed.'
Assert-Inventory (@(Get-ChildItem -LiteralPath $testRoot -Filter '*.pending-*' -File).Count -eq 0) 'Atomic pending files not consumed.'

# Integration run uses a fixture copy of the real entrypoint and a mock-only collector file.
# No real collector executes; exercise orchestration, checkpoints and repeated unique reports.
$mockLibrary=@'
function Assert-LlmInventoryLoopback($BaseUrl) { 'http://127.0.0.1:11434' }
function Get-LlmInventoryRuntime { [pscustomobject]@{executables=@();processes=@()} }
function Get-LlmInventoryOllama { throw 'SECRET_TEST_VALUE' }
function Get-LlmInventoryHardware { [pscustomobject]@{mock=$true} }
function Get-LlmInventoryFiles { [pscustomobject]@{partial=$true;files=@()} }
function Get-LlmInventoryReferences { [pscustomobject]@{references=@()} }
'@
$libraryText=[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'LlmCleanupInventory.ps1'))
[IO.File]::WriteAllText((Join-Path $repo 'ops/windows/LlmCleanupInventory.ps1'),$libraryText+[Environment]::NewLine+$mockLibrary)
$runner=Join-Path $repo 'ops/windows/GetSpareLlmCleanupInventory.ps1'
[IO.File]::WriteAllText($runner,[IO.File]::ReadAllText((Join-Path $PSScriptRoot 'GetSpareLlmCleanupInventory.ps1')))
$output=Join-Path $testRoot 'reports'
& $runner -OutputDirectory $output
& $runner -OutputDirectory $output
$reports=@(Get-ChildItem -LiteralPath $output -File -Filter '*.json')
Assert-Inventory ($reports.Count -eq 2) 'Repeated runs collided or created unexpected report files.'
$result=Get-Content -LiteralPath $reports[0].FullName -Raw -Encoding UTF8 | ConvertFrom-Json
Assert-Inventory ($result.status -eq 'COMPLETED_REVIEW_REQUIRED' -and $result.sections.ollama.status -eq 'UNKNOWN') 'Partial collection did not complete with unknown status.'
Assert-Inventory ($result.events.Count -eq 6 -and $result.safety.modelInferenceCalls -eq 0 -and $result.safety.modelsDeleted -eq 0) 'Progress or safety metadata failed.'
Assert-Inventory (($result | ConvertTo-Json -Depth 16) -notmatch 'SECRET_TEST_VALUE') 'Integration report leaked an exception body.'
Assert-Inventory ($result.warnings.Count -ge 2) 'Partial-result limitations missing.'
Write-Host "PASS: $checks assertions. Fixture directory retained: $testRoot"
