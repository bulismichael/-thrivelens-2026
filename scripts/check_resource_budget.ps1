[CmdletBinding()]
param(
    [Parameter()]
    [ValidateRange(1, 1024)]
    [double]$CapGB = 18,

    [Parameter()]
    [ValidateRange(1, 100)]
    [double]$WarningPercent = 85,

    [Parameter()]
    [string]$Root = (Split-Path -Parent $PSScriptRoot)
)

$ErrorActionPreference = 'Stop'
$resolvedRoot = (Resolve-Path -LiteralPath $Root).Path
$capBytes = [double]($CapGB * 1GB)
$totalBytes = [double]0
$fileCount = 0

foreach ($filePath in [System.IO.Directory]::EnumerateFiles(
    $resolvedRoot,
    '*',
    [System.IO.SearchOption]::AllDirectories
)) {
    try {
        $totalBytes += [System.IO.FileInfo]::new($filePath).Length
        $fileCount += 1
    }
    catch {
        throw "Unable to account for delivery file '$filePath': $($_.Exception.Message)"
    }
}

$usedGB = [math]::Round($totalBytes / 1GB, 3)
$remainingGB = [math]::Round(($capBytes - $totalBytes) / 1GB, 3)
$usedPercent = if ($capBytes -eq 0) { 100 } else { [math]::Round(($totalBytes / $capBytes) * 100, 2) }
$os = Get-CimInstance Win32_OperatingSystem
$freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
$drive = Get-PSDrive -Name ([System.IO.Path]::GetPathRoot($resolvedRoot).Substring(0, 1))

$result = [ordered]@{
    root = $resolvedRoot
    cap_gb = $CapGB
    accounted_gb = $usedGB
    remaining_gb = $remainingGB
    used_percent = $usedPercent
    file_count = $fileCount
    host_free_disk_gb = [math]::Round($drive.Free / 1GB, 2)
    host_free_memory_gb = $freeMemoryGB
    status = if ($totalBytes -gt $capBytes) { 'CAP_EXCEEDED' } elseif ($usedPercent -ge $WarningPercent) { 'WARNING' } else { 'OK' }
}

$result | ConvertTo-Json

if ($totalBytes -gt $capBytes) {
    Write-Error "ThriveLens delivery footprint is $usedGB GB and exceeds the $CapGB GB cap."
    exit 1
}

if ($freeMemoryGB -lt 1) {
    Write-Warning "Host free memory is $freeMemoryGB GB. Keep local builds sequential and stop unused applications before emulator or release-build work."
}
