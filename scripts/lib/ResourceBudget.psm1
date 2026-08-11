Set-StrictMode -Version Latest

function Test-IsReparsePoint {
    param([Parameter(Mandatory)][IO.FileSystemInfo]$Item)
    return [bool]($Item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-ValidatedRoot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][bool]$Required
    )

    if ($Path -match '%[^%]+%') {
        throw "Resource root '$Label' contains an unresolved environment variable."
    }
    if (-not [IO.Path]::IsPathRooted($Path)) {
        throw "Resource root '$Label' must be absolute."
    }
    if ($Path.StartsWith('\\')) {
        throw "Resource root '$Label' must be on a local filesystem."
    }

    $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $volumeRoot = [IO.Path]::GetPathRoot($fullPath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($fullPath -eq $volumeRoot) {
        throw "Resource root '$Label' cannot be a filesystem volume root."
    }

    if (-not (Test-Path -LiteralPath $fullPath -PathType Container)) {
        if ($Required) { throw "Required resource root '$Label' is missing." }
        return [pscustomobject]@{ Label = $Label; Missing = $true; FullPath = $fullPath }
    }

    $item = Get-Item -LiteralPath $fullPath -Force
    if (Test-IsReparsePoint -Item $item) {
        throw "Resource root '$Label' cannot be a symbolic link or junction."
    }

    return [pscustomobject]@{ Label = $Label; Missing = $false; FullPath = $item.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) }
}

function Measure-SafeRoot {
    param(
        [Parameter(Mandatory)][string]$Label,
        [Parameter(Mandatory)][string]$RootPath
    )

    $rootInfo = [IO.DirectoryInfo]::new($RootPath)
    $rootPrefix = $rootInfo.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $directories = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
    $directories.Push($rootInfo)
    $bytes = [double]0
    $files = 0

    while ($directories.Count -gt 0) {
        $directory = $directories.Pop()
        try {
            foreach ($file in $directory.EnumerateFiles()) {
                if (Test-IsReparsePoint -Item $file) {
                    throw "Resource root '$Label' contains a symbolic-link or reparse-point file."
                }
                $fileFullPath = $file.FullName
                if (-not $fileFullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Resource root '$Label' escaped its approved boundary."
                }
                $bytes += $file.Length
                $files += 1
            }

            foreach ($child in $directory.EnumerateDirectories()) {
                if (Test-IsReparsePoint -Item $child) {
                    throw "Resource root '$Label' contains a symbolic link or junction."
                }
                $childFullPath = $child.FullName.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
                if (-not $childFullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw "Resource root '$Label' escaped its approved boundary."
                }
                $directories.Push($child)
            }
        }
        catch {
            if ($_.Exception.Message -like "Resource root '$Label'*") { throw }
            throw "Unable to account for every file in resource root '$Label'."
        }
    }

    $drive = Get-PSDrive -PSProvider FileSystem |
        Where-Object { $RootPath.StartsWith($_.Root, [StringComparison]::OrdinalIgnoreCase) } |
        Sort-Object { $_.Root.Length } -Descending |
        Select-Object -First 1

    return [pscustomobject]@{
        label = $Label
        bytes = [int64]$bytes
        gb = [math]::Round($bytes / 1GB, 3)
        file_count = $files
        volume = if ($drive) { $drive.Name } else { $null }
        free_disk_gb = if ($drive) { [math]::Round($drive.Free / 1GB, 2) } else { $null }
    }
}

function Measure-ThriveLensResourceBudget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$RootSpec,
        [Parameter(Mandatory)][ValidateRange(0.000001, 1024)][double]$CapGB,
        [Parameter(Mandatory)][ValidateRange(1, 99)][double]$WarningPercent,
        [Parameter(Mandatory)][ValidateRange(1, 99)][double]$HardStopPercent
    )

    if ($WarningPercent -ge $HardStopPercent) {
        throw 'WarningPercent must be lower than HardStopPercent.'
    }

    $validated = [Collections.Generic.List[object]]::new()
    $missing = [Collections.Generic.List[string]]::new()
    $labels = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)

    foreach ($spec in $RootSpec) {
        $label = [string]$spec.Label
        if ([string]::IsNullOrWhiteSpace($label) -or -not $labels.Add($label)) {
            throw 'Resource root labels must be non-empty and unique.'
        }
        $root = Get-ValidatedRoot -Label $label -Path ([string]$spec.Path) -Required ([bool]$spec.Required)
        if ($root.Missing) { $missing.Add($label) } else { $validated.Add($root) }
    }

    $sorted = $validated | Sort-Object { $_.FullPath.Length }, FullPath
    $deduplicated = [Collections.Generic.List[object]]::new()
    $coveredLabels = [Collections.Generic.List[string]]::new()
    foreach ($root in $sorted) {
        $covering = $deduplicated | Where-Object {
            $root.FullPath -eq $_.FullPath -or
            $root.FullPath.StartsWith($_.FullPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        } | Select-Object -First 1
        if ($covering) {
            $coveredLabels.Add($root.Label)
        }
        else {
            $deduplicated.Add($root)
        }
    }

    $rootResults = [Collections.Generic.List[object]]::new()
    $totalBytes = [double]0
    $fileCount = 0
    foreach ($root in $deduplicated) {
        $measurement = Measure-SafeRoot -Label $root.Label -RootPath $root.FullPath
        $rootResults.Add($measurement)
        $totalBytes += $measurement.bytes
        $fileCount += $measurement.file_count
    }

    $capBytes = [double]($CapGB * 1GB)
    $rawUsedPercent = ($totalBytes / $capBytes) * 100
    $usedPercent = [math]::Round($rawUsedPercent, 2)
    $status = if ($totalBytes -ge $capBytes) {
        'CAP_EXCEEDED'
    }
    elseif ($rawUsedPercent -ge $HardStopPercent) {
        'HARD_STOP'
    }
    elseif ($rawUsedPercent -ge $WarningPercent) {
        'WARNING'
    }
    else {
        'OK'
    }

    return [pscustomobject][ordered]@{
        cap_gb = $CapGB
        accounted_bytes = [int64]$totalBytes
        accounted_gb = [math]::Round($totalBytes / 1GB, 3)
        remaining_gb = [math]::Round(($capBytes - $totalBytes) / 1GB, 3)
        used_percent = $usedPercent
        warning_percent = $WarningPercent
        hard_stop_percent = $HardStopPercent
        file_count = $fileCount
        roots = $rootResults
        missing_inactive_roots = $missing
        nested_roots_already_covered = $coveredLabels
        status = $status
    }
}

Export-ModuleMember -Function Measure-ThriveLensResourceBudget
