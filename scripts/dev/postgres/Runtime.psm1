#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ThriveLensProjectRoot {
    $root = Join-Path $PSScriptRoot '..\..\..'
    return (Resolve-Path -LiteralPath $root).Path
}

function Get-ThriveLensManifest {
    $manifestPath = Join-Path (Get-ThriveLensProjectRoot) 'config\toolchains\backend.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'BACKEND_MANIFEST_UNAVAILABLE'
    }
    try {
        return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw 'BACKEND_MANIFEST_INVALID'
    }
}

function Get-ThriveLensAttributableRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA_UNAVAILABLE'
    }
    $root = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens'))
    $volumeRoot = [IO.Path]::GetPathRoot($root)
    if ([string]::IsNullOrWhiteSpace($volumeRoot) -or $root.TrimEnd('\') -ieq $volumeRoot.TrimEnd('\')) {
        throw 'ATTRIBUTABLE_ROOT_UNSAFE'
    }
    $root = $root.TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) {
        throw 'ATTRIBUTABLE_ROOT_UNAVAILABLE'
    }
    $rootItem = Get-Item -LiteralPath $root -Force
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'ATTRIBUTABLE_ROOT_REPARSE_REJECTED'
    }
    return $root
}

function Assert-ThriveLensOwnedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$AllowMissing
    )

    $root = Get-ThriveLensAttributableRoot
    $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if ($candidate -ine $root -and -not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PATH_OUTSIDE_ATTRIBUTABLE_ROOT'
    }

    $relative = [IO.Path]::GetRelativePath($root, $candidate)
    $cursor = $root
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'REPARSE_PATH_REJECTED'
            }
        }
        elseif (-not $AllowMissing) {
            throw 'REQUIRED_PATH_UNAVAILABLE'
        }
    }
    return $candidate
}

function Get-ThriveLensPostgresPaths {
    $manifest = Get-ThriveLensManifest
    $binaryRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.binary_root) -AllowMissing
    $dataRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.data_root) -AllowMissing
    $logRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.log_root) -AllowMissing
    $paths = [pscustomobject]@{
        BinaryRoot = $binaryRoot
        DataRoot = $dataRoot
        LogRoot = $logRoot
        PgCtl = Join-Path $binaryRoot 'bin\pg_ctl.exe'
        InitDb = Join-Path $binaryRoot 'bin\initdb.exe'
        Postgres = Join-Path $binaryRoot 'bin\postgres.exe'
        PgIsReady = Join-Path $binaryRoot 'bin\pg_isready.exe'
        Port = [int]$manifest.postgresql.port
        ListenAddress = [string]$manifest.postgresql.listen_address
    }
    foreach ($path in @($paths.PgCtl, $paths.InitDb, $paths.Postgres, $paths.PgIsReady)) {
        $null = Assert-ThriveLensOwnedPath -Path $path -AllowMissing
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw 'POSTGRES_EXECUTABLE_TARGET_INVALID'
        }
    }
    foreach ($path in @($paths.BinaryRoot, $paths.DataRoot, $paths.LogRoot)) {
        if ((Test-Path -LiteralPath $path) -and -not (Test-Path -LiteralPath $path -PathType Container)) {
            throw 'POSTGRES_DIRECTORY_TARGET_INVALID'
        }
    }
    return $paths
}

function Get-ThriveLensFreeMemoryBytes {
    if (-not $IsWindows) {
        throw 'WINDOWS_HOST_REQUIRED'
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [int64]$os.FreePhysicalMemory * 1KB
    }
    catch {
        throw 'MEMORY_MEASUREMENT_UNAVAILABLE'
    }
}

function Get-ThriveLensResourcePhase {
    $configPath = Join-Path (Get-ThriveLensProjectRoot) 'config\resource-budget.json'
    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        return [string]$config.phase
    }
    catch {
        throw 'RESOURCE_CONFIG_INVALID'
    }
}

function Assert-ThriveLensProjectedBudget {
    param(
        [Parameter(Mandatory)][int64]$AccountedBytes,
        [Parameter(Mandatory)][int64]$AdditionalBytes,
        [Parameter(Mandatory)][int64]$CapBytes,
        [Parameter(Mandatory)][int]$HardStopPercent
    )
    if ($AccountedBytes -lt 0 -or $AdditionalBytes -lt 0 -or $CapBytes -le 0 -or
        $HardStopPercent -le 0 -or $HardStopPercent -ge 100 -or
        $AdditionalBytes -gt ([int64]::MaxValue - $AccountedBytes)) {
        throw 'PROJECTED_RESOURCE_INPUT_INVALID'
    }
    $projectedBytes = $AccountedBytes + $AdditionalBytes
    if ($projectedBytes -ge $CapBytes) {
        throw 'PROJECTED_RESOURCE_CAP_EXCEEDED'
    }
    if (([decimal]$projectedBytes * 100) -ge ([decimal]$CapBytes * $HardStopPercent)) {
        throw 'PROJECTED_RESOURCE_HARD_STOP'
    }
    return $projectedBytes
}

function Assert-ThriveLensFreeDiskBudget {
    param(
        [Parameter(Mandatory)][int64]$FreeDiskBytes,
        [Parameter(Mandatory)][int64]$AdditionalBytes,
        [Parameter(Mandatory)][int64]$ReserveBytes
    )
    if ($FreeDiskBytes -lt 0 -or $AdditionalBytes -lt 0 -or $ReserveBytes -lt 0 -or
        $ReserveBytes -gt ([int64]::MaxValue - $AdditionalBytes)) {
        throw 'PROJECTED_FREE_DISK_INPUT_INVALID'
    }
    $requiredFreeBytes = $AdditionalBytes + $ReserveBytes
    if ($FreeDiskBytes -lt $requiredFreeBytes) {
        throw 'PROJECTED_FREE_DISK_INSUFFICIENT'
    }
    return $requiredFreeBytes
}

function Invoke-ThriveLensResourceGate {
    param([int64]$ProjectedAdditionalBytes = 0)

    $scriptPath = Join-Path (Get-ThriveLensProjectRoot) 'scripts\check_resource_budget.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw 'RESOURCE_GATE_UNAVAILABLE'
    }
    $output = @(& pwsh -NoProfile -File $scriptPath 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'RESOURCE_GATE_FAILED'
    }
    $text = $output -join [Environment]::NewLine
    $start = $text.IndexOf('{')
    $end = $text.LastIndexOf('}')
    if ($start -lt 0 -or $end -le $start) {
        throw 'RESOURCE_GATE_RESULT_INVALID'
    }
    try { $result = $text.Substring($start, $end - $start + 1) | ConvertFrom-Json }
    catch { throw 'RESOURCE_GATE_RESULT_INVALID' }

    $manifest = Get-ThriveLensManifest
    $capBytes = [int64]$manifest.resource_policy.aggregate_cap_bytes
    $projectedBytes = Assert-ThriveLensProjectedBudget `
        -AccountedBytes ([int64]$result.accounted_bytes) `
        -AdditionalBytes $ProjectedAdditionalBytes `
        -CapBytes $capBytes `
        -HardStopPercent ([int]$manifest.resource_policy.hard_stop_percent)

    $root = Get-ThriveLensAttributableRoot
    $driveName = ([IO.Path]::GetPathRoot($root)).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction Stop
    $null = Assert-ThriveLensFreeDiskBudget `
        -FreeDiskBytes ([int64]$drive.Free) `
        -AdditionalBytes $ProjectedAdditionalBytes `
        -ReserveBytes ([int64]$manifest.resource_policy.minimum_free_disk_reserve_bytes)
    return [pscustomobject]@{
        AccountedBytes = [int64]$result.accounted_bytes
        ProjectedBytes = $projectedBytes
        FreeDiskBytes = [int64]$drive.Free
    }
}

function Measure-ThriveLensSafeTree {
    param(
        [Parameter(Mandatory)][string]$Root,
        [int64]$MaximumBytes = [int64]::MaxValue,
        [int]$MaximumEntries = 100000
    )
    if ($MaximumBytes -lt 0 -or $MaximumEntries -le 0) {
        throw 'SAFE_TREE_LIMIT_INVALID'
    }
    $rootPath = Assert-ThriveLensOwnedPath -Path $Root
    if (-not (Test-Path -LiteralPath $rootPath -PathType Container)) {
        throw 'SAFE_TREE_ROOT_INVALID'
    }
    $pending = [Collections.Generic.Stack[string]]::new()
    $pending.Push($rootPath)
    $bytes = [int64]0
    $entries = 0
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($item in Get-ChildItem -LiteralPath $directory -Force) {
            $entries++
            if ($entries -gt $MaximumEntries) { throw 'SAFE_TREE_ENTRY_LIMIT_EXCEEDED' }
            $null = Assert-ThriveLensOwnedPath -Path $item.FullName
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'SAFE_TREE_REPARSE_REJECTED'
            }
            if ($item.PSIsContainer) {
                $pending.Push($item.FullName)
                continue
            }
            if ([int64]$item.Length -gt ([int64]::MaxValue - $bytes)) {
                throw 'SAFE_TREE_SIZE_OVERFLOW'
            }
            $bytes += [int64]$item.Length
            if ($bytes -gt $MaximumBytes) { throw 'SAFE_TREE_SIZE_EXCEEDED' }
        }
    }
    return [pscustomobject]@{ Bytes = $bytes; Entries = $entries }
}

function Assert-ThriveLensPostgresArchive {
    param(
        [Parameter(Mandatory)][string]$ArchivePath,
        [Parameter(Mandatory)][string]$DestinationRoot,
        [Parameter(Mandatory)][int]$MaximumEntries,
        [Parameter(Mandatory)][int64]$MaximumUncompressedBytes
    )
    if ($MaximumEntries -le 0 -or $MaximumUncompressedBytes -lt 0) {
        throw 'ARCHIVE_LIMIT_INVALID'
    }
    $archive = Assert-ThriveLensOwnedPath -Path $ArchivePath
    $destination = Assert-ThriveLensOwnedPath -Path $DestinationRoot -AllowMissing
    Add-Type -AssemblyName System.IO.Compression
    $stream = [IO.File]::Open($archive, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $zip = [IO.Compression.ZipArchive]::new($stream, [IO.Compression.ZipArchiveMode]::Read, $false)
        try {
            if ($zip.Entries.Count -le 0 -or $zip.Entries.Count -gt $MaximumEntries) {
                throw 'ARCHIVE_ENTRY_LIMIT_EXCEEDED'
            }
            $sum = [int64]0
            $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
            foreach ($entry in $zip.Entries) {
                $name = [string]$entry.FullName
                $normalized = $name.Replace('\', '/')
                if ([string]::IsNullOrWhiteSpace($normalized) -or $normalized -match '[\x00-\x1f]' -or
                    $normalized.StartsWith('/') -or $normalized.StartsWith('//') -or
                    $normalized -match ':' -or $normalized.Contains('//')) {
                    throw 'ARCHIVE_PATH_REJECTED'
                }
                $trimmed = $normalized.TrimEnd('/')
                $segments = @($trimmed.Split('/'))
                if ($segments.Count -eq 0 -or
                    @($segments | Where-Object {
                        [string]::IsNullOrWhiteSpace($_) -or $_ -in @('.', '..') -or
                        $_.EndsWith('.') -or $_.EndsWith(' ') -or
                        $_ -match '["<>|*?]' -or
                        $_ -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$'
                    }).Count -gt 0) {
                    throw 'ARCHIVE_PATH_REJECTED'
                }
                if ($trimmed -cne 'pgsql' -and -not $trimmed.StartsWith('pgsql/', [StringComparison]::Ordinal)) {
                    throw 'ARCHIVE_LAYOUT_REJECTED'
                }
                if (-not $seen.Add($trimmed)) {
                    throw 'ARCHIVE_DUPLICATE_PATH_REJECTED'
                }
                $candidate = [IO.Path]::GetFullPath((Join-Path $destination ($normalized.Replace('/', '\'))))
                $destinationPrefix = $destination.TrimEnd('\') + '\'
                if ($candidate.TrimEnd('\') -ine $destination.TrimEnd('\') -and
                    -not $candidate.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'ARCHIVE_CONTAINMENT_REJECTED'
                }
                $external = [BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$entry.ExternalAttributes), 0)
                $unixType = ($external -shr 16) -band 0xF000
                $dosAttributes = $external -band 0xFFFF
                if (($dosAttributes -band [uint32][IO.FileAttributes]::ReparsePoint) -ne 0 -or
                    $unixType -notin @(0, 0x4000, 0x8000)) {
                    throw 'ARCHIVE_LINK_OR_SPECIAL_ENTRY_REJECTED'
                }
                if ([int64]$entry.Length -gt ([int64]::MaxValue - $sum)) {
                    throw 'ARCHIVE_SIZE_OVERFLOW'
                }
                $sum += [int64]$entry.Length
                if ($sum -gt $MaximumUncompressedBytes) {
                    throw 'ARCHIVE_UNCOMPRESSED_SIZE_EXCEEDED'
                }
            }
            return [pscustomobject]@{ Entries = $zip.Entries.Count; UncompressedBytes = $sum }
        }
        finally { $zip.Dispose() }
    }
    finally { $stream.Dispose() }
}

function Assert-ThriveLensSecretFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $IsWindows) { throw 'SECRET_ACL_WINDOWS_REQUIRED' }
    $secretPath = Assert-ThriveLensOwnedPath -Path $Path
    if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) { throw 'SECRET_FILE_UNAVAILABLE' }
    $acl = Get-Acl -LiteralPath $secretPath
    if (-not $acl.AreAccessRulesProtected) { throw 'SECRET_ACL_INHERITANCE_ENABLED' }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowedSids = @($currentSid, 'S-1-5-18', 'S-1-5-32-544')
    $ownerSid = $acl.Owner
    try { $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch {
        try { $ownerSid = ([Security.Principal.SecurityIdentifier]$acl.Owner).Value }
        catch { throw 'SECRET_ACL_OWNER_UNVERIFIABLE' }
    }
    if ($allowedSids -notcontains $ownerSid) { throw 'SECRET_ACL_OWNER_REJECTED' }
    $readMask = [Security.AccessControl.FileSystemRights]::ReadData -bor
        [Security.AccessControl.FileSystemRights]::ReadAttributes -bor
        [Security.AccessControl.FileSystemRights]::ReadExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::ReadPermissions
    $currentUserCanRead = $false
    foreach ($rule in $acl.Access) {
        if ($rule.IsInherited) { throw 'SECRET_ACL_INHERITED_RULE_REJECTED' }
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
            ($rule.FileSystemRights -band $readMask) -eq 0) { continue }
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw 'SECRET_ACL_IDENTITY_UNVERIFIABLE' }
        if ($allowedSids -notcontains $sid) { throw 'SECRET_ACL_READ_ALLOWLIST_VIOLATION' }
        if ($sid -ceq $currentSid) { $currentUserCanRead = $true }
    }
    if (-not $currentUserCanRead) { throw 'SECRET_ACL_CURRENT_USER_READ_MISSING' }
    try {
        $probe = [IO.File]::Open($secretPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $probe.Dispose()
    }
    catch { throw 'SECRET_ACL_CURRENT_USER_READ_UNAVAILABLE' }
}

function Assert-ThriveLensVersionText {
    param(
        [Parameter(Mandatory)][ValidateSet('postgres', 'pg_ctl', 'initdb', 'pg_isready')][string]$Tool,
        [Parameter(Mandatory)][string]$Observed,
        [Parameter(Mandatory)][string]$Version
    )
    $expected = "$Tool (PostgreSQL) $Version"
    if ($Observed.Trim() -cne $expected) { throw 'POSTGRES_VERSION_OUTPUT_MISMATCH' }
}

function Assert-ThriveLensPostgresVersions {
    param([string]$BinaryRoot)

    $manifest = Get-ThriveLensManifest
    if ([string]::IsNullOrWhiteSpace($BinaryRoot)) {
        $paths = Get-ThriveLensPostgresPaths
        $resolvedBinaryRoot = $paths.BinaryRoot
    }
    else {
        $resolvedBinaryRoot = Assert-ThriveLensOwnedPath -Path $BinaryRoot
    }
    $tools = @(
        @{ Name = 'postgres'; Path = (Join-Path $resolvedBinaryRoot 'bin\postgres.exe') },
        @{ Name = 'pg_ctl'; Path = (Join-Path $resolvedBinaryRoot 'bin\pg_ctl.exe') },
        @{ Name = 'initdb'; Path = (Join-Path $resolvedBinaryRoot 'bin\initdb.exe') },
        @{ Name = 'pg_isready'; Path = (Join-Path $resolvedBinaryRoot 'bin\pg_isready.exe') }
    )
    foreach ($tool in $tools) {
        $toolPath = Assert-ThriveLensOwnedPath -Path $tool.Path
        if (-not (Test-Path -LiteralPath $toolPath -PathType Leaf)) {
            throw 'POSTGRES_VERSION_EXECUTABLE_UNAVAILABLE'
        }
        $observed = @(& $toolPath '--version' 2>$null)
        if ($LASTEXITCODE -ne 0) { throw 'POSTGRES_VERSION_EXECUTION_FAILED' }
        Assert-ThriveLensVersionText -Tool $tool.Name -Observed ($observed -join [Environment]::NewLine) -Version ([string]$manifest.postgresql.version)
    }
}

function Test-ThriveLensPostgresRunning {
    $paths = Get-ThriveLensPostgresPaths
    if (-not (Test-Path -LiteralPath $paths.PgCtl -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $paths.DataRoot 'PG_VERSION') -PathType Leaf)) {
        return $false
    }
    $null = & $paths.PgCtl status '-D' $paths.DataRoot 2>&1
    return $LASTEXITCODE -eq 0
}

function Get-ThriveLensExactPostgresProcesses {
    $paths = Get-ThriveLensPostgresPaths
    $matches = [Collections.Generic.List[object]]::new()
    try { $processes = @(Get-CimInstance Win32_Process -Filter "Name = 'postgres.exe'") }
    catch { throw 'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE' }
    foreach ($process in $processes) {
        if ([string]::IsNullOrWhiteSpace([string]$process.ExecutablePath)) {
            throw 'POSTGRES_PROCESS_MEASUREMENT_UNAVAILABLE'
        }
        $executable = [IO.Path]::GetFullPath([string]$process.ExecutablePath)
        if ($executable -ieq [IO.Path]::GetFullPath($paths.Postgres)) { $matches.Add($process) }
    }
    return @($matches)
}

function Get-ThriveLensPostgresListeners {
    $paths = Get-ThriveLensPostgresPaths
    try {
        return @(Get-NetTCPConnection -State Listen -ErrorAction Stop | Where-Object {
            [int]$_.LocalPort -eq $paths.Port
        })
    }
    catch { throw 'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE' }
}

function Assert-ThriveLensLoopbackListener {
    $paths = Get-ThriveLensPostgresPaths
    $listeners = @(Get-ThriveLensPostgresListeners)
    if ($listeners.Count -eq 0) {
        throw 'POSTGRES_LISTENER_UNAVAILABLE'
    }
    $processIds = @(Get-ThriveLensExactPostgresProcesses | ForEach-Object { [int]$_.ProcessId })
    foreach ($listener in $listeners) {
        if ([string]$listener.LocalAddress -cne '127.0.0.1' -or $processIds -notcontains [int]$listener.OwningProcess) {
            throw 'POSTGRES_NON_LOOPBACK_LISTENER'
        }
    }
}

function Assert-ThriveLensPostgresAbsent {
    if (Test-ThriveLensPostgresRunning) { throw 'POSTGRES_CLUSTER_STILL_RUNNING' }
    if (@(Get-ThriveLensExactPostgresProcesses).Count -gt 0) { throw 'POSTGRES_PROCESS_STILL_PRESENT' }
    if (@(Get-ThriveLensPostgresListeners).Count -gt 0) {
        throw 'POSTGRES_LISTENER_STILL_PRESENT'
    }
}

Export-ModuleMember -Function @(
    'Get-ThriveLensProjectRoot',
    'Get-ThriveLensManifest',
    'Get-ThriveLensAttributableRoot',
    'Assert-ThriveLensOwnedPath',
    'Get-ThriveLensPostgresPaths',
    'Get-ThriveLensFreeMemoryBytes',
    'Get-ThriveLensResourcePhase',
    'Assert-ThriveLensProjectedBudget',
    'Assert-ThriveLensFreeDiskBudget',
    'Invoke-ThriveLensResourceGate',
    'Measure-ThriveLensSafeTree',
    'Assert-ThriveLensPostgresArchive',
    'Assert-ThriveLensSecretFileAcl',
    'Assert-ThriveLensVersionText',
    'Assert-ThriveLensPostgresVersions',
    'Test-ThriveLensPostgresRunning',
    'Get-ThriveLensExactPostgresProcesses',
    'Get-ThriveLensPostgresListeners',
    'Assert-ThriveLensLoopbackListener',
    'Assert-ThriveLensPostgresAbsent'
)
