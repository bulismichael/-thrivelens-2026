#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$stopAttempted = $false

try {
    Import-Module -Name $modulePath -Force
    $paths = Get-ThriveLensPostgresPaths
    $wasRunning = Test-ThriveLensPostgresRunning
    if ($wasRunning) {
        $stopAttempted = $true
        $stopOutput = @(& $paths.PgCtl 'stop' '-D' $paths.DataRoot '-m' 'fast' '-w' '-t' '30' 2>&1)
        if ($LASTEXITCODE -ne 0) {
            $stopOutput = $null
            throw 'POSTGRES_STOP_FAILED'
        }
        $stopOutput = $null
    }

    # Never claim stopped merely because pg_ctl returned. Verify the exact
    # binary process and every listener on the dedicated port are absent.
    Assert-ThriveLensPostgresAbsent
    if ($stopAttempted) { $null = Invoke-ThriveLensResourceGate }

    if ($wasRunning) {
        [pscustomobject]@{ schema_version = 1; status = 'STOPPED'; shutdown_mode = 'fast'; absence_verified = $true } | ConvertTo-Json -Compress
    }
    else {
        [pscustomobject]@{ schema_version = 1; status = 'ALREADY_STOPPED'; absence_verified = $true } | ConvertTo-Json -Compress
    }
}
catch {
    $allowed = @(
        'POSTGRES_STOP_FAILED',
        'POSTGRES_CLUSTER_STILL_RUNNING',
        'POSTGRES_PROCESS_STILL_PRESENT',
        'POSTGRES_LISTENER_STILL_PRESENT',
        'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE',
        'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE',
        'RESOURCE_GATE_FAILED',
        'PROJECTED_RESOURCE_CAP_EXCEEDED',
        'PROJECTED_RESOURCE_HARD_STOP',
        'PROJECTED_FREE_DISK_INSUFFICIENT'
    )
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'POSTGRES_STOP_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
