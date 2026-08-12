#Requires -Version 7.0

[CmdletBinding()]
param([string]$PasswordFile)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-ThriveLensRuntimeCredential {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock
    )

    if ($Path -cnotmatch '^/run/thrivelens-r0-(?:auth|wrong)-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $removeResult=$null;$absenceResult=$null;$rootFailureCode=$null
    $removeSucceeded=$false;$absenceVerified=$false;$allowAbsenceProbe=$true
    try {
        try {
            $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
            $removeResult = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/rm', '-f', '--', $Path)
            $removeSucceeded = $removeResult.ExitCode -eq 0
        }
        catch {
            $removeRawCode=[string]$_.Exception.Message
            $rootFailureCode=Resolve-ThriveLensRuntimePublicCode -Code $removeRawCode
            # Only bounded supervisor failures whose guarded wrapper already
            # re-established same-token containment may be followed by a fresh
            # read-only absence probe. Identity/lock/unknown failures authorize
            # no further guest command.
            $allowAbsenceProbe=Test-ThriveLensCredentialAbsenceProbeAllowed -FailureCode $removeRawCode
        }

        if($allowAbsenceProbe){
            try {
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
                $absenceResult = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test', '!', '-e', $Path)
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
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock
    )

    if ($AuthFile -cnotmatch '^/run/thrivelens-r0-auth-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $probe = $null
    try {
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $probe = Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @(
            '/usr/sbin/runuser', '-u', 'postgres', '--',
            '/usr/bin/env', '-i', "PGPASSFILE=$AuthFile", 'PGCONNECT_TIMEOUT=5', 'PGREQUIREAUTH=scram-sha-256',
            '/usr/bin/psql', '-X', '-w', '-h', '127.0.0.1', '-p', '55432',
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
$probeIdentityToken = $null
$probeIdentityEverEstablished = $false
$cleanupAuthorityVerified = $true
$distroAbsenceVerified = $false
$hostAbsenceVerified = $false

try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force

    $preflightOutput = @(
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Runtime 2>&1
    )
    $preflightExitCode = $LASTEXITCODE
    if ($preflightExitCode -ne 0) {
        $preflightOutput | Write-Output
        $preflightOutput = $null
        exit $preflightExitCode
    }
    $preflightOutput = $null
    # READY preflight is required to stop the exact distro; independently
    # prove that contract before any start attempt.
    Assert-ThriveLensDistroStopped
    $distroAbsenceVerified = $true
    Assert-ThriveLensHostPortAbsent
    $hostAbsenceVerified = $true

    $manifest = Get-ThriveLensManifest
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

    foreach ($cycle in 1..2) {
        # A nonzero start child may still have started PostgreSQL. Mark the
        # attempt before invocation so every outcome enters independent cleanup.
        $distroAbsenceVerified = $false
        $hostAbsenceVerified = $false
        $probeIdentityEverEstablished = $false
        $cleanupAuthorityVerified = $true
        $startExitCode = 3
        $started=$true;$start=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'start.ps1') 2>&1)
        $startExitCode = $LASTEXITCODE
        $start = $null
        $startOutcome=Resolve-ThriveLensStartChildExit -ExitCode $startExitCode
        if ($startOutcome.ExitCode -ne 0) {
            $failureExitCode=[int]$startOutcome.ExitCode
            if($startOutcome.Fatal){throw [string]$startOutcome.Code}
            # Exit 2 carries no mutation authority. The catch path performs
            # host-only absence observations and never launches a cleanup child.
            throw 'RUNTIME_START_PROBE_FAILED'
        }

        # The start child releases its mutex before returning. The parent now
        # takes ownership and captures a fresh host-only identity token before
        # its first name-addressed distro command. Hold this fence through every
        # probe, transient credential deletion, and same-token shutdown.
        $probeLifecycleLock=Enter-ThriveLensLifecycleLock
        $probeIdentityToken=Get-ThriveLensWslCleanupIdentityToken -LifecycleLock $probeLifecycleLock
        $probeIdentityEverEstablished=$true
        $null=Assert-ThriveLensWslIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensClusterScramConfig
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensWslLoopback
        Assert-ThriveLensHostLoopback

        # The hardened reader validates the exact configured path, ACLs,
        # identity, encoding and Base64Url value on every cycle.
        $correctAuthFile = '/run/thrivelens-r0-auth-' + [guid]::NewGuid().ToString('N') + '.pgpass'
        $correctCreate = $null
        $correctOperationFailure=$null
        try {
            $bootstrapSecret = Read-ThriveLensPostgresBootstrapSecret -Path $actual
            $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
            $credentialCleanupRequired=$true
            $correctCreate = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                -StandardInput ("127.0.0.1:55432:postgres:tl_bootstrap:$bootstrapSecret`n") `
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
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SHOW password_encryption' `
                -Expected 'scram-sha-256' `
                -FailureCode 'PASSWORD_ENCRYPTION_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) > 0) AND bool_and(error IS NULL) AND bool_and(auth_method = ''scram-sha-256''), false) FROM pg_hba_file_rules' `
                -Expected 't' `
                -FailureCode 'HBA_SCRAM_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) = 1) AND bool_and(rolpassword LIKE ''SCRAM-SHA-256$%''), false) FROM pg_authid WHERE rolname = ''tl_bootstrap''' `
                -Expected 't' `
                -FailureCode 'SCRAM_VERIFIER_PROBE_FAILED' `
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
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
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
                $credentialCleanupRequired=$true
                $wrongCreate = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock `
                    -StandardInput ("127.0.0.1:55432:postgres:tl_bootstrap:$wrongSecret`n") `
                    -Arguments @(
                        '/usr/bin/install', '-o', 'postgres', '-g', 'postgres', '-m', '0600',
                        '/dev/stdin', $wrongAuthFile
                    )
                $wrongSecret = $null
                if ($wrongCreate.ExitCode -ne 0) { throw 'WRONG_AUTH_FILE_CREATE_FAILED' }
                $wrongCreate = $null

                # stderr stays in the shared 128 KiB in-memory budget and is
                # consumed only by the exact locale-fixed classifier below.
                $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
                $wrongProbe = Invoke-ThriveLensGuardedDistro -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock -CapturePrivateStandardError -Arguments @(
                    '/usr/sbin/runuser', '-u', 'postgres', '--',
                    '/usr/bin/env', '-i', 'LC_ALL=C', 'LANG=C', "PGPASSFILE=$wrongAuthFile", 'PGCONNECT_TIMEOUT=5', 'PGREQUIREAUTH=scram-sha-256',
                    '/usr/bin/psql', '-X', '-w', '-h', '127.0.0.1', '-p', '55432',
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
                    $credentialCleanupFatal=$true;$credentialAbsenceVerified=$false
                }
                else{try {
                    $previousCredentialAbsence=$credentialAbsenceVerified
                    $credentialAbsenceVerified=$false
                    $credentialResult=Remove-ThriveLensRuntimeCredential -Path $wrongAuthFile -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
                    if($null -eq $credentialRootFailureCode -and $null -ne $credentialResult.RootFailureCode){$credentialRootFailureCode=[string]$credentialResult.RootFailureCode}
                    $credentialRemoveFailed=$credentialRemoveFailed -or -not [bool]$credentialResult.RemoveSucceeded
                    $credentialAbsenceVerified=$previousCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                    if($null -ne $credentialResult.FailureCode){
                        $credentialCleanupFatal=$true
                        $credentialCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $wrongOperationFailure -RootFailureCode $credentialResult.RootFailureCode -CleanupCode $credentialResult.FailureCode
                        if($null -eq $wrongOperationFailure){throw $credentialCode}
                    }
                }
                catch {
                    $credentialCleanupFatal = $true
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
                -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
            $serverUsableAfterWrong=$true
            $wrongOutcome=Resolve-ThriveLensWrongPasswordProbe `
                -ExitCode $wrongExitCode `
                -PrivateStandardOutput $wrongStandardOutput `
                -PrivateStandardError $wrongPrivateError `
                -ExpectedPasswordFile $wrongAuthFile `
                -ServerUsableAfterProbe $serverUsableAfterWrong
            if($wrongOutcome.Status -cne 'AUTHENTICATION_REJECTED'){throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'}
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
                $credentialCleanupFatal=$true;$credentialAbsenceVerified=$false
            }
            else{try {
                $previousCredentialAbsence=$credentialAbsenceVerified
                $credentialAbsenceVerified=$false
                $credentialResult=Remove-ThriveLensRuntimeCredential -Path $correctAuthFile -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
                if($null -eq $credentialRootFailureCode -and $null -ne $credentialResult.RootFailureCode){$credentialRootFailureCode=[string]$credentialResult.RootFailureCode}
                $credentialRemoveFailed=$credentialRemoveFailed -or -not [bool]$credentialResult.RemoveSucceeded
                $credentialAbsenceVerified=$previousCredentialAbsence -and [bool]$credentialResult.CredentialAbsenceVerified
                if($null -ne $credentialResult.FailureCode){
                    $credentialCleanupFatal=$true
                    $credentialCode=Resolve-ThriveLensCredentialFailureCode -PrimaryOperationCode $correctOperationFailure -RootFailureCode $credentialResult.RootFailureCode -CleanupCode $credentialResult.FailureCode
                    if($null -eq $correctOperationFailure){throw $credentialCode}
                }
            }
            catch {
                $credentialCleanupFatal = $true
                $credentialCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
                if($credentialCode -ceq 'AUTH_FILE_CLEANUP_REMOVE_FAILED'){$credentialRemoveFailed=$true}
                if($null -eq $correctOperationFailure){throw $credentialCode}
            }}
            $correctAuthFile = $null
        }

        # A negative authentication result is accepted only while the same
        # loopback-only server remains reachable.
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensWslLoopback
        Assert-ThriveLensHostLoopback
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        # Preserve identity continuity through successful cleanup too. WSL has
        # no supported GUID-targeted terminate command, so releasing the mutex
        # and minting a new token here would widen the accepted name race.
        $wasRunning=Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        if(-not $wasRunning){throw 'RUNTIME_POSTGRES_NOT_RUNNING_AT_STOP'}
        $null=Invoke-ThriveLensResourceGate
        Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock
        Assert-ThriveLensDistroStopped
        $distroAbsenceVerified = $true
        Assert-ThriveLensHostPortAbsent
        $hostAbsenceVerified = $true
        $started = $false
        Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock
        $probeLifecycleLock=$null;$probeIdentityToken=$null
    }

    [pscustomobject]@{
        schema_version = 1
        status='PASS'
        real_postgresql = $true
        cycles = 2
        scram_authenticated = $true
        password_encryption = 'scram-sha-256'
        hba_scram_verified = $true
        scram_verifier_verified = $true
        wrong_password_rejected = $true
        host_loopback_reachable = $true
        stopped_before_pass = $true
        distro_absence_verified = $distroAbsenceVerified
        host_absence_verified = $hostAbsenceVerified
    } | ConvertTo-Json -Compress
}
catch {
    $originalCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
    $fatalOriginalCodes=@(
        'RUNTIME_TEST_INTERNAL_ERROR','RUNTIME_START_CHILD_FATAL','RUNTIME_START_CHILD_UNEXPECTED_EXIT',
        'RUNTIME_START_ABSENCE_UNVERIFIED','AUTH_FILE_CLEANUP_REMOVE_FAILED',
        'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED','WSL_GUARDED_COMMAND_CONTAINMENT_FAILED',
        'WSL_CLEANUP_IDENTITY_CHANGED','LIFECYCLE_LOCK_TIMEOUT','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED'
    )
    $originalExitCode=if($failureExitCode -eq 3 -or $credentialCleanupFatal -or $fatalOriginalCodes -ccontains $originalCode){3}else{2}
    $cleanupRequired = $started
    $cleanupIdentityChanged=$false
    $postgresStopFailed=$false;$distroTerminateFailed=$false
    $distroAbsenceCheckFailed=$false;$hostAbsenceCheckFailed=$false;$lockReleaseFailed=$false

    # Once a cycle has captured an identity token, cleanup stays under that
    # same mutex/token authority. Never release it and mint fresh authority for
    # a same-name replacement. Graceful and forced cleanup remain independent.
    if($started -and $probeIdentityEverEstablished){
        if($null -eq $probeLifecycleLock -or $null -eq $probeIdentityToken){
            $cleanupIdentityChanged=$true
        }
        else{
            try{$null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock}
            catch{$cleanupIdentityChanged=$true}
            if(-not $cleanupIdentityChanged -and -not $credentialCleanupFatal -and $originalCode -cne 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED'){
                try{$null=Stop-ThriveLensPostgresUnderLock -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock}
                catch{
                    $postgresStopFailed=$true
                    if(-not (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage 'POSTGRES_STOP' -FailureCode ([string]$_.Exception.Message))){$cleanupIdentityChanged=$true}
                }
                if(-not $cleanupIdentityChanged){
                    try{Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock}
                    catch{
                        $cleanupFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode ([string]$_.Exception.Message)
                        switch([string]$cleanupFailure.Stage){
                            'DISTRO_TERMINATE' {$distroTerminateFailed=$true}
                            'DISTRO_ABSENCE' {$distroAbsenceCheckFailed=$true}
                            'HOST_ABSENCE' {$hostAbsenceCheckFailed=$true}
                        }
                        if(-not $cleanupFailure.IdentityAuthorityPreserved){$cleanupIdentityChanged=$true}
                    }
                }
            }
            elseif(-not $cleanupIdentityChanged){
                # Credential uncertainty or guest-command containment failure
                # authorizes only exact token-gated distro termination. Do not
                # issue pg_ctl or any additional guest command first.
                try{Stop-ThriveLensDistroAndVerify -IdentityToken $probeIdentityToken -LifecycleLock $probeLifecycleLock}
                catch{
                    $cleanupFailure=Resolve-ThriveLensDistroCleanupFailure -FailureCode ([string]$_.Exception.Message)
                    switch([string]$cleanupFailure.Stage){
                        'DISTRO_TERMINATE' {$distroTerminateFailed=$true}
                        'DISTRO_ABSENCE' {$distroAbsenceCheckFailed=$true}
                        'HOST_ABSENCE' {$hostAbsenceCheckFailed=$true}
                    }
                    if(-not $cleanupFailure.IdentityAuthorityPreserved){$cleanupIdentityChanged=$true}
                }
            }
            if(-not $cleanupIdentityChanged){
                try{Assert-ThriveLensDistroStopped;$distroAbsenceVerified=$true}catch{$distroAbsenceVerified=$false}
                try{Assert-ThriveLensHostPortAbsent;$hostAbsenceVerified=$true}catch{$hostAbsenceVerified=$false}
            }
            if($distroAbsenceVerified -and $hostAbsenceVerified){$started=$false}
        }
        try{Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock}catch{$lockReleaseFailed=$true}
        $probeLifecycleLock=$null;$probeIdentityToken=$null
    }
    elseif($null -ne $probeLifecycleLock){
        # A lock without a completed token carries no mutation authority.
        try{Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock}catch{$lockReleaseFailed=$true}
        $probeLifecycleLock=$null;$probeIdentityToken=$null
    }

    if($started -and -not $probeIdentityEverEstablished){
        # A child exit without a parent token conveys no cleanup authority.
        # Observe only the host WSL running list and Windows exposure state;
        # never invoke stop.ps1 or any distribution command from this branch.
        try{Assert-ThriveLensDistroStopped;$distroAbsenceVerified=$true}catch{$distroAbsenceVerified=$false}
        try{Assert-ThriveLensHostPortAbsent;$hostAbsenceVerified=$true}catch{$hostAbsenceVerified=$false}
        $observation=Resolve-ThriveLensPreTokenStartObservation -StartExitCode $startExitCode -DistroAbsent $distroAbsenceVerified -HostPortAbsent $hostAbsenceVerified
        $originalCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$observation.Code)
        $originalExitCode=[int]$observation.ExitCode
        $cleanupAuthorityVerified=[bool]$observation.CleanupVerified
        if($observation.CleanupVerified){$started=$false}
    }

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
    [pscustomobject]@{
        schema_version = 2
        status = [string]$outcome.Status
        code = [string]$outcome.Code
        original_code = [string]$outcome.OriginalCode
        failure_stages = @($outcome.FailureStages)
        cleanup_required = $cleanupRequired
        cleanup_verified = [bool]$outcome.CleanupVerified
        credential_cleanup_required = $credentialCleanupRequired
        credential_absence_verified = $credentialAbsenceVerified
        distro_absence_verified = $distroAbsenceVerified
        host_absence_verified = $hostAbsenceVerified
    } | ConvertTo-Json -Compress
    exit ([int]$outcome.ExitCode)
}
finally {
    # Clear every variable that may have held credential material on all exits.
    $bootstrapSecret = $null
    $wrongSecret = $null
    $correctAuthFile = $null
    $wrongAuthFile = $null
    if($null -ne $probeLifecycleLock){try{Exit-ThriveLensLifecycleLock -Mutex $probeLifecycleLock}catch{};$probeLifecycleLock=$null}
    $probeIdentityToken=$null
}
