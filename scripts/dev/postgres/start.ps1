#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$startAttempted = $false
$mutationStarted = $false

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Runtime 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    if (Test-ThriveLensPostgresRunning) {
        throw 'POSTGRES_ALREADY_RUNNING'
    }
    $paths = Get-ThriveLensPostgresPaths
    Assert-ThriveLensPostgresVersions
    $logFile = Assert-ThriveLensOwnedPath -Path (Join-Path $paths.LogRoot 'postgres.log') -AllowMissing
    if ((Test-Path -LiteralPath $logFile) -and -not (Test-Path -LiteralPath $logFile -PathType Leaf)) {
        throw 'POSTGRES_LOG_TARGET_INVALID'
    }
    $serverOptions = "-h 127.0.0.1 -p $($paths.Port) -c max_connections=20 -c shared_buffers=64MB -c work_mem=2MB -c maintenance_work_mem=32MB -c logging_collector=off -c log_statement=none -c log_connections=off -c log_disconnections=off -c log_hostname=off -c log_min_error_statement=panic"

    $mutationStarted = $true
    $null = New-Item -ItemType Directory -Path $paths.LogRoot -Force
    $startAttempted = $true
    $startOutput = @(& $paths.PgCtl 'start' '-D' $paths.DataRoot '-l' $logFile '-o' $serverOptions '-w' '-t' '30' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $startOutput = $null
        throw 'POSTGRES_START_FAILED'
    }
    $startOutput = $null
    Assert-ThriveLensLoopbackListener
    $null = Invoke-ThriveLensResourceGate

    [pscustomobject]@{
        schema_version = 1
        status = 'STARTED'
        address = '127.0.0.1'
        port = $paths.Port
        service_registered = $false
    } | ConvertTo-Json -Compress
}
catch {
    $originalCode = $_.Exception.Message
    $cleanupFailed = $false
    if ($startAttempted) {
        $cleanupExitCode = 0
        try {
            $cleanupOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1)
            $cleanupExitCode = $LASTEXITCODE
            $cleanupOutput = $null
            Assert-ThriveLensPostgresAbsent
        }
        catch { $cleanupFailed = $true }
        if ($cleanupExitCode -ne 0) { $cleanupFailed = $true }
    }
    if ($mutationStarted) {
        try { $null = Invoke-ThriveLensResourceGate }
        catch { $cleanupFailed = $true }
    }

    if ($cleanupFailed) {
        [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'POSTGRES_START_CLEANUP_FAILED' } | ConvertTo-Json -Compress
        exit 3
    }
    $allowed = @(
        'POSTGRES_ALREADY_RUNNING',
        'POSTGRES_LOG_TARGET_INVALID',
        'POSTGRES_START_FAILED',
        'POSTGRES_LISTENER_UNAVAILABLE',
        'POSTGRES_NON_LOOPBACK_LISTENER',
        'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_VERSION_OUTPUT_MISMATCH',
        'POSTGRES_VERSION_EXECUTION_FAILED',
        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE',
        'RESOURCE_GATE_FAILED',
        'PROJECTED_RESOURCE_CAP_EXCEEDED',
        'PROJECTED_RESOURCE_HARD_STOP',
        'PROJECTED_FREE_DISK_INSUFFICIENT'
    )
    $code = if ($allowed -contains $originalCode) { $originalCode } else { 'POSTGRES_START_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
