#Requires -Version 7.0

[CmdletBinding()]
param([string]$PasswordFile)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-ThriveLensRuntimeCredential {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$Paths
    )

    if ($Path -cnotmatch '^/run/thrivelens-r0-(?:auth|wrong)-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $removeResult=$null;$absenceResult=$null;$rootFailureCode=$null
    $removeSucceeded=$false;$absenceVerified=$false;$allowAbsenceProbe=$true
    try {
        try {
            $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
            $removeResult = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract -Arguments @('/usr/bin/rm', '-f', '--', $Path)
            $removeSucceeded = $removeResult.ExitCode -eq 0
        }
        catch {
            $removeRawCode=[string]$_.Exception.Message
            $rootFailureCode=Resolve-ThriveLensRuntimePublicCode -Code $removeRawCode
            # Only bounded supervisor failures whose guarded wrapper already
            # re-established same-token containment may be followed by a later
            # read-only absence probe. Identity/lock/unknown failures authorize
            # no further guest command.
            $allowAbsenceProbe=Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $removeRawCode
        }

        if($allowAbsenceProbe){
            try {
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
                $absenceResult = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract -Arguments @('/usr/bin/test', '!', '-e', $Path)
                $absenceVerified = $absenceResult.ExitCode -eq 0
            }
            catch {
                $absenceVerified=$false
                if($null -eq $rootFailureCode){$rootFailureCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)}
            }
        }
        if(-not $removeSucceeded -and $null -eq $rootFailureCode){$rootFailureCode='AUTH_FILE_CLEANUP_REMOVE_FAILED'}
        if((-not $allowAbsenceProbe -or -not $absenceVerified) -and $null -eq $rootFailureCode){$rootFailureCode='AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED'}
        return Resolve-ThriveLensCredentialCleanupResult -RemoveSucceeded $removeSucceeded -AbsenceAttempted $allowAbsenceProbe -AbsenceVerified $absenceVerified -RootFailureCode $rootFailureCode
    }
    finally {
        $removeResult = $null
        $absenceResult = $null
    }
}

function Assert-ThriveLensAuthenticatedScalar {
    param(
        [Parameter(Mandatory)][string]$AuthFile,
        [Parameter(Mandatory)][string]$Sql,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$FailureCode,
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$Paths
    )

    if ($AuthFile -cnotmatch '^/run/thrivelens-r0-auth-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $probe = $null
    try {
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
        $probe = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract -Arguments @(
            '/usr/sbin/runuser', '-u', 'postgres', '--',
            '/usr/bin/env', '-i', "PGPASSFILE=$AuthFile", 'PGCONNECT_TIMEOUT=5', 'PGREQUIREAUTH=scram-sha-256',
            '/usr/bin/psql', '-X', '-w', '-h', '127.0.0.1', '-p', ([string]$Paths.Port),
            '-U', 'tl_bootstrap', '-d', 'postgres', '-Atq',
            '--set=ON_ERROR_STOP=1', '--command', $Sql
        )
        if ($probe.ExitCode -ne 0 -or $probe.Output -cne $Expected) {
            throw $FailureCode
        }
    }
    finally {
        # Query output is deliberately neither returned nor printed.
        $probe = $null
    }
}

function Get-ThriveLensPrivateClusterIdentityFingerprint {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)]$Contract,
        [Parameter(Mandatory)]$Paths
    )

    $probe = $null
    $privateOutput = $null
    $privateError = $null
    $identifierText = $null
    $identifierBytes = $null
    try {
        $null = Assert-ThriveLensWslCleanupIdentity `
            -IdentityToken $IdentityToken `
            -LifecycleLock $LifecycleLock `
            -Contract $Contract
        $probe = Invoke-ThriveLensGuardedDistro `
            -IdentityToken $IdentityToken `
            -LifecycleLock $LifecycleLock `
            -Contract $Contract `
            -CapturePrivateStandardError `
            -Arguments @(
                '/usr/bin/env', '-i', 'LC_ALL=C', 'LANG=C',
                $Paths.PgControlData, $Paths.DataRoot
            )
        if ($probe.ExitCode -ne 0) {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_PROBE_FAILED'
        }
        $privateOutput = [string]$probe.PrivateStandardOutput
        $privateError = [string]$probe.PrivateStandardError
        if (-not [string]::IsNullOrEmpty($privateError)) {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_PROBE_FAILED'
        }
        if ([string]::IsNullOrWhiteSpace($privateOutput) -or
            $privateOutput.Length -gt 131072 -or
            $privateOutput -cmatch '[^\x09\x0A\x0D\x20-\x7E]') {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_INVALID'
        }
        $matches = [regex]::Matches(
            $privateOutput,
            '(?m)^Database system identifier:\s+([1-9][0-9]{0,19})\r?$',
            [Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if ($matches.Count -ne 1) {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_INVALID'
        }
        $identifierText = [string]$matches[0].Groups[1].Value
        $identifier = [uint64]0
        if (-not [uint64]::TryParse(
                $identifierText,
                [Globalization.NumberStyles]::None,
                [Globalization.CultureInfo]::InvariantCulture,
                [ref]$identifier
            ) -or $identifier -eq 0 -or
            $identifier.ToString([Globalization.CultureInfo]::InvariantCulture) -cne $identifierText) {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_INVALID'
        }
        $identifierBytes = [Text.Encoding]::ASCII.GetBytes($identifierText)
        $fingerprint = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($identifierBytes)
        )
        if ($fingerprint -cnotmatch '^[A-F0-9]{64}$') {
            throw 'POSTGRES_SYSTEM_IDENTIFIER_INVALID'
        }
        return $fingerprint
    }
    finally {
        if ($null -ne $identifierBytes) {
            [Array]::Clear($identifierBytes, 0, $identifierBytes.Length)
        }
        $identifierText = $null
        $privateOutput = $null
        $privateError = $null
        $probe = $null
    }
}

function Get-ThriveLensInterCycleMemoryTargetBytes {
    param([Parameter(Mandatory)]$Manifest)

    try {
        $policyValues = @($Manifest.resource_policy)
        if ($policyValues.Count -ne 1 -or $null -eq $policyValues[0] -or
            $policyValues[0] -is [bool]) {
            throw 'INVALID_MEMORY_POLICY'
        }

        $validatedValues = [int64[]]::new(2)
        $fieldNames = @(
            'runtime_minimum_free_memory_bytes',
            'install_minimum_free_memory_bytes'
        )
        for ($index = 0; $index -lt $fieldNames.Count; $index++) {
            $property = $policyValues[0].PSObject.Properties[$fieldNames[$index]]
            $candidateValues = if ($null -eq $property) { @() } else { @($property.Value) }
            if ($candidateValues.Count -ne 1 -or $null -eq $candidateValues[0] -or
                $candidateValues[0] -isnot [int64]) {
                throw 'INVALID_MEMORY_POLICY'
            }
            $candidateBytes = [int64]$candidateValues[0]
            if ($candidateBytes -le 0) {
                throw 'INVALID_MEMORY_POLICY'
            }
            $validatedValues[$index] = $candidateBytes
        }
        return [Math]::Max($validatedValues[0], $validatedValues[1])
    }
    catch {
        throw 'RUNTIME_MEMORY_POLICY_INVALID'
    }
}

$started = $false
$failureExitCode = 2
$credentialCleanupFatal = $false
$credentialCleanupRequired = $false
$credentialRemoveFailed = $false
$credentialRootFailureCode = $null
$credentialAbsenceVerified = $true
$bootstrapSecret = $null
$wrongSecret = $null
$correctAuthFile = $null
$wrongAuthFile = $null
$wrongStandardOutput = $null
$wrongPrivateError = $null
$wrongOutcome = $null
$probeLifecycleLock = $null
$configurationLease = $null
$leasedContract = $null
$leasedPaths = $null
$probeIdentityToken = $null
$sameTokenEstablished = $false
$cleanupAuthorityVerified = $true
$distroAbsenceVerified = $false
$hostAbsenceVerified = $false
$lockReleaseFailed = $false
$lockReleaseAttempts = 0
$lockReleaseSuccesses = 0
$currentLockReleaseAttempted = $false
$currentLockReleased = $false
$leaseReleaseFailed = $false
$leaseReleaseAttempts = 0
$leaseReleaseSuccesses = 0
$currentLeaseReleaseAttempted = $false
$currentLeaseReleased = $false
$leaseIntegrityFailed = $false
$leaseIntegrityFailureCode = $null
$currentLeaseIntegrityVerified = $false
$attempted = $false
$wslTouched = $false
$startCommitResourceGateVerified = $false
$finalResourceGateVerified = $false
$finalResourceGateFailed = $false
$modulesReady = $false
$configurationFingerprint = $null
$clusterIdentityFingerprint = $null
$interCycleMemoryTargetBytes = [int64]0
$sameClusterIdentityVerified = $false
$completedCycles = 0
$proofCounts = [ordered]@{
    ScramAuthenticated = 0
    PasswordEncryptionVerified = 0
    HbaScramVerified = 0
    ScramVerifierVerified = 0
    WrongPasswordRejected = 0
    HostLoopbackReachable = 0
    CredentialAbsenceVerified = 0
    PostgresStopVerified = 0
    DistroAbsenceVerified = 0
    HostAbsenceVerified = 0
    ClusterIdentityProbed = 0
    PostMutationResourceGateVerified = 0
}

try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $modulesReady = $true

    foreach ($cycle in 1..2) {
        $distroAbsenceVerified = $false
        $hostAbsenceVerified = $false
        $cleanupAuthorityVerified = $true
        $attempted = $false
        $wslTouched = $false
        $startCommitResourceGateVerified = $false
        $finalResourceGateVerified = $false
        $finalResourceGateFailed = $false
        $started = $false
        $sameTokenEstablished = $false
        $leasedContract = $null
        $leasedPaths = $null
        $currentLockReleaseAttempted = $false
        $currentLockReleased = $false
        $currentLeaseReleaseAttempted = $false
        $currentLeaseReleased = $false
        $currentLeaseIntegrityVerified = $false
        $cycleCredentialCleanupRequired = $false
        $cycleCredentialAbsenceVerified = $true
        $cycleEvidence = [ordered]@{
            ScramAuthenticated = $false
            PasswordEncryptionVerified = $false
            HbaScramVerified = $false
            ScramVerifierVerified = $false
            WrongPasswordRejected = $false
            HostLoopbackReachable = $false
            CredentialAbsenceVerified = $false
            PostgresStopVerified = $false
            DistroAbsenceVerified = $false
            HostAbsenceVerified = $false
            ClusterIdentityProbed = $false
            PostMutationResourceGateVerified = $false
        }
        $probeLifecycleLock = Enter-ThriveLensLifecycleLock
        $configurationLease = Enter-ThriveLensConfigurationLease
        $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
        $currentLeaseIntegrityVerified = $true
        $leasedContract = Get-ThriveLensWslContract -ConfigurationLease $configurationLease
        $leasedPaths = Get-ThriveLensWslPaths -Contract $leasedContract
        $probeIdentityToken = Get-ThriveLensWslCleanupIdentityToken `
            -LifecycleLock $probeLifecycleLock `
            -Contract $leasedContract
        $sameTokenEstablished = $true

        $cycleFingerprint = Get-ThriveLensConfigurationLeaseFingerprint -Lease $configurationLease
        if ($cycleFingerprint -cnotmatch '^[A-F0-9]{64}$') {
            throw 'CONFIGURATION_LEASE_FINGERPRINT_INVALID'
        }
        if ($cycle -eq 1) {
            $configurationFingerprint = $cycleFingerprint
        }
        elseif ($cycleFingerprint -cne $configurationFingerprint) {
            throw 'CONFIGURATION_LEASE_FINGERPRINT_CHANGED'
        }

        $manifest = $leasedContract.Manifest
        try {
            $configuredPasswordFile = [IO.Path]::GetFullPath(
                [Environment]::ExpandEnvironmentVariables([string]$manifest.wsl_fallback.host_password_file)
            )
            $actual = if ([string]::IsNullOrWhiteSpace($PasswordFile)) {
                $configuredPasswordFile
            }
            else {
                [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($PasswordFile))
            }
        }
        catch { throw 'PASSWORD_FILE_PATH_INVALID' }
        if ($actual -cne $configuredPasswordFile) {
            throw 'PASSWORD_FILE_PATH_MISMATCH'
        }
        $null = Invoke-ThriveLensPostgresStartUnderLock `
            -ConfigurationLease $configurationLease `
            -IdentityToken $probeIdentityToken `
            -LifecycleLock $probeLifecycleLock `
            -WslTouched ([ref]$wslTouched) `
            -StartAttempted ([ref]$attempted) `
            -StartCommitResourceGateVerified ([ref]$startCommitResourceGateVerified)
        if (-not $startCommitResourceGateVerified) {
            throw 'POST_MUTATION_RESOURCE_GATE_FAILED'
        }
        $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
        $currentLeaseIntegrityVerified = $true
        $started = $true

        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
        Assert-ThriveLensClusterScramConfig -Paths $leasedPaths -Contract $leasedContract -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
        Assert-ThriveLensWslLoopback -Paths $leasedPaths -Contract $leasedContract -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensHostLoopback -Paths $leasedPaths -Contract $leasedContract

        $cycleClusterIdentityFingerprint = Get-ThriveLensPrivateClusterIdentityFingerprint `
            -IdentityToken $probeIdentityToken `
            -LifecycleLock $probeLifecycleLock `
            -Contract $leasedContract `
            -Paths $leasedPaths
        try {
            if ($cycle -eq 1) {
                $clusterIdentityFingerprint = $cycleClusterIdentityFingerprint
            }
            elseif ($cycleClusterIdentityFingerprint -cne $clusterIdentityFingerprint) {
                throw 'POSTGRES_SYSTEM_IDENTIFIER_INVALID'
            }
            else {
                $sameClusterIdentityVerified = $true
            }
            $cycleEvidence.ClusterIdentityProbed = $true
        }
        finally {
            $cycleClusterIdentityFingerprint = $null
        }

        # The hardened reader validates the exact configured path, ACLs,
        # identity, encoding and Base64Url value on every cycle.
        $correctAuthFile = '/run/thrivelens-r0-auth-' + [guid]::NewGuid().ToString('N') + '.pgpass'
        $correctCreate = $null
        $correctOperationFailure=$null
        try {
            $bootstrapSecret = Read-ThriveLensPostgresBootstrapSecret -Path $actual
            $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
            $credentialCleanupRequired=$true
            $cycleCredentialCleanupRequired=$true
            $correctCreate = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract `
                -StandardInput ("127.0.0.1:$($leasedPaths.Port):postgres:tl_bootstrap:$bootstrapSecret`n") `
                -Arguments @(
                    '/usr/bin/install', '-o', 'postgres', '-g', 'postgres', '-m', '0600',
                    '/dev/stdin', $correctAuthFile
                )
            $bootstrapSecret = $null
            if ($correctCreate.ExitCode -ne 0) { throw 'AUTH_FILE_CREATE_FAILED' }
            $correctCreate = $null

            # Keep the same correct credential bridge alive for every positive
            # proof. Each query can emit only its expected scalar and is never
            # forwarded to the caller.
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT 1' `
                -Expected '1' `
                -FailureCode 'SCRAM_AUTH_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract -Paths $leasedPaths
            $cycleEvidence.ScramAuthenticated = $true
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SHOW password_encryption' `
                -Expected 'scram-sha-256' `
                -FailureCode 'PASSWORD_ENCRYPTION_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract -Paths $leasedPaths
            $cycleEvidence.PasswordEncryptionVerified = $true
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) > 0) AND bool_and(error IS NULL) AND bool_and(auth_method = ''scram-sha-256''), false) FROM pg_hba_file_rules' `
                -Expected 't' `
                -FailureCode 'HBA_SCRAM_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract -Paths $leasedPaths
            $cycleEvidence.HbaScramVerified = $true
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) = 1) AND bool_and(rolpassword LIKE ''SCRAM-SHA-256$%''), false) FROM pg_authid WHERE rolname = ''tl_bootstrap''' `
                -Expected 't' `
                -FailureCode 'SCRAM_VERIFIER_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract -Paths $leasedPaths
            $cycleEvidence.ScramVerifierVerified = $true
            # This fixed synthetic Base64Url value has a prefix rejected by the
            # hardened real-secret reader, so it cannot equal an accepted secret.
            $wrongSecret = 'placeholder_R0_wrong_password_probe_0123456789ABCDEF'
            if ($wrongSecret -cnotmatch '^[A-Za-z0-9_-]{43,128}$') {
                throw 'WRONG_PASSWORD_FIXTURE_INVALID'
            }
            $wrongAuthFile = '/run/thrivelens-r0-wrong-' + [guid]::NewGuid().ToString('N') + '.pgpass'
            $wrongCreate = $null
            $wrongProbe = $null
            $wrongOperationFailure=$null
            $wrongExitCode = -1
            $wrongStandardOutput = $null
            $wrongPrivateError = $null
            try {
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
                $credentialCleanupRequired=$true
                $cycleCredentialCleanupRequired=$true
                $wrongCreate = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                    -Contract $leasedContract `
                    -StandardInput ("127.0.0.1:$($leasedPaths.Port):postgres:tl_bootstrap:$wrongSecret`n") `
                    -Arguments @(
                        '/usr/bin/install', '-o', 'postgres', '-g', 'postgres', '-m', '0600',
                        '/dev/stdin', $wrongAuthFile
                    )
                $wrongSecret = $null
                if ($wrongCreate.ExitCode -ne 0) { throw 'WRONG_AUTH_FILE_CREATE_FAILED' }
                $wrongCreate = $null

                # stderr stays in the shared 128 KiB in-memory budget and is
                # consumed only by the exact locale-fixed classifier below.
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
                $wrongProbe = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract -CapturePrivateStandardError -Arguments @(
                    '/usr/sbin/runuser', '-u', 'postgres', '--',
                    '/usr/bin/env', '-i', 'LC_ALL=C', 'LANG=C', "PGPASSFILE=$wrongAuthFile", 'PGCONNECT_TIMEOUT=5', 'PGREQUIREAUTH=scram-sha-256',
                    '/usr/bin/psql', '-X', '-w', '-h', '127.0.0.1', '-p', ([string]$leasedPaths.Port),
                    '-U', 'tl_bootstrap', '-d', 'postgres', '-Atq',
                    '--set=ON_ERROR_STOP=1', '--command', 'SELECT 1'
                )
                $wrongExitCode=[int]$wrongProbe.ExitCode
                $wrongStandardOutput=[string]$wrongProbe.PrivateStandardOutput
                $wrongPrivateError=[string]$wrongProbe.PrivateStandardError
            }
            catch{$wrongOperationFailure=[string]$_.Exception.Message;throw}
            finally {
                $wrongSecret = $null
                $wrongCreate = $null
                $wrongProbe = $null
                if($null -ne $wrongOperationFailure -and -not (Test-ThriveLensCredentialCleanupAllowedAfterFailure -FailureCode $wrongOperationFailure)){
                    $credentialCleanupFatal=$true
                    $credentialAbsenceVerified=$false
                    $cycleCredentialAbsenceVerified=$false
                }
                else{try {
                    $null=Assert-ThriveLensConfigurationLease -Lease $configurationLease
                    $currentLeaseIntegrityVerified=$true
                    $previousCredentialAbsence=$cycleCredentialAbsenceVerified
                    $previousOverallCredentialAbsence=$credentialAbsenceVerified
                    $credentialAbsenceVerified=$false
                    $cycleCredentialAbsenceVerified=$false
                    $credentialResult=Remove-ThriveLensRuntimeCredential -Path $wrongAuthFile -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract -Paths $leasedPaths
                    if($null -eq $credentialRootFailureCode -and $null -ne $credentialResult.RootFailureCode){$credentialRootFailureCode=[string]$credentialResult.RootFailureCode}
                    $credentialRemoveFailed=$credentialRemoveFailed -or -not [bool]$credentialResult.RemoveSucceeded
                    $cycleCredentialAbsenceVerified=$previousCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                    $credentialAbsenceVerified=$previousOverallCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                    if($null -ne $credentialResult.FailureCode){
                        $credentialCleanupFatal=$true
                        $credentialCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $wrongOperationFailure -RootFailureCode $credentialResult.RootFailureCode -CleanupCode $credentialResult.FailureCode
                        if($null -eq $wrongOperationFailure){throw $credentialCode}
                    }
                }
                catch {
                    $credentialCleanupFatal = $true
                    $credentialAbsenceVerified = $false
                    $cycleCredentialAbsenceVerified = $false
                    $credentialCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
                    if($credentialCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED'){$credentialRemoveFailed=$true}
                    if($null -eq $wrongOperationFailure){throw $credentialCode}
                }}
            }

            # Prove the same server remains usable through correct SCRAM auth;
            # arbitrary client/query/transport failures cannot count as a valid
            # negative-auth result.
            $serverUsableAfterWrong=$false
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT 1' `
                -Expected '1' `
                -FailureCode 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -Contract $leasedContract -Paths $leasedPaths
            $serverUsableAfterWrong=$true
            $wrongOutcome=Resolve-ThriveLensWrongPasswordProbe `
                -ExitCode $wrongExitCode `
                -PrivateStandardOutput $wrongStandardOutput `
                -PrivateStandardError $wrongPrivateError `
                -ExpectedPasswordFile $wrongAuthFile `
                -ServerUsableAfterProbe $serverUsableAfterWrong
            if($wrongOutcome.Status -cne 'AUTHENTICATION_REJECTED'){throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'}
            $cycleEvidence.WrongPasswordRejected = $true
            $wrongAuthFile=$null
            $wrongOutcome=$null;$wrongStandardOutput=$null;$wrongPrivateError=$null
        }
        catch{$correctOperationFailure=[string]$_.Exception.Message;throw}
        finally {
            $bootstrapSecret = $null
            $correctCreate = $null
            $wrongAuthFile = $null
            $wrongStandardOutput = $null
            $wrongPrivateError = $null
            if($null -ne $correctOperationFailure -and -not (Test-ThriveLensCredentialCleanupAllowedAfterFailure -FailureCode $correctOperationFailure)){
                $credentialCleanupFatal=$true
                $credentialAbsenceVerified=$false
                $cycleCredentialAbsenceVerified=$false
            }
            else{try {
                $null=Assert-ThriveLensConfigurationLease -Lease $configurationLease
                $currentLeaseIntegrityVerified=$true
                $previousCredentialAbsence=$cycleCredentialAbsenceVerified
                $previousOverallCredentialAbsence=$credentialAbsenceVerified
                $credentialAbsenceVerified=$false
                $cycleCredentialAbsenceVerified=$false
                $credentialResult=Remove-ThriveLensRuntimeCredential -Path $correctAuthFile -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract -Paths $leasedPaths
                if($null -eq $credentialRootFailureCode -and $null -ne $credentialResult.RootFailureCode){$credentialRootFailureCode=[string]$credentialResult.RootFailureCode}
                $credentialRemoveFailed=$credentialRemoveFailed -or -not [bool]$credentialResult.RemoveSucceeded
                $cycleCredentialAbsenceVerified=$previousCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                $credentialAbsenceVerified=$previousOverallCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                if($null -ne $credentialResult.FailureCode){
                    $credentialCleanupFatal=$true
                    $credentialCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $correctOperationFailure -RootFailureCode $credentialResult.RootFailureCode -CleanupCode $credentialResult.FailureCode
                    if($null -eq $correctOperationFailure){throw $credentialCode}
                }
            }
            catch {
                $credentialCleanupFatal = $true
                $credentialAbsenceVerified = $false
                $cycleCredentialAbsenceVerified = $false
                $credentialCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
                if($credentialCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED'){$credentialRemoveFailed=$true}
                if($null -eq $correctOperationFailure){throw $credentialCode}
            }}
            $correctAuthFile = $null
        }

        # A negative authentication result is accepted only while the same
        # loopback-only server remains reachable.
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
        Assert-ThriveLensWslLoopback -Paths $leasedPaths -Contract $leasedContract -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensHostLoopback -Paths $leasedPaths -Contract $leasedContract
        $cycleEvidence.HostLoopbackReachable = $true
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
        # Preserve identity continuity through successful cleanup too. WSL has
        # no supported GUID-targeted terminate command, so releasing the mutex
        # and minting a new token here would widen the accepted name race.
        $null=Assert-ThriveLensConfigurationLease -Lease $configurationLease
        $currentLeaseIntegrityVerified=$true
        $wasRunning=Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract -Paths $leasedPaths
        if(-not $wasRunning){throw 'RUNTIME_POSTGRES_NOT_RUNNING_AT_STOP'}
        $cycleEvidence.PostgresStopVerified = $true
        $null=Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
        Assert-ThriveLensDistroStopped -Contract $leasedContract
        $distroAbsenceVerified = $true
        $cycleEvidence.DistroAbsenceVerified = $true
        Assert-ThriveLensHostPortAbsent -Paths $leasedPaths -Contract $leasedContract
        $hostAbsenceVerified = $true
        $cycleEvidence.HostAbsenceVerified = $true
        # Final cycle accounting follows complete PostgreSQL/distro/host
        # containment and still runs under the original lease and mutex.
        $null=Invoke-ThriveLensResourceGate -Manifest $manifest
        $finalResourceGateVerified = $true
        $cycleEvidence.PostMutationResourceGateVerified = $true
        $started = $false
        $attempted = $false
        $wslTouched = $false
        $cycleEvidence.CredentialAbsenceVerified =
            $cycleCredentialCleanupRequired -and $cycleCredentialAbsenceVerified
        $cycleComplete = $true
        foreach ($proofName in @($cycleEvidence.Keys)) {
            if (-not [bool]$cycleEvidence[$proofName]) {
                $cycleComplete = $false
                break
            }
        }
        if (-not $cycleComplete) {
            throw 'RUNTIME_TEST_INTERNAL_ERROR'
        }
        foreach ($proofName in @($proofCounts.Keys)) {
            $proofCounts[$proofName] = [int]$proofCounts[$proofName] + 1
        }
        $completedCycles++

        if ($cycle -eq 1) {
            # Capture the stricter leased policy value before disposing the
            # configuration authority. The following wait receives only this
            # validated scalar and cannot re-read configuration.
            $interCycleMemoryTargetBytes = Get-ThriveLensInterCycleMemoryTargetBytes `
                -Manifest $manifest
        }

        $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
        $currentLeaseIntegrityVerified = $true
        try {
            # The exact credential/distro/host absence proofs above are
            # terminal for this cycle.  Dispose the original configuration
            # lease while the original mutex/token are still held.
            $currentLeaseReleaseAttempted = $true
            $leaseReleaseAttempts++
            Exit-ThriveLensConfigurationLease -Lease $configurationLease
            $currentLeaseReleased = $true
            $leaseReleaseSuccesses++
            $configurationLease = $null
        }
        catch {
            $leaseReleaseFailed = $true
            throw 'CONFIGURATION_LEASE_RELEASE_FAILED'
        }
        try {
            $currentLockReleaseAttempted = $true
            $lockReleaseAttempts++
            Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock
            $currentLockReleased = $true
            $lockReleaseSuccesses++
            $probeLifecycleLock = $null
            $probeIdentityToken = $null
            $sameTokenEstablished = $false
        }
        catch {
            $lockReleaseFailed = $true
            throw 'RUNTIME_LOCK_RELEASE_FAILED'
        }

        # Successful disposal ends every configuration and WSL observation
        # authority for this cycle. In particular, an inter-cycle wait failure
        # reaches catch with no contract or paths that could authorize a probe.
        $leasedContract = $null
        $leasedPaths = $null
        $manifest = $null

        if ($cycle -eq 1) {
            Wait-ThriveLensInterCycleMemorySettle `
                -MinimumFreeMemoryBytes $interCycleMemoryTargetBytes
            continue
        }
    }

    if ($completedCycles -ne 2 -or -not $sameClusterIdentityVerified -or
        $proofCounts.ScramAuthenticated -ne 2 -or
        $proofCounts.PasswordEncryptionVerified -ne 2 -or
        $proofCounts.HbaScramVerified -ne 2 -or
        $proofCounts.ScramVerifierVerified -ne 2 -or
        $proofCounts.WrongPasswordRejected -ne 2 -or
        $proofCounts.HostLoopbackReachable -ne 2 -or
        $proofCounts.CredentialAbsenceVerified -ne 2 -or
        $proofCounts.PostgresStopVerified -ne 2 -or
        $proofCounts.DistroAbsenceVerified -ne 2 -or
        $proofCounts.HostAbsenceVerified -ne 2 -or
        $proofCounts.ClusterIdentityProbed -ne 2 -or
        $proofCounts.PostMutationResourceGateVerified -ne 2) {
        throw 'RUNTIME_TEST_INTERNAL_ERROR'
    }

    [pscustomobject]@{
        schema_version = 1
        status='PASS'
        real_postgresql = ($completedCycles -eq 2)
        cycles = $completedCycles
        scram_authenticated = ($proofCounts.ScramAuthenticated -eq 2)
        password_encryption = if ($proofCounts.PasswordEncryptionVerified -eq 2) { 'scram-sha-256' } else { $null }
        hba_scram_verified = ($proofCounts.HbaScramVerified -eq 2)
        scram_verifier_verified = ($proofCounts.ScramVerifierVerified -eq 2)
        wrong_password_rejected = ($proofCounts.WrongPasswordRejected -eq 2)
        host_loopback_reachable = ($proofCounts.HostLoopbackReachable -eq 2)
        credential_absence_verified = ($proofCounts.CredentialAbsenceVerified -eq 2)
        stopped_before_pass = ($proofCounts.PostgresStopVerified -eq 2)
        distro_absence_verified = ($proofCounts.DistroAbsenceVerified -eq 2)
        host_absence_verified = ($proofCounts.HostAbsenceVerified -eq 2)
        same_cluster_identity_verified = $sameClusterIdentityVerified -and ($proofCounts.ClusterIdentityProbed -eq 2)
        post_mutation_resource_gate_verified = ($proofCounts.PostMutationResourceGateVerified -eq 2)
    } | ConvertTo-Json -Compress
}
catch {
    if (-not $modulesReady) {
        # Module bootstrap has no trustworthy policy/classifier surface. Emit a
        # fixed closed response without touching raw exception text or calling
        # any function that may have failed to import.
        [pscustomobject]@{
            schema_version = 2
            status = 'ERROR'
            code = 'RUNTIME_TEST_INTERNAL_ERROR'
            original_code = 'RUNTIME_TEST_INTERNAL_ERROR'
            failure_stages = @('BOOTSTRAP')
            cleanup_required = $false
            cleanup_verified = $false
            guest_cleanup_allowed = $false
            guest_cleanup_attempted = $false
            forced_termination_attempted = $false
            post_mutation_resource_gate_verified = $false
            credential_cleanup_required = $false
            credential_absence_verified = $false
            distro_absence_verified = $false
            host_absence_verified = $false
            configuration_lease_integrity_verified = $false
            configuration_lease_release_attempted = $false
            configuration_lease_released = $false
            configuration_lease_release_attempts = 0
            configuration_lease_release_successes = 0
            lifecycle_lock_release_attempted = $false
            lifecycle_lock_released = $false
            lifecycle_lock_release_attempts = 0
            lifecycle_lock_release_successes = 0
        } | ConvertTo-Json -Compress
        exit 3
    }
    $rawFailureCode=[string]$_.Exception.Message
    $originalCode=Resolve-ThriveLensRuntimePublicCode -Code $rawFailureCode
    $coreAttemptFailed = $attempted -and -not $started
    $fatalOriginalCodes=@(
        'RUNTIME_TEST_INTERNAL_ERROR','AUTH_FILE_CLEANUP_REMOVE_FAILED',
        'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED','WSL_GUARDED_COMMAND_CONTAINMENT_FAILED',
        'WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_TIMEOUT','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED',
        'RUNTIME_LOCK_RELEASE_FAILED','CONFIGURATION_LEASE_RELEASE_FAILED',
        'POST_MUTATION_RESOURCE_GATE_FAILED','POSTGRES_START_INTERNAL_ERROR'
    )
    $fatalRawFailure=$rawFailureCode -cmatch '^CONFIGURATION_LEASE_' -or
        $rawFailureCode -cmatch '^LIFECYCLE_LOCK_' -or
        $rawFailureCode -cmatch 'IDENTITY' -or
        $rawFailureCode -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED' -or
        $rawFailureCode -ceq 'POSTGRES_START_INTERNAL_ERROR'
    $originalExitCode=if($failureExitCode -eq 3 -or $credentialCleanupFatal -or
        $coreAttemptFailed -or $fatalRawFailure -or
        $fatalOriginalCodes -ccontains $originalCode){3}else{2}
    $cleanupRequired = $started -or $attempted -or $wslTouched
    if($attempted){$finalResourceGateVerified=$false}
    $resourceGateOutputDrainIncomplete=
        $rawFailureCode -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' -or
        $originalCode -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
    if($resourceGateOutputDrainIncomplete){
        # Unknown output-drain/process state forbids another guest command or
        # resource runner. Exact-distro containment remains mandatory below.
        $finalResourceGateFailed=$true
    }
    $cleanupIdentityChanged=$false
    $postgresStopFailed=$false;$distroTerminateFailed=$false
    $distroAbsenceCheckFailed=$false;$hostAbsenceCheckFailed=$false
    $guestCleanupAllowed=$false;$guestCleanupAttempted=$false
    $forcedTerminationAttempted=$false
    $cleanupLeaseVerified=$false
    $cleanupIdentityVerified=$false

    if($null -ne $configurationLease -and -not $currentLeaseReleaseAttempted){
        try {
            $null=Assert-ThriveLensConfigurationLease -Lease $configurationLease
            $currentLeaseIntegrityVerified=$true
            $cleanupLeaseVerified=$true
        }
        catch {
            $leaseIntegrityFailed=$true
            $leaseIntegrityFailureCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
        }
    }

    # All cleanup uses only the current cycle's original mutex, lease and exact
    # identity token.  No child script, second lock acquisition, or new token
    # can target a same-name replacement.
    if($cleanupRequired){
        $cleanupAuthorityVerified=$false
        if(-not $sameTokenEstablished -or $null -eq $probeLifecycleLock -or
            $null -eq $probeIdentityToken -or $null -eq $leasedContract -or
            $null -eq $leasedPaths){
            $cleanupIdentityChanged=$true
        }
        else {
            # Lease and identity gates are independent.  A failed lease cannot
            # suppress exact same-token distro containment, and a valid lease
            # cannot authorize guest cleanup after a forbidden failure class.
            try{
                $guestCleanupAllowed=Test-ThriveLensCredentialCleanupAllowedAfterFailure -FailureCode $rawFailureCode
            }
            catch{$guestCleanupAllowed=$false}
            try{
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
                $cleanupIdentityVerified=$true
            }
            catch {
                $cleanupIdentityChanged=$true
            }

            if(-not $resourceGateOutputDrainIncomplete -and
                $cleanupLeaseVerified -and $cleanupIdentityVerified -and
                $guestCleanupAllowed -and $attempted){
                # Guest pg_ctl cleanup requires a successful assertion of the
                # original lease plus the original-failure policy decision.
                try{
                    $guestCleanupAttempted=$true
                    $null=Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract -Paths $leasedPaths
                }
                catch{
                    $postgresStopFailed=$true
                }
            }

            # Forced exact-distro containment is independent of lease validity
            # and guest-cleanup policy, but revalidates the original token under
            # the original mutex immediately before termination.
            $forcedTerminationAuthorized=$false
            try{
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
                $forcedTerminationAuthorized=$true
                $cleanupAuthorityVerified=$true
            }
            catch{
                $cleanupIdentityChanged=$true
                $cleanupAuthorityVerified=$false
            }
            if($forcedTerminationAuthorized){
                try{
                    $forcedTerminationAttempted=$true
                    $null=Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -Contract $leasedContract
                }
                catch{
                    $cleanupFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode ([string]$_.Exception.Message)
                    switch([string]$cleanupFailure.Stage){
                        'DISTRO_TERMINATE' {$distroTerminateFailed=$true}
                        'DISTRO_ABSENCE' {$distroAbsenceCheckFailed=$true}
                        'HOST_ABSENCE' {$hostAbsenceCheckFailed=$true}
                    }
                    if(-not $cleanupFailure.IdentityAuthorityPreserved){
                        $cleanupIdentityChanged=$true
                        $cleanupAuthorityVerified=$false
                    }
                }
            }
            if($forcedTerminationAuthorized -and -not $cleanupIdentityChanged){
                try{Assert-ThriveLensDistroStopped -Contract $leasedContract;$distroAbsenceVerified=$true}catch{$distroAbsenceVerified=$false;$distroAbsenceCheckFailed=$true}
                try{Assert-ThriveLensHostPortAbsent -Paths $leasedPaths -Contract $leasedContract;$hostAbsenceVerified=$true}catch{$hostAbsenceVerified=$false;$hostAbsenceCheckFailed=$true}
            }
            if($distroAbsenceVerified -and $hostAbsenceVerified){$started=$false}
        }
    }

    if(-not $cleanupRequired -and $null -ne $leasedContract -and $null -ne $leasedPaths){
        try{Assert-ThriveLensDistroStopped -Contract $leasedContract;$distroAbsenceVerified=$true}catch{$distroAbsenceVerified=$false}
        try{Assert-ThriveLensHostPortAbsent -Paths $leasedPaths -Contract $leasedContract;$hostAbsenceVerified=$true}catch{$hostAbsenceVerified=$false}
    }

    # Cleanup and final absence observations cannot be skipped by an accounting
    # failure. Re-run the post-mutation gate only after containment, through the
    # still-valid original lease, and before reverse disposal.
    if($attempted -and -not $resourceGateOutputDrainIncomplete){
        if($cleanupLeaseVerified -and $null -ne $leasedContract){
            try{
                $null=Invoke-ThriveLensResourceGate -Manifest $leasedContract.Manifest
                $finalResourceGateVerified=$true
            }
            catch{$finalResourceGateFailed=$true}
        }
        else{$finalResourceGateFailed=$true}
    }

    # Always attempt lease disposal separately from assertion, even when lease
    # integrity failed.  Dispose before releasing the original lifecycle mutex,
    # and never retry a terminal transition already attempted by the success
    # tail.
    if($null -ne $configurationLease -and -not $currentLeaseReleaseAttempted){
        $currentLeaseReleaseAttempted=$true
        $leaseReleaseAttempts++
        try{
            Exit-ThriveLensConfigurationLease -Lease $configurationLease
            $currentLeaseReleased=$true
            $leaseReleaseSuccesses++
        }
        catch{$leaseReleaseFailed=$true}
    }
    $configurationLease=$null
    if($null -ne $probeLifecycleLock -and -not $currentLockReleaseAttempted){
        $currentLockReleaseAttempted=$true
        $lockReleaseAttempts++
        try{
            Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock
            $currentLockReleased=$true
            $lockReleaseSuccesses++
        }
        catch{$lockReleaseFailed=$true}
    }
    $probeLifecycleLock=$null
    $probeIdentityToken=$null
    $sameTokenEstablished=$false

    $bootstrapSecret = $null
    $wrongSecret = $null
    $outcome=Resolve-ThriveLensRuntimeCleanupOutcome `
        -OriginalCode $originalCode -OriginalExitCode $originalExitCode `
        -CleanupRequired $cleanupRequired `
        -CleanupAuthorityVerified $cleanupAuthorityVerified `
        -CredentialCleanupRequired $credentialCleanupRequired `
        -CredentialRemoveFailed $credentialRemoveFailed `
        -CredentialRootFailureCode $credentialRootFailureCode `
        -CredentialAbsenceVerified $credentialAbsenceVerified `
        -IdentityChanged $cleanupIdentityChanged `
        -PostgresStopFailed $postgresStopFailed `
        -DistroTerminateFailed $distroTerminateFailed `
        -DistroAbsenceCheckFailed $distroAbsenceCheckFailed `
        -HostAbsenceCheckFailed $hostAbsenceCheckFailed `
        -DistroAbsent $distroAbsenceVerified -HostAbsent $hostAbsenceVerified `
        -LockReleaseFailed $lockReleaseFailed
    $failureStages=[Collections.Generic.List[string]]::new()
    foreach($stage in @($outcome.FailureStages)){
        if(-not $failureStages.Contains([string]$stage)){$failureStages.Add([string]$stage)}
    }
    if($leaseIntegrityFailed -and -not $failureStages.Contains('CONFIGURATION_LEASE_INTEGRITY')){
        $failureStages.Add('CONFIGURATION_LEASE_INTEGRITY')
    }
    if($leaseReleaseFailed -and -not $failureStages.Contains('CONFIGURATION_LEASE_RELEASE')){
        $failureStages.Add('CONFIGURATION_LEASE_RELEASE')
    }
    if($finalResourceGateFailed -and -not $failureStages.Contains('RESOURCE_GATE')){
        $failureStages.Add('RESOURCE_GATE')
    }
    $finalStatus=[string]$outcome.Status
    $finalCode=[string]$outcome.Code
    $finalExitCode=[int]$outcome.ExitCode
    if($resourceGateOutputDrainIncomplete){
        $finalStatus='ERROR'
        $finalCode=if($attempted){'POST_MUTATION_RESOURCE_GATE_FAILED'}else{'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'}
        $finalExitCode=3
    }
    elseif($finalResourceGateFailed){
        $finalStatus='ERROR'
        $finalCode='POST_MUTATION_RESOURCE_GATE_FAILED'
        $finalExitCode=3
    }
    elseif($leaseReleaseFailed -and -not $lockReleaseFailed){
        $finalStatus='ERROR'
        $finalCode='CONFIGURATION_LEASE_RELEASE_FAILED'
        $finalExitCode=3
    }
    elseif($leaseIntegrityFailed -and $finalStatus -cne 'ERROR'){
        $finalStatus='ERROR'
        $finalCode=if([string]::IsNullOrWhiteSpace($leaseIntegrityFailureCode)){'CONFIGURATION_LEASE_INVALID'}else{$leaseIntegrityFailureCode}
        $finalExitCode=3
    }
    [pscustomobject]@{
        schema_version = 2
        status = $finalStatus
        code = $finalCode
        original_code = $originalCode
        failure_stages = @($failureStages)
        cleanup_required = $cleanupRequired
        cleanup_verified = [bool]$outcome.CleanupVerified -and -not $resourceGateOutputDrainIncomplete
        guest_cleanup_allowed = $guestCleanupAllowed
        guest_cleanup_attempted = $guestCleanupAttempted
        forced_termination_attempted = $forcedTerminationAttempted
        post_mutation_resource_gate_verified = $finalResourceGateVerified -and -not $finalResourceGateFailed
        credential_cleanup_required = $credentialCleanupRequired
        credential_absence_verified = $credentialAbsenceVerified
        distro_absence_verified = $distroAbsenceVerified
        host_absence_verified = $hostAbsenceVerified
        configuration_lease_integrity_verified = $currentLeaseIntegrityVerified -and -not $leaseIntegrityFailed
        configuration_lease_release_attempted = $currentLeaseReleaseAttempted
        configuration_lease_released = $currentLeaseReleased
        configuration_lease_release_attempts = $leaseReleaseAttempts
        configuration_lease_release_successes = $leaseReleaseSuccesses
        lifecycle_lock_release_attempted = $currentLockReleaseAttempted
        lifecycle_lock_released = $currentLockReleased
        lifecycle_lock_release_attempts = $lockReleaseAttempts
        lifecycle_lock_release_successes = $lockReleaseSuccesses
    } | ConvertTo-Json -Compress
    exit $finalExitCode
}
finally {
    # Clear every variable that may have held credential material on all exits.
    $bootstrapSecret = $null
    $wrongSecret = $null
    $correctAuthFile = $null
    $wrongAuthFile = $null
    $clusterIdentityFingerprint = $null
    $cycleClusterIdentityFingerprint = $null
    # The catch path owns classified reverse-order release.  Do not silently
    # retry an uncertain lifecycle mutex or configuration lease here.
    $probeIdentityToken=$null
    $sameTokenEstablished=$false
}
