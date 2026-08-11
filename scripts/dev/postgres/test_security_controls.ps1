#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$failures = [Collections.Generic.List[string]]::new()
$assertionCount = 0
$fixtureRoot = $null

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    $script:assertionCount++
    if (-not $Condition) { $script:failures.Add($Code) }
}

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Code
    )
    $observed = $null
    try { & $Action | Out-Null }
    catch { $observed = $_.Exception.Message }
    Assert-Condition ($observed -ceq $Expected) $Code
}

function New-TestZip {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][object[]]$Entries
    )
    $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            foreach ($spec in $Entries) {
                $entry = $zip.CreateEntry([string]$spec.Name)
                if ($null -ne $spec.ExternalAttributes) {
                    $entry.ExternalAttributes = [int]$spec.ExternalAttributes
                }
                if ($null -ne $spec.Content) {
                    $bytes = [Text.Encoding]::UTF8.GetBytes([string]$spec.Content)
                    $entryStream = $entry.Open()
                    try { $entryStream.Write($bytes, 0, $bytes.Length) }
                    finally { $entryStream.Dispose() }
                }
            }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

try {
    Import-Module -Name $modulePath -Force
    Add-Type -AssemblyName System.IO.Compression
    $attributableRoot = Get-ThriveLensAttributableRoot
    $fixtureParent = Assert-ThriveLensOwnedPath -Path (Join-Path $attributableRoot 'test-temp') -AllowMissing
    $fixtureRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $fixtureParent ('security-' + [guid]::NewGuid().ToString('N'))) -AllowMissing
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force
    $destination = Assert-ThriveLensOwnedPath -Path (Join-Path $fixtureRoot 'extract') -AllowMissing

    $goodZip = Join-Path $fixtureRoot 'good.zip'
    New-TestZip -Path $goodZip -Entries @(
        [pscustomobject]@{ Name = 'pgsql/'; Content = $null; ExternalAttributes = $null },
        [pscustomobject]@{ Name = 'pgsql/bin/postgres.exe'; Content = 'x'; ExternalAttributes = $null }
    )
    $goodScan = Assert-ThriveLensPostgresArchive -ArchivePath $goodZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 10
    Assert-Condition ($goodScan.Entries -eq 2 -and $goodScan.UncompressedBytes -eq 1) 'GOOD_ARCHIVE_SCAN'

    $traversalZip = Join-Path $fixtureRoot 'traversal.zip'
    New-TestZip -Path $traversalZip -Entries @(
        [pscustomobject]@{ Name = 'pgsql/../escape'; Content = 'x'; ExternalAttributes = $null }
    )
    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $traversalZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 10 } `
        'ARCHIVE_PATH_REJECTED' 'ARCHIVE_TRAVERSAL_REJECTED'

    $duplicateZip = Join-Path $fixtureRoot 'duplicate.zip'
    New-TestZip -Path $duplicateZip -Entries @(
        [pscustomobject]@{ Name = 'pgsql/a'; Content = 'x'; ExternalAttributes = $null },
        [pscustomobject]@{ Name = 'pgsql/A'; Content = 'y'; ExternalAttributes = $null }
    )
    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $duplicateZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 10 } `
        'ARCHIVE_DUPLICATE_PATH_REJECTED' 'ARCHIVE_CASE_COLLISION_REJECTED'

    $symlinkUnsigned = [uint32]::Parse('A1FF0000', [Globalization.NumberStyles]::HexNumber)
    $symlinkAttributes = [BitConverter]::ToInt32([BitConverter]::GetBytes($symlinkUnsigned), 0)
    $symlinkZip = Join-Path $fixtureRoot 'symlink.zip'
    New-TestZip -Path $symlinkZip -Entries @(
        [pscustomobject]@{ Name = 'pgsql/link'; Content = 'target'; ExternalAttributes = $symlinkAttributes }
    )
    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $symlinkZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 10 } `
        'ARCHIVE_LINK_OR_SPECIAL_ENTRY_REJECTED' 'ARCHIVE_SYMLINK_REJECTED'

    $reparseZip = Join-Path $fixtureRoot 'reparse.zip'
    New-TestZip -Path $reparseZip -Entries @(
        [pscustomobject]@{ Name = 'pgsql/reparse'; Content = 'x'; ExternalAttributes = [int][IO.FileAttributes]::ReparsePoint }
    )
    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $reparseZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 10 } `
        'ARCHIVE_LINK_OR_SPECIAL_ENTRY_REJECTED' 'ARCHIVE_REPARSE_REJECTED'

    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $goodZip -DestinationRoot $destination -MaximumEntries 1 -MaximumUncompressedBytes 10 } `
        'ARCHIVE_ENTRY_LIMIT_EXCEEDED' 'ARCHIVE_ENTRY_CEILING'
    Assert-ThrowsCode { Assert-ThriveLensPostgresArchive -ArchivePath $goodZip -DestinationRoot $destination -MaximumEntries 10 -MaximumUncompressedBytes 0 } `
        'ARCHIVE_UNCOMPRESSED_SIZE_EXCEEDED' 'ARCHIVE_SIZE_CEILING'

    $treeRoot = Join-Path $fixtureRoot 'safe-tree'
    $null = New-Item -ItemType Directory -Path $treeRoot
    [IO.File]::WriteAllBytes((Join-Path $treeRoot 'three.bin'), [byte[]](1, 2, 3))
    $treeScan = Measure-ThriveLensSafeTree -Root $treeRoot -MaximumBytes 3 -MaximumEntries 1
    Assert-Condition ($treeScan.Bytes -eq 3 -and $treeScan.Entries -eq 1) 'SAFE_TREE_EXACT_CEILING'
    Assert-ThrowsCode { Measure-ThriveLensSafeTree -Root $treeRoot -MaximumBytes 2 -MaximumEntries 1 } `
        'SAFE_TREE_SIZE_EXCEEDED' 'SAFE_TREE_SIZE_REJECTED'

    $outsidePath = Join-Path ([IO.Path]::GetPathRoot($attributableRoot)) 'Windows'
    Assert-ThrowsCode { Assert-ThriveLensOwnedPath -Path $outsidePath -AllowMissing } `
        'PATH_OUTSIDE_ATTRIBUTABLE_ROOT' 'OUTSIDE_PATH_REJECTED'

    $null = Assert-ThriveLensProjectedBudget -AccountedBytes 800 -AdditionalBytes 49 -CapBytes 1000 -HardStopPercent 85
    Assert-Condition $true 'PROJECTED_BELOW_HIGH_WATER'
    Assert-ThrowsCode { Assert-ThriveLensProjectedBudget -AccountedBytes 800 -AdditionalBytes 50 -CapBytes 1000 -HardStopPercent 85 } `
        'PROJECTED_RESOURCE_HARD_STOP' 'PROJECTED_85_PERCENT_REJECTED'
    Assert-ThrowsCode { Assert-ThriveLensProjectedBudget -AccountedBytes 900 -AdditionalBytes 100 -CapBytes 1000 -HardStopPercent 85 } `
        'PROJECTED_RESOURCE_CAP_EXCEEDED' 'PROJECTED_CAP_REJECTED'
    $null = Assert-ThriveLensFreeDiskBudget -FreeDiskBytes 150 -AdditionalBytes 100 -ReserveBytes 50
    Assert-Condition $true 'PROJECTED_FREE_DISK_EXACT_CEILING'
    Assert-ThrowsCode { Assert-ThriveLensFreeDiskBudget -FreeDiskBytes 149 -AdditionalBytes 100 -ReserveBytes 50 } `
        'PROJECTED_FREE_DISK_INSUFFICIENT' 'PROJECTED_FREE_DISK_REJECTED'

    foreach ($tool in @('postgres', 'pg_ctl', 'initdb', 'pg_isready')) {
        Assert-ThriveLensVersionText -Tool $tool -Observed "$tool (PostgreSQL) 17.10" -Version '17.10'
        Assert-Condition $true ('EXACT_VERSION_' + $tool)
    }
    Assert-ThrowsCode { Assert-ThriveLensVersionText -Tool postgres -Observed 'postgres (PostgreSQL) 17.10 extra' -Version '17.10' } `
        'POSTGRES_VERSION_OUTPUT_MISMATCH' 'VERSION_SUFFIX_REJECTED'

    $secretPath = Join-Path $fixtureRoot 'secret.txt'
    [IO.File]::WriteAllText($secretPath, 'synthetic-test-only')
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    $aclOutput = @(& icacls.exe $secretPath '/inheritance:r' '/grant:r' ("*$($currentSid.Value):(F)") 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'SYNTHETIC_ACL_SETUP_FAILED' }
    $aclOutput = $null
    Assert-ThriveLensSecretFileAcl -Path $secretPath
    Assert-Condition $true 'STRICT_SECRET_ACL_ACCEPTED'

    $aclOutput = @(& icacls.exe $secretPath '/grant' '*S-1-1-0:(R)' 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'SYNTHETIC_ACL_MUTATION_FAILED' }
    $aclOutput = $null
    Assert-ThrowsCode { Assert-ThriveLensSecretFileAcl -Path $secretPath } `
        'SECRET_ACL_READ_ALLOWLIST_VIOLATION' 'BROAD_SECRET_READ_REJECTED'

    if ($failures.Count -gt 0) {
        [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) } | ConvertTo-Json -Compress
        exit 1
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; assertions = $assertionCount } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'SECURITY_CONTROL_TEST_INTERNAL_ERROR' } | ConvertTo-Json -Compress
    exit 2
}
finally {
    if ($null -ne $fixtureRoot -and (Test-Path -LiteralPath $fixtureRoot)) {
        try {
            $validatedFixtureRoot = Assert-ThriveLensOwnedPath -Path $fixtureRoot
            Remove-Item -LiteralPath $validatedFixtureRoot -Recurse -Force
        }
        catch { [Console]::Error.WriteLine('Synthetic security fixture cleanup failed closed.') }
    }
}
