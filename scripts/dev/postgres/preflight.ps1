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
$cleanupIdentityToken = $null

function Stop-ThriveLensPreflightDistro {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock
    )
    # Preflight never owns a running database. Under the lifecycle lock, prove
    # there is no PostgreSQL process/listener before terminating the exact
    # project distro that read-only probes may have launched.
    $null = Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    Assert-ThriveLensWslAbsent
    Assert-ThriveLensHostPortAbsent
    Stop-ThriveLensDistroAndVerify -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    Assert-ThriveLensHostPortAbsent
}

function Complete-ThriveLensPreflightProbeAndAdmit {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)][int64]$MinimumFreeMemoryBytes
    )
    Stop-ThriveLensPreflightDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    try {
        Wait-ThriveLensInterCycleMemorySettle -MinimumFreeMemoryBytes $MinimumFreeMemoryBytes
    }
    catch {
        switch ([string]$_.Exception.Message) {
            'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED' { throw 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' }
            'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE' { throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' }
            default { throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' }
        }
    }
    Assert-ThriveLensDistroStopped
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    Assert-ThriveLensHostPortAbsent

    try{$memoryValues=@(Get-ThriveLensFreeMemoryBytes)}catch{throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
    if($memoryValues.Count -ne 1 -or $null -eq $memoryValues[0] -or $memoryValues[0] -is [bool]){throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
    $memoryText=[Convert]::ToString($memoryValues[0],[Globalization.CultureInfo]::InvariantCulture)
    $freeMemoryBytes=[int64]0
    if(-not [int64]::TryParse($memoryText,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$freeMemoryBytes) -or $freeMemoryBytes -lt 0){throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
    if($freeMemoryBytes -lt $MinimumFreeMemoryBytes){throw 'LOW_FREE_MEMORY_AFTER_WSL_PROBES'}
}

try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $preflightLock=Enter-ThriveLensLifecycleLock
    # Host-only identity authority is captured under the lifecycle mutex before
    # the first command that can launch the dedicated distro.
    $cleanupIdentityToken=Get-ThriveLensWslCleanupIdentityToken -LifecycleLock $preflightLock
    $manifest = Get-ThriveLensManifest
    try{if (@($manifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)) { $blockers.Add('RESOURCE_PHASE_NOT_ACTIVE') }}catch{$blockers.Add('RESOURCE_PHASE_UNAVAILABLE')}
    if ($Action -eq 'Install') {
        if ($InstallKind -eq 'Python' -or $InstallKind -eq 'Backend') { $blockers.Add('PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE') }
        if ($InstallKind -eq 'PostgreSQL') { $projection = [int64]$manifest.resource_policy.postgresql_worst_case_additional_bytes }
    }
    elseif ($Action -eq 'Initialize') { $projection = [int64]$manifest.resource_policy.postgresql_initialization_worst_case_additional_bytes }
    try { $null = Invoke-ThriveLensResourceGate -ProjectedAdditionalBytes $projection } catch { $code=$_.Exception.Message;if($code -notmatch '^[A-Z0-9_]+$'){$code='RESOURCE_GATE_FAILED'};$blockers.Add($code) }
    $memoryPolicy = Get-ThriveLensMemoryPolicyThresholds -Manifest $manifest
    $minimum = if ($Action -eq 'Install') { $memoryPolicy.InstallMinimumBytes } else { $memoryPolicy.RuntimeMinimumBytes }
    try{if ((Get-ThriveLensFreeMemoryBytes) -lt $minimum) { $blockers.Add('LOW_FREE_MEMORY') }}catch{$blockers.Add('MEMORY_MEASUREMENT_UNAVAILABLE')}
    if($blockers.Count -gt 0){
        [pscustomobject]@{schema_version=1;status='BLOCKED';action=$Action;install_kind=if($Action -eq 'Install'){$InstallKind}else{$null};projected_additional_bytes=$projection;codes=@($blockers|Select-Object -Unique)}|ConvertTo-Json -Compress;exit 2
    }
    $wslProbed = $true
    try { $null = Assert-ThriveLensWslIdentity -IdentityToken $cleanupIdentityToken -LifecycleLock $preflightLock } catch { $blockers.Add($_.Exception.Message) }
    if($blockers.Count -gt 0){
        try { Stop-ThriveLensPreflightDistro -IdentityToken $cleanupIdentityToken -LifecycleLock $preflightLock } catch {
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
    try {
        Complete-ThriveLensPreflightProbeAndAdmit -IdentityToken $cleanupIdentityToken -LifecycleLock $preflightLock -MinimumFreeMemoryBytes $minimum
    }
    catch {
        $postProbeCode=[string]$_.Exception.Message
        if($postProbeCode -cin @('LOW_FREE_MEMORY_AFTER_WSL_PROBES','MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES')){
            $blockers.Add($postProbeCode)
        }
        else{
            [pscustomobject]@{schema_version=1;status='ERROR';action=$Action;codes=@('PREFLIGHT_DISTRO_CLEANUP_FAILED')}|ConvertTo-Json -Compress;exit 3
        }
    }
    if ($blockers.Count -gt 0) {
        $safeCodes=@($blockers|ForEach-Object{if($_ -match '^[A-Z0-9_]+$'){$_}else{'WSL_VALIDATION_FAILED'}}|Select-Object -Unique)
        [pscustomobject]@{ schema_version=1; status='BLOCKED'; action=$Action; install_kind=if($Action -eq 'Install'){$InstallKind}else{$null}; projected_additional_bytes=$projection; codes=$safeCodes } | ConvertTo-Json -Compress
        exit 2
    }
    [pscustomobject]@{ schema_version=1; status='READY'; action=$Action; install_kind=if($Action -eq 'Install'){$InstallKind}else{$null}; projected_additional_bytes=$projection; codes=@() } | ConvertTo-Json -Compress
}
catch {
    if($wslProbed -and $null -ne $preflightLock -and $null -ne $cleanupIdentityToken){try{Stop-ThriveLensPreflightDistro -IdentityToken $cleanupIdentityToken -LifecycleLock $preflightLock}catch{}}
    [pscustomobject]@{ schema_version=1; status='ERROR'; action=$Action; codes=@('PREFLIGHT_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 3
}
finally{if($null -ne $preflightLock){Exit-ThriveLensLifecycleLock -Mutex $preflightLock}}
