#Requires -Version 7.0
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'PaytmSecurityProbes.ps1')
$checks=0
function Check($Value,$Name){if(-not $Value){throw "PROBE_TEST_$Name"};$script:checks++}
$cases=@(Get-PaytmSecurityProbeCases)
foreach($c in $cases){
 $a=Get-PaytmSecurityProbeArguments $c
 Check ($a[0] -ceq '-q' -and $a -contains '--head' -and $a -notcontains '--insecure') 'SAFE_CURL_FLAGS'
 Check ($a -contains 'http://127.0.0.1:18889' -and $a -contains '--noproxy' -and $a -contains '') 'EXPLICIT_PROXY'
 Check ($a[-1] -ceq $c.url) 'DESTINATION'
 foreach($bad in @(@{exitCode=28;stdout='200|0|000'},@{exitCode=0;stdout=''},@{exitCode=0;stdout='PRIVATE_TEXT'},@{exitCode=4;stdout='200|0|000'})){
  Check (-not (Test-PaytmSecurityProbeResult $c $bad)) 'TIMEOUT_OR_UNSUPPORTED_NEVER_PASSES'
 }
}
$script:rows=@();$script:index=0
$baselineRun={param($Arguments)
 $case=$cases[$script:index];$script:index++
 switch($case.kind){
  CONTROL {$code=0;$metrics='200|0|503'}
  PIN {$code=90;$metrics='200|0|000'}
  CONNECT_DENIED {$code=56;$metrics='403|0|000'}
  HTTP_DENIED {$code=0;$metrics='000|0|403'}
 }
 @{exitCode=$code;stdout=$metrics;stderr='PRIVATE_STDERR';elapsedSeconds=0.1}
}
Invoke-PaytmSecurityProbeBatch $baselineRun {param($r)$script:rows+=,$r}
Check ($rows.Count -eq 6 -and @($rows|Where-Object passed -NE $true).Count -eq 0) 'FULL_BATCH'
Check (($rows|ConvertTo-Json) -notmatch 'PRIVATE_STDERR') 'NO_STDERR'
foreach($failAt in 0..5){
 $script:index=0;$script:rows=@();$threw=$false
 try{Invoke-PaytmSecurityProbeBatch {
  param($Arguments)
  if($script:index -eq $failAt){$script:index++;return @{exitCode=28;stdout='';elapsedSeconds=6}}
  & $baselineRun $Arguments
 } {param($r)$script:rows+=,$r}}catch{$threw=$_.Exception.Message -like 'SECURITY_PROBE_FAILED_*'}
 Check ($threw -and $rows.Count -eq $failAt+1 -and -not $rows[-1].passed) 'STOP_AT_FIRST_FAILURE_WITH_EVIDENCE'
}
$threw=$false
try{Get-PaytmSecurityProbeArguments @{name='CONTROL_BEFORE';url='https://unapproved.invalid/';kind='CONTROL'}}catch{$threw=$true}
Check $threw 'NO_ARBITRARY_DESTINATION'
Check (-not (Test-PaytmSecurityProbeResult $cases[1] @{exitCode=0;stdout='200|0|503'})) 'WRONG_PIN_MUST_FAIL'
Check (-not (Test-PaytmSecurityProbeResult $cases[2] @{exitCode=7;stdout='000|0|000'})) 'UNREACHABLE_IS_NOT_DENIAL'
foreach($n in @('PaytmSecurityProbes.ps1','TestPaytmSecurityProbeBundle.ps1')){
 $tokens=$null;$errors=$null
 $null=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot $n),[ref]$tokens,[ref]$errors)
 Check ($errors.Count -eq 0) 'SCRIPT_PARSE'
}
[pscustomobject]@{status='SECURITY_PROBE_LOCAL_TESTS_PASSED';assertions=$checks;runtimeGatewayTested=$false}|ConvertTo-Json
