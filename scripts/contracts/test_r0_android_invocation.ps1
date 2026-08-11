[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'R0AndroidInvocation.psm1') -Force

function Assert-Equal {
    param($Actual, $Expected, [string] $Label)
    if ($Actual -cne $Expected) {
        throw "Android invocation primitive mismatch: $Label."
    }
}

$startCharacters = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._:'
$continuationCharacters = $startCharacters + '-'
for ($code = 0; $code -le 127; $code++) {
    $character = [char]$code
    $startCandidate = [string]$character + 'A'
    $middleCandidate = 'A' + [string]$character + 'B'
    $endCandidate = 'A' + [string]$character
    Assert-Equal (Test-R0AndroidDeviceSerial $startCandidate) $startCharacters.Contains($character) "ASCII $code at start"
    Assert-Equal (Test-R0AndroidDeviceSerial $middleCandidate) $continuationCharacters.Contains($character) "ASCII $code at middle"
    Assert-Equal (Test-R0AndroidDeviceSerial $endCandidate) $continuationCharacters.Contains($character) "ASCII $code at end"
}
Assert-Equal (Test-R0AndroidDeviceSerial '') $false 'empty serial'
Assert-Equal (Test-R0AndroidDeviceSerial ('A' * 128)) $true 'maximum serial length'
Assert-Equal (Test-R0AndroidDeviceSerial ('A' * 129)) $false 'oversized serial'

$hostileArguments = @('A&B', 'A<B', 'A>B', 'A"B', "A'B", 'A%B', 'A`B', "A`tB", 'A B')
$info = New-R0ProcessStartInfo -FilePath 'fixture-tool.exe' -Arguments $hostileArguments
Assert-Equal $info.UseShellExecute $false 'UseShellExecute'
Assert-Equal $info.FileName 'fixture-tool.exe' 'executable path'
Assert-Equal (($info.ArgumentList | ForEach-Object { [string]$_ }) -join "`n") ($hostileArguments -join "`n") 'ArgumentList preservation'

foreach ($unsafe in @('', '-e', '--help', 'A&B', 'A<B', 'A>B', 'A"B', "A'B", 'A%B', 'A`B', "A`tB", 'A B')) {
    $rejected = $false
    try {
        New-R0AndroidInvocationPlan -DeviceSerial $unsafe -AdbPath 'fixture-adb.exe' -HeartbeatProbePath 'fixture-probe.exe' | Out-Null
    }
    catch {
        $rejected = $true
    }
    if (-not $rejected) {
        throw 'Unsafe serial reached an Android child invocation.'
    }
}

$plan = New-R0AndroidInvocationPlan -DeviceSerial 'fixture-device' -AdbPath 'fixture-adb.exe' -HeartbeatProbePath 'fixture-probe.exe'
Assert-Equal $plan.Reverse.FileName 'fixture-adb.exe' 'reverse executable'
Assert-Equal ((@($plan.Reverse.ArgumentList) -join ' ')) '-s fixture-device reverse tcp:8000 tcp:8000' 'reverse arguments'
Assert-Equal $plan.Probe.FileName 'fixture-probe.exe' 'probe executable'
Assert-Equal ((@($plan.Probe.ArgumentList) -join ' ')) '--base-url http://127.0.0.1:8000/api/v1 --mode debug' 'probe arguments'
Assert-Equal $plan.Cleanup.FileName 'fixture-adb.exe' 'cleanup executable'
Assert-Equal ((@($plan.Cleanup.ArgumentList) -join ' ')) '-s fixture-device reverse --remove tcp:8000' 'cleanup arguments'

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase ("thrivelens-r0-android-invocation-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)
$priorAdbLog = [Environment]::GetEnvironmentVariable('THRIVELENS_FAKE_ADB_LOG', 'Process')
$priorProbeLog = [Environment]::GetEnvironmentVariable('THRIVELENS_FAKE_PROBE_LOG', 'Process')
try {
    $fixtureSource = Join-Path $temporaryRoot 'fixture-tool.py'
    $fixture = @'
from __future__ import annotations
import os
import sys
from pathlib import Path
role = Path(sys.argv[0]).stem.lower()
arguments = sys.argv[1:]
if role.startswith("fake-adb"):
    with open(os.environ["THRIVELENS_FAKE_ADB_LOG"], "a", encoding="utf-8") as handle:
        handle.write(" ".join(arguments) + "\n")
    raise SystemExit(0)
with open(os.environ["THRIVELENS_FAKE_PROBE_LOG"], "a", encoding="utf-8") as handle:
    handle.write(" ".join(arguments) + "\n")
raise SystemExit(7 if role.startswith("probe-fail") else 0)
'@
    Set-Content -LiteralPath $fixtureSource -Value $fixture -Encoding UTF8 -NoNewline
    $fakeAdb = Join-Path $temporaryRoot 'fake-adb.py'
    $probeOk = Join-Path $temporaryRoot 'probe-ok.py'
    $probeFail = Join-Path $temporaryRoot 'probe-fail.py'
    Copy-Item -LiteralPath $fixtureSource -Destination $fakeAdb
    Copy-Item -LiteralPath $fixtureSource -Destination $probeOk
    Copy-Item -LiteralPath $fixtureSource -Destination $probeFail
    $adbLog = Join-Path $temporaryRoot 'adb.log'
    $probeLog = Join-Path $temporaryRoot 'probe.log'
    [Environment]::SetEnvironmentVariable('THRIVELENS_FAKE_ADB_LOG', $adbLog, 'Process')
    [Environment]::SetEnvironmentVariable('THRIVELENS_FAKE_PROBE_LOG', $probeLog, 'Process')

    Invoke-R0AndroidVerification -DeviceSerial 'fixture-device' -AdbPath $fakeAdb -HeartbeatProbePath $probeOk
    Assert-Equal ((Get-Content -LiteralPath $adbLog) -join "`n") "-s fixture-device reverse tcp:8000 tcp:8000`n-s fixture-device reverse --remove tcp:8000" 'real reverse and cleanup lifecycle'
    Assert-Equal ((Get-Content -LiteralPath $probeLog) -join "`n") '--base-url http://127.0.0.1:8000/api/v1 --mode debug' 'real probe lifecycle'

    Remove-Item -LiteralPath $adbLog
    Remove-Item -LiteralPath $probeLog
    $probeRejected = $false
    try {
        Invoke-R0AndroidVerification -DeviceSerial 'fixture-device' -AdbPath $fakeAdb -HeartbeatProbePath $probeFail
    }
    catch {
        $probeRejected = $true
    }
    if (-not $probeRejected) {
        throw 'Android invocation primitive did not propagate probe failure.'
    }
    Assert-Equal ((Get-Content -LiteralPath $adbLog) -join "`n") "-s fixture-device reverse tcp:8000 tcp:8000`n-s fixture-device reverse --remove tcp:8000" 'failure cleanup lifecycle'
}
finally {
    [Environment]::SetEnvironmentVariable('THRIVELENS_FAKE_ADB_LOG', $priorAdbLog, 'Process')
    [Environment]::SetEnvironmentVariable('THRIVELENS_FAKE_PROBE_LOG', $priorProbeLog, 'Process')
    $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryRoot)
    if (-not $resolvedTemporary.StartsWith($temporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -or $resolvedTemporary -eq $temporaryBase) {
        throw 'Refusing to remove an unexpected Android invocation temporary path.'
    }
    if (Test-Path -LiteralPath $resolvedTemporary) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}

Write-Output 'TL-R0-002 Android invocation primitive PASS: exhaustive ASCII positions, bounds, no-shell argv, and reject-before-child.'
