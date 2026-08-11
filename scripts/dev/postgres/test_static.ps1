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
            Assert-Condition ($content -notmatch '(?i)\b(New-Service|Start-Service|Register-Service|sudo|wsl\.exe|docker\.exe)\b') ('GLOBAL_MUTATION_' + $script.Name)
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
    $composeValidator = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'validate_compose_inputs.ps1') -Raw
    $postgresInstaller = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\bootstrap\backend\install_postgres.ps1') -Raw
    $pythonInstaller = Get-Content -LiteralPath (Join-Path $projectRoot 'scripts\bootstrap\backend\install_python.ps1') -Raw
    Assert-Condition ($start -match "-h 127\.0\.0\.1") 'START_LOOPBACK'
    Assert-Condition ($start -match "'-w'.*'-t'.*'30'") 'START_BOUNDED_WAIT'
    Assert-Condition ($start -match 'if \(\$startAttempted\)[\s\S]+stop\.ps1[\s\S]+Assert-ThriveLensPostgresAbsent') 'START_FAILURE_CLEANUP'
    Assert-Condition ($start -match 'POSTGRES_START_CLEANUP_FAILED') 'START_CLEANUP_FAILURE_CODE'
    Assert-Condition ($stop -match "'-m'.*'fast'.*'-w'.*'-t'.*'30'") 'STOP_BOUNDED_FAST'
    Assert-Condition ($stop.IndexOf('Assert-ThriveLensPostgresAbsent') -lt $stop.IndexOf("status = 'STOPPED'")) 'STOP_ABSENCE_BEFORE_CLAIM'
    Assert-Condition ($stop -match 'POSTGRES_LISTENER_MEASUREMENT_UNAVAILABLE') 'STOP_LISTENER_MEASUREMENT_FAIL_CLOSED'
    Assert-Condition ($initialize -match '--auth-host=scram-sha-256') 'INIT_HOST_SCRAM'
    Assert-Condition ($initialize -match '--auth-local=scram-sha-256') 'INIT_LOCAL_SCRAM'
    Assert-Condition ($initialize -match '--pwfile') 'INIT_PASSWORD_FILE'
    Assert-Condition ($initialize -match 'Assert-ThriveLensSecretFileAcl') 'INIT_PASSWORD_ACL'
    Assert-Condition ($initialize -match '--data-checksums') 'INIT_CHECKSUMS'
    Assert-Condition ($initialize -match 'DATA_INVENTORY_UPDATE_REQUIRED') 'INIT_DATA_INVENTORY'
    Assert-Condition ($initialize -match 'Measure-ThriveLensSafeTree') 'INIT_POST_SIZE_CEILING'
    Assert-Condition ($initialize -match 'Invoke-ThriveLensResourceGate') 'INIT_POST_RESOURCE_GATE'
    Assert-Condition ($preflight -match 'LOW_FREE_MEMORY') 'LOW_MEMORY_FAIL_CLOSED'
    Assert-Condition ($preflight -match 'RESOURCE_PHASE_NOT_ACTIVE') 'PHASE_FAIL_CLOSED'
    Assert-Condition ($preflight -match 'ProjectedAdditionalBytes') 'PROJECTED_RESOURCE_GATE'
    Assert-Condition ($preflight -match 'WINDOWS_POSTGRES_RUNTIME_REJECTED') 'REJECTED_WINDOWS_RUNTIME'
    Assert-Condition ($preflight -match 'WSL_FALLBACK_REQUIRED_NOT_ACTIVATED') 'WSL_REQUIRED_BLOCKER'
    Assert-Condition ($preflight -match 'Assert-ThriveLensPostgresVersions') 'RUNTIME_EXACT_VERSIONS'
    Assert-Condition ($runtimeTest.IndexOf("stop.ps1") -lt $runtimeTest.IndexOf("status = 'PASS'")) 'TEST_STOP_BEFORE_PASS'
    Assert-Condition ($runtimeTest -match 'RUNTIME_CLEANUP_FAILED') 'TEST_CLEANUP_FAILURE'

    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensPostgresArchive') 'ARCHIVE_CENTRAL_SCAN'
    Assert-Condition ($runtimeModule -match 'ARCHIVE_LINK_OR_SPECIAL_ENTRY_REJECTED') 'ARCHIVE_LINK_REJECT'
    Assert-Condition ($runtimeModule -match 'ARCHIVE_DUPLICATE_PATH_REJECTED') 'ARCHIVE_DUPLICATE_REJECT'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensProjectedBudget') 'PROJECTED_BUDGET_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'Assert-ThriveLensFreeDiskBudget') 'PROJECTED_DISK_PRIMITIVE'
    Assert-Condition ($runtimeModule -match 'SECRET_ACL_READ_ALLOWLIST_VIOLATION') 'SECRET_READ_ALLOWLIST'
    Assert-Condition ($runtimeModule -match "ValidateSet\('postgres', 'pg_ctl', 'initdb', 'pg_isready'\)") 'FOUR_EXACT_VERSION_TOOLS'

    Assert-Condition ($postgresInstaller -match 'WINDOWS_POSTGRES_INSTALL_DISABLED') 'POSTGRES_INSTALL_HARD_DISABLED'
    Assert-Condition ($postgresInstaller.IndexOf('Assert-ThriveLensPostgresArchive') -lt $postgresInstaller.IndexOf('Expand-Archive')) 'ARCHIVE_SCAN_BEFORE_EXTRACT'
    Assert-Condition ($postgresInstaller.IndexOf('Assert-ThriveLensPostgresVersions') -lt $postgresInstaller.IndexOf('Move-Item')) 'VERSION_BEFORE_MOVE'
    Assert-Condition ($postgresInstaller -match 'Measure-ThriveLensSafeTree') 'POSTGRES_NOFOLLOW_RESCAN'
    Assert-Condition ($postgresInstaller -match 'Invoke-ThriveLensResourceGate') 'POSTGRES_POST_RESOURCE_GATE'
    Assert-Condition ($pythonInstaller -match '-InstallKind Python') 'PYTHON_PROJECTED_PREFLIGHT'
    Assert-Condition ($pythonInstaller -match 'Measure-ThriveLensSafeTree') 'PYTHON_NOFOLLOW_RESCAN'
    Assert-Condition ($pythonInstaller -match 'Invoke-ThriveLensResourceGate') 'PYTHON_POST_RESOURCE_GATE'

    $compose = Get-Content -LiteralPath (Join-Path $projectRoot 'infra\compose.yaml') -Raw
    Assert-Condition ($compose -match '127\.0\.0\.1:\$\{TL_POSTGRES_PORT:-55432\}:5432') 'COMPOSE_LOOPBACK'
    Assert-Condition ($compose -notmatch '0\.0\.0\.0') 'COMPOSE_NO_WILDCARD'
    Assert-Condition ($compose -match 'postgres:17\.10-bookworm@sha256:[0-9a-f]{64}') 'COMPOSE_DIGEST_PIN'
    Assert-Condition ($compose -match 'sha256:6e5a6518f9d2ff9e9f4cba2a5a87d8f41b0f067f6f92ac847c344351a6c8d923') 'COMPOSE_AMD64_CHILD_DIGEST'
    Assert-Condition ($compose -match 'platform: linux/amd64') 'COMPOSE_AMD64_PLATFORM'
    Assert-Condition ($compose -match 'profiles: \["postgres-explicit"\]') 'COMPOSE_DEFAULT_DISABLED_PROFILE'
    Assert-Condition ($compose -match 'POSTGRES_PASSWORD_FILE') 'COMPOSE_SECRET_FILE'
    Assert-Condition ($compose -notmatch 'POSTGRES_PASSWORD\s*:') 'COMPOSE_NO_INLINE_PASSWORD'
    Assert-Condition ($compose -match 'type: bind') 'COMPOSE_COUNTED_BIND'
    Assert-Condition ($compose -match 'TL_POSTGRES_COMPOSE_DATA_DIR') 'COMPOSE_DATA_ENV'
    Assert-Condition ($compose -notmatch '(?m)^volumes:') 'COMPOSE_NO_NAMED_VOLUME'
    Assert-Condition ($composeValidator -match 'COMPOSE_ENGINE_STORAGE_ACCOUNTING_REQUIRED') 'COMPOSE_ACCOUNTING_GATE'
    Assert-Condition ($composeValidator -match 'Assert-ThriveLensSecretFileAcl') 'COMPOSE_SECRET_ACL_GATE'

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
