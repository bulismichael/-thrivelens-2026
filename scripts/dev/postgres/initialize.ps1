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

function Assert-SecretFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    $unsafeSidTypes = @(
        [Security.Principal.WellKnownSidType]::WorldSid,
        [Security.Principal.WellKnownSidType]::AuthenticatedUserSid,
        [Security.Principal.WellKnownSidType]::BuiltinUsersSid,
        [Security.Principal.WellKnownSidType]::AnonymousSid
    )
    $readMask = [Security.AccessControl.FileSystemRights]::Read -bor [Security.AccessControl.FileSystemRights]::ReadAndExecute -bor [Security.AccessControl.FileSystemRights]::FullControl
    $acl = Get-Acl -LiteralPath $Path
    foreach ($rule in $acl.Access) {
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            ($rule.FileSystemRights -band $readMask) -eq 0) {
            continue
        }
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]) }
        catch { throw 'PASSWORD_FILE_ACL_UNVERIFIABLE' }
        foreach ($sidType in $unsafeSidTypes) {
            if ($sid.IsWellKnown($sidType)) { throw 'PASSWORD_FILE_ACL_TOO_BROAD' }
        }
    }
}

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Initialize 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    $paths = Get-ThriveLensPostgresPaths
    if (Test-Path -LiteralPath $paths.DataRoot) {
        throw 'CLUSTER_ALREADY_EXISTS'
    }
    if (-not (Test-Path -LiteralPath $PasswordFile -PathType Leaf)) {
        throw 'PASSWORD_FILE_UNAVAILABLE'
    }
    $passwordPath = Assert-ThriveLensOwnedPath -Path $PasswordFile
    Assert-SecretFileAcl -Path $passwordPath
    $passwordContent = Get-Content -LiteralPath $passwordPath -Raw
    if ([string]::IsNullOrWhiteSpace($passwordContent)) {
        throw 'PASSWORD_FILE_EMPTY'
    }
    if ($BootstrapUser -notmatch '^[a-z][a-z0-9_]{2,31}$') {
        throw 'BOOTSTRAP_USER_INVALID'
    }

    $parent = Split-Path -Parent $paths.DataRoot
    $null = New-Item -ItemType Directory -Path $parent -Force
    $null = & $paths.InitDb '--pgdata' $paths.DataRoot '--username' $BootstrapUser '--pwfile' $passwordPath '--auth-host=scram-sha-256' '--auth-local=scram-sha-256' '--encoding=UTF8' '--locale=C' '--data-checksums' '--no-instructions' 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'INITDB_FAILED'
    }
    [pscustomobject]@{ schema_version = 1; status = 'INITIALIZED'; authentication = 'scram-sha-256'; data_checksums = $true } | ConvertTo-Json -Compress
}
catch {
    $allowed = @('CLUSTER_ALREADY_EXISTS', 'PASSWORD_FILE_UNAVAILABLE', 'PASSWORD_FILE_EMPTY', 'PASSWORD_FILE_ACL_UNVERIFIABLE', 'PASSWORD_FILE_ACL_TOO_BROAD', 'BOOTSTRAP_USER_INVALID', 'INITDB_FAILED')
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'INITIALIZE_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
