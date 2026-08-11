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
    $startOutput = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'start.ps1') 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'RUNTIME_START_PROBE_FAILED'
    }
    $startedHere = $true
    $paths = Get-ThriveLensPostgresPaths
    & $paths.PgIsReady '-h' '127.0.0.1' '-p' ([string]$paths.Port) '-t' '5' '-q'
    if ($LASTEXITCODE -ne 0) {
        throw 'RUNTIME_READINESS_PROBE_FAILED'
    }
    Assert-ThriveLensLoopbackListener
    & $paths.Postgres '--version' | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw 'RUNTIME_VERSION_PROBE_FAILED'
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; real_postgresql = $true; loopback_only = $true; start_stop_proven = $true } | ConvertTo-Json -Compress
}
catch {
    $allowed = @('RUNTIME_TEST_REQUIRES_STOPPED_CLUSTER', 'RUNTIME_START_PROBE_FAILED', 'RUNTIME_READINESS_PROBE_FAILED', 'RUNTIME_VERSION_PROBE_FAILED', 'POSTGRES_LISTENER_UNAVAILABLE', 'POSTGRES_NON_LOOPBACK_LISTENER')
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'RUNTIME_TEST_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
finally {
    if ($startedHere) {
        $null = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'stop.ps1') 2>&1
    }
}
