#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$startInvoked = $false
$failureExitCode = 2

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Runtime 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    if (Test-ThriveLensPostgresRunning) {
        throw 'RUNTIME_TEST_REQUIRES_STOPPED_CLUSTER'
    }
    Assert-ThriveLensPostgresAbsent

    # A child can start PostgreSQL and then fail while reporting a nonzero exit.
    # From this point onward every failure path must independently stop/prove
    # absence; the child process's cleanup claim is never trusted by itself.
    $startInvoked = $true
    $startOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'start.ps1') 2>&1)
    $startExitCode = $LASTEXITCODE
    $startFailure = Resolve-ThriveLensStartChildFailure `
        -ExitCode $startExitCode `
        -OutputText ($startOutput -join [Environment]::NewLine)
    $startOutput = $null
    if ($startExitCode -ne 0) {
        $failureExitCode = [int]$startFailure.ExitCode
        throw [string]$startFailure.Code
    }

    $paths = Get-ThriveLensPostgresPaths
    $readinessOutput = @(& $paths.PgIsReady '-h' '127.0.0.1' '-p' ([string]$paths.Port) '-t' '5' '-q' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $readinessOutput = $null
        throw 'RUNTIME_READINESS_PROBE_FAILED'
    }
    $readinessOutput = $null
    Assert-ThriveLensLoopbackListener
    Assert-ThriveLensPostgresVersions

    # PASS is impossible until the bounded stop script succeeds and exact
    # process/listener absence is independently verified.
    $stopOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $stopOutput = $null
        throw 'RUNTIME_STOP_PROBE_FAILED'
    }
    $stopOutput = $null
    Assert-ThriveLensPostgresAbsent
    $startInvoked = $false

    [pscustomobject]@{
        schema_version = 1
        status = 'PASS'
        real_postgresql = $true
        loopback_only = $true
        start_stop_proven = $true
        stopped_before_pass = $true
        absence_verified = $true
    } | ConvertTo-Json -Compress
}
catch {
    $rawOriginalCode = $_.Exception.Message
    $allowed = @(
        'RUNTIME_TEST_REQUIRES_STOPPED_CLUSTER',
        'RUNTIME_START_PROBE_FAILED',
        'POSTGRES_START_CLEANUP_FAILED',
        'RUNTIME_START_CHILD_FATAL',
        'RUNTIME_READINESS_PROBE_FAILED',
        'RUNTIME_STOP_PROBE_FAILED',
        'POSTGRES_CLUSTER_STILL_RUNNING',
        'POSTGRES_PROCESS_STILL_PRESENT',
        'POSTGRES_LISTENER_STILL_PRESENT',
        'POSTGRES_LISTENER_UNAVAILABLE',
        'POSTGRES_NON_LOOPBACK_LISTENER',
        'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_VERSION_OUTPUT_MISMATCH',
        'POSTGRES_VERSION_EXECUTION_FAILED',
        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE'
    )
    $originalCode = if ($allowed -contains $rawOriginalCode) { $rawOriginalCode } else { 'RUNTIME_TEST_INTERNAL_ERROR' }

    $cleanupAttempted = $false
    $cleanupExitCode = 0
    $absenceVerified = $false
    if ($startInvoked) {
        $cleanupAttempted = $true
        $cleanupExitCode = -1
        $cleanupOutput = @()
        try {
            $cleanupOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
            $cleanupExitCode = $LASTEXITCODE
        }
        catch { $cleanupExitCode = -1 }
        finally { $cleanupOutput = $null }

        # This probe runs even when the independent stop command returns
        # nonzero or throws, so a surviving process/listener cannot be hidden.
        try {
            Assert-ThriveLensPostgresAbsent
            $absenceVerified = $true
        }
        catch { $absenceVerified = $false }
    }

    $outcome = Resolve-ThriveLensRuntimeFailureOutcome `
        -OriginalCode $originalCode `
        -OriginalExitCode $failureExitCode `
        -StartInvoked $startInvoked `
        -CleanupAttempted $cleanupAttempted `
        -CleanupExitCode $cleanupExitCode `
        -AbsenceVerified $absenceVerified
    [pscustomobject]@{
        schema_version = 1
        status = [string]$outcome.Status
        code = [string]$outcome.Code
        cleanup_required = [bool]$outcome.CleanupRequired
        cleanup_verified = [bool]$outcome.CleanupVerified
    } | ConvertTo-Json -Compress
    exit ([int]$outcome.ExitCode)
}
