#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('ThriveLens.BoundedCaptureStream' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;
namespace ThriveLens {
 public sealed class OutputBudget { public long Count; public readonly long Limit; public volatile bool Exceeded; public OutputBudget(long limit){Limit=limit;} }
 public sealed class BoundedCaptureStream : Stream {
  readonly OutputBudget budget; readonly MemoryStream data=new MemoryStream();
  public BoundedCaptureStream(OutputBudget b){budget=b;}
  void Put(byte[] buffer,int offset,int count){long total=Interlocked.Add(ref budget.Count,count);if(total>budget.Limit){budget.Exceeded=true;throw new IOException("OUTPUT_LIMIT");}data.Write(buffer,offset,count);}
  public byte[] ToArray(){return data.ToArray();}
  public override void Write(byte[] b,int o,int c){Put(b,o,c);}
  public override Task WriteAsync(byte[] b,int o,int c,CancellationToken t){Put(b,o,c);return Task.CompletedTask;}
  public override bool CanRead=>false;public override bool CanSeek=>false;public override bool CanWrite=>true;
  public override long Length=>data.Length;public override long Position{get=>data.Position;set=>throw new NotSupportedException();}
  public override void Flush(){} public override Task FlushAsync(CancellationToken t)=>Task.CompletedTask;
  public override int Read(byte[] b,int o,int c)=>throw new NotSupportedException();
  public override long Seek(long o,SeekOrigin s)=>throw new NotSupportedException();public override void SetLength(long v)=>throw new NotSupportedException();
  protected override void Dispose(bool disposing){if(disposing)data.Dispose();base.Dispose(disposing);}
 }
}
'@
}

function Get-ThriveLensWslContract {
    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    $manifest = Get-Content -LiteralPath (Join-Path $root 'config\toolchains\backend.json') -Raw | ConvertFrom-Json
    return [pscustomobject]@{ Root = $root; Manifest = $manifest; Wsl = $manifest.wsl_fallback }
}

function Invoke-ThriveLensWsl {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [string]$StandardInput
    )
    if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 300) { throw 'WSL_TIMEOUT_POLICY_INVALID' }
    $start = [Diagnostics.ProcessStartInfo]::new()
    $start.FileName = (Join-Path $env:SystemRoot 'System32\wsl.exe')
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $false
    $start.RedirectStandardError = $false
    $start.RedirectStandardInput = $null -ne $StandardInput
    $start.StandardOutputEncoding = [Text.Encoding]::UTF8
    $start.StandardErrorEncoding = [Text.Encoding]::UTF8
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.CreateNoWindow = $true
    foreach ($argument in $Arguments) { $null = $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new(); $process.StartInfo = $start
    $stdoutTask=$null;$stderrTask=$null;$budget=[ThriveLens.OutputBudget]::new(131072)
    $stdoutSink=[ThriveLens.BoundedCaptureStream]::new($budget);$stderrSink=[ThriveLens.BoundedCaptureStream]::new($budget);$started=$false
    try {
        if (-not $process.Start()) { throw 'WSL_PROCESS_START_FAILED' }
        $started = $true
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutSink)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrSink)
        if ($null -ne $StandardInput) { $process.StandardInput.Write($StandardInput); $process.StandardInput.Close() }
        $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
        while (-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 25
            if ($budget.Exceeded -or $stdoutTask.IsFaulted -or $stderrTask.IsFaulted) { throw 'WSL_OUTPUT_LIMIT_EXCEEDED' }
        }
        if (-not $process.HasExited) { throw 'WSL_COMMAND_TIMEOUT' }
        if (-not [Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask),5000)) {
            try { $process.Kill($true) } catch { }
            throw 'WSL_OUTPUT_DRAIN_INCOMPLETE'
        }
        if ($budget.Exceeded) { throw 'WSL_OUTPUT_LIMIT_EXCEEDED' }
        $captured=$stdoutSink.ToArray()
        $encoding=if($captured.Length -ge 2 -and (($captured[0] -eq 255 -and $captured[1] -eq 254) -or (@($captured|Where-Object{$_ -eq 0}).Count -gt ($captured.Length/4)))){[Text.Encoding]::Unicode}else{[Text.Encoding]::UTF8}
        return [pscustomobject]@{ ExitCode=$process.ExitCode;Output=($encoding.GetString($captured)).Trim([char]0).Trim();Error='' }
    }
    catch {
        if ($started -and -not $process.HasExited) { try { $process.Kill($true); $null=$process.WaitForExit(5000) } catch { } }
        if ($Arguments -contains '--distribution') {
            $terminateInfo=[Diagnostics.ProcessStartInfo]::new();$terminateInfo.FileName=(Join-Path $env:SystemRoot 'System32\wsl.exe');$terminateInfo.UseShellExecute=$false;$terminateInfo.CreateNoWindow=$true
            $null=$terminateInfo.ArgumentList.Add('--terminate');$null=$terminateInfo.ArgumentList.Add('ThriveLens-R0')
            $terminate=[Diagnostics.Process]::Start($terminateInfo)
            try {
                if (-not $terminate.WaitForExit(10000)) {
                    try{$terminate.Kill($true);$null=$terminate.WaitForExit(5000)}catch{}
                    throw 'WSL_PROCESS_TREE_TERMINATION_UNPROVEN'
                }
                if ($terminate.ExitCode -ne 0) { throw 'WSL_PROCESS_TREE_TERMINATION_UNPROVEN' }
            } finally { $terminate.Dispose() }
        }
        throw
    }
    finally {
        $process.Dispose();$stdoutSink.Dispose();$stderrSink.Dispose()
    }
}

function Invoke-ThriveLensDistro {
    param([Parameter(Mandatory)][string[]]$Arguments, [int]$TimeoutSeconds = 30, [string]$StandardInput)
    $contract = Get-ThriveLensWslContract
    if([string]$contract.Wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $all = @('--distribution', [string]$contract.Wsl.distribution_name, '--user', 'root', '--exec') + $Arguments
    return Invoke-ThriveLensWsl -Arguments $all -TimeoutSeconds $TimeoutSeconds -StandardInput $StandardInput
}

function Assert-ThriveLensWslIdentity {
    $contract = Get-ThriveLensWslContract
    $wsl = $contract.Wsl
    $version = Invoke-ThriveLensWsl -Arguments @('--version')
    if ($version.ExitCode -ne 0 -or $version.Output -notmatch '(?m)^WSL version:\s*2\.6\.3\.0\s*$') {
        throw 'WSL_VERSION_MISMATCH'
    }
    $matches = @()
    foreach ($key in @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop)) {
        $entry = Get-ItemProperty -LiteralPath $key.PSPath
        if ([string]$entry.DistributionName -ceq [string]$wsl.distribution_name) { $matches += $entry }
    }
    if ($matches.Count -ne 1) { throw 'WSL_DISTRO_IDENTITY_MISMATCH' }
    $expectedRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$wsl.distribution_install_root)).TrimEnd('\')
    $countedRoot = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens')).TrimEnd('\')
    if (-not $expectedRoot.StartsWith($countedRoot + '\',[StringComparison]::OrdinalIgnoreCase)) { throw 'WSL_STORAGE_OUTSIDE_ATTRIBUTABLE_ROOT' }
    $null = Assert-ThriveLensOwnedPath -Path $expectedRoot
    $actualRoot = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$matches[0].BasePath)).TrimEnd('\')
    if ($actualRoot -cne $expectedRoot -or [int]$matches[0].Version -ne 2) { throw 'WSL_DISTRO_LOCATION_MISMATCH' }
    $cursor = $expectedRoot
    while ($cursor -and $cursor.StartsWith([IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens')), [StringComparison]::OrdinalIgnoreCase)) {
        if ((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'WSL_STORAGE_REPARSE_REJECTED' }
        $cursor = Split-Path -Parent $cursor
    }
    $vhd = Join-Path $expectedRoot ([string]$wsl.distribution_vhd_filename)
    if (-not (Test-Path -LiteralPath $vhd -PathType Leaf)) { throw 'WSL_VHD_UNAVAILABLE' }
    if((Get-Item -LiteralPath $vhd -Force).Attributes -band [IO.FileAttributes]::ReparsePoint){throw 'WSL_VHD_REPARSE_REJECTED'}
    if ((Get-Item -LiteralPath $vhd).Length -gt [int64]$wsl.maximum_vhd_bytes) { throw 'WSL_VHD_LIMIT_EXCEEDED' }
    $release = Invoke-ThriveLensDistro -Arguments @('/usr/bin/dpkg-query','-W','-f=${Version}','base-files')
    if ($release.ExitCode -ne 0) { throw 'WSL_UBUNTU_IDENTITY_UNAVAILABLE' }
    $osRelease = Invoke-ThriveLensDistro -Arguments @('/usr/bin/grep','-Fx','VERSION_ID="24.04"','/etc/os-release')
    if ($osRelease.ExitCode -ne 0) { throw 'WSL_UBUNTU_RELEASE_MISMATCH' }
    $arch=Invoke-ThriveLensDistro -Arguments @('/usr/bin/dpkg','--print-architecture');if($arch.ExitCode -ne 0 -or $arch.Output -cne 'amd64'){throw 'WSL_ARCHITECTURE_MISMATCH'}
    $disk = Invoke-ThriveLensDistro -Arguments @('/usr/bin/df','-B1','--output=size','/')
    $numbers = @([regex]::Matches($disk.Output, '(?m)^\s*([0-9]+)\s*$') | ForEach-Object { [int64]$_.Groups[1].Value })
    if ($disk.ExitCode -ne 0 -or $numbers.Count -ne 1 -or $numbers[0] -gt [int64]$wsl.maximum_vhd_bytes) { throw 'WSL_VHD_CAPACITY_MISMATCH' }
    return [pscustomobject]@{ Distribution = [string]$wsl.distribution_name; Version = 2; VhdBytes = (Get-Item $vhd).Length; CapacityBytes = $numbers[0] }
}

function Assert-ThriveLensWslCleanupIdentity {
    $contract=Get-ThriveLensWslContract;$wsl=$contract.Wsl
    if([string]$wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $expected=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$wsl.distribution_install_root)).TrimEnd('\')
    $counted=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens')).TrimEnd('\')
    if(-not $expected.StartsWith($counted+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'WSL_STORAGE_OUTSIDE_ATTRIBUTABLE_ROOT'}
    $entries=@();foreach($key in @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop)){$entry=Get-ItemProperty -LiteralPath $key.PSPath;if([string]$entry.DistributionName -ceq 'ThriveLens-R0'){$entries+=$entry}}
    if($entries.Count -ne 1 -or [int]$entries[0].Version -ne 2){throw 'WSL_DISTRO_IDENTITY_MISMATCH'}
    $actual=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$entries[0].BasePath)).TrimEnd('\')
    if($actual -cne $expected){throw 'WSL_DISTRO_LOCATION_MISMATCH'}
    $null=Assert-ThriveLensOwnedPath -Path $actual
    return $true
}

function Assert-ThriveLensWslPackages {
    $wsl = (Get-ThriveLensWslContract).Wsl
    $keyHash = Invoke-ThriveLensDistro -Arguments @('/usr/bin/sha256sum',[string]$wsl.pgdg.keyring_path)
    if ($keyHash.ExitCode -ne 0 -or ($keyHash.Output -split '\s+')[0] -cne [string]$wsl.pgdg.keyring_sha256) { throw 'WSL_PGDG_KEY_HASH_MISMATCH' }
    $sourceHash = Invoke-ThriveLensDistro -Arguments @('/usr/bin/sha256sum',[string]$wsl.pgdg.source_path)
    if ($sourceHash.ExitCode -ne 0 -or ($sourceHash.Output -split '\s+')[0] -cne [string]$wsl.pgdg.source_sha256) { throw 'WSL_PGDG_SOURCE_HASH_MISMATCH' }
    $fingerprint = Invoke-ThriveLensDistro -Arguments @('/usr/bin/gpg','--batch','--show-keys','--with-colons',[string]$wsl.pgdg.keyring_path)
    if ($fingerprint.ExitCode -ne 0 -or $fingerprint.Output -notmatch "(?m)^fpr:::::::::$([regex]::Escape([string]$wsl.pgdg.signing_key_fingerprint)):$") { throw 'WSL_PGDG_KEY_FINGERPRINT_MISMATCH' }
    foreach($pair in @(@([string]$wsl.pgdg.policy_rc_d_path,[string]$wsl.pgdg.policy_rc_d_sha256),@([string]$wsl.pgdg.createcluster_path,[string]$wsl.pgdg.createcluster_sha256))){
        $hash=Invoke-ThriveLensDistro -Arguments @('/usr/bin/sha256sum',$pair[0]);if($hash.ExitCode -ne 0 -or ($hash.Output -split '\s+')[0] -cne $pair[1]){throw 'WSL_NO_AUTOSTART_POLICY_MISMATCH'}
    }
    foreach ($package in @($wsl.pgdg.package_closure)) {
        $probe = Invoke-ThriveLensDistro -Arguments @('/usr/bin/dpkg-query','-W','-f=${Status}\t${Version}\t${Architecture}',[string]$package.name)
        if ($probe.ExitCode -ne 0 -or $probe.Output -notmatch "^(?:install|hold) ok installed`t$([regex]::Escape([string]$package.version))`t$([regex]::Escape([string]$package.architecture))$") {
            throw 'WSL_PACKAGE_CLOSURE_MISMATCH'
        }
        $policy=Invoke-ThriveLensDistro -Arguments @('/usr/bin/apt-cache','policy',[string]$package.name)
        if($policy.ExitCode -ne 0 -or $policy.Output -notmatch "(?m)^\s*Installed:\s+$([regex]::Escape([string]$package.version))\s*$" -or $policy.Output -notmatch "(?m)^\s*Candidate:\s+$([regex]::Escape([string]$package.version))\s*$"){throw 'WSL_PACKAGE_CANDIDATE_MISMATCH'}
        if([string]$package.version -match 'pgdg' -and $policy.Output -notmatch '(?m)^\s*500 https://apt\.postgresql\.org/pub/repos/apt noble-pgdg/main amd64 Packages\s*$'){throw 'WSL_PACKAGE_ORIGIN_MISMATCH'}
    }
    $held = Invoke-ThriveLensDistro -Arguments @('/usr/bin/apt-mark','showhold')
    foreach ($packageName in @($wsl.pgdg.held_packages)) {
        if ($held.ExitCode -ne 0 -or @($held.Output -split "`r?`n") -cnotcontains [string]$packageName) { throw 'WSL_PACKAGE_HOLD_MISSING' }
    }
    foreach ($tool in @('postgres','pg_ctl','initdb','pg_isready')) {
        $probe = Invoke-ThriveLensDistro -Arguments @("/usr/lib/postgresql/17/bin/$tool",'--version')
        if ($probe.ExitCode -ne 0 -or $probe.Output -cne "$tool (PostgreSQL) 17.10 (Ubuntu 17.10-1.pgdg24.04+1)") { throw 'WSL_POSTGRES_VERSION_MISMATCH' }
    }
    $clusters = Invoke-ThriveLensDistro -Arguments @('/usr/bin/pg_lsclusters','--no-header')
    if ($clusters.ExitCode -ne 0) { throw 'WSL_CLUSTER_INVENTORY_UNAVAILABLE' }
    if (-not [string]::IsNullOrWhiteSpace($clusters.Output)) { throw 'WSL_UNMANAGED_CLUSTER_PRESENT' }
    foreach($unit in @('postgresql.service','postgresql@.service')){$service=Invoke-ThriveLensDistro -Arguments @('/usr/bin/systemctl','is-enabled',$unit);if($service.Output -cne 'masked'){throw 'WSL_POSTGRES_SERVICE_NOT_MASKED'}}
    $active=Invoke-ThriveLensDistro -Arguments @('/usr/bin/systemctl','is-active','postgresql.service');if($active.Output -cne 'inactive'){throw 'WSL_POSTGRES_SERVICE_ACTIVE'}
}

function Resolve-ThriveLensLinuxTreeRootPolicy {
    param(
        [Parameter(Mandatory)][string]$Root,
        [Parameter(Mandatory)][string]$DataRoot,
        [Parameter(Mandatory)][string]$LogRoot,
        [Parameter(Mandatory)][int64]$MaximumBytes
    )
    if ($DataRoot -cne '/var/lib/thrivelens/postgresql/r0' -or $LogRoot -cne '/var/log/thrivelens/postgresql/r0') {
        throw 'LINUX_TREE_ROOT_CONTRACT_MISMATCH'
    }
    foreach ($path in @($Root,$DataRoot,$LogRoot)) {
        if ($path -notmatch '^/[A-Za-z0-9._/-]+$' -or $path -match '(^|/)\.\.?(/|$)|//' -or $path.EndsWith('/') -or [Text.Encoding]::UTF8.GetByteCount($path) -gt 4095) {
            throw 'LINUX_TREE_ROOT_CONTRACT_MISMATCH'
        }
    }
    if ($MaximumBytes -lt 1 -or $MaximumBytes -gt 134217728) { throw 'LINUX_TREE_LIMIT_CONTRACT_MISMATCH' }
    if ($Root -ceq $DataRoot) {
        return [pscustomobject]@{ Kind='DATA'; MaximumBytes=$MaximumBytes }
    }
    if ($Root -ceq $LogRoot) {
        return [pscustomobject]@{ Kind='LOG'; MaximumBytes=$MaximumBytes }
    }
    $dataParent = $DataRoot.Substring(0,$DataRoot.LastIndexOf('/'))
    if ($Root -cmatch ('^'+[regex]::Escape($dataParent)+'/\.r0-staging-[0-9a-f]{32}$')) {
        return [pscustomobject]@{ Kind='STAGING'; MaximumBytes=$MaximumBytes }
    }
    throw 'LINUX_TREE_ROOT_CONTRACT_MISMATCH'
}

function Assert-ThriveLensLinuxTreePolicy {
    param([Parameter(Mandatory)][string]$Root)
    $contract = Get-ThriveLensWslContract
    $paths = Get-ThriveLensWslPaths
    $maximumEntries = [int64]$contract.Manifest.resource_policy.maximum_tree_entries
    $maximumBytes = [int64]$contract.Manifest.postgresql.maximum_initial_cluster_bytes
    if ($maximumEntries -ne 50000 -or $maximumBytes -ne 134217728) { throw 'LINUX_TREE_LIMIT_CONTRACT_MISMATCH' }
    $policy = Resolve-ThriveLensLinuxTreeRootPolicy -Root $Root -DataRoot $paths.DataRoot -LogRoot $paths.LogRoot -MaximumBytes $maximumBytes
    $probe = Invoke-ThriveLensDistro -TimeoutSeconds 60 -Arguments @('/usr/bin/python3','-c',@'
import os
import stat
import sys

ROOT = os.fsencode(sys.argv[1])
MAX_ENTRIES = int(sys.argv[2])
MAX_BYTES = int(sys.argv[3])
MAX_PATH_BYTES = int(sys.argv[4])
MAX_DEPTH = int(sys.argv[5])

UNAVAILABLE = 10
SYMLINK = 11
FOREIGN_DEVICE = 12
SPECIAL_FILE = 13
ENTRY_LIMIT = 14
BYTE_LIMIT = 15
PATH_LIMIT = 16
DEPTH_LIMIT = 17
MOUNT_REJECTED = 18
MOUNT_MEASUREMENT = 19
TREE_MEASUREMENT = 20

def stop(code):
    raise SystemExit(code)

def mount_path(field):
    for escaped, raw in ((b'\\040', b' '), (b'\\011', b'\t'), (b'\\012', b'\n'), (b'\\134', b'\\')):
        field = field.replace(escaped, raw)
    if b'\\' in field or not field.startswith(b'/'):
        stop(MOUNT_MEASUREMENT)
    return field

def assert_no_mounts():
    try:
        with open('/proc/self/mountinfo', 'rb', buffering=0) as mountinfo:
            for raw_line in mountinfo:
                fields = raw_line.rstrip(b'\n').split(b' ')
                if len(fields) < 10 or b'-' not in fields[6:]:
                    stop(MOUNT_MEASUREMENT)
                target = mount_path(fields[4])
                if target == ROOT or target.startswith(ROOT + b'/'):
                    stop(MOUNT_REJECTED)
    except OSError:
        stop(MOUNT_MEASUREMENT)

try:
    root_stat = os.lstat(ROOT)
except FileNotFoundError:
    stop(UNAVAILABLE)
except OSError:
    stop(TREE_MEASUREMENT)

cursor = b''
for component in ROOT.split(b'/')[1:]:
    cursor += b'/' + component
    try:
        if stat.S_ISLNK(os.lstat(cursor).st_mode):
            stop(SYMLINK)
    except OSError:
        stop(TREE_MEASUREMENT)
if not stat.S_ISDIR(root_stat.st_mode):
    stop(SPECIAL_FILE)

try:
    root_device = os.lstat(b'/').st_dev
except OSError:
    stop(TREE_MEASUREMENT)
if root_stat.st_dev != root_device:
    stop(FOREIGN_DEVICE)

assert_no_mounts()

flags = os.O_RDONLY | os.O_DIRECTORY
for optional in ('O_CLOEXEC', 'O_NOFOLLOW'):
    flags |= getattr(os, optional, 0)

entries = 1
measured_bytes = root_stat.st_size
if measured_bytes > MAX_BYTES:
    stop(BYTE_LIMIT)

def walk(directory_fd, path, depth):
    global entries, measured_bytes
    try:
        iterator = os.scandir(directory_fd)
        with iterator:
            for item in iterator:
                child_path = path + b'/' + os.fsencode(item.name)
                child_depth = depth + 1
                if len(child_path) > MAX_PATH_BYTES:
                    stop(PATH_LIMIT)
                if child_depth > MAX_DEPTH:
                    stop(DEPTH_LIMIT)
                try:
                    metadata = item.stat(follow_symlinks=False)
                except OSError:
                    stop(TREE_MEASUREMENT)
                entries += 1
                if entries > MAX_ENTRIES:
                    stop(ENTRY_LIMIT)
                measured_bytes += metadata.st_size
                if measured_bytes > MAX_BYTES:
                    stop(BYTE_LIMIT)
                mode = metadata.st_mode
                if stat.S_ISLNK(mode):
                    stop(SYMLINK)
                if metadata.st_dev != root_device:
                    stop(FOREIGN_DEVICE)
                if stat.S_ISDIR(mode):
                    try:
                        child_fd = os.open(item.name, flags, dir_fd=directory_fd)
                        opened = os.fstat(child_fd)
                    except OSError:
                        stop(TREE_MEASUREMENT)
                    if opened.st_dev != metadata.st_dev or opened.st_ino != metadata.st_ino or not stat.S_ISDIR(opened.st_mode):
                        os.close(child_fd)
                        stop(TREE_MEASUREMENT)
                    try:
                        walk(child_fd, child_path, child_depth)
                    finally:
                        os.close(child_fd)
                elif not stat.S_ISREG(mode):
                    stop(SPECIAL_FILE)
    except SystemExit:
        raise
    except OSError:
        stop(TREE_MEASUREMENT)

try:
    root_fd = os.open(ROOT, flags)
    opened_root = os.fstat(root_fd)
except OSError:
    stop(TREE_MEASUREMENT)
if opened_root.st_dev != root_stat.st_dev or opened_root.st_ino != root_stat.st_ino or not stat.S_ISDIR(opened_root.st_mode):
    os.close(root_fd)
    stop(TREE_MEASUREMENT)
try:
    walk(root_fd, ROOT, 0)
finally:
    os.close(root_fd)
assert_no_mounts()
try:
    final_root = os.lstat(ROOT)
except OSError:
    stop(TREE_MEASUREMENT)
if final_root.st_dev != root_stat.st_dev or final_root.st_ino != root_stat.st_ino or stat.S_ISLNK(final_root.st_mode):
    stop(TREE_MEASUREMENT)
'@,$Root,[string]$maximumEntries,[string]$policy.MaximumBytes,'4095','64')
    if (-not [string]::IsNullOrWhiteSpace($probe.Output)) { throw 'WSL_TREE_MEASUREMENT_FAILED' }
    $code = switch ($probe.ExitCode) {
        0  { $null }
        10 { 'WSL_TREE_ROOT_UNAVAILABLE' }
        11 { 'WSL_CLUSTER_TREE_SYMLINK_REJECTED' }
        12 { 'WSL_CLUSTER_FILESYSTEM_MISMATCH' }
        13 { 'WSL_CLUSTER_TREE_SPECIAL_FILE_REJECTED' }
        14 { 'WSL_CLUSTER_TREE_ENTRY_LIMIT_EXCEEDED' }
        15 { 'WSL_CLUSTER_TREE_BYTE_LIMIT_EXCEEDED' }
        16 { 'WSL_CLUSTER_TREE_PATH_LIMIT_EXCEEDED' }
        17 { 'WSL_CLUSTER_TREE_DEPTH_LIMIT_EXCEEDED' }
        18 { 'WSL_CLUSTER_PATH_MOUNT_REJECTED' }
        19 { 'WSL_MOUNT_MEASUREMENT_FAILED' }
        default { 'WSL_TREE_MEASUREMENT_FAILED' }
    }
    if ($null -ne $code) { throw $code }
    return [pscustomobject]@{ Status='VALID'; Kind=$policy.Kind }
}

function Assert-ThriveLensLinuxPathPolicy {
    param([switch]$RequireLeaf)
    $paths = Get-ThriveLensWslPaths
    $projectPaths=@('/var/lib/thrivelens','/var/lib/thrivelens/postgresql','/var/lib/thrivelens/postgresql/r0','/var/log/thrivelens','/var/log/thrivelens/postgresql','/var/log/thrivelens/postgresql/r0')
    foreach ($path in @('/var','/var/lib')+$projectPaths[0..2]+@('/var/log')+$projectPaths[3..5]) {
        if($path -notmatch '^/[^\\\x00-\x1f]+$' -or $path -match '(^|/)\.\.(/|$)|//'){throw 'LINUX_PATH_CONTRACT_MISMATCH'}
        $link = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-L',$path)
        if($link.ExitCode -eq 0){throw 'WSL_CLUSTER_PATH_SYMLINK_REJECTED'};if($link.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
        $probe = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$path)
        if ($probe.ExitCode -eq 0) {
            $mount = Invoke-ThriveLensDistro -Arguments @('/usr/bin/findmnt','--mountpoint',$path,'--noheadings')
            if ($mount.ExitCode -eq 0) { throw 'WSL_CLUSTER_PATH_MOUNT_REJECTED' }
            if($mount.ExitCode -notin @(0,1)){throw 'WSL_MOUNT_MEASUREMENT_FAILED'}
        }
        elseif($probe.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
    }
    $rootDevice = Invoke-ThriveLensDistro -Arguments @('/usr/bin/stat','-c','%d','/')
    if($rootDevice.ExitCode -ne 0 -or $rootDevice.Output -notmatch '^[0-9]+$'){throw 'WSL_ROOT_DEVICE_MEASUREMENT_FAILED'}
    foreach ($path in $projectPaths) {
        $exists = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$path)
        if ($exists.ExitCode -eq 0) {
            $device = Invoke-ThriveLensDistro -Arguments @('/usr/bin/stat','-c','%d',$path)
            $metadata = Invoke-ThriveLensDistro -Arguments @('/usr/bin/stat','-c','%U:%G:%a',$path)
            if ($device.ExitCode -ne 0 -or $device.Output -cne $rootDevice.Output) { throw 'WSL_CLUSTER_FILESYSTEM_MISMATCH' }
            if ($metadata.ExitCode -ne 0 -or $metadata.Output -cne 'postgres:postgres:700') { throw 'WSL_CLUSTER_PATH_METADATA_MISMATCH' }
        }
        elseif($exists.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
        elseif ($RequireLeaf -and $path -in @($paths.DataRoot,$paths.LogRoot)) { throw 'WSL_CLUSTER_PATH_UNAVAILABLE' }
    }
    foreach ($root in @($paths.DataRoot,$paths.LogRoot)) {
        $exists = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$root)
        if ($exists.ExitCode -eq 0) { $null = Assert-ThriveLensLinuxTreePolicy -Root $root }
        elseif ($exists.ExitCode -ne 1) { throw 'WSL_PATH_MEASUREMENT_FAILED' }
    }
}

function Get-ThriveLensWslPaths {
    $wsl = (Get-ThriveLensWslContract).Wsl
    return [pscustomobject]@{
        DataRoot = [string]$wsl.cluster_data_root
        LogRoot = [string]$wsl.cluster_log_root
        PgCtl = '/usr/lib/postgresql/17/bin/pg_ctl'
        InitDb = '/usr/lib/postgresql/17/bin/initdb'
        Postgres = '/usr/lib/postgresql/17/bin/postgres'
        PgIsReady = '/usr/lib/postgresql/17/bin/pg_isready'
        Port = 55432
    }
}

function Assert-ThriveLensDataInventoryGate {
    $contract = Get-ThriveLensWslContract
    $path = Join-Path $contract.Root 'docs\privacy\DATA_INVENTORY.md'
    $raw = Get-Content -LiteralPath $path -Raw
    if ($raw -notmatch [regex]::Escape('Dedicated R0 WSL distribution state:') -or
        $raw -notmatch [regex]::Escape('R0 PostgreSQL cluster infrastructure state:') -or
        $raw -notmatch [regex]::Escape('SCRAM password verifiers')) {
        throw 'DATA_INVENTORY_UPDATE_REQUIRED'
    }
}

function Assert-ThriveLensWslInternalDisk {
    param([int64]$RequiredBytes)
    $wsl=(Get-ThriveLensWslContract).Wsl
    $probe=Invoke-ThriveLensDistro -Arguments @('/usr/bin/df','-B1','--output=avail','/')
    $values=@([regex]::Matches($probe.Output,'(?m)^\s*([0-9]+)\s*$')|ForEach-Object{[int64]$_.Groups[1].Value})
    if($probe.ExitCode -ne 0 -or $values.Count -ne 1){throw 'WSL_FREE_DISK_MEASUREMENT_UNAVAILABLE'}
    if($values[0] -lt ($RequiredBytes + 536870912)){throw 'WSL_FREE_DISK_INSUFFICIENT'}
}

function Test-ThriveLensWslClusterExists {
    $paths = Get-ThriveLensWslPaths
    $probe = Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-f',"$($paths.DataRoot)/PG_VERSION")
    return $probe.ExitCode -eq 0
}

function Assert-ThriveLensClusterScramConfig {
    $paths=Get-ThriveLensWslPaths
    $probe=Invoke-ThriveLensDistro -Arguments @('/usr/bin/python3','-c',@'
import pathlib,sys
p=pathlib.Path(sys.argv[1])/'pg_hba.conf'
try: lines=p.read_text(encoding='utf-8').splitlines()
except OSError: raise SystemExit(2)
rules=[]
for raw in lines:
    line=raw.split('#',1)[0].strip()
    if not line: continue
    fields=line.split()
    if len(fields)<4: raise SystemExit(3)
    rules.append(fields)
if not rules or any(fields[-1] != 'scram-sha-256' for fields in rules): raise SystemExit(4)
print(len(rules))
'@,$paths.DataRoot)
    if($probe.ExitCode -ne 0 -or $probe.Output -notmatch '^[1-9][0-9]*$'){throw 'CLUSTER_HBA_SCRAM_MISMATCH'}
}

function Resolve-ThriveLensClusterProbe {
    param(
        [int]$ExistsExitCode,
        [bool]$PathPolicyValid,
        [int]$VersionExitCode,
        [string]$VersionOutput,
        [int]$ControlExitCode,
        [bool]$ChecksumsEnabled
    )
    if($ExistsExitCode -eq 1){return 'ABSENT'}
    if($ExistsExitCode -ne 0){throw 'CLUSTER_STATE_MEASUREMENT_UNAVAILABLE'}
    if(-not $PathPolicyValid -or $VersionExitCode -ne 0 -or $VersionOutput -cne '17' -or $ControlExitCode -ne 0 -or -not $ChecksumsEnabled){return 'PARTIAL_OR_INVALID'}
    return 'VALID'
}

function Get-ThriveLensWslClusterState {
    $paths=Get-ThriveLensWslPaths
    $exists=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$paths.DataRoot)
    if($exists.ExitCode -ne 0){return Resolve-ThriveLensClusterProbe -ExistsExitCode $exists.ExitCode -PathPolicyValid $false -VersionExitCode 1 -VersionOutput '' -ControlExitCode 1 -ChecksumsEnabled $false}
    try{
        Assert-ThriveLensLinuxPathPolicy -RequireLeaf
        $version=Invoke-ThriveLensDistro -Arguments @('/usr/bin/cat',"$($paths.DataRoot)/PG_VERSION")
        $control=Invoke-ThriveLensDistro -Arguments @('/usr/lib/postgresql/17/bin/pg_controldata',$paths.DataRoot)
        Assert-ThriveLensClusterScramConfig
        return Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode $version.ExitCode -VersionOutput $version.Output -ControlExitCode $control.ExitCode -ChecksumsEnabled ($control.Output -match '(?m)^Data page checksum version:\s+1\s*$')
    }catch{return 'PARTIAL_OR_INVALID'}
}

function Assert-ThriveLensWslAbsent {
    $paths = Get-ThriveLensWslPaths
    $running = Invoke-ThriveLensDistro -Arguments @('/usr/sbin/runuser','-u','postgres','--',$paths.PgCtl,'status','-D',$paths.DataRoot)
    if ($running.ExitCode -eq 0) { throw 'POSTGRES_CLUSTER_STILL_RUNNING' }
    $listener = Invoke-ThriveLensDistro -Arguments @('/usr/bin/ss','-H','-ltn','sport',':55432')
    if ($listener.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($listener.Output)) { throw 'POSTGRES_LISTENER_STILL_PRESENT' }
    $process = Invoke-ThriveLensDistro -Arguments @('/usr/bin/python3','-c',@'
import pathlib
target=b"/usr/lib/postgresql/17/bin/postgres"
data=b"/var/lib/thrivelens/postgresql/r0"
found=0
for item in pathlib.Path("/proc").iterdir():
    if not item.name.isdigit(): continue
    try:
        if pathlib.Path(item/"exe").resolve().as_posix().encode()==target:
            found+=1
    except (FileNotFoundError, ProcessLookupError): pass
    except PermissionError: raise SystemExit(3)
print(found)
'@)
    if ($process.ExitCode -ne 0 -or $process.Output -cne '0') { throw 'POSTGRES_PROCESS_STILL_PRESENT' }
}

function Assert-ThriveLensWslLoopback {
    $listener = Invoke-ThriveLensDistro -Arguments @('/usr/bin/ss','-H','-ltn','sport',':55432')
    if ($listener.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($listener.Output)) { throw 'POSTGRES_LISTENER_UNAVAILABLE' }
    foreach ($line in @($listener.Output -split "`r?`n")) {
        if ($line -notmatch '\s127\.0\.0\.1:55432\s') { throw 'POSTGRES_NON_LOOPBACK_LISTENER' }
    }
}

function Assert-ThriveLensHostPortAbsent {
    try{$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object LocalPort -eq 55432)}catch{throw 'HOST_LISTENER_MEASUREMENT_UNAVAILABLE'}
    if($listeners.Count -gt 0){throw 'HOST_POSTGRES_LISTENER_STILL_PRESENT'}
    Assert-ThriveLensNoHostPortProxy -FailureCode 'HOST_PORTPROXY_STILL_PRESENT'
}

function Resolve-ThriveLensPortProxyMapping {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )
    if($Source -notmatch '/(?<port>[0-9]{1,5})$'){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
    $listenPort=[int]$Matches.port
    if($Destination -notmatch '/(?<port>[0-9]{1,5})$'){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
    $connectPort=[int]$Matches.port
    if($listenPort -lt 1 -or $listenPort -gt 65535 -or $connectPort -lt 1 -or $connectPort -gt 65535){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
    return [pscustomobject]@{ListenPort=$listenPort;ConnectPort=$connectPort}
}

function Assert-ThriveLensNoHostPortProxy {
    param([Parameter(Mandatory)][ValidateSet('HOST_PORTPROXY_STILL_PRESENT','HOST_PORTPROXY_PRESENT')][string]$FailureCode)

    # Registry inspection is locale-independent and covers all four Windows
    # portproxy families. The netsh all-table view is measured as a second,
    # bounded surface so a registry/CLI representation drift fails closed.
    $tables=@('v4tov4','v4tov6','v6tov4','v6tov6')
    $registryMappings=[Collections.Generic.List[object]]::new()
    foreach($table in $tables){
        $key="HKLM:\SYSTEM\CurrentControlSet\Services\PortProxy\$table\tcp"
        try{$exists=Test-Path -LiteralPath $key -PathType Container -ErrorAction Stop}catch{throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
        if(-not $exists){continue}
        try{$item=Get-ItemProperty -LiteralPath $key -ErrorAction Stop}catch{throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
        foreach($property in @($item.PSObject.Properties|Where-Object{$_.Name -notlike 'PS*'})){
            $registryMappings.Add((Resolve-ThriveLensPortProxyMapping -Source ([string]$property.Name) -Destination ([string]$property.Value)))
        }
    }
    $portproxy=@(& netsh.exe interface portproxy show all 2>$null)
    if($LASTEXITCODE -ne 0 -or $portproxy.Count -gt 4096){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
    $netshMappings=[Collections.Generic.List[object]]::new()
    foreach($line in $portproxy){
        if([Text.Encoding]::UTF8.GetByteCount([string]$line) -gt 4096){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
        if([string]$line -match '^\s*\S+\s+(?<listen>[0-9]{1,5})\s+\S+\s+(?<connect>[0-9]{1,5})\s*$'){
            $listenPort=[int]$Matches.listen;$connectPort=[int]$Matches.connect
            if($listenPort -lt 1 -or $listenPort -gt 65535 -or $connectPort -lt 1 -or $connectPort -gt 65535){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
            $netshMappings.Add([pscustomobject]@{ListenPort=$listenPort;ConnectPort=$connectPort})
        }
    }
    if($netshMappings.Count -lt $registryMappings.Count){throw 'HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE'}
    foreach($mapping in @($registryMappings)+@($netshMappings)){
        if($mapping.ListenPort -eq 55432 -or $mapping.ConnectPort -eq 55432){throw $FailureCode}
    }
}

function Assert-ThriveLensHostLoopback {
    try{$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object LocalPort -eq 55432)}catch{throw 'HOST_LISTENER_MEASUREMENT_UNAVAILABLE'}
    foreach($listener in $listeners){if([string]$listener.LocalAddress -notin @('127.0.0.1','::1')){throw 'HOST_NON_LOOPBACK_LISTENER'}}
    Assert-ThriveLensNoHostPortProxy -FailureCode 'HOST_PORTPROXY_PRESENT'
    $client=[Net.Sockets.TcpClient]::new()
    try{$task=$client.ConnectAsync('127.0.0.1',55432);if(-not $task.Wait(5000) -or -not $client.Connected){throw 'HOST_TCP_REACHABILITY_FAILED'}}finally{$client.Dispose()}
}

function Stop-ThriveLensPostgresUnderLock {
    $state=Get-ThriveLensWslClusterState
    $wasRunning=$false
    if($state -ceq 'VALID'){
        Assert-ThriveLensLinuxPathPolicy -RequireLeaf
        $p=Get-ThriveLensWslPaths
        $status=Invoke-ThriveLensDistro -Arguments @('/usr/sbin/runuser','-u','postgres','--',$p.PgCtl,'status','-D',$p.DataRoot)
        $wasRunning=$status.ExitCode -eq 0
        if($wasRunning){$stop=Invoke-ThriveLensDistro -TimeoutSeconds 45 -Arguments @('/usr/sbin/runuser','-u','postgres','--',$p.PgCtl,'stop','-D',$p.DataRoot,'-m','fast','-w','-t','30');if($stop.ExitCode -ne 0){throw 'POSTGRES_STOP_FAILED'}}
    }
    elseif($state -ceq 'PARTIAL_OR_INVALID'){
        Assert-ThriveLensWslAbsent
    }
    Assert-ThriveLensWslAbsent
    Assert-ThriveLensHostPortAbsent
    return $wasRunning
}

function Resolve-ThriveLensChildOutcome {
    param([int]$ExitCode,[bool]$IndependentCleanupVerified)
    if($ExitCode -eq 0){return [pscustomobject]@{Fatal=$false;Code=$null;ExitCode=0}}
    if($ExitCode -eq 3){return [pscustomobject]@{Fatal=$true;Code='CHILD_FATAL_PRESERVED';ExitCode=3}}
    if(-not $IndependentCleanupVerified){return [pscustomobject]@{Fatal=$true;Code='INDEPENDENT_CLEANUP_UNVERIFIED';ExitCode=3}}
    return [pscustomobject]@{Fatal=$false;Code='CHILD_BLOCKED';ExitCode=2}
}

function Stop-ThriveLensDistroAndVerify {
    $contract=Get-ThriveLensWslContract;if([string]$contract.Wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $result=Invoke-ThriveLensWsl -Arguments @('--terminate','ThriveLens-R0') -TimeoutSeconds 15
    if($result.ExitCode -ne 0){throw 'WSL_DISTRO_TERMINATE_FAILED'}
    Assert-ThriveLensDistroStopped
}

function Assert-ThriveLensDistroStopped {
    $running=Invoke-ThriveLensWsl -Arguments @('--list','--running','--quiet') -TimeoutSeconds 15
    if($running.ExitCode -ne 0){throw 'WSL_RUNNING_STATE_UNAVAILABLE'}
    if(@($running.Output -split "`r?`n") -ccontains 'ThriveLens-R0'){throw 'WSL_DISTRO_STILL_RUNNING'}
}

function Enter-ThriveLensLifecycleLock {
    param([int]$TimeoutSeconds=15)
    $mutex=[Threading.Mutex]::new($false,'Local\ThriveLens-R0-PostgreSQL-Lifecycle')
    try{
        if(-not $mutex.WaitOne([TimeSpan]::FromSeconds($TimeoutSeconds))){$mutex.Dispose();throw 'LIFECYCLE_LOCK_TIMEOUT'}
    }
    catch [Threading.AbandonedMutexException] {
        # The caller now owns the abandoned mutex. Every lifecycle caller
        # revalidates resource, distro, cluster, process, listener and path
        # state under this lock before mutation, enabling safe crash recovery.
        return $mutex
    }
    catch{if($null -ne $mutex){$mutex.Dispose()};throw}
    return $mutex
}

function Exit-ThriveLensLifecycleLock {
    param([Parameter(Mandatory)][Threading.Mutex]$Mutex)
    try{$Mutex.ReleaseMutex()}finally{$Mutex.Dispose()}
}

Export-ModuleMember -Function @(
    'Get-ThriveLensWslContract','Invoke-ThriveLensDistro',
    'Assert-ThriveLensWslIdentity','Assert-ThriveLensWslCleanupIdentity','Assert-ThriveLensWslPackages','Get-ThriveLensWslPaths',
    'Assert-ThriveLensDataInventoryGate','Test-ThriveLensWslClusterExists','Assert-ThriveLensClusterScramConfig','Resolve-ThriveLensClusterProbe','Get-ThriveLensWslClusterState',
    'Assert-ThriveLensWslInternalDisk','Resolve-ThriveLensLinuxTreeRootPolicy','Assert-ThriveLensLinuxTreePolicy','Assert-ThriveLensLinuxPathPolicy',
    'Assert-ThriveLensWslAbsent','Assert-ThriveLensWslLoopback','Assert-ThriveLensHostPortAbsent','Resolve-ThriveLensPortProxyMapping','Assert-ThriveLensNoHostPortProxy','Assert-ThriveLensHostLoopback',
    'Stop-ThriveLensPostgresUnderLock','Stop-ThriveLensDistroAndVerify','Assert-ThriveLensDistroStopped','Resolve-ThriveLensChildOutcome',
    'Enter-ThriveLensLifecycleLock','Exit-ThriveLensLifecycleLock'
)
