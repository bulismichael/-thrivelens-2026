#Requires -Version 7.0

[CmdletBinding()]
param(
    [string]$DataDirectory,
    [string]$PasswordFile = $env:TL_POSTGRES_ADMIN_PASSWORD_FILE
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest
    $blockers = [Collections.Generic.List[string]]::new()
    if ([string]::IsNullOrWhiteSpace($DataDirectory)) {
        $DataDirectory = [Environment]::ExpandEnvironmentVariables([string]$manifest.compose.data_root)
    }

    if ([bool]$manifest.compose.enabled_by_default -or
        [string]$manifest.compose.required_profile -cne 'postgres-explicit') {
        $blockers.Add('COMPOSE_DEFAULT_DISABLE_POLICY_INVALID')
    }
    if ([string]$manifest.compose.engine_storage_accounting_status -cne 'CONFIGURED') {
        $blockers.Add('COMPOSE_ENGINE_STORAGE_ACCOUNTING_REQUIRED')
    }
    if ([string]$manifest.data_inventory_gate.status -cne 'SATISFIED') {
        $blockers.Add('DATA_INVENTORY_UPDATE_REQUIRED')
    }
    try {
        if (@($manifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)) {
            $blockers.Add('RESOURCE_PHASE_NOT_ACTIVE')
        }
    }
    catch { $blockers.Add('RESOURCE_PHASE_UNAVAILABLE') }
    try {
        $null = Invoke-ThriveLensResourceGate -ProjectedAdditionalBytes ([int64]$manifest.compose.projected_additional_bytes)
    }
    catch {
        if ($_.Exception.Message -in @(
            'PROJECTED_RESOURCE_CAP_EXCEEDED',
            'PROJECTED_RESOURCE_HARD_STOP',
            'PROJECTED_FREE_DISK_INSUFFICIENT'
        )) { $blockers.Add($_.Exception.Message) }
        else { $blockers.Add('RESOURCE_GATE_FAILED') }
    }
    try {
        if ((Get-ThriveLensFreeMemoryBytes) -lt [int64]$manifest.resource_policy.runtime_minimum_free_memory_bytes) {
            $blockers.Add('LOW_FREE_MEMORY')
        }
    }
    catch { $blockers.Add('MEMORY_MEASUREMENT_UNAVAILABLE') }

    if (-not [string]::IsNullOrWhiteSpace($DataDirectory)) {
        try {
            $dataPath = Assert-ThriveLensComposeDataDirectory `
                -Path $DataDirectory `
                -ExpectedPath ([string]$manifest.compose.data_root)
        }
        catch {
            if ($_.Exception.Message -in @(
                'PATH_OUTSIDE_ATTRIBUTABLE_ROOT',
                'REPARSE_PATH_REJECTED',
                'COMPOSE_DATA_ROOT_FORBIDDEN',
                'COMPOSE_DATA_DIRECTORY_MISMATCH',
                'COMPOSE_DATA_DIRECTORY_UNAVAILABLE',
                'COMPOSE_DATA_DIRECTORY_NOT_EMPTY',
                'DIRECTORY_ACL_INHERITANCE_ENABLED',
                'DIRECTORY_ACL_INHERITED_RULE_REJECTED',
                'DIRECTORY_ACL_OWNER_UNVERIFIABLE',
                'DIRECTORY_ACL_OWNER_REJECTED',
                'DIRECTORY_ACL_IDENTITY_UNVERIFIABLE',
                'DIRECTORY_ACL_ALLOWLIST_VIOLATION',
                'DIRECTORY_ACL_CURRENT_USER_MODIFY_MISSING'
            )) { $blockers.Add($_.Exception.Message) }
            else { $blockers.Add('COMPOSE_DATA_POLICY_FAILED') }
        }
    }
    else { $blockers.Add('COMPOSE_DATA_DIRECTORY_REQUIRED') }

    if ([string]::IsNullOrWhiteSpace($PasswordFile)) {
        $blockers.Add('COMPOSE_PASSWORD_FILE_REQUIRED')
    }
    else {
        try {
            $secretPath = Assert-ThriveLensOwnedPath -Path $PasswordFile -AllowMissing
            $null = Assert-ThriveLensPathOutsideDirectory `
                -DirectoryPath ([string]$manifest.compose.data_root) `
                -OtherPath $secretPath
            if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) {
                $blockers.Add('COMPOSE_PASSWORD_FILE_UNAVAILABLE')
            }
            else { Assert-ThriveLensSecretFileAcl -Path $secretPath }
        }
        catch {
            if ($_.Exception.Message -in @(
                'PATH_OUTSIDE_ATTRIBUTABLE_ROOT',
                'REPARSE_PATH_REJECTED',
                'COMPOSE_SECRET_DATA_OVERLAP',
                'SECRET_FILE_UNAVAILABLE',
                'SECRET_ACL_WINDOWS_REQUIRED',
                'SECRET_ACL_INHERITANCE_ENABLED',
                'SECRET_ACL_INHERITED_RULE_REJECTED',
                'SECRET_ACL_OWNER_UNVERIFIABLE',
                'SECRET_ACL_OWNER_REJECTED',
                'SECRET_ACL_IDENTITY_UNVERIFIABLE',
                'SECRET_ACL_ALLOWLIST_VIOLATION',
                'SECRET_ACL_CURRENT_USER_READ_MISSING',
                'SECRET_ACL_CURRENT_USER_READ_UNAVAILABLE'
            )) { $blockers.Add($_.Exception.Message) }
            else { $blockers.Add('COMPOSE_SECRET_POLICY_FAILED') }
        }
    }

    if ($blockers.Count -gt 0) {
        [pscustomobject]@{
            schema_version = 1
            status = 'BLOCKED'
            profile = [string]$manifest.compose.required_profile
            projected_additional_bytes = [int64]$manifest.compose.projected_additional_bytes
            codes = @($blockers | Select-Object -Unique)
        } | ConvertTo-Json -Compress
        exit 2
    }

    [pscustomobject]@{
        schema_version = 1
        status = 'READY'
        profile = [string]$manifest.compose.required_profile
        platform = [string]$manifest.compose.platform
        projected_additional_bytes = [int64]$manifest.compose.projected_additional_bytes
    } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'COMPOSE_VALIDATION_INTERNAL_ERROR' } | ConvertTo-Json -Compress
    exit 3
}
