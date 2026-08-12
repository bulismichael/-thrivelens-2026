#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$failures = [Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    $script:assertionCount++
    if (-not $Condition) { $failures.Add($Code) }
}

function Test-ThriveLensRuntimeResourceRunnerDisposalContract {
    param([Parameter(Mandatory)][string]$Source)
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) { return $false }
    $functions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-ThriveLensResourceGate'
    }, $true))
    if ($functions.Count -ne 1) { return $false }
    $body = $functions[0].Extent.Text
    return (
        $body -match 'if\s*\(\$stdoutReaderComplete\)\s*\{\s*\$stdoutSink\.Dispose\(\)\s*\}' -and
        $body -match 'if\s*\(\$stderrReaderComplete\)\s*\{\s*\$stderrSink\.Dispose\(\)\s*\}' -and
        $body -match '\$rootInactive\s*=\s*-not\s+\$started' -and
        $body -match 'if\s*\(\$started\)\s*\{[\s\S]+?\$rootInactive\s*=\s*\$process\.HasExited' -and
        $body -match 'if\s*\(\$rootInactive\s*-and\s*\$stdoutReaderComplete\s*-and\s*\$stderrReaderComplete\)\s*\{\s*\$process\.Dispose\(\)\s*\}'
    )
}

function Test-ThriveLensRuntimeResourceRunnerArgumentContract {
    param([Parameter(Mandatory)][string]$Source)
    $tokens = $null
    $errors = $null
    $ast = [Management.Automation.Language.Parser]::ParseInput($Source, [ref]$tokens, [ref]$errors)
    if (@($errors).Count -ne 0) { return $false }
    $functions = @($ast.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-ThriveLensResourceGate'
    }, $true))
    if ($functions.Count -ne 1) { return $false }
    $body = $functions[0].Extent.Text
    return (
        ([regex]::Matches($body, '\$startInfo\.ArgumentList\.Add\(')).Count -eq 6 -and
        $body -match "ArgumentList\.Add\('-NoProfile'\)[\s\S]+ArgumentList\.Add\('-NonInteractive'\)[\s\S]+ArgumentList\.Add\('-File'\)[\s\S]+ArgumentList\.Add\(\`$scriptPath\)[\s\S]+ArgumentList\.Add\('-WarningAction'\)[\s\S]+ArgumentList\.Add\('SilentlyContinue'\)" -and
        $body -notmatch "ArgumentList\.Add\('-Command'\)"
    )
}

function Replace-ThriveLensStaticSourceOnce {
    param([string]$Source, [string]$Old, [string]$New)
    $offset = $Source.IndexOf($Old, [StringComparison]::Ordinal)
    if ($offset -lt 0 -or $Source.IndexOf($Old, $offset + $Old.Length, [StringComparison]::Ordinal) -ge 0) {
        throw 'STATIC_MUTATION_TARGET_NOT_UNIQUE'
    }
    return $Source.Substring(0, $offset) + $New + $Source.Substring($offset + $Old.Length)
}

function Invoke-ComposeValidatorProbe {
    param(
        [Parameter(Mandatory)][hashtable]$EnvironmentValues,
        [string[]]$AdditionalArguments = @()
    )
    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = Join-Path $PSHOME 'pwsh.exe'
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.CreateNoWindow = $true
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add((Join-Path $PSScriptRoot 'validate_compose_inputs.ps1'))
    foreach ($argument in $AdditionalArguments) { $startInfo.ArgumentList.Add($argument) }
    foreach ($name in $EnvironmentValues.Keys) {
        $startInfo.Environment[[string]$name] = [string]$EnvironmentValues[$name]
    }
    $process = [Diagnostics.Process]::Start($startInfo)
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    return [pscustomobject]@{
        ExitCode = $process.ExitCode
        StandardOutput = $standardOutput.Trim()
        StandardError = $standardError.Trim()
    }
}

try {
    $scriptRoots = @(
        (Join-Path $projectRoot 'scripts\bootstrap\backend'),
        (Join-Path $projectRoot 'scripts\dev\postgres')
    )
    $scripts = @(foreach ($root in $scriptRoots) { Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') } })
    Assert-Condition ($scripts.Count -ge 12) 'SCRIPT_INVENTORY'
    foreach ($script in $scripts) {
        $tokens = $null
        $errors = $null
        $null = [Management.Automation.Language.Parser]::ParseFile($script.FullName, [ref]$tokens, [ref]$errors)
        Assert-Condition (@($errors).Count -eq 0) ('POWERSHELL_PARSE_' + $script.Name)
        $content = Get-Content -LiteralPath $script.FullName -Raw
        if ($script.Name -cne 'test_static.ps1') {
            Assert-Condition ($content -notmatch '(?i)\b(New-Service|Start-Service|Register-Service|sudo|docker\.exe)\b') ('GLOBAL_MUTATION_' + $script.Name)
            Assert-Condition ($content -notmatch '(?i)\b(Invoke-WebRequest|Invoke-RestMethod|Start-BitsTransfer|curl(?:\.exe)?|wget(?:\.exe)?)\b') ('NETWORK_DOWNLOAD_' + $script.Name)
            Assert-Condition ($content -notmatch '0\.0\.0\.0') ('WILDCARD_BIND_' + $script.Name)
        }
    }

    $start = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'start.ps1') -Raw
    $stop = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'stop.ps1') -Raw
    $initialize = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'initialize.ps1') -Raw
    $preflight = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'preflight.ps1') -Raw
    $runtimeTest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test_runtime.ps1') -Raw
    $runtimeModule = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'Runtime.psm1') -Raw
    $wslModule = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'WslRuntime.psm1') -Raw
    $securityTest = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'test_security_controls.ps1') -Raw
    $composeValidator = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'validate_compose_inputs.ps1') -Raw
    $postgresInstaller = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\bootstrap\backend\install_postgres.ps1') -Raw
    $pythonInstaller = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\bootstrap\backend\install_python.ps1') -Raw
    $startTokens = $null
    $startParseErrors = $null
    $startAst = [Management.Automation.Language.Parser]::ParseInput(
        $start,
        [ref]$startTokens,
        [ref]$startParseErrors
    )
    $runtimeTokens = $null
    $runtimeParseErrors = $null
    $runtimeAst = [Management.Automation.Language.Parser]::ParseInput(
        $runtimeTest,
        [ref]$runtimeTokens,
        [ref]$runtimeParseErrors
    )
    $wslTokens = $null
    $wslParseErrors = $null
    $wslAst = [Management.Automation.Language.Parser]::ParseInput(
        $wslModule,
        [ref]$wslTokens,
        [ref]$wslParseErrors
    )
    $runtimeModuleTokens = $null
    $runtimeModuleParseErrors = $null
    $runtimeModuleAst = [Management.Automation.Language.Parser]::ParseInput(
        $runtimeModule,
        [ref]$runtimeModuleTokens,
        [ref]$runtimeModuleParseErrors
    )
    $startCoreCalls = @($startAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -ceq 'Invoke-ThriveLensPostgresStartUnderLock'
    }, $true))
    $runtimeCoreCalls = @($runtimeAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -ceq 'Invoke-ThriveLensPostgresStartUnderLock'
    }, $true))
    $coreFunctions = @($wslAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-ThriveLensPostgresStartUnderLock'
    }, $true))
    $coreBody = if ($coreFunctions.Count -eq 1) { $coreFunctions[0].Extent.Text } else { '' }
    $resourceGateFunctions = @($runtimeModuleAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Invoke-ThriveLensResourceGate'
    }, $true))
    $resourceGateBody = if ($resourceGateFunctions.Count -eq 1) { $resourceGateFunctions[0].Extent.Text } else { '' }
    $resourceResultFunctions = @($runtimeModuleAst.FindAll({
        param($node)
        $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -ceq 'Read-ThriveLensResourceGateResult'
    }, $true))
    $resourceResultBody = if ($resourceResultFunctions.Count -eq 1) { $resourceResultFunctions[0].Extent.Text } else { '' }

    Assert-Condition (@($startParseErrors).Count -eq 0 -and $startCoreCalls.Count -eq 1) 'START_ONE_IN_PROCESS_CORE_CALL'
    Assert-Condition (@($runtimeParseErrors).Count -eq 0 -and $runtimeCoreCalls.Count -eq 1) 'TEST_ONE_LEXICAL_CORE_CALL'
    Assert-Condition (@($wslParseErrors).Count -eq 0 -and $coreFunctions.Count -eq 1) 'SHARED_START_CORE_PRESENT'
    Assert-Condition ($coreBody -match "-h 127\.0\.0\.1" -and $coreBody -match "'-w'.*'-t'.*'30'") 'CORE_LOOPBACK_BOUNDED_WAIT'
    $oldChildSymbols = 'Resolve-ThriveLens(?:ChildOutcome|StartChildExit|PreTokenStartObservation|StartChildFailure|StartChildFailureOutcome|RuntimeFailureOutcome)'
    Assert-Condition ($start -notmatch '(?i)pwsh(?:\.exe)?\s+.*(?:preflight|start)\.ps1|Start-Process' -and $start -notmatch $oldChildSymbols) 'START_NO_NESTED_RUNNER_OR_CHILD_POLICY'
    Assert-Condition ($runtimeTest -notmatch '(?i)pwsh(?:\.exe)?\s+.*(?:preflight|start|stop)\.ps1|Start-Process' -and $runtimeTest -notmatch $oldChildSymbols) 'TEST_NO_NESTED_RUNNER_OR_CHILD_POLICY'
    Assert-Condition ($wslModule -notmatch $oldChildSymbols -and $runtimeModule -notmatch $oldChildSymbols) 'NO_OLD_CHILD_POLICY_SYMBOLS'
    Assert-Condition ($start -match 'POSTGRES_START_CLEANUP_FAILED') 'START_FAILURE_CLEANUP'
    Assert-Condition ($start -match 'POSTGRES_START_CLEANUP_FAILED') 'START_CLEANUP_FAILURE_CODE'
    Assert-Condition ($wslModule -match "'-m'.*'fast'.*'-w'.*'-t'.*'30'") 'STOP_BOUNDED_FAST'
    Assert-Condition ($wslModule -match 'Assert-ThriveLensWslAbsent') 'STOP_ABSENCE_BEFORE_CLAIM'
    Assert-Condition ($wslModule -match 'POSTGRES_LISTENER_STILL_PRESENT') 'STOP_LISTENER_MEASUREMENT_FAIL_CLOSED'
    Assert-Condition ($initialize -match '--auth-host=scram-sha-256') 'INIT_HOST_SCRAM'
    Assert-Condition ($initialize -match '--auth-local=scram-sha-256') 'INIT_LOCAL_SCRAM'
    Assert-Condition ($initialize -match '--pwfile') 'INIT_PASSWORD_FILE'
    Assert-Condition ($initialize -match 'Read-ThriveLensPostgresBootstrapSecret') 'INIT_PASSWORD_ACL_EXCLUSIVE_READ'
    Assert-Condition ($initialize -match '--data-checksums') 'INIT_CHECKSUMS'
    Assert-Condition ($initialize -match 'Assert-ThriveLensDataInventoryGate') 'INIT_DATA_INVENTORY'
    Assert-Condition ($initialize -match 'maximum_initial_cluster_bytes') 'INIT_POST_SIZE_CEILING'
    Assert-Condition ($initialize -match 'Invoke-ThriveLensResourceGate') 'INIT_POST_RESOURCE_GATE'
    Assert-Condition ($preflight -match 'LOW_FREE_MEMORY') 'LOW_MEMORY_FAIL_CLOSED'
    Assert-Condition ($preflight -match 'RESOURCE_PHASE_NOT_ACTIVE') 'PHASE_FAIL_CLOSED'
    Assert-Condition ($preflight -match 'ProjectedAdditionalBytes') 'PROJECTED_RESOURCE_GATE'
    Assert-Condition ($preflight -match 'Assert-ThriveLensWslIdentity') 'WSL_IDENTITY_GATE'
    Assert-Condition ($preflight -match 'PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE') 'PYTHON_INSTALL_BLOCKER'
    Assert-Condition ($preflight -match 'PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE') 'PYTHON_PROJECTION_BLOCKER'
    Assert-Condition ($wslModule -match 'WSL_POSTGRES_VERSION_MISMATCH') 'RUNTIME_EXACT_VERSIONS'
    Assert-Condition ($runtimeTest -match 'Stop-ThriveLensPostgresUnderLock[\s\S]+Stop-ThriveLensDistroAndVerify[\s\S]+Assert-ThriveLensDistroStopped[\s\S]+Assert-ThriveLensHostPortAbsent[\s\S]+\$completedCycles\+\+[\s\S]+status\s*=\s*''PASS''') 'TEST_SAME_TOKEN_STOP_BEFORE_COMPLETED_PASS'
    Assert-Condition ($runtimeTest -match '\$completedCycles\s*-ne\s*2' -and $runtimeTest -match 'real_postgresql\s*=\s*\(\$completedCycles\s*-eq\s*2\)' -and $runtimeTest -match 'cycles\s*=\s*\$completedCycles') 'TEST_PASS_DERIVED_FROM_COMPLETED_CYCLES'
    Assert-Condition ($runtimeTest -match '\$leasedContract\s*=\s*Get-ThriveLensWslContract\s+-ConfigurationLease\s+\$configurationLease' -and
        $runtimeTest -match '\$leasedPaths\s*=\s*Get-ThriveLensWslPaths\s+-Contract\s+\$leasedContract' -and
        $runtimeTest -match '\$manifest\s*=\s*\$leasedContract\.Manifest' -and
        $runtimeTest -notmatch 'Get-ThriveLensManifest') 'TEST_USES_LEASED_POLICY_ONLY'
    Assert-Condition ($start -match 'Get-ThriveLensWslContract\s+-ConfigurationLease\s+\$configurationLease' -and
        $start -match 'Get-ThriveLensWslPaths\s+-Contract\s+\$leasedContract' -and
        $start -match 'Get-ThriveLensWslCleanupIdentityToken[\s\S]+-Contract\s+\$leasedContract') 'START_FREEZES_LEASED_CONTRACT_AND_PATHS'
    Assert-Condition ($start -match '\$absenceObservationAuthorized\s*=\s*\$null\s*-ne\s*\$leasedContract\s*-and\s*\$null\s*-ne\s*\$leasedPaths\s*-and\s*\(\$forcedTerminationAuthorized\s*-or\s*-not\s*\$cleanupRequired\)' -and
        $start -match 'if\s*\(\$absenceObservationAuthorized\)\s*\{[\s\S]+Assert-ThriveLensDistroStopped[\s\S]+Assert-ThriveLensHostPortAbsent') 'START_ABSENCE_REQUIRES_FROZEN_CONFIGURATION'
    Assert-Condition ($runtimeTest -match 'Stop-ThriveLensPostgresUnderLock\s+-IdentityToken\s+\$probeIdentityToken\s+-LifecycleLock\s+\$probeLifecycleLock\s+-Contract\s+\$leasedContract\s+-Paths\s+\$leasedPaths' -and
        $start -match 'Stop-ThriveLensPostgresUnderLock[\s\S]+-Contract\s+\$leasedContract[\s\S]+-Paths\s+\$leasedPaths') 'ADAPTER_STOP_USES_FROZEN_CONFIGURATION'
    Assert-Condition ($runtimeTest -match 'Resolve-ThriveLensRuntimeCleanupOutcome' -and $wslModule -match 'RUNTIME_CLEANUP_FAILED') 'TEST_CLEANUP_OUTCOME_CLASSIFIER'
    Assert-Condition ($start -match 'POSTGRES_START_CLEANUP_FAILED') 'TEST_PRESERVES_START_FATAL'
    Assert-Condition ($securityTest.IndexOf('finally {') -lt $securityTest.LastIndexOf('$preliminaryResponse | ConvertTo-Json')) 'SECURITY_PASS_AFTER_CLEANUP'
    Assert-Condition ($securityTest -match 'SECURITY_FIXTURE_CLEANUP_FAILED') 'SECURITY_CLEANUP_FAILURE_FATAL'

    Assert-Condition ($runtimeModule -notmatch '(?i)ZipArchive|\.Entries|Assert-ThriveLensPostgresArchive') 'NO_ARCHIVE_PARSER'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensProjectedBudget') 'PROJECTED_BUDGET_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensFreeDiskBudget') 'PROJECTED_DISK_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'SECRET_ACL_ALLOWLIST_VIOLATION') 'SECRET_FULL_ALLOWLIST'
    Assert-Condition ($runtimeModule -match 'Enter-ThriveLensConfigurationLease' -and $runtimeModule -match 'Assert-ThriveLensConfigurationLease' -and $runtimeModule -match 'Exit-ThriveLensConfigurationLease') 'RUNTIME_CONFIGURATION_LEASE_PRIMITIVES'
    Assert-Condition ($runtimeModule -match '\[IO\.FileShare\]::Read' -and $runtimeModule -notmatch '\[IO\.FileShare\]::ReadWrite') 'RUNTIME_CONFIGURATION_LEASE_READ_SHARE_ONLY'
    Assert-Condition ($runtimeModule -match 'CONFIGURATION_LEASE_JSON_DUPLICATE_PROPERTY' -and $runtimeModule -match 'CONFIGURATION_LEASE_BOM_REJECTED') 'RUNTIME_CONFIGURATION_STRICT_JSON'
    Assert-Condition ($wslModule -match 'Resolve-ThriveLensRuntimeCleanupOutcome') 'RUNTIME_CLEANUP_POLICY_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensComposeDataDirectory') 'COMPOSE_EXACT_DIRECTORY_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensPathOutsideDirectory') 'COMPOSE_DISJOINT_PATH_PRIMITIVE'
    Assert-Condition ($runtimeModule -match "ValidateSet\('postgres', 'pg_ctl', 'initdb', 'pg_isready'\)") 'FOUR_EXACT_VERSION_TOOLS'
    Assert-Condition (@($runtimeModuleParseErrors).Count -eq 0 -and $resourceGateFunctions.Count -eq 1 -and
        $resourceGateBody -match "\`$pwshPath\s*=\s*\[IO\.Path\]::GetFullPath\(\[IO\.Path\]::Combine\(\`$PSHOME,\s*'pwsh\.exe'\)\)" -and
        $resourceGateBody -match '\$startInfo\.FileName\s*=\s*\$pwshPath' -and
        $resourceGateBody -match '\$startInfo\.UseShellExecute\s*=\s*\$false' -and
        $resourceGateBody -match '\$startInfo\.CreateNoWindow\s*=\s*\$true' -and
        $resourceGateBody -notmatch '(?i)cmd(?:\.exe)?|UseShellExecute\s*=\s*\$true') 'RESOURCE_GATE_ABSOLUTE_NO_SHELL_RUNNER'
    Assert-Condition (Test-ThriveLensRuntimeResourceRunnerArgumentContract -Source $runtimeModule) 'RESOURCE_GATE_EXACT_ARGUMENT_VECTOR'
    $runtimeArgumentMutations = @(
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_WARNING_ACTION_REMOVAL'; Old = "`$startInfo.ArgumentList.Add('-WarningAction')"; New = "`$null = 'warning action removed'" },
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_WARNING_VALUE_RELAXATION'; Old = "`$startInfo.ArgumentList.Add('SilentlyContinue')"; New = "`$startInfo.ArgumentList.Add('Continue')" },
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_WARNING_ARGUMENT_ORDER'; Old = "`$startInfo.ArgumentList.Add('-WarningAction')"; New = "`$startInfo.ArgumentList.Add('SilentlyContinue')" }
    )
    foreach ($mutation in $runtimeArgumentMutations) {
        $mutant = Replace-ThriveLensStaticSourceOnce -Source $runtimeModule -Old $mutation.Old -New $mutation.New
        $mutantTokens = $null
        $mutantErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($mutant, [ref]$mutantTokens, [ref]$mutantErrors)
        Assert-Condition (
            $mutant -cne $runtimeModule -and
            @($mutantErrors).Count -eq 0 -and
            -not (Test-ThriveLensRuntimeResourceRunnerArgumentContract -Source $mutant)
        ) $mutation.Code
    }
    Assert-Condition ($runtimeModule -match 'ResourceGateOutputBudgetV2[\s\S]+ContractVersion\s*=\s*"TL_RESOURCE_GATE_CAPTURE_V2"' -and
        $runtimeModule -match 'ResourceGateCaptureStreamV2[\s\S]+ContractVersion\s*=\s*"TL_RESOURCE_GATE_CAPTURE_V2"' -and
        $runtimeModule -match '\$resourceGateCaptureProbeBudget\s*=\s*\[ThriveLens\.ResourceGateOutputBudgetV2\]::new\(4\)' -and
        $runtimeModule -match '\$probeBytes\.Length\s*-ne\s*3' -and
        $resourceGateBody -match 'ResourceGateOutputBudgetV2\]::new\(131072\)' -and
        $resourceGateBody -match 'ResourceGateCaptureStreamV2\]::new\(\$budget\)[\s\S]+ResourceGateCaptureStreamV2\]::new\(\$budget\)' -and
        $resourceGateBody -match 'ElapsedMilliseconds\s*-ge\s*30000' -and
        $resourceGateBody -match '30000\s*-\s*\[int\]\$watch\.ElapsedMilliseconds' -and
        $resourceGateBody -match '\[Threading\.Thread\]::Sleep\(10\)') 'RESOURCE_GATE_V2_ATTESTED_SHARED_CAP_AND_DEADLINE'
    Assert-Condition ($resourceGateBody -match '\$process\.Kill\(\$true\)' -and
        $resourceGateBody -match '\$process\.WaitForExit\(5000\)' -and
        $resourceGateBody -match 'Task\]::WaitAll\(\$tasks,\s*5000\)' -and
        $resourceGateBody -match 'Where-Object\s*\{\s*-not\s+\$_\.IsCompleted\s*\}' -and
        $resourceGateBody -match "RESOURCE_GATE_FAILED','RESOURCE_GATE_PROCESS_START_FAILED'[\s\S]+RESOURCE_GATE_TIMEOUT','RESOURCE_GATE_OUTPUT_LIMIT'[\s\S]+RESOURCE_GATE_OUTPUT_DRAIN_INCOMPLETE','RESOURCE_GATE_RESULT_INVALID") 'RESOURCE_GATE_KILL_REAP_JOIN_FINITE_CODES'
    Assert-Condition ($resourceResultFunctions.Count -eq 1 -and
        $resourceResultBody -match "'cap_gb','accounted_bytes','accounted_gb','remaining_gb','used_percent'[\s\S]+'warning_percent','hard_stop_percent','file_count','roots'[\s\S]+'missing_inactive_roots','nested_roots_already_covered','status','phase'[\s\S]+'host_free_memory_gb'" -and
        $resourceResultBody -match '\$properties\.Count\s*-ne\s*\$expectedNames\.Count' -and
        $resourceResultBody -match '\[string\]\$properties\[11\]\.Value\.GetString\(\)\s*-cnotin\s*@\(''OK'',\s*''WARNING''\)' -and
        $resourceResultBody -match '\$properties\[1\]\.Value\.TryGetInt64\(\[ref\]\$accountedBytes\)' -and
        $resourceResultBody -match 'JsonDocumentOptions[\s\S]+AllowTrailingCommas\s*=\s*\$false[\s\S]+JsonCommentHandling\]::Disallow' -and
        $resourceResultBody -match 'Assert-ThriveLensConfigurationJsonElement') 'RESOURCE_GATE_SYSTEM_TEXT_JSON_EXACT_RESULT_SCHEMA'
    Assert-Condition ($resourceGateBody -match 'if\s*\(\$stderrBytes\.Length\s*-ne\s*0\)\s*\{\s*throw\s+''RESOURCE_GATE_RESULT_INVALID''\s*\}' -and
        $resourceGateBody -notmatch '(?i)GetString\(\$stderrBytes\)|Write-(?:Output|Host|Error|Warning|Information)[^\r\n]*\$stderr') 'RESOURCE_GATE_STDERR_PRIVATE_BYTES_AND_REJECTED'
    Assert-Condition ($runtimeModule -match 'function ConvertTo-ThriveLensResourcePolicyInt64[\s\S]+\$Value\s+-is\s+\[enum\][\s\S]+\$Value\s+-is\s+\[bool\][\s\S]+\$Value\s+-isnot\s+\[sbyte\][\s\S]+\$Value\s+-isnot\s+\[uint64\][\s\S]+\[uint64\]\[int64\]::MaxValue') 'RESOURCE_GATE_MANIFEST_EXACT_INTEGRAL_PRIMITIVES'
    Assert-Condition (Test-ThriveLensRuntimeResourceRunnerDisposalContract -Source $runtimeModule) 'RESOURCE_GATE_CONDITIONAL_READER_AND_PROCESS_DISPOSAL'
    $runtimeDisposalMutations = @(
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_ACTIVE_STDOUT_SINK_DISPOSAL'; Old = 'if ($stdoutReaderComplete) { $stdoutSink.Dispose() }'; New = '$stdoutSink.Dispose()' },
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_ACTIVE_STDERR_SINK_DISPOSAL'; Old = 'if ($stderrReaderComplete) { $stderrSink.Dispose() }'; New = '$stderrSink.Dispose()' },
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_PROCESS_READER_GATE_REMOVAL'; Old = 'if ($rootInactive -and $stdoutReaderComplete -and $stderrReaderComplete) {'; New = 'if ($rootInactive) {' },
        [pscustomobject]@{ Code = 'MUTATION_KILLS_RESOURCE_GATE_PROCESS_INACTIVE_GATE_REMOVAL'; Old = 'if ($rootInactive -and $stdoutReaderComplete -and $stderrReaderComplete) {'; New = 'if ($stdoutReaderComplete -and $stderrReaderComplete) {' }
    )
    foreach ($mutation in $runtimeDisposalMutations) {
        $mutant = Replace-ThriveLensStaticSourceOnce -Source $runtimeModule -Old $mutation.Old -New $mutation.New
        $mutantTokens = $null
        $mutantErrors = $null
        $null = [Management.Automation.Language.Parser]::ParseInput($mutant, [ref]$mutantTokens, [ref]$mutantErrors)
        Assert-Condition (
            $mutant -cne $runtimeModule -and
            @($mutantErrors).Count -eq 0 -and
            -not (Test-ThriveLensRuntimeResourceRunnerDisposalContract -Source $mutant)
        ) $mutation.Code
    }

    Assert-Condition ($postgresInstaller -match 'WINDOWS_POSTGRES_INSTALL_DISABLED') 'POSTGRES_INSTALL_HARD_DISABLED'
    Assert-Condition ($postgresInstaller -notmatch '(?i)Expand-Archive|ZipArchive|Get-Item|Get-Content|Test-Path|Move-Item|Start-Process') 'POSTGRES_BLOCK_BEFORE_ARTIFACT_USE'
    Assert-Condition ($pythonInstaller -match 'PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE') 'PYTHON_INSTALL_HARD_DISABLED'
    Assert-Condition ($pythonInstaller -notmatch '(?i)Start-Process|Get-Item|Get-Content|Test-Path|Get-FileHash|Invoke-ThriveLensResourceGate') 'PYTHON_BLOCK_BEFORE_ARTIFACT_PROCESS_USE'

    $composePath = Join-Path $projectRoot 'infra\compose.yaml'
    $compose = Get-Content -LiteralPath $composePath -Raw
    Assert-Condition ($compose -match '(?m)^services:\s*\{\}\s*$') 'COMPOSE_SERVICES_EMPTY'
    Assert-Condition ($compose -match '(?m)^x-thrivelens-postgres-contract:\s*$') 'COMPOSE_EXTENSION_CONTRACT'
    Assert-Condition ($compose -match 'status: BLOCKED_GATED_ACTIVATION_WRAPPER_NOT_IMPLEMENTED') 'COMPOSE_WRAPPER_BLOCKED'
    Assert-Condition ($compose -match 'direct_compose_activation_permitted: false') 'COMPOSE_DIRECT_ACTIVATION_BLOCKED'
    Assert-Condition ($compose -match 'restart_policy: "no"') 'COMPOSE_NO_RESTART_POLICY'
    Assert-Condition ($compose -notmatch '\$\{') 'COMPOSE_NO_INTERPOLATION'
    Assert-Condition ($compose -notmatch '(?m)^\s+(?:image|ports|volumes|secrets|build|command|entrypoint|container_name):') 'COMPOSE_NO_RUNNABLE_SERVICE_SURFACE'
    Assert-Condition ($compose -notmatch '0\.0\.0\.0') 'COMPOSE_NO_WILDCARD'
    Assert-Condition ($compose -match 'image_reference: postgres:17\.10-bookworm@sha256:[0-9a-f]{64}') 'COMPOSE_DIGEST_PIN'
    Assert-Condition ($compose -match 'sha256:6e5a6518f9d2ff9e9f4cba2a5a87d8f41b0f067f6f92ac847c344351a6c8d923') 'COMPOSE_AMD64_CHILD_DIGEST'
    Assert-Condition ($compose -match 'platform: linux/amd64') 'COMPOSE_AMD64_PLATFORM'
    Assert-Condition ($compose -match 'listen_address: 127\.0\.0\.1') 'COMPOSE_LOOPBACK'
    Assert-Condition ($compose -match 'host_port: 55432') 'COMPOSE_FIXED_HOST_PORT'
    Assert-Condition ($compose -match 'admin_user: tl_bootstrap') 'COMPOSE_FIXED_ADMIN_USER'
    Assert-Condition ($compose -match 'database: thrivelens_r0') 'COMPOSE_FIXED_DATABASE'
    Assert-Condition ($compose -match 'data_root: "%LOCALAPPDATA%\\\\ThriveLens\\\\data\\\\postgresql\\\\compose-r0"') 'COMPOSE_EXACT_DATA_DESCRIPTOR'
    Assert-Condition ($compose -match 'runtime_bytes: 536870912') 'COMPOSE_RUNTIME_LIMIT_DESCRIPTOR'
    Assert-Condition ($compose -match 'data_bytes: 134217728') 'COMPOSE_DATA_LIMIT_DESCRIPTOR'
    Assert-Condition ($compose -match 'same_process_validation_and_use_required: true') 'COMPOSE_NO_VALIDATION_USE_GAP'
    Assert-Condition ($compose -notmatch '(?m)^secrets:') 'COMPOSE_NO_SECRET_OBJECT'
    Assert-Condition ($composeValidator -match 'COMPOSE_ENGINE_STORAGE_ACCOUNTING_REQUIRED') 'COMPOSE_ACCOUNTING_GATE'
    Assert-Condition ($composeValidator -match 'COMPOSE_ACTIVATION_WRAPPER_REQUIRED') 'COMPOSE_WRAPPER_GATE'
    Assert-Condition ($composeValidator -match 'COMPOSE_ADMIN_USER_MISMATCH') 'COMPOSE_ADMIN_USER_GATE'
    Assert-Condition ($composeValidator -match 'COMPOSE_DATABASE_MISMATCH') 'COMPOSE_DATABASE_GATE'
    Assert-Condition ($composeValidator -match 'COMPOSE_PORT_MISMATCH') 'COMPOSE_PORT_GATE'
    Assert-Condition ($composeValidator -match 'GetEnvironmentVariable') 'COMPOSE_PROCESS_ENVIRONMENT_INPUT'
    Assert-Condition ($composeValidator -match 'Assert-ThriveLensComposeDataDirectory') 'COMPOSE_EXACT_DATA_GATE'
    Assert-Condition ($composeValidator -match 'COMPOSE_DATA_DIRECTORY_NOT_EMPTY') 'COMPOSE_EMPTY_DATA_GATE'
    Assert-Condition ($composeValidator -match 'Assert-ThriveLensPathOutsideDirectory') 'COMPOSE_DISJOINT_SECRET_GATE'
    Assert-Condition ($composeValidator -match 'DIRECTORY_ACL_ALLOWLIST_VIOLATION') 'COMPOSE_DIRECTORY_ACL_GATE'
    Assert-Condition ($composeValidator -match 'Assert-ThriveLensSecretFileAcl') 'COMPOSE_SECRET_ACL_GATE'

    $validatorTokens = $null
    $validatorErrors = $null
    $validatorAst = [Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $PSScriptRoot 'validate_compose_inputs.ps1'),
        [ref]$validatorTokens,
        [ref]$validatorErrors
    )
    Assert-Condition (@($validatorErrors).Count -eq 0) 'COMPOSE_VALIDATOR_PARSE_FOR_PARAMETERS'
    Assert-Condition ($validatorAst.ParamBlock.Parameters.Count -eq 0) 'COMPOSE_VALIDATOR_NO_PARAMETER_OVERRIDE'

    $manifest = Get-Content -LiteralPath (Join-Path $projectRoot 'config\toolchains\backend.json') -Raw | ConvertFrom-Json
    $validEnvironment = @{
        TL_POSTGRES_COMPOSE_DATA_DIR = [Environment]::ExpandEnvironmentVariables([string]$manifest.compose.data_root)
        TL_POSTGRES_ADMIN_PASSWORD_FILE = ''
        TL_POSTGRES_ADMIN_USER = [string]$manifest.compose.admin_user
        TL_POSTGRES_DATABASE = [string]$manifest.compose.database
        TL_POSTGRES_PORT = [string][int]$manifest.compose.port
    }
    $validProbe = Invoke-ComposeValidatorProbe -EnvironmentValues $validEnvironment
    $validPayload = $validProbe.StandardOutput | ConvertFrom-Json
    Assert-Condition ($validProbe.ExitCode -eq 2) 'COMPOSE_VALID_INPUT_STILL_BLOCKED'
    Assert-Condition (@($validPayload.codes) -ccontains 'COMPOSE_ACTIVATION_WRAPPER_REQUIRED') 'COMPOSE_VALID_INPUT_WRAPPER_REQUIRED'
    Assert-Condition (@($validPayload.codes) -cnotcontains 'COMPOSE_ADMIN_USER_MISMATCH') 'COMPOSE_VALID_ADMIN_ACCEPTED'
    Assert-Condition (@($validPayload.codes) -cnotcontains 'COMPOSE_DATABASE_MISMATCH') 'COMPOSE_VALID_DATABASE_ACCEPTED'
    Assert-Condition (@($validPayload.codes) -cnotcontains 'COMPOSE_PORT_MISMATCH') 'COMPOSE_VALID_PORT_ACCEPTED'

    $unsafeEnvironment = $validEnvironment.Clone()
    $unsafeEnvironment.TL_POSTGRES_ADMIN_USER = 'tl_bootstrap;whoami'
    $unsafeEnvironment.TL_POSTGRES_DATABASE = 'thrivelens_r0/../postgres'
    $unsafeEnvironment.TL_POSTGRES_PORT = '55432:5432'
    $unsafeProbe = Invoke-ComposeValidatorProbe -EnvironmentValues $unsafeEnvironment
    $unsafePayload = $unsafeProbe.StandardOutput | ConvertFrom-Json
    Assert-Condition ($unsafeProbe.ExitCode -eq 2) 'COMPOSE_UNSAFE_INPUT_BLOCKED'
    Assert-Condition (@($unsafePayload.codes) -ccontains 'COMPOSE_ADMIN_USER_MISMATCH') 'COMPOSE_UNSAFE_ADMIN_REJECTED'
    Assert-Condition (@($unsafePayload.codes) -ccontains 'COMPOSE_DATABASE_MISMATCH') 'COMPOSE_UNSAFE_DATABASE_REJECTED'
    Assert-Condition (@($unsafePayload.codes) -ccontains 'COMPOSE_PORT_MISMATCH') 'COMPOSE_UNSAFE_PORT_REJECTED'

    $overrideProbe = Invoke-ComposeValidatorProbe `
        -EnvironmentValues $validEnvironment `
        -AdditionalArguments @('-DataDirectory', 'C:\unsafe-override')
    Assert-Condition ($overrideProbe.ExitCode -ne 0) 'COMPOSE_PARAMETER_OVERRIDE_BLOCKED'
    Assert-Condition ((($overrideProbe.StandardOutput + $overrideProbe.StandardError) -notmatch '"status"\s*:\s*"READY"')) 'COMPOSE_PARAMETER_OVERRIDE_NEVER_READY'

    if ($failures.Count -gt 0) {
        [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) } | ConvertTo-Json -Compress
        exit 1
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; scripts_parsed = $scripts.Count; policy_assertions = $assertionCount } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; codes = @('STATIC_TEST_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 2
}
