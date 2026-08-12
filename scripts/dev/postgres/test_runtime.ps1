#Requires -Version 7.0

[CmdletBinding()]
param([string]$PasswordFile)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Remove-ThriveLensRuntimeCredential {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path -cnotmatch '^/run/thrivelens-r0-(?:auth|wrong)-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $removeResult = $null
    $absenceResult = $null
    $removeSucceeded = $false
    $absenceVerified = $false
    try {
        try {
            $removeResult = Invoke-ThriveLensDistro -Arguments @('/usr/bin/rm', '-f', '--', $Path)
            $removeSucceeded = $removeResult.ExitCode -eq 0
        }
        catch { $removeSucceeded = $false }

        # Absence is measured even when rm fails or its bounded invocation throws.
        try {
            $absenceResult = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test', '!', '-e', $Path)
            $absenceVerified = $absenceResult.ExitCode -eq 0
        }
        catch { $absenceVerified = $false }

        if (-not $removeSucceeded -or -not $absenceVerified) {
            throw 'AUTH_FILE_CLEANUP_FAILED'
        }
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
        [Parameter(Mandatory)][string]$FailureCode
    )

    if ($AuthFile -cnotmatch '^/run/thrivelens-r0-auth-[0-9a-f]{32}\.pgpass$') {
        throw 'AUTH_FILE_PATH_INVALID'
    }

    $probe = $null
    try {
        $probe = Invoke-ThriveLensDistro -Arguments @(
            '/usr/sbin/runuser', '-u', 'postgres', '--',
            '/usr/bin/env', '-i', "PGPASSFILE=$AuthFile", 'PGCONNECT_TIMEOUT=5',
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
$bootstrapSecret = $null
$wrongSecret = $null
$correctAuthFile = $null
$wrongAuthFile = $null
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
        $started=$true;$start=@(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'start.ps1') 2>&1)
        $startExitCode = $LASTEXITCODE
        $start = $null
        if ($startExitCode -ne 0) {
            $failureExitCode = if ($startExitCode -eq 3) { 3 } else { 2 }
            if ($startExitCode -eq 3) { throw 'RUNTIME_START_CHILD_FATAL' }
            throw 'RUNTIME_START_PROBE_FAILED'
        }

        Assert-ThriveLensClusterScramConfig
        Assert-ThriveLensWslLoopback
        Assert-ThriveLensHostLoopback

        # The hardened reader validates the exact configured path, ACLs,
        # identity, encoding and Base64Url value on every cycle.
        $correctAuthFile = '/run/thrivelens-r0-auth-' + [guid]::NewGuid().ToString('N') + '.pgpass'
        $correctCreate = $null
        try {
            $bootstrapSecret = Read-ThriveLensPostgresBootstrapSecret -Path $actual
            $correctCreate = Invoke-ThriveLensDistro `
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
                -FailureCode 'SCRAM_AUTH_PROBE_FAILED'
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SHOW password_encryption' `
                -Expected 'scram-sha-256' `
                -FailureCode 'PASSWORD_ENCRYPTION_PROBE_FAILED'
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) > 0) AND bool_and(error IS NULL) AND bool_and(auth_method = ''scram-sha-256''), false) FROM pg_hba_file_rules' `
                -Expected 't' `
                -FailureCode 'HBA_SCRAM_PROBE_FAILED'
            Assert-ThriveLensAuthenticatedScalar `
                -AuthFile $correctAuthFile `
                -Sql 'SELECT COALESCE((count(*) = 1) AND bool_and(rolpassword LIKE ''SCRAM-SHA-256$%''), false) FROM pg_authid WHERE rolname = ''tl_bootstrap''' `
                -Expected 't' `
                -FailureCode 'SCRAM_VERIFIER_PROBE_FAILED'
        }
        finally {
            $bootstrapSecret = $null
            $correctCreate = $null
            try {
                Remove-ThriveLensRuntimeCredential -Path $correctAuthFile
            }
            catch {
                $credentialCleanupFatal = $true
                throw 'AUTH_FILE_CLEANUP_FAILED'
            }
            finally { $correctAuthFile = $null }
        }

        # This fixed synthetic value is Base64Url and starts with a prefix the
        # hardened reader rejects, so it cannot equal an accepted real secret.
        # The correct bridge has already been deleted and proved absent above.
        $wrongSecret = 'placeholder_R0_wrong_password_probe_0123456789ABCDEF'
        if ($wrongSecret -cnotmatch '^[A-Za-z0-9_-]{43,128}$') {
            throw 'WRONG_PASSWORD_FIXTURE_INVALID'
        }
        $wrongAuthFile = '/run/thrivelens-r0-wrong-' + [guid]::NewGuid().ToString('N') + '.pgpass'
        $wrongCreate = $null
        $wrongProbe = $null
        try {
            $wrongCreate = Invoke-ThriveLensDistro `
                -StandardInput ("127.0.0.1:55432:postgres:tl_bootstrap:$wrongSecret`n") `
                -Arguments @(
                    '/usr/bin/install', '-o', 'postgres', '-g', 'postgres', '-m', '0600',
                    '/dev/stdin', $wrongAuthFile
                )
            $wrongSecret = $null
            if ($wrongCreate.ExitCode -ne 0) { throw 'WRONG_AUTH_FILE_CREATE_FAILED' }
            $wrongCreate = $null

            $wrongProbe = Invoke-ThriveLensDistro -Arguments @(
                '/usr/sbin/runuser', '-u', 'postgres', '--',
                '/usr/bin/env', '-i', "PGPASSFILE=$wrongAuthFile", 'PGCONNECT_TIMEOUT=5',
                '/usr/bin/psql', '-X', '-w', '-h', '127.0.0.1', '-p', '55432',
                '-U', 'tl_bootstrap', '-d', 'postgres', '-Atq',
                '--set=ON_ERROR_STOP=1', '--command', 'SELECT 1'
            )
            if ($wrongProbe.ExitCode -eq 0) { throw 'WRONG_PASSWORD_WAS_ACCEPTED' }
        }
        finally {
            $wrongSecret = $null
            $wrongCreate = $null
            $wrongProbe = $null
            try {
                Remove-ThriveLensRuntimeCredential -Path $wrongAuthFile
            }
            catch {
                $credentialCleanupFatal = $true
                throw 'AUTH_FILE_CLEANUP_FAILED'
            }
            finally { $wrongAuthFile = $null }
        }

        # A negative authentication result is accepted only while the same
        # loopback-only server remains reachable.
        Assert-ThriveLensWslLoopback
        Assert-ThriveLensHostLoopback

        $stopOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
        $stopExitCode = $LASTEXITCODE
        $stopOutput = $null
        if ($stopExitCode -ne 0) {
            $failureExitCode = if ($stopExitCode -eq 3) { 3 } else { 2 }
            if ($stopExitCode -eq 3) { throw 'RUNTIME_STOP_CHILD_FATAL' }
            throw 'RUNTIME_STOP_PROBE_FAILED'
        }

        # Do not trust the child cleanup claim: independently verify the exact
        # dedicated distro and Windows host boundary after every attempt.
        Assert-ThriveLensDistroStopped
        $distroAbsenceVerified = $true
        Assert-ThriveLensHostPortAbsent
        $hostAbsenceVerified = $true
        $started = $false
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
    $rawCode = $_.Exception.Message
    $code = if ($rawCode -match '^[A-Z0-9_]+$') { $rawCode } else { 'RUNTIME_TEST_INTERNAL_ERROR' }
    $cleanupRequired = $started
    $cleanupInvocationFailed = $false

    if ($started) {
        # Invoke cleanup after every attempted start, including nonzero and
        # fatal children. Exact absence probes run independently even if the
        # cleanup child itself fails.
        $cleanupOutput = $null
        try {
            $cleanupOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
            $cleanupExitCode = $LASTEXITCODE
            if ($cleanupExitCode -eq 3) { $failureExitCode = 3 }
        }
        catch { $cleanupInvocationFailed = $true }
        finally { $cleanupOutput = $null }

        try {
            Assert-ThriveLensDistroStopped
            $distroAbsenceVerified = $true
        }
        catch { $distroAbsenceVerified = $false }
        try {
            Assert-ThriveLensHostPortAbsent
            $hostAbsenceVerified = $true
        }
        catch { $hostAbsenceVerified = $false }

        if ($distroAbsenceVerified -and $hostAbsenceVerified) {
            $started = $false
        }
        else {
            $cleanupInvocationFailed = $true
        }
        if ($cleanupInvocationFailed) {
            $code = 'RUNTIME_CLEANUP_FAILED'
            $failureExitCode = 3
        }
    }

    $bootstrapSecret = $null
    $wrongSecret = $null
    $fatal = $credentialCleanupFatal -or $failureExitCode -eq 3
    [pscustomobject]@{
        schema_version = 1
        status = if ($fatal) { 'ERROR' } else { 'BLOCKED' }
        code = $code
        cleanup_required = $cleanupRequired
        cleanup_verified = (-not $started -and -not $credentialCleanupFatal -and $distroAbsenceVerified -and $hostAbsenceVerified)
        distro_absence_verified = $distroAbsenceVerified
        host_absence_verified = $hostAbsenceVerified
    } | ConvertTo-Json -Compress
    if ($fatal) { exit 3 }
    exit 2
}
finally {
    # Clear every variable that may have held credential material on all exits.
    $bootstrapSecret = $null
    $wrongSecret = $null
    $correctAuthFile = $null
    $wrongAuthFile = $null
}
