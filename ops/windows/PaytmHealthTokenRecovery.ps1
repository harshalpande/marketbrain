# Definitions only. Recovery is restricted to the reviewed pre-worker failure.
function Read-HealthTokenRecoveryEvidence([string]$Path){
 $null=Assert-PaytmAccountPath $Path
 if((Get-FileHash -LiteralPath $Path).Hash -cne '36B5F94E466A075D7553A73128771FEDB19E3AEE43ACBDCFDD4B0227CBA0DF92'){throw 'HEALTH_TOKEN_RECOVERY_EVIDENCE_MISMATCH'}
 $e=Get-Content -LiteralPath $Path -Raw|ConvertFrom-Json
 if($e.runId -cne '3c51b7f72b3342819ab0dd45bbb62897' -or $e.stage -cne 'ENCRYPT_AND_AUTHENTICATE_AS_HEALTH_ACCOUNT' -or $e.stagingCreated -ne $true -or $e.stageWorker -or $e.freshWorker -or @($e.stageDiagnostics.PSObject.Properties).Count -ne 0){throw 'HEALTH_TOKEN_RECOVERY_EVIDENCE_STATE'}
 $e
}
function Assert-HealthTokenRecoveryFiles([string]$Directory,[string]$Work,$Evidence){
 $null=Assert-PaytmAccountPath $Directory;$null=Assert-PaytmAccountPath $Work
 if(-not (Test-Path -LiteralPath $Directory -PathType Container)){throw 'HEALTH_TOKEN_RECOVERY_DIRECTORY_MISSING'}
 $entries=@(Get-ChildItem -LiteralPath $Directory -Force)
 if($entries.Count -ne 1 -or $entries[0].Name -cne 'library.ps1' -or $entries[0].PSIsContainer){throw 'HEALTH_TOKEN_RECOVERY_UNEXPECTED_FILES'}
 $null=Assert-PaytmAccountPath $entries[0].FullName
 if((Get-FileHash -LiteralPath $entries[0].FullName).Hash -cne $Evidence.sourceHashes.'PaytmHealthTokenCustody.ps1'){throw 'HEALTH_TOKEN_RECOVERY_LIBRARY_CHANGED'}
 # No token ciphertext should exist after a failure before worker launch.
 if(@(Get-ChildItem -LiteralPath $Work -Filter 'token-*.dpapi' -Force).Count){throw 'HEALTH_TOKEN_RECOVERY_CIPHER_EXISTS'}
}
