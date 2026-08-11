Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:RepositoryRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$script:MaximumCombinedOutputBytes = 65536
$script:OutputReadChunkBytes = 4096
$script:PostKillDrainMilliseconds = 500
$script:PostExitDrainMilliseconds = 1000
$script:EntryKeys = @(
    'argv',
    'expected_missing_behavior_marker',
    'future_green_command',
    'id',
    'owner',
    'test_ids',
    'timeout_seconds',
    'working_directory'
)

function Test-ExactKeys {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Value,
        [Parameter(Mandatory)] [string[]] $Expected,
        [Parameter(Mandatory)] [string] $Label
    )

    $actual = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $wanted = @($Expected | Sort-Object)
    if (($actual -join "`n") -cne ($wanted -join "`n")) {
        throw "$Label has unknown or missing keys."
    }
}

function Read-ExpectedRedManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $ManifestPath)

    $resolved = Resolve-Path -LiteralPath $ManifestPath -ErrorAction Stop
    $file = Get-Item -LiteralPath $resolved.Path -Force
    if ($file.Length -gt 262144) {
        throw 'Expected-red manifest exceeds 256 KiB.'
    }
    $raw = Get-Content -Raw -LiteralPath $resolved.Path -Encoding UTF8
    try {
        $manifest = $raw | ConvertFrom-Json -AsHashtable -Depth 32
    }
    catch {
        throw 'Expected-red manifest is not valid bounded JSON.'
    }
    if ($manifest -isnot [System.Collections.IDictionary]) {
        throw 'Expected-red manifest root must be an object.'
    }
    Test-ExactKeys -Value $manifest -Expected @('entries', 'schema_version') -Label 'Manifest root'
    if ($manifest.schema_version -isnot [long] -and $manifest.schema_version -isnot [int]) {
        throw 'Expected-red schema_version must be an integer.'
    }
    if ([int]$manifest.schema_version -ne 1) {
        throw 'Expected-red schema_version must be 1.'
    }
    $entries = @($manifest.entries)
    if ($entries.Count -lt 1 -or $entries.Count -gt 16) {
        throw 'Expected-red manifest must contain 1 through 16 entries.'
    }

    $seenIds = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    $seenTests = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::Ordinal)
    foreach ($entry in $entries) {
        if ($entry -isnot [System.Collections.IDictionary]) {
            throw 'Every expected-red entry must be an object.'
        }
        Test-ExactKeys -Value $entry -Expected $script:EntryKeys -Label 'Manifest entry'
        $id = [string]$entry.id
        $owner = [string]$entry.owner
        if ($id -notmatch '^TL-R0-[0-9]{3}-[A-Z0-9-]{1,80}$') {
            throw 'Expected-red entry ID is not bounded or canonical.'
        }
        if (-not $seenIds.Add($id)) {
            throw 'Expected-red entry IDs must be unique.'
        }
        if ($owner -notmatch '^TL-R0-[0-9]{3}$') {
            throw "Expected-red owner is invalid for $id."
        }
        if ([string]$entry.working_directory -cne '.') {
            throw "Expected-red working_directory must be repository dot for $id."
        }
        $argv = @($entry.argv)
        if ($argv.Count -lt 2 -or $argv.Count -gt 24) {
            throw "Expected-red argv must contain 2 through 24 arguments for $id."
        }
        foreach ($argument in $argv) {
            if ($argument -isnot [string] -or $argument.Length -lt 1 -or $argument.Length -gt 2048) {
                throw "Expected-red argv has an invalid argument for $id."
            }
            if ($argument.Contains([char]0) -or $argument.Contains("`r") -or $argument.Contains("`n")) {
                throw "Expected-red argv contains a control character for $id."
            }
        }
        if ([string]$argv[0] -cne 'python') {
            throw "Expected-red executable must be python for $id."
        }
        if ([string]$argv[1] -in @('-c', '-')) {
            throw "Expected-red inline or standard-input Python execution is forbidden for $id."
        }
        $timeout = $entry.timeout_seconds
        if (($timeout -isnot [long] -and $timeout -isnot [int]) -or [int]$timeout -lt 1 -or [int]$timeout -gt 120) {
            throw "Expected-red timeout must be an integer from 1 through 120 for $id."
        }
        $testIds = @($entry.test_ids)
        if ($testIds.Count -ne 1) {
            throw "Expected-red entry must name exactly one collected test for $id."
        }
        $testId = [string]$testIds[0]
        if ($testId -notmatch '^(?:tests\.|__main__\.)[A-Za-z0-9_.]{3,300}$') {
            throw "Expected-red test ID is invalid for $id."
        }
        if (-not $seenTests.Add($testId)) {
            throw 'Expected-red test IDs must be globally unique.'
        }
        $expectedMarker = "THRIVELENS_MISSING_IMPLEMENTATION::$id"
        if ([string]$entry.expected_missing_behavior_marker -cne $expectedMarker) {
            throw "Expected-red marker is not derived from its ID for $id."
        }
        $futureCommand = [string]$entry.future_green_command
        if ($futureCommand.Length -lt 20 -or $futureCommand.Length -gt 500 -or
            $futureCommand -notmatch [regex]::Escape("-Owner $owner")) {
            throw "Expected-red future green command does not bind its owner for $id."
        }
    }
    return [pscustomobject]@{
        Path = $resolved.Path
        Entries = $entries
    }
}

function Add-BoundedOutputChunk {
    param(
        [Parameter(Mandatory)] [System.IO.MemoryStream] $Destination,
        [Parameter(Mandatory)] [byte[]] $Buffer,
        [Parameter(Mandatory)] [int] $Count,
        [Parameter(Mandatory)] [ref] $CombinedCount
    )

    $remaining = $script:MaximumCombinedOutputBytes - [int]$CombinedCount.Value
    $accepted = [Math]::Min([Math]::Max($remaining, 0), $Count)
    if ($accepted -gt 0) {
        $Destination.Write($Buffer, 0, $accepted)
        $CombinedCount.Value = [int]$CombinedCount.Value + $accepted
    }
    return ($accepted -eq $Count)
}

function Invoke-BoundedProcess {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Entry,
        [scriptblock] $TerminationHook
    )

    $argv = @($Entry.argv)
    $info = [System.Diagnostics.ProcessStartInfo]::new()
    $info.FileName = [string]$argv[0]
    for ($index = 1; $index -lt $argv.Count; $index++) {
        [void]$info.ArgumentList.Add([string]$argv[$index])
    }
    $info.WorkingDirectory = $script:RepositoryRoot
    $info.UseShellExecute = $false
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $info
    try {
        if (-not $process.Start()) {
            $process.Dispose()
            return [pscustomobject]@{
                Started = $false; TimedOut = $false; OutputLimitExceeded = $false
                KillFailed = $false; DrainIncomplete = $false; ReadFailed = $false
                ExitCode = $null; Output = ''
            }
        }
    }
    catch {
        $process.Dispose()
        return [pscustomobject]@{
            Started = $false; TimedOut = $false; OutputLimitExceeded = $false
            KillFailed = $false; DrainIncomplete = $false; ReadFailed = $false
            ExitCode = $null; Output = ''
        }
    }

    $stdoutStream = $process.StandardOutput.BaseStream
    $stderrStream = $process.StandardError.BaseStream
    $stdoutBytes = [System.IO.MemoryStream]::new()
    $stderrBytes = [System.IO.MemoryStream]::new()
    $stdoutBuffer = [byte[]]::new($script:OutputReadChunkBytes)
    $stderrBuffer = [byte[]]::new($script:OutputReadChunkBytes)
    $stdoutTask = $stdoutStream.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length)
    $stderrTask = $stderrStream.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
    $stdoutEof = $false
    $stderrEof = $false
    $combinedCount = 0
    $timedOut = $false
    $outputLimitExceeded = $false
    $killFailed = $false
    $drainIncomplete = $false
    $readFailed = $false
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $postExitStartedAt = -1L
    $processExited = $false

    while ($true) {
        $madeProgress = $false
        if (-not $stdoutEof -and $null -ne $stdoutTask -and $stdoutTask.IsCompleted) {
            try { $read = $stdoutTask.GetAwaiter().GetResult() } catch { $read = 0; $readFailed = $true }
            $stdoutTask = $null
            if ($read -le 0) {
                $stdoutEof = $true
            }
            else {
                if (-not (Add-BoundedOutputChunk -Destination $stdoutBytes -Buffer $stdoutBuffer -Count $read -CombinedCount ([ref]$combinedCount))) {
                    $outputLimitExceeded = $true
                }
                if (-not $outputLimitExceeded) {
                    $stdoutTask = $stdoutStream.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length)
                }
            }
            $madeProgress = $true
        }
        if (-not $stderrEof -and $null -ne $stderrTask -and $stderrTask.IsCompleted) {
            try { $read = $stderrTask.GetAwaiter().GetResult() } catch { $read = 0; $readFailed = $true }
            $stderrTask = $null
            if ($read -le 0) {
                $stderrEof = $true
            }
            else {
                if (-not (Add-BoundedOutputChunk -Destination $stderrBytes -Buffer $stderrBuffer -Count $read -CombinedCount ([ref]$combinedCount))) {
                    $outputLimitExceeded = $true
                }
                if (-not $outputLimitExceeded) {
                    $stderrTask = $stderrStream.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
                }
            }
            $madeProgress = $true
        }

        try { $processExited = $process.HasExited } catch { $processExited = $false }
        if ($outputLimitExceeded -or $readFailed) {
            break
        }
        if (-not $processExited -and $stopwatch.ElapsedMilliseconds -ge ([int]$Entry.timeout_seconds * 1000)) {
            $timedOut = $true
            break
        }
        if ($processExited -and $stdoutEof -and $stderrEof) {
            break
        }
        if ($processExited) {
            if ($postExitStartedAt -lt 0) {
                $postExitStartedAt = $stopwatch.ElapsedMilliseconds
            }
            elseif (($stopwatch.ElapsedMilliseconds - $postExitStartedAt) -ge $script:PostExitDrainMilliseconds) {
                $drainIncomplete = $true
                break
            }
        }
        if (-not $madeProgress) {
            [System.Threading.Thread]::Sleep(5)
        }
    }

    $terminationRequired = $timedOut -or $outputLimitExceeded -or ($readFailed -and -not $processExited)
    if ($terminationRequired) {
        try {
            if ($null -ne $TerminationHook) {
                & $TerminationHook $process
            }
            else {
                $process.Kill($true)
            }
        }
        catch {
            $killFailed = $true
        }
        try {
            if (-not $process.WaitForExit(500)) {
                $killFailed = $true
            }
        }
        catch {
            $killFailed = $true
        }

        $drainDeadline = $stopwatch.ElapsedMilliseconds + $script:PostKillDrainMilliseconds
        while (($stopwatch.ElapsedMilliseconds -lt $drainDeadline) -and (-not $stdoutEof -or -not $stderrEof)) {
            $madeProgress = $false
            if (-not $stdoutEof) {
                if ($null -eq $stdoutTask) {
                    try { $stdoutTask = $stdoutStream.ReadAsync($stdoutBuffer, 0, $stdoutBuffer.Length) } catch { $stdoutEof = $true }
                }
                elseif ($stdoutTask.IsCompleted) {
                    try { $read = $stdoutTask.GetAwaiter().GetResult() } catch { $read = 0; $readFailed = $true }
                    $stdoutTask = $null
                    if ($read -le 0) { $stdoutEof = $true }
                    $madeProgress = $true
                }
            }
            if (-not $stderrEof) {
                if ($null -eq $stderrTask) {
                    try { $stderrTask = $stderrStream.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length) } catch { $stderrEof = $true }
                }
                elseif ($stderrTask.IsCompleted) {
                    try { $read = $stderrTask.GetAwaiter().GetResult() } catch { $read = 0; $readFailed = $true }
                    $stderrTask = $null
                    if ($read -le 0) { $stderrEof = $true }
                    $madeProgress = $true
                }
            }
            if (-not $madeProgress) {
                [System.Threading.Thread]::Sleep(5)
            }
        }
        if (-not $stdoutEof -or -not $stderrEof) {
            $drainIncomplete = $true
        }
    }

    $exitCode = $null
    try {
        if ($process.HasExited) { $exitCode = $process.ExitCode }
    }
    catch { }
    $stdout = [System.Text.Encoding]::UTF8.GetString($stdoutBytes.ToArray())
    $stderr = [System.Text.Encoding]::UTF8.GetString($stderrBytes.ToArray())
    $combined = ($stdout + "`n" + $stderr).Replace($script:RepositoryRoot, '<repository>')

    try { $stdoutStream.Dispose() } catch { }
    try { $stderrStream.Dispose() } catch { }
    $stdoutBytes.Dispose()
    $stderrBytes.Dispose()
    $process.Dispose()
    $stopwatch.Stop()
    return [pscustomobject]@{
        Started = $true
        TimedOut = $timedOut
        OutputLimitExceeded = $outputLimitExceeded
        KillFailed = $killFailed
        DrainIncomplete = $drainIncomplete
        ReadFailed = $readFailed
        ExitCode = $exitCode
        Output = $combined
    }
}

function Assert-CollectedOnce {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Entry,
        [Parameter(Mandatory)] [string] $Output
    )
    $id = [string]$Entry.id
    $testId = [string]@($Entry.test_ids)[0]
    if (-not $Output.Contains($testId)) {
        throw "Expected-red entry did not collect its named test: $id."
    }
    if ($Output -notmatch '(?m)^Ran 1 test(?:s)? in ') {
        throw "Expected-red entry did not run exactly one test: $id."
    }
    if ($Output -match '(?i)Ran 0 tests|skipped\s*=|expected failures?\s*=|unexpected successes?\s*=') {
        throw "Expected-red entry skipped or failed to collect its named test: $id."
    }
}

function Assert-NoToolOrCrashFailure {
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary] $Entry,
        [Parameter(Mandatory)] [string] $Output
    )
    if ($Output -match '(?m)^ERROR:|ModuleNotFoundError|ImportError|SyntaxError|No module named|can''t open file|not recognized as|command not found') {
        throw "Expected-red entry failed for tooling, import, syntax, or crash rather than behavior: $($Entry.id)."
    }
}

function Invoke-ExpectedRedEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary[]] $Entries,
        [scriptblock] $TerminationHook
    )

    $count = 0
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $Entries) {
        try {
            $result = Invoke-BoundedProcess -Entry $entry -TerminationHook $TerminationHook
            if (-not $result.Started) {
                throw "Expected-red entry executable could not start: $($entry.id)."
            }
            if ($result.TimedOut) {
                throw "Expected-red entry timed out: $($entry.id)."
            }
            if ($result.OutputLimitExceeded) {
                throw "Expected-red entry exceeded the bounded output limit: $($entry.id)."
            }
            if ($result.KillFailed) {
                throw "Expected-red entry could not be terminated safely: $($entry.id)."
            }
            if ($result.DrainIncomplete) {
                throw "Expected-red entry output did not close within the bounded drain: $($entry.id)."
            }
            if ($result.ReadFailed) {
                throw "Expected-red entry output could not be read safely: $($entry.id)."
            }
            if ($result.ExitCode -eq 0) {
                throw "Expected-red entry unexpectedly passed: $($entry.id)."
            }
            Assert-CollectedOnce -Entry $entry -Output $result.Output
            Assert-NoToolOrCrashFailure -Entry $entry -Output $result.Output
            $marker = [string]$entry.expected_missing_behavior_marker
            $assertions = [regex]::Matches($result.Output, '(?m)^AssertionError: ([^\r\n]+)\r?$')
            if ($assertions.Count -ne 1 -or $assertions[0].Groups[1].Value -cne $marker) {
                throw "Expected-red entry failed for the wrong assertion: $($entry.id)."
            }
            if ($result.Output -notmatch '(?m)^FAILED \(failures=1\)\s*$') {
                throw "Expected-red entry did not produce one canonical assertion failure: $($entry.id)."
            }
            $markerCount = [regex]::Matches($result.Output, [regex]::Escape($marker)).Count
            if ($markerCount -ne 1) {
                throw "Expected-red marker was absent, duplicated, or spoofed: $($entry.id)."
            }
            $count++
        }
        catch {
            $failures.Add([string]$entry.id) | Out-Null
        }
    }
    if ($failures.Count -gt 0) {
        throw ("Expected-red entries failed validation: " + ($failures -join ', ') + '.')
    }
    return $count
}

function Invoke-ExpectedGreenEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [System.Collections.IDictionary[]] $Entries,
        [Parameter(Mandatory)] [string] $Owner,
        [scriptblock] $TerminationHook
    )

    if ($Owner -notmatch '^TL-R0-[0-9]{3}$') {
        throw 'Green owner must be one canonical task ID.'
    }
    $selected = @($Entries | Where-Object { [string]$_.owner -ceq $Owner })
    if ($selected.Count -eq 0) {
        throw "Green owner has no expected-red entries: $Owner."
    }
    $count = 0
    $failures = [System.Collections.Generic.List[string]]::new()
    foreach ($entry in $selected) {
        try {
            $result = Invoke-BoundedProcess -Entry $entry -TerminationHook $TerminationHook
            if (-not $result.Started) {
                throw "Expected-green entry executable could not start: $($entry.id)."
            }
            if ($result.TimedOut) {
                throw "Expected-green entry timed out: $($entry.id)."
            }
            if ($result.OutputLimitExceeded) {
                throw "Expected-green entry exceeded the bounded output limit: $($entry.id)."
            }
            if ($result.KillFailed) {
                throw "Expected-green entry could not be terminated safely: $($entry.id)."
            }
            if ($result.DrainIncomplete) {
                throw "Expected-green entry output did not close within the bounded drain: $($entry.id)."
            }
            if ($result.ReadFailed) {
                throw "Expected-green entry output could not be read safely: $($entry.id)."
            }
            Assert-CollectedOnce -Entry $entry -Output $result.Output
            Assert-NoToolOrCrashFailure -Entry $entry -Output $result.Output
            if ($result.ExitCode -ne 0) {
                throw "Expected-green entry did not pass: $($entry.id)."
            }
            if ($result.Output -match 'THRIVELENS_MISSING_IMPLEMENTATION::|(?m)^FAIL:|(?m)^FAILED |(?m)^ERROR:') {
                throw "Expected-green entry retained red or error output: $($entry.id)."
            }
            if ($result.Output -notmatch '(?m)^OK\s*$') {
                throw "Expected-green entry did not produce a canonical passing result: $($entry.id)."
            }
            $count++
        }
        catch {
            $failures.Add([string]$entry.id) | Out-Null
        }
    }
    if ($failures.Count -gt 0 -or $count -ne $selected.Count) {
        throw ("Expected-green owner had failing entries: " + ($failures -join ', ') + '.')
    }
    return $count
}

Export-ModuleMember -Function Read-ExpectedRedManifest, Invoke-ExpectedRedEntries, Invoke-ExpectedGreenEntries
