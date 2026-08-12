#Requires -Version 7.0
[CmdletBinding()] param()
Set-StrictMode -Version Latest
$ErrorActionPreference='Stop'
$lifecycleLock=$null
$cleanupIdentityToken=$null
try {
    Import-Module (Join-Path $PSScriptRoot 'Runtime.psm1') -Force
    Import-Module (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Force
    $lifecycleLock=Enter-ThriveLensLifecycleLock
    $cleanupIdentityToken=Get-ThriveLensWslCleanupIdentityToken -LifecycleLock $lifecycleLock
    $null=Assert-ThriveLensWslCleanupIdentity -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock
    $wasRunning=Stop-ThriveLensPostgresUnderLock -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock
    if($wasRunning){$null=Invoke-ThriveLensResourceGate}
    Stop-ThriveLensDistroAndVerify -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock
    [pscustomobject]@{schema_version=1;status=if($wasRunning){'STOPPED'}else{'ALREADY_STOPPED'};absence_verified=$true}|ConvertTo-Json -Compress
}
catch{
    $code=if($_.Exception.Message -match '^[A-Z0-9_]+$'){$_.Exception.Message}else{'POSTGRES_STOP_INTERNAL_ERROR'}
    # A lock timeout/failure means another lifecycle owner may be active. Never
    # terminate by name without both ownership and the canonical identity token.
    if($null -ne $lifecycleLock -and $null -ne $cleanupIdentityToken){
        try{Stop-ThriveLensDistroAndVerify -IdentityToken $cleanupIdentityToken -LifecycleLock $lifecycleLock;Assert-ThriveLensHostPortAbsent}catch{$code='POSTGRES_FORCED_CLEANUP_UNVERIFIED'}
    }
    [pscustomobject]@{schema_version=1;status='ERROR';code=$code}|ConvertTo-Json -Compress;exit 3
}
finally{if($null -ne $lifecycleLock){Exit-ThriveLensLifecycleLock -Mutex $lifecycleLock}}
