#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Python', 'PostgreSQL')]
    [string]$Kind,
    [Parameter(Mandatory)]
    [string]$Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\..\dev\postgres\Runtime.psm1'

try {
    Import-Module -Name $modulePath -Force
    $manifest = Get-ThriveLensManifest
    if ($Kind -eq 'PostgreSQL' -and
        ([string]$manifest.postgresql.portable_status -ceq 'REJECTED_FOR_RUNTIME' -or
        -not [bool]$manifest.postgresql.windows_portable_install_enabled)) {
        throw 'POSTGRES_WINDOWS_ARTIFACT_REJECTED'
    }
    $artifactPath = Assert-ThriveLensOwnedPath -Path $Path
    if (-not (Test-Path -LiteralPath $artifactPath -PathType Leaf)) {
        throw 'ARTIFACT_UNAVAILABLE'
    }

    $spec = if ($Kind -eq 'Python') { $manifest.python } else { $manifest.postgresql }
    if ([IO.Path]::GetFileName($artifactPath) -cne [string]$spec.artifact_filename) {
        throw 'ARTIFACT_FILENAME_MISMATCH'
    }
    $file = Get-Item -LiteralPath $artifactPath
    if ([int64]$file.Length -ne [int64]$spec.compressed_bytes) {
        throw 'ARTIFACT_SIZE_MISMATCH'
    }
    if ($null -eq $spec.integrity.value -or [string]::IsNullOrWhiteSpace([string]$spec.integrity.value)) {
        throw 'PUBLISHER_INTEGRITY_ATTESTATION_UNAVAILABLE'
    }
    $expectedHash = [string]$spec.integrity.value
    if ($expectedHash -notmatch '^[0-9a-f]{64}$') {
        throw 'EXPECTED_HASH_INVALID'
    }
    $actualHash = (Get-FileHash -LiteralPath $artifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualHash -cne $expectedHash) {
        throw 'ARTIFACT_HASH_MISMATCH'
    }

    if ($Kind -eq 'Python') {
        $signature = Get-AuthenticodeSignature -LiteralPath $artifactPath
        if ($signature.Status -ne [Management.Automation.SignatureStatus]::Valid -or
            [string]$signature.SignerCertificate.Subject -notlike '*Python Software Foundation*') {
            throw 'PYTHON_AUTHENTICODE_INVALID'
        }
    }

    [pscustomobject]@{
        schema_version = 1
        status = 'VERIFIED'
        kind = $Kind
        algorithm = 'SHA-256'
        publisher_signature_checked = ($Kind -eq 'Python')
    } | ConvertTo-Json -Compress
}
catch {
    $allowed = @(
        'ARTIFACT_UNAVAILABLE',
        'POSTGRES_WINDOWS_ARTIFACT_REJECTED',
        'ARTIFACT_FILENAME_MISMATCH',
        'ARTIFACT_SIZE_MISMATCH',
        'PUBLISHER_INTEGRITY_ATTESTATION_UNAVAILABLE',
        'EXPECTED_HASH_INVALID',
        'ARTIFACT_HASH_MISMATCH',
        'PYTHON_AUTHENTICODE_INVALID'
    )
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'ARTIFACT_VERIFICATION_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; kind = $Kind; code = $code } | ConvertTo-Json -Compress
    exit 2
}
