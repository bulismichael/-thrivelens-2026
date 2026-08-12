#Requires -Version 7.0
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$fail=[Collections.Generic.List[string]]::new();$count=0
function A([bool]$ok,[string]$code){$script:count++;if(-not $ok){$fail.Add($code)}}
function Test-ThrowsExact([scriptblock]$Action,[string]$ExpectedCode){
 try{$null=& $Action;return $false}catch{return $_.Exception.Message -ceq $ExpectedCode}
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
 $authError='psql: error: connection to server at "127.0.0.1", port 55432 failed: FATAL:  password authentication failed for user "tl_bootstrap"'
 $authRejected=Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError ($authError+"`n") -ServerUsableAfterProbe $true
 A ($authRejected.Status -ceq 'AUTHENTICATION_REJECTED') 'WRONG_PASSWORD_EXACT_REJECTION_ACCEPTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 0 -PrivateStandardOutput '1' -PrivateStandardError '' -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_WAS_ACCEPTED') 'WRONG_PASSWORD_SUCCESS_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput ' ' -PrivateStandardError $authError -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNEXPECTED_OUTPUT') 'WRONG_PASSWORD_WHITESPACE_STDOUT_REJECTED'
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 1 -PrivateStandardOutput '' -PrivateStandardError $authError -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_WRONG_EXIT_REJECTED'
 $authNearMisses=@(
  ('prefix'+$authError),($authError+' suffix'),($authError+"`n`n"),
  ($authError -replace '127\.0\.0\.1','localhost'),($authError -replace '55432','55433'),
  ($authError -replace 'tl_bootstrap','postgres'),'psql: error: client executable failure'
 )
 A ($authNearMisses.Count -eq 7) 'WRONG_PASSWORD_NEAR_MISS_MATRIX_COMPLETE'
 foreach($nearMiss in $authNearMisses){
  A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $nearMiss -ServerUsableAfterProbe $true} 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE') 'WRONG_PASSWORD_DIAGNOSTIC_NEAR_MISS_REJECTED'
 }
 A (Test-ThrowsExact {Resolve-ThriveLensWrongPasswordProbe -ExitCode 2 -PrivateStandardOutput '' -PrivateStandardError $authError -ServerUsableAfterProbe $false} 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED') 'WRONG_PASSWORD_SERVER_UNUSABLE_REJECTED'
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
 $runtimeTest=Get-Content (Join-Path $PSScriptRoot 'test_runtime.ps1') -Raw
 A ($runtimeTest -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$actual') 'RUNTIME_PROTECTED_SECRET_READER'
 A ($runtimeTest -match 'SCRAM_AUTH_PROBE_FAILED') 'RUNTIME_POSITIVE_AUTH_MARKER'
 A ($runtimeTest -match 'Assert-ThriveLensClusterScramConfig') 'RUNTIME_HBA_MARKER'
 A ($runtimeTest -match 'PASSWORD_ENCRYPTION_PROBE_FAILED') 'RUNTIME_PASSWORD_ENCRYPTION_MARKER'
 A ($runtimeTest -match 'SCRAM_VERIFIER_PROBE_FAILED') 'RUNTIME_VERIFIER_MARKER'
 A ($runtimeTest -match 'Resolve-ThriveLensWrongPasswordProbe' -and $runtimeTest -match 'CapturePrivateStandardError' -and $runtimeTest -match "'LC_ALL=C'") 'RUNTIME_WRONG_PASSWORD_CLASSIFIER'
 $wrongProbeIndex=$runtimeTest.IndexOf('$wrongProbe = Invoke-ThriveLensGuardedDistro');$usabilityFalseIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$false',$wrongProbeIndex);$usabilityQueryIndex=$runtimeTest.IndexOf("-FailureCode 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED'",$usabilityFalseIndex);$usabilityTrueIndex=$runtimeTest.IndexOf('$serverUsableAfterWrong=$true',$usabilityQueryIndex);$classifierIndex=$runtimeTest.IndexOf('$wrongOutcome=Resolve-ThriveLensWrongPasswordProbe',$usabilityTrueIndex)
 A ($wrongProbeIndex -ge 0 -and $usabilityFalseIndex -gt $wrongProbeIndex -and $usabilityQueryIndex -gt $usabilityFalseIndex -and $usabilityTrueIndex -gt $usabilityQueryIndex -and $classifierIndex -gt $usabilityTrueIndex -and $runtimeTest.Substring($classifierIndex,[Math]::Min(500,$runtimeTest.Length-$classifierIndex)) -match '-ServerUsableAfterProbe \$serverUsableAfterWrong') 'RUNTIME_WRONG_PASSWORD_USABILITY_ORDERED'
 $runtimeStartIndex=$runtimeTest.IndexOf('$started=$true;$start=');$probeLockIndex=$runtimeTest.IndexOf('$probeLifecycleLock=Enter-ThriveLensLifecycleLock',$runtimeStartIndex);$probeTokenIndex=$runtimeTest.IndexOf('$probeIdentityToken=Get-ThriveLensWslCleanupIdentityToken',$probeLockIndex);$firstRuntimeDistroIndex=$runtimeTest.IndexOf('Assert-ThriveLensClusterScramConfig',$runtimeStartIndex);$successStopIndex=$runtimeTest.IndexOf('$wasRunning=Stop-ThriveLensPostgresUnderLock',$probeTokenIndex);$successTerminateIndex=$runtimeTest.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$successStopIndex);$probeReleaseIndex=$runtimeTest.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$successTerminateIndex)
 A ($probeLockIndex -gt $runtimeStartIndex -and $probeTokenIndex -gt $probeLockIndex -and $firstRuntimeDistroIndex -gt $probeTokenIndex -and $successStopIndex -gt $firstRuntimeDistroIndex -and $successTerminateIndex -gt $successStopIndex -and $probeReleaseIndex -gt $successTerminateIndex) 'RUNTIME_PROBE_LOCK_TOKEN_LIFECYCLE_ORDERED'
 $catchIndex=$runtimeTest.IndexOf("catch {",$runtimeTest.IndexOf("} | ConvertTo-Json -Compress"));$sameTokenCatchStop=$runtimeTest.IndexOf('Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken',$catchIndex);$sameTokenCatchTerminate=$runtimeTest.IndexOf('Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken',$sameTokenCatchStop);$catchRelease=$runtimeTest.IndexOf('Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock',$sameTokenCatchTerminate);$preTokenObservation=$runtimeTest.IndexOf('Resolve-ThriveLensPreTokenStartObservation',$catchRelease);$freshStopInvocation=$runtimeTest.IndexOf("& pwsh -NoProfile -File (Join-Path `$PSScriptRoot 'stop.ps1')")
 A ($runtimeTest -match '\$probeIdentityEverEstablished=\$true' -and $sameTokenCatchStop -gt $catchIndex -and $sameTokenCatchTerminate -gt $sameTokenCatchStop -and $catchRelease -gt $sameTokenCatchTerminate -and $preTokenObservation -gt $catchRelease -and $freshStopInvocation -lt 0 -and $runtimeTest -notmatch 'Test-ThriveLensFailureAllowsFreshCleanup') 'RUNTIME_SAME_TOKEN_FAILURE_CLEANUP_DEFAULT_DENY'
 A ($runtimeTest -match 'Assert-ThriveLensDistroStopped' -and $runtimeTest -match 'Assert-ThriveLensHostPortAbsent' -and $runtimeTest -match 'Resolve-ThriveLensPreTokenStartObservation' -and $runtimeTest -notmatch '\$freshStopAllowed') 'RUNTIME_PRETOKEN_EXIT_READ_ONLY_OBSERVATION'
 A ($runtimeTest -notmatch 'Invoke-ThriveLensDistro' -and $runtimeTest -match 'Invoke-ThriveLensGuardedDistro') 'RUNTIME_ONLY_GUARDED_DISTRO_CALLS'
 A ($runtimeTest -match 'cleanup_verified = \(-not \$started -and -not \$credentialCleanupFatal -and \$distroAbsenceVerified -and \$hostAbsenceVerified\)') 'RUNTIME_CLEANUP_TRUTH_CONJUNCTION'
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
