#Requires -Version 7.0

[CmdletBinding()]
param(
    [ValidateSet('Install', 'Initialize', 'Runtime')]
    [string]$Action = 'Runtime',
    [ValidateSet('Backend', 'Python', 'PostgreSQL')]
    [string]$InstallKind = 'Backend'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest
    $blockers = [Collections.Generic.List[string]]::new()

    $projectedAdditionalBytes = switch ($Action) {
        'Install' {
            switch ($InstallKind) {
                'Python' { [int64]$manifest.resource_policy.python_worst_case_additional_bytes }
                'PostgreSQL' { [int64]$manifest.resource_policy.postgresql_worst_case_additional_bytes }
                default { [int64]$manifest.resource_policy.worst_case_backend_additional_bytes }
            }
        }
        'Initialize' { [int64]$manifest.resource_policy.postgresql_initialization_worst_case_additional_bytes }
        default { [int64]0 }
    }
    try { $null = Invoke-ThriveLensResourceGate -ProjectedAdditionalBytes $projectedAdditionalBytes }
    catch {
        if ($_.Exception.Message -in @(
            'PROJECTED_RESOURCE_CAP_EXCEEDED',
            'PROJECTED_RESOURCE_HARD_STOP',
            'PROJECTED_FREE_DISK_INSUFFICIENT'
        )) {
            $blockers.Add($_.Exception.Message)
        }
        else { $blockers.Add('RESOURCE_GATE_FAILED') }
    }

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

    if ($Action -eq 'Install' -and $InstallKind -eq 'PostgreSQL' -and
        -not [bool]$manifest.postgresql.windows_portable_install_enabled) {
        $blockers.Add('WINDOWS_POSTGRES_INSTALL_DISABLED')
        $blockers.Add('WSL_FALLBACK_REQUIRED_NOT_ACTIVATED')
    }

    if ($Action -in @('Initialize', 'Runtime')) {
        $windowsRuntimeApproved = [string]$manifest.postgresql.portable_status -ceq 'VERIFIED_INSTALLED'
        if (-not $windowsRuntimeApproved) {
            $blockers.Add('WINDOWS_POSTGRES_RUNTIME_REJECTED')
        }
        if ([string]$manifest.wsl_fallback.status -cne 'ACTIVATED') {
            $blockers.Add('WSL_FALLBACK_REQUIRED_NOT_ACTIVATED')
        }
        if ($Action -eq 'Initialize' -and [string]$manifest.data_inventory_gate.status -cne 'SATISFIED') {
            $blockers.Add('DATA_INVENTORY_UPDATE_REQUIRED')
        }
        try {
            $paths = Get-ThriveLensPostgresPaths
            $binariesAvailable = $true
            foreach ($requiredFile in @($paths.PgCtl, $paths.InitDb, $paths.Postgres, $paths.PgIsReady)) {
                if (-not (Test-Path -LiteralPath $requiredFile -PathType Leaf)) {
                    $blockers.Add('POSTGRES_BINARIES_UNAVAILABLE')
                    $binariesAvailable = $false
                    break
                }
            }
            if ($binariesAvailable -and $windowsRuntimeApproved) {
                try { Assert-ThriveLensPostgresVersions }
                catch {
                    if ($_.Exception.Message -in @(
                        'POSTGRES_VERSION_OUTPUT_MISMATCH',
                        'POSTGRES_VERSION_EXECUTION_FAILED',
                        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE'
                    )) {
                        $blockers.Add($_.Exception.Message)
                    }
                    else { throw }
                }
            }
            if ($Action -eq 'Runtime' -and -not (Test-Path -LiteralPath (Join-Path $paths.DataRoot 'PG_VERSION') -PathType Leaf)) {
                $blockers.Add('POSTGRES_CLUSTER_UNAVAILABLE')
            }
            $listeners = @(Get-ThriveLensPostgresListeners)
            if ($listeners.Count -gt 0 -and
                (-not $windowsRuntimeApproved -or -not (Test-ThriveLensPostgresRunning))) {
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
            install_kind = if ($Action -eq 'Install') { $InstallKind } else { $null }
            projected_additional_bytes = $projectedAdditionalBytes
            codes = @($blockers | Select-Object -Unique)
        } | ConvertTo-Json -Compress
        exit 2
    }

    [pscustomobject]@{
        schema_version = 1
        status = 'READY'
        action = $Action
        install_kind = if ($Action -eq 'Install') { $InstallKind } else { $null }
        projected_additional_bytes = $projectedAdditionalBytes
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
