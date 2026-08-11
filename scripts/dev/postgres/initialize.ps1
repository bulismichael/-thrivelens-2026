#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PasswordFile,
    [string]$BootstrapUser = 'tl_bootstrap'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$mutationStarted = $false
$response = $null
$resultExitCode = 0

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Initialize 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }

    $manifest = Get-ThriveLensManifest
    if ([string]$manifest.data_inventory_gate.status -cne 'SATISFIED') {
        throw 'DATA_INVENTORY_UPDATE_REQUIRED'
    }
    $paths = Get-ThriveLensPostgresPaths
    Assert-ThriveLensPostgresVersions
    if (Test-Path -LiteralPath $paths.DataRoot) {
        throw 'CLUSTER_ALREADY_EXISTS'
    }
    $passwordPath = Assert-ThriveLensOwnedPath -Path $PasswordFile -AllowMissing
    if (-not (Test-Path -LiteralPath $passwordPath -PathType Leaf)) {
        throw 'PASSWORD_FILE_UNAVAILABLE'
    }
    $passwordPath = Assert-ThriveLensOwnedPath -Path $passwordPath
    Assert-ThriveLensSecretFileAcl -Path $passwordPath
    $passwordLines = @(Get-Content -LiteralPath $passwordPath -TotalCount 2)
    if ($passwordLines.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$passwordLines[0])) {
        throw 'PASSWORD_FILE_INVALID'
    }
    if ($BootstrapUser -notmatch '^[a-z][a-z0-9_]{2,31}$') {
        throw 'BOOTSTRAP_USER_INVALID'
    }

    $parent = Assert-ThriveLensOwnedPath -Path (Split-Path -Parent $paths.DataRoot) -AllowMissing
    $mutationStarted = $true
    $null = New-Item -ItemType Directory -Path $parent -Force
    $initOutput = @(& $paths.InitDb `
        '--pgdata' $paths.DataRoot `
        '--username' $BootstrapUser `
        '--pwfile' $passwordPath `
        '--auth-host=scram-sha-256' `
        '--auth-local=scram-sha-256' `
        '--encoding=UTF8' `
        '--locale=C' `
        '--data-checksums' `
        '--no-instructions' 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $initOutput = $null
        throw 'INITDB_FAILED'
    }
    $initOutput = $null

    if (-not (Test-Path -LiteralPath (Join-Path $paths.DataRoot 'PG_VERSION') -PathType Leaf)) {
        throw 'INITDB_RESULT_INVALID'
    }
    $clusterScan = Measure-ThriveLensSafeTree `
        -Root $paths.DataRoot `
        -MaximumBytes ([int64]$manifest.postgresql.maximum_initial_cluster_bytes) `
        -MaximumEntries ([int]$manifest.postgresql.maximum_archive_entries)
    $response = [pscustomobject]@{
        schema_version = 1
        status = 'INITIALIZED'
        authentication = 'scram-sha-256'
        data_checksums = $true
        cluster_bytes = [int64]$clusterScan.Bytes
        cluster_entries = [int]$clusterScan.Entries
    }
}
catch {
    $allowed = @(
        'DATA_INVENTORY_UPDATE_REQUIRED',
        'CLUSTER_ALREADY_EXISTS',
        'PASSWORD_FILE_UNAVAILABLE',
        'PASSWORD_FILE_INVALID',
        'SECRET_FILE_UNAVAILABLE',
        'SECRET_ACL_WINDOWS_REQUIRED',
        'SECRET_ACL_INHERITANCE_ENABLED',
        'SECRET_ACL_INHERITED_RULE_REJECTED',
        'SECRET_ACL_OWNER_UNVERIFIABLE',
        'SECRET_ACL_OWNER_REJECTED',
        'SECRET_ACL_IDENTITY_UNVERIFIABLE',
        'SECRET_ACL_READ_ALLOWLIST_VIOLATION',
        'SECRET_ACL_CURRENT_USER_READ_MISSING',
        'SECRET_ACL_CURRENT_USER_READ_UNAVAILABLE',
        'BOOTSTRAP_USER_INVALID',
        'INITDB_FAILED',
        'INITDB_RESULT_INVALID',
        'SAFE_TREE_ENTRY_LIMIT_EXCEEDED',
        'SAFE_TREE_LIMIT_INVALID',
        'SAFE_TREE_REPARSE_REJECTED',
        'SAFE_TREE_SIZE_OVERFLOW',
        'SAFE_TREE_SIZE_EXCEEDED',
        'POSTGRES_VERSION_OUTPUT_MISMATCH',
        'POSTGRES_VERSION_EXECUTION_FAILED',
        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE'
    )
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'INITIALIZE_INTERNAL_ERROR' }
    $response = [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code }
    $resultExitCode = 2
}
finally {
    if ($mutationStarted) {
        try { $null = Invoke-ThriveLensResourceGate }
        catch {
            $response = [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'POST_MUTATION_RESOURCE_GATE_FAILED' }
            $resultExitCode = 3
        }
    }
}

$response | ConvertTo-Json -Compress
if ($resultExitCode -ne 0) { exit $resultExitCode }
