#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ArtifactPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot '..\..\dev\postgres\Runtime.psm1'
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
    $verification = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify_artifact.ps1') -Kind Python -Path $ArtifactPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        $verification | Write-Output
        exit $LASTEXITCODE
    }

    $manifest = Get-ThriveLensManifest
    $artifact = Assert-ThriveLensOwnedPath -Path $ArtifactPath
    $target = Assert-ThriveLensOwnedPath -Path ([string]$manifest.python.install_root) -AllowMissing
    if (Test-Path -LiteralPath $target) {
        throw 'PYTHON_TARGET_ALREADY_EXISTS'
    }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force
    $arguments = @(
        '/quiet',
        'InstallAllUsers=0',
        "TargetDir=`"$target`"",
        'AssociateFiles=0',
        'Shortcuts=0',
        'Include_doc=0',
        'Include_launcher=0',
        'Include_test=0',
        'Include_tcltk=0',
        'Include_pip=1',
        'Include_tools=1',
        'PrependPath=0',
        'AppendPath=0'
    )
    $mutationStarted = $true
    $process = Start-Process -FilePath $artifact -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw 'PYTHON_INSTALLER_FAILED'
    }
    $python = Join-Path $target 'python.exe'
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw 'PYTHON_INSTALL_INCOMPLETE'
    }
    $version = & $python '--version' 2>&1
    if ($LASTEXITCODE -ne 0 -or [string]$version -cne ('Python ' + [string]$manifest.python.version)) {
        throw 'PYTHON_VERSION_MISMATCH'
    }
    $installedBytes = Measure-TreeBytes -Root $target
    if ($installedBytes -gt [int64]$manifest.python.maximum_installed_bytes) {
        throw 'PYTHON_INSTALLED_SIZE_EXCEEDED'
    }
    [pscustomobject]@{ schema_version = 1; status = 'INSTALLED'; version = [string]$manifest.python.version; installed_bytes = $installedBytes; machine_path_modified = $false } | ConvertTo-Json -Compress
}
catch {
    $allowed = @('PYTHON_TARGET_ALREADY_EXISTS', 'PYTHON_INSTALLER_FAILED', 'PYTHON_INSTALL_INCOMPLETE', 'PYTHON_VERSION_MISMATCH', 'PYTHON_INSTALLED_SIZE_EXCEEDED')
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'PYTHON_INSTALL_INTERNAL_ERROR' }
    [pscustomobject]@{ schema_version = 1; status = 'BLOCKED'; code = $code } | ConvertTo-Json -Compress
    exit 2
}
finally {
    if ($mutationStarted) {
        try { Invoke-ThriveLensResourceGate }
        catch {
            [Console]::Error.WriteLine('Post-install resource gate failed closed. code=RESOURCE_GATE_FAILED')
            exit 3
        }
    }
}
