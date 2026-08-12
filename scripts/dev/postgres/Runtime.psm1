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

if (-not ('ThriveLens.ResourceGateCaptureStreamV2' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

namespace ThriveLens {
    public sealed class ResourceGateOutputBudgetV2 {
        public const string ContractVersion = "TL_RESOURCE_GATE_CAPTURE_V2";
        long count;
        public long Limit { get; private set; }
        public bool Exceeded { get; private set; }
        public ResourceGateOutputBudgetV2(long limit) {
            if (limit < 1) throw new ArgumentOutOfRangeException("limit");
            Limit = limit;
        }
        public void Add(int value) {
            long total = Interlocked.Add(ref count, value);
            if (total > Limit) {
                Exceeded = true;
                throw new IOException("RESOURCE_GATE_OUTPUT_LIMIT");
            }
        }
    }

    public sealed class ResourceGateCaptureStreamV2 : Stream {
        public const string ContractVersion = "TL_RESOURCE_GATE_CAPTURE_V2";
        readonly ResourceGateOutputBudgetV2 budget;
        readonly MemoryStream data = new MemoryStream();
        public ResourceGateCaptureStreamV2(ResourceGateOutputBudgetV2 sharedBudget) {
            budget = sharedBudget ?? throw new ArgumentNullException("sharedBudget");
        }
        void Put(byte[] buffer, int offset, int count) {
            budget.Add(count);
            data.Write(buffer, offset, count);
        }
        public byte[] ToArray() { return data.ToArray(); }
        public override void Write(byte[] buffer, int offset, int count) {
            Put(buffer, offset, count);
        }
        public override Task WriteAsync(
            byte[] buffer, int offset, int count, CancellationToken cancellationToken
        ) {
            Put(buffer, offset, count);
            return Task.CompletedTask;
        }
        public override bool CanRead { get { return false; } }
        public override bool CanSeek { get { return false; } }
        public override bool CanWrite { get { return true; } }
        public override long Length { get { return data.Length; } }
        public override long Position {
            get { return data.Position; }
            set { throw new NotSupportedException(); }
        }
        public override void Flush() { }
        public override Task FlushAsync(CancellationToken cancellationToken) {
            return Task.CompletedTask;
        }
        public override int Read(byte[] buffer, int offset, int count) {
            throw new NotSupportedException();
        }
        public override long Seek(long offset, SeekOrigin origin) {
            throw new NotSupportedException();
        }
        public override void SetLength(long value) {
            throw new NotSupportedException();
        }
        protected override void Dispose(bool disposing) {
            if (disposing) data.Dispose();
            base.Dispose(disposing);
        }
    }
}
'@
}

if ([ThriveLens.ResourceGateOutputBudgetV2]::ContractVersion -cne
        'TL_RESOURCE_GATE_CAPTURE_V2' -or
    [ThriveLens.ResourceGateCaptureStreamV2]::ContractVersion -cne
        'TL_RESOURCE_GATE_CAPTURE_V2') {
    throw 'RESOURCE_GATE_CAPTURE_CONTRACT_INVALID'
}
$resourceGateCaptureProbeBudget = [ThriveLens.ResourceGateOutputBudgetV2]::new(4)
$resourceGateCaptureProbe = [ThriveLens.ResourceGateCaptureStreamV2]::new(
    $resourceGateCaptureProbeBudget
)
try {
    $resourceGateCaptureProbe.Write([byte[]](1, 2, 3), 0, 3)
    $overflowObserved = $false
    try { $resourceGateCaptureProbe.Write([byte[]](4, 5), 0, 2) }
    catch [IO.IOException] { $overflowObserved = $true }
    $probeBytes = $resourceGateCaptureProbe.ToArray()
    try {
        if (-not $overflowObserved -or -not $resourceGateCaptureProbeBudget.Exceeded -or
            $probeBytes.Length -ne 3) {
            throw 'RESOURCE_GATE_CAPTURE_CONTRACT_INVALID'
        }
    }
    finally { [Array]::Clear($probeBytes, 0, $probeBytes.Length) }
}
finally {
    $resourceGateCaptureProbe.Dispose()
    $resourceGateCaptureProbe = $null
    $resourceGateCaptureProbeBudget = $null
}

$script:ThriveLensConfigurationLeaseStates =
    [Runtime.CompilerServices.ConditionalWeakTable[object, object]]::new()

function Get-ThriveLensConfigurationLeaseDefinitions {
    $projectRoot = Get-ThriveLensProjectRoot
    return @(
        [pscustomobject]@{
            Role = 'BACKEND_MANIFEST'
            Path = [IO.Path]::GetFullPath((Join-Path $projectRoot 'config\toolchains\backend.json'))
            MaximumLength = 1MB
        },
        [pscustomobject]@{
            Role = 'RESOURCE_BUDGET'
            Path = [IO.Path]::GetFullPath((Join-Path $projectRoot 'config\resource-budget.json'))
            MaximumLength = 256KB
        }
    )
}

function Assert-ThriveLensConfigurationJsonString {
    param([Parameter(Mandatory)][AllowEmptyString()][string]$Value)

    foreach ($character in $Value.ToCharArray()) {
        if ([Globalization.CharUnicodeInfo]::GetUnicodeCategory($character) -eq
            [Globalization.UnicodeCategory]::Control) {
            throw 'CONFIGURATION_LEASE_JSON_CONTROL_REJECTED'
        }
    }
}

function Assert-ThriveLensConfigurationJsonElement {
    param([Parameter(Mandatory)][Text.Json.JsonElement]$Element)

    switch ($Element.ValueKind) {
        ([Text.Json.JsonValueKind]::Object) {
            # PowerShell property access is case-insensitive. Reject both exact
            # duplicates and case-variant aliases before ConvertFrom-Json can
            # collapse policy meaning at a later call site.
            $propertyNames = [Collections.Generic.HashSet[string]]::new(
                [StringComparer]::OrdinalIgnoreCase
            )
            foreach ($property in $Element.EnumerateObject()) {
                Assert-ThriveLensConfigurationJsonString -Value $property.Name
                if (-not $propertyNames.Add($property.Name)) {
                    throw 'CONFIGURATION_LEASE_JSON_DUPLICATE_PROPERTY'
                }
                Assert-ThriveLensConfigurationJsonElement -Element $property.Value
            }
        }
        ([Text.Json.JsonValueKind]::Array) {
            foreach ($item in $Element.EnumerateArray()) {
                Assert-ThriveLensConfigurationJsonElement -Element $item
            }
        }
        ([Text.Json.JsonValueKind]::String) {
            Assert-ThriveLensConfigurationJsonString -Value $Element.GetString()
        }
    }
}

function Assert-ThriveLensConfigurationJsonBytes {
    param(
        [Parameter(Mandatory)][byte[]]$Bytes,
        [Parameter(Mandatory)][int64]$MaximumLength
    )

    if ($Bytes.Length -lt 1 -or $Bytes.Length -gt $MaximumLength) {
        throw 'CONFIGURATION_LEASE_LENGTH_INVALID'
    }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and
        $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        throw 'CONFIGURATION_LEASE_BOM_REJECTED'
    }
    foreach ($value in $Bytes) {
        if (($value -lt 0x20 -and $value -notin @(0x09, 0x0A, 0x0D)) -or $value -eq 0x7F) {
            throw 'CONFIGURATION_LEASE_JSON_CONTROL_REJECTED'
        }
    }

    try { $rawJson = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes) }
    catch { throw 'CONFIGURATION_LEASE_UTF8_INVALID' }

    $document = $null
    try {
        $options = [Text.Json.JsonDocumentOptions]::new()
        $options.AllowTrailingCommas = $false
        $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
        $options.MaxDepth = 128
        $memory = [ReadOnlyMemory[byte]]::new($Bytes)
        $document = [Text.Json.JsonDocument]::Parse($memory, $options)
        if ($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'CONFIGURATION_LEASE_JSON_ROOT_INVALID'
        }
        Assert-ThriveLensConfigurationJsonElement -Element $document.RootElement
    }
    catch {
        if ($_.Exception.Message -clike 'CONFIGURATION_LEASE_*') { throw }
        throw 'CONFIGURATION_LEASE_JSON_INVALID'
    }
    finally {
        if ($null -ne $document) { $document.Dispose() }
    }
    return $rawJson
}

function Get-ThriveLensConfigurationLeaseSnapshot {
    param(
        [Parameter(Mandatory)][IO.FileStream]$Stream,
        [Parameter(Mandatory)][string]$ExpectedPath
    )

    try { $snapshot = [ThriveLens.ExclusiveFileSnapshot]::Capture($Stream.SafeFileHandle) }
    catch { throw 'CONFIGURATION_LEASE_IDENTITY_UNAVAILABLE' }
    $finalPath = ConvertFrom-ThriveLensFinalPath -Path $snapshot.FinalPath
    try { $finalPath = [IO.Path]::GetFullPath($finalPath) }
    catch { throw 'CONFIGURATION_LEASE_FINAL_PATH_INVALID' }
    if (-not $finalPath.Equals($ExpectedPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CONFIGURATION_LEASE_FINAL_PATH_MISMATCH'
    }
    if (($snapshot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($snapshot.Attributes -band [IO.FileAttributes]::Directory) -ne 0 -or
        $snapshot.LinkCount -ne 1) {
        throw 'CONFIGURATION_LEASE_IDENTITY_REJECTED'
    }
    return [pscustomobject]@{
        Path = $finalPath
        Identity = [string]$snapshot.Identity
        Length = [int64]$snapshot.Length
        Attributes = [int64]$snapshot.Attributes
        LinkCount = [int64]$snapshot.LinkCount
    }
}

function Read-ThriveLensConfigurationLeaseStream {
    param(
        [Parameter(Mandatory)][IO.FileStream]$Stream,
        [Parameter(Mandatory)][int64]$Length,
        [Parameter(Mandatory)][int64]$MaximumLength
    )

    if ($Length -lt 1 -or $Length -gt $MaximumLength -or $Length -gt [int]::MaxValue) {
        throw 'CONFIGURATION_LEASE_LENGTH_INVALID'
    }
    $bytes = [byte[]]::new([int]$Length)
    try {
        try { $Stream.Position = 0 }
        catch { throw 'CONFIGURATION_LEASE_STREAM_UNREADABLE' }
        $offset = 0
        while ($offset -lt $bytes.Length) {
            try { $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset) }
            catch { throw 'CONFIGURATION_LEASE_READ_FAILED' }
            if ($read -le 0) { throw 'CONFIGURATION_LEASE_READ_INCOMPLETE' }
            $offset += $read
        }
        if ($Stream.ReadByte() -ne -1) { throw 'CONFIGURATION_LEASE_LENGTH_CHANGED' }
        $rawJson = Assert-ThriveLensConfigurationJsonBytes `
            -Bytes $bytes `
            -MaximumLength $MaximumLength
        $sha256 = [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($bytes)
        )
        return [pscustomobject]@{
            RawJson = $rawJson
            Sha256 = $sha256
        }
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function New-ThriveLensConfigurationLeaseRecord {
    param([Parameter(Mandatory)]$Definition)

    if (-not (Test-Path -LiteralPath $Definition.Path -PathType Leaf)) {
        throw 'CONFIGURATION_LEASE_FILE_UNAVAILABLE'
    }
    try { $item = Get-Item -LiteralPath $Definition.Path -Force -ErrorAction Stop }
    catch { throw 'CONFIGURATION_LEASE_FILE_UNAVAILABLE' }
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or
        ($item.Attributes -band [IO.FileAttributes]::Directory) -ne 0) {
        throw 'CONFIGURATION_LEASE_PATH_REJECTED'
    }

    $stream = $null
    try {
        try {
            $stream = [IO.FileStream]::new(
                $Definition.Path,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read,
                4096,
                [IO.FileOptions]::SequentialScan
            )
        }
        catch { throw 'CONFIGURATION_LEASE_OPEN_FAILED' }

        $before = Get-ThriveLensConfigurationLeaseSnapshot `
            -Stream $stream `
            -ExpectedPath $Definition.Path
        if ($before.Length -lt 1 -or $before.Length -gt $Definition.MaximumLength) {
            throw 'CONFIGURATION_LEASE_LENGTH_INVALID'
        }
        $content = Read-ThriveLensConfigurationLeaseStream `
            -Stream $stream `
            -Length $before.Length `
            -MaximumLength $Definition.MaximumLength
        $after = Get-ThriveLensConfigurationLeaseSnapshot `
            -Stream $stream `
            -ExpectedPath $Definition.Path
        if ($after.Path -cne $before.Path -or $after.Identity -cne $before.Identity -or
            $after.Length -ne $before.Length -or $after.Attributes -ne $before.Attributes -or
            $after.LinkCount -ne $before.LinkCount) {
            throw 'CONFIGURATION_LEASE_IDENTITY_CHANGED'
        }

        return [pscustomobject]@{
            Role = [string]$Definition.Role
            Path = [string]$before.Path
            Sha256 = [string]$content.Sha256
            RawJson = [string]$content.RawJson
            Identity = [string]$before.Identity
            Length = [int64]$before.Length
            Attributes = [int64]$before.Attributes
            LinkCount = [int64]$before.LinkCount
            MaximumLength = [int64]$Definition.MaximumLength
            Stream = $stream
        }
    }
    catch {
        if ($null -ne $stream) { $stream.Dispose() }
        throw
    }
}

function Enter-ThriveLensConfigurationLease {
    $definitions = @(Get-ThriveLensConfigurationLeaseDefinitions)
    $internalRecords = [Collections.Generic.List[object]]::new()
    $completed = $false
    try {
        $expectedRoles = @('BACKEND_MANIFEST', 'RESOURCE_BUDGET')
        if ($definitions.Count -ne $expectedRoles.Count) {
            throw 'CONFIGURATION_LEASE_INVALID'
        }
        for ($index = 0; $index -lt $definitions.Count; $index++) {
            try {
                if ([string]$definitions[$index].Role -cne $expectedRoles[$index] -or
                    [string]::IsNullOrWhiteSpace([string]$definitions[$index].Path) -or
                    [int64]$definitions[$index].MaximumLength -le 0) {
                    throw 'CONFIGURATION_LEASE_INVALID'
                }
            }
            catch { throw 'CONFIGURATION_LEASE_INVALID' }
        }
        foreach ($definition in $definitions) {
            # The order is security-significant: backend first, then resource budget.
            $internalRecords.Add((New-ThriveLensConfigurationLeaseRecord -Definition $definition))
        }

        $publicRoles = [string[]]::new($internalRecords.Count)
        $internalStreams = [IO.FileStream[]]::new($internalRecords.Count)
        for ($index = 0; $index -lt $internalRecords.Count; $index++) {
            $record = $internalRecords[$index]
            $publicRoles[$index] = [string]$record.Role
            $internalStreams[$index] = $record.Stream
        }
        $lease = [pscustomobject]@{
            Version = 1
            Roles = $publicRoles
        }
        $state = [pscustomobject]@{
            Lease = $lease
            PublicRoles = $publicRoles
            InternalRecords = @($internalRecords)
            InternalStreams = $internalStreams
            Exited = $false
        }
        $script:ThriveLensConfigurationLeaseStates.Add($lease, $state)
        $completed = $true
        return $lease
    }
    finally {
        if (-not $completed) {
            for ($index = $internalRecords.Count - 1; $index -ge 0; $index--) {
                try { $internalRecords[$index].Stream.Dispose() }
                catch { }
            }
        }
    }
}

function Get-ThriveLensConfigurationLeaseState {
    param([Parameter(Mandatory)]$Lease)

    $state = $null
    if (-not $script:ThriveLensConfigurationLeaseStates.TryGetValue(
        [object]$Lease,
        [ref]$state
    )) {
        throw 'CONFIGURATION_LEASE_INVALID'
    }
    return $state
}

function Test-ThriveLensConfigurationLeasePublicShape {
    param(
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)]$State
    )

    try {
        $propertyNames = @($Lease.PSObject.Properties | ForEach-Object { [string]$_.Name })
        if ($propertyNames.Count -ne 2 -or
            $propertyNames[0] -cne 'Version' -or
            $propertyNames[1] -cne 'Roles' -or
            $Lease.Version -isnot [int] -or
            $Lease.Version -ne 1 -or
            $Lease.Roles -isnot [string[]] -or
            -not [object]::ReferenceEquals($Lease, $State.Lease) -or
            -not [object]::ReferenceEquals($Lease.Roles, $State.PublicRoles) -or
            $Lease.Roles.Count -ne 2 -or
            $State.InternalRecords.Count -ne 2) {
            return $false
        }
        $expectedRoles = @('BACKEND_MANIFEST', 'RESOURCE_BUDGET')
        for ($index = 0; $index -lt $State.InternalRecords.Count; $index++) {
            $internal = $State.InternalRecords[$index]
            if ($Lease.Roles[$index] -cne $expectedRoles[$index] -or
                $Lease.Roles[$index] -cne [string]$internal.Role) {
                return $false
            }
        }
        return $true
    }
    catch { return $false }
}

function Assert-ThriveLensConfigurationLeaseInternalIntegrity {
    param(
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)]$State
    )

    try {
        if ($State.Exited -isnot [bool] -or $State.Exited -or
            -not [object]::ReferenceEquals($Lease, $State.Lease) -or
            $State.InternalRecords.Count -ne 2 -or
            $State.InternalStreams -isnot [IO.FileStream[]] -or
            $State.InternalStreams.Count -ne $State.InternalRecords.Count) {
            throw 'CONFIGURATION_LEASE_INVALID'
        }
        $definitions = @(Get-ThriveLensConfigurationLeaseDefinitions)
        if ($definitions.Count -ne $State.InternalRecords.Count) {
            throw 'CONFIGURATION_LEASE_INVALID'
        }
    }
    catch { throw 'CONFIGURATION_LEASE_INVALID' }

    $expectedRoles = @('BACKEND_MANIFEST', 'RESOURCE_BUDGET')
    for ($index = 0; $index -lt $definitions.Count; $index++) {
        $definition = $definitions[$index]
        $record = $State.InternalRecords[$index]
        $stream = $State.InternalStreams[$index]
        try {
            $definitionPath = [IO.Path]::GetFullPath([string]$definition.Path)
            if ([string]$definition.Role -cne $expectedRoles[$index] -or
                [string]$record.Role -cne $expectedRoles[$index] -or
                [string]$record.Role -cne [string]$definition.Role -or
                -not ([string]$record.Path).Equals(
                    $definitionPath,
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                [int64]$record.MaximumLength -ne [int64]$definition.MaximumLength -or
                [int64]$record.MaximumLength -le 0 -or
                $record.Sha256 -cnotmatch '^[0-9A-F]{64}$' -or
                $record.Length -lt 1 -or $record.Length -gt $record.MaximumLength -or
                $record.LinkCount -ne 1 -or
                $stream -isnot [IO.FileStream] -or
                -not [object]::ReferenceEquals($record.Stream, $stream) -or
                -not $stream.CanRead -or
                $stream.SafeFileHandle.IsClosed -or
                $stream.SafeFileHandle.IsInvalid) {
                throw 'CONFIGURATION_LEASE_INVALID'
            }
        }
        catch { throw 'CONFIGURATION_LEASE_INVALID' }

        $snapshot = Get-ThriveLensConfigurationLeaseSnapshot `
            -Stream $stream `
            -ExpectedPath $definitionPath
        if (-not $snapshot.Path.Equals($definitionPath, [StringComparison]::OrdinalIgnoreCase) -or
            $snapshot.Identity -cne $record.Identity -or $snapshot.Length -ne $record.Length -or
            $snapshot.Attributes -ne $record.Attributes -or
            $snapshot.LinkCount -ne $record.LinkCount) {
            throw 'CONFIGURATION_LEASE_IDENTITY_CHANGED'
        }
        $content = Read-ThriveLensConfigurationLeaseStream `
            -Stream $stream `
            -Length $record.Length `
            -MaximumLength $record.MaximumLength
        if ($content.Sha256 -cne $record.Sha256 -or $content.RawJson -cne $record.RawJson) {
            throw 'CONFIGURATION_LEASE_CONTENT_CHANGED'
        }
        $afterRead = Get-ThriveLensConfigurationLeaseSnapshot `
            -Stream $stream `
            -ExpectedPath $definitionPath
        if (-not $afterRead.Path.Equals($definitionPath, [StringComparison]::OrdinalIgnoreCase) -or
            $afterRead.Identity -cne $record.Identity -or
            $afterRead.Length -ne $record.Length -or
            $afterRead.Attributes -ne $record.Attributes -or
            $afterRead.LinkCount -ne $record.LinkCount) {
            throw 'CONFIGURATION_LEASE_IDENTITY_CHANGED'
        }
        # Parse the immutable retained text again as part of every assertion.
        $retainedBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($record.RawJson)
        try {
            $retainedRaw = Assert-ThriveLensConfigurationJsonBytes `
                -Bytes $retainedBytes `
                -MaximumLength $record.MaximumLength
            if ($retainedRaw -cne $record.RawJson) {
                throw 'CONFIGURATION_LEASE_CONTENT_CHANGED'
            }
        }
        finally {
            [Array]::Clear($retainedBytes, 0, $retainedBytes.Length)
        }
    }
}

function Assert-ThriveLensConfigurationLease {
    param([Parameter(Mandatory)]$Lease)

    $state = Get-ThriveLensConfigurationLeaseState -Lease $Lease
    if (-not (Test-ThriveLensConfigurationLeasePublicShape -Lease $Lease -State $state)) {
        throw 'CONFIGURATION_LEASE_INVALID'
    }
    Assert-ThriveLensConfigurationLeaseInternalIntegrity -Lease $Lease -State $state
}

function Get-ThriveLensLeasedConfigurationValue {
    param(
        [Parameter(Mandatory)]$Lease,
        [Parameter(Mandatory)][ValidateSet('BACKEND_MANIFEST', 'RESOURCE_BUDGET')][string]$Role
    )

    Assert-ThriveLensConfigurationLease -Lease $Lease
    $state = Get-ThriveLensConfigurationLeaseState -Lease $Lease
    $record = @($state.InternalRecords | Where-Object { $_.Role -ceq $Role })
    if ($record.Count -ne 1) { throw 'CONFIGURATION_LEASE_INVALID' }
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($record[0].RawJson)
    try {
        $rawJson = Assert-ThriveLensConfigurationJsonBytes `
            -Bytes $bytes `
            -MaximumLength $record[0].MaximumLength
        try { return $rawJson | ConvertFrom-Json -Depth 128 }
        catch { throw 'CONFIGURATION_LEASE_JSON_INVALID' }
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Get-ThriveLensLeasedBackendManifest {
    param([Parameter(Mandatory)]$Lease)
    return Get-ThriveLensLeasedConfigurationValue -Lease $Lease -Role 'BACKEND_MANIFEST'
}

function Get-ThriveLensLeasedResourceBudget {
    param([Parameter(Mandatory)]$Lease)
    return Get-ThriveLensLeasedConfigurationValue -Lease $Lease -Role 'RESOURCE_BUDGET'
}

function Get-ThriveLensConfigurationLeaseFingerprint {
    param([Parameter(Mandatory)]$Lease)

    Assert-ThriveLensConfigurationLease -Lease $Lease
    $state = Get-ThriveLensConfigurationLeaseState -Lease $Lease
    $components = [Collections.Generic.List[string]]::new()
    $components.Add('THRIVELENS_CONFIGURATION_LEASE_V1')
    foreach ($record in $state.InternalRecords) {
        $components.Add(('{0}:{1}:{2}' -f $record.Role, $record.Length, $record.Sha256))
    }
    $fingerprintBytes = [Text.Encoding]::UTF8.GetBytes(($components -join "`n"))
    try {
        return [Convert]::ToHexString(
            [Security.Cryptography.SHA256]::HashData($fingerprintBytes)
        )
    }
    finally {
        [Array]::Clear($fingerprintBytes, 0, $fingerprintBytes.Length)
    }
}

function Exit-ThriveLensConfigurationLease {
    param([Parameter(Mandatory)]$Lease)

    $state = Get-ThriveLensConfigurationLeaseState -Lease $Lease
    $shapeValid = Test-ThriveLensConfigurationLeasePublicShape -Lease $Lease -State $state
    $integrityValid = $true
    try {
        Assert-ThriveLensConfigurationLeaseInternalIntegrity -Lease $Lease -State $state
    }
    catch { $integrityValid = $false }
    $releaseFailed = $false
    try {
        for ($index = $state.InternalStreams.Count - 1; $index -ge 0; $index--) {
            try { $state.InternalStreams[$index].Dispose() }
            catch { $releaseFailed = $true }
        }
    }
    catch { $releaseFailed = $true }
    try {
        $state.Exited = $true
    }
    catch { $releaseFailed = $true }
    if (-not $shapeValid -or -not $integrityValid) { throw 'CONFIGURATION_LEASE_INVALID' }
    if ($releaseFailed) { throw 'CONFIGURATION_LEASE_RELEASE_FAILED' }
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

if ($null -eq ('ThriveLens.HostMemorySnapshot' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace ThriveLens
{
    public static class HostMemorySnapshot
    {
        [StructLayout(LayoutKind.Sequential, Pack = 8)]
        private struct MEMORYSTATUSEX
        {
            public UInt32 dwLength;
            public UInt32 dwMemoryLoad;
            public UInt64 ullTotalPhys;
            public UInt64 ullAvailPhys;
            public UInt64 ullTotalPageFile;
            public UInt64 ullAvailPageFile;
            public UInt64 ullTotalVirtual;
            public UInt64 ullAvailVirtual;
            public UInt64 ullAvailExtendedVirtual;
        }

        [DllImport("kernel32.dll", ExactSpelling = true, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx(ref MEMORYSTATUSEX status);

        public static Int64 ToSignedByteCount(UInt64 availablePhysicalBytes)
        {
            return checked((Int64)availablePhysicalBytes);
        }

        public static Int64 GetAvailablePhysicalBytes()
        {
            MEMORYSTATUSEX status = new MEMORYSTATUSEX();
            int nativeSize = Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            if (nativeSize != 64)
            {
                throw new InvalidOperationException("Unexpected MEMORYSTATUSEX ABI size.");
            }
            status.dwLength = checked((UInt32)nativeSize);
            if (!GlobalMemoryStatusEx(ref status))
            {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            return ToSignedByteCount(status.ullAvailPhys);
        }
    }
}
'@
}

function Get-ThriveLensFreeMemoryBytes {
    if (-not $IsWindows) {
        throw 'WINDOWS_HOST_REQUIRED'
    }
    try {
        $availableBytes = [ThriveLens.HostMemorySnapshot]::GetAvailablePhysicalBytes()
        if ($availableBytes -lt 0) {
            throw 'INVALID_MEMORY_SAMPLE'
        }
        return [int64]$availableBytes
    }
    catch {
        throw 'MEMORY_MEASUREMENT_UNAVAILABLE'
    }
}

function Wait-ThriveLensInterCycleMemorySettle {
    param(
        [Parameter(Mandatory)][int64]$MinimumFreeMemoryBytes
    )

    if ($MinimumFreeMemoryBytes -le 0) {
        throw 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE'
    }

    $timeoutMilliseconds = 90000
    $sampleIntervalMilliseconds = 1000
    $requiredConsecutiveSamples = 3
    $consecutiveSamples = 0
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($stopwatch.ElapsedMilliseconds -le $timeoutMilliseconds) {
            try {
                $samples = @(Get-ThriveLensFreeMemoryBytes)
                if ($samples.Count -ne 1 -or $null -eq $samples[0] -or $samples[0] -is [bool]) {
                    throw 'INVALID_MEMORY_SAMPLE'
                }
                $sampleText = [Convert]::ToString($samples[0], [Globalization.CultureInfo]::InvariantCulture)
                $freeMemoryBytes = [int64]0
                if (-not [int64]::TryParse(
                    $sampleText,
                    [Globalization.NumberStyles]::Integer,
                    [Globalization.CultureInfo]::InvariantCulture,
                    [ref]$freeMemoryBytes
                ) -or $freeMemoryBytes -lt 0) {
                    throw 'INVALID_MEMORY_SAMPLE'
                }
            }
            catch {
                throw 'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE'
            }

            if ($freeMemoryBytes -ge $MinimumFreeMemoryBytes) {
                $consecutiveSamples++
                if ($consecutiveSamples -ge $requiredConsecutiveSamples) {
                    return
                }
            }
            else {
                $consecutiveSamples = 0
            }

            $remainingMilliseconds = $timeoutMilliseconds - $stopwatch.ElapsedMilliseconds
            if ($remainingMilliseconds -le 0) {
                break
            }
            Start-Sleep -Milliseconds ([int][Math]::Min($sampleIntervalMilliseconds, $remainingMilliseconds))
        }
    }
    finally {
        $stopwatch.Stop()
    }
    throw 'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED'
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

function ConvertTo-ThriveLensResourcePolicyInt64 {
    param([Parameter(Mandatory)]$Value)

    if ($Value -is [enum] -or $Value -is [bool] -or
        $Value -isnot [sbyte] -and $Value -isnot [byte] -and
        $Value -isnot [int16] -and $Value -isnot [uint16] -and
        $Value -isnot [int32] -and $Value -isnot [uint32] -and
        $Value -isnot [int64] -and $Value -isnot [uint64]) {
        throw 'RESOURCE_GATE_MANIFEST_INVALID'
    }
    if ($Value -is [uint64] -and $Value -gt [uint64][int64]::MaxValue) {
        throw 'RESOURCE_GATE_MANIFEST_INVALID'
    }
    try { return [Convert]::ToInt64($Value, [Globalization.CultureInfo]::InvariantCulture) }
    catch { throw 'RESOURCE_GATE_MANIFEST_INVALID' }
}

function Read-ThriveLensResourceGateResult {
    param([Parameter(Mandatory)][byte[]]$Bytes)

    if ($Bytes.Length -lt 2 -or $Bytes.Length -gt 131072 -or
        ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and
         $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF)) {
        throw 'RESOURCE_GATE_RESULT_INVALID'
    }
    $document = $null
    try {
        $options = [Text.Json.JsonDocumentOptions]::new()
        $options.AllowTrailingCommas = $false
        $options.CommentHandling = [Text.Json.JsonCommentHandling]::Disallow
        $options.MaxDepth = 16
        $document = [Text.Json.JsonDocument]::Parse(
            [ReadOnlyMemory[byte]]::new($Bytes),
            $options
        )
        if ($document.RootElement.ValueKind -ne [Text.Json.JsonValueKind]::Object) {
            throw 'RESOURCE_GATE_RESULT_INVALID'
        }
        # Reject duplicate names, case aliases, control-bearing strings, and
        # malformed nested structures before selecting any policy value.
        Assert-ThriveLensConfigurationJsonElement -Element $document.RootElement
        $properties = @($document.RootElement.EnumerateObject())
        $expectedNames = @(
            'cap_gb','accounted_bytes','accounted_gb','remaining_gb','used_percent',
            'warning_percent','hard_stop_percent','file_count','roots',
            'missing_inactive_roots','nested_roots_already_covered','status','phase',
            'host_free_memory_gb'
        )
        if ($properties.Count -ne $expectedNames.Count) {
            throw 'RESOURCE_GATE_RESULT_INVALID'
        }
        for ($index = 0; $index -lt $expectedNames.Count; $index++) {
            if ([string]$properties[$index].Name -cne $expectedNames[$index]) {
                throw 'RESOURCE_GATE_RESULT_INVALID'
            }
        }
        foreach ($index in @(0, 2, 3, 4, 5, 6)) {
            if ($properties[$index].Value.ValueKind -ne [Text.Json.JsonValueKind]::Number) {
                throw 'RESOURCE_GATE_RESULT_INVALID'
            }
        }
        $accountedBytes = [int64]0
        if ($properties[1].Value.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
            -not $properties[1].Value.TryGetInt64([ref]$accountedBytes) -or
            $accountedBytes -lt 0) {
            throw 'RESOURCE_GATE_RESULT_INVALID'
        }
        $fileCount = [int64]0
        if ($properties[7].Value.ValueKind -ne [Text.Json.JsonValueKind]::Number -or
            -not $properties[7].Value.TryGetInt64([ref]$fileCount) -or
            $fileCount -lt 0) {
            throw 'RESOURCE_GATE_RESULT_INVALID'
        }
        foreach ($index in @(8, 9, 10)) {
            if ($properties[$index].Value.ValueKind -ne [Text.Json.JsonValueKind]::Array) {
                throw 'RESOURCE_GATE_RESULT_INVALID'
            }
        }
        if ($properties[11].Value.ValueKind -ne [Text.Json.JsonValueKind]::String -or
            [string]$properties[11].Value.GetString() -cnotin @('OK', 'WARNING') -or
            $properties[12].Value.ValueKind -ne [Text.Json.JsonValueKind]::String -or
            [string]::IsNullOrWhiteSpace([string]$properties[12].Value.GetString()) -or
            $properties[13].Value.ValueKind -notin @(
                [Text.Json.JsonValueKind]::Number,
                [Text.Json.JsonValueKind]::Null
            )) {
            throw 'RESOURCE_GATE_RESULT_INVALID'
        }
        return [pscustomobject]@{
            AccountedBytes = $accountedBytes
            Status = [string]$properties[11].Value.GetString()
        }
    }
    catch {
        if ([string]$_.Exception.Message -ceq 'RESOURCE_GATE_RESULT_INVALID') { throw }
        throw 'RESOURCE_GATE_RESULT_INVALID'
    }
    finally {
        if ($null -ne $document) { $document.Dispose() }
    }
}

function Invoke-ThriveLensResourceGate {
    param(
        [int64]$ProjectedAdditionalBytes = 0,
        [AllowNull()]$Manifest
    )

    $scriptPath = [IO.Path]::GetFullPath([IO.Path]::Combine(
        (Get-ThriveLensProjectRoot),
        'scripts',
        'check_resource_budget.ps1'
    ))
    if (-not [IO.File]::Exists($scriptPath)) {
        throw 'RESOURCE_GATE_UNAVAILABLE'
    }
    $pwshPath = [IO.Path]::GetFullPath([IO.Path]::Combine($PSHOME, 'pwsh.exe'))
    if (-not [IO.File]::Exists($pwshPath)) {
        throw 'RESOURCE_GATE_UNAVAILABLE'
    }
    $process = [Diagnostics.Process]::new()
    $standardOutputTask = $null
    $standardErrorTask = $null
    $budget = [ThriveLens.ResourceGateOutputBudgetV2]::new(131072)
    $stdoutSink = [ThriveLens.ResourceGateCaptureStreamV2]::new($budget)
    $stderrSink = [ThriveLens.ResourceGateCaptureStreamV2]::new($budget)
    $started = $false
    $readerSetupComplete = $false
    $runnerFailure = $null
    $watch = [Diagnostics.Stopwatch]::StartNew()
    try {
        $startInfo = [Diagnostics.ProcessStartInfo]::new()
        $startInfo.FileName = $pwshPath
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        $startInfo.RedirectStandardOutput = $true
        $startInfo.RedirectStandardError = $true
        $startInfo.ArgumentList.Add('-NoProfile')
        $startInfo.ArgumentList.Add('-NonInteractive')
        $startInfo.ArgumentList.Add('-File')
        $startInfo.ArgumentList.Add($scriptPath)
        $process.StartInfo = $startInfo
        try {
            if (-not $process.Start()) { throw 'RESOURCE_GATE_PROCESS_START_FAILED' }
            $started = $true
        }
        catch {
            if ($_.Exception.Message -ceq 'RESOURCE_GATE_PROCESS_START_FAILED') { throw }
            throw 'RESOURCE_GATE_PROCESS_START_FAILED'
        }

        $standardOutputTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutSink)
        $standardErrorTask = $process.StandardError.BaseStream.CopyToAsync($stderrSink)
        $readerSetupComplete = $true
        while (-not $process.HasExited) {
            if ($budget.Exceeded) {
                $runnerFailure = 'RESOURCE_GATE_OUTPUT_LIMIT'
                break
            }
            if ($standardOutputTask.IsFaulted -or $standardOutputTask.IsCanceled -or
                $standardErrorTask.IsFaulted -or $standardErrorTask.IsCanceled) {
                $runnerFailure = if ($budget.Exceeded) {
                    'RESOURCE_GATE_OUTPUT_LIMIT'
                }
                else {
                    'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
                }
                break
            }
            if ($watch.ElapsedMilliseconds -ge 30000) {
                $runnerFailure = 'RESOURCE_GATE_TIMEOUT'
                break
            }
            [Threading.Thread]::Sleep(10)
        }

        if ($null -ne $runnerFailure) { throw $runnerFailure }
        $remainingMilliseconds = [Math]::Max(0, 30000 - [int]$watch.ElapsedMilliseconds)
        try {
            if (-not [Threading.Tasks.Task]::WaitAll(
                @($standardOutputTask, $standardErrorTask),
                $remainingMilliseconds
            )) {
                throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
            }
        }
        catch {
            if ($budget.Exceeded) { throw 'RESOURCE_GATE_OUTPUT_LIMIT' }
            if ($_.Exception.Message -ceq 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE') { throw }
            throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
        }
        try {
            $standardOutputTask.GetAwaiter().GetResult()
            $standardErrorTask.GetAwaiter().GetResult()
        }
        catch {
            if ($budget.Exceeded) { throw 'RESOURCE_GATE_OUTPUT_LIMIT' }
            throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
        }
        if ($budget.Exceeded) { throw 'RESOURCE_GATE_OUTPUT_LIMIT' }
        $stdoutBytes = $stdoutSink.ToArray()
        $stderrBytes = $stderrSink.ToArray()
        try {
            if ($process.ExitCode -ne 0) { throw 'RESOURCE_GATE_FAILED' }
            if ($stderrBytes.Length -ne 0) { throw 'RESOURCE_GATE_RESULT_INVALID' }
            $result = Read-ThriveLensResourceGateResult -Bytes $stdoutBytes
        }
        finally {
            [Array]::Clear($stdoutBytes, 0, $stdoutBytes.Length)
            [Array]::Clear($stderrBytes, 0, $stderrBytes.Length)
        }
    }
    catch {
        $code = [string]$_.Exception.Message
        $cleanupVerified = -not $started
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) } catch { }
            try { $cleanupVerified = $process.WaitForExit(5000) -and $process.HasExited }
            catch { $cleanupVerified = $false }
        }
        elseif ($started) {
            $cleanupVerified = $process.HasExited
        }
        $tasks = @(@($standardOutputTask, $standardErrorTask) | Where-Object { $null -ne $_ })
        if ($tasks.Count -gt 0) {
            try {
                $null = [Threading.Tasks.Task]::WaitAll($tasks, 5000)
            }
            catch {
                # A bounded-output task is expected to fault after enforcing the
                # shared cap. It is still joined once it reaches a terminal state.
            }
            if (@($tasks | Where-Object { -not $_.IsCompleted }).Count -ne 0) {
                $cleanupVerified = $false
            }
        }
        if ($started -and -not $readerSetupComplete) {
            $code = 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
        }
        if (-not $cleanupVerified) { throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE' }
        if ($code -cin @(
            'RESOURCE_GATE_FAILED','RESOURCE_GATE_PROCESS_START_FAILED',
            'RESOURCE_GATE_TIMEOUT','RESOURCE_GATE_OUTPUT_LIMIT',
            'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE','RESOURCE_GATE_RESULT_INVALID'
        )) { throw $code }
        throw 'RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
    }
    finally {
        $watch.Stop()
        $stdoutReaderComplete = $null -eq $standardOutputTask
        $stderrReaderComplete = $null -eq $standardErrorTask
        if ($null -ne $standardOutputTask) {
            try { $stdoutReaderComplete = $standardOutputTask.IsCompleted }
            catch { $stdoutReaderComplete = $false }
        }
        if ($null -ne $standardErrorTask) {
            try { $stderrReaderComplete = $standardErrorTask.IsCompleted }
            catch { $stderrReaderComplete = $false }
        }
        if ($stdoutReaderComplete) { $stdoutSink.Dispose() }
        if ($stderrReaderComplete) { $stderrSink.Dispose() }
        $rootInactive = -not $started
        if ($started) {
            try { $rootInactive = $process.HasExited }
            catch { $rootInactive = $false }
        }
        if ($rootInactive -and $stdoutReaderComplete -and $stderrReaderComplete) {
            $process.Dispose()
        }
        $standardOutputTask = $null
        $standardErrorTask = $null
    }

    $accountedBytes = [int64]$result.AccountedBytes

    if ($PSBoundParameters.ContainsKey('Manifest')) {
        try {
            $manifestValues = @($Manifest)
            if ($manifestValues.Count -ne 1 -or $null -eq $manifestValues[0] -or
                $manifestValues[0] -isnot [pscustomobject]) {
                throw 'RESOURCE_GATE_MANIFEST_INVALID'
            }
            $resolvedManifest = $manifestValues[0]
            $policyProperties = @($resolvedManifest.PSObject.Properties | Where-Object {
                $_.Name -ceq 'resource_policy'
            })
            if ($policyProperties.Count -ne 1 -or $null -eq $policyProperties[0].Value -or
                $policyProperties[0].Value -isnot [pscustomobject]) {
                throw 'RESOURCE_GATE_MANIFEST_INVALID'
            }
            $resourcePolicy = $policyProperties[0].Value
            $requiredProperties = @(
                'aggregate_cap_bytes',
                'hard_stop_percent',
                'minimum_free_disk_reserve_bytes'
            )
            foreach ($propertyName in $requiredProperties) {
                $matches = @($resourcePolicy.PSObject.Properties | Where-Object {
                    $_.Name -ceq $propertyName
                })
                if ($matches.Count -ne 1 -or $null -eq $matches[0].Value -or
                    $matches[0].Value -is [bool] -or
                    $matches[0].Value -isnot [ValueType]) {
                    throw 'RESOURCE_GATE_MANIFEST_INVALID'
                }
            }
            $capBytes = ConvertTo-ThriveLensResourcePolicyInt64 -Value $resourcePolicy.aggregate_cap_bytes
            $hardStopValue = ConvertTo-ThriveLensResourcePolicyInt64 -Value $resourcePolicy.hard_stop_percent
            $minimumFreeDiskReserveBytes = ConvertTo-ThriveLensResourcePolicyInt64 -Value $resourcePolicy.minimum_free_disk_reserve_bytes
            if ($hardStopValue -gt [int]::MaxValue) { throw 'RESOURCE_GATE_MANIFEST_INVALID' }
            $hardStopPercent = [int]$hardStopValue
            if ($capBytes -le 0 -or $hardStopPercent -le 0 -or
                $hardStopPercent -ge 100 -or $minimumFreeDiskReserveBytes -lt 0) {
                throw 'RESOURCE_GATE_MANIFEST_INVALID'
            }
        }
        catch { throw 'RESOURCE_GATE_MANIFEST_INVALID' }
    }
    else {
        $resolvedManifest = Get-ThriveLensManifest
        $capBytes = [int64]$resolvedManifest.resource_policy.aggregate_cap_bytes
        $hardStopPercent = [int]$resolvedManifest.resource_policy.hard_stop_percent
        $minimumFreeDiskReserveBytes = [int64]$resolvedManifest.resource_policy.minimum_free_disk_reserve_bytes
    }
    $projectedBytes = Assert-ThriveLensProjectedBudget `
        -AccountedBytes $accountedBytes `
        -AdditionalBytes $ProjectedAdditionalBytes `
        -CapBytes $capBytes `
        -HardStopPercent $hardStopPercent

    $root = Get-ThriveLensAttributableRoot
    $driveName = ([IO.Path]::GetPathRoot($root)).TrimEnd('\').TrimEnd(':')
    $drive = Get-PSDrive -Name $driveName -PSProvider FileSystem -ErrorAction Stop
    $null = Assert-ThriveLensFreeDiskBudget `
        -FreeDiskBytes ([int64]$drive.Free) `
        -AdditionalBytes $ProjectedAdditionalBytes `
        -ReserveBytes $minimumFreeDiskReserveBytes
    return [pscustomobject]@{
        AccountedBytes = $accountedBytes
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
    'Enter-ThriveLensConfigurationLease',
    'Assert-ThriveLensConfigurationLease',
    'Get-ThriveLensLeasedBackendManifest',
    'Get-ThriveLensLeasedResourceBudget',
    'Get-ThriveLensConfigurationLeaseFingerprint',
    'Exit-ThriveLensConfigurationLease',
    'Get-ThriveLensAttributableRoot',
    'Assert-ThriveLensOwnedPath',
    'Get-ThriveLensPostgresPaths',
    'Get-ThriveLensFreeMemoryBytes',
    'Wait-ThriveLensInterCycleMemorySettle',
    'Get-ThriveLensResourcePhase',
    'Assert-ThriveLensProjectedBudget',
    'Assert-ThriveLensFreeDiskBudget',
    'Invoke-ThriveLensResourceGate',
    'Measure-ThriveLensSafeTree',
    'Assert-ThriveLensComposeDataDirectory',
    'Assert-ThriveLensPathOutsideDirectory',
    'Assert-ThriveLensSecretFileAcl',
    'Read-ThriveLensPostgresBootstrapSecret',
    'Assert-ThriveLensVersionText',
    'Assert-ThriveLensPostgresVersions',
    'Test-ThriveLensPostgresRunning',
    'Get-ThriveLensExactPostgresProcesses',
    'Get-ThriveLensPostgresListeners',
    'Assert-ThriveLensLoopbackListener',
    'Assert-ThriveLensPostgresAbsent'
)
