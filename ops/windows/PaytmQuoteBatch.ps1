function Get-PaytmQuoteBatchAssessment {
 param([object[]]$Samples,[int]$SecurityId,[switch]$RequireFresh)
 if($Samples.Count -ne 3){throw 'SUPERVISED_QUOTE_BATCH_COUNT'}
 $fresh=0;$stale=0;$missing=0;$lastObserved=0
 foreach($q in $Samples){
  if($q.ordersEnabled -ne $false -or $q.fresh -isnot [bool]){throw 'SUPERVISED_QUOTE_BATCH_SCOPE'}
  if($q.status -eq 'NO_QUOTE'){if($q.fresh){throw 'SUPERVISED_QUOTE_BATCH_INVALID'};$missing++;continue}
  if($q.status -notin @('FRESH_QUOTE_OBSERVED','STALE_QUOTE') -or $q.securityId -ne $SecurityId -or $q.exchange -cne 'NSE' -or $q.scripType -cne 'EQUITY' -or $q.timestampEpoch -cne 'PAYTM_1980_SECONDS'){throw 'SUPERVISED_QUOTE_BATCH_IDENTITY'}
  foreach($n in @('observedEpochMilliseconds','tradeEpochMilliseconds','ageMilliseconds','lastPrice')){
   if($null -eq $q.$n -or $q.$n -is [string] -or $q.$n -is [bool]){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  }
  if($q.lastPrice -le 0 -or $q.observedEpochMilliseconds -le $lastObserved -or $q.ageMilliseconds -lt 0 -or ($q.observedEpochMilliseconds-$q.tradeEpochMilliseconds) -ne $q.ageMilliseconds){throw 'SUPERVISED_QUOTE_BATCH_INVALID'}
  $lastObserved=$q.observedEpochMilliseconds
  if($q.status -eq 'FRESH_QUOTE_OBSERVED'){
   if(-not $q.fresh -or $q.ageMilliseconds -gt 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_FRESH'};$fresh++
  }else{if($q.fresh -or $q.ageMilliseconds -le 15000){throw 'SUPERVISED_QUOTE_BATCH_FALSE_STALE'};$stale++}
 }
 return @{status=$(if($fresh -eq 3){'THREE_FRESH_MAPPED_QUOTES'}else{'FRESHNESS_PENDING'});passed=($fresh -eq 3);freshCount=$fresh;staleCount=$stale;missingCount=$missing;sampleCount=3;securityId=$SecurityId;strictFreshRequired=[bool]$RequireFresh;ordersEnabled=$false}
}
