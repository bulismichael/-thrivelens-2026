#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'

function Get-ProcessEnvironmentValue {
    param([Parameter(Mandatory)][string]$Name)
    return [string][Environment]::GetEnvironmentVariable(
        $Name,
        [EnvironmentVariableTarget]::Process
    )
}

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest
    $blockers = [Collections.Generic.List[string]]::new()

    # There is deliberately no runnable Compose service yet. A future wrapper
    # must validate and consume one immutable process-environment snapshot in
    # the same process before it generates and invokes temporary configuration.
    $blockers.Add('COMPOSE_ACTIVATION_WRAPPER_REQUIRED')
    $remainingArguments = @(Get-Variable -Name args -ValueOnly -ErrorAction SilentlyContinue)
    if ($remainingArguments.Count -ne 0) {
        $blockers.Add('COMPOSE_PARAMETER_OVERRIDE_REJECTED')
    }

    $environmentNames = $manifest.compose.environment_contract
    $inputSnapshot = [pscustomobject]@{
        DataDirectory = Get-ProcessEnvironmentValue -Name ([string]$environmentNames.data_directory)
        PasswordFile = Get-ProcessEnvironmentValue -Name ([string]$environmentNames.password_file)
        AdminUser = Get-ProcessEnvironmentValue -Name ([string]$environmentNames.admin_user)
        Database = Get-ProcessEnvironmentValue -Name ([string]$environmentNames.database)
        Port = Get-ProcessEnvironmentValue -Name ([string]$environmentNames.port)
    }

    if ([bool]$manifest.compose.enabled_by_default -or
        [bool]$manifest.compose.direct_compose_activation_permitted -or
        -not [bool]$manifest.compose.activation_wrapper_required -or
        -not [bool]$manifest.compose.same_process_validation_and_use_required -or
        [string]$manifest.compose.activation_status -cne 'BLOCKED_GATED_ACTIVATION_WRAPPER_NOT_IMPLEMENTED' -or
        [string]$manifest.compose.activation_wrapper_status -cne 'REQUIRED_NOT_IMPLEMENTED') {
        $blockers.Add('COMPOSE_ACTIVATION_POLICY_INVALID')
    }
    if ([string]$manifest.compose.required_profile -cne 'postgres-explicit') {
        $blockers.Add('COMPOSE_FUTURE_PROFILE_POLICY_INVALID')
    }
    if ([string]$manifest.compose.listen_address -cne '127.0.0.1' -or
        [int]$manifest.compose.port -ne 55432 -or
        [string]$manifest.compose.admin_user -cne 'tl_bootstrap' -or
        [string]$manifest.compose.database -cne 'thrivelens_r0') {
        $blockers.Add('COMPOSE_PINNED_INPUT_POLICY_INVALID')
    }

    if ([string]::IsNullOrWhiteSpace($inputSnapshot.AdminUser)) {
        $blockers.Add('COMPOSE_ADMIN_USER_REQUIRED')
    }
    elseif ($inputSnapshot.AdminUser -cne [string]$manifest.compose.admin_user) {
        $blockers.Add('COMPOSE_ADMIN_USER_MISMATCH')
    }
    if ([string]::IsNullOrWhiteSpace($inputSnapshot.Database)) {
        $blockers.Add('COMPOSE_DATABASE_REQUIRED')
    }
    elseif ($inputSnapshot.Database -cne [string]$manifest.compose.database) {
        $blockers.Add('COMPOSE_DATABASE_MISMATCH')
    }
    if ([string]::IsNullOrWhiteSpace($inputSnapshot.Port)) {
        $blockers.Add('COMPOSE_PORT_REQUIRED')
    }
    elseif ($inputSnapshot.Port -cne ([string][int]$manifest.compose.port)) {
        $blockers.Add('COMPOSE_PORT_MISMATCH')
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

    if ([string]::IsNullOrWhiteSpace($inputSnapshot.DataDirectory)) {
        $blockers.Add('COMPOSE_DATA_DIRECTORY_REQUIRED')
    }
    else {
        try {
            $dataPath = Assert-ThriveLensComposeDataDirectory `
                -Path ([Environment]::ExpandEnvironmentVariables($inputSnapshot.DataDirectory)) `
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

    if ([string]::IsNullOrWhiteSpace($inputSnapshot.PasswordFile)) {
        $blockers.Add('COMPOSE_PASSWORD_FILE_REQUIRED')
    }
    else {
        try {
            $secretPath = Assert-ThriveLensOwnedPath `
                -Path ([Environment]::ExpandEnvironmentVariables($inputSnapshot.PasswordFile)) `
                -AllowMissing
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

    [pscustomobject]@{
        schema_version = 1
        status = 'BLOCKED'
        activation_status = [string]$manifest.compose.activation_status
        environment_snapshot_read_once = $true
        projected_additional_bytes = [int64]$manifest.compose.projected_additional_bytes
        codes = @($blockers | Select-Object -Unique)
    } | ConvertTo-Json -Compress
    exit 2
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'COMPOSE_VALIDATION_INTERNAL_ERROR' } | ConvertTo-Json -Compress
    exit 3
}
