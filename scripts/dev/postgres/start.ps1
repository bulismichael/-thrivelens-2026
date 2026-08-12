#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$attempted = $false
$wslTouched = $false
$lifecycleLock = $null
$configurationLease = $null
$leasedContract = $null
$leasedPaths = $null
$cleanupIdentityToken = $null
$startSucceeded = $false
$startCommitResourceGateVerified = $false
$finalResourceGateVerified = $false
$finalResourceGateFailed = $false
$cleanupVerified = $false
$distroAbsent = $false
$hostAbsent = $false
$lockReleaseFailed = $false
$lockReleaseAttempted = $false
$lockReleased = $false
$leaseReleaseFailed = $false
$leaseReleaseAttempted = $false
$leaseReleased = $false
$leaseIntegrityFailed = $false
$leaseIntegrityVerified = $false
$cleanupFailed = $false
$identityFailure = $false
$guestCleanupAllowed = $false
$guestCleanupAttempted = $false
$forcedTerminationAttempted = $false
$originalCode = $null
$response = $null
$responseExitCode = 3

try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force

    $lifecycleLock = Enter-ThriveLensLifecycleLock
    $configurationLease = Enter-ThriveLensConfigurationLease
    $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
    $leasedContract = Get-ThriveLensWslContract -ConfigurationLease $configurationLease
    $leasedPaths = Get-ThriveLensWslPaths -Contract $leasedContract
    $cleanupIdentityToken = Get-ThriveLensWslCleanupIdentityToken `
        -LifecycleLock $lifecycleLock `
        -Contract $leasedContract

    $null = Invoke-ThriveLensPostgresStartUnderLock `
        -ConfigurationLease $configurationLease `
        -IdentityToken $cleanupIdentityToken `
        -LifecycleLock $lifecycleLock `
        -WslTouched ([ref]$wslTouched) `
        -StartAttempted ([ref]$attempted) `
        -StartCommitResourceGateVerified ([ref]$startCommitResourceGateVerified)
    $finalResourceGateVerified = $startCommitResourceGateVerified
    if (-not $startCommitResourceGateVerified) {
        throw 'POST_MUTATION_RESOURCE_GATE_FAILED'
    }
    $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
    $leaseIntegrityVerified = $true
    $startSucceeded = $true

    try {
        # Dispose the configuration lease while the original lifecycle mutex
        # and identity token are still held.  A release anomaly therefore
        # enters catch with exact-distro containment authority still available.
        $leaseReleaseAttempted = $true
        Exit-ThriveLensConfigurationLease -Lease $configurationLease
        $leaseReleased = $true
        $configurationLease = $null
    }
    catch {
        $leaseReleaseFailed = $true
        throw 'POSTGRES_START_CONFIGURATION_LEASE_RELEASE_FAILED'
    }

    try {
        $lockReleaseAttempted = $true
        Exit-ThriveLensLifecycleLock -Mutex $lifecycleLock
        $lockReleased = $true
        $lifecycleLock = $null
        $cleanupIdentityToken = $null
    }
    catch {
        # A failed release invalidates STARTED.  Catch may use only this
        # original mutex/token if ownership can still be re-proved.
        $lockReleaseFailed = $true
        throw 'POSTGRES_START_LOCK_RELEASE_FAILED'
    }

    $response = [pscustomobject]@{
        schema_version = 1
        status = 'STARTED'
        address = '127.0.0.1'
        port = [int]$leasedPaths.Port
        service_registered = $false
        logs_persisted = $false
    }
    $responseExitCode = 0
}
catch {
    $rawCode = [string]$_.Exception.Message
    $originalCode = if ($rawCode -cmatch '^[A-Z0-9_]+$') {
        $rawCode
    }
    else {
        'POSTGRES_START_INTERNAL_ERROR'
    }

    $cleanupRequired = $attempted -or $wslTouched
    if ($attempted) { $finalResourceGateVerified = $false }
    $resourceGateOutputDrainIncomplete =
        $originalCode -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
    if ($resourceGateOutputDrainIncomplete) {
        # An incompletely drained runner has unknown retained output/process
        # state.  Containment remains mandatory, but neither a guest command nor
        # a second resource runner is safe in this transaction.
        $finalResourceGateFailed = $true
    }
    $cleanupLeaseValid = $false

    # Guest cleanup is configuration-dependent.  It is permitted only while
    # the original, still-held lease asserts successfully.  A lease whose
    # disposal was already attempted is terminal and cannot authorize a guest
    # command, even when the pre-disposal assertion succeeded.
    if ($null -ne $configurationLease -and -not $leaseReleaseAttempted) {
        try {
            $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
            $leaseIntegrityVerified = $true
            $cleanupLeaseValid = $true
        }
        catch {
            $leaseIntegrityFailed = $true
        }
    }

    try {
        $guestCleanupAllowed = Test-ThriveLensCredentialCleanupAllowedAfterFailure `
            -FailureCode $originalCode
    }
    catch {
        $guestCleanupAllowed = $false
    }

    $sameTokenAuthority = $false
    if ($null -ne $lifecycleLock -and $null -ne $cleanupIdentityToken) {
        try {
            $null = Assert-ThriveLensWslCleanupIdentity `
                -IdentityToken $cleanupIdentityToken `
                -LifecycleLock $lifecycleLock `
                -Contract $leasedContract
            $sameTokenAuthority = $true
        }
        catch {
            $identityFailure = $true
        }
    }
    elseif ($cleanupRequired) {
        $identityFailure = $true
    }

    if (-not $resourceGateOutputDrainIncomplete -and
        $sameTokenAuthority -and $cleanupLeaseValid -and
        $guestCleanupAllowed -and $attempted) {
        # Guest pg_ctl cleanup has three independent gates: the original lease,
        # the original failure policy, and the original same-token identity.
        try {
            $guestCleanupAttempted = $true
            $null = Stop-ThriveLensPostgresUnderLock `
                -IdentityToken $cleanupIdentityToken `
                -LifecycleLock $lifecycleLock `
                -Contract $leasedContract `
                -Paths $leasedPaths
        }
        catch {
            $cleanupFailed = $true
        }
    }

    # Forced exact-distro containment is independent from the lease and guest
    # cleanup policy.  Revalidate the original token under the original mutex
    # immediately before using the only supported exact-distro boundary.
    $forcedTerminationAuthorized = $false
    if ($cleanupRequired -and $null -ne $lifecycleLock -and
        $null -ne $cleanupIdentityToken) {
        try {
            $null = Assert-ThriveLensWslCleanupIdentity `
                -IdentityToken $cleanupIdentityToken `
                -LifecycleLock $lifecycleLock `
                -Contract $leasedContract
            $forcedTerminationAuthorized = $true
        }
        catch {
            $sameTokenAuthority = $false
            $identityFailure = $true
        }
    }
    if ($forcedTerminationAuthorized) {
        try {
            $forcedTerminationAttempted = $true
            $null = Stop-ThriveLensDistroAndVerify `
                -IdentityToken $cleanupIdentityToken `
                -LifecycleLock $lifecycleLock `
                -Contract $leasedContract
        }
        catch {
            $cleanupFailed = $true
            $cleanupFailure = Resolve-ThriveLensDistroCleanupFailure `
                -FailureCode ([string]$_.Exception.Message)
            if (-not [bool]$cleanupFailure.IdentityAuthorityPreserved) {
                $sameTokenAuthority = $false
                $identityFailure = $true
            }
        }
    }

    $absenceObservationAuthorized = $null -ne $leasedContract -and
        $null -ne $leasedPaths -and
        ($forcedTerminationAuthorized -or -not $cleanupRequired)
    if ($absenceObservationAuthorized) {
        try {
            Assert-ThriveLensDistroStopped -Contract $leasedContract
            $distroAbsent = $true
        }
        catch {
            $distroAbsent = $false
            $cleanupFailed = $cleanupRequired
        }
        try {
            Assert-ThriveLensHostPortAbsent `
                -Paths $leasedPaths `
                -Contract $leasedContract
            $hostAbsent = $true
        }
        catch {
            $hostAbsent = $false
            $cleanupFailed = $cleanupRequired
        }
    }
    $cleanupVerified = $distroAbsent -and $hostAbsent -and
        (-not $cleanupRequired -or ($forcedTerminationAuthorized -and -not $identityFailure)) -and
        -not $resourceGateOutputDrainIncomplete

    # Containment and absence proof always precede resource accounting.  Any
    # attempted pg_ctl start whose core gate did not complete is re-gated only
    # from the still-valid original lease, before reverse disposal.
    if ($attempted -and -not $resourceGateOutputDrainIncomplete) {
        if ($cleanupLeaseValid -and $null -ne $leasedContract) {
            try {
                $null = Invoke-ThriveLensResourceGate -Manifest $leasedContract.Manifest
                $finalResourceGateVerified = $true
            }
            catch {
                $finalResourceGateFailed = $true
            }
        }
        else {
            $finalResourceGateFailed = $true
        }
    }

    # Lease assertion and disposal are deliberately separate attempts.  Even a
    # failed assertion cannot strand its retained handles.  Never retry a lease
    # disposal whose terminal transition was already attempted.
    if ($null -ne $configurationLease -and -not $leaseReleaseAttempted) {
        $leaseReleaseAttempted = $true
        try {
            Exit-ThriveLensConfigurationLease -Lease $configurationLease
            $leaseReleased = $true
        }
        catch {
            $leaseReleaseFailed = $true
        }
    }
    $configurationLease = $null

    # Release the original mutex only after lease disposal reaches terminal
    # state.  Do not retry an uncertain release attempted by the success tail.
    if ($null -ne $lifecycleLock -and -not $lockReleaseAttempted) {
        $lockReleaseAttempted = $true
        try {
            Exit-ThriveLensLifecycleLock -Mutex $lifecycleLock
            $lockReleased = $true
        }
        catch {
            $lockReleaseFailed = $true
        }
    }
    $lifecycleLock = $null
    $cleanupIdentityToken = $null

    $expectedValidationCodes = @(
        'RESOURCE_PHASE_NOT_ACTIVE_AFTER_LIFECYCLE_LOCK',
        'RESOURCE_PHASE_UNAVAILABLE',
        'RESOURCE_PHASE_CHANGED_AFTER_CONFIGURATION_LEASE',
        'RESOURCE_GATE_FAILED',
        'RESOURCE_GATE_UNAVAILABLE',
        'RESOURCE_GATE_RESULT_INVALID',
        'RESOURCE_GATE_MANIFEST_INVALID',
        'RESOURCE_GATE_PROCESS_START_FAILED',
        'RESOURCE_GATE_TIMEOUT',
        'RESOURCE_GATE_OUTPUT_LIMIT',
        'WSL_STANDARD_INPUT_INVALID',
        'WSL_STANDARD_INPUT_LIMIT_EXCEEDED',
        'RUNTIME_MEMORY_POLICY_INVALID',
        'MEMORY_MEASUREMENT_UNAVAILABLE',
        'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK',
        'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES',
        'LOW_FREE_MEMORY_AFTER_WSL_PROBES',
        'POSTGRES_CLUSTER_INVALID_AFTER_LIFECYCLE_LOCK',
        'POSTGRES_CLUSTER_STILL_RUNNING',
        'POSTGRES_LISTENER_STILL_PRESENT',
        'POSTGRES_PROCESS_STILL_PRESENT',
        'HOST_POSTGRES_LISTENER_STILL_PRESENT',
        'HOST_PORTPROXY_STILL_PRESENT',
        'CLUSTER_STATE_MEASUREMENT_UNAVAILABLE',
        'WSL_FREE_DISK_INSUFFICIENT'
    )
    $expectedValidationPrefixes = @(
        'PROJECTED_RESOURCE_', 'PROJECTED_FREE_DISK_', 'MEMORY_MEASUREMENT_',
        'WSL_VERSION_', 'WSL_ARCHITECTURE_', 'WSL_UBUNTU_', 'WSL_PACKAGE_',
        'WSL_PGDG_', 'WSL_NO_AUTOSTART_', 'WSL_POSTGRES_SERVICE_',
        'WSL_STORAGE_', 'WSL_VHD_', 'WSL_MOUNT_', 'WSL_PATH_', 'WSL_TREE_',
        'WSL_ROOT_', 'WSL_CLUSTER_', 'WSL_UNMANAGED_CLUSTER_', 'LINUX_PATH_',
        'LINUX_TREE_', 'HOST_'
    )
    $expectedValidation = $expectedValidationCodes -ccontains $originalCode
    if (-not $expectedValidation) {
        foreach ($prefix in $expectedValidationPrefixes) {
            if ($originalCode.StartsWith($prefix, [StringComparison]::Ordinal)) {
                $expectedValidation = $true
                break
            }
        }
    }

    $originalIdentityOrLeaseFailure = $originalCode -match 'IDENTITY' -or
        $originalCode -match '^CONFIGURATION_LEASE_' -or
        $originalCode -match '^LIFECYCLE_LOCK_'
    $fatal = $startSucceeded -or $attempted -or -not $expectedValidation -or
        -not $cleanupVerified -or $identityFailure -or $cleanupFailed -or
        $lockReleaseFailed -or $leaseReleaseFailed -or
        $leaseIntegrityFailed -or $finalResourceGateFailed -or
        $originalIdentityOrLeaseFailure -or
        $originalCode -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED'
    $finalCode = if ($resourceGateOutputDrainIncomplete -and -not $attempted) {
        'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
    }
    elseif ($finalResourceGateFailed) {
        'POST_MUTATION_RESOURCE_GATE_FAILED'
    }
    elseif ($lockReleaseFailed) {
        'POSTGRES_START_LOCK_RELEASE_FAILED'
    }
    elseif ($leaseReleaseFailed) {
        'POSTGRES_START_CONFIGURATION_LEASE_RELEASE_FAILED'
    }
    elseif ($leaseIntegrityFailed) {
        'POSTGRES_START_CONFIGURATION_LEASE_FAILED'
    }
    elseif ($identityFailure) {
        'POSTGRES_START_CLEANUP_IDENTITY_FAILED'
    }
    elseif ($cleanupFailed -or -not $cleanupVerified) {
        'POSTGRES_START_CLEANUP_FAILED'
    }
    else {
        $originalCode
    }

    $response = [pscustomobject]@{
        schema_version = 1
        status = if ($fatal) { 'ERROR' } else { 'BLOCKED' }
        code = $finalCode
        original_code = $originalCode
        cleanup_required = $cleanupRequired
        cleanup_verified = $cleanupVerified
        guest_cleanup_allowed = $guestCleanupAllowed
        guest_cleanup_attempted = $guestCleanupAttempted
        forced_termination_attempted = $forcedTerminationAttempted
        post_mutation_resource_gate_verified = $finalResourceGateVerified -and -not $finalResourceGateFailed
        configuration_lease_integrity_verified = $leaseIntegrityVerified -and -not $leaseIntegrityFailed
        configuration_lease_release_attempted = $leaseReleaseAttempted
        configuration_lease_released = $leaseReleased
        lifecycle_lock_release_attempted = $lockReleaseAttempted
        lifecycle_lock_released = $lockReleased
    }
    $responseExitCode = if ($fatal) { 3 } else { 2 }
}
finally {
    # Catch owns all classified release attempts.  Never silently retry an
    # uncertain mutex or lease release after final outcome composition.
    $cleanupIdentityToken = $null
}

$response | ConvertTo-Json -Compress
exit $responseExitCode
