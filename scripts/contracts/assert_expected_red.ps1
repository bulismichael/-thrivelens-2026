[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string] $Manifest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))

try {
    Import-Module (Join-Path $PSScriptRoot 'ExpectedRedHarness.psm1') -Force
    $canonicalManifest = (Resolve-Path -LiteralPath (Join-Path $repositoryRoot 'tests\contracts\expected-red.json')).Path
    $requestedManifest = (Resolve-Path -LiteralPath $Manifest).Path
    if (-not $requestedManifest.Equals($canonicalManifest, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Only the canonical expected-red manifest may be executed.'
    }
    & python (Join-Path $PSScriptRoot 'validate_openapi.py')
    if ($LASTEXITCODE -ne 0) {
        throw 'Canonical contract and manifest validation failed.'
    }
    $loaded = Read-ExpectedRedManifest -ManifestPath $Manifest
    $count = Invoke-ExpectedRedEntries -Entries $loaded.Entries
    Write-Output "TL-R0-002 expected-red PASS: $count named tests failed only for their frozen missing implementation."
    exit 0
}
catch {
    $safeMessage = $_.Exception.Message.Replace($repositoryRoot, '<repository>')
    $safeMessage = [regex]::Replace($safeMessage, '(?i)[A-Z]:\\[^\r\n]+', '<path>')
    Write-Error ("TL-R0-002 expected-red FAILED: " + $safeMessage)
    exit 1
}
