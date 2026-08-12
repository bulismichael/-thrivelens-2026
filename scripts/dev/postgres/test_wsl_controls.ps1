#Requires -Version 7.0
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$fail=[Collections.Generic.List[string]]::new();$count=0
function A([bool]$ok,[string]$code){$script:count++;if(-not $ok){$fail.Add($code)}}
function Test-ThrowsExact([scriptblock]$Action,[string]$ExpectedCode){
 try{$null=& $Action;return $false}catch{return $_.Exception.Message -ceq $ExpectedCode}
}
function Get-ArrayArgumentTokenText([Management.Automation.Language.CommandAst]$Command,[string]$ParameterName){
 $elements=@($Command.CommandElements)
 for($i=0;$i -lt ($elements.Count-1);$i++){
  if($elements[$i] -is [Management.Automation.Language.CommandParameterAst] -and $elements[$i].ParameterName -ceq $ParameterName){
   $argument=$elements[$i+1]
   if($argument -isnot [Management.Automation.Language.ArrayExpressionAst]){return @()}
   $statements=@($argument.SubExpression.Statements)
   if($statements.Count -ne 1 -or $statements[0] -isnot [Management.Automation.Language.PipelineAst]){return @()}
   $pipelineElements=@($statements[0].PipelineElements)
   if($pipelineElements.Count -ne 1 -or $pipelineElements[0] -isnot [Management.Automation.Language.CommandExpressionAst]){return @()}
   $expression=$pipelineElements[0].Expression
   if($expression -isnot [Management.Automation.Language.ArrayLiteralAst]){return @()}
   return @($expression.Elements|ForEach-Object{$_.Extent.Text})
  }
 }
 return @()
}
try{
 $root=(Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
 $manifest=Get-Content (Join-Path $root 'config\toolchains\backend.json') -Raw|ConvertFrom-Json
 A ([string]$manifest.wsl_fallback.distribution_name -ceq 'ThriveLens-R0') 'DISTRO_NAME'
 A ([string]$manifest.wsl_fallback.distribution_install_root -ceq '%LOCALAPPDATA%\ThriveLens\wsl\ThriveLens-R0') 'DISTRO_ROOT'
 A ([int64]$manifest.wsl_fallback.maximum_vhd_bytes -eq 6442450944) 'VHD_LIMIT'
 A ([string]$manifest.wsl_fallback.pgdg.signing_key_fingerprint -ceq 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8') 'KEY_FINGERPRINT'
 A (@($manifest.wsl_fallback.pgdg.package_closure).Count -eq 9) 'PACKAGE_CLOSURE'
 A ((@($manifest.wsl_fallback.pgdg.held_packages)-join ',') -ceq 'libjson-perl,libllvm19,libpq5,libxslt1.1,postgresql-17,postgresql-client-17,postgresql-client-common,postgresql-common,ssl-cert') 'HOLDS'
 A ([string]$manifest.wsl_fallback.cluster_data_root -ceq '/var/lib/thrivelens/postgresql/r0') 'POSIX_DATA'
 A ([string]$manifest.wsl_fallback.cluster_log_root -ceq '/var/log/thrivelens/postgresql/r0') 'POSIX_LOG'
 A (-not [bool]$manifest.wsl_fallback.logs_persisted) 'NO_RAW_LOG'
 $module=Get-Content (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Raw
 A ($module -match 'BoundedCaptureStream') 'BOUNDED_CAPTURE'
 A ($module -match 'Kill\(\$true\)') 'TREE_KILL'
 A ($module -match "distribution_name -cne 'ThriveLens-R0'") 'EXACT_TARGET'
 A ($module -match 'WSL_CLUSTER_PATH_SYMLINK_REJECTED') 'SYMLINK_GATE'
 A ($module -match 'POSTGRES_PROCESS_STILL_PRESENT') 'PROCESS_ABSENCE'
 A ($module -match 'Local\\ThriveLens-R0-PostgreSQL-Lifecycle') 'LIFECYCLE_LOCK'
 $invokeWslStart=$module.IndexOf('function Invoke-ThriveLensWsl');$invokeWslEnd=$module.IndexOf('function Invoke-ThriveLensDistro',$invokeWslStart);$invokeWslBody=if($invokeWslStart -ge 0 -and $invokeWslEnd -gt $invokeWslStart){$module.Substring($invokeWslStart,$invokeWslEnd-$invokeWslStart)}else{''}
 A ($invokeWslBody -notmatch "--terminate|WSL_PROCESS_TREE_TERMINATION_UNPROVEN") 'GENERIC_WSL_NEVER_TERMINATES_DISTRO'
 $terminateStart=$module.IndexOf('function Stop-ThriveLensDistroAndVerify');$terminateEnd=$module.IndexOf('function Assert-ThriveLensDistroStopped',$terminateStart);$terminateBody=if($terminateStart -ge 0 -and $terminateEnd -gt $terminateStart){$module.Substring($terminateStart,$terminateEnd-$terminateStart)}else{''}
 A ($terminateBody -match 'IdentityToken' -and $terminateBody -match 'LifecycleLock' -and $terminateBody -match 'Assert-ThriveLensWslCleanupIdentity' -and $terminateBody -match 'finally') 'TERMINATE_REVALIDATES_IDENTITY_PRE_POST'
 $runtimeModule=Get-Content (Join-Path $PSScriptRoot 'Runtime.psm1') -Raw
 $readerStart=$runtimeModule.IndexOf('function Read-ThriveLensPostgresBootstrapSecret');$readerEnd=if($readerStart -ge 0){$runtimeModule.IndexOf('function Resolve-ThriveLensStartChildFailure',$readerStart)}else{-1};$readerBody=if($readerStart -ge 0 -and $readerEnd -gt $readerStart){$runtimeModule.Substring($readerStart,$readerEnd-$readerStart)}else{''}
 A ($readerBody -match 'Assert-ThriveLensSecretRootAcl') 'SECRET_READER_PARENT_ACL'
 A ($readerBody -match 'Assert-ThriveLensSecretFileAclRules') 'SECRET_READER_FILE_ACL'
 A ($readerBody -match '\[IO\.FileShare\]::None') 'SECRET_READER_EXCLUSIVE_OPEN'
 Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
 $identityToken=[pscustomobject]@{SchemaVersion=1;RegistryId='11111111-1111-1111-1111-111111111111';DistributionName='ThriveLens-R0';Version=2;BasePath='C:\Synthetic\ThriveLens-R0';VhdPath='C:\Synthetic\ThriveLens-R0\ext4.vhdx';VhdIdentity='00000001:0000000000000001'}
 $sameIdentity=[pscustomobject]@{SchemaVersion=1;RegistryId=$identityToken.RegistryId;DistributionName=$identityToken.DistributionName;Version=2;BasePath=$identityToken.BasePath;VhdPath=$identityToken.VhdPath;VhdIdentity=$identityToken.VhdIdentity}
 A (Compare-ThriveLensWslCleanupIdentityToken -Expected $identityToken -Actual $sameIdentity) 'CLEANUP_IDENTITY_EXACT_ACCEPTED'
 $replacementIdentity=[pscustomobject]@{SchemaVersion=1;RegistryId='22222222-2222-2222-2222-222222222222';DistributionName='ThriveLens-R0';Version=2;BasePath=$identityToken.BasePath;VhdPath=$identityToken.VhdPath;VhdIdentity='00000001:0000000000000002'}
 A (Test-ThrowsExact {Compare-ThriveLensWslCleanupIdentityToken -Expected $identityToken -Actual $replacementIdentity} 'WSL_CLEANUP_IDENTITY_CHANGED') 'CLEANUP_SAME_NAME_REPLACEMENT_REJECTED'
 $unownedLock=[Threading.Mutex]::new($false)
 try{A (Test-ThrowsExact {Stop-ThriveLensDistroAndVerify -IdentityToken $identityToken -LifecycleLock $unownedLock} 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED') 'TERMINATE_WITHOUT_HELD_LOCK_REJECTED'}finally{$unownedLock.Dispose()}
 $nativeLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2
 try{
  A ([ThriveLens.MutexOwnershipVerifier]::IsOwnedByCurrentThread($nativeLock)) 'NATIVE_CURRENT_THREAD_MUTEX_OWNERSHIP'
  A (-not [ThriveLens.MutexOwnershipVerifier]::CheckFromNewThread($nativeLock)) 'NATIVE_CROSS_THREAD_MUTEX_REJECTED'
 }finally{Exit-ThriveLensLifecycleLock -Mutex $nativeLock}
 $releasedLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2
 try{
  $releasedLock.ReleaseMutex()
  A (Test-ThrowsExact {Stop-ThriveLensDistroAndVerify -IdentityToken $identityToken -LifecycleLock $releasedLock} 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED') 'NATIVE_RELEASED_MUTEX_REJECTED'
  $null=$releasedLock.WaitOne(0)
 }finally{Exit-ThriveLensLifecycleLock -Mutex $releasedLock}
 $wrongPasswordPath='/run/thrivelens-r0-wrong-0123456789abcdef0123456789abcdef.pgpass'
 $otherWrongPasswordPath='/run/thrivelens-r0-wrong-fedcba9876543210fedcba9876543210.pgpass'
 $authError='psql: error: connection to server at "127.0.0.1", port 55432 failed: FATAL:  password authentication failed for user "tl_bootstrap"'
 $passwordFileError='password retrieved from file "'+$wrongPasswordPath+'"'
 $acceptedAuthDiagnostics=@(
  ($authError+"`n"+$passwordFileError),($authError+"`n"+$passwordFileError+"`n")
 )
 A ($acceptedAuthDiagnostics.Count -eq 2) 'WRONG_PASSWORD_ACCEPTED_MATRIX_COMPLETE'
 foreach($acceptedDiagnostic in $acceptedAuthDiagnostics){
  $authRejected=Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $acceptedDiagnostic -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true
  A ($authRejected.Status -ceq 'AUTHENTICATION_REJECTED' -and $authRejected.ExitCode -eq 2) 'WRONG_PASSWORD_EXACT_REJECTION_ACCEPTED'
 }
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 0 -PrivateStandardOutput '1' -PrivateStandardError '' -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_WAS_ACCEPTED') 'WRONG_PASSWORD_SUCCESS_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput ' ' -PrivateStandardError $authError -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNEXPECTED_OUTPUT') 'WRONG_PASSWORD_WHITESPACE_STDOUT_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 1 -PrivateStandardOutput '' -PrivateStandardError ($authError+"`n"+$passwordFileError) -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_WRONG_EXIT_REJECTED'
 $authNearMisses=@(
  $authError,($authError+"`n"),($authError+"`r`n"),
  ('prefix'+$authError),($authError+' suffix'),($authError+"`n`n"),($authError+"`r`n`r`n"),
  ($authError -replace '127\.0\.0\.1','localhost'),($authError -replace '55432','55433'),
  ($authError -replace 'tl_bootstrap','postgres'),(($authError -replace 'FATAL','fatal')+"`n"+$passwordFileError),'psql: error: client executable failure',
  $passwordFileError,($authError+"`npassword retrieved from file `"$otherWrongPasswordPath`""),
  ($authError+"`n"+$passwordFileError+' suffix'),($authError+"`n"+$passwordFileError+"`nextra"),
  ($authError+"`n"+$passwordFileError+"`n`n"),($authError+"`r"),
  ($authError+"`n"+$passwordFileError+"`r"),($authError+"`r`n"+$passwordFileError+"`r`n"),
  ($authError+"`t")
 )
 A ($authNearMisses.Count -eq 21) 'WRONG_PASSWORD_NEAR_MISS_MATRIX_COMPLETE'
 foreach($nearMiss in $authNearMisses){
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $nearMiss -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_DIAGNOSTIC_NEAR_MISS_REJECTED'
 }
 foreach($hostileDiagnostic in @(
  ($authError+[char]0),($authError+[char]0x00e9),[string]::new('x',513)
 )){
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $hostileDiagnostic -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_HOSTILE_DIAGNOSTIC_REJECTED'
 }
 foreach($invalidExpectedPath in @(
  '/run/thrivelens-r0-wrong-0123456789ABCDEF0123456789abcdef.pgpass',
  '/run/thrivelens-r0-auth-0123456789abcdef0123456789abcdef.pgpass',
  ($wrongPasswordPath+'.extra'),($wrongPasswordPath+"`n")
 )){
  $invalidPathDiagnostic=$authError+"`npassword retrieved from file `"$invalidExpectedPath`""
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $invalidPathDiagnostic -ExpectedPasswordFile $invalidExpectedPath -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_EXPECTED_PATH_REJECTED'
 }
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError ($authError+"`n"+$passwordFileError) -ExpectedPasswordFile $wrongPasswordPath -ServerUsableAfterProbe $false} 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED') 'WRONG_PASSWORD_SERVER_UNUSABLE_REJECTED'
 $secretValue=$null
 try{
  $secretPath=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.wsl_fallback.host_password_file))
  $secretValue=Read-ThriveLensPostgresBootstrapSecret -Path $secretPath
  A ($secretValue -cmatch '^[A-Za-z0-9_-]{43,128}$') 'EXECUTABLE_PROTECTED_SECRET_READER'
 }finally{$secretValue=$null;Remove-Variable -Name secretValue -ErrorAction SilentlyContinue}
 $budget=[ThriveLens.OutputBudget]::new(8);$sinkA=[ThriveLens.BoundedCaptureStream]::new($budget);$sinkB=[ThriveLens.BoundedCaptureStream]::new($budget)
 try{$sinkA.Write([byte[]](1,2,3,4),0,4);$sinkB.Write([byte[]](5,6,7,8),0,4);try{$sinkA.Write([byte[]](9),0,1)}catch{};A ($budget.Exceeded -and ($sinkA.Length+$sinkB.Length) -eq 8) 'EXECUTABLE_SHARED_OUTPUT_CAP'}finally{$sinkA.Dispose();$sinkB.Dispose()}
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 1 -PathPolicyValid $false -VersionExitCode 1 -VersionOutput '' -ControlExitCode 1 -ChecksumsEnabled $false) -ceq 'ABSENT') 'CLUSTER_CLASSIFIER_ABSENT'
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode 0 -VersionOutput '17' -ControlExitCode 0 -ChecksumsEnabled $true) -ceq 'VALID') 'CLUSTER_CLASSIFIER_VALID'
 A ((Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode 0 -VersionOutput '16' -ControlExitCode 0 -ChecksumsEnabled $true) -ceq 'PARTIAL_OR_INVALID') 'CLUSTER_CLASSIFIER_PARTIAL'
 $fatalChild=Resolve-ThriveLensChildOutcome -ExitCode 3 -IndependentCleanupVerified $true;A ($fatalChild.Fatal -and $fatalChild.ExitCode -eq 3) 'CHILD_FATAL_PRESERVED'
 $unsafeChild=Resolve-ThriveLensChildOutcome -ExitCode 2 -IndependentCleanupVerified $false;A ($unsafeChild.Fatal -and $unsafeChild.ExitCode -eq 3) 'CHILD_CLEANUP_UNVERIFIED_FATAL'
 $startOk=Resolve-ThriveLensStartChildExit -ExitCode 0;A ($startOk.Status -ceq 'STARTED' -and -not $startOk.Fatal -and -not $startOk.FreshCleanupAllowed) 'START_EXIT_ZERO_ACCEPTED'
 $startBlocked=Resolve-ThriveLensStartChildExit -ExitCode 2;A ($startBlocked.Status -ceq 'BLOCKED' -and -not $startBlocked.Fatal -and -not $startBlocked.FreshCleanupAllowed) 'START_EXIT_TWO_FRESH_CLEANUP_DENIED'
 foreach($unexpectedExit in @(1,3,255)){$startFatal=Resolve-ThriveLensStartChildExit -ExitCode $unexpectedExit;A ($startFatal.Fatal -and -not $startFatal.FreshCleanupAllowed -and $startFatal.ExitCode -eq 3) 'START_UNKNOWN_OR_FATAL_EXIT_DEFAULT_DENY'}
 $preTokenBlocked=Resolve-ThriveLensPreTokenStartObservation -StartExitCode 2 -DistroAbsent $true -HostPortAbsent $true
 A (-not $preTokenBlocked.Fatal -and $preTokenBlocked.ExitCode -eq 2 -and $preTokenBlocked.CleanupVerified) 'START_EXIT_TWO_READ_ONLY_ABSENCE_ACCEPTED'
 foreach($absenceCase in @(@($false,$true),@($true,$false),@($false,$false))){$preTokenFatal=Resolve-ThriveLensPreTokenStartObservation -StartExitCode 2 -DistroAbsent $absenceCase[0] -HostPortAbsent $absenceCase[1];A ($preTokenFatal.Fatal -and $preTokenFatal.ExitCode -eq 3 -and -not $preTokenFatal.CleanupVerified) 'START_EXIT_TWO_ABSENCE_UNVERIFIED_FATAL'}
 foreach($unexpectedExit in @(1,3,255)){$preTokenFatal=Resolve-ThriveLensPreTokenStartObservation -StartExitCode $unexpectedExit -DistroAbsent $true -HostPortAbsent $true;A ($preTokenFatal.Fatal -and $preTokenFatal.ExitCode -eq 3 -and -not $preTokenFatal.CleanupVerified) 'START_UNEXPECTED_EXIT_OBSERVATION_DEFAULT_DENY'}
 $preTokenBlockedFinal=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $preTokenBlocked.Code -OriginalExitCode $preTokenBlocked.ExitCode -CleanupRequired $true -CleanupAuthorityVerified $preTokenBlocked.CleanupVerified -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($preTokenBlockedFinal.CleanupVerified -and $preTokenBlockedFinal.Status -ceq 'BLOCKED' -and $preTokenBlockedFinal.ExitCode -eq 2) 'START_EXIT_TWO_COMPOSED_CLEANUP_TRUTH'
 foreach($unexpectedExit in @(1,3,255)){$preTokenFatal=Resolve-ThriveLensPreTokenStartObservation -StartExitCode $unexpectedExit -DistroAbsent $true -HostPortAbsent $true;$preTokenFatalFinal=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $preTokenFatal.Code -OriginalExitCode $preTokenFatal.ExitCode -CleanupRequired $true -CleanupAuthorityVerified $preTokenFatal.CleanupVerified -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false;A (-not $preTokenFatalFinal.CleanupVerified -and $preTokenFatalFinal.Status -ceq 'ERROR' -and $preTokenFatalFinal.ExitCode -eq 3 -and @($preTokenFatalFinal.FailureStages) -contains 'IDENTITY') 'START_UNEXPECTED_EXIT_COMPOSED_CLEANUP_DEFAULT_DENY'}
 foreach($safeCredentialFailure in @('WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED')){A (Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $safeCredentialFailure) 'CREDENTIAL_CONTAINED_REMOVE_FAILURE_ALLOWS_ABSENCE_PROBE'}
 foreach($unsafeCredentialFailure in @('WSL_GUARDED_COMMAND_CONTAINMENT_FAILED','WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','arbitrary secret text')){A (-not (Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $unsafeCredentialFailure)) 'CREDENTIAL_UNSAFE_REMOVE_FAILURE_BLOCKS_ABSENCE_PROBE'}
 foreach($stopAuthorityCode in @('POSTGRES_STOP_FAILED','POSTGRES_CLUSTER_STILL_RUNNING','WSL_COMMAND_TIMEOUT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $stopAuthorityCode) 'POSTGRES_STOP_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($stopAbsenceCode in @('POSTGRES_CLUSTER_STILL_RUNNING','POSTGRES_LISTENER_STILL_PRESENT','POSTGRES_PROCESS_STILL_PRESENT')){$stopAbsenceOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $stopAbsenceCode -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $true -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false;A ($stopAbsenceOutcome.OriginalCode -ceq $stopAbsenceCode -and $stopAbsenceOutcome.CleanupVerified -and @($stopAbsenceOutcome.FailureStages) -contains 'POSTGRES_STOP' -and (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $stopAbsenceCode)) 'POSTGRES_STOP_ABSENCE_CODE_COMPOSED_AND_PRESERVED'}
 foreach($terminateAuthorityCode in @('WSL_DISTRO_TERMINATE_FAILED','WSL_COMMAND_TIMEOUT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_TERMINATE' -FailureCode $terminateAuthorityCode) 'TERMINATE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($distroAbsenceAuthorityCode in @('WSL_RUNNING_STATE_UNAVAILABLE','WSL_DISTRO_STILL_RUNNING')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_ABSENCE' -FailureCode $distroAbsenceAuthorityCode) 'DISTRO_ABSENCE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 foreach($hostAbsenceAuthorityCode in @('HOST_LISTENER_MEASUREMENT_UNAVAILABLE','HOST_POSTGRES_LISTENER_STILL_PRESENT','HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE','HOST_PORTPROXY_STILL_PRESENT')){A (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'HOST_ABSENCE' -FailureCode $hostAbsenceAuthorityCode) 'HOST_ABSENCE_OPERATIONAL_FAILURE_RETAINS_OLD_TOKEN_AUTHORITY'}
 $distroAbsenceFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode 'WSL_DISTRO_STILL_RUNNING';A ($distroAbsenceFailure.Stage -ceq 'DISTRO_ABSENCE' -and $distroAbsenceFailure.IdentityAuthorityPreserved) 'DISTRO_ABSENCE_FAILURE_EXACTLY_CLASSIFIED'
 $hostAbsenceFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode 'HOST_POSTGRES_LISTENER_STILL_PRESENT';A ($hostAbsenceFailure.Stage -ceq 'HOST_ABSENCE' -and $hostAbsenceFailure.IdentityAuthorityPreserved) 'HOST_ABSENCE_FAILURE_EXACTLY_CLASSIFIED'
 foreach($unsafeDistroCleanupCode in @('WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','arbitrary secret text')){$unsafeDistroCleanup=Resolve-ThriveLensDistroCleanupFailure -FailureCode $unsafeDistroCleanupCode;A (-not $unsafeDistroCleanup.IdentityAuthorityPreserved) 'DISTRO_CLEANUP_IDENTITY_OR_UNKNOWN_DEFAULT_DENY'}
 foreach($identityFailureCode in @('WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED','WSL_STORAGE_REPARSE_REJECTED','arbitrary secret text')){A (-not (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode $identityFailureCode)) 'POSTGRES_STOP_IDENTITY_OR_UNKNOWN_FAILURE_DEFAULT_DENY';A (-not (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'DISTRO_TERMINATE' -FailureCode $identityFailureCode)) 'TERMINATE_IDENTITY_OR_UNKNOWN_FAILURE_DEFAULT_DENY'}
 $credentialClean=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $true -AbsenceAttempted $true -AbsenceVerified $true -RootFailureCode $null;A ($credentialClean.CredentialAbsenceVerified -and $null -eq $credentialClean.FailureCode -and $null -eq $credentialClean.RootFailureCode -and $credentialClean.FailureStages.Count -eq 0) 'CREDENTIAL_CLEANUP_SUCCESS_CLASSIFIED'
 $credentialRemoveAnomaly=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $false -AbsenceAttempted $true -AbsenceVerified $true -RootFailureCode 'WSL_COMMAND_TIMEOUT';A ($credentialRemoveAnomaly.CredentialAbsenceVerified -and $credentialRemoveAnomaly.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $credentialRemoveAnomaly.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and @($credentialRemoveAnomaly.FailureStages) -ceq 'CREDENTIAL_REMOVE') 'CREDENTIAL_REMOVE_FAILURE_WITH_ABSENCE_CLASSIFIED'
 $credentialAbsenceMissing=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $true -AbsenceAttempted $true -AbsenceVerified $false -RootFailureCode 'WSL_COMMAND_TIMEOUT';A (-not $credentialAbsenceMissing.CredentialAbsenceVerified -and $credentialAbsenceMissing.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $credentialAbsenceMissing.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and @($credentialAbsenceMissing.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'CREDENTIAL_ABSENCE_FAILURE_CLASSIFIED'
 $credentialContainmentBlocked=Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $false -AbsenceAttempted $false -AbsenceVerified $false -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED';A (-not $credentialContainmentBlocked.CredentialAbsenceVerified -and $credentialContainmentBlocked.RootFailureCode -ceq 'WSL_CLEANUP_IDENTITY_CHANGED' -and @($credentialContainmentBlocked.FailureStages) -contains 'CREDENTIAL_REMOVE' -and @($credentialContainmentBlocked.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'CREDENTIAL_CONTAINMENT_FAILURE_NO_FOLLOW_ON_CLASSIFIED'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode 'SCRAM_AUTH_PROBE_FAILED' -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'SCRAM_AUTH_PROBE_FAILED') 'CREDENTIAL_CAUSE_PRIMARY_WINS'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'WSL_CLEANUP_IDENTITY_CHANGED') 'CREDENTIAL_CAUSE_ROOT_WINS_WITHOUT_PRIMARY'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode $null -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') 'CREDENTIAL_CAUSE_CLEANUP_FALLBACK'
 A ((Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'raw private detail' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') -ceq 'RUNTIME_TEST_INTERNAL_ERROR') 'CREDENTIAL_CAUSE_UNKNOWN_SANITIZED_DEFAULT_DENY'
 $gracefulRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $true -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($gracefulRecovered.CleanupVerified -and $gracefulRecovered.Status -ceq 'BLOCKED' -and $gracefulRecovered.Code -ceq 'SCRAM_AUTH_PROBE_FAILED' -and @($gracefulRecovered.FailureStages) -contains 'POSTGRES_STOP') 'RUNTIME_GRACEFUL_FAILURE_FINAL_CONTAINMENT_TRUTH'
 $terminateRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $true -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($terminateRecovered.CleanupVerified -and @($terminateRecovered.FailureStages) -contains 'DISTRO_TERMINATE') 'RUNTIME_TERMINATE_ANOMALY_FINAL_CONTAINMENT_TRUTH'
 $distroAbsenceRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $true -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($distroAbsenceRecovered.CleanupVerified -and @($distroAbsenceRecovered.FailureStages) -contains 'DISTRO_ABSENCE' -and @($distroAbsenceRecovered.FailureStages) -notcontains 'DISTRO_TERMINATE') 'RUNTIME_RECOVERED_DISTRO_ABSENCE_EXACT_STAGE'
 $hostAbsenceRecovered=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $true -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($hostAbsenceRecovered.CleanupVerified -and @($hostAbsenceRecovered.FailureStages) -contains 'HOST_ABSENCE' -and @($hostAbsenceRecovered.FailureStages) -notcontains 'DISTRO_TERMINATE') 'RUNTIME_RECOVERED_HOST_ABSENCE_EXACT_STAGE'
 $hostUnverified=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $false -LockReleaseFailed $false
 A (-not $hostUnverified.CleanupVerified -and $hostUnverified.Status -ceq 'ERROR' -and $hostUnverified.Code -ceq 'RUNTIME_CLEANUP_FAILED' -and @($hostUnverified.FailureStages) -contains 'HOST_ABSENCE') 'RUNTIME_FINAL_HOST_ABSENCE_REQUIRED'
 $identityChangedOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $true -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A (-not $identityChangedOutcome.CleanupVerified -and $identityChangedOutcome.Code -ceq 'RUNTIME_CLEANUP_IDENTITY_CHANGED' -and @($identityChangedOutcome.FailureStages) -contains 'IDENTITY') 'RUNTIME_IDENTITY_DRIFT_FATAL'
 $credentialUnverifiedOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $false -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A (-not $credentialUnverifiedOutcome.CleanupVerified -and $credentialUnverifiedOutcome.Code -ceq 'RUNTIME_CLEANUP_FAILED' -and $credentialUnverifiedOutcome.OriginalCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED') 'RUNTIME_CREDENTIAL_ABSENCE_REQUIRED'
 $primaryWithRemoveAnomaly=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithRemoveAnomaly.OriginalCode -ceq 'SCRAM_AUTH_PROBE_FAILED' -and $primaryWithRemoveAnomaly.ExitCode -eq 3 -and $primaryWithRemoveAnomaly.CleanupVerified -and @($primaryWithRemoveAnomaly.FailureStages) -contains 'PROBE' -and @($primaryWithRemoveAnomaly.FailureStages) -contains 'CREDENTIAL_REMOVE') 'RUNTIME_PRIMARY_FAILURE_SURVIVES_CREDENTIAL_REMOVE_ANOMALY'
 $primaryWithAbsenceFailure=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithAbsenceFailure.OriginalCode -ceq 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE' -and -not $primaryWithAbsenceFailure.CleanupVerified -and @($primaryWithAbsenceFailure.FailureStages) -contains 'CREDENTIAL_REMOVE' -and @($primaryWithAbsenceFailure.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_PRIMARY_FAILURE_SURVIVES_CREDENTIAL_ABSENCE_FAILURE'
 $primaryWithIdentityCredentialFailure=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialRootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($primaryWithIdentityCredentialFailure.OriginalCode -ceq 'SCRAM_AUTH_PROBE_FAILED' -and -not $primaryWithIdentityCredentialFailure.CleanupVerified -and @($primaryWithIdentityCredentialFailure.FailureStages) -contains 'IDENTITY' -and @($primaryWithIdentityCredentialFailure.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_CREDENTIAL_ROOT_CAUSE_COMPOSED_WITH_PRIMARY'
 $rootOnlyCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $null -RootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CleanupCode 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED'
 $rootOnlyOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode $rootOnlyCode -OriginalExitCode 3 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $true -CredentialRemoveFailed $true -CredentialRootFailureCode 'WSL_CLEANUP_IDENTITY_CHANGED' -CredentialAbsenceVerified $false -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $false
 A ($rootOnlyOutcome.OriginalCode -ceq 'WSL_CLEANUP_IDENTITY_CHANGED' -and -not $rootOnlyOutcome.CleanupVerified -and @($rootOnlyOutcome.FailureStages) -contains 'IDENTITY' -and @($rootOnlyOutcome.FailureStages) -contains 'CREDENTIAL_ABSENCE') 'RUNTIME_CREDENTIAL_ROOT_CAUSE_BECOMES_PRIMARY_WHEN_ALONE'
 $lockReleaseOutcome=Resolve-ThriveLensRuntimeCleanupOutcome -OriginalCode 'SCRAM_AUTH_PROBE_FAILED' -OriginalExitCode 2 -CleanupRequired $true -CleanupAuthorityVerified $true -CredentialCleanupRequired $false -CredentialRemoveFailed $false -CredentialAbsenceVerified $true -IdentityChanged $false -PostgresStopFailed $false -DistroTerminateFailed $false -DistroAbsenceCheckFailed $false -HostAbsenceCheckFailed $false -DistroAbsent $true -HostAbsent $true -LockReleaseFailed $true
 A ($lockReleaseOutcome.CleanupVerified -and $lockReleaseOutcome.Status -ceq 'ERROR' -and $lockReleaseOutcome.Code -ceq 'RUNTIME_LOCK_RELEASE_FAILED' -and @($lockReleaseOutcome.FailureStages) -contains 'LOCK_RELEASE') 'RUNTIME_LOCK_RELEASE_SEPARATE_FROM_PHYSICAL_CONTAINMENT'
 $containmentBlocked=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED' -SameTokenContainmentReverified $false
 A ($containmentBlocked.RequiresRecontainment -and -not $containmentBlocked.AllowGuestCleanup -and $containmentBlocked.Fatal) 'CLEANUP_CONTAINMENT_FAILURE_BLOCKS_GUEST_CLEANUP'
 $containmentRecovered=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED' -SameTokenContainmentReverified $true
 A ($containmentRecovered.RequiresRecontainment -and $containmentRecovered.AllowGuestCleanup -and $containmentRecovered.Fatal) 'CLEANUP_CONTAINMENT_REVERIFY_REQUIRED'
 $unknownContainment=Resolve-ThriveLensCleanupContainmentPolicy -FailureCode 'not-sanitized' -SameTokenContainmentReverified $true
 A ($unknownContainment.RequiresRecontainment -and -not $unknownContainment.AllowGuestCleanup -and $unknownContainment.Fatal) 'CLEANUP_UNKNOWN_FAILURE_DEFAULT_DENY'
 $dataRoot='/var/lib/thrivelens/postgresql/r0';$logRoot='/var/log/thrivelens/postgresql/r0';$treeLimit=[int64]134217728;$stagingRoot='/var/lib/thrivelens/postgresql/.r0-staging-0123456789abcdef0123456789abcdef'
 $dataPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $dataRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($dataPolicy.Kind -ceq 'DATA' -and $dataPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_DATA_ACCEPTED'
 $logPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $logRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($logPolicy.Kind -ceq 'LOG' -and $logPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_LOG_ACCEPTED'
 $stagingPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $stagingRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($stagingPolicy.Kind -ceq 'STAGING' -and $stagingPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_STAGING_ACCEPTED'
 A (Test-ThrowsExact {Assert-ThriveLensLinuxTreePolicy -Root $stagingRoot} 'LINUX_TREE_GUARD_REQUIRED') 'POST_MUTATION_TREE_INSPECTION_REQUIRES_CONTAINMENT_GUARD'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root '/tmp/r0' -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit} 'LINUX_TREE_ROOT_CONTRACT_MISMATCH') 'TREE_ROOT_OUTSIDE_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root '/var/lib/thrivelens/postgresql/../r0' -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit} 'LINUX_TREE_ROOT_CONTRACT_MISMATCH') 'TREE_ROOT_MALFORMED_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensLinuxTreeRootPolicy -Root $stagingRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes 134217729} 'LINUX_TREE_LIMIT_CONTRACT_MISMATCH') 'TREE_ROOT_OVERSIZE_LIMIT_REJECTED'
 $proxyListen=Resolve-ThriveLensPortProxyMapping -Source '127.0.0.1/55432' -Destination '127.0.0.1/12345';A ($proxyListen.ListenPort -eq 55432 -and $proxyListen.ConnectPort -eq 12345) 'PORTPROXY_LISTEN_TARGET_PARSED'
 $proxyConnect=Resolve-ThriveLensPortProxyMapping -Source '127.0.0.1/12345' -Destination '127.0.0.1/55432';A ($proxyConnect.ListenPort -eq 12345 -and $proxyConnect.ConnectPort -eq 55432) 'PORTPROXY_CONNECT_TARGET_PARSED'
 A (Test-ThrowsExact {Resolve-ThriveLensPortProxyMapping -Source 'malformed' -Destination '127.0.0.1/55432'} 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE') 'PORTPROXY_MALFORMED_REJECTED'
 $holderInfo=[Diagnostics.ProcessStartInfo]::new();$holderInfo.FileName=(Join-Path $PSHOME 'pwsh.exe');$holderInfo.UseShellExecute=$false;$holderInfo.RedirectStandardOutput=$true;$holderInfo.CreateNoWindow=$true
 $null=$holderInfo.ArgumentList.Add('-NoProfile');$null=$holderInfo.ArgumentList.Add('-Command');$null=$holderInfo.ArgumentList.Add('$m=[Threading.Mutex]::new($false,''Local\ThriveLens-R0-PostgreSQL-Lifecycle'');$null=$m.WaitOne();[Console]::Out.WriteLine(''READY'');Start-Sleep -Seconds 3;$m.ReleaseMutex();$m.Dispose()')
 $holder=[Diagnostics.Process]::Start($holderInfo)
 $holderReaped=$false
 try{
  $ready=$null;$readyTask=$holder.StandardOutput.ReadLineAsync();$readyObserved=$false
  try{if($readyTask.Wait(5000)){$ready=$readyTask.GetAwaiter().GetResult();$readyObserved=$ready -ceq 'READY'}}catch{}
  $lockCode=$null
  if($readyObserved){try{$probeLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 1;Exit-ThriveLensLifecycleLock -Mutex $probeLock}catch{$lockCode=$_.Exception.Message}}
 A ($readyObserved -and $lockCode -ceq 'LIFECYCLE_LOCK_TIMEOUT') 'EXECUTABLE_LOCK_TIMEOUT'
 }finally{
  try{
   $holderReaped=$holder.WaitForExit(5000)
   if(-not $holderReaped){
    try{$holder.Kill($true)}catch{if(-not $holder.HasExited){throw}}
    $holderReaped=$holder.WaitForExit(5000)
   }
  }catch{$holderReaped=$false}
  $holder.Dispose()
 }
 A $holderReaped 'EXECUTABLE_LOCK_HOLDER_REAP'
 $abandonInfo=[Diagnostics.ProcessStartInfo]::new();$abandonInfo.FileName=(Join-Path $PSHOME 'pwsh.exe');$abandonInfo.UseShellExecute=$false;$abandonInfo.RedirectStandardOutput=$true;$abandonInfo.CreateNoWindow=$true
 $null=$abandonInfo.ArgumentList.Add('-NoProfile');$null=$abandonInfo.ArgumentList.Add('-Command');$null=$abandonInfo.ArgumentList.Add('$m=[Threading.Mutex]::new($false,''Local\ThriveLens-R0-PostgreSQL-Lifecycle'');$null=$m.WaitOne();[Console]::Out.WriteLine(''READY'');Start-Sleep -Milliseconds 750;[Environment]::Exit(0)')
 $abandon=[Diagnostics.Process]::Start($abandonInfo);$abandonedRecovered=$false
 try{
  $abandonReadyTask=$abandon.StandardOutput.ReadLineAsync();$abandonReady=$abandonReadyTask.Wait(5000) -and $abandonReadyTask.GetAwaiter().GetResult() -ceq 'READY'
  if($abandonReady){$recoveredLock=Enter-ThriveLensLifecycleLock -TimeoutSeconds 2;try{$abandonedRecovered=$true}finally{Exit-ThriveLensLifecycleLock -Mutex $recoveredLock}}
  $abandonExited=$abandon.WaitForExit(5000);$abandonedRecovered=$abandonedRecovered -and $abandonExited
 }finally{if(-not $abandon.HasExited){try{$abandon.Kill($true);$null=$abandon.WaitForExit(5000)}catch{}};$abandon.Dispose()}
 A $abandonedRecovered 'EXECUTABLE_ABANDONED_LOCK_RECOVERY'
 $initialize=Get-Content (Join-Path $PSScriptRoot 'initialize.ps1') -Raw
 $stagingGuard='Assert-ThriveLensLinuxTreePolicy -Root $staging -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock';$firstStagingGuard=$initialize.IndexOf($stagingGuard);$lastStagingGuard=$initialize.LastIndexOf($stagingGuard);$activationAttempted=$initialize.IndexOf('$activationAttempted=$true');$activationMove=$initialize.IndexOf('$move=Invoke-ThriveLensGuardedDistro');$rollbackDelete=$initialize.IndexOf('rm_tree(fd)')
 A ($initialize -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$passwordPath') 'INITIALIZE_PROTECTED_SECRET_READER'
 A ($firstStagingGuard -ge 0 -and $activationMove -gt $firstStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_MOVE'
 A ($lastStagingGuard -gt $activationMove -and $rollbackDelete -gt $lastStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_ROLLBACK'
 $treeFunctionStart=$module.IndexOf('function Assert-ThriveLensLinuxTreePolicy');$treeFunctionEnd=$module.IndexOf('function Assert-ThriveLensLinuxPathPolicy',$treeFunctionStart);$treeFunctionBody=if($treeFunctionStart -ge 0 -and $treeFunctionEnd -gt $treeFunctionStart){$module.Substring($treeFunctionStart,$treeFunctionEnd-$treeFunctionStart)}else{''}
 A ($treeFunctionBody -match "Kind -ceq 'STAGING'.*LINUX_TREE_GUARD_REQUIRED" -and $treeFunctionBody -match 'Invoke-ThriveLensGuardedDistro -IdentityToken \$IdentityToken -LifecycleLock \$LifecycleLock') 'POST_MUTATION_TREE_SUPERVISOR_IDENTITY_FENCED'
 A ($initialize -match "fdinfo/'\+str\(fd\)" -and $initialize -match 'mount_id\(parentfd\) != trustedmount' -and $initialize -match 'rootmount != trustedmount' -and $initialize -match 'mount_id\(child\) != rootmount' -and $initialize -match 'mount_id\(leaf\) != rootmount' -and $initialize -notmatch 'shutil\.rmtree') 'INITIALIZE_FD_RELATIVE_MOUNT_FENCED_ROLLBACK'
 A ($activationAttempted -ge 0 -and $activationAttempted -lt $activationMove -and $initialize -match 'if\(\$activationAttempted -or \$activated\)\{\$fatalCleanup=\$true\}') 'INITIALIZE_ACTIVATION_ATTEMPT_FATAL'
 A ($initialize -match '\$null -ne \$staging -and -not \$activationAttempted -and -not \$activated') 'INITIALIZE_NO_ROLLBACK_AFTER_ACTIVATION_ATTEMPT'
 A ($initialize -match '\$wslTouched=\$true' -and $initialize -match 'if\(\$cleanupIdentityReady -and \(\$wslTouched -or \$mutated -or \$activationAttempted\)\)') 'INITIALIZE_ALL_POST_PREFLIGHT_WSL_PATHS_CLEANED'
 $mutationMarker=$initialize.IndexOf('$mutated = $true');$directoryLoop=$initialize.IndexOf('foreach($directory');A ($mutationMarker -ge 0 -and $directoryLoop -gt $mutationMarker) 'INITIALIZE_MUTATION_TRACKED_BEFORE_DIRECTORY_CREATE'
 $validBranchStart=$initialize.IndexOf("if(`$clusterState -ceq 'VALID')");$validBranchEnd=$initialize.IndexOf("if(`$clusterState -cne 'ABSENT')",$validBranchStart);$validBranch=if($validBranchStart -ge 0 -and $validBranchEnd -gt $validBranchStart){$initialize.Substring($validBranchStart,$validBranchEnd-$validBranchStart)}else{''};A ($validBranch -match 'Stop-ThriveLensDistroAndVerify' -and $validBranch -match 'Assert-ThriveLensHostPortAbsent') 'INITIALIZE_IDEMPOTENT_CLEANUP'
 $startRaw=Get-Content (Join-Path $PSScriptRoot 'start.ps1') -Raw
 $startTokens=$null;$startErrors=$null;$startAst=[Management.Automation.Language.Parser]::ParseInput($startRaw,[ref]$startTokens,[ref]$startErrors);$startTries=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.TryStatementAst]},$true));$gracefulTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensPostgresUnderLock'});$forcedTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensDistroAndVerify'});$combinedTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensPostgresUnderLock' -and $_.Body.Extent.Text -match 'Stop-ThriveLensDistroAndVerify'})
 A (@($startErrors).Count -eq 0 -and $gracefulTries.Count -eq 1 -and $forcedTries.Count -eq 2 -and $combinedTries.Count -eq 0) 'START_INDEPENDENT_GRACEFUL_FORCED_CLEANUP'
 A ($startRaw -match '\$wslTouched=\$true' -and $startRaw -match 'elseif\(\$wslTouched\)') 'START_PRE_ATTEMPT_WSL_CLEANUP'
 A ($startRaw -notmatch 'Invoke-ThriveLensDistro' -and $startRaw -match 'Invoke-ThriveLensGuardedDistro') 'START_ONLY_GUARDED_DISTRO_MUTATION'
 foreach($lifecycleFile in @('preflight.ps1','initialize.ps1','start.ps1','stop.ps1')){
  $lifecycleRaw=Get-Content (Join-Path $PSScriptRoot $lifecycleFile) -Raw
  $tokenIndex=$lifecycleRaw.IndexOf('Get-ThriveLensWslCleanupIdentityToken');$distroIndex=$lifecycleRaw.IndexOf('Assert-ThriveLensWslIdentity')
  A ($tokenIndex -ge 0 -and ($distroIndex -lt 0 -or $tokenIndex -lt $distroIndex)) ('IDENTITY_TOKEN_BEFORE_DISTRO_'+$lifecycleFile)
  $unguardedTerminate=@($lifecycleRaw -split "`r?`n"|Where-Object{$_ -match 'Stop-ThriveLensDistroAndVerify' -and ($_ -notmatch '-IdentityToken\s+\$' -or $_ -notmatch '-LifecycleLock\s+\$')})
  A ($unguardedTerminate.Count -eq 0) ('TERMINATE_TOKEN_ARGUMENTS_'+$lifecycleFile)
 }
 $stopRaw=Get-Content (Join-Path $PSScriptRoot 'stop.ps1') -Raw
 A ($stopRaw -match 'if\(\$null -ne \$lifecycleLock -and \$null -ne \$cleanupIdentityToken\)') 'STOP_LOCK_FAILURE_NEVER_TERMINATES'
 $stopFunctionStart=$module.IndexOf('function Stop-ThriveLensPostgresUnderLock');$stopFunctionEnd=$module.IndexOf('function Resolve-ThriveLensChildOutcome',$stopFunctionStart);$stopFunctionBody=if($stopFunctionStart -ge 0 -and $stopFunctionEnd -gt $stopFunctionStart){$module.Substring($stopFunctionStart,$stopFunctionEnd-$stopFunctionStart)}else{''}
 A ($stopFunctionBody -match 'IdentityToken' -and $stopFunctionBody -match 'LifecycleLock' -and $stopFunctionBody -match 'Assert-ThriveLensLifecycleLockOwnership' -and $stopFunctionBody -match 'Invoke-ThriveLensGuardedDistro') 'GRACEFUL_STOP_IDENTITY_FENCED'
 A ($stopFunctionBody -match 'Assert-ThriveLensWslAbsent' -and $stopFunctionBody -notmatch 'Assert-ThriveLensHostPortAbsent') 'GRACEFUL_STOP_GUEST_ABSENCE_ONLY'
 A ($terminateBody.IndexOf('Assert-ThriveLensDistroStopped') -ge 0 -and $terminateBody.IndexOf('Assert-ThriveLensHostPortAbsent') -gt $terminateBody.IndexOf('Assert-ThriveLensDistroStopped')) 'TERMINATE_FINAL_HOST_ABSENCE_ORDERED'
 $runtimeTest=Get-Content (Join-Path $PSScriptRoot 'test_runtime.ps1') -Raw
 $runtimeTokens=$null;$runtimeParseErrors=$null;$runtimeAst=[Management.Automation.Language.Parser]::ParseInput($runtimeTest,[ref]$runtimeTokens,[ref]$runtimeParseErrors)
 $pseudoFinallyCommands=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'finally'},$true))
 A ($runtimeParseErrors.Count -eq 0 -and $pseudoFinallyCommands.Count -eq 0) 'RUNTIME_FINALLY_AST_BOUND'
 $credentialFunctionStart=$runtimeTest.IndexOf('function Remove-ThriveLensRuntimeCredential');$credentialFunctionEnd=$runtimeTest.IndexOf('function Assert-ThriveLensAuthenticatedScalar',$credentialFunctionStart);$credentialFunctionBody=if($credentialFunctionStart -ge 0 -and $credentialFunctionEnd -gt $credentialFunctionStart){$runtimeTest.Substring($credentialFunctionStart,$credentialFunctionEnd-$credentialFunctionStart)}else{''}
 $removeCatchIndex=$credentialFunctionBody.IndexOf('$removeRawCode=');$absenceProbeIndex=$credentialFunctionBody.IndexOf("Invoke-ThriveLensGuardedDistro -IdentityToken `$IdentityToken -LifecycleLock `$LifecycleLock -Arguments @('/usr/bin/test'",$removeCatchIndex);$credentialResolverIndex=$credentialFunctionBody.IndexOf('Resolve-ThriveLensCredentialCleanupResult',$absenceProbeIndex)
 A ($removeCatchIndex -ge 0 -and $absenceProbeIndex -gt $removeCatchIndex -and $credentialResolverIndex -gt $absenceProbeIndex -and $credentialFunctionBody -match 'Test-ThriveLensCredentialAbsenceProbeAllowed') 'CREDENTIAL_REMOVE_FAILURE_THEN_BOUNDED_ABSENCE_FLOW'
 $credentialTestModule=New-Module -ArgumentList $credentialFunctionBody -ScriptBlock {
  param([string]$Definition)
  $script:Scenario='SUCCESS';$script:IdentityAssertCalls=0;$script:GuardedCalls=0;$script:CallLog=[Collections.Generic.List[string]]::new()
  function Assert-ThriveLensWslCleanupIdentity {
   param($IdentityToken,$LifecycleLock)
   $script:IdentityAssertCalls++
   $assertFailures=@{ASSERT_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';ASSERT_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';ASSERT_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';ASSERT_UNKNOWN='untrusted raw failure'}
   if($assertFailures.ContainsKey($script:Scenario)){throw $assertFailures[$script:Scenario]}
   return $true
  }
  function Invoke-ThriveLensGuardedDistro {
   param($IdentityToken,$LifecycleLock,[string[]]$Arguments)
   $script:GuardedCalls++;$script:CallLog.Add(($Arguments[0]+'|'+$Arguments[-1]))
   if($Arguments[0] -ceq '/usr/bin/rm'){
    $removeFailures=@{
     REMOVE_TIMEOUT='WSL_COMMAND_TIMEOUT';REMOVE_OUTPUT_LIMIT='WSL_OUTPUT_LIMIT_EXCEEDED';REMOVE_DRAIN='WSL_OUTPUT_DRAIN_INCOMPLETE';REMOVE_START='WSL_PROCESS_START_FAILED';
     REMOVE_TIMEOUT_ABSENCE_FALSE='WSL_COMMAND_TIMEOUT';REMOVE_TIMEOUT_ABSENCE_THROW='WSL_COMMAND_TIMEOUT';
     REMOVE_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';REMOVE_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';REMOVE_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';REMOVE_UNKNOWN='untrusted raw failure'
    }
    if($removeFailures.ContainsKey($script:Scenario)){throw $removeFailures[$script:Scenario]}
    if($script:Scenario -ceq 'REMOVE_EXIT_ONE'){return [pscustomobject]@{ExitCode=1;Output=''}}
    return [pscustomobject]@{ExitCode=0;Output=''}
   }
   if($Arguments[0] -ceq '/usr/bin/test'){
    if($script:Scenario -ceq 'REMOVE_TIMEOUT_ABSENCE_THROW'){throw 'WSL_COMMAND_TIMEOUT'}
    return [pscustomobject]@{ExitCode=if($script:Scenario -cin @('ABSENCE_FALSE','REMOVE_TIMEOUT_ABSENCE_FALSE')){1}else{0};Output=''}
   }
   throw 'UNEXPECTED_TEST_COMMAND'
  }
  . ([scriptblock]::Create($Definition))
 }
 $credentialTestLock=[Threading.Mutex]::new($false)
 try{
  $credentialPath='/run/thrivelens-r0-auth-0123456789abcdef0123456789abcdef.pgpass'
  $runCredentialCase={param([string]$scenario)& $credentialTestModule {param($scenario,$token,$lock,$path)$script:Scenario=$scenario;$script:IdentityAssertCalls=0;$script:GuardedCalls=0;$script:CallLog.Clear();$result=Remove-ThriveLensRuntimeCredential -Path $path -IdentityToken $token -LifecycleLock $lock;[pscustomobject]@{Result=$result;IdentityCalls=$script:IdentityAssertCalls;GuardedCalls=$script:GuardedCalls;Log=@($script:CallLog)}} $scenario $identityToken $credentialTestLock $credentialPath}
  $successCase=& $runCredentialCase 'SUCCESS';A ($successCase.Result.RemoveSucceeded -and $successCase.Result.CredentialAbsenceVerified -and $successCase.IdentityCalls -eq 2 -and $successCase.GuardedCalls -eq 2 -and ($successCase.Log -join ',') -ceq ("/usr/bin/rm|$credentialPath,/usr/bin/test|$credentialPath")) 'CREDENTIAL_EXECUTABLE_SUCCESS_EXACT_ORDER'
  $removeExitCase=& $runCredentialCase 'REMOVE_EXIT_ONE';A (-not $removeExitCase.Result.RemoveSucceeded -and $removeExitCase.Result.CredentialAbsenceVerified -and $removeExitCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $removeExitCase.Result.RootFailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $removeExitCase.IdentityCalls -eq 2 -and $removeExitCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_REMOVE_EXIT_THEN_ABSENCE'
  $safeFailureCodes=@{REMOVE_TIMEOUT='WSL_COMMAND_TIMEOUT';REMOVE_OUTPUT_LIMIT='WSL_OUTPUT_LIMIT_EXCEEDED';REMOVE_DRAIN='WSL_OUTPUT_DRAIN_INCOMPLETE';REMOVE_START='WSL_PROCESS_START_FAILED'}
  foreach($safeScenario in $safeFailureCodes.Keys){$safeCase=& $runCredentialCase $safeScenario;A (-not $safeCase.Result.RemoveSucceeded -and $safeCase.Result.CredentialAbsenceVerified -and $safeCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED' -and $safeCase.Result.RootFailureCode -ceq $safeFailureCodes[$safeScenario] -and $safeCase.IdentityCalls -eq 2 -and $safeCase.GuardedCalls -eq 2 -and ($safeCase.Log -join ',') -ceq ("/usr/bin/rm|$credentialPath,/usr/bin/test|$credentialPath")) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_THEN_EXACT_ABSENCE'}
  $safeFalseCase=& $runCredentialCase 'REMOVE_TIMEOUT_ABSENCE_FALSE';A (-not $safeFalseCase.Result.CredentialAbsenceVerified -and $safeFalseCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $safeFalseCase.Result.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and $safeFalseCase.IdentityCalls -eq 2 -and $safeFalseCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_FALSE_ABSENCE'
  $safeThrowCase=& $runCredentialCase 'REMOVE_TIMEOUT_ABSENCE_THROW';A (-not $safeThrowCase.Result.CredentialAbsenceVerified -and $safeThrowCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $safeThrowCase.Result.RootFailureCode -ceq 'WSL_COMMAND_TIMEOUT' -and $safeThrowCase.IdentityCalls -eq 2 -and $safeThrowCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_SAFE_THROW_ABSENCE_THROW'
  $unsafeRemoveCodes=@{REMOVE_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';REMOVE_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';REMOVE_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';REMOVE_UNKNOWN='RUNTIME_TEST_INTERNAL_ERROR'}
  foreach($unsafeScenario in $unsafeRemoveCodes.Keys){$unsafeCase=& $runCredentialCase $unsafeScenario;A (-not $unsafeCase.Result.CredentialAbsenceVerified -and $unsafeCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $unsafeCase.Result.RootFailureCode -ceq $unsafeRemoveCodes[$unsafeScenario] -and $unsafeCase.IdentityCalls -eq 1 -and $unsafeCase.GuardedCalls -eq 1 -and $unsafeCase.Log[0] -ceq "/usr/bin/rm|$credentialPath") 'CREDENTIAL_EXECUTABLE_UNSAFE_REMOVE_ZERO_FOLLOW_ON'}
  $assertFailureCodes=@{ASSERT_IDENTITY='WSL_CLEANUP_IDENTITY_CHANGED';ASSERT_LOCK='LIFECYCLE_LOCK_OWNERSHIP_REQUIRED';ASSERT_CONTAINMENT='WSL_GUARDED_COMMAND_CONTAINMENT_FAILED';ASSERT_UNKNOWN='RUNTIME_TEST_INTERNAL_ERROR'}
  foreach($assertScenario in $assertFailureCodes.Keys){$assertFailureCase=& $runCredentialCase $assertScenario;A (-not $assertFailureCase.Result.CredentialAbsenceVerified -and $assertFailureCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $assertFailureCase.Result.RootFailureCode -ceq $assertFailureCodes[$assertScenario] -and $assertFailureCase.IdentityCalls -eq 1 -and $assertFailureCase.GuardedCalls -eq 0) 'CREDENTIAL_EXECUTABLE_ASSERT_FAILURE_ZERO_GUEST_CALLS'}
  $absenceFalseCase=& $runCredentialCase 'ABSENCE_FALSE';A ($absenceFalseCase.Result.RemoveSucceeded -and -not $absenceFalseCase.Result.CredentialAbsenceVerified -and $absenceFalseCase.Result.FailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $absenceFalseCase.Result.RootFailureCode -ceq 'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED' -and $absenceFalseCase.IdentityCalls -eq 2 -and $absenceFalseCase.GuardedCalls -eq 2) 'CREDENTIAL_EXECUTABLE_FALSE_ABSENCE_REJECTED'
 }finally{$credentialTestLock.Dispose();Remove-Module $credentialTestModule -Force -ErrorAction SilentlyContinue}
 A ($runtimeTest -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$actual') 'RUNTIME_PROTECTED_SECRET_READER'
 A ($runtimeTest -match 'SCRAM_AUTH_PROBE_FAILED') 'RUNTIME_POSITIVE_AUTH_MARKER'
 A ($runtimeTest -match 'Assert-ThriveLensClusterScramConfig') 'RUNTIME_HBA_MARKER'
 A ($runtimeTest -match 'PASSWORD_ENCRYPTION_PROBE_FAILED') 'RUNTIME_PASSWORD_ENCRYPTION_MARKER'
 A ($runtimeTest -match 'SCRAM_VERIFIER_PROBE_FAILED') 'RUNTIME_VERIFIER_MARKER'
 A ($runtimeTest -match 'Resolve-ThriveLensWrongPasswordProbe' -and $runtimeTest -match 'CapturePrivateStandardError' -and $runtimeTest -match "'LC_ALL=C'") 'RUNTIME_WRONG_PASSWORD_CLASSIFIER'
 $guardedCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Invoke-ThriveLensGuardedDistro'},$true))
 $positiveProbeTokens=@("'/usr/sbin/runuser'","'-u'","'postgres'","'--'","'/usr/bin/env'","'-i'",'"PGPASSFILE=$AuthFile"',"'PGCONNECT_TIMEOUT=5'","'PGREQUIREAUTH=scram-sha-256'","'/usr/bin/psql'","'-X'","'-w'","'-h'","'127.0.0.1'","'-p'","'55432'","'-U'","'tl_bootstrap'","'-d'","'postgres'","'-Atq'","'--set=ON_ERROR_STOP=1'","'--command'",'$Sql')
 $wrongProbeTokens=@("'/usr/sbin/runuser'","'-u'","'postgres'","'--'","'/usr/bin/env'","'-i'","'LC_ALL=C'","'LANG=C'",'"PGPASSFILE=$wrongAuthFile"',"'PGCONNECT_TIMEOUT=5'","'PGREQUIREAUTH=scram-sha-256'","'/usr/bin/psql'","'-X'","'-w'","'-h'","'127.0.0.1'","'-p'","'55432'","'-U'","'tl_bootstrap'","'-d'","'postgres'","'-Atq'","'--set=ON_ERROR_STOP=1'","'--command'","'SELECT 1'")
 $wrongInstallTokens=@("'/usr/bin/install'","'-o'","'postgres'","'-g'","'postgres'","'-m'","'0600'","'/dev/stdin'",'$wrongAuthFile')
 $positiveProbeCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($positiveProbeTokens-join "`n")})
 $wrongProbeCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($wrongProbeTokens-join "`n")})
 $wrongInstallCalls=@($guardedCalls|Where-Object{((Get-ArrayArgumentTokenText -Command $_ -ParameterName 'Arguments')-join "`n") -ceq ($wrongInstallTokens-join "`n")})
 A ($positiveProbeCalls.Count -eq 1 -and $wrongProbeCalls.Count -eq 1 -and $wrongInstallCalls.Count -eq 1) 'RUNTIME_EXACT_SCRAM_PROBE_ARGUMENT_ASTS'
 $wrongProbeAst=$wrongProbeCalls[0];$wrongInstallAst=$wrongInstallCalls[0]
 A (@($wrongProbeAst.CommandElements|Where-Object{$_ -is [Management.Automation.Language.CommandParameterAst] -and $_.ParameterName -ceq 'CapturePrivateStandardError'}).Count -eq 1) 'RUNTIME_WRONG_PROBE_PRIVATE_STDERR_AST'
 $wrongProbeIndex=$wrongProbeAst.Extent.StartOffset
 $wrongCredentialDeleteIndex=$runtimeTest.IndexOf('Remove-ThriveLensRuntimeCredential -Path $wrongAuthFile',$wrongProbeIndex);$usabilityFalseIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$false',$wrongCredentialDeleteIndex);$usabilityQueryIndex=$runtimeTest.IndexOf("-FailureCode 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED'",$usabilityFalseIndex);$usabilityTrueIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$true',$usabilityQueryIndex);$classifierIndex=$runtimeTest.IndexOf('$wrongOutcome=Resolve-ThriveLensWrongPasswordProbe',$usabilityTrueIndex)
 A ($wrongProbeIndex -ge 0 -and $usabilityFalseIndex -gt $wrongProbeIndex -and $usabilityQueryIndex -gt $usabilityFalseIndex -and $usabilityTrueIndex -gt $usabilityQueryIndex -and $classifierIndex -gt $usabilityTrueIndex -and $runtimeTest.Substring($classifierIndex,[Math]::Min(500,$runtimeTest.Length-$classifierIndex)) -match '-ServerUsableAfterProbe \$serverUsableAfterWrong') 'RUNTIME_WRONG_PASSWORD_USABILITY_ORDERED'
 $expectedPathBindingIndex=$runtimeTest.IndexOf('-ExpectedPasswordFile $wrongAuthFile',$classifierIndex);$wrongPathClearIndex=$runtimeTest.IndexOf('$wrongAuthFile=$null',$expectedPathBindingIndex)
 $wrongRemoveCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Remove-ThriveLensRuntimeCredential' -and $node.Extent.Text -match '-Path\s+\$wrongAuthFile(?:\s|$)'},$true))
 $wrongClassifierCalls=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Resolve-ThriveLensWrongPasswordProbe' -and $node.Extent.Text -match '-ExpectedPasswordFile\s+\$wrongAuthFile(?:\s|$)'},$true))
 $wrongClears=@($runtimeAst.FindAll({param($node)$node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$wrongAuthFile' -and $node.Right.Extent.Text -ceq '$null'},$true)|Where-Object{$_.Extent.StartOffset -gt $wrongInstallAst.Extent.StartOffset})
 A ($wrongRemoveCalls.Count -eq 1 -and $wrongClassifierCalls.Count -eq 1 -and $wrongClears.Count -ge 1 -and $wrongInstallAst.Extent.StartOffset -lt $wrongProbeAst.Extent.StartOffset -and $wrongProbeAst.Extent.StartOffset -lt $wrongRemoveCalls[0].Extent.StartOffset -and $wrongRemoveCalls[0].Extent.StartOffset -lt $wrongClassifierCalls[0].Extent.StartOffset -and $wrongClassifierCalls[0].Extent.StartOffset -lt $wrongClears[0].Extent.StartOffset -and $runtimeTest.Substring($wrongInstallAst.Extent.StartOffset,$wrongClassifierCalls[0].Extent.StartOffset-$wrongInstallAst.Extent.StartOffset) -notmatch '\$wrongAuthFile\s*=\s*\$null') 'RUNTIME_WRONG_PASSWORD_PATH_PRIVATE_LIFETIME'
 $runtimeStartIndex=$runtimeTest.IndexOf('$started=$true;$start=');$probeLockIndex=$runtimeTest.IndexOf('$probeLifecycleLock=Enter-ThriveLensLifecycleLock',$runtimeStartIndex);$probeTokenIndex=$runtimeTest.IndexOf('$probeIdentityToken=Get-ThriveLensWslCleanupIdentityToken',$probeLockIndex);$firstRuntimeDistroIndex=$runtimeTest.IndexOf('Assert-ThriveLensClusterScramConfig',$runtimeStartIndex);$successStopIndex=$runtimeTest.IndexOf('$wasRunning=Stop-ThriveLensPostgresUnderLock',$probeTokenIndex);$successTerminateIndex=$runtimeTest.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$successStopIndex);$probeReleaseIndex=$runtimeTest.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$successTerminateIndex)
 A ($probeLockIndex -gt $runtimeStartIndex -and $probeTokenIndex -gt $probeLockIndex -and $firstRuntimeDistroIndex -gt $probeTokenIndex -and $successStopIndex -gt $firstRuntimeDistroIndex -and $successTerminateIndex -gt $successStopIndex -and $probeReleaseIndex -gt $successTerminateIndex) 'RUNTIME_PROBE_LOCK_TOKEN_LIFECYCLE_ORDERED'
 $catchIndex=$runtimeTest.IndexOf("catch {",$runtimeTest.IndexOf("} | ConvertTo-Json -Compress"));$sameTokenCatchStop=$runtimeTest.IndexOf('Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken',$catchIndex);$sameTokenCatchTerminate=$runtimeTest.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$sameTokenCatchStop);$catchRelease=$runtimeTest.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$sameTokenCatchTerminate);$preTokenObservation=$runtimeTest.IndexOf('Resolve-ThriveLensPreTokenStartObservation',$catchRelease);$freshStopInvocation=$runtimeTest.IndexOf("& pwsh -NoProfile -File (Join-Path `$PSScriptRoot 'stop.ps1')")
 A ($runtimeTest -match '\$probeIdentityEverEstablished=\$true' -and $sameTokenCatchStop -gt $catchIndex -and $sameTokenCatchTerminate -gt $sameTokenCatchStop -and $catchRelease -gt $sameTokenCatchTerminate -and $preTokenObservation -gt $catchRelease -and $freshStopInvocation -lt 0 -and $runtimeTest -notmatch 'Test-ThriveLensFailureAllowsFreshCleanup') 'RUNTIME_SAME_TOKEN_FAILURE_CLEANUP_DEFAULT_DENY'
 A ($runtimeTest -match 'Assert-ThriveLensDistroStopped' -and $runtimeTest -match 'Assert-ThriveLensHostPortAbsent' -and $runtimeTest -match 'Resolve-ThriveLensPreTokenStartObservation' -and $runtimeTest -notmatch '\$freshStopAllowed') 'RUNTIME_PRETOKEN_EXIT_READ_ONLY_OBSERVATION'
 A ($runtimeTest -notmatch 'Invoke-ThriveLensDistro' -and $runtimeTest -match 'Invoke-ThriveLensGuardedDistro') 'RUNTIME_ONLY_GUARDED_DISTRO_CALLS'
 A ($runtimeTest -match 'Resolve-ThriveLensRuntimeCleanupOutcome' -and $runtimeTest -match 'schema_version = 2' -and $runtimeTest -match 'original_code' -and $runtimeTest -match 'failure_stages' -and $runtimeTest -match 'credential_absence_verified') 'RUNTIME_CLOSED_FAILURE_SCHEMA_V2'
 $preflightRaw=Get-Content (Join-Path $PSScriptRoot 'preflight.ps1') -Raw;A ($preflightRaw -match 'function Stop-ThriveLensPreflightDistro' -and $preflightRaw -match 'Stop-ThriveLensDistroAndVerify' -and $preflightRaw -match 'Assert-ThriveLensHostPortAbsent') 'PREFLIGHT_EXACT_DISTRO_CLEANUP'
 A ($preflightRaw -match '\$preflightLock=Enter-ThriveLensLifecycleLock' -and $preflightRaw -match 'Assert-ThriveLensWslAbsent' -and $preflightRaw -match 'finally\{if\(\$null -ne \$preflightLock\)') 'PREFLIGHT_LOCKED_ABSENCE_BEFORE_TERMINATE'
 $guardStart=$module.IndexOf('function Invoke-ThriveLensGuardedDistro');$guardEnd=$module.IndexOf('function Assert-ThriveLensLifecycleLockOwnership',$guardStart);$guardBody=if($guardStart -ge 0 -and $guardEnd -gt $guardStart){$module.Substring($guardStart,$guardEnd-$guardStart)}else{''}
 A ($guardBody -match 'Assert-ThriveLensLifecycleLockOwnership' -and $guardBody -match 'Assert-ThriveLensWslCleanupIdentity' -and $guardBody -match 'finally' -and $guardBody -match 'Stop-ThriveLensDistroAndVerify' -and $guardBody.IndexOf('Stop-ThriveLensDistroAndVerify') -lt $guardBody.LastIndexOf('throw $failureCode')) 'GUARDED_DISTRO_FAILURE_CONTAINMENT_ORDERED'
 $containmentMarker=$initialize.IndexOf('$containmentVerified=$code -cne ''WSL_GUARDED_COMMAND_CONTAINMENT_FAILED''');$credentialCleanup=$initialize.IndexOf('if($containmentVerified -and $cleanupIdentityReady -and $null -ne $distroPasswordFile)');$nestedContainment=$initialize.IndexOf('$policy=Resolve-ThriveLensCleanupContainmentPolicy',$credentialCleanup);$rollbackGuard=$initialize.IndexOf('if($containmentVerified -and $cleanupIdentityReady -and $null -ne $staging')
 A ($containmentMarker -ge 0 -and $credentialCleanup -gt $containmentMarker -and $nestedContainment -gt $credentialCleanup -and $rollbackGuard -gt $nestedContainment -and $initialize.Substring($nestedContainment,$rollbackGuard-$nestedContainment) -match '\$containmentVerified=\$false') 'INITIALIZE_CONTAINMENT_BEFORE_ROLLBACK'
 foreach($file in @('initialize.ps1','start.ps1','stop.ps1','test_runtime.ps1')){$raw=Get-Content (Join-Path $PSScriptRoot $file)-Raw;A ($raw -notmatch '(?i)wsl\.exe\s+[^\r\n]*Ubuntu(?:\s|$)') ('SHARED_UBUNTU_'+$file)}
 if($fail.Count){[pscustomobject]@{schema_version=1;status='FAIL';codes=@($fail)}|ConvertTo-Json -Compress;exit 1}
 [pscustomobject]@{schema_version=1;status='PASS';assertions=$count}|ConvertTo-Json -Compress
}catch{[pscustomobject]@{schema_version=1;status='ERROR';code='WSL_CONTROL_TEST_INTERNAL_ERROR'}|ConvertTo-Json -Compress;exit 2}
