#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$startedHere = $false

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

    $startOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'start.ps1') 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $startOutput = $null
        throw 'RUNTIME_START_PROBE_FAILED'
    }
    $startOutput = $null
    $startedHere = $true

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
    $startedHere = $false

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
    $originalCode = $_.Exception.Message
    $cleanupFailed = $false
    if ($startedHere) {
        $cleanupExitCode = 0
        try {
            $cleanupOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
            $cleanupExitCode = $LASTEXITCODE
            $cleanupOutput = $null
            Assert-ThriveLensPostgresAbsent
            $startedHere = $false
        }
        catch { $cleanupFailed = $true }
        if ($cleanupExitCode -ne 0) { $cleanupFailed = $true }
    }
    if ($cleanupFailed) {
        [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'RUNTIME_CLEANUP_FAILED' } | ConvertTo-Json -Compress
        exit 3
    }

    $allowed = @(
        'RUNTIME_TEST_REQUIRES_STOPPED_CLUSTER',
        'RUNTIME_START_PROBE_FAILED',
        'RUNTIME_READINESS_PROBE_FAILED',
        'RUNTIME_STOP_PROBE_FAILED',
        'POSTGRES_LISTENER_UNAVAILABLE',
        'POSTGRES_NON_LOOPBACK_LISTENER',
        'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_VERSION_OUTPUT_MISMATCH',
        'POSTGRES_VERSION_EXECUTION_FAILED',
        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE'
    )
    $code = if ($allowed -contains $originalCode) { $originalCode } else { 'RUNTIME_TEST_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
