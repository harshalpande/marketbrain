# Definitions only. Fixed credential-free HEAD requests; no gateway mutation.
function Get-PaytmSecurityProbeCases {
 @(
  @{name='CONTROL_BEFORE';url='https://developer.paytmmoney.com/';kind='CONTROL'},
  @{name='WRONG_TLS_PIN';url='https://developer.paytmmoney.com/';kind='PIN'},
  @{name='FORBIDDEN_HOST';url='https://example.com/';kind='CONNECT_DENIED'},
  @{name='FORBIDDEN_PORT';url='https://developer.paytmmoney.com:444/';kind='CONNECT_DENIED'},
  @{name='PLAINTEXT';url='http://developer.paytmmoney.com/';kind='HTTP_DENIED'},
  @{name='CONTROL_AFTER';url='https://developer.paytmmoney.com/';kind='CONTROL'}
 )
}
function Get-PaytmSecurityProbeArguments($Case) {
 $known=@(Get-PaytmSecurityProbeCases | Where-Object { $_.name -ceq $Case.name -and $_.url -ceq $Case.url -and $_.kind -ceq $Case.kind })
 if($known.Count -ne 1){throw 'SECURITY_UNKNOWN_CASE'}
 $a=@('-q','--silent','--show-error','--connect-timeout','4','--max-time','6','--max-redirs','0',
 '--proxy','http://127.0.0.1:18889','--noproxy','','--head','--output','NUL','--write-out','%{http_connect}|%{ssl_verify_result}|%{http_code}')
 if($Case.kind -ceq 'PIN'){$a+=@('--pinnedpubkey','sha256//AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=')}
 $a+=$Case.url
 return ,$a
}
function Test-PaytmSecurityProbeResult($Case,$Result) {
 $m=$Result.stdout.Trim()
 switch -CaseSensitive ($Case.kind) {
  'CONTROL' {return ($Result.exitCode -eq 0 -and $m -cmatch '^200\|0\|[2-5][0-9]{2}$')}
  'PIN' {return ($Result.exitCode -eq 90 -and $m -ceq '200|0|000')}
  'CONNECT_DENIED' {return ($Result.exitCode -cin @(7,56) -and $m -ceq '403|0|000')}
  'HTTP_DENIED' {return ($Result.exitCode -eq 0 -and $m -ceq '000|0|403')}
  default {return $false}
 }
}
function Invoke-PaytmSecurityProbeBatch([scriptblock]$Run,[scriptblock]$Record) {
 $cases=@(Get-PaytmSecurityProbeCases)
 for($i=0;$i -lt $cases.Count;$i++){
  $c=$cases[$i];$percent=20+10*$i
  Write-Host "[$percent%] $($c.name)"
  Write-Progress -Activity 'Gateway security rejection checks' -Status $c.name -PercentComplete $percent
  $r=& $Run (Get-PaytmSecurityProbeArguments $c)
  $passed=Test-PaytmSecurityProbeResult $c $r
  # Do not retain stderr, response headers, cookies or response bodies.
  $metrics=$r.stdout.Trim();if($metrics -cnotmatch '^\d{3}\|\d+\|\d{3}$'){$metrics='UNPARSED'}
  & $Record ([ordered]@{name=$c.name;passed=$passed;exitCode=$r.exitCode;metrics=$metrics;elapsedSeconds=$r.elapsedSeconds})
  if(-not $passed){throw ('SECURITY_PROBE_FAILED_'+$c.name)}
 }
}
