#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Initialize', 'Runtime')]
    [string]$Action = 'Runtime'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest
    $blockers = [Collections.Generic.List[string]]::new()

    try { Invoke-ThriveLensResourceGate }
    catch { $blockers.Add('RESOURCE_GATE_FAILED') }

    try {
        if (@($manifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)) {
            $blockers.Add('RESOURCE_PHASE_NOT_ACTIVE')
        }
    }
    catch { $blockers.Add('RESOURCE_PHASE_UNAVAILABLE') }

    try {
        $minimumBytes = if ($Action -eq 'Install') {
            [int64]$manifest.resource_policy.install_minimum_free_memory_bytes
        }
        else {
            [int64]$manifest.resource_policy.runtime_minimum_free_memory_bytes
        }
        if ((Get-ThriveLensFreeMemoryBytes) -lt $minimumBytes) {
            $blockers.Add('LOW_FREE_MEMORY')
        }
    }
    catch { $blockers.Add('MEMORY_MEASUREMENT_UNAVAILABLE') }

    if ($Action -in @('Initialize', 'Runtime')) {
        if (@('INSTALLED_PENDING_RUNTIME_PROOF', 'VERIFIED_INSTALLED') -cnotcontains [string]$manifest.postgresql.portable_status) {
            $blockers.Add('PORTABLE_RUNTIME_NOT_VERIFIED')
        }
        if ([string]$manifest.postgresql.integrity.status -cne 'VERIFIED') {
            $blockers.Add('POSTGRES_ARTIFACT_INTEGRITY_BLOCKED')
        }
        try {
            $paths = Get-ThriveLensPostgresPaths
            foreach ($requiredFile in @($paths.PgCtl, $paths.InitDb, $paths.Postgres, $paths.PgIsReady)) {
                if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
                    $blockers.Add('POSTGRES_BINARIES_UNAVAILABLE')
                    break
                }
            }
            if ($Action -eq 'Runtime' -and -not (Test-Path -LiteralPath (Join-Path $paths.DataRoot 'PG_VERSION') -PathType Leaf)) {
                $blockers.Add('POSTGRES_CLUSTER_UNAVAILABLE')
            }
            $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $paths.Port -ErrorAction SilentlyContinue)
            if ($listeners.Count -gt 0 -and -not (Test-ThriveLensPostgresRunning)) {
                $blockers.Add('POSTGRES_PORT_ALREADY_IN_USE')
            }
        }
        catch { $blockers.Add('POSTGRES_PATH_POLICY_FAILED') }
    }

    if ($blockers.Count -gt 0) {
        [pscustomobject]@{
            schema_version = 1
            status = 'BLOCKED'
            action = $Action
            codes = @($blockers | Select-Object -Unique)
        } | ConvertTo-Json -Compress
        exit 2
    }

    [pscustomobject]@{
        schema_version = 1
        status = 'READY'
        action = $Action
        codes = @()
    } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{
        schema_version = 1
        status = 'ERROR'
        action = $Action
        codes = @('PREFLIGHT_INTERNAL_ERROR')
    } | ConvertTo-Json -Compress
    exit 3
}
