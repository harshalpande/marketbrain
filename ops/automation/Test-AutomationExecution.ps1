#requires -Version 7.5
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'Automation.Common.ps1')
. (Join-Path $PSScriptRoot 'Automation.TestExecution.ps1')
$fixture=[IO.File]::ReadAllBytes((Join-Path $PSScriptRoot 'jobs/PaytmTransport.ps1'))
function Get-AutomationReviewedSource([string]$Revision) { return ,$fixture }
$root=Join-Path ([IO.Path]::GetTempPath()) ('mb-execution-fixture-'+[guid]::NewGuid().ToString('N'))
$hash=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fixture))
$job=[pscustomobject]@{id=[guid]::NewGuid().ToString();kind='paytm-transport-test';spec=[pscustomobject]@{revision=('a'*40);sha256=$hash;mode='FailureFixture'}}
$result=Invoke-AutomationReviewedTest $job $root
if($result.passed -or $result.exitCode -ne 1 -or $result.evidence.failure -ne 'DELIBERATE_FAILURE_FIXTURE_NO_GATEWAY_ACCESS'){throw 'Structured failure was not retained'}
try { $null=Invoke-AutomationReviewedTest $job $root; throw 'Replay permitted' }
catch { if($_.Exception.Message -ne 'EXECUTION_ALREADY_RESERVED_REVIEW_REQUIRED'){throw} }
$job.id=[guid]::NewGuid().ToString(); $job.spec.sha256='F'*64
try { $null=Invoke-AutomationReviewedTest $job $root; throw 'Bad hash permitted' }
catch { if($_.Exception.Message -ne 'TEST_SOURCE_HASH_MISMATCH'){throw} }
$job.spec.revision='main'
try { Assert-AutomationTestSpec $job.spec; throw 'Branch permitted' }
catch { if($_.Exception.Message -ne 'INVALID_TEST_SPEC'){throw} }
# Updated source version executes with a fresh identity; no installed runner replacement.
$fixture=[Text.Encoding]::UTF8.GetBytes("param([string]`$ResultPath,[string]`$Mode)`n[IO.File]::WriteAllText(`$ResultPath,'{`"passed`":true,`"fixture`":true}')")
$job.id=[guid]::NewGuid().ToString();$job.spec.revision='b'*40
$job.spec.sha256=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($fixture))
$result=Invoke-AutomationReviewedTest $job $root
if(-not $result.passed -or $result.revision -ne ('b'*40)){throw 'Updated reviewed fixture did not execute'}
Write-Host 'EXECUTION_FIXTURES_PASSED: structured failure, replay refusal, hash refusal, branch refusal, next reviewed version execution.'
Write-Host "Isolated fixture evidence: $root"
