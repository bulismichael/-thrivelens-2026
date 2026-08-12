#Requires -Version 7.0
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$attempted=$false
$wslTouched=$false
$lifecycleLock=$null
$cleanupIdentityToken=$null
try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $preflight=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Runtime 2>&1)
    if($LASTEXITCODE -ne 0){$preflight|Write-Output;exit $LASTEXITCODE}
    $lifecycleLock=Enter-ThriveLensLifecycleLock
    $cleanupIdentityToken=Get-ThriveLensWslCleanupIdentityToken -LifecycleLock $lifecycleLock
    $lockedManifest=Get-ThriveLensManifest
    if(@($lockedManifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)){throw 'RESOURCE_PHASE_NOT_ACTIVE_AFTER_LIFECYCLE_LOCK'}
    $null=Invoke-ThriveLensResourceGate
    if((Get-ThriveLensFreeMemoryBytes) -lt 1073741824){throw 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK'}
    $wslTouched=$true
    $null=Assert-ThriveLensWslIdentity -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock;Assert-ThriveLensWslPackages
    if((Get-ThriveLensWslClusterState) -cne 'VALID'){throw 'POSTGRES_CLUSTER_INVALID_AFTER_LIFECYCLE_LOCK'}
    Assert-ThriveLensLinuxPathPolicy -RequireLeaf
    Assert-ThriveLensWslAbsent;Assert-ThriveLensHostPortAbsent
    $p=Get-ThriveLensWslPaths
    $options='-h 127.0.0.1 -p 55432 -c max_connections=20 -c shared_buffers=64MB -c work_mem=2MB -c maintenance_work_mem=32MB -c password_encryption=scram-sha-256 -c logging_collector=off -c log_statement=none -c log_connections=off -c log_disconnections=off -c log_hostname=off -c log_min_error_statement=panic'
    $attempted=$true
    $start=Invoke-ThriveLensGuardedDistro -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock -TimeoutSeconds 45 -Arguments @('/usr/sbin/runuser','-u','postgres','--',$p.PgCtl,'start','-D',$p.DataRoot,'-l','/dev/null','-o',$options,'-w','-t','30')
    if($start.ExitCode -ne 0){throw 'POSTGRES_START_FAILED'}
    Assert-ThriveLensWslLoopback;Assert-ThriveLensHostLoopback
    $null=Invoke-ThriveLensResourceGate
    [pscustomobject]@{schema_version=1;status='STARTED';address='127.0.0.1';port=55432;service_registered=$false;logs_persisted=$false}|ConvertTo-Json -Compress
}
catch{
    $code=if($_.Exception.Message -match '^[A-Z0-9_]+$'){$_.Exception.Message}else{'POSTGRES_START_INTERNAL_ERROR'}
    $fatal=$false
    $cleanupIdentityReady=$false
    if($null -ne $lifecycleLock -and $null -ne $cleanupIdentityToken){
        try{$null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock;$cleanupIdentityReady=$true}catch{$code='POSTGRES_START_CLEANUP_IDENTITY_FAILED';$fatal=$true}
    }
    if($attempted){
        # Graceful shutdown and exact-distro termination are deliberately
        # independent. A broken/partial cluster can make pg_ctl fail; that must
        # never skip the containment boundary that terminates ThriveLens-R0.
        if($cleanupIdentityReady){try{$null=Stop-ThriveLensPostgresUnderLock -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock}catch{$code='POSTGRES_START_CLEANUP_FAILED';$fatal=$true}}
        if($cleanupIdentityReady){try{Stop-ThriveLensDistroAndVerify -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock;Assert-ThriveLensHostPortAbsent}catch{$code='POSTGRES_START_CLEANUP_FAILED';$fatal=$true}}
    }
    elseif($wslTouched){
        if($cleanupIdentityReady){try{Assert-ThriveLensWslAbsent;Assert-ThriveLensHostPortAbsent}catch{$code='POSTGRES_START_CLEANUP_FAILED';$fatal=$true}}
        if($cleanupIdentityReady){try{Stop-ThriveLensDistroAndVerify -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock}catch{$code='POSTGRES_START_CLEANUP_FAILED';$fatal=$true}}
        if($cleanupIdentityReady){try{Assert-ThriveLensHostPortAbsent}catch{$code='POSTGRES_START_CLEANUP_FAILED';$fatal=$true}}
    }
    if($attempted){try{$null=Invoke-ThriveLensResourceGate}catch{if(-not $fatal){$code='POST_MUTATION_RESOURCE_GATE_FAILED'};$fatal=$true}}
    [pscustomobject]@{schema_version=1;status=if($fatal){'ERROR'}else{'BLOCKED'};code=$code}|ConvertTo-Json -Compress
    if($fatal){exit 3};exit 2
}
finally{if($null -ne $lifecycleLock){Exit-ThriveLensLifecycleLock -Mutex $lifecycleLock}}
