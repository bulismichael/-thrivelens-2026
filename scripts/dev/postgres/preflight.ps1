#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Install','Initialize','Runtime')][string]$Action = 'Runtime',
    [ValidateSet('Backend','Python','PostgreSQL')][string]$InstallKind = 'Backend'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$blockers = [Collections.Generic.List[string]]::new()
$projection = [int64]0
$wslProbed = $false
$preflightLock = $null

function Stop-ThriveLensPreflightDistro {
    # Preflight never owns a running database. Under the lifecycle lock, prove
    # there is no PostgreSQL process/listener before terminating the exact
    # project distro that read-only probes may have launched.
    Assert-ThriveLensWslAbsent
    Assert-ThriveLensHostPortAbsent
    $null = Assert-ThriveLensWslCleanupIdentity
    Stop-ThriveLensDistroAndVerify
    Assert-ThriveLensHostPortAbsent
}

try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $preflightLock=Enter-ThriveLensLifecycleLock
    $manifest = Get-ThriveLensManifest
    try{if (@($manifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)) { $blockers.Add('RESOURCE_PHASE_NOT_ACTIVE') }}catch{$blockers.Add('RESOURCE_PHASE_UNAVAILABLE')}
    if ($Action -eq 'Install') {
        if ($InstallKind -eq 'Python' -or $InstallKind -eq 'Backend') { $blockers.Add('PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE') }
        if ($InstallKind -eq 'PostgreSQL') { $projection = [int64]$manifest.resource_policy.postgresql_worst_case_additional_bytes }
    }
    elseif ($Action -eq 'Initialize') { $projection = [int64]$manifest.resource_policy.postgresql_initialization_worst_case_additional_bytes }
    try { $null = Invoke-ThriveLensResourceGate -ProjectedAdditionalBytes $projection } catch { $code=$_.Exception.Message;if($code -notmatch '^[A-Z0-9_]+$'){$code='RESOURCE_GATE_FAILED'};$blockers.Add($code) }
    $minimum = if ($Action -eq 'Install') { [int64]$manifest.resource_policy.install_minimum_free_memory_bytes } else { [int64]$manifest.resource_policy.runtime_minimum_free_memory_bytes }
    try{if ((Get-ThriveLensFreeMemoryBytes) -lt $minimum) { $blockers.Add('LOW_FREE_MEMORY') }}catch{$blockers.Add('MEMORY_MEASUREMENT_UNAVAILABLE')}
    if($blockers.Count -gt 0){
        [pscustomobject]@{schema_version=1;status='BLOCKED';action=$Action;install_kind=if($Action -eq 'Install'){$InstallKind}else{$null};projected_additional_bytes=$projection;codes=@($blockers|Select-Object -Unique)}|ConvertTo-Json -Compress;exit 2
    }
    $wslProbed = $true
    try { $null = Assert-ThriveLensWslIdentity } catch { $blockers.Add($_.Exception.Message) }
    if($blockers.Count -gt 0){
        try { Stop-ThriveLensPreflightDistro } catch {
            [pscustomobject]@{schema_version=1;status='ERROR';action=$Action;codes=@('PREFLIGHT_DISTRO_CLEANUP_FAILED')}|ConvertTo-Json -Compress;exit 3
        }
        [pscustomobject]@{schema_version=1;status='BLOCKED';action=$Action;install_kind=if($Action -eq 'Install'){$InstallKind}else{$null};projected_additional_bytes=$projection;codes=@($blockers|ForEach-Object{if($_ -match '^[A-Z0-9_]+$'){$_}else{'WSL_IDENTITY_FAILED'}}|Select-Object -Unique)}|ConvertTo-Json -Compress;exit 2
    }
    if ($Action -in @('Initialize','Runtime') -or ($Action -eq 'Install' -and $InstallKind -eq 'PostgreSQL')) {
        try { Assert-ThriveLensWslPackages } catch { $blockers.Add($_.Exception.Message) }
    }
    if ($Action -eq 'Initialize') { try { Assert-ThriveLensDataInventoryGate } catch { $blockers.Add($_.Exception.Message) } }
    try{Assert-ThriveLensWslInternalDisk -RequiredBytes $projection}catch{$blockers.Add($_.Exception.Message)}
    if ($Action -eq 'Runtime') {
        try{$clusterState=Get-ThriveLensWslClusterState;if($clusterState -ceq 'ABSENT'){$blockers.Add('POSTGRES_CLUSTER_UNAVAILABLE')}elseif($clusterState -cne 'VALID'){$blockers.Add('PARTIAL_CLUSTER_PRESENT')}}catch{$blockers.Add('CLUSTER_STATE_MEASUREMENT_UNAVAILABLE')}
    }
    try{if((Get-ThriveLensFreeMemoryBytes) -lt $minimum){$blockers.Add('LOW_FREE_MEMORY_AFTER_WSL_PROBES')}}catch{$blockers.Add('MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES')}
    try { Stop-ThriveLensPreflightDistro } catch {
        [pscustomobject]@{schema_version=1;status='ERROR';action=$Action;codes=@('PREFLIGHT_DISTRO_CLEANUP_FAILED')}|ConvertTo-Json -Compress;exit 3
    }
    if ($blockers.Count -gt 0) {
        $safeCodes=@($blockers|ForEach-Object{if($_ -match '^[A-Z0-9_]+$'){$_}else{'WSL_VALIDATION_FAILED'}}|Select-Object -Unique)
        [pscustomobject]@{ schema_version=1; status='BLOCKED'; action=$Action; install_kind=if($Action -eq 'Install'){$InstallKind}else{$null}; projected_additional_bytes=$projection; codes=$safeCodes } | ConvertTo-Json -Compress
        exit 2
    }
    [pscustomobject]@{ schema_version=1; status='READY'; action=$Action; install_kind=if($Action -eq 'Install'){$InstallKind}else{$null}; projected_additional_bytes=$projection; codes=@() } | ConvertTo-Json -Compress
}
catch {
    if($wslProbed){try{Stop-ThriveLensPreflightDistro}catch{}}
    [pscustomobject]@{ schema_version=1; status='ERROR'; action=$Action; codes=@('PREFLIGHT_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 3
}
finally{if($null -ne $preflightLock){Exit-ThriveLensLifecycleLock -Mutex $preflightLock}}
