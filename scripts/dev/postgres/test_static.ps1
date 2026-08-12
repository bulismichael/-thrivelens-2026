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
    Assert-Condition ($start -match "-h 127\.0\.0\.1") 'START_LOOPBACK'
    Assert-Condition ($start -match "'-w'.*'-t'.*'30'") 'START_BOUNDED_WAIT'
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
    Assert-Condition ($runtimeTest -match 'stop\.ps1[\s\S]+status=''PASS''') 'TEST_STOP_BEFORE_PASS'
    Assert-Condition ($runtimeTest.IndexOf('$started=$true') -lt $runtimeTest.IndexOf("start.ps1")) 'TEST_MARKS_START_BEFORE_CHILD'
    Assert-Condition ($runtimeTest -match '\$started=\$true;\$start=') 'TEST_NONZERO_START_INDEPENDENT_CLEANUP'
    Assert-Condition ($runtimeTest -match 'RUNTIME_START_PROBE_FAILED') 'TEST_CHILD_FAILURE_CLASSIFIER'
    Assert-Condition ($runtimeTest -match 'RUNTIME_CLEANUP_FAILED') 'TEST_CLEANUP_OUTCOME_CLASSIFIER'
    Assert-Condition ($start -match 'POSTGRES_START_CLEANUP_FAILED') 'TEST_PRESERVES_START_FATAL'
    Assert-Condition ($securityTest.IndexOf('finally {') -lt $securityTest.LastIndexOf('$preliminaryResponse | ConvertTo-Json')) 'SECURITY_PASS_AFTER_CLEANUP'
    Assert-Condition ($securityTest -match 'SECURITY_FIXTURE_CLEANUP_FAILED') 'SECURITY_CLEANUP_FAILURE_FATAL'

    Assert-Condition ($runtimeModule -notmatch '(?i)ZipArchive|\.Entries|Assert-ThriveLensPostgresArchive') 'NO_ARCHIVE_PARSER'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensProjectedBudget') 'PROJECTED_BUDGET_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensFreeDiskBudget') 'PROJECTED_DISK_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'SECRET_ACL_ALLOWLIST_VIOLATION') 'SECRET_FULL_ALLOWLIST'
    Assert-Condition ($runtimeModule -match 'Resolve-ThriveLensStartChildFailure') 'RUNTIME_CHILD_POLICY_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Resolve-ThriveLensRuntimeFailureOutcome') 'RUNTIME_CLEANUP_POLICY_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensComposeDataDirectory') 'COMPOSE_EXACT_DIRECTORY_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensPathOutsideDirectory') 'COMPOSE_DISJOINT_PATH_PRIMITIVE'
    Assert-Condition ($runtimeModule -match "ValidateSet\('postgres', 'pg_ctl', 'initdb', 'pg_isready'\)") 'FOUR_EXACT_VERSION_TOOLS'

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
