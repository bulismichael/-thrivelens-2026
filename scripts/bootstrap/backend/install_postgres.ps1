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
$targetVersionRoot = $null
$mutationStarted = $false

function Measure-TreeBytes {
    param([Parameter(Mandatory)][string]$Root)
    $sum = [int64]0
    foreach ($file in Get-ChildItem -LiteralPath $Root -File -Recurse -Force) {
        $sum += [int64]$file.Length
    }
    return $sum
}

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\..\dev\postgres\preflight.ps1') -Action Install 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    $verification = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify_artifact.ps1') -Kind PostgreSQL -Path $ArtifactPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $verification | Write-Output
        exit $LASTEXITCODE
    }

    $manifest = Get-ThriveLensManifest
    $artifact = Assert-ThriveLensOwnedPath -Path $ArtifactPath
    $paths = Get-ThriveLensPostgresPaths
    $targetVersionRoot = Split-Path -Parent $paths.BinaryRoot
    $targetVersionRoot = Assert-ThriveLensOwnedPath -Path $targetVersionRoot -AllowMissing
    if (Test-Path -LiteralPath $targetVersionRoot) {
        throw 'POSTGRES_TARGET_ALREADY_EXISTS'
    }

    $stagingParent = Assert-ThriveLensOwnedPath -Path ((Join-Path (Get-ThriveLensAttributableRoot) 'staging')) -AllowMissing
    $stagingRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $stagingParent ('postgres-' + [guid]::NewGuid().ToString('N'))) -AllowMissing
    $null = New-Item -ItemType Directory -Path $stagingRoot -Force
    $mutationStarted = $true
    Expand-Archive -LiteralPath $artifact -DestinationPath $stagingRoot
    $expandedRoot = Join-Path $stagingRoot 'pgsql'
    foreach ($relative in @('bin\postgres.exe', 'bin\pg_ctl.exe', 'bin\initdb.exe', 'bin\pg_isready.exe')) {
        if (-not (Test-Path -LiteralPath (Join-Path $expandedRoot $relative) -PathType Leaf)) {
            throw 'POSTGRES_ARCHIVE_LAYOUT_INVALID'
        }
    }
    $expandedBytes = Measure-TreeBytes -Root $expandedRoot
    if ($expandedBytes -gt [int64]$manifest.postgresql.maximum_extracted_binary_bytes) {
        throw 'POSTGRES_EXTRACTED_SIZE_EXCEEDED'
    }
    foreach ($relative in @('bin\postgres.exe', 'bin\pg_ctl.exe', 'bin\initdb.exe')) {
        $signature = Get-AuthenticodeSignature -LiteralPath (Join-Path $expandedRoot $relative)
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            [string]$signature.SignerCertificate.Subject -notmatch [string]$manifest.postgresql.integrity.required_executable_authenticode_subject_regex) {
            throw 'POSTGRES_EXECUTABLE_SIGNATURE_INVALID'
        }
    }

    $null = New-Item -ItemType Directory -Path $targetVersionRoot -Force
    Move-Item -LiteralPath $expandedRoot -Destination $paths.BinaryRoot
    [pscustomobject]@{ schema_version = 1; status = 'INSTALLED_PENDING_RUNTIME_PROOF'; version = [string]$manifest.postgresql.version; extracted_bytes = $expandedBytes } | ConvertTo-Json -Compress
}
catch {
    $allowed = @('POSTGRES_TARGET_ALREADY_EXISTS', 'POSTGRES_ARCHIVE_LAYOUT_INVALID', 'POSTGRES_EXTRACTED_SIZE_EXCEEDED', 'POSTGRES_EXECUTABLE_SIGNATURE_INVALID')
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'POSTGRES_INSTALL_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
finally {
    if ($null -ne $stagingRoot -and (Test-Path -LiteralPath $stagingRoot)) {
        $validatedStaging = Assert-ThriveLensOwnedPath -Path $stagingRoot
        Remove-Item -LiteralPath $validatedStaging -Recurse -Force
    }
    if ($mutationStarted) {
        try { Invoke-ThriveLensResourceGate }
        catch {
            [Console]::Error.WriteLine('Post-install resource gate failed closed. code=RESOURCE_GATE_FAILED')
            exit 3
        }
    }
}
