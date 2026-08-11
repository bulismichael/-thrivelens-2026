#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

try {
    Import-Module -Name $modulePath -Force
    $paths = Get-ThriveLensPostgresPaths
    if (-not (Test-ThriveLensPostgresRunning)) {
        [pscustomobject]@{ schema_version = 1; status = 'ALREADY_STOPPED' } | ConvertTo-Json -Compress
        exit 0
    }
    $null = & $paths.PgCtl 'stop' '-D' $paths.DataRoot '-m' 'fast' '-w' '-t' '30' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'POSTGRES_STOP_FAILED'
    }
    [pscustomobject]@{ schema_version = 1; status = 'STOPPED'; shutdown_mode = 'fast' } | ConvertTo-Json -Compress
}
catch {
    $code = if ($_.Exception.Message -ceq 'POSTGRES_STOP_FAILED') { 'POSTGRES_STOP_FAILED' } else { 'POSTGRES_STOP_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
