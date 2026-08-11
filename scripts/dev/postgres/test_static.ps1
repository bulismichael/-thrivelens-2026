#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$failures = [Collections.Generic.List[string]]::new()

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    if (-not $Condition) { $failures.Add($Code) }
}

try {
    $scriptRoots = @(
        (Join-Path $projectRoot 'scripts\bootstrap\backend'),
        (Join-Path $projectRoot 'scripts\dev\postgres')
    )
    $scripts = @(foreach ($root in $scriptRoots) { Get-ChildItem -LiteralPath $root -File | Where-Object { $_.Extension -in @('.ps1', '.psm1') } })
    Assert-Condition ($scripts.Count -ge 10) 'SCRIPT_INVENTORY'
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
    Assert-Condition ($start -match "-h 127\.0\.0\.1") 'START_LOOPBACK'
    Assert-Condition ($start -match "'-w'.*'-t'.*'30'") 'START_BOUNDED_WAIT'
    Assert-Condition ($stop -match "'-m'.*'fast'.*'-w'.*'-t'.*'30'") 'STOP_BOUNDED_FAST'
    Assert-Condition ($initialize -match '--auth-host=scram-sha-256') 'INIT_HOST_SCRAM'
    Assert-Condition ($initialize -match '--auth-local=scram-sha-256') 'INIT_LOCAL_SCRAM'
    Assert-Condition ($initialize -match '--pwfile') 'INIT_PASSWORD_FILE'
    Assert-Condition ($initialize -match 'PASSWORD_FILE_ACL_TOO_BROAD') 'INIT_PASSWORD_ACL'
    Assert-Condition ($initialize -match '--data-checksums') 'INIT_CHECKSUMS'
    Assert-Condition ($preflight -match 'LOW_FREE_MEMORY') 'LOW_MEMORY_FAIL_CLOSED'
    Assert-Condition ($preflight -match 'RESOURCE_PHASE_NOT_ACTIVE') 'PHASE_FAIL_CLOSED'

    $compose = Get-Content -LiteralPath (Join-Path $projectRoot 'infra\compose.yaml') -Raw
    Assert-Condition ($compose -match '127\.0\.0\.1:\$\{TL_POSTGRES_PORT:-55432\}:5432') 'COMPOSE_LOOPBACK'
    Assert-Condition ($compose -notmatch '0\.0\.0\.0') 'COMPOSE_NO_WILDCARD'
    Assert-Condition ($compose -match 'postgres:17\.10-bookworm@sha256:[0-9a-f]{64}') 'COMPOSE_DIGEST_PIN'
    Assert-Condition ($compose -match 'POSTGRES_PASSWORD_FILE') 'COMPOSE_SECRET_FILE'
    Assert-Condition ($compose -notmatch 'POSTGRES_PASSWORD\s*:') 'COMPOSE_NO_INLINE_PASSWORD'

    if ($failures.Count -gt 0) {
        [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) } | ConvertTo-Json -Compress
        exit 1
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; scripts_parsed = $scripts.Count; policy_assertions = 16 } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; codes = @('STATIC_TEST_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 2
}
