[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'lib\ResourceBudget.psm1'
$policyScript = Join-Path $PSScriptRoot 'check_resource_budget.ps1'
$realConfigPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'config\resource-budget.json'
Import-Module -Name $modulePath -Force

$tempBase = [IO.Path]::GetTempPath().TrimEnd([IO.Path]::DirectorySeparatorChar)
$tempRoot = Join-Path $tempBase ("thrivelens-budget-test-{0}-{1}" -f $PID, [guid]::NewGuid().ToString('N'))
$additionalRoot = "$tempRoot-additional"
$thresholdRoot = "$tempRoot-thresholds"
$policyFixtureRoot = "$tempRoot-policy-fixture"
$childRoot = Join-Path $tempRoot 'child'
$junctionPath = Join-Path $tempRoot 'junction-escape'
$oneMBInGB = 1MB / 1GB

function Set-TestFileLength {
    param([string]$Path, [long]$Length)
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.SetLength($Length) } finally { $stream.Dispose() }
}

function Measure-TestBudget {
    param([object[]]$Roots, [double]$Warning = 75, [double]$HardStop = 85)
    return Measure-ThriveLensResourceBudget -RootSpec $Roots -CapGB $oneMBInGB -WarningPercent $Warning -HardStopPercent $HardStop
}

function Expect-Throw {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action; throw 'Expected operation to fail.' }
    catch {
        if ($_.Exception.Message -eq 'Expected operation to fail.' -or $_.Exception.Message -notmatch $Pattern) { throw }
    }
}

function Assert-SanitizedOutput {
    param([string]$Output)
    $sensitiveValues = @(
        $env:USERPROFILE,
        $env:LOCALAPPDATA,
        $tempBase,
        $tempRoot,
        (Resolve-Path -LiteralPath (Split-Path -Parent $PSScriptRoot)).Path
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($value in $sensitiveValues) {
        if ($Output -match [regex]::Escape($value)) { throw 'Resource output disclosed a sensitive absolute root.' }
    }
}

function Invoke-IsolatedPolicyFailure {
    param([string]$ExpectedCode)
    $fixturePolicy = Join-Path $policyFixtureRoot 'scripts\check_resource_budget.ps1'
    $output = & pwsh -NoProfile -File $fixturePolicy 2>&1 | Out-String
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 3 -or $output -notmatch [regex]::Escape($ExpectedCode)) {
        throw "Isolated resource policy did not fail with $ExpectedCode."
    }
    Assert-SanitizedOutput -Output $output
}

New-Item -ItemType Directory -Path $tempRoot,$additionalRoot,$childRoot,$thresholdRoot | Out-Null

try {
    Set-TestFileLength -Path (Join-Path $tempRoot 'under.bin') -Length 512KB
    $rootOnly = @([pscustomobject]@{ Label = 'fixture'; Path = $tempRoot; Required = $true })
    $under = Measure-TestBudget -Roots $rootOnly
    if ($under.status -ne 'OK') { throw 'Under-cap case failed.' }
    if ($IsWindows -and ([string]::IsNullOrWhiteSpace($under.roots[0].volume) -or $null -eq $under.roots[0].free_disk_gb)) {
        throw 'Per-root volume/free-space evidence is missing.'
    }

    $thresholdFile = Join-Path $thresholdRoot 'threshold.bin'
    $thresholdRoots = @([pscustomobject]@{ Label = 'threshold'; Path = $thresholdRoot; Required = $true })
    Set-TestFileLength -Path $thresholdFile -Length 786431
    if ((Measure-TestBudget -Roots $thresholdRoots).status -ne 'OK') { throw 'Just-below-warning boundary failed.' }
    Set-TestFileLength -Path $thresholdFile -Length 786432
    if ((Measure-TestBudget -Roots $thresholdRoots).status -ne 'WARNING') { throw 'Exact-warning boundary failed.' }
    Set-TestFileLength -Path $thresholdFile -Length 891289
    if ((Measure-TestBudget -Roots $thresholdRoots).status -ne 'WARNING') { throw 'Just-below-high-water boundary failed.' }
    Set-TestFileLength -Path $thresholdFile -Length 891290
    if ((Measure-TestBudget -Roots $thresholdRoots).status -ne 'HARD_STOP') { throw 'First-byte-above-high-water boundary failed.' }
    Set-TestFileLength -Path $thresholdFile -Length 1048576
    if ((Measure-TestBudget -Roots $thresholdRoots).status -ne 'CAP_EXCEEDED') { throw 'Exact-cap threshold fixture failed.' }

    Set-TestFileLength -Path (Join-Path $tempRoot 'to-high-water.bin') -Length 384KB
    $high = Measure-TestBudget -Roots $rootOnly
    if ($high.status -ne 'HARD_STOP') { throw 'High-water case failed.' }

    Remove-Item -LiteralPath (Join-Path $tempRoot 'to-high-water.bin') -Force
    Set-TestFileLength -Path (Join-Path $tempRoot 'to-exact-cap.bin') -Length 512KB
    $exact = Measure-TestBudget -Roots $rootOnly
    if ($exact.status -ne 'CAP_EXCEEDED') { throw 'Exact-cap case failed.' }

    Remove-Item -LiteralPath (Join-Path $tempRoot 'to-exact-cap.bin') -Force
    Set-TestFileLength -Path (Join-Path $additionalRoot 'extra.bin') -Length 256KB
    $aggregateRoots = @(
        [pscustomobject]@{ Label = 'fixture'; Path = $tempRoot; Required = $true },
        [pscustomobject]@{ Label = 'extra'; Path = $additionalRoot; Required = $true }
    )
    $aggregate = Measure-TestBudget -Roots $aggregateRoots
    if ($aggregate.accounted_bytes -ne 786432) { throw 'Additional-root aggregation failed.' }

    $parentFirst = Measure-TestBudget -Roots @(
        [pscustomobject]@{ Label = 'parent'; Path = $tempRoot; Required = $true },
        [pscustomobject]@{ Label = 'child'; Path = $childRoot; Required = $true }
    )
    $childFirst = Measure-TestBudget -Roots @(
        [pscustomobject]@{ Label = 'child'; Path = $childRoot; Required = $true },
        [pscustomobject]@{ Label = 'parent'; Path = $tempRoot; Required = $true }
    )
    if ($parentFirst.accounted_bytes -ne $childFirst.accounted_bytes -or $parentFirst.roots.Count -ne 1 -or $childFirst.roots.Count -ne 1) {
        throw 'Parent/child root deduplication is order-dependent.'
    }

    $missingPath = Join-Path $tempRoot 'missing-required'
    $inactive = Measure-TestBudget -Roots @([pscustomobject]@{ Label = 'phase-root'; Path = $missingPath; Required = $false })
    if ($inactive.missing_inactive_roots -notcontains 'phase-root') { throw 'Inactive missing-root phase behavior failed.' }
    Expect-Throw -Pattern 'Required resource root.*missing' -Action {
        Measure-TestBudget -Roots @([pscustomobject]@{ Label = 'missing'; Path = $missingPath; Required = $true })
    }
    Expect-Throw -Pattern 'must be absolute' -Action {
        Measure-TestBudget -Roots @([pscustomobject]@{ Label = 'relative'; Path = '.\relative'; Required = $true })
    }
    Expect-Throw -Pattern 'unresolved environment' -Action {
        Measure-TestBudget -Roots @([pscustomobject]@{ Label = 'unresolved'; Path = '%THRIVELENS_MISSING_VAR%\data'; Required = $false })
    }
    Expect-Throw -Pattern 'WarningPercent must be lower' -Action {
        Measure-TestBudget -Roots $rootOnly -Warning 90 -HardStop 80
    }

    New-Item -ItemType Junction -Path $junctionPath -Target $additionalRoot | Out-Null
    Expect-Throw -Pattern 'symbolic link or junction' -Action { Measure-TestBudget -Roots $rootOnly }
    Remove-Item -LiteralPath $junctionPath -Force

    $policyOutput = & pwsh -NoProfile -File $policyScript 2>&1 | Out-String
    if ($LASTEXITCODE -ne 0) {
        throw 'Default policy failed or disclosed an absolute user-profile path.'
    }
    Assert-SanitizedOutput -Output $policyOutput
    $bypassOutput = & pwsh -NoProfile -File $policyScript -CapGB 1024 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { throw 'Policy accepted a cap override.' }
    Assert-SanitizedOutput -Output $bypassOutput
    $rootBypassOutput = & pwsh -NoProfile -File $policyScript -Root $tempRoot 2>&1 | Out-String
    if ($LASTEXITCODE -eq 0) { throw 'Policy accepted a root override.' }
    Assert-SanitizedOutput -Output $rootBypassOutput

    $fixtureScripts = Join-Path $policyFixtureRoot 'scripts'
    $fixtureLib = Join-Path $fixtureScripts 'lib'
    $fixtureConfig = Join-Path $policyFixtureRoot 'config'
    New-Item -ItemType Directory -Path $fixtureLib,$fixtureConfig | Out-Null
    Copy-Item -LiteralPath $policyScript -Destination (Join-Path $fixtureScripts 'check_resource_budget.ps1')
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_MODULE_INVALID'
    Copy-Item -LiteralPath $modulePath -Destination (Join-Path $fixtureLib 'ResourceBudget.psm1')
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), '{ malformed', [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $validConfig.phase = 'invalid-phase'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig.phase = 'prebootstrap'
    $validConfig.additional_roots[0].path = (Join-Path $policyFixtureRoot 'outside-allowlist')
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig.additional_roots[0].path = '%LOCALAPPDATA%\ThriveLens'
    $validConfig.hard_stop_percent = 99
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig.hard_stop_percent = 85
    $validConfig | Add-Member -NotePropertyName unapproved_top_level -NotePropertyValue $true
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig.PSObject.Properties.Remove('unapproved_top_level')
    $validConfig.rules | Add-Member -NotePropertyName unapproved_rule -NotePropertyValue 'unsafe'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig.rules.PSObject.Properties.Remove('unapproved_rule')
    $validConfig.rules.model_downloads_in_bootstrap = $true
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $validConfig.additional_roots[0].purpose = 'changed purpose'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $secondRoot = $validConfig.additional_roots[0] | ConvertTo-Json -Depth 6 | ConvertFrom-Json
    $secondRoot.label = 'second'
    $validConfig.additional_roots = @($validConfig.additional_roots[0], $secondRoot)
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $validConfig.cap_gb = [double]18
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $validConfig.warning_percent = $true
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_CONFIG_INVALID'
    $validConfig = Get-Content -LiteralPath $realConfigPath -Raw | ConvertFrom-Json
    $validConfig.phase = 'implementation'
    [IO.File]::WriteAllText((Join-Path $fixtureConfig 'resource-budget.json'), ($validConfig | ConvertTo-Json -Depth 6), [Text.UTF8Encoding]::new($false))
    $previousLocalAppData = $env:LOCALAPPDATA
    try {
        $env:LOCALAPPDATA = Join-Path $policyFixtureRoot 'missing-sensitive-root'
        Invoke-IsolatedPolicyFailure -ExpectedCode 'RESOURCE_POLICY_MEASUREMENT_FAILED'
    }
    finally {
        $env:LOCALAPPDATA = $previousLocalAppData
    }

    Write-Output 'PASS strict adjacent warning/high/exact cap boundaries'
    Write-Output 'PASS additional-root and order-independent nested-root accounting'
    Write-Output 'PASS inactive/required phase, relative, unresolved, threshold, and per-volume behavior'
    Write-Output 'PASS junction fail-closed behavior'
    Write-Output 'PASS non-overridable sanitized success and failure policy'
}
finally {
    if (Test-Path -LiteralPath $junctionPath) { Remove-Item -LiteralPath $junctionPath -Force }
    foreach ($target in @($tempRoot, $additionalRoot, $thresholdRoot, $policyFixtureRoot)) {
        if (Test-Path -LiteralPath $target) {
            $resolved = (Resolve-Path -LiteralPath $target).Path
            if (-not $resolved.StartsWith($tempBase + [IO.Path]::DirectorySeparatorChar + 'thrivelens-budget-test-', [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to remove unexpected test path '$resolved'."
            }
            Remove-Item -LiteralPath $resolved -Recurse -Force
        }
    }
}
