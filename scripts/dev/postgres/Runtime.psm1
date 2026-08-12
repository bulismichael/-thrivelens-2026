#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('ThriveLens.ExclusiveFileSnapshot' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace ThriveLens {
    public sealed class ExclusiveFileSnapshot {
        public string FinalPath { get; private set; }
        public string Identity { get; private set; }
        public long Length { get; private set; }
        public FileAttributes Attributes { get; private set; }
        public uint LinkCount { get; private set; }

        ExclusiveFileSnapshot(
            string finalPath,
            string identity,
            long length,
            FileAttributes attributes,
            uint linkCount
        ) {
            FinalPath = finalPath;
            Identity = identity;
            Length = length;
            Attributes = attributes;
            LinkCount = linkCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        struct ByHandleFileInformation {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", SetLastError = true)]
        static extern bool GetFileInformationByHandle(
            SafeFileHandle file,
            out ByHandleFileInformation information
        );

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        static extern uint GetFinalPathNameByHandle(
            SafeFileHandle file,
            StringBuilder path,
            uint pathLength,
            uint flags
        );

        public static ExclusiveFileSnapshot Capture(SafeFileHandle file) {
            if (file == null || file.IsInvalid || file.IsClosed) {
                throw new IOException("FILE_IDENTITY_UNAVAILABLE");
            }
            ByHandleFileInformation information;
            if (!GetFileInformationByHandle(file, out information)) {
                throw new IOException("FILE_IDENTITY_UNAVAILABLE");
            }

            uint capacity = 512;
            StringBuilder path = new StringBuilder((int)capacity);
            uint written = GetFinalPathNameByHandle(file, path, capacity, 0);
            if (written == 0) {
                throw new IOException("FILE_FINAL_PATH_UNAVAILABLE");
            }
            if (written >= capacity) {
                capacity = checked(written + 1);
                path = new StringBuilder((int)capacity);
                written = GetFinalPathNameByHandle(file, path, capacity, 0);
                if (written == 0 || written >= capacity) {
                    throw new IOException("FILE_FINAL_PATH_UNAVAILABLE");
                }
            }

            long length = ((long)information.FileSizeHigh << 32) | information.FileSizeLow;
            string identity = information.VolumeSerialNumber.ToString("X8") + ":" +
                information.FileIndexHigh.ToString("X8") + information.FileIndexLow.ToString("X8");
            return new ExclusiveFileSnapshot(
                path.ToString(), identity, length,
                (FileAttributes)information.FileAttributes, information.NumberOfLinks
            );
        }
    }
}
'@
}

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

function Assert-ThriveLensComposeDataDirectory {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$ExpectedPath
    )
    $root = Get-ThriveLensAttributableRoot
    $candidate = Assert-ThriveLensOwnedPath -Path $Path -AllowMissing
    $expected = Assert-ThriveLensOwnedPath -Path $ExpectedPath -AllowMissing
    if ($candidate -ieq $root) { throw 'COMPOSE_DATA_ROOT_FORBIDDEN' }
    if ($candidate -ine $expected) { throw 'COMPOSE_DATA_DIRECTORY_MISMATCH' }
    if (-not (Test-Path -LiteralPath $candidate -PathType Container)) {
        throw 'COMPOSE_DATA_DIRECTORY_UNAVAILABLE'
    }

    $acl = Get-Acl -LiteralPath $candidate
    if (-not $acl.AreAccessRulesProtected) { throw 'DIRECTORY_ACL_INHERITANCE_ENABLED' }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $allowedSids = @($currentSid, 'S-1-5-18', 'S-1-5-32-544')
    $ownerSid = $acl.Owner
    try { $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch {
        try { $ownerSid = ([Security.Principal.SecurityIdentifier]$acl.Owner).Value }
        catch { throw 'DIRECTORY_ACL_OWNER_UNVERIFIABLE' }
    }
    if ($allowedSids -notcontains $ownerSid) { throw 'DIRECTORY_ACL_OWNER_REJECTED' }

    $currentUserCanModify = $false
    $modifyMask = [Security.AccessControl.FileSystemRights]::Modify
    foreach ($rule in $acl.Access) {
        if ($rule.IsInherited) { throw 'DIRECTORY_ACL_INHERITED_RULE_REJECTED' }
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw 'DIRECTORY_ACL_IDENTITY_UNVERIFIABLE' }
        if ($allowedSids -notcontains $sid) { throw 'DIRECTORY_ACL_ALLOWLIST_VIOLATION' }
        if ($sid -ceq $currentSid -and ($rule.FileSystemRights -band $modifyMask) -eq $modifyMask) {
            $currentUserCanModify = $true
        }
    }
    if (-not $currentUserCanModify) { throw 'DIRECTORY_ACL_CURRENT_USER_MODIFY_MISSING' }
    if (@(Get-ChildItem -LiteralPath $candidate -Force).Count -ne 0) {
        throw 'COMPOSE_DATA_DIRECTORY_NOT_EMPTY'
    }
    return $candidate
}

function Assert-ThriveLensPathOutsideDirectory {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath,
        [Parameter(Mandatory)][string]$OtherPath
    )
    $directory = Assert-ThriveLensOwnedPath -Path $DirectoryPath -AllowMissing
    $other = Assert-ThriveLensOwnedPath -Path $OtherPath -AllowMissing
    $prefix = $directory.TrimEnd('\') + '\'
    if ($other -ieq $directory -or $other.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'COMPOSE_SECRET_DATA_OVERLAP'
    }
    return $other
}

function ConvertTo-ThriveLensSidValue {
    param(
        [Parameter(Mandatory)]
        [Security.Principal.IdentityReference]$Identity,
        [Parameter(Mandatory)]
        [string]$FailureCode
    )
    try {
        return $Identity.Translate([Security.Principal.SecurityIdentifier]).Value
    }
    catch {
        throw $FailureCode
    }
}

function Get-ThriveLensSecretAclContext {
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    return [pscustomobject]@{
        CurrentSid = $currentSid
        AllowedSids = @($currentSid, 'S-1-5-18', 'S-1-5-32-544')
    }
}

function Assert-ThriveLensSecretRootAcl {
    param([Parameter(Mandatory)][string]$Path)

    try { $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop }
    catch { throw 'SECRET_ROOT_ACL_UNAVAILABLE' }
    if (-not $acl.AreAccessRulesProtected) { throw 'SECRET_ROOT_ACL_INHERITANCE_ENABLED' }

    $context = Get-ThriveLensSecretAclContext
    try { $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate([Security.Principal.SecurityIdentifier]).Value }
    catch {
        try { $ownerSid = ([Security.Principal.SecurityIdentifier]$acl.Owner).Value }
        catch { throw 'SECRET_ROOT_ACL_OWNER_UNVERIFIABLE' }
    }
    if ($context.AllowedSids -notcontains $ownerSid) { throw 'SECRET_ROOT_ACL_OWNER_REJECTED' }

    $requiredRead = [Security.AccessControl.FileSystemRights]::ReadData -bor
        [Security.AccessControl.FileSystemRights]::ReadAttributes -bor
        [Security.AccessControl.FileSystemRights]::ReadExtendedAttributes -bor
        [Security.AccessControl.FileSystemRights]::ReadPermissions
    $currentUserAllowed = [Security.AccessControl.FileSystemRights]0
    $currentUserDenied = [Security.AccessControl.FileSystemRights]0
    foreach ($rule in $acl.Access) {
        if ($rule.IsInherited) { throw 'SECRET_ROOT_ACL_INHERITED_RULE_REJECTED' }
        $sid = ConvertTo-ThriveLensSidValue `
            -Identity $rule.IdentityReference `
            -FailureCode 'SECRET_ROOT_ACL_IDENTITY_UNVERIFIABLE'
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            # Restrict every Allow ACE, including inherit-only ACEs which could
            # otherwise permit replacement or deletion of the fixed child.
            if ($context.AllowedSids -notcontains $sid) {
                throw 'SECRET_ROOT_ACL_ALLOWLIST_VIOLATION'
            }
        }
        if ($sid -cne $context.CurrentSid -or
            ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0) {
            continue
        }
        if ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow) {
            $currentUserAllowed = $currentUserAllowed -bor $rule.FileSystemRights
        }
        elseif ($rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Deny) {
            $currentUserDenied = $currentUserDenied -bor $rule.FileSystemRights
        }
    }
    if (($currentUserAllowed -band $requiredRead) -ne $requiredRead -or
        ($currentUserDenied -band $requiredRead) -ne 0) {
        throw 'SECRET_ROOT_ACL_CURRENT_USER_READ_MISSING'
    }
}

function Assert-ThriveLensSecretFileAclRules {
    param([Parameter(Mandatory)][string]$Path)

    try { $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop }
    catch { throw 'SECRET_ACL_UNAVAILABLE' }
    if (-not $acl.AreAccessRulesProtected) { throw 'SECRET_ACL_INHERITANCE_ENABLED' }
    $context = Get-ThriveLensSecretAclContext
    $currentSid = $context.CurrentSid
    $allowedSids = $context.AllowedSids
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
        if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) { continue }
        try { $sid = $rule.IdentityReference.Translate([Security.Principal.SecurityIdentifier]).Value }
        catch { throw 'SECRET_ACL_IDENTITY_UNVERIFIABLE' }
        # A write-only or control-only ACE can replace, delete, or weaken the
        # secret without reading it. Therefore every effective Allow ACE, not
        # merely read-capable ACEs, is restricted to the explicit allowlist.
        if ($allowedSids -notcontains $sid) { throw 'SECRET_ACL_ALLOWLIST_VIOLATION' }
        if ($sid -ceq $currentSid -and ($rule.FileSystemRights -band $readMask) -ne 0) {
            $currentUserCanRead = $true
        }
    }
    if (-not $currentUserCanRead) { throw 'SECRET_ACL_CURRENT_USER_READ_MISSING' }
}

function Assert-ThriveLensSecretFileAcl {
    param([Parameter(Mandatory)][string]$Path)
    if (-not $IsWindows) { throw 'SECRET_ACL_WINDOWS_REQUIRED' }
    $secretPath = Assert-ThriveLensOwnedPath -Path $Path
    if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) { throw 'SECRET_FILE_UNAVAILABLE' }
    Assert-ThriveLensSecretFileAclRules -Path $secretPath
    try {
        $probe = [IO.File]::Open($secretPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        $probe.Dispose()
    }
    catch { throw 'SECRET_ACL_CURRENT_USER_READ_UNAVAILABLE' }
}

function ConvertFrom-ThriveLensFinalPath {
    param([Parameter(Mandatory)][string]$Path)

    if ($Path.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        return '\\' + $Path.Substring(8)
    }
    if ($Path.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        return $Path.Substring(4)
    }
    return $Path
}

function Read-ThriveLensPostgresBootstrapSecret {
    param([Parameter(Mandatory)][string]$Path)

    if (-not $IsWindows) { throw 'SECRET_ACL_WINDOWS_REQUIRED' }
    $countedRoot = Get-ThriveLensAttributableRoot
    $secretRoot = [IO.Path]::GetFullPath((Join-Path $countedRoot 'secrets')).TrimEnd('\')
    $expectedPath = [IO.Path]::GetFullPath((Join-Path $secretRoot 'postgres-r0-bootstrap.pw'))
    try {
        $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))
    }
    catch { throw 'PASSWORD_FILE_PATH_INVALID' }
    if ($candidate -cne $expectedPath) { throw 'PASSWORD_FILE_PATH_MISMATCH' }

    foreach ($component in @($countedRoot, $secretRoot, $expectedPath)) {
        if (-not (Test-Path -LiteralPath $component)) { throw 'PASSWORD_FILE_PATH_UNAVAILABLE' }
        try { $item = Get-Item -LiteralPath $component -Force -ErrorAction Stop }
        catch { throw 'PASSWORD_FILE_PATH_UNAVAILABLE' }
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'PASSWORD_FILE_REPARSE_REJECTED'
        }
    }
    if (-not (Test-Path -LiteralPath $secretRoot -PathType Container) -or
        -not (Test-Path -LiteralPath $expectedPath -PathType Leaf)) {
        throw 'PASSWORD_FILE_PATH_TYPE_INVALID'
    }

    Assert-ThriveLensSecretRootAcl -Path $secretRoot
    Assert-ThriveLensSecretFileAclRules -Path $expectedPath

    $stream = $null
    $bytes = $null
    try {
        try {
            $stream = [IO.FileStream]::new(
                $expectedPath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::None,
                128,
                [IO.FileOptions]::SequentialScan
            )
        }
        catch { throw 'PASSWORD_FILE_EXCLUSIVE_OPEN_FAILED' }

        try { $before = [ThriveLens.ExclusiveFileSnapshot]::Capture($stream.SafeFileHandle) }
        catch { throw 'PASSWORD_FILE_IDENTITY_UNAVAILABLE' }
        $beforePath = ConvertFrom-ThriveLensFinalPath -Path $before.FinalPath
        if (-not $beforePath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase)) {
            throw 'PASSWORD_FILE_FINAL_PATH_MISMATCH'
        }
        if (($before.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
            ($before.Attributes -band [IO.FileAttributes]::Directory) -ne 0 -or
            $before.LinkCount -ne 1) {
            throw 'PASSWORD_FILE_IDENTITY_REJECTED'
        }
        if ($before.Length -lt 1 -or $before.Length -gt 129) {
            throw 'PASSWORD_FILE_SIZE_INVALID'
        }

        $bytes = [byte[]]::new([int]$before.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            try { $read = $stream.Read($bytes, $offset, $bytes.Length - $offset) }
            catch { throw 'PASSWORD_FILE_READ_FAILED' }
            if ($read -le 0) { throw 'PASSWORD_FILE_READ_INCOMPLETE' }
            $offset += $read
        }

        try { $after = [ThriveLens.ExclusiveFileSnapshot]::Capture($stream.SafeFileHandle) }
        catch { throw 'PASSWORD_FILE_IDENTITY_UNAVAILABLE' }
        $afterPath = ConvertFrom-ThriveLensFinalPath -Path $after.FinalPath
        if (-not $afterPath.Equals($expectedPath, [StringComparison]::OrdinalIgnoreCase) -or
            $afterPath -cne $beforePath -or
            $after.Identity -cne $before.Identity -or
            $after.Length -ne $before.Length -or
            $after.Attributes -ne $before.Attributes -or
            $after.LinkCount -ne $before.LinkCount) {
            throw 'PASSWORD_FILE_IDENTITY_CHANGED'
        }

        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
            throw 'PASSWORD_FILE_BOM_REJECTED'
        }
        try { $value = [Text.UTF8Encoding]::new($false, $true).GetString($bytes) }
        catch { throw 'PASSWORD_FILE_ENCODING_INVALID' }
        if ($value.EndsWith("`r`n", [StringComparison]::Ordinal)) {
            $value = $value.Substring(0, $value.Length - 2)
        }
        elseif ($value.EndsWith("`n", [StringComparison]::Ordinal)) {
            $value = $value.Substring(0, $value.Length - 1)
        }
        if ($value -match '[\x00-\x1F\x7F]' -or $value.Contains(':') -or
            $value.Contains('\') -or $value -cnotmatch '^[A-Za-z0-9_-]{43,128}$' -or
            $value -match '(?i)^(?:password|postgres|thrivelens|changeme|change_me|test|testing|secret|placeholder|example|default|demo|admin|root|letmein|qwerty)' -or
            $value -match '(?i)(?:sentinel|not[_-]?a[_-]?real|dummy|placeholder|changeme)' -or
            $value -match '^(.)\1{42,}$') {
            throw 'PASSWORD_FILE_INVALID'
        }

        Assert-ThriveLensSecretRootAcl -Path $secretRoot
        Assert-ThriveLensSecretFileAclRules -Path $expectedPath
        foreach ($component in @($countedRoot, $secretRoot, $expectedPath)) {
            try { $item = Get-Item -LiteralPath $component -Force -ErrorAction Stop }
            catch { throw 'PASSWORD_FILE_PATH_UNAVAILABLE' }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'PASSWORD_FILE_REPARSE_REJECTED'
            }
        }
        return $value
    }
    finally {
        if ($null -ne $bytes) { [Array]::Clear($bytes, 0, $bytes.Length) }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Resolve-ThriveLensStartChildFailure {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [AllowEmptyString()][string]$OutputText = ''
    )
    if ($ExitCode -eq 0) {
        return [pscustomobject]@{ Code = $null; ExitCode = 0 }
    }
    if ($ExitCode -eq 3) {
        $code = if ($OutputText -match '"code"\s*:\s*"POSTGRES_START_CLEANUP_FAILED"') {
            'POSTGRES_START_CLEANUP_FAILED'
        }
        else { 'RUNTIME_START_CHILD_FATAL' }
        return [pscustomobject]@{ Code = $code; ExitCode = 3 }
    }
    return [pscustomobject]@{ Code = 'RUNTIME_START_PROBE_FAILED'; ExitCode = 2 }
}

function Resolve-ThriveLensRuntimeFailureOutcome {
    param(
        [Parameter(Mandatory)][string]$OriginalCode,
        [Parameter(Mandatory)][ValidateSet(2, 3)][int]$OriginalExitCode,
        [Parameter(Mandatory)][bool]$StartInvoked,
        [Parameter(Mandatory)][bool]$CleanupAttempted,
        [Parameter(Mandatory)][int]$CleanupExitCode,
        [Parameter(Mandatory)][bool]$AbsenceVerified
    )
    if ([string]::IsNullOrWhiteSpace($OriginalCode)) {
        throw 'RUNTIME_FAILURE_POLICY_INPUT_INVALID'
    }
    $cleanupRequired = $StartInvoked
    $cleanupVerified = -not $cleanupRequired -or
        ($CleanupAttempted -and $CleanupExitCode -eq 0 -and $AbsenceVerified)

    if (-not $cleanupVerified) {
        # Preserve a child cleanup fatal exactly; otherwise cleanup uncertainty
        # escalates an ordinary probe failure to exit 3.
        $code = if ($OriginalExitCode -eq 3) { $OriginalCode } else { 'RUNTIME_CLEANUP_FAILED' }
        return [pscustomobject]@{
            Status = 'ERROR'
            Code = $code
            ExitCode = 3
            CleanupRequired = $cleanupRequired
            CleanupVerified = $false
        }
    }

    return [pscustomobject]@{
        Status = if ($OriginalExitCode -eq 3) { 'ERROR' } else { 'BLOCKED' }
        Code = $OriginalCode
        ExitCode = $OriginalExitCode
        CleanupRequired = $cleanupRequired
        CleanupVerified = $cleanupVerified
    }
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
    'Assert-ThriveLensComposeDataDirectory',
    'Assert-ThriveLensPathOutsideDirectory',
    'Assert-ThriveLensSecretFileAcl',
    'Read-ThriveLensPostgresBootstrapSecret',
    'Resolve-ThriveLensStartChildFailure',
    'Resolve-ThriveLensRuntimeFailureOutcome',
    'Assert-ThriveLensVersionText',
    'Assert-ThriveLensPostgresVersions',
    'Test-ThriveLensPostgresRunning',
    'Get-ThriveLensExactPostgresProcesses',
    'Get-ThriveLensPostgresListeners',
    'Assert-ThriveLensLoopbackListener',
    'Assert-ThriveLensPostgresAbsent'
)
