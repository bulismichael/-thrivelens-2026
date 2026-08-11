Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:SafeDeviceSerialPattern = '\A[A-Za-z0-9._:][A-Za-z0-9._:-]{0,127}\z'
$script:DebugBaseUrl = 'http://127.0.0.1:8000/api/v1'
$script:ProcessTimeoutMilliseconds = 20000

function Test-R0AndroidDeviceSerial {
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $DeviceSerial)

    return (
        $null -ne $DeviceSerial -and
        [System.Text.RegularExpressions.Regex]::IsMatch(
            $DeviceSerial,
            $script:SafeDeviceSerialPattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
    )
}

function Assert-R0AndroidDeviceSerial {
    [CmdletBinding()]
    param([AllowNull()] [AllowEmptyString()] [string] $DeviceSerial)

    if (-not (Test-R0AndroidDeviceSerial -DeviceSerial $DeviceSerial)) {
        throw 'ADB device serial must be one bounded explicit non-option argument.'
    }
    return $DeviceSerial
}

function New-R0ProcessStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $FilePath,
        [Parameter(Mandatory)] [AllowEmptyCollection()] [string[]] $Arguments
    )

    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = $FilePath
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    foreach ($argument in $Arguments) {
        if ($null -eq $argument -or $argument.Contains([char]0)) {
            throw 'Process arguments must be non-null and NUL-free.'
        }
        [void]$info.ArgumentList.Add($argument)
    }
    return $info
}

function Invoke-R0Process {
    param(
        [Parameter(Mandatory)] [System.Diagnostics.ProcessStartInfo] $StartInfo
    )

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $StartInfo
    try {
        if (-not $process.Start()) {
            throw 'Android verification child could not start.'
        }
        if (-not $process.WaitForExit($script:ProcessTimeoutMilliseconds)) {
            try { $process.Kill($true) } catch { }
            try { [void]$process.WaitForExit(500) } catch { }
            throw 'Android verification child exceeded its bounded timeout.'
        }
        return $process.ExitCode
    }
    finally {
        $process.Dispose()
    }
}

function New-R0SelectedProcessStartInfo {
    param(
        [Parameter(Mandatory)] [string] $FilePath,
        [Parameter(Mandatory)] [string[]] $Arguments
    )

    $selectedFile = $FilePath
    $selectedArguments = @($Arguments)
    $extension = [System.IO.Path]::GetExtension($FilePath)
    if ($extension -ceq '.ps1') {
        $hosts = @(Get-Command pwsh -CommandType Application -ErrorAction Stop)
        $selectedFile = [string]$hosts[0].Source
        $selectedArguments = @('-NoProfile', '-NonInteractive', '-File', $FilePath) + $selectedArguments
    }
    elseif ($extension -ceq '.py') {
        $hosts = @(Get-Command python -CommandType Application -ErrorAction Stop)
        $selectedFile = [string]$hosts[0].Source
        $selectedArguments = @($FilePath) + $selectedArguments
    }
    return New-R0ProcessStartInfo -FilePath $selectedFile -Arguments $selectedArguments
}

function New-R0AndroidInvocationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $DeviceSerial,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $AdbPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $HeartbeatProbePath
    )

    $selected = Assert-R0AndroidDeviceSerial -DeviceSerial $DeviceSerial
    return [pscustomobject]@{
        Reverse = New-R0SelectedProcessStartInfo -FilePath $AdbPath -Arguments @(
            '-s', $selected, 'reverse', 'tcp:8000', 'tcp:8000'
        )
        Probe = New-R0SelectedProcessStartInfo -FilePath $HeartbeatProbePath -Arguments @(
            '--base-url', $script:DebugBaseUrl, '--mode', 'debug'
        )
        Cleanup = New-R0SelectedProcessStartInfo -FilePath $AdbPath -Arguments @(
            '-s', $selected, 'reverse', '--remove', 'tcp:8000'
        )
    }
}

function Invoke-R0AndroidVerification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $DeviceSerial,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $AdbPath,
        [Parameter(Mandatory)] [ValidateNotNullOrEmpty()] [string] $HeartbeatProbePath
    )

    $plan = New-R0AndroidInvocationPlan -DeviceSerial $DeviceSerial -AdbPath $AdbPath -HeartbeatProbePath $HeartbeatProbePath
    $failure = $null
    try {
        $reverseExit = Invoke-R0Process -StartInfo $plan.Reverse
        if ($reverseExit -ne 0) {
            throw 'ADB reverse mapping failed.'
        }

        $probeExit = Invoke-R0Process -StartInfo $plan.Probe
        if ($probeExit -ne 0) {
            throw 'Android heartbeat probe failed.'
        }
    }
    catch {
        $failure = $_
    }
    finally {
        try {
            $cleanupExit = Invoke-R0Process -StartInfo $plan.Cleanup
            if ($cleanupExit -ne 0 -and $null -eq $failure) {
                $failure = [System.Management.Automation.ErrorRecord]::new(
                    [System.InvalidOperationException]::new('ADB reverse cleanup failed.'),
                    'R0AndroidCleanupFailed',
                    [System.Management.Automation.ErrorCategory]::OperationStopped,
                    $null
                )
            }
        }
        catch {
            if ($null -eq $failure) { $failure = $_ }
        }
    }
    if ($null -ne $failure) {
        throw $failure
    }
}

Export-ModuleMember -Function Test-R0AndroidDeviceSerial, Assert-R0AndroidDeviceSerial, New-R0ProcessStartInfo, New-R0AndroidInvocationPlan, Invoke-R0AndroidVerification
