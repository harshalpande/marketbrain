# Offline isolated-runner and status validation; native Docker replaced before invocation.
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'TestPaperPersistenceReviewWorkflow.ps1')
. (Join-Path $PSScriptRoot 'PaperApprovalVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperStorageVerification.ps1')
. (Join-Path $PSScriptRoot 'PaperStorageKey.ps1')
$start=$script:count
$java=Get-Content (Join-Path $PSScriptRoot '../../marketbrain-service/src/main/java/in/marketbrain/paper/PaperStorageVerification.java') -Raw
$script:names=@([regex]::Matches($java,'check\("([a-z0-9_]+)"')|ForEach-Object {$_.Groups[1].Value})
Check ($script:names.Count -eq 12) '12 fixed declarations'
function Sample([string]$Phase){
    $names=if($Phase -ceq '--prepare'){@($script:names|Select-Object -First 10)}else{@($script:names|Select-Object -Last 2)}
    @{version='PAPER_STORAGE_REVIEW_V1';phase=$Phase;schema=$schema;status='ISOLATED_STORAGE_CHECKS_PASSED';checkCount=$names.Count;failedCount=0;elapsedSeconds=1;checks=@($names|ForEach-Object {@{name=$_;passed=$true;elapsedMillis=1}});applicationDatabaseAccessed=$false;actionExecutionEnabled=$false;syntheticDatabaseWritesPerformed=$true;providerCalls=0;telegramCalls=0;modelCalls=0;cashPaise=10000000;reservedCashPaise=0;ledgerRevision=0;orderCount=0;fillCount=0;bindingCount=1;proposalCount=0;deliveryCount=0}|ConvertTo-Json -Depth 6|ConvertFrom-Json
}
foreach($phase in @('--prepare','--recover')){Assert-PaperStoragePhase (Sample $phase) $phase $schema;Check $true 'valid phase'}
foreach($field in @('failedCount','providerCalls','telegramCalls','modelCalls','reservedCashPaise','ledgerRevision','orderCount','fillCount','proposalCount','deliveryCount','cashPaise','bindingCount','checkCount')){$v=Sample '--prepare';$v.$field++;Reject {Assert-PaperStoragePhase $v '--prepare' $schema} 'numeric mutation'}
foreach($field in @('applicationDatabaseAccessed','actionExecutionEnabled','syntheticDatabaseWritesPerformed')){$v=Sample '--prepare';$v.$field=-not $v.$field;Reject {Assert-PaperStoragePhase $v '--prepare' $schema} 'safety mutation'}
$v=Sample '--prepare';$v.checks[0].passed=$false;Reject {Assert-PaperStoragePhase $v '--prepare' $schema} 'failed case'
$v=Sample '--prepare';$v.checks[0].name=$v.checks[1].name;Reject {Assert-PaperStoragePhase $v '--prepare' $schema} 'duplicate case'
$script:failMock=$false;$script:failResolution=$false;$script:failPreflight=$false;$script:mockContainers=@{};$script:mockCalls=@()
$run=[scriptblock]::Create($mocked.Replace('$v.receipt.tailHash=''b''*64;', 'if(-not $ApprovalStorage){$v.receipt.tailHash=''b''*64};'))
Reject {& $run -ApprovalDelivery -ApprovalStorage -OutputDirectory (Join-Path $testRoot 'invalid-storage')} 'exclusive suite'
& $run -ApprovalStorage -OutputDirectory (Join-Path $testRoot 'storage-pass')
$file=Get-ChildItem (Join-Path $testRoot 'storage-pass') -Filter '*.json'|Select-Object -First 1
$r=Get-Content $file.FullName -Raw|ConvertFrom-Json
Check ($r.status -ceq 'ISOLATED_STORAGE_PASSED_APPLICATION_DEPLOYMENT_PENDING') 'storage success'
Check ($r.prepare.checkCount -eq 10 -and $r.recover.checkCount -eq 2) 'phase counts'
Check (@($r.cleanup|Where-Object action -eq 'REMOVED_SYNTHETIC_CONTAINER_AND_ANONYMOUS_VOLUMES').Count -eq 3) 'cleanup'
$script:failMock=$true;$script:mockContainers=@{}
Reject {& $run -ApprovalStorage -OutputDirectory (Join-Path $testRoot 'storage-fail')} 'failure stops'
$valid=[pscustomobject]@{version='PAPER_APPROVAL_STORAGE_V1';status='STORAGE_KEY_VERIFIED_ACTIONS_DISABLED';databaseWritesPerformed=$false;notificationEnabled=$false;actionExecutionEnabled=$false;liveExecutionEnabled=$false}
Assert-PaperStorageStatus $valid;Check $true 'valid status'
foreach($flag in @('databaseWritesPerformed','notificationEnabled','actionExecutionEnabled','liveExecutionEnabled')){$valid.$flag=$true;Reject {Assert-PaperStorageStatus $valid} 'unsafe capability';$valid.$flag=$false}
$valid.status='STORAGE_SETUP_BLOCKED';Reject {Assert-PaperStorageStatus $valid} 'blocked key'
$script:aclFixture=[pscustomobject]@{AreAccessRulesProtected=$false;Access=@()}
function Get-Acl {param($LiteralPath);return $script:aclFixture}
Reject {Assert-PaperPrivateAcl 'fixture-only'} 'inherited ACL rejected'
$script:aclFixture.AreAccessRulesProtected=$true
$script:aclFixture.Access=@([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.SecurityIdentifier]::new('S-1-1-0'),'Read','Allow'))
Reject {Assert-PaperPrivateAcl 'fixture-only'} 'everyone grant rejected'
$script:aclFixture.Access=@([Security.AccessControl.FileSystemAccessRule]::new([Security.Principal.WindowsIdentity]::GetCurrent().User,'FullControl','Allow'))
Assert-PaperPrivateAcl 'fixture-only';Check $true 'private owner grant accepted'
Write-Host "PASS: $script:count offline assertions; $($script:count-$start) storage additions. No key files provisioned."
