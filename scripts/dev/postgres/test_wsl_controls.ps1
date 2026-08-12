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
 $runtimeModule=Get-Content (Join-Path $PSScriptRoot 'Runtime.psm1') -Raw
 $readerStart=$runtimeModule.IndexOf('function Read-ThriveLensPostgresBootstrapSecret');$readerEnd=if($readerStart -ge 0){$runtimeModule.IndexOf('function Resolve-ThriveLensStartChildFailure',$readerStart)}else{-1};$readerBody=if($readerStart -ge 0 -and $readerEnd -gt $readerStart){$runtimeModule.Substring($readerStart,$readerEnd-$readerStart)}else{''}
 A ($readerBody -match 'Assert-ThriveLensSecretRootAcl') 'SECRET_READER_PARENT_ACL'
 A ($readerBody -match 'Assert-ThriveLensSecretFileAclRules') 'SECRET_READER_FILE_ACL'
 A ($readerBody -match '\[IO\.FileShare\]::None') 'SECRET_READER_EXCLUSIVE_OPEN'
 Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
 Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
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
 $dataRoot='/var/lib/thrivelens/postgresql/r0';$logRoot='/var/log/thrivelens/postgresql/r0';$treeLimit=[int64]134217728;$stagingRoot='/var/lib/thrivelens/postgresql/.r0-staging-0123456789abcdef0123456789abcdef'
 $dataPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $dataRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($dataPolicy.Kind -ceq 'DATA' -and $dataPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_DATA_ACCEPTED'
 $logPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $logRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($logPolicy.Kind -ceq 'LOG' -and $logPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_LOG_ACCEPTED'
 $stagingPolicy=Resolve-ThriveLensLinuxTreeRootPolicy -Root $stagingRoot -DataRoot $dataRoot -LogRoot $logRoot -MaximumBytes $treeLimit
 A ($stagingPolicy.Kind -ceq 'STAGING' -and $stagingPolicy.MaximumBytes -eq $treeLimit) 'TREE_ROOT_STAGING_ACCEPTED'
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
 $stagingGuard='Assert-ThriveLensLinuxTreePolicy -Root $staging';$firstStagingGuard=$initialize.IndexOf($stagingGuard);$lastStagingGuard=$initialize.LastIndexOf($stagingGuard);$activationAttempted=$initialize.IndexOf('$activationAttempted=$true');$activationMove=$initialize.IndexOf('$move=Invoke-ThriveLensDistro');$rollbackDelete=$initialize.IndexOf('rm_tree(fd)')
 A ($initialize -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$passwordPath') 'INITIALIZE_PROTECTED_SECRET_READER'
 A ($firstStagingGuard -ge 0 -and $activationMove -gt $firstStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_MOVE'
 A ($lastStagingGuard -gt $activationMove -and $rollbackDelete -gt $lastStagingGuard) 'INITIALIZE_STAGING_GUARD_BEFORE_ROLLBACK'
 A ($initialize -match "fdinfo/'\+str\(fd\)" -and $initialize -match 'mount_id\(parentfd\) != trustedmount' -and $initialize -match 'rootmount != trustedmount' -and $initialize -match 'mount_id\(child\) != rootmount' -and $initialize -match 'mount_id\(leaf\) != rootmount' -and $initialize -notmatch 'shutil\.rmtree') 'INITIALIZE_FD_RELATIVE_MOUNT_FENCED_ROLLBACK'
 A ($activationAttempted -ge 0 -and $activationAttempted -lt $activationMove -and $initialize -match 'if\(\$activationAttempted -or \$activated\)\{\$fatalCleanup=\$true\}') 'INITIALIZE_ACTIVATION_ATTEMPT_FATAL'
 A ($initialize -match '\$null -ne \$staging -and -not \$activationAttempted -and -not \$activated') 'INITIALIZE_NO_ROLLBACK_AFTER_ACTIVATION_ATTEMPT'
 A ($initialize -match '\$wslTouched=\$true' -and $initialize -match 'if\(\$wslTouched -or \$mutated -or \$activationAttempted\)') 'INITIALIZE_ALL_POST_PREFLIGHT_WSL_PATHS_CLEANED'
 $mutationMarker=$initialize.IndexOf('$mutated = $true');$directoryLoop=$initialize.IndexOf('foreach($directory');A ($mutationMarker -ge 0 -and $directoryLoop -gt $mutationMarker) 'INITIALIZE_MUTATION_TRACKED_BEFORE_DIRECTORY_CREATE'
 $validBranchStart=$initialize.IndexOf("if(`$clusterState -ceq 'VALID')");$validBranchEnd=$initialize.IndexOf("if(`$clusterState -cne 'ABSENT')",$validBranchStart);$validBranch=if($validBranchStart -ge 0 -and $validBranchEnd -gt $validBranchStart){$initialize.Substring($validBranchStart,$validBranchEnd-$validBranchStart)}else{''};A ($validBranch -match 'Stop-ThriveLensDistroAndVerify' -and $validBranch -match 'Assert-ThriveLensHostPortAbsent') 'INITIALIZE_IDEMPOTENT_CLEANUP'
 $startRaw=Get-Content (Join-Path $PSScriptRoot 'start.ps1') -Raw
 $startTokens=$null;$startErrors=$null;$startAst=[Management.Automation.Language.Parser]::ParseInput($startRaw,[ref]$startTokens,[ref]$startErrors);$startTries=@($startAst.FindAll({param($node)$node -is [Management.Automation.Language.TryStatementAst]},$true));$gracefulTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensPostgresUnderLock'});$forcedTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensDistroAndVerify'});$combinedTries=@($startTries|Where-Object{$_.Body.Extent.Text -match 'Stop-ThriveLensPostgresUnderLock' -and $_.Body.Extent.Text -match 'Stop-ThriveLensDistroAndVerify'})
 A (@($startErrors).Count -eq 0 -and $gracefulTries.Count -eq 1 -and $forcedTries.Count -eq 2 -and $combinedTries.Count -eq 0) 'START_INDEPENDENT_GRACEFUL_FORCED_CLEANUP'
 A ($startRaw -match '\$wslTouched=\$true' -and $startRaw -match 'elseif\(\$wslTouched\)') 'START_PRE_ATTEMPT_WSL_CLEANUP'
 $runtimeTest=Get-Content (Join-Path $PSScriptRoot 'test_runtime.ps1') -Raw
 A ($runtimeTest -match 'Read-ThriveLensPostgresBootstrapSecret\s+-Path\s+\$actual') 'RUNTIME_PROTECTED_SECRET_READER'
 A ($runtimeTest -match 'SCRAM_AUTH_PROBE_FAILED') 'RUNTIME_POSITIVE_AUTH_MARKER'
 A ($runtimeTest -match 'Assert-ThriveLensClusterScramConfig') 'RUNTIME_HBA_MARKER'
 A ($runtimeTest -match 'PASSWORD_ENCRYPTION_PROBE_FAILED') 'RUNTIME_PASSWORD_ENCRYPTION_MARKER'
 A ($runtimeTest -match 'SCRAM_VERIFIER_PROBE_FAILED') 'RUNTIME_VERIFIER_MARKER'
 A ($runtimeTest -match 'WRONG_PASSWORD_WAS_ACCEPTED') 'RUNTIME_WRONG_PASSWORD_MARKER'
 A ($runtimeTest -match 'cleanup_verified = \(-not \$started -and -not \$credentialCleanupFatal -and \$distroAbsenceVerified -and \$hostAbsenceVerified\)') 'RUNTIME_CLEANUP_TRUTH_CONJUNCTION'
 $preflightRaw=Get-Content (Join-Path $PSScriptRoot 'preflight.ps1') -Raw;A ($preflightRaw -match 'function Stop-ThriveLensPreflightDistro' -and $preflightRaw -match 'Stop-ThriveLensDistroAndVerify' -and $preflightRaw -match 'Assert-ThriveLensHostPortAbsent') 'PREFLIGHT_EXACT_DISTRO_CLEANUP'
 A ($preflightRaw -match '\$preflightLock=Enter-ThriveLensLifecycleLock' -and $preflightRaw -match 'Assert-ThriveLensWslAbsent' -and $preflightRaw -match 'finally\{if\(\$null -ne \$preflightLock\)') 'PREFLIGHT_LOCKED_ABSENCE_BEFORE_TERMINATE'
 foreach($file in @('initialize.ps1','start.ps1','stop.ps1','test_runtime.ps1')){$raw=Get-Content (Join-Path $PSScriptRoot $file)-Raw;A ($raw -notmatch '(?i)wsl\.exe\s+[^\r\n]*Ubuntu(?:\s|$)') ('SHARED_UBUNTU_'+$file)}
 if($fail.Count){[pscustomobject]@{schema_version=1;status='FAIL';codes=@($fail)}|ConvertTo-Json -Compress;exit 1}
 [pscustomobject]@{schema_version=1;status='PASS';assertions=$count}|ConvertTo-Json -Compress
}catch{[pscustomobject]@{schema_version=1;status='ERROR';code='WSL_CONTROL_TEST_INTERNAL_ERROR'}|ConvertTo-Json -Compress;exit 2}
