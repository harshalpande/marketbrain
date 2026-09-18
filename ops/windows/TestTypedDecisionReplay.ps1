$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'TypedDecisionEvaluation.ps1')
$fixture=Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test-fixtures/typed-decision-v4-echo-regression.json') -Raw | ConvertFrom-Json
$directory=Join-Path ([IO.Path]::GetTempPath()) ('marketbrain-replay-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $directory | Out-Null
try {
    $rows=@(foreach ($a in $fixture.attempts) {
        foreach ($name in @('javaDecision','evidenceCategory','targetNetReturnPercent','targetBenchmarkExcessReturnPercent','targetMaximumDrawdownPercent')) {
            $a | Add-Member -NotePropertyName $name -NotePropertyValue $a.offlineCandidateEvidence.$name
        }
        $a | Add-Member evaluationMode 'INDEPENDENT'
        $a | Add-Member elapsedMillis 1
        $a | Add-Member schemaValid $false
        $a | Add-Member businessValid $false
        $a | Add-Member failures @('NO_JSON_OBJECT_FOUND')
        $a
    })
    $source=[pscustomobject]@{ modelRef='captured-Qwen-1.5B'; selectionMode='CONTRAST_VALIDATION'; attempts=$rows }
    $sourcePath=Join-Path $directory 'source.json'
    Save-TypedDecisionEvidence $source $sourcePath
    $before=(Get-FileHash -LiteralPath $sourcePath).Hash
    $output=Join-Path $directory 'output'
    & (Join-Path $PSScriptRoot 'ReplayPrototypeSwingTypedDecisions.ps1') -EvidencePath $sourcePath -OutputDirectory $output
    $files=@(Get-ChildItem -LiteralPath $output -File -Recurse)
    if ($files.Count -ne 2) { throw 'Replay must produce just JSON and log.' }
    $result=$files | Where-Object Extension -eq '.json' | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json }
    if ((Get-FileHash -LiteralPath $sourcePath).Hash -ne $before -or $result.sourceSha256 -ne $before) { throw 'Source evidence changed.' }
    if ($result.results[0].schemaValidPercent -ne 100 -or $result.results[0].businessValidPercent -ne 25 -or $result.results[0].evaluation.diagnosticPassedCount -ne 0) { throw 'Replay scores differ from captured regression.' }
    if ($result.modelCallsPerformed -ne 0 -or $result.results[0].attempts[0].originalReported.schemaValid) { throw 'Replay provenance incorrect.' }
    if ($null -ne $result.results[0].evaluation.javaSelectedMeanMaximumDrawdownPercent) { throw 'Missing labels became zero.' }
    Write-Host '[100%] Offline replay and immutable-evidence tests passed.'
}
finally {
    $resolved=(Resolve-Path -LiteralPath $directory).Path
    if ((Split-Path -Parent $resolved) -eq [IO.Path]::GetTempPath().TrimEnd('\') -and
        (Split-Path -Leaf $resolved) -like 'marketbrain-replay-test-*') {
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
