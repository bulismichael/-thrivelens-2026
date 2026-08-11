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
$response = $null
$resultExitCode = 0

try {
    Import-Module -Name $modulePath -Force
    $preflight = & pwsh -NoProfile -File (Join-Path $PSScriptRoot '..\..\dev\postgres\preflight.ps1') `
        -Action Install -InstallKind Python 2>&1
    if ($LASTEXITCODE -ne 0) {
        $preflight | Write-Output
        exit $LASTEXITCODE
    }
    $verification = & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'verify_artifact.ps1') `
        -Kind Python -Path $ArtifactPath 2>&1
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
    $targetParent = Assert-ThriveLensOwnedPath -Path (Split-Path -Parent $target) -AllowMissing
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
    $null = New-Item -ItemType Directory -Path $targetParent -Force
    $process = Start-Process -FilePath $artifact -ArgumentList $arguments -Wait -PassThru -WindowStyle Hidden
    if ($process.ExitCode -ne 0) {
        throw 'PYTHON_INSTALLER_FAILED'
    }
    $python = Assert-ThriveLensOwnedPath -Path (Join-Path $target 'python.exe')
    if (-not (Test-Path -LiteralPath $python -PathType Leaf)) {
        throw 'PYTHON_INSTALL_INCOMPLETE'
    }
    $version = @(& $python '--version' 2>&1) -join [Environment]::NewLine
    if ($LASTEXITCODE -ne 0 -or $version.Trim() -cne ('Python ' + [string]$manifest.python.version)) {
        throw 'PYTHON_VERSION_MISMATCH'
    }
    $installedScan = Measure-ThriveLensSafeTree `
        -Root $target `
        -MaximumBytes ([int64]$manifest.python.maximum_installed_bytes) `
        -MaximumEntries 50000
    $response = [pscustomobject]@{
        schema_version = 1
        status = 'INSTALLED'
        version = [string]$manifest.python.version
        installed_bytes = [int64]$installedScan.Bytes
        installed_entries = [int]$installedScan.Entries
        machine_path_modified = $false
    }
}
catch {
    $allowed = @(
        'PYTHON_TARGET_ALREADY_EXISTS',
        'PYTHON_INSTALLER_FAILED',
        'PYTHON_INSTALL_INCOMPLETE',
        'PYTHON_VERSION_MISMATCH',
        'SAFE_TREE_LIMIT_INVALID',
        'SAFE_TREE_ENTRY_LIMIT_EXCEEDED',
        'SAFE_TREE_REPARSE_REJECTED',
        'SAFE_TREE_SIZE_OVERFLOW',
        'SAFE_TREE_SIZE_EXCEEDED'
    )
    $code = if ($allowed -contains $_.Exception.Message) { $_.Exception.Message } else { 'PYTHON_INSTALL_INTERNAL_ERROR' }
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
