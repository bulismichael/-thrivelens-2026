#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

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
    $null = New-Item -ItemType Directory -Path $paths.LogRoot -Force
    $logFile = Join-Path $paths.LogRoot 'postgres.log'
    $serverOptions = "-h 127.0.0.1 -p $($paths.Port) -c max_connections=20 -c shared_buffers=64MB -c work_mem=2MB -c maintenance_work_mem=32MB -c logging_collector=off -c log_statement=none -c log_connections=off -c log_disconnections=off -c log_hostname=off -c log_min_error_statement=panic"
    $null = & $paths.PgCtl 'start' '-D' $paths.DataRoot '-l' $logFile '-o' $serverOptions '-w' '-t' '30' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'POSTGRES_START_FAILED'
    }
    Assert-ThriveLensLoopbackListener
    [pscustomobject]@{ schema_version = 1; status = 'STARTED'; address = '127.0.0.1'; port = $paths.Port; service_registered = $false } | ConvertTo-Json -Compress
}
catch {
    $allowed = @('POSTGRES_ALREADY_RUNNING', 'POSTGRES_START_FAILED', 'POSTGRES_LISTENER_UNAVAILABLE', 'POSTGRES_NON_LOOPBACK_LISTENER')
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'POSTGRES_START_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
