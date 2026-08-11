#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\..\dev\postgres\Runtime.psm1'
$stagingRoot = $null
$mutationStarted = $false
$response = $null
$resultExitCode = 0

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest

    # The reviewed manifest deliberately keeps this path unreachable. The code
    # below is a dormant, fail-closed contract for a future separately reviewed
    # publisher-attested archive; a local hash cannot enable it.
    if (-not [bool]$manifest.postgresql.windows_portable_install_enabled -or
        [string]$manifest.postgresql.portable_status -ceq 'REJECTED_FOR_RUNTIME') {
        throw 'WINDOWS_POSTGRES_INSTALL_DISABLED'
    }

    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\..\dev\postgres\preflight.ps1') `
        -Action Install -InstallKind PostgreSQL 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    $verification = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify_artifact.ps1') `
        -Kind PostgreSQL -Path $ArtifactPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $verification | Write-Output
        exit $LASTEXITCODE
    }

    $artifact = Assert-ThriveLensOwnedPath -Path $ArtifactPath
    $paths = Get-ThriveLensPostgresPaths
    $targetVersionRoot = Assert-ThriveLensOwnedPath -Path (Split-Path -Parent $paths.BinaryRoot) -AllowMissing
    if (Test-Path -LiteralPath $targetVersionRoot) {
        throw 'POSTGRES_TARGET_ALREADY_EXISTS'
    }

    $stagingParent = Assert-ThriveLensOwnedPath -Path (Join-Path (Get-ThriveLensAttributableRoot) 'staging') -AllowMissing
    $stagingRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $stagingParent ('postgres-' + [guid]::NewGuid().ToString('N'))) -AllowMissing

    # Scan the ZIP central directory before any directory creation or extraction.
    $archiveScan = Assert-ThriveLensPostgresArchive `
        -ArchivePath $artifact `
        -DestinationRoot $stagingRoot `
        -MaximumEntries ([int]$manifest.postgresql.maximum_archive_entries) `
        -MaximumUncompressedBytes ([int64]$manifest.postgresql.maximum_extracted_binary_bytes)

    $mutationStarted = $true
    $null = New-Item -ItemType Directory -Path $stagingRoot -Force
    Expand-Archive -LiteralPath $artifact -DestinationPath $stagingRoot

    $expandedRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $stagingRoot 'pgsql')
    $expandedScan = Measure-ThriveLensSafeTree `
        -Root $expandedRoot `
        -MaximumBytes ([int64]$manifest.postgresql.maximum_extracted_binary_bytes) `
        -MaximumEntries ([int]$manifest.postgresql.maximum_archive_entries)

    $executablePaths = @()
    foreach ($relative in @('bin\postgres.exe', 'bin\pg_ctl.exe', 'bin\initdb.exe', 'bin\pg_isready.exe')) {
        $executablePath = Assert-ThriveLensOwnedPath -Path (Join-Path $expandedRoot $relative)
        if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
            throw 'POSTGRES_ARCHIVE_LAYOUT_INVALID'
        }
        $executablePaths += $executablePath
    }

    foreach ($executablePath in $executablePaths) {
        $signature = Get-AuthenticodeSignature -LiteralPath $executablePath
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            [string]$signature.SignerCertificate.Subject -notmatch [string]$manifest.postgresql.integrity.required_executable_authenticode_subject_regex) {
            throw 'POSTGRES_EXECUTABLE_SIGNATURE_INVALID'
        }
    }
    # Execute only publisher-signed files. All four must report the exact pin
    # before any final move into the versioned toolchain root.
    Assert-ThriveLensPostgresVersions -BinaryRoot $expandedRoot

    $null = New-Item -ItemType Directory -Path $targetVersionRoot -Force
    Move-Item -LiteralPath $expandedRoot -Destination $paths.BinaryRoot
    $response = [pscustomobject]@{
        schema_version = 1
        status = 'INSTALLED_PENDING_RUNTIME_PROOF'
        version = [string]$manifest.postgresql.version
        archive_entries = [int]$archiveScan.Entries
        extracted_entries = [int]$expandedScan.Entries
        extracted_bytes = [int64]$expandedScan.Bytes
    }
}
catch {
    $allowed = @(
        'WINDOWS_POSTGRES_INSTALL_DISABLED',
        'POSTGRES_TARGET_ALREADY_EXISTS',
        'ARCHIVE_ENTRY_LIMIT_EXCEEDED',
        'ARCHIVE_LIMIT_INVALID',
        'ARCHIVE_PATH_REJECTED',
        'ARCHIVE_LAYOUT_REJECTED',
        'ARCHIVE_DUPLICATE_PATH_REJECTED',
        'ARCHIVE_CONTAINMENT_REJECTED',
        'ARCHIVE_LINK_OR_SPECIAL_ENTRY_REJECTED',
        'ARCHIVE_SIZE_OVERFLOW',
        'ARCHIVE_UNCOMPRESSED_SIZE_EXCEEDED',
        'POSTGRES_ARCHIVE_LAYOUT_INVALID',
        'SAFE_TREE_ENTRY_LIMIT_EXCEEDED',
        'SAFE_TREE_LIMIT_INVALID',
        'SAFE_TREE_REPARSE_REJECTED',
        'SAFE_TREE_SIZE_OVERFLOW',
        'SAFE_TREE_SIZE_EXCEEDED',
        'POSTGRES_VERSION_OUTPUT_MISMATCH',
        'POSTGRES_VERSION_EXECUTION_FAILED',
        'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE',
        'POSTGRES_EXECUTABLE_SIGNATURE_INVALID'
    )
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'POSTGRES_INSTALL_INTERNAL_ERROR' }
    $response = [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code }
    $resultExitCode = 2
}
finally {
    if ($null -ne $stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
        try {
            $validatedStaging = Assert-ThriveLensOwnedPath -Path $stagingRoot
            Remove-Item -LiteralPath $validatedStaging -Recurse -Force
        }
        catch {
            $response = [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'POSTGRES_STAGING_CLEANUP_FAILED' }
            $resultExitCode = 3
        }
    }
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
