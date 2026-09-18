#Requires -Version 5.1
[CmdletBinding()]
param(
    [string]$ReviewDirectory='C:\MarketBrainData\Review',
    [string]$OutputDirectory='C:\MarketBrainData\Review',
    [switch]$IncludeIntermediate
)
$ErrorActionPreference='Stop'
Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'NumericalHistoryEvidence.ps1')
if(-not(Test-Path -LiteralPath $ReviewDirectory -PathType Container)){throw 'Existing review directory not found. Do not rerun collection.'}
$root=Get-Item -LiteralPath $ReviewDirectory
if($root.Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'Linked review root refused.'}
if(-not(Test-Path -LiteralPath $OutputDirectory)){[void](New-Item -ItemType Directory -Path $OutputDirectory)}
$path=Join-Path $OutputDirectory ('existing-data-validation-'+(Get-Date -Format 'yyyyMMdd-HHmmss')+'-'+[guid]::NewGuid().ToString('N').Substring(0,12)+'.json')
$timer=[Diagnostics.Stopwatch]::StartNew()
$report=[pscustomobject]@{
    version='EXISTING_DATA_VALIDATION_EVIDENCE_V2';status='RUNNING';createdAtUtc=[DateTime]::UtcNow.ToString('o');updatedAtUtc=$null
    selectionMode=$(if($IncludeIntermediate){'FINAL_FIRST_WITH_INTERMEDIATE'}else{'FINAL_OUTCOMES_ONLY'})
    limits=[pscustomobject]@{directoryEntries=1000;files=50;perFileBytes=16MB;totalBytes=96MB;cooperativeSeconds=60}
    elapsedSeconds=0;scriptSha256=(Get-FileHash -LiteralPath $PSCommandPath).Hash
    files=[Collections.Generic.List[object]]::new();events=[Collections.Generic.List[object]]::new();partial=$false;errorType=$null
    summary=$null;trainingAuthorized=$false;databaseWritesPerformed=$false;providerCallCount=0;modelCallCount=0
    limitations='Saved artifacts only, top-level directory only. Source metadata/selected metrics are claims from those files, not revalidated quality or proof all 500 symbols/15 years were checked. Missing, malformed, oversized and changed files remain unknown. No network/DB/model calls, downloads, backfill, deletion or provider checks. Current-membership and historical-vintage limitations remain.'
}
function Save-EvidenceProgress([int]$Percent,[string]$Message){
    $report.elapsedSeconds=[math]::Round($timer.Elapsed.TotalSeconds,2)
    $report.events.Add([pscustomobject]@{atUtc=[DateTime]::UtcNow.ToString('o');percent=$Percent;message=$Message})
    Save-NumericalHistoryReport $report $path
    Write-Host "[$Percent%] $Message"
    Write-Progress -Id 101 -Activity 'Reusing saved data validation evidence' -Status $Message -PercentComplete $Percent
}
try {
    Save-EvidenceProgress 0 'Reading existing reports only; no validation job will be rerun.'
    # Never recurse. Bound inspection; extra sentinel proves the listing was incomplete.
    $listed=@(Get-ChildItem -LiteralPath $ReviewDirectory -File -Filter '*.json' | Select-Object -First 1001)
    if($listed.Count -gt 1000){$report.partial=$true;$listed=@($listed | Select-Object -First 1000)}
    $finalPattern='^(final-provider-quality-|expansion-batch-[0-9]+-final-(database-quality|provider-quality|quality-checkpoints)-|daily-enrichment-(database-quality|provider-quality|quality-checkpoints)-).*\.json$'
    $allPattern='^(final-provider-quality-|expansion-batch-[0-9]+-.*(quality|analysis|investigation|remediation)|daily-enrichment-(database-quality|provider-quality|quality-checkpoints)-|remaining-data-analysis-).*\.json$'
    $pattern=if($IncludeIntermediate){$allPattern}else{$finalPattern}
    $matching=@($listed | Where-Object {$_.Name -match $pattern} | Sort-Object @{Expression={if($_.Name -match $finalPattern){0}else{1}}},@{Expression='LastWriteTimeUtc';Descending=$true})
    if($matching.Count -gt 50){$report.partial=$true;$matching=@($matching | Select-Object -First 50)}
    $bytesRead=0L;$number=0
    foreach($file in $matching){
        $number++
        if($timer.Elapsed.TotalSeconds -gt 60){$report.partial=$true;break}
        $entry=[pscustomobject]@{name=$file.Name;bytes=$file.Length;lastWriteTimeUtc=$file.LastWriteTimeUtc.ToString('o');sha256=$null;status='PENDING';skipReason=$null;metrics=$null;errorType=$null}
        $report.files.Add($entry)
        if(($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $file.Length -gt 16MB -or ($bytesRead+$file.Length) -gt 96MB){
            $entry.status='SKIPPED_LINK_OR_SIZE_BUDGET';$report.partial=$true
            $entry.skipReason=if($file.Attributes -band [IO.FileAttributes]::ReparsePoint){'LINK'}elseif($file.Length -gt 16MB){'PER_FILE_LIMIT'}else{'TOTAL_BYTE_LIMIT'}
        }else{
            try {
                # A single bounded read supplies both hash and JSON; disallow concurrent writers while reading.
                $stream=[IO.File]::Open($file.FullName,[IO.FileMode]::Open,[IO.FileAccess]::Read,[IO.FileShare]::Read)
                try {
                    if($stream.Length -ne $file.Length -or $stream.Length -gt 16MB){throw 'File changed before read.'}
                    $memory=[IO.MemoryStream]::new();try{$stream.CopyTo($memory);$bytes=$memory.ToArray()}finally{$memory.Dispose()}
                }finally{$stream.Dispose()}
                $bytesRead+=$bytes.Length
                $sha=[Security.Cryptography.SHA256]::Create();try{$entry.sha256=[BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','')}finally{$sha.Dispose()}
                $data=[Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0xFEFF) | ConvertFrom-Json
                if($null -eq $data -or $data -is [array] -or $data -isnot [pscustomobject]){throw 'Expected report object.'}
                $metrics=[ordered]@{}
                foreach($field in @('jobId','runId','datasetRunId','manifestHash','planHash','status','qualityStatus','requestedFrom','requestedTo','targetDate',
                    'instrumentCount','instruments','totalCandles','totalChunks','completedChunks','failedChunks','acceptedRows','rejectedRows',
                    'blockingInstrumentCount','missingProviderDataInstrumentCount','reviewInstrumentCount','duplicateRows','invalidRows',
                    'unresolvedFindingCount','resolvedFindingCount','documentedFindingCount','truncatedFindingCount','currentResolutionCount',
                    'completedItems','failedItems','secondaryCandlesReady','providerSpotCheckRequested','providerMismatchCount','providerCheckFailureCount',
                    'modelTrainingEligible','backtestingEligible','databaseWritesPerformed',
                    'failedInvariantCount','remediationOrJobCheckpointChanged','providerNonMatchCount')){
                    $property=$data.PSObject.Properties[$field]
                    if($property){
                        $value=$property.Value
                        if($value -is [bool] -or $value -is [int] -or $value -is [long] -or $value -is [decimal] -or $value -is [double]){$metrics[$field]=$value}
                        elseif($value -is [string] -and $value.Length -le 128 -and $value -match '^[a-zA-Z0-9_.:+-]+$'){$metrics[$field]=$value}
                    }
                }
                if($data.PSObject.Properties['providerSpotChecks']){
                    $checks=@($data.providerSpotChecks | Where-Object {$null -ne $_})
                    $metrics['savedProviderCheckCount']=$checks.Count
                    $metrics['savedProviderMatchedCount']=@($checks | Where-Object {$_.PSObject.Properties['status'] -and $_.status -eq 'MATCHED'}).Count
                }
                foreach($field in @('failedInvariants','databaseProviderChangedMetrics')){
                    if($data.PSObject.Properties[$field]){$metrics[$field+'Count']=@($data.$field | Where-Object {$null -ne $_}).Count}
                }
                $entry.metrics=[pscustomobject]$metrics
                $entry.status=if($metrics.Count){'SAVED_METRICS_CAPTURED_NOT_REVALIDATED'}else{'NO_RECOGNIZED_SUMMARY_FIELDS'}
            }catch{$entry.status='UNREADABLE_OR_INVALID';$entry.errorType=$_.Exception.GetType().Name;$report.partial=$true}
        }
        Save-EvidenceProgress ([int](90*$number/[math]::Max(1,$matching.Count))) "Inspected $number/$($matching.Count) saved reports."
    }
    $report.summary=[pscustomobject]@{selectedFiles=$matching.Count;inspectedFiles=$report.files.Count;bytesRead=$bytesRead;capturedSummaries=@($report.files.ToArray() | Where-Object status -eq 'SAVED_METRICS_CAPTURED_NOT_REVALIDATED').Count;skippedFiles=@($report.files.ToArray() | Where-Object status -eq 'SKIPPED_LINK_OR_SIZE_BUDGET').Count;invalidFiles=@($report.files.ToArray() | Where-Object status -eq 'UNREADABLE_OR_INVALID').Count}
    $report.status=if($report.partial){'PARTIAL_SAVED_EVIDENCE_REVIEW_REQUIRED'}elseif($report.summary.capturedSummaries -eq 0){'NO_SAVED_SUMMARY_FOUND'}else{'SAVED_EVIDENCE_REVIEW_REQUIRED'}
    Save-EvidenceProgress 100 'Saved evidence packaged. Missing evidence does not invalidate historical work.'
}catch{
    $report.status='FAILED_PARTIAL_REPORT';$report.partial=$true;$report.errorType=$_.Exception.GetType().Name
    try{Save-EvidenceProgress 100 'Stopped; preserve existing JSON and any pending checkpoint.'}catch{Write-Warning 'Checkpoint failed; retain prior JSON/pending file.'}
    throw
}finally{Write-Progress -Id 101 -Activity 'Reusing saved data validation evidence' -Completed;Write-Host "Share only: $path"}
