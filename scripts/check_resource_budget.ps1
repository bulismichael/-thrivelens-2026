[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$failureCode = 'RESOURCE_POLICY_INITIALIZATION_FAILED'
$expectedRootPurpose = 'Attributable SDKs, bounded caches, task worktrees, portable PostgreSQL data, and generated build evidence outside the synced path'

function Test-JsonInteger {
    param([object]$Value)
    return $Value -is [sbyte] -or $Value -is [byte] -or $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or $Value -is [int64] -or $Value -is [uint64]
}

try {
    $projectRoot = (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
    $configPath = Join-Path $projectRoot 'config\resource-budget.json'
    $modulePath = Join-Path $PSScriptRoot 'lib\ResourceBudget.psm1'
    $failureCode = 'RESOURCE_POLICY_MODULE_INVALID'
    if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) { throw 'module unavailable' }
    Import-Module -Name $modulePath -Force -ErrorAction Stop

    $failureCode = 'RESOURCE_POLICY_CONFIG_INVALID'
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) { throw 'configuration unavailable' }
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    $expectedTopLevel = @('schema_version', 'phase', 'cap_gb', 'warning_percent', 'hard_stop_percent', 'additional_roots', 'rules')
    $actualTopLevel = @($config.PSObject.Properties.Name)
    if ($actualTopLevel.Count -ne $expectedTopLevel.Count -or (Compare-Object $actualTopLevel $expectedTopLevel)) { throw 'configuration fields drifted' }
    if (-not (Test-JsonInteger $config.schema_version) -or $config.schema_version -ne 1) { throw 'unsupported configuration schema' }
    $allowedPhases = @('prebootstrap', 'bootstrap_active', 'implementation', 'release')
    if ($config.phase -isnot [string] -or $allowedPhases -notcontains [string]$config.phase) { throw 'invalid resource phase' }
    if (-not (Test-JsonInteger $config.cap_gb) -or -not (Test-JsonInteger $config.warning_percent) -or -not (Test-JsonInteger $config.hard_stop_percent)) {
        throw 'Configured resource numbers must use exact JSON integers.'
    }
    $capGB = [double]$config.cap_gb
    $warningPercent = [double]$config.warning_percent
    $hardStopPercent = [double]$config.hard_stop_percent
    if ($config.cap_gb -ne 18) { throw 'Configured delivery cap must remain exactly 18 GB.' }
    if ($warningPercent -ne 75 -or $hardStopPercent -ne 85) { throw 'Configured resource thresholds must remain exactly 75/85 percent.' }
    if ($config.additional_roots -isnot [System.Array]) { throw 'configured roots must be a JSON array' }
    $configuredRoots = @($config.additional_roots)
    if ($configuredRoots.Count -ne 1) { throw 'unexpected configured root count' }
    $configuredRoot = $configuredRoots[0]
    $expectedRootFields = @('label', 'path', 'purpose', 'required_in_phases')
    $actualRootFields = @($configuredRoot.PSObject.Properties.Name)
    if ($actualRootFields.Count -ne $expectedRootFields.Count -or (Compare-Object $actualRootFields $expectedRootFields)) { throw 'configured root fields drifted' }
    if ($configuredRoot.label -isnot [string] -or $configuredRoot.path -isnot [string] -or $configuredRoot.purpose -isnot [string] -or
        [string]$configuredRoot.label -cne 'local_attributable' -or [string]$configuredRoot.path -cne '%LOCALAPPDATA%\ThriveLens' -or
        [string]$configuredRoot.purpose -cne $expectedRootPurpose) {
        throw 'configured root is outside the R0 allowlist'
    }
    if ($configuredRoot.required_in_phases -isnot [System.Array]) { throw 'configured root phases must be a JSON array' }
    $expectedRequiredPhases = @('bootstrap_active', 'implementation', 'release')
    $actualRequiredPhases = @($configuredRoot.required_in_phases)
    if ($actualRequiredPhases.Count -ne $expectedRequiredPhases.Count -or (Compare-Object -SyncWindow 0 $actualRequiredPhases $expectedRequiredPhases)) {
        throw 'configured root phase policy drifted'
    }
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) { throw 'local application data root is unavailable' }
    $expectedRuleFields = @('absolute_cap_semantics', 'high_watermark_semantics', 'model_downloads_in_bootstrap', 'local_builds_are_sequential')
    $actualRuleFields = @($config.rules.PSObject.Properties.Name)
    if ($actualRuleFields.Count -ne $expectedRuleFields.Count -or (Compare-Object $actualRuleFields $expectedRuleFields)) { throw 'resource rule fields drifted' }
    if ($config.rules.absolute_cap_semantics -isnot [string] -or $config.rules.high_watermark_semantics -isnot [string] -or
        $config.rules.model_downloads_in_bootstrap -isnot [bool] -or $config.rules.local_builds_are_sequential -isnot [bool] -or
        [string]$config.rules.absolute_cap_semantics -cne 'fail when accounted bytes are greater than or equal to 18 GB' -or
        [string]$config.rules.high_watermark_semantics -cne 'all installs and builds stop at or above 85 percent until a reviewed configuration decision changes the budget' -or
        $config.rules.model_downloads_in_bootstrap -ne $false -or
        $config.rules.local_builds_are_sequential -ne $true) {
        throw 'resource rule values drifted'
    }

    $rootSpec = [Collections.Generic.List[object]]::new()
    $rootSpec.Add([pscustomobject]@{ Label = 'repository'; Path = $projectRoot; Required = $true })
    foreach ($entry in $configuredRoots) {
        $expandedPath = [Environment]::ExpandEnvironmentVariables([string]$entry.path)
        $requiredPhases = @($entry.required_in_phases)
        $rootSpec.Add([pscustomobject]@{
            Label = [string]$entry.label
            Path = $expandedPath
            Required = [bool]($requiredPhases -contains [string]$config.phase)
        })
    }

    $failureCode = 'RESOURCE_POLICY_MEASUREMENT_FAILED'
    $result = Measure-ThriveLensResourceBudget `
        -RootSpec $rootSpec `
        -CapGB $capGB `
        -WarningPercent $warningPercent `
        -HardStopPercent $hardStopPercent

    $freeMemoryGB = $null
    if ($IsWindows) {
        try {
            $os = Get-CimInstance Win32_OperatingSystem
            $freeMemoryGB = [math]::Round($os.FreePhysicalMemory / 1MB, 2)
        }
        catch { $freeMemoryGB = $null }
    }
    elseif (Test-Path -LiteralPath '/proc/meminfo') {
        $availableLine = Select-String -LiteralPath '/proc/meminfo' -Pattern '^MemAvailable:\s+(\d+)\s+kB$'
        if ($availableLine) { $freeMemoryGB = [math]::Round([double]$availableLine.Matches[0].Groups[1].Value / 1MB, 2) }
    }
    $result | Add-Member -NotePropertyName phase -NotePropertyValue ([string]$config.phase)
    $result | Add-Member -NotePropertyName host_free_memory_gb -NotePropertyValue $freeMemoryGB
    $result | ConvertTo-Json -Depth 6

    if ($result.status -eq 'CAP_EXCEEDED') {
        [Console]::Error.WriteLine('ThriveLens attributable footprint must remain strictly below the configured 18 GB cap.')
        exit 1
    }
    if ($result.status -eq 'HARD_STOP') {
        [Console]::Error.WriteLine('ThriveLens attributable footprint reached the configured high-water stop. Clean up before another install or build.')
        exit 2
    }
    if ($null -ne $freeMemoryGB -and $freeMemoryGB -lt 1) {
        Write-Warning "Host free memory is $freeMemoryGB GB. Keep work sequential and stop unused applications before installation, emulator, or release-build work."
    }
}
catch {
    [Console]::Error.WriteLine("Resource policy failed closed. code=$failureCode")
    exit 3
}
