#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$PasswordFile,
    [Parameter(Mandatory)][ValidatePattern('^AUTHORIZED_DEDICATED_THRIVELENS_R0_2026_08_12$')][string]$AuthorityMarker,
    [string]$BootstrapUser = 'tl_bootstrap'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$mutated = $false
$staging = $null
$distroPasswordFile = $null
$lifecycleLock=$null
$fatalCleanup=$false
$activated=$false
$activationAttempted=$false
$passwordValue=$null
$wslTouched=$false
try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $preflight = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot 'preflight.ps1') -Action Initialize 2>&1)
    if ($LASTEXITCODE -ne 0) { $preflight | Write-Output; exit $LASTEXITCODE }
    $lifecycleLock=Enter-ThriveLensLifecycleLock
    # Revalidate mutable host/distro state after acquiring the lifecycle lock.
    $lockedManifest=Get-ThriveLensManifest
    if(@($lockedManifest.resource_policy.allowed_active_phases) -cnotcontains (Get-ThriveLensResourcePhase)){throw 'RESOURCE_PHASE_NOT_ACTIVE_AFTER_LIFECYCLE_LOCK'}
    $null=Invoke-ThriveLensResourceGate -ProjectedAdditionalBytes 134217728
    if((Get-ThriveLensFreeMemoryBytes) -lt 1073741824){throw 'LOW_FREE_MEMORY_AFTER_LIFECYCLE_LOCK'}
    $wslTouched=$true
    $null=Assert-ThriveLensWslIdentity;Assert-ThriveLensWslPackages
    Assert-ThriveLensDataInventoryGate
    if ($BootstrapUser -cne 'tl_bootstrap') { throw 'BOOTSTRAP_USER_MISMATCH' }
    $clusterState=Get-ThriveLensWslClusterState
    if($clusterState -ceq 'VALID'){
        Assert-ThriveLensDataInventoryGate;Assert-ThriveLensWslAbsent;$null=Invoke-ThriveLensResourceGate
        Stop-ThriveLensDistroAndVerify;Assert-ThriveLensHostPortAbsent
        [pscustomobject]@{schema_version=1;status='ALREADY_INITIALIZED';authentication='scram-sha-256';data_checksums=$true}|ConvertTo-Json -Compress;return
    }
    if($clusterState -cne 'ABSENT'){throw 'PARTIAL_CLUSTER_PRESENT'}
    # An absent target directory does not prove the dedicated distro is free
    # of an orphan/manual PostgreSQL 17 process or host exposure.
    Assert-ThriveLensWslAbsent
    Assert-ThriveLensHostPortAbsent
    Assert-ThriveLensLinuxPathPolicy
    $manifest=Get-ThriveLensManifest
    $expectedPassword=[IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$manifest.wsl_fallback.host_password_file))
    $passwordPath = Assert-ThriveLensOwnedPath -Path $PasswordFile
    if($passwordPath -cne $expectedPassword){throw 'PASSWORD_FILE_PATH_MISMATCH'}
    $passwordValue = Read-ThriveLensPostgresBootstrapSecret -Path $passwordPath
    $paths = Get-ThriveLensWslPaths
    if($paths.DataRoot -cne '/var/lib/thrivelens/postgresql/r0' -or $paths.LogRoot -cne '/var/log/thrivelens/postgresql/r0' -or $paths.DataRoot -match '\\' -or $paths.LogRoot -match '\\'){throw 'LINUX_PATH_CONTRACT_MISMATCH'}
    $parent = '/var/lib/thrivelens/postgresql'
    $logParent = $paths.LogRoot
    # Conservatively mark the operation as mutating before the first command
    # that can create a directory, so every partial first-init path receives
    # post-mutation accounting and exact distro cleanup.
    $mutated = $true
    foreach($directory in @('/var/lib/thrivelens',$parent,'/var/log/thrivelens','/var/log/thrivelens/postgresql',$logParent)){
        $exists=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$directory)
        if($exists.ExitCode -eq 1){$mkdir=Invoke-ThriveLensDistro -Arguments @('/usr/bin/install','-d','-o','postgres','-g','postgres','-m','0700',$directory);if($mkdir.ExitCode -ne 0){throw 'CLUSTER_DIRECTORY_CREATE_FAILED'}}
        elseif($exists.ExitCode -ne 0){throw 'WSL_PATH_MEASUREMENT_FAILED'}
    }
    Assert-ThriveLensLinuxPathPolicy
    $nonce=[guid]::NewGuid().ToString('N')
    $staging="$parent/.r0-staging-$nonce"
    $stale=Invoke-ThriveLensDistro -Arguments @('/usr/bin/find',$parent,'-mindepth','1','-maxdepth','1','-name','.r0-staging-*','-print','-quit')
    if($stale.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($stale.Output)){throw 'STALE_STAGING_PRESENT'}
    $distroPasswordFile="/run/thrivelens-r0-$nonce.pw"
    try {
        $pwCreate=Invoke-ThriveLensDistro -StandardInput ($passwordValue+"`n") -Arguments @('/usr/bin/install','-o','postgres','-g','postgres','-m','0600','/dev/stdin',$distroPasswordFile)
    }
    finally { $passwordValue=$null }
    if($pwCreate.ExitCode -ne 0){throw 'DISTRO_PASSWORD_FILE_CREATE_FAILED'}
    $init = Invoke-ThriveLensDistro -TimeoutSeconds 120 -Arguments @(
        '/usr/sbin/runuser','-u','postgres','--','/usr/lib/postgresql/17/bin/initdb',
        '--pgdata',$staging,'--username','tl_bootstrap',"--pwfile=$distroPasswordFile",
        '--auth-host=scram-sha-256','--auth-local=scram-sha-256','--encoding=UTF8','--locale=C',
        '--data-checksums','--no-instructions'
    )
    $unlink=Invoke-ThriveLensDistro -Arguments @('/usr/bin/rm','-f','--',$distroPasswordFile)
    $absent=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','!','-e',$distroPasswordFile)
    if($unlink.ExitCode -ne 0 -or $absent.ExitCode -ne 0){throw 'DISTRO_PASSWORD_FILE_CLEANUP_FAILED'};$distroPasswordFile=$null
    if ($init.ExitCode -ne 0) { throw 'INITDB_FAILED' }
    $null = Assert-ThriveLensLinuxTreePolicy -Root $staging
    $control = Invoke-ThriveLensDistro -Arguments @('/usr/lib/postgresql/17/bin/pg_controldata',$staging)
    if ($control.ExitCode -ne 0 -or $control.Output -notmatch '(?m)^Data page checksum version:\s+1\s*$') { throw 'DATA_CHECKSUM_VERIFICATION_FAILED' }
    $size = Invoke-ThriveLensDistro -Arguments @('/usr/bin/du','-sb',$staging)
    if ($size.ExitCode -ne 0 -or $size.Output -notmatch '^([0-9]+)\s') { throw 'CLUSTER_SIZE_MEASUREMENT_FAILED' }
    $bytes = [int64]$Matches[1]
    if ($bytes -gt [int64]$manifest.postgresql.maximum_initial_cluster_bytes) { throw 'CLUSTER_SIZE_LIMIT_EXCEEDED' }
    $finalAbsent=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','!','-e',$paths.DataRoot);if($finalAbsent.ExitCode -ne 0){throw 'CLUSTER_ACTIVATION_TARGET_PRESENT'}
    $activationAttempted=$true
    $move=Invoke-ThriveLensDistro -Arguments @('/usr/bin/mv','-T','--no-clobber','--',$staging,$paths.DataRoot)
    if($move.ExitCode -ne 0){throw 'CLUSTER_ACTIVATION_FAILED'}
    $sourceAbsent=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','!','-e',$staging);$finalExists=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$paths.DataRoot)
    if($sourceAbsent.ExitCode -ne 0 -or $finalExists.ExitCode -ne 0){throw 'CLUSTER_ACTIVATION_AMBIGUOUS'}
    $activated=$true;$staging=$null
    Assert-ThriveLensLinuxPathPolicy -RequireLeaf
    if((Get-ThriveLensWslClusterState) -cne 'VALID'){throw 'INITDB_RESULT_INVALID'}
    $null = Invoke-ThriveLensResourceGate
    Stop-ThriveLensDistroAndVerify
    Assert-ThriveLensHostPortAbsent
    [pscustomobject]@{ schema_version=1; status='INITIALIZED'; authentication='scram-sha-256'; data_checksums=$true; cluster_bytes=$bytes } | ConvertTo-Json -Compress
}
catch {
    $passwordValue=$null
    $code = if ($_.Exception.Message -match '^[A-Z0-9_]+$') { $_.Exception.Message } else { 'INITIALIZE_INTERNAL_ERROR' }
    if($null -ne $distroPasswordFile){try{$unlink=Invoke-ThriveLensDistro -Arguments @('/usr/bin/rm','-f','--',$distroPasswordFile);$absent=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','!','-e',$distroPasswordFile);if($unlink.ExitCode -ne 0 -or $absent.ExitCode -ne 0){throw 'cleanup'}}catch{$code='INITIALIZE_CREDENTIAL_CLEANUP_FAILED';$fatalCleanup=$true}}
    # Once mv has been attempted, either the final cluster exists or the
    # activation state is uncertain. Preserve it for explicit recovery and
    # report a fatal outcome; never recursively remove either candidate.
    if($activationAttempted -or $activated){$fatalCleanup=$true}
    if($null -ne $staging -and -not $activationAttempted -and -not $activated){
        try{
            Assert-ThriveLensWslAbsent
            $exists=Invoke-ThriveLensDistro -Arguments @('/usr/bin/test','-e',$staging)
            if($exists.ExitCode -eq 1){$staging=$null}
            elseif($exists.ExitCode -ne 0){throw 'measurement'}
            if($null -ne $staging){$null=Assert-ThriveLensLinuxTreePolicy -Root $staging}
            if($null -ne $staging){$cleanup=Invoke-ThriveLensDistro -Arguments @('/usr/bin/python3','-c',@'
import os,re,stat,sys
p=os.fsencode(sys.argv[1]); parent=b'/var/lib/thrivelens/postgresql'; name=os.path.basename(p)
if os.path.dirname(p) != parent or not re.fullmatch(br'\.r0-staging-[0-9a-f]{32}',name): raise SystemExit(2)
flags=os.O_RDONLY|os.O_DIRECTORY|getattr(os,'O_CLOEXEC',0)|getattr(os,'O_NOFOLLOW',0)
fileflags=os.O_RDONLY|getattr(os,'O_CLOEXEC',0)|getattr(os,'O_NOFOLLOW',0)
def mount_id(fd):
    try:
        with open('/proc/self/fdinfo/'+str(fd),'rt',encoding='ascii') as info:
            rows=[line for line in info if line.startswith('mnt_id:')]
        if len(rows)!=1: raise ValueError()
        return int(rows[0].split(':',1)[1].strip())
    except (OSError,ValueError): raise SystemExit(3)
def rm_tree(fd):
    if mount_id(fd) != rootmount: raise SystemExit(3)
    with os.scandir(fd) as entries:
        for item in entries:
            meta=item.stat(follow_symlinks=False)
            if meta.st_dev != rootdev or stat.S_ISLNK(meta.st_mode): raise SystemExit(3)
            if stat.S_ISDIR(meta.st_mode):
                child=os.open(item.name,flags,dir_fd=fd)
                try:
                    opened=os.fstat(child)
                    if opened.st_dev != meta.st_dev or opened.st_ino != meta.st_ino or mount_id(child) != rootmount: raise SystemExit(3)
                    rm_tree(child)
                finally: os.close(child)
                os.rmdir(item.name,dir_fd=fd)
            elif stat.S_ISREG(meta.st_mode):
                leaf=os.open(item.name,fileflags,dir_fd=fd)
                try:
                    opened=os.fstat(leaf)
                    if opened.st_dev != meta.st_dev or opened.st_ino != meta.st_ino or mount_id(leaf) != rootmount: raise SystemExit(3)
                finally: os.close(leaf)
                os.unlink(item.name,dir_fd=fd)
            else: raise SystemExit(3)
rootfd=os.open(b'/',flags)
try:
    rootdev=os.fstat(rootfd).st_dev; trustedmount=mount_id(rootfd)
finally: os.close(rootfd)
parentfd=os.open(parent,flags)
try:
    if os.fstat(parentfd).st_dev != rootdev or mount_id(parentfd) != trustedmount: raise SystemExit(3)
    fd=os.open(name,flags,dir_fd=parentfd)
    try:
        root=os.fstat(fd)
        if root.st_dev != rootdev: raise SystemExit(3)
        rootmount=mount_id(fd)
        if rootmount != trustedmount: raise SystemExit(3)
        rm_tree(fd)
    finally: os.close(fd)
    os.rmdir(name,dir_fd=parentfd)
finally: os.close(parentfd)
'@,$staging)
            if($cleanup.ExitCode -ne 0){throw 'cleanup'}}
        }catch{if($null -ne $staging){$code='INITIALIZE_ROLLBACK_FAILED';$fatalCleanup=$true}}
    }
    if ($mutated) { try { $null = Invoke-ThriveLensResourceGate } catch { if(-not $fatalCleanup){$code = 'POST_MUTATION_RESOURCE_GATE_FAILED'};$fatalCleanup=$true } }
    if($wslTouched -or $mutated -or $activationAttempted){
        try{Assert-ThriveLensWslAbsent;Assert-ThriveLensHostPortAbsent}catch{$code='INITIALIZE_DISTRO_CLEANUP_FAILED';$fatalCleanup=$true}
        try{Stop-ThriveLensDistroAndVerify}catch{$code='INITIALIZE_DISTRO_CLEANUP_FAILED';$fatalCleanup=$true}
        try{Assert-ThriveLensHostPortAbsent}catch{$code='INITIALIZE_DISTRO_CLEANUP_FAILED';$fatalCleanup=$true}
    }
    [pscustomobject]@{ schema_version=1; status=if($fatalCleanup){'ERROR'}else{'BLOCKED'}; code=$code } | ConvertTo-Json -Compress
    if($fatalCleanup){exit 3};exit 2
}
finally{$passwordValue=$null;if($null -ne $lifecycleLock){Exit-ThriveLensLifecycleLock -Mutex $lifecycleLock}}
