#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:HeldLifecycleLocks = @{}

$wslSecurityTypeNames=@(
    'ThriveLens.WslSecurityV2.OutputBudget',
    'ThriveLens.WslSecurityV2.BoundedCaptureStream',
    'ThriveLens.WslSecurityV2.HostFileIdentity',
    'ThriveLens.WslSecurityV2.MutexOwnershipVerifier'
)
$existingWslSecurityTypes=@($wslSecurityTypeNames|Where-Object{$_ -as [type]})
if($existingWslSecurityTypes.Count -eq 0){
    try{Add-Type -TypeDefinition @'
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32.SafeHandles;
namespace ThriveLens.WslSecurityV2 {
 public sealed class OutputBudget { public const int ContractVersion=2; public long Count; public readonly long Limit; public volatile bool Exceeded; public OutputBudget(long limit){Limit=limit;} }
 public sealed class BoundedCaptureStream : Stream {
  public const int ContractVersion=2;
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
 public sealed class HostFileIdentity {
  public const int ContractVersion=2;
  public string FinalPath { get; private set; }
  public string Identity { get; private set; }
  public FileAttributes Attributes { get; private set; }
  public uint LinkCount { get; private set; }
  HostFileIdentity(string path,string identity,FileAttributes attributes,uint links){FinalPath=path;Identity=identity;Attributes=attributes;LinkCount=links;}
  [StructLayout(LayoutKind.Sequential)] struct Info {
   public uint FileAttributes; public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
   public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime; public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
   public uint VolumeSerialNumber; public uint FileSizeHigh; public uint FileSizeLow; public uint NumberOfLinks; public uint FileIndexHigh; public uint FileIndexLow;
  }
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern SafeFileHandle CreateFileW(string name,uint access,uint share,IntPtr security,uint creation,uint flags,IntPtr template);
  [DllImport("kernel32.dll",SetLastError=true)] static extern bool GetFileInformationByHandle(SafeFileHandle file,out Info info);
  [DllImport("kernel32.dll",CharSet=CharSet.Unicode,SetLastError=true)] static extern uint GetFinalPathNameByHandle(SafeFileHandle file,StringBuilder path,uint length,uint flags);
  public static HostFileIdentity Capture(string path){
   const uint FILE_READ_ATTRIBUTES=0x80, SHARE_ALL=7, OPEN_EXISTING=3, OPEN_REPARSE_POINT=0x00200000, BACKUP_SEMANTICS=0x02000000;
   using(SafeFileHandle file=CreateFileW(path,FILE_READ_ATTRIBUTES,SHARE_ALL,IntPtr.Zero,OPEN_EXISTING,OPEN_REPARSE_POINT|BACKUP_SEMANTICS,IntPtr.Zero)){
    if(file.IsInvalid)throw new IOException("FILE_IDENTITY_UNAVAILABLE"); Info info;
    if(!GetFileInformationByHandle(file,out info))throw new IOException("FILE_IDENTITY_UNAVAILABLE");
    uint capacity=512;StringBuilder finalPath=new StringBuilder((int)capacity);uint written=GetFinalPathNameByHandle(file,finalPath,capacity,0);
    if(written==0)throw new IOException("FILE_FINAL_PATH_UNAVAILABLE");
    if(written>=capacity){capacity=checked(written+1);finalPath=new StringBuilder((int)capacity);written=GetFinalPathNameByHandle(file,finalPath,capacity,0);if(written==0||written>=capacity)throw new IOException("FILE_FINAL_PATH_UNAVAILABLE");}
    string identity=info.VolumeSerialNumber.ToString("X8")+":"+info.FileIndexHigh.ToString("X8")+info.FileIndexLow.ToString("X8");
    return new HostFileIdentity(finalPath.ToString(),identity,(FileAttributes)info.FileAttributes,info.NumberOfLinks);
   }
  }
 }
 public static class MutexOwnershipVerifier {
  public const int ContractVersion=2;
  public static bool IsOwnedByCurrentThread(Mutex mutex){
   if(mutex==null)return false;bool recursive=false;
   try{recursive=mutex.WaitOne(0);}catch(AbandonedMutexException){recursive=true;}catch(ObjectDisposedException){return false;}
   if(!recursive)return false;
   try{mutex.ReleaseMutex();}catch(ApplicationException){return false;}
   bool otherAcquired=false;Exception failure=null;
   Thread probe=new Thread(()=>{try{if(mutex.WaitOne(0)){otherAcquired=true;mutex.ReleaseMutex();}}catch(Exception error){failure=error;}});
   probe.IsBackground=true;probe.Start();if(!probe.Join(2000))return false;
   return failure==null&&!otherAcquired;
  }
  public static bool CheckFromNewThread(Mutex mutex){
   bool result=true;Thread probe=new Thread(()=>{result=IsOwnedByCurrentThread(mutex);});
   probe.IsBackground=true;probe.Start();if(!probe.Join(2000))return false;return result;
  }
 }
}
'@
    }catch{throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'}
}
elseif($existingWslSecurityTypes.Count -ne $wslSecurityTypeNames.Count){
    throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'
}

try{
    $wslSecurityTypes=@($wslSecurityTypeNames|ForEach-Object{$_ -as [type]})
    if(@($wslSecurityTypes|Where-Object{$null -eq $_}).Count -ne 0 -or
       @($wslSecurityTypes|ForEach-Object Assembly|Select-Object -Unique).Count -ne 1){
        throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'
    }
    foreach($securityType in $wslSecurityTypes){
        $versionField=$securityType.GetField('ContractVersion',[Reflection.BindingFlags]'Public,Static')
        if($null -eq $versionField -or -not $versionField.IsLiteral -or
           [int]$versionField.GetRawConstantValue() -ne 2){throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'}
    }
    $hostIdentityType='ThriveLens.WslSecurityV2.HostFileIdentity' -as [type]
    $captureMethods=@($hostIdentityType.GetMethods([Reflection.BindingFlags]'Public,Static')|Where-Object{
        $_.Name -ceq 'Capture' -and $_.ReturnType -eq $hostIdentityType -and
        @($_.GetParameters()).Count -eq 1 -and $_.GetParameters()[0].ParameterType -eq [string]
    })
    if($captureMethods.Count -ne 1){throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'}

    $attestationBudget=[ThriveLens.WslSecurityV2.OutputBudget]::new(8)
    $attestationSink=[ThriveLens.WslSecurityV2.BoundedCaptureStream]::new($attestationBudget)
    try{
        $attestationSink.Write([byte[]](1,2,3,4),0,4)
        $attestationSink.Write([byte[]](5,6,7,8),0,4)
        $overflowObserved=$false
        try{$attestationSink.Write([byte[]](9),0,1)}catch{$overflowObserved=$true}
        $preserved=$attestationSink.ToArray()
        if(-not $overflowObserved -or -not $attestationBudget.Exceeded -or
           $attestationSink.Length -ne 8 -or ($preserved -join ',') -cne '1,2,3,4,5,6,7,8'){
            throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'
        }
    }finally{$attestationSink.Dispose()}

    $attestationMutex=[Threading.Mutex]::new($false)
    $attestationMutexHeld=$false
    try{
        $attestationMutexHeld=$attestationMutex.WaitOne(0)
        if(-not $attestationMutexHeld -or
           -not [ThriveLens.WslSecurityV2.MutexOwnershipVerifier]::IsOwnedByCurrentThread($attestationMutex)){
            throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'
        }
        $attestationMutex.ReleaseMutex();$attestationMutexHeld=$false
        if([ThriveLens.WslSecurityV2.MutexOwnershipVerifier]::IsOwnedByCurrentThread($attestationMutex)){
            throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'
        }
    }finally{if($attestationMutexHeld){$attestationMutex.ReleaseMutex()};$attestationMutex.Dispose()}

    $hostAttestation=[ThriveLens.WslSecurityV2.HostFileIdentity]::Capture($PSCommandPath)
    if([string]::IsNullOrWhiteSpace([string]$hostAttestation.FinalPath) -or
       [string]$hostAttestation.Identity -cnotmatch '^[0-9A-F]{8}:[0-9A-F]{16}$' -or
       [uint32]$hostAttestation.LinkCount -lt 1){throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'}
}
catch{throw 'WSL_SECURITY_TYPE_CONTRACT_MISMATCH'}

function Get-ThriveLensWslContract {
    param($ConfigurationLease)

    $root = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
    if ($PSBoundParameters.ContainsKey('ConfigurationLease')) {
        if ($null -eq $ConfigurationLease) { throw 'CONFIGURATION_LEASE_INVALID' }
        $manifestValues = @(Get-ThriveLensLeasedBackendManifest -Lease $ConfigurationLease)
        if ($manifestValues.Count -ne 1) { throw 'CONFIGURATION_LEASE_INVALID' }
        $manifest = $manifestValues[0]
    }
    else {
        $manifest = Get-Content -LiteralPath (Join-Path $root 'config\toolchains\backend.json') -Raw | ConvertFrom-Json
    }
    return [pscustomobject]@{ Root = $root; Manifest = $manifest; Wsl = $manifest.wsl_fallback }
}

function Invoke-ThriveLensWsl {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [string]$StandardInput,
        [switch]$CapturePrivateStandardError
    )
    if ($TimeoutSeconds -lt 1 -or $TimeoutSeconds -gt 300) { throw 'WSL_TIMEOUT_POLICY_INVALID' }
    $timeoutMilliseconds=[Math]::BigMul([int]$TimeoutSeconds,1000)
    $stdinBytes=$null
    if($null -ne $StandardInput){
        try{$stdinBytes=[Text.UTF8Encoding]::new($false,$true).GetBytes($StandardInput)}
        catch{throw 'WSL_STANDARD_INPUT_INVALID'}
        # Current inputs are a 43-128 byte bootstrap secret or a pgpass line
        # containing that secret plus fixed loopback metadata. 512 bytes leaves
        # bounded protocol headroom without accepting an arbitrary input body.
        if($stdinBytes.Length -gt 512){
            [Array]::Clear($stdinBytes,0,$stdinBytes.Length);$stdinBytes=$null
            throw 'WSL_STANDARD_INPUT_LIMIT_EXCEEDED'
        }
    }
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
    $stdoutTask=$null;$stderrTask=$null;$stdinWriteTask=$null;$stdinFlushTask=$null;$budget=[ThriveLens.WslSecurityV2.OutputBudget]::new(131072)
    $stdoutSink=[ThriveLens.WslSecurityV2.BoundedCaptureStream]::new($budget);$stderrSink=[ThriveLens.WslSecurityV2.BoundedCaptureStream]::new($budget);$started=$false
    $stopwatch=[Diagnostics.Stopwatch]::StartNew()
    try {
        if (-not $process.Start()) { throw 'WSL_PROCESS_START_FAILED' }
        $started = $true
        $stdoutTask = $process.StandardOutput.BaseStream.CopyToAsync($stdoutSink)
        $stderrTask = $process.StandardError.BaseStream.CopyToAsync($stderrSink)
        if($null -ne $stdinBytes){
            try{
                $remainingMilliseconds=[int][Math]::Min([int]::MaxValue,($timeoutMilliseconds-$stopwatch.ElapsedMilliseconds))
                if($remainingMilliseconds -le 0){throw 'WSL_COMMAND_TIMEOUT'}
                $stdinWriteTask=$process.StandardInput.BaseStream.WriteAsync($stdinBytes,0,$stdinBytes.Length)
                if(-not $stdinWriteTask.Wait($remainingMilliseconds)){throw 'WSL_COMMAND_TIMEOUT'}
            }
            catch{throw 'WSL_COMMAND_TIMEOUT'}
            try{
                $remainingMilliseconds=[int][Math]::Min([int]::MaxValue,($timeoutMilliseconds-$stopwatch.ElapsedMilliseconds))
                if($remainingMilliseconds -le 0){throw 'WSL_COMMAND_TIMEOUT'}
                $stdinFlushTask=$process.StandardInput.BaseStream.FlushAsync()
                if(-not $stdinFlushTask.Wait($remainingMilliseconds)){throw 'WSL_COMMAND_TIMEOUT'}
                $process.StandardInput.Close()
            }
            catch{throw 'WSL_COMMAND_TIMEOUT'}
        }
        while (-not $process.HasExited -and $stopwatch.ElapsedMilliseconds -lt $timeoutMilliseconds) {
            Start-Sleep -Milliseconds 25
            if ($budget.Exceeded -or $stdoutTask.IsFaulted -or $stderrTask.IsFaulted) { throw 'WSL_OUTPUT_LIMIT_EXCEEDED' }
        }
        if (-not $process.HasExited) { throw 'WSL_COMMAND_TIMEOUT' }
        if (-not [Threading.Tasks.Task]::WaitAll(@($stdoutTask,$stderrTask),5000)) {
            throw 'WSL_OUTPUT_DRAIN_INCOMPLETE'
        }
        if ($budget.Exceeded) { throw 'WSL_OUTPUT_LIMIT_EXCEEDED' }
        $captured=$stdoutSink.ToArray()
        $encoding=if($captured.Length -ge 2 -and (($captured[0] -eq 255 -and $captured[1] -eq 254) -or (@($captured|Where-Object{$_ -eq 0}).Count -gt ($captured.Length/4)))){[Text.Encoding]::Unicode}else{[Text.Encoding]::UTF8}
        $decodedOutput=$encoding.GetString($captured)
        $privateOutput=$null
        $privateError=$null
        if($CapturePrivateStandardError){
            $privateOutput=$decodedOutput
            $capturedError=$stderrSink.ToArray()
            $errorEncoding=if($capturedError.Length -ge 2 -and (($capturedError[0] -eq 255 -and $capturedError[1] -eq 254) -or (@($capturedError|Where-Object{$_ -eq 0}).Count -gt ($capturedError.Length/4)))){[Text.Encoding]::Unicode}else{[Text.Encoding]::UTF8}
            $privateError=$errorEncoding.GetString($capturedError)
            [Array]::Clear($capturedError,0,$capturedError.Length)
        }
        return [pscustomobject]@{ ExitCode=$process.ExitCode;Output=$decodedOutput.Trim([char]0).Trim();PrivateStandardOutput=$privateOutput;PrivateStandardError=$privateError }
    }
    catch {
        $failureCode=if(-not $started){'WSL_PROCESS_START_FAILED'}elseif(
            [string]$_.Exception.Message -cin @(
                'WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED',
                'WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED'
            )
        ){[string]$_.Exception.Message}else{'WSL_OUTPUT_DRAIN_INCOMPLETE'}
        $cleanupProven=$true
        if($started){
            $rootReaped=$false
            try{
                if(-not $process.HasExited){$process.Kill($true)}
                $rootReaped=$process.WaitForExit(5000)
                if($rootReaped){$rootReaped=$process.HasExited}
            }
            catch{$rootReaped=$false}
            if(-not $rootReaped){$cleanupProven=$false}

            # CopyToAsync can be established for only one stream when setup
            # fails. Join every task that exists, independently and boundedly;
            # faulted tasks count as joined only after they are completed.
            foreach($ioTask in @($stdoutTask,$stderrTask,$stdinWriteTask,$stdinFlushTask)){
                if($null -eq $ioTask){continue}
                try{if(-not $ioTask.IsCompleted){$null=$ioTask.Wait(5000)}}catch{}
                try{if(-not $ioTask.IsCompleted){$cleanupProven=$false}}catch{$cleanupProven=$false}
            }
        }
        # Killing the Windows process tree is always safe. Distro termination is
        # intentionally not attempted here: a name alone is not authority to
        # mutate WSL state. Lifecycle callers must hold the project mutex and
        # present a freshly revalidated host-only identity token.
        if(-not $cleanupProven){throw 'WSL_OUTPUT_DRAIN_INCOMPLETE'}
        throw $failureCode
    }
    finally {
        $stopwatch.Stop()
        if($null -ne $stdinBytes){[Array]::Clear($stdinBytes,0,$stdinBytes.Length);$stdinBytes=$null}
        $stdoutComplete=$null -eq $stdoutTask
        $stderrComplete=$null -eq $stderrTask
        $stdinWriteComplete=$null -eq $stdinWriteTask
        $stdinFlushComplete=$null -eq $stdinFlushTask
        if($null -ne $stdoutTask){try{$stdoutComplete=$stdoutTask.IsCompleted}catch{$stdoutComplete=$false}}
        if($null -ne $stderrTask){try{$stderrComplete=$stderrTask.IsCompleted}catch{$stderrComplete=$false}}
        if($null -ne $stdinWriteTask){try{$stdinWriteComplete=$stdinWriteTask.IsCompleted}catch{$stdinWriteComplete=$false}}
        if($null -ne $stdinFlushTask){try{$stdinFlushComplete=$stdinFlushTask.IsCompleted}catch{$stdinFlushComplete=$false}}
        if($stdoutComplete){$stdoutSink.Dispose()}
        if($stderrComplete){$stderrSink.Dispose()}
        $rootInactive=-not $started
        if($started){try{$rootInactive=$process.HasExited}catch{$rootInactive=$false}}
        if($rootInactive -and $stdoutComplete -and $stderrComplete -and $stdinWriteComplete -and $stdinFlushComplete){$process.Dispose()}
    }
}

function Invoke-ThriveLensDistro {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [string]$StandardInput,
        [switch]$CapturePrivateStandardError,
        $Contract
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if([string]$Contract.Wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $all = @('--distribution', [string]$Contract.Wsl.distribution_name, '--user', 'root', '--exec') + $Arguments
    return Invoke-ThriveLensWsl -Arguments $all -TimeoutSeconds $TimeoutSeconds -StandardInput $StandardInput -CapturePrivateStandardError:$CapturePrivateStandardError
}

function Invoke-ThriveLensGuardedDistro {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [string]$StandardInput,
        [switch]$CapturePrivateStandardError,
        $Contract
    )
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    $result=$null;$failureCode=$null;$postIdentityCode=$null
    try{
        $result=Invoke-ThriveLensDistro -Arguments $Arguments -TimeoutSeconds $TimeoutSeconds -StandardInput $StandardInput -CapturePrivateStandardError:$CapturePrivateStandardError -Contract $Contract
    }
    catch{
        $failureCode=if($_.Exception.Message -match '^[A-Z0-9_]+$'){$_.Exception.Message}else{'WSL_GUARDED_COMMAND_FAILED'}
    }
    finally{
        # Revalidate even when process start, output drain, budget, or timeout
        # handling throws. Identity drift never authorizes name-only cleanup.
        try{$null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract}
        catch{$postIdentityCode=if($_.Exception.Message -match '^[A-Z0-9_]+$'){$_.Exception.Message}else{'WSL_CLEANUP_IDENTITY_CHANGED'}}
    }
    if($null -ne $postIdentityCode){throw $postIdentityCode}
    if($null -ne $failureCode){
        # The host process tree has already been killed by Invoke-ThriveLensWsl.
        # Under the same mutex and unchanged identity, contain any surviving
        # guest child before callers can inspect or roll back filesystem state.
        try{
            Stop-ThriveLensDistroAndVerify -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
            Assert-ThriveLensHostPortAbsent -Contract $Contract
        }
        catch{throw 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED'}
        throw $failureCode
    }
    return $result
}

function Invoke-ThriveLensDistroProbe {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [int]$TimeoutSeconds = 30,
        [string]$StandardInput,
        [switch]$CapturePrivateStandardError,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    $hasIdentityToken = $null -ne $IdentityToken
    $hasLifecycleLock = $null -ne $LifecycleLock
    if ($hasIdentityToken -ne $hasLifecycleLock) { throw 'WSL_GUARD_ARGUMENT_MISMATCH' }
    if ($hasIdentityToken) {
        return Invoke-ThriveLensGuardedDistro `
            -IdentityToken $IdentityToken `
            -LifecycleLock $LifecycleLock `
            -Arguments $Arguments `
            -TimeoutSeconds $TimeoutSeconds `
            -StandardInput $StandardInput `
            -CapturePrivateStandardError:$CapturePrivateStandardError `
            -Contract $Contract
    }
    return Invoke-ThriveLensDistro `
        -Arguments $Arguments `
        -TimeoutSeconds $TimeoutSeconds `
        -StandardInput $StandardInput `
        -CapturePrivateStandardError:$CapturePrivateStandardError `
        -Contract $Contract
}

function Assert-ThriveLensLifecycleLockOwnership {
    param([Parameter(Mandatory)][Threading.Mutex]$LifecycleLock)
    $key=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($LifecycleLock)
    if(-not $script:HeldLifecycleLocks.ContainsKey($key)){
        throw 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED'
    }
    $record=$script:HeldLifecycleLocks[$key]
    if(-not [object]::ReferenceEquals($record.Mutex,$LifecycleLock) -or
       [int]$record.OwnerThreadId -ne [Environment]::CurrentManagedThreadId -or
       -not [ThriveLens.WslSecurityV2.MutexOwnershipVerifier]::IsOwnedByCurrentThread($LifecycleLock)){
        throw 'LIFECYCLE_LOCK_OWNERSHIP_REQUIRED'
    }
    return $true
}

function Get-ThriveLensVhdFileIdentity {
    param([Parameter(Mandatory)][string]$Path)
    if(-not ('ThriveLens.WslSecurityV2.HostFileIdentity' -as [type])){throw 'WSL_VHD_IDENTITY_PROVIDER_UNAVAILABLE'}
    try{
        $snapshot=[ThriveLens.WslSecurityV2.HostFileIdentity]::Capture($Path)
        $final=[string]$snapshot.FinalPath
        if($final.StartsWith('\\?\',[StringComparison]::Ordinal)){$final=$final.Substring(4)}
        $final=[IO.Path]::GetFullPath($final)
        if($final -cne [IO.Path]::GetFullPath($Path) -or $snapshot.LinkCount -ne 1 -or (($snapshot.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)){
            throw 'WSL_VHD_IDENTITY_MISMATCH'
        }
        return [pscustomobject]@{Path=$final;Identity=[string]$snapshot.Identity}
    }
    catch{
        if($_.Exception.Message -match '^WSL_VHD_'){throw}
        throw 'WSL_VHD_IDENTITY_UNAVAILABLE'
    }
}

function Get-ThriveLensWslCleanupIdentityToken {
    param(
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        $Contract
    )
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
    if ($null -eq $Contract) { $Contract=Get-ThriveLensWslContract }
    $wsl=$Contract.Wsl
    if([string]$wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $expected=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$wsl.distribution_install_root)).TrimEnd('\')
    $counted=[IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens')).TrimEnd('\')
    if(-not $expected.StartsWith($counted+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'WSL_STORAGE_OUTSIDE_ATTRIBUTABLE_ROOT'}
    $null=Assert-ThriveLensOwnedPath -Path $expected
    $matches=@()
    foreach($key in @(Get-ChildItem 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lxss' -ErrorAction Stop)){
        $entry=Get-ItemProperty -LiteralPath $key.PSPath -ErrorAction Stop
        if([string]$entry.DistributionName -ceq 'ThriveLens-R0'){$matches+=[pscustomobject]@{Key=[string]$key.PSChildName;Entry=$entry}}
    }
    if($matches.Count -ne 1){throw 'WSL_DISTRO_IDENTITY_MISMATCH'}
    $parsedGuid=[guid]::Empty
    if(-not [guid]::TryParse($matches[0].Key,[ref]$parsedGuid)){throw 'WSL_DISTRO_REGISTRY_ID_INVALID'}
    $actual=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$matches[0].Entry.BasePath)).TrimEnd('\')
    if($actual -cne $expected -or [int]$matches[0].Entry.Version -ne 2){throw 'WSL_DISTRO_LOCATION_MISMATCH'}
    $cursor=$actual
    while($cursor -and $cursor.StartsWith($counted,[StringComparison]::OrdinalIgnoreCase)){
        $item=Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if(($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0){throw 'WSL_STORAGE_REPARSE_REJECTED'}
        if($cursor -ceq $counted){break};$cursor=Split-Path -Parent $cursor
    }
    $vhdPath=Join-Path $actual ([string]$wsl.distribution_vhd_filename)
    $vhd=Get-ThriveLensVhdFileIdentity -Path $vhdPath
    return [pscustomobject]@{
        SchemaVersion=1;RegistryId=$parsedGuid.ToString('D');DistributionName='ThriveLens-R0';Version=2
        BasePath=$actual;VhdPath=$vhd.Path;VhdIdentity=$vhd.Identity
    }
}

function Compare-ThriveLensWslCleanupIdentityToken {
    param([Parameter(Mandatory)]$Expected,[Parameter(Mandatory)]$Actual)
    $names=@('SchemaVersion','RegistryId','DistributionName','Version','BasePath','VhdPath','VhdIdentity')
    foreach($name in $names){if($null -eq $Expected.PSObject.Properties[$name] -or $null -eq $Actual.PSObject.Properties[$name]){throw 'WSL_CLEANUP_IDENTITY_TOKEN_INVALID'}}
    if([int]$Expected.SchemaVersion -ne 1 -or [int]$Actual.SchemaVersion -ne 1 -or
       [string]$Expected.DistributionName -cne 'ThriveLens-R0' -or [string]$Actual.DistributionName -cne 'ThriveLens-R0' -or
       [int]$Expected.Version -ne 2 -or [int]$Actual.Version -ne 2){throw 'WSL_CLEANUP_IDENTITY_TOKEN_INVALID'}
    foreach($name in @('RegistryId','DistributionName','BasePath','VhdPath','VhdIdentity')){
        if([string]$Expected.$name -cne [string]$Actual.$name){throw 'WSL_CLEANUP_IDENTITY_CHANGED'}
    }
    if([int]$Expected.Version -ne [int]$Actual.Version){throw 'WSL_CLEANUP_IDENTITY_CHANGED'}
    return $true
}

function Assert-ThriveLensWslIdentity {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        $Contract
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    $wsl = $Contract.Wsl
    $version = Invoke-ThriveLensWsl -Arguments @('--version')
    $expectedWslVersion = [string]$wsl.wsl_version
    if ($version.ExitCode -ne 0 -or
        $version.Output -notmatch ("(?m)^WSL version:\s*" + [regex]::Escape($expectedWslVersion) + "\s*$")) {
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
    $release = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/dpkg-query','-W','-f=${Version}','base-files')
    if ($release.ExitCode -ne 0) { throw 'WSL_UBUNTU_IDENTITY_UNAVAILABLE' }
    $osRelease = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/grep','-Fx',("VERSION_ID=`"{0}`"" -f [string]$wsl.ubuntu_release),'/etc/os-release')
    if ($osRelease.ExitCode -ne 0) { throw 'WSL_UBUNTU_RELEASE_MISMATCH' }
    $arch=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/dpkg','--print-architecture');if($arch.ExitCode -ne 0 -or $arch.Output -cne [string]$wsl.pgdg.architecture){throw 'WSL_ARCHITECTURE_MISMATCH'}
    $disk = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/df','-B1','--output=size','/')
    $numbers = @([regex]::Matches($disk.Output, '(?m)^\s*([0-9]+)\s*$') | ForEach-Object { [int64]$_.Groups[1].Value })
    if ($disk.ExitCode -ne 0 -or $numbers.Count -ne 1 -or $numbers[0] -gt [int64]$wsl.maximum_vhd_bytes) { throw 'WSL_VHD_CAPACITY_MISMATCH' }
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    return [pscustomobject]@{ Distribution = [string]$wsl.distribution_name; Version = 2; VhdBytes = (Get-Item $vhd).Length; CapacityBytes = $numbers[0] }
}

function Assert-ThriveLensWslCleanupIdentity {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        $Contract
    )
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
    $current=Get-ThriveLensWslCleanupIdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    return Compare-ThriveLensWslCleanupIdentityToken -Expected $IdentityToken -Actual $current
}

function Assert-ThriveLensWslPackages {
    param(
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $wsl = $Contract.Wsl
    $paths = Get-ThriveLensWslPaths -Contract $Contract
    $postgresVersion = [string]$Contract.Manifest.postgresql.version
    $postgresMajor = $postgresVersion.Split('.')[0]
    $serverPackages = @($wsl.pgdg.package_closure | Where-Object {
        [string]$_.name -ceq "postgresql-$postgresMajor"
    })
    if ($serverPackages.Count -ne 1) { throw 'WSL_PACKAGE_CLOSURE_MISMATCH' }
    $keyHash = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/sha256sum',[string]$wsl.pgdg.keyring_path)
    if ($keyHash.ExitCode -ne 0 -or ($keyHash.Output -split '\s+')[0] -cne [string]$wsl.pgdg.keyring_sha256) { throw 'WSL_PGDG_KEY_HASH_MISMATCH' }
    $sourceHash = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/sha256sum',[string]$wsl.pgdg.source_path)
    if ($sourceHash.ExitCode -ne 0 -or ($sourceHash.Output -split '\s+')[0] -cne [string]$wsl.pgdg.source_sha256) { throw 'WSL_PGDG_SOURCE_HASH_MISMATCH' }
    $fingerprint = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/gpg','--batch','--show-keys','--with-colons',[string]$wsl.pgdg.keyring_path)
    if ($fingerprint.ExitCode -ne 0 -or $fingerprint.Output -notmatch "(?m)^fpr:::::::::$([regex]::Escape([string]$wsl.pgdg.signing_key_fingerprint)):$") { throw 'WSL_PGDG_KEY_FINGERPRINT_MISMATCH' }
    foreach($pair in @(@([string]$wsl.pgdg.policy_rc_d_path,[string]$wsl.pgdg.policy_rc_d_sha256),@([string]$wsl.pgdg.createcluster_path,[string]$wsl.pgdg.createcluster_sha256))){
        $hash=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/sha256sum',$pair[0]);if($hash.ExitCode -ne 0 -or ($hash.Output -split '\s+')[0] -cne $pair[1]){throw 'WSL_NO_AUTOSTART_POLICY_MISMATCH'}
    }
    foreach ($package in @($wsl.pgdg.package_closure)) {
        $probe = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/dpkg-query','-W','-f=${Status}\t${Version}\t${Architecture}',[string]$package.name)
        if ($probe.ExitCode -ne 0 -or $probe.Output -notmatch "^(?:install|hold) ok installed`t$([regex]::Escape([string]$package.version))`t$([regex]::Escape([string]$package.architecture))$") {
            throw 'WSL_PACKAGE_CLOSURE_MISMATCH'
        }
        $policy=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/apt-cache','policy',[string]$package.name)
        if($policy.ExitCode -ne 0 -or $policy.Output -notmatch "(?m)^\s*Installed:\s+$([regex]::Escape([string]$package.version))\s*$" -or $policy.Output -notmatch "(?m)^\s*Candidate:\s+$([regex]::Escape([string]$package.version))\s*$"){throw 'WSL_PACKAGE_CANDIDATE_MISMATCH'}
        $originPattern = '(?m)^\s*500 https://apt\.postgresql\.org/pub/repos/apt ' +
            [regex]::Escape([string]$wsl.pgdg.suite) + '/' +
            [regex]::Escape([string]$wsl.pgdg.component) + '\s+' +
            [regex]::Escape([string]$wsl.pgdg.architecture) + ' Packages\s*$'
        if([string]$package.version -match 'pgdg' -and $policy.Output -notmatch $originPattern){throw 'WSL_PACKAGE_ORIGIN_MISMATCH'}
    }
    $held = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/apt-mark','showhold')
    foreach ($packageName in @($wsl.pgdg.held_packages)) {
        if ($held.ExitCode -ne 0 -or @($held.Output -split "`r?`n") -cnotcontains [string]$packageName) { throw 'WSL_PACKAGE_HOLD_MISSING' }
    }
    $toolPaths = [ordered]@{
        postgres = $paths.Postgres
        pg_ctl = $paths.PgCtl
        initdb = $paths.InitDb
        pg_isready = $paths.PgIsReady
    }
    foreach ($tool in $toolPaths.Keys) {
        $probe = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @([string]$toolPaths[$tool],'--version')
        $expectedVersion = "$tool (PostgreSQL) $postgresVersion (Ubuntu $([string]$serverPackages[0].version))"
        if ($probe.ExitCode -ne 0 -or $probe.Output -cne $expectedVersion) { throw 'WSL_POSTGRES_VERSION_MISMATCH' }
    }
    $clusters = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/pg_lsclusters','--no-header')
    if ($clusters.ExitCode -ne 0) { throw 'WSL_CLUSTER_INVENTORY_UNAVAILABLE' }
    if (-not [string]::IsNullOrWhiteSpace($clusters.Output)) { throw 'WSL_UNMANAGED_CLUSTER_PRESENT' }
    foreach($unit in @('postgresql.service','postgresql@.service')){$service=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/systemctl','is-enabled',$unit);if($service.Output -cne 'masked'){throw 'WSL_POSTGRES_SERVICE_NOT_MASKED'}}
    $active=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/systemctl','is-active','postgresql.service');if($active.Output -cne 'inactive'){throw 'WSL_POSTGRES_SERVICE_ACTIVE'}
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
    param(
        [Parameter(Mandatory)][string]$Root,
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $maximumEntries = [int64]$Contract.Manifest.resource_policy.maximum_tree_entries
    $maximumBytes = [int64]$Contract.Manifest.postgresql.maximum_initial_cluster_bytes
    if ($maximumEntries -ne 50000 -or $maximumBytes -ne 134217728) { throw 'LINUX_TREE_LIMIT_CONTRACT_MISMATCH' }
    $policy = Resolve-ThriveLensLinuxTreeRootPolicy -Root $Root -DataRoot $paths.DataRoot -LogRoot $paths.LogRoot -MaximumBytes $maximumBytes
    $hasIdentityToken = $null -ne $IdentityToken
    $hasLifecycleLock = $null -ne $LifecycleLock
    if ($hasIdentityToken -ne $hasLifecycleLock) { throw 'LINUX_TREE_GUARD_ARGUMENT_MISMATCH' }
    # A staging tree exists only after this initializer has mutated the guest.
    # Its bounded supervisor must therefore carry the same lock and immutable
    # host identity token so timeout/output failure is contained before any
    # caller may attempt rollback.
    if ($policy.Kind -ceq 'STAGING' -and -not $hasIdentityToken) { throw 'LINUX_TREE_GUARD_REQUIRED' }
    $treeArguments = @('/usr/bin/python3','-c',@'
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
    $probe = Invoke-ThriveLensDistroProbe `
        -Contract $Contract `
        -IdentityToken $IdentityToken `
        -LifecycleLock $LifecycleLock `
        -TimeoutSeconds 60 `
        -Arguments $treeArguments
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
    param(
        [switch]$RequireLeaf,
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $projectPaths=@(
        '/var/lib/thrivelens',
        '/var/lib/thrivelens/postgresql',
        [string]$Paths.DataRoot,
        '/var/log/thrivelens',
        '/var/log/thrivelens/postgresql',
        [string]$Paths.LogRoot
    )
    foreach ($path in @('/var','/var/lib')+$projectPaths[0..2]+@('/var/log')+$projectPaths[3..5]) {
        if($path -notmatch '^/[^\\\x00-\x1f]+$' -or $path -match '(^|/)\.\.(/|$)|//'){throw 'LINUX_PATH_CONTRACT_MISMATCH'}
        $link = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-L',$path)
        if($link.ExitCode -eq 0){throw 'WSL_CLUSTER_PATH_SYMLINK_REJECTED'};if($link.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
        $probe = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-e',$path)
        if ($probe.ExitCode -eq 0) {
            $mount = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/findmnt','--mountpoint',$path,'--noheadings')
            if ($mount.ExitCode -eq 0) { throw 'WSL_CLUSTER_PATH_MOUNT_REJECTED' }
            if($mount.ExitCode -notin @(0,1)){throw 'WSL_MOUNT_MEASUREMENT_FAILED'}
        }
        elseif($probe.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
    }
    $rootDevice = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/stat','-c','%d','/')
    if($rootDevice.ExitCode -ne 0 -or $rootDevice.Output -notmatch '^[0-9]+$'){throw 'WSL_ROOT_DEVICE_MEASUREMENT_FAILED'}
    foreach ($path in $projectPaths) {
        $exists = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-e',$path)
        if ($exists.ExitCode -eq 0) {
            $device = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/stat','-c','%d',$path)
            $metadata = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/stat','-c','%U:%G:%a',$path)
            if ($device.ExitCode -ne 0 -or $device.Output -cne $rootDevice.Output) { throw 'WSL_CLUSTER_FILESYSTEM_MISMATCH' }
            if ($metadata.ExitCode -ne 0 -or $metadata.Output -cne 'postgres:postgres:700') { throw 'WSL_CLUSTER_PATH_METADATA_MISMATCH' }
        }
        elseif($exists.ExitCode -ne 1){throw 'WSL_PATH_MEASUREMENT_FAILED'}
        elseif ($RequireLeaf -and $path -in @($Paths.DataRoot,$Paths.LogRoot)) { throw 'WSL_CLUSTER_PATH_UNAVAILABLE' }
    }
    foreach ($root in @($Paths.DataRoot,$Paths.LogRoot)) {
        $exists = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-e',$root)
        if ($exists.ExitCode -eq 0) {
            $null = Assert-ThriveLensLinuxTreePolicy `
                -Root $root `
                -Paths $Paths `
                -Contract $Contract `
                -IdentityToken $IdentityToken `
                -LifecycleLock $LifecycleLock
        }
        elseif ($exists.ExitCode -ne 1) { throw 'WSL_PATH_MEASUREMENT_FAILED' }
    }
}

function Get-ThriveLensWslPaths {
    param($Contract)
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $wsl = $Contract.Wsl
    $postgresVersion = [string]$Contract.Manifest.postgresql.version
    $versionMatch = [regex]::Match($postgresVersion, '^(?<major>[0-9]+)\.[0-9]+$')
    if (-not $versionMatch.Success -or $versionMatch.Groups['major'].Value -cne '17') {
        throw 'WSL_PATH_CONTRACT_MISMATCH'
    }
    $binaryRoot = "/usr/lib/postgresql/$($versionMatch.Groups['major'].Value)/bin"
    return [pscustomobject]@{
        DataRoot = [string]$wsl.cluster_data_root
        LogRoot = [string]$wsl.cluster_log_root
        PgCtl = "$binaryRoot/pg_ctl"
        InitDb = "$binaryRoot/initdb"
        Postgres = "$binaryRoot/postgres"
        PgIsReady = "$binaryRoot/pg_isready"
        PgControlData = "$binaryRoot/pg_controldata"
        Port = [int]$Contract.Manifest.postgresql.port
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
    param(
        [int64]$RequiredBytes,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $reserveBytes = [int64]$Contract.Manifest.resource_policy.minimum_free_disk_reserve_bytes
    $probe=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/df','-B1','--output=avail','/')
    $values=@([regex]::Matches($probe.Output,'(?m)^\s*([0-9]+)\s*$')|ForEach-Object{[int64]$_.Groups[1].Value})
    if($probe.ExitCode -ne 0 -or $values.Count -ne 1){throw 'WSL_FREE_DISK_MEASUREMENT_UNAVAILABLE'}
    if($reserveBytes -lt 0 -or $RequiredBytes -lt 0 -or $RequiredBytes -gt ([int64]::MaxValue - $reserveBytes)) { throw 'WSL_FREE_DISK_MEASUREMENT_UNAVAILABLE' }
    if($values[0] -lt ($RequiredBytes + $reserveBytes)){throw 'WSL_FREE_DISK_INSUFFICIENT'}
}

function Test-ThriveLensWslClusterExists {
    param(
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $probe = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-f',"$($Paths.DataRoot)/PG_VERSION")
    return $probe.ExitCode -eq 0
}

function Assert-ThriveLensClusterScramConfig {
    param(
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $probe=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/python3','-c',@'
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
'@,$Paths.DataRoot)
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
    param(
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $exists=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/test','-e',$Paths.DataRoot)
    if($exists.ExitCode -ne 0){return Resolve-ThriveLensClusterProbe -ExistsExitCode $exists.ExitCode -PathPolicyValid $false -VersionExitCode 1 -VersionOutput '' -ControlExitCode 1 -ChecksumsEnabled $false}
    try{
        Assert-ThriveLensLinuxPathPolicy -RequireLeaf -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $version=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/cat',"$($Paths.DataRoot)/PG_VERSION")
        $control=Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @($Paths.PgControlData,$Paths.DataRoot)
        Assert-ThriveLensClusterScramConfig -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        return Resolve-ThriveLensClusterProbe -ExistsExitCode 0 -PathPolicyValid $true -VersionExitCode $version.ExitCode -VersionOutput $version.Output -ControlExitCode $control.ExitCode -ChecksumsEnabled ($control.Output -match '(?m)^Data page checksum version:\s+1\s*$')
    }
    catch {
        # Default read-only callers retain the legacy classifier. A guarded
        # transaction must never collapse an identity, lock, or containment
        # failure into ordinary cluster invalidity.
        if ($null -ne $IdentityToken) { throw }
        return 'PARTIAL_OR_INVALID'
    }
}

function Assert-ThriveLensWslAbsent {
    param(
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $running = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/sbin/runuser','-u','postgres','--',$Paths.PgCtl,'status','-D',$Paths.DataRoot)
    if ($running.ExitCode -eq 0) { throw 'POSTGRES_CLUSTER_STILL_RUNNING' }
    $listener = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/ss','-H','-ltn','sport',":$($Paths.Port)")
    if ($listener.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($listener.Output)) { throw 'POSTGRES_LISTENER_STILL_PRESENT' }
    $process = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/python3','-c',@'
import os,pathlib,sys
target=os.fsencode(sys.argv[1])
found=0
for item in pathlib.Path("/proc").iterdir():
    if not item.name.isdigit(): continue
    try:
        if pathlib.Path(item/"exe").resolve().as_posix().encode()==target:
            found+=1
    except (FileNotFoundError, ProcessLookupError): pass
    except PermissionError: raise SystemExit(3)
print(found)
'@,$Paths.Postgres)
    if ($process.ExitCode -ne 0 -or $process.Output -cne '0') { throw 'POSTGRES_PROCESS_STILL_PRESENT' }
}

function Assert-ThriveLensWslLoopback {
    param(
        $Paths,
        $Contract,
        $IdentityToken,
        [Threading.Mutex]$LifecycleLock
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $listener = Invoke-ThriveLensDistroProbe -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Arguments @('/usr/bin/ss','-H','-ltn','sport',":$($Paths.Port)")
    if ($listener.ExitCode -ne 0 -or [string]::IsNullOrWhiteSpace($listener.Output)) { throw 'POSTGRES_LISTENER_UNAVAILABLE' }
    foreach ($line in @($listener.Output -split "`r?`n")) {
        if ($line -notmatch ("\s127\.0\.0\.1:" + [regex]::Escape([string]$Paths.Port) + "\s")) { throw 'POSTGRES_NON_LOOPBACK_LISTENER' }
    }
}

function Assert-ThriveLensHostPortAbsent {
    param($Paths,$Contract)
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    try{$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object LocalPort -eq $Paths.Port)}catch{throw 'HOST_LISTENER_MEASUREMENT_UNAVAILABLE'}
    if($listeners.Count -gt 0){throw 'HOST_POSTGRES_LISTENER_STILL_PRESENT'}
    Assert-ThriveLensNoHostPortProxy -FailureCode 'HOST_PORTPROXY_STILL_PRESENT' -Paths $Paths -Contract $Contract
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
    param(
        [Parameter(Mandatory)][ValidateSet('HOST_PORTPROXY_STILL_PRESENT','HOST_PORTPROXY_PRESENT')][string]$FailureCode,
        $Paths,
        $Contract
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }

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
        if($mapping.ListenPort -eq $Paths.Port -or $mapping.ConnectPort -eq $Paths.Port){throw $FailureCode}
    }
}

function Assert-ThriveLensHostLoopback {
    param($Paths,$Contract)
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    try{$listeners=@(Get-NetTCPConnection -State Listen -ErrorAction Stop|Where-Object LocalPort -eq $Paths.Port)}catch{throw 'HOST_LISTENER_MEASUREMENT_UNAVAILABLE'}
    foreach($listener in $listeners){if([string]$listener.LocalAddress -notin @('127.0.0.1','::1')){throw 'HOST_NON_LOOPBACK_LISTENER'}}
    Assert-ThriveLensNoHostPortProxy -FailureCode 'HOST_PORTPROXY_PRESENT' -Paths $Paths -Contract $Contract
    $client=[Net.Sockets.TcpClient]::new()
    try{$task=$client.ConnectAsync('127.0.0.1',[int]$Paths.Port);if(-not $task.Wait(5000) -or -not $client.Connected){throw 'HOST_TCP_REACHABILITY_FAILED'}}finally{$client.Dispose()}
}

function Invoke-ThriveLensPostgresStartUnderLock {
    param(
        [Parameter(Mandatory)]$ConfigurationLease,
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        [Parameter(Mandatory)][ref]$WslTouched,
        [Parameter(Mandatory)][ref]$StartAttempted,
        [Parameter(Mandatory)][ref]$StartCommitResourceGateVerified
    )

    $StartCommitResourceGateVerified.Value=$false
    try {
        $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
        $null=Assert-ThriveLensConfigurationLease -Lease $ConfigurationLease
        $entryFingerprintValues=@(Get-ThriveLensConfigurationLeaseFingerprint -Lease $ConfigurationLease)
        if($entryFingerprintValues.Count -ne 1 -or [string]::IsNullOrWhiteSpace([string]$entryFingerprintValues[0])){
            throw 'CONFIGURATION_LEASE_INVALID'
        }
        $entryFingerprint=[string]$entryFingerprintValues[0]

        $leasedContract=Get-ThriveLensWslContract -ConfigurationLease $ConfigurationLease
        $leasedManifest=$leasedContract.Manifest
        $resourceValues=@(Get-ThriveLensLeasedResourceBudget -Lease $ConfigurationLease)
        if($resourceValues.Count -ne 1){throw 'CONFIGURATION_LEASE_INVALID'}
        $leasedResourceBudget=$resourceValues[0]

        if([string]::IsNullOrWhiteSpace([string]$leasedResourceBudget.phase)){
            throw 'RESOURCE_PHASE_UNAVAILABLE'
        }
        $activePhase=[string]$leasedResourceBudget.phase
        if(@($leasedManifest.resource_policy.allowed_active_phases) -cnotcontains $activePhase){
            throw 'RESOURCE_PHASE_NOT_ACTIVE_AFTER_LIFECYCLE_LOCK'
        }
        $paths=Get-ThriveLensWslPaths -Contract $leasedContract

        try{$null=Invoke-ThriveLensResourceGate -Manifest $leasedManifest}
        catch{
            $resourceGateCode=[string]$_.Exception.Message
            if($resourceGateCode -cin @(
                'RESOURCE_GATE_UNAVAILABLE','RESOURCE_GATE_FAILED','RESOURCE_GATE_RESULT_INVALID',
                'RESOURCE_GATE_MANIFEST_INVALID','RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT',
                'RESOURCE_GATE_OUTPUT_LIMIT','RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
            )){throw $resourceGateCode}
            throw 'RESOURCE_GATE_FAILED'
        }

        $memoryPolicy=Get-ThriveLensMemoryPolicyThresholds -Manifest $leasedManifest
        $runtimeMinimumBytes=[int64]$memoryPolicy.RuntimeMinimumBytes
        $startReclaimTargetBytes=[int64]$memoryPolicy.StartReclaimTargetBytes

        try{$memoryValues=@(Get-ThriveLensFreeMemoryBytes)}catch{throw 'MEMORY_MEASUREMENT_UNAVAILABLE'}
        if($memoryValues.Count -ne 1 -or $memoryValues[0] -is [bool]){throw 'MEMORY_MEASUREMENT_UNAVAILABLE'}
        $memoryText=[Convert]::ToString($memoryValues[0],[Globalization.CultureInfo]::InvariantCulture)
        $freeMemoryBytes=[int64]0
        if(-not [int64]::TryParse($memoryText,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$freeMemoryBytes) -or
           $freeMemoryBytes -lt 0){throw 'MEMORY_MEASUREMENT_UNAVAILABLE'}
        if($freeMemoryBytes -lt $runtimeMinimumBytes){throw 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK'}

        $WslTouched.Value=$true
        $null=Assert-ThriveLensWslIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $leasedContract
        $null=Assert-ThriveLensWslPackages -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $null=Assert-ThriveLensWslInternalDisk -RequiredBytes 0 -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        if((Get-ThriveLensWslClusterState -Paths $paths -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock) -cne 'VALID'){throw 'POSTGRES_CLUSTER_INVALID_AFTER_LIFECYCLE_LOCK'}
        $null=Assert-ThriveLensWslAbsent -Paths $paths -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $null=Assert-ThriveLensHostPortAbsent -Paths $paths -Contract $leasedContract

        # Read-only WSL validation launches the dedicated distro. Reclaim that
        # probe footprint under the same lock and exact host identity token,
        # then admit start only after bounded host-only memory settling.
        $null=Stop-ThriveLensDistroAndVerify -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $leasedContract
        try {
            Wait-ThriveLensInterCycleMemorySettle -MinimumFreeMemoryBytes $startReclaimTargetBytes
        }
        catch {
            switch ([string]$_.Exception.Message) {
                'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED' { throw 'LOW_FREE_MEMORY_AFTER_WSL_PROBES' }
                'RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE' { throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' }
                default { throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES' }
            }
        }

        $options="-h 127.0.0.1 -p $($paths.Port) -c max_connections=20 -c shared_buffers=64MB -c work_mem=2MB -c maintenance_work_mem=32MB -c password_encryption=scram-sha-256 -c logging_collector=off -c log_statement=none -c log_connections=off -c log_disconnections=off -c log_hostname=off -c log_min_error_statement=panic"

        $null=Assert-ThriveLensConfigurationLease -Lease $ConfigurationLease
        $commitFingerprintValues=@(Get-ThriveLensConfigurationLeaseFingerprint -Lease $ConfigurationLease)
        if($commitFingerprintValues.Count -ne 1 -or [string]$commitFingerprintValues[0] -cne $entryFingerprint){
            throw 'CONFIGURATION_LEASE_CHANGED'
        }
        $null=Assert-ThriveLensWslIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $leasedContract
        $null=Assert-ThriveLensWslAbsent -Paths $paths -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $null=Assert-ThriveLensHostPortAbsent -Paths $paths -Contract $leasedContract

        try{$memoryValues=@(Get-ThriveLensFreeMemoryBytes)}catch{throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
        if($memoryValues.Count -ne 1 -or $memoryValues[0] -is [bool]){throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
        $memoryText=[Convert]::ToString($memoryValues[0],[Globalization.CultureInfo]::InvariantCulture)
        $freeMemoryBytes=[int64]0
        if(-not [int64]::TryParse($memoryText,[Globalization.NumberStyles]::Integer,[Globalization.CultureInfo]::InvariantCulture,[ref]$freeMemoryBytes) -or
           $freeMemoryBytes -lt 0){throw 'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES'}
        if($freeMemoryBytes -lt $runtimeMinimumBytes){throw 'LOW_FREE_MEMORY_AFTER_WSL_PROBES'}

        $StartAttempted.Value=$true
        $startResult=Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -TimeoutSeconds 45 -Contract $leasedContract -Arguments @('/usr/sbin/runuser','-u','postgres','--',$paths.PgCtl,'start','-D',$paths.DataRoot,'-l','/dev/null','-o',$options,'-w','-t','30')
        if($startResult.ExitCode -ne 0){throw 'POSTGRES_START_FAILED'}
        $null=Assert-ThriveLensWslLoopback -Paths $paths -Contract $leasedContract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $null=Assert-ThriveLensHostLoopback -Paths $paths -Contract $leasedContract
        try{$null=Invoke-ThriveLensResourceGate -Manifest $leasedManifest}
        catch{
            $postGateCode=[string]$_.Exception.Message
            if($postGateCode -cin @(
                'RESOURCE_GATE_UNAVAILABLE','RESOURCE_GATE_FAILED','RESOURCE_GATE_RESULT_INVALID',
                'RESOURCE_GATE_MANIFEST_INVALID','RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT',
                'RESOURCE_GATE_OUTPUT_LIMIT','RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE'
            )){throw $postGateCode}
            throw 'POST_MUTATION_RESOURCE_GATE_FAILED'
        }
        $StartCommitResourceGateVerified.Value=$true
    }
    catch {
        $code=[string]$_.Exception.Message
        if($code -match '^[A-Z0-9_]{1,128}$'){throw $code}
        throw 'POSTGRES_START_INTERNAL_ERROR'
    }
}

function Stop-ThriveLensPostgresUnderLock {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        $Contract,
        $Paths
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    if ($null -eq $Paths) { $Paths = Get-ThriveLensWslPaths -Contract $Contract }
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    $state=Get-ThriveLensWslClusterState -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    $wasRunning=$false
    if($state -ceq 'VALID'){
        Assert-ThriveLensLinuxPathPolicy -RequireLeaf -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
        $status=Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract -Arguments @('/usr/sbin/runuser','-u','postgres','--',$Paths.PgCtl,'status','-D',$Paths.DataRoot)
        $wasRunning=$status.ExitCode -eq 0
        if($wasRunning){
            $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
            $stop=Invoke-ThriveLensGuardedDistro -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract -TimeoutSeconds 45 -Arguments @('/usr/sbin/runuser','-u','postgres','--',$Paths.PgCtl,'stop','-D',$Paths.DataRoot,'-m','fast','-w','-t','30')
            if($stop.ExitCode -ne 0){throw 'POSTGRES_STOP_FAILED'}
        }
    }
    elseif($state -ceq 'PARTIAL_OR_INVALID'){
        Assert-ThriveLensWslAbsent -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    }
    Assert-ThriveLensWslAbsent -Paths $Paths -Contract $Contract -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock
    return $wasRunning
}

function Resolve-ThriveLensRuntimePublicCode {
    param([AllowEmptyString()][string]$Code)
    $allowed=@(
        'AUTH_FILE_PATH_INVALID','AUTH_FILE_CREATE_FAILED','WRONG_AUTH_FILE_CREATE_FAILED',
        'AUTH_FILE_CLEANUP_REMOVE_FAILED','AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED',
        'PASSWORD_FILE_PATH_INVALID','PASSWORD_FILE_PATH_MISMATCH',
        'CONFIGURATION_LEASE_BOM_REJECTED','CONFIGURATION_LEASE_CHANGED','CONFIGURATION_LEASE_CONTENT_CHANGED',
        'CONFIGURATION_LEASE_FILE_UNAVAILABLE','CONFIGURATION_LEASE_FINAL_PATH_INVALID','CONFIGURATION_LEASE_FINAL_PATH_MISMATCH',
        'CONFIGURATION_LEASE_FINGERPRINT_CHANGED','CONFIGURATION_LEASE_FINGERPRINT_INVALID',
        'CONFIGURATION_LEASE_IDENTITY_CHANGED','CONFIGURATION_LEASE_IDENTITY_REJECTED','CONFIGURATION_LEASE_IDENTITY_UNAVAILABLE',
        'CONFIGURATION_LEASE_INVALID','CONFIGURATION_LEASE_JSON_CONTROL_REJECTED','CONFIGURATION_LEASE_JSON_DUPLICATE_PROPERTY',
        'CONFIGURATION_LEASE_JSON_INVALID','CONFIGURATION_LEASE_JSON_ROOT_INVALID','CONFIGURATION_LEASE_LENGTH_CHANGED',
        'CONFIGURATION_LEASE_LENGTH_INVALID','CONFIGURATION_LEASE_OPEN_FAILED','CONFIGURATION_LEASE_PATH_REJECTED',
        'CONFIGURATION_LEASE_READ_FAILED','CONFIGURATION_LEASE_READ_INCOMPLETE','CONFIGURATION_LEASE_RELEASE_FAILED',
        'CONFIGURATION_LEASE_STREAM_UNREADABLE','CONFIGURATION_LEASE_UTF8_INVALID',
        'RESOURCE_PHASE_UNAVAILABLE','RESOURCE_PHASE_CHANGED_AFTER_CONFIGURATION_LEASE','RESOURCE_PHASE_NOT_ACTIVE_AFTER_LIFECYCLE_LOCK',
        'RUNTIME_MEMORY_POLICY_INVALID','MEMORY_MEASUREMENT_UNAVAILABLE','LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK',
        'MEMORY_MEASUREMENT_UNAVAILABLE_AFTER_WSL_PROBES','LOW_FREE_MEMORY_AFTER_WSL_PROBES',
        'POSTGRES_CLUSTER_INVALID_AFTER_LIFECYCLE_LOCK','POSTGRES_START_FAILED','POSTGRES_START_INTERNAL_ERROR',
        'POSTGRES_SYSTEM_IDENTIFIER_PROBE_FAILED','POSTGRES_SYSTEM_IDENTIFIER_INVALID',
        'POST_MUTATION_RESOURCE_GATE_FAILED','RESOURCE_GATE_UNAVAILABLE','RESOURCE_GATE_FAILED','RESOURCE_GATE_RESULT_INVALID',
        'RESOURCE_GATE_MANIFEST_INVALID','RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT',
        'RESOURCE_GATE_OUTPUT_LIMIT','RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE',
        'RUNTIME_START_PROBE_FAILED','RUNTIME_START_CHILD_FATAL','RUNTIME_START_CHILD_UNEXPECTED_EXIT',
        'RUNTIME_START_ABSENCE_UNVERIFIED','RUNTIME_POSTGRES_NOT_RUNNING_AT_STOP',
        'SCRAM_AUTH_PROBE_FAILED','PASSWORD_ENCRYPTION_PROBE_FAILED','HBA_SCRAM_PROBE_FAILED',
        'SCRAM_VERIFIER_PROBE_FAILED','WRONG_PASSWORD_FIXTURE_INVALID','WRONG_PASSWORD_WAS_ACCEPTED',
        'WRONG_PASSWORD_PROBE_UNEXPECTED_OUTPUT','WRONG_PASSWORD_PROBE_UNRELATED_FAILURE',
        'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED','POSTGRES_STOP_FAILED',
        'POSTGRES_CLUSTER_STILL_RUNNING','POSTGRES_LISTENER_STILL_PRESENT','POSTGRES_PROCESS_STILL_PRESENT',
        'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED','WSL_CLEANUP_IDENTITY_CHANGED','WSL_CLEANUP_IDENTITY_TOKEN_INVALID',
        'WSL_ARCHITECTURE_MISMATCH','WSL_DISTRO_IDENTITY_MISMATCH','WSL_DISTRO_LOCATION_MISMATCH','WSL_DISTRO_NAME_MISMATCH',
        'WSL_GUARD_ARGUMENT_MISMATCH','WSL_PATH_CONTRACT_MISMATCH',
        'WSL_DISTRO_REGISTRY_ID_INVALID','WSL_FREE_DISK_INSUFFICIENT','WSL_FREE_DISK_MEASUREMENT_UNAVAILABLE',
        'WSL_NO_AUTOSTART_POLICY_MISMATCH','WSL_PACKAGE_CANDIDATE_MISMATCH','WSL_PACKAGE_CLOSURE_MISMATCH',
        'WSL_PACKAGE_HOLD_MISSING','WSL_PACKAGE_ORIGIN_MISMATCH','WSL_PGDG_KEY_FINGERPRINT_MISMATCH',
        'WSL_PGDG_KEY_HASH_MISMATCH','WSL_PGDG_SOURCE_HASH_MISMATCH','WSL_POSTGRES_SERVICE_ACTIVE',
        'WSL_POSTGRES_SERVICE_NOT_MASKED','WSL_POSTGRES_VERSION_MISMATCH','WSL_STORAGE_OUTSIDE_ATTRIBUTABLE_ROOT',
        'WSL_STORAGE_REPARSE_REJECTED','WSL_UBUNTU_IDENTITY_UNAVAILABLE','WSL_UBUNTU_RELEASE_MISMATCH',
        'WSL_UNMANAGED_CLUSTER_PRESENT','WSL_VERSION_MISMATCH','WSL_VHD_CAPACITY_MISMATCH','WSL_VHD_IDENTITY_MISMATCH',
        'WSL_VHD_IDENTITY_PROVIDER_UNAVAILABLE','WSL_VHD_IDENTITY_UNAVAILABLE','WSL_VHD_LIMIT_EXCEEDED',
        'WSL_VHD_REPARSE_REJECTED','WSL_VHD_UNAVAILABLE','WSL_CLUSTER_INVENTORY_UNAVAILABLE',
        'LINUX_PATH_CONTRACT_MISMATCH','LINUX_TREE_ROOT_CONTRACT_MISMATCH','LINUX_TREE_LIMIT_CONTRACT_MISMATCH',
        'LINUX_TREE_GUARD_ARGUMENT_MISMATCH','LINUX_TREE_GUARD_REQUIRED','WSL_CLUSTER_FILESYSTEM_MISMATCH',
        'WSL_CLUSTER_PATH_METADATA_MISMATCH','WSL_CLUSTER_PATH_MOUNT_REJECTED','WSL_CLUSTER_PATH_SYMLINK_REJECTED',
        'WSL_CLUSTER_PATH_UNAVAILABLE','WSL_CLUSTER_TREE_SYMLINK_REJECTED','WSL_CLUSTER_TREE_SPECIAL_FILE_REJECTED',
        'WSL_CLUSTER_TREE_ENTRY_LIMIT_EXCEEDED','WSL_CLUSTER_TREE_BYTE_LIMIT_EXCEEDED','WSL_CLUSTER_TREE_PATH_LIMIT_EXCEEDED',
        'WSL_CLUSTER_TREE_DEPTH_LIMIT_EXCEEDED','WSL_MOUNT_MEASUREMENT_FAILED','WSL_PATH_MEASUREMENT_FAILED',
        'WSL_ROOT_DEVICE_MEASUREMENT_FAILED','WSL_TREE_MEASUREMENT_FAILED','WSL_TREE_ROOT_UNAVAILABLE',
        'LIFECYCLE_LOCK_TIMEOUT','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED',
        'HOST_LISTENER_MEASUREMENT_UNAVAILABLE','HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE',
        'HOST_POSTGRES_LISTENER_STILL_PRESENT','HOST_PORTPROXY_STILL_PRESENT','HOST_NON_LOOPBACK_LISTENER',
        'HOST_PORTPROXY_PRESENT','HOST_TCP_REACHABILITY_FAILED','POSTGRES_LISTENER_UNAVAILABLE','POSTGRES_NON_LOOPBACK_LISTENER',
        'WSL_DISTRO_TERMINATE_FAILED','WSL_RUNNING_STATE_UNAVAILABLE','WSL_DISTRO_STILL_RUNNING','RESOURCE_GATE_FAILED',
        'RESOURCE_INTER_CYCLE_MEMORY_NOT_SETTLED','RESOURCE_INTER_CYCLE_MEMORY_MEASUREMENT_UNAVAILABLE',
        'RUNTIME_CLEANUP_FAILED','RUNTIME_CLEANUP_IDENTITY_CHANGED','RUNTIME_LOCK_RELEASE_FAILED',
        'WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE',
        'WSL_PROCESS_START_FAILED','WSL_STANDARD_INPUT_INVALID','WSL_STANDARD_INPUT_LIMIT_EXCEEDED',
        'RUNTIME_TEST_INTERNAL_ERROR'
    )
    if($allowed -ccontains $Code){return $Code}
    return 'RUNTIME_TEST_INTERNAL_ERROR'
}

function Test-ThriveLensCredentialAbsenceProbeAllowed {
    param([AllowEmptyString()][string]$FailureCode)
    return @(
        'WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED',
        'WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED'
    ) -ccontains $FailureCode
}

function Test-ThriveLensCredentialCleanupAllowedAfterFailure {
    param([AllowEmptyString()][string]$FailureCode)
    $public=Resolve-ThriveLensRuntimePublicCode -Code $FailureCode
    if($public -ceq 'RUNTIME_TEST_INTERNAL_ERROR' -or $public -like 'CONFIGURATION_LEASE_*' -or
       $public -like '*IDENTITY*' -or $public -like '*INTERNAL_ERROR' -or
       $public -cin @(
           'RESOURCE_GATE_PROCESS_START_FAILED','RESOURCE_GATE_TIMEOUT',
           'RESOURCE_GATE_OUTPUT_LIMIT','RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE',
           'WSL_STANDARD_INPUT_INVALID','WSL_STANDARD_INPUT_LIMIT_EXCEEDED'
       ) -or
       $public -like 'WSL_DISTRO_*' -or $public -like 'WSL_STORAGE_*' -or
       $public -like 'WSL_VHD_*' -or $public -like 'WSL_UBUNTU_*' -or
       $public -cin @('WSL_VERSION_MISMATCH','WSL_ARCHITECTURE_MISMATCH')){
        return $false
    }
    return $public -cnotin @(
        'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED','WSL_CLEANUP_IDENTITY_CHANGED',
        'LIFECYCLE_LOCK_TIMEOUT','LIFECYCLE_LOCK_OWNERSHIP_REQUIRED',
        'AUTH_FILE_CLEANUP_REMOVE_FAILED','AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED'
    )
}

function Test-ThriveLensCleanupFailurePreservesIdentityAuthority {
    param(
        [Parameter(Mandatory)][ValidateSet('POSTGRES_STOP','DISTRO_TERMINATE','DISTRO_ABSENCE','HOST_ABSENCE')][string]$Stage,
        [AllowEmptyString()][string]$FailureCode
    )
    $common=@('WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED')
    $allowed=switch($Stage){
        'POSTGRES_STOP' {$common+@('POSTGRES_STOP_FAILED','POSTGRES_CLUSTER_STILL_RUNNING','POSTGRES_LISTENER_STILL_PRESENT','POSTGRES_PROCESS_STILL_PRESENT');break}
        'DISTRO_TERMINATE' {$common+@('WSL_DISTRO_TERMINATE_FAILED');break}
        'DISTRO_ABSENCE' {$common+@('WSL_RUNNING_STATE_UNAVAILABLE','WSL_DISTRO_STILL_RUNNING');break}
        'HOST_ABSENCE' {@('HOST_LISTENER_MEASUREMENT_UNAVAILABLE','HOST_POSTGRES_LISTENER_STILL_PRESENT','HOST_PORTPROXY_MEASUREMENT_UNAVAILABLE','HOST_PORTPROXY_STILL_PRESENT');break}
    }
    return $allowed -ccontains $FailureCode
}

function Resolve-ThriveLensDistroCleanupFailure {
    param([AllowEmptyString()][string]$FailureCode)
    $publicCode=Resolve-ThriveLensRuntimePublicCode -Code $FailureCode
    $stage=Resolve-ThriveLensRuntimeFailureStage -Code $publicCode
    $boundedStage=$stage -cin @('DISTRO_TERMINATE','DISTRO_ABSENCE','HOST_ABSENCE')
    $preserves=$boundedStage -and (Test-ThriveLensCleanupFailurePreservesIdentityAuthority -Stage $stage -FailureCode $publicCode)
    return [pscustomobject]@{
        Code=$publicCode
        Stage=$stage
        IdentityAuthorityPreserved=$preserves
    }
}

function Resolve-ThriveLensCredentialCleanupResult {
    param(
        [Parameter(Mandatory)][bool]$RemoveSucceeded,
        [Parameter(Mandatory)][bool]$AbsenceAttempted,
        [Parameter(Mandatory)][bool]$AbsenceVerified,
        [AllowNull()][string]$RootFailureCode
    )
    $stages=[Collections.Generic.List[string]]::new()
    if(-not $RemoveSucceeded){$stages.Add('CREDENTIAL_REMOVE')}
    if(-not $AbsenceAttempted -or -not $AbsenceVerified){$stages.Add('CREDENTIAL_ABSENCE')}
    $code=if(-not $AbsenceAttempted -or -not $AbsenceVerified){'AUTH_FILE_CLEANUP_ABSENCE_UNVERIFIED'}elseif(-not $RemoveSucceeded){'AUTH_FILE_CLEANUP_REMOVE_FAILED'}else{$null}
    $sanitizedRoot=if([string]::IsNullOrWhiteSpace($RootFailureCode)){$null}else{Resolve-ThriveLensRuntimePublicCode -Code $RootFailureCode}
    return [pscustomobject]@{RemoveSucceeded=$RemoveSucceeded;CredentialAbsenceVerified=($AbsenceAttempted -and $AbsenceVerified);FailureCode=$code;RootFailureCode=$sanitizedRoot;FailureStages=@($stages)}
}

function Resolve-ThriveLensCredentialFailureCode {
    param(
        [AllowNull()][string]$PrimaryOperationCode,
        [AllowNull()][string]$RootFailureCode,
        [AllowNull()][string]$CleanupCode
    )
    foreach($candidate in @($PrimaryOperationCode,$RootFailureCode,$CleanupCode)){
        if(-not [string]::IsNullOrWhiteSpace($candidate)){
            return Resolve-ThriveLensRuntimePublicCode -Code $candidate
        }
    }
    return $null
}

function Resolve-ThriveLensRuntimeFailureStage {
    param([Parameter(Mandatory)][string]$Code)
    if($Code -like 'AUTH_FILE_CLEANUP_REMOVE*'){return 'CREDENTIAL_REMOVE'}
    if($Code -like 'AUTH_FILE_CLEANUP_ABSENCE*'){return 'CREDENTIAL_ABSENCE'}
    if($Code -cin @('CONFIGURATION_LEASE_RELEASE_FAILED','RUNTIME_LOCK_RELEASE_FAILED')){return 'LOCK_RELEASE'}
    if($Code -like 'CONFIGURATION_LEASE_*'){return 'RESOURCE_GATE'}
    if($Code -like 'RUNTIME_START*' -or $Code -like 'POSTGRES_START*'){return 'START'}
    if($Code -match 'IDENTITY|LIFECYCLE_LOCK'){return 'IDENTITY'}
    if($Code -like 'RESOURCE_*' -or $Code -like 'LOW_FREE_MEMORY*' -or
       $Code -like 'MEMORY_MEASUREMENT_UNAVAILABLE*' -or $Code -ceq 'RUNTIME_MEMORY_POLICY_INVALID' -or
       $Code -ceq 'POST_MUTATION_RESOURCE_GATE_FAILED'){
        return 'RESOURCE_GATE'
    }
    if($Code -like 'POSTGRES_STOP*' -or $Code -cin @('RUNTIME_POSTGRES_NOT_RUNNING_AT_STOP','POSTGRES_CLUSTER_STILL_RUNNING','POSTGRES_LISTENER_STILL_PRESENT','POSTGRES_PROCESS_STILL_PRESENT')){return 'POSTGRES_STOP'}
    if($Code -like 'WSL_DISTRO_TERMINATE*'){return 'DISTRO_TERMINATE'}
    if($Code -like 'WSL_RUNNING_STATE*' -or $Code -ceq 'WSL_DISTRO_STILL_RUNNING'){return 'DISTRO_ABSENCE'}
    if($Code -like 'HOST_*'){return 'HOST_ABSENCE'}
    return 'PROBE'
}

function Resolve-ThriveLensRuntimeCleanupOutcome {
    param(
        [Parameter(Mandatory)][string]$OriginalCode,
        [Parameter(Mandatory)][ValidateSet(2,3)][int]$OriginalExitCode,
        [Parameter(Mandatory)][bool]$CleanupRequired,
        [Parameter(Mandatory)][bool]$CleanupAuthorityVerified,
        [Parameter(Mandatory)][bool]$CredentialCleanupRequired,
        [Parameter(Mandatory)][bool]$CredentialRemoveFailed,
        [AllowNull()][string]$CredentialRootFailureCode,
        [Parameter(Mandatory)][bool]$CredentialAbsenceVerified,
        [Parameter(Mandatory)][bool]$IdentityChanged,
        [Parameter(Mandatory)][bool]$PostgresStopFailed,
        [Parameter(Mandatory)][bool]$DistroTerminateFailed,
        [Parameter(Mandatory)][bool]$DistroAbsenceCheckFailed,
        [Parameter(Mandatory)][bool]$HostAbsenceCheckFailed,
        [Parameter(Mandatory)][bool]$DistroAbsent,
        [Parameter(Mandatory)][bool]$HostAbsent,
        [Parameter(Mandatory)][bool]$LockReleaseFailed
    )
    $publicCode=Resolve-ThriveLensRuntimePublicCode -Code $OriginalCode
    $stages=[Collections.Generic.List[string]]::new()
    $addStage={param([string]$Stage)if(-not $stages.Contains($Stage)){$stages.Add($Stage)}}
    & $addStage (Resolve-ThriveLensRuntimeFailureStage -Code $publicCode)
    if(-not [string]::IsNullOrWhiteSpace($CredentialRootFailureCode)){
        & $addStage (Resolve-ThriveLensRuntimeFailureStage -Code (Resolve-ThriveLensRuntimePublicCode -Code $CredentialRootFailureCode))
    }
    if($CredentialRemoveFailed){& $addStage 'CREDENTIAL_REMOVE'}
    if($CredentialCleanupRequired -and -not $CredentialAbsenceVerified){& $addStage 'CREDENTIAL_ABSENCE'}
    if(-not $CleanupAuthorityVerified){& $addStage 'IDENTITY'}
    if($IdentityChanged){& $addStage 'IDENTITY'}
    if($PostgresStopFailed){& $addStage 'POSTGRES_STOP'}
    if($DistroTerminateFailed){& $addStage 'DISTRO_TERMINATE'}
    if($DistroAbsenceCheckFailed){& $addStage 'DISTRO_ABSENCE'}
    if($HostAbsenceCheckFailed){& $addStage 'HOST_ABSENCE'}
    if(-not $DistroAbsent){& $addStage 'DISTRO_ABSENCE'}
    if(-not $HostAbsent){& $addStage 'HOST_ABSENCE'}
    if($LockReleaseFailed){& $addStage 'LOCK_RELEASE'}
    $cleanupVerified=$CleanupAuthorityVerified -and
        (-not $CleanupRequired -or ($DistroAbsent -and $HostAbsent -and -not $IdentityChanged)) -and
        (-not $CredentialCleanupRequired -or $CredentialAbsenceVerified)
    if(-not $cleanupVerified){
        $finalCode=if($IdentityChanged){'RUNTIME_CLEANUP_IDENTITY_CHANGED'}else{'RUNTIME_CLEANUP_FAILED'}
        return [pscustomobject]@{Status='ERROR';Code=$finalCode;OriginalCode=$publicCode;ExitCode=3;CleanupVerified=$false;FailureStages=@($stages)}
    }
    if($LockReleaseFailed){
        return [pscustomobject]@{Status='ERROR';Code='RUNTIME_LOCK_RELEASE_FAILED';OriginalCode=$publicCode;ExitCode=3;CleanupVerified=$true;FailureStages=@($stages)}
    }
    return [pscustomobject]@{
        Status=if($OriginalExitCode -eq 3){'ERROR'}else{'BLOCKED'}
        Code=$publicCode
        OriginalCode=$publicCode
        ExitCode=$OriginalExitCode
        CleanupVerified=$true
        FailureStages=@($stages)
    }
}

function Resolve-ThriveLensCleanupContainmentPolicy {
    param(
        [Parameter(Mandatory)][string]$FailureCode,
        [Parameter(Mandatory)][bool]$SameTokenContainmentReverified
    )
    if($FailureCode -notmatch '^[A-Z0-9_]+$'){
        return [pscustomobject]@{RequiresRecontainment=$true;AllowGuestCleanup=$false;Fatal=$true}
    }
    if($FailureCode -ceq 'WSL_GUARDED_COMMAND_CONTAINMENT_FAILED'){
        return [pscustomobject]@{
            RequiresRecontainment=$true
            AllowGuestCleanup=$SameTokenContainmentReverified
            Fatal=$true
        }
    }
    return [pscustomobject]@{RequiresRecontainment=$false;AllowGuestCleanup=$true;Fatal=$false}
}

function Resolve-ThriveLensWrongPasswordProbe {
    param(
        [Parameter(Mandatory)][int]$ExitCode,
        [AllowEmptyString()][string]$PrivateStandardOutput = '',
        [AllowEmptyString()][string]$PrivateStandardError = '',
        [Parameter(Mandatory)][string]$ExpectedPasswordFile,
        [Parameter(Mandatory)][bool]$ServerUsableAfterProbe
    )
    if($ExitCode -eq 0){throw 'WRONG_PASSWORD_WAS_ACCEPTED'}
    if(-not [string]::IsNullOrEmpty($PrivateStandardOutput)){throw 'WRONG_PASSWORD_PROBE_UNEXPECTED_OUTPUT'}
    if($ExitCode -ne 2){throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'}
    if($ExpectedPasswordFile -cnotmatch '\A/run/thrivelens-r0-wrong-[0-9a-f]{32}\.pgpass\z'){
        throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'
    }
    if($PrivateStandardError.Length -gt 512 -or $PrivateStandardError -cmatch '[^\x0A\x20-\x7E]'){
        throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'
    }
    $authError='psql: error: connection to server at "127.0.0.1", port 55432 failed: FATAL:  password authentication failed for user "tl_bootstrap"'
    $passwordFileError='password retrieved from file "'+$ExpectedPasswordFile+'"'
    $normalized=$PrivateStandardError
    if($normalized.EndsWith("`n",[StringComparison]::Ordinal)){$normalized=$normalized.Substring(0,$normalized.Length-1)}
    if($normalized -cne ($authError+"`n"+$passwordFileError)){
        throw 'WRONG_PASSWORD_PROBE_UNRELATED_FAILURE'
    }
    if(-not $ServerUsableAfterProbe){throw 'WRONG_PASSWORD_SERVER_USABILITY_UNVERIFIED'}
    return [pscustomobject]@{Status='AUTHENTICATION_REJECTED';ExitCode=2}
}

function Stop-ThriveLensDistroAndVerify {
    param(
        [Parameter(Mandatory)]$IdentityToken,
        [Parameter(Mandatory)][Threading.Mutex]$LifecycleLock,
        $Contract
    )
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $Paths = Get-ThriveLensWslPaths -Contract $Contract
    if([string]$Contract.Wsl.distribution_name -cne 'ThriveLens-R0'){throw 'WSL_DISTRO_NAME_MISMATCH'}
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $LifecycleLock
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    $terminateFailure=$null
    try{
        try{
            $result=Invoke-ThriveLensWsl -Arguments @('--terminate',[string]$Contract.Wsl.distribution_name) -TimeoutSeconds 15
            if($result.ExitCode -ne 0){$terminateFailure='WSL_DISTRO_TERMINATE_FAILED'}
        }
        catch{
            $publicCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
            $terminateFailure=if($publicCode -cin @('WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED')){'WSL_DISTRO_TERMINATE_FAILED'}else{$publicCode}
        }
    }
    finally{
        # A same-name replacement between authorization and mutation is fatal.
        $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $IdentityToken -LifecycleLock $LifecycleLock -Contract $Contract
    }
    if($null -ne $terminateFailure){throw $terminateFailure}
    try{Assert-ThriveLensDistroStopped -Contract $Contract}
    catch{
        $publicCode=Resolve-ThriveLensRuntimePublicCode -Code ([string]$_.Exception.Message)
        if($publicCode -cin @('WSL_COMMAND_TIMEOUT','WSL_OUTPUT_LIMIT_EXCEEDED','WSL_OUTPUT_DRAIN_INCOMPLETE','WSL_PROCESS_START_FAILED')){throw 'WSL_RUNNING_STATE_UNAVAILABLE'}
        throw $publicCode
    }
    # Windows can retain a transient WSL relay until the exact distro is
    # terminated. Host absence belongs here, after the token-gated termination,
    # rather than in the guest PostgreSQL graceful-stop primitive.
    Assert-ThriveLensHostPortAbsent -Paths $Paths -Contract $Contract
}

function Assert-ThriveLensDistroStopped {
    param($Contract)
    if ($null -eq $Contract) { $Contract = Get-ThriveLensWslContract }
    $running=Invoke-ThriveLensWsl -Arguments @('--list','--running','--quiet') -TimeoutSeconds 15
    if($running.ExitCode -ne 0){throw 'WSL_RUNNING_STATE_UNAVAILABLE'}
    if(@($running.Output -split "`r?`n") -ccontains [string]$Contract.Wsl.distribution_name){throw 'WSL_DISTRO_STILL_RUNNING'}
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
        $key=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($mutex);$script:HeldLifecycleLocks[$key]=[pscustomobject]@{Mutex=$mutex;OwnerThreadId=[Environment]::CurrentManagedThreadId}
        return $mutex
    }
    catch{if($null -ne $mutex){$mutex.Dispose()};throw}
    $key=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($mutex);$script:HeldLifecycleLocks[$key]=[pscustomobject]@{Mutex=$mutex;OwnerThreadId=[Environment]::CurrentManagedThreadId}
    return $mutex
}

function Exit-ThriveLensLifecycleLock {
    param([Parameter(Mandatory)][Threading.Mutex]$Mutex)
    $key=[Runtime.CompilerServices.RuntimeHelpers]::GetHashCode($Mutex)
    $null=Assert-ThriveLensLifecycleLockOwnership -LifecycleLock $Mutex
    $Mutex.ReleaseMutex()
    $null=$script:HeldLifecycleLocks.Remove($key)
    $Mutex.Dispose()
}

Export-ModuleMember -Function @(
    'Get-ThriveLensWslContract','Invoke-ThriveLensGuardedDistro',
    'Get-ThriveLensWslCleanupIdentityToken','Compare-ThriveLensWslCleanupIdentityToken','Assert-ThriveLensWslIdentity','Assert-ThriveLensWslCleanupIdentity','Assert-ThriveLensWslPackages','Get-ThriveLensWslPaths',
    'Assert-ThriveLensDataInventoryGate','Test-ThriveLensWslClusterExists','Assert-ThriveLensClusterScramConfig','Resolve-ThriveLensClusterProbe','Get-ThriveLensWslClusterState',
    'Assert-ThriveLensWslInternalDisk','Resolve-ThriveLensLinuxTreeRootPolicy','Assert-ThriveLensLinuxTreePolicy','Assert-ThriveLensLinuxPathPolicy',
    'Assert-ThriveLensWslAbsent','Assert-ThriveLensWslLoopback','Assert-ThriveLensHostPortAbsent','Resolve-ThriveLensPortProxyMapping','Assert-ThriveLensNoHostPortProxy','Assert-ThriveLensHostLoopback',
    'Invoke-ThriveLensPostgresStartUnderLock','Stop-ThriveLensPostgresUnderLock','Stop-ThriveLensDistroAndVerify','Assert-ThriveLensDistroStopped','Resolve-ThriveLensCleanupContainmentPolicy','Resolve-ThriveLensWrongPasswordProbe','Resolve-ThriveLensRuntimePublicCode','Test-ThriveLensCredentialAbsenceProbeAllowed','Test-ThriveLensCredentialCleanupAllowedAfterFailure','Test-ThriveLensCleanupFailurePreservesIdentityAuthority','Resolve-ThriveLensDistroCleanupFailure','Resolve-ThriveLensCredentialCleanupResult','Resolve-ThriveLensCredentialFailureCode','Resolve-ThriveLensRuntimeFailureStage','Resolve-ThriveLensRuntimeCleanupOutcome',
    'Enter-ThriveLensLifecycleLock','Exit-ThriveLensLifecycleLock'
)
