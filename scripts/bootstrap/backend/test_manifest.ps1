#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $projectRoot 'config\toolchains\backend.json'
$failures = [Collections.Generic.List[string]]::new()

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    if (-not $Condition) { $failures.Add($Code) }
}

try {
    $raw = Get-Content -LiteralPath $manifestPath -Raw
    $manifest = $raw | ConvertFrom-Json
    Assert-Condition ($manifest.schema_version -eq 1) 'SCHEMA_VERSION'
    Assert-Condition ([string]$manifest.task_id -ceq 'TL-R0-003') 'TASK_ID'
    Assert-Condition ([string]$manifest.target.attributable_root -ceq '%LOCALAPPDATA%\ThriveLens') 'ATTRIBUTABLE_ROOT'
    Assert-Condition ([int64]$manifest.resource_policy.aggregate_cap_bytes -eq 19327352832) 'AGGREGATE_CAP'
    Assert-Condition ([int]$manifest.resource_policy.hard_stop_percent -eq 85) 'HARD_STOP_PERCENT'
    Assert-Condition ([int64]$manifest.resource_policy.install_minimum_free_memory_bytes -eq 2147483648) 'INSTALL_MEMORY'
    Assert-Condition ([int64]$manifest.resource_policy.runtime_minimum_free_memory_bytes -eq 1073741824) 'RUNTIME_MEMORY'
    Assert-Condition ((@($manifest.resource_policy.allowed_active_phases) -join ',') -ceq 'bootstrap_active,implementation,release') 'ACTIVE_PHASES'

    Assert-Condition ([string]$manifest.python.version -ceq '3.13.15') 'PYTHON_VERSION'
    Assert-Condition ([int64]$manifest.python.compressed_bytes -eq 29452944) 'PYTHON_SIZE'
    Assert-Condition ([string]$manifest.python.integrity.value -cmatch '^[0-9a-f]{64}$') 'PYTHON_SHA256'
    Assert-Condition ([string]$manifest.python.integrity.sigstore_bundle_url -cmatch '^https://www\.python\.org/') 'PYTHON_SIGSTORE'
    Assert-Condition (-not [bool]$manifest.python.install_policy.all_users) 'PYTHON_ALL_USERS'
    Assert-Condition (-not [bool]$manifest.python.install_policy.modify_machine_path) 'PYTHON_PATH_POLICY'

    Assert-Condition ([string]$manifest.postgresql.version -ceq '17.10') 'POSTGRES_VERSION'
    Assert-Condition ([string]$manifest.postgresql.package_revision -ceq '2') 'POSTGRES_REVISION'
    Assert-Condition ([int64]$manifest.postgresql.compressed_bytes -eq 333927270) 'POSTGRES_SIZE'
    Assert-Condition ($null -eq $manifest.postgresql.integrity.value) 'POSTGRES_HASH_MUST_REMAIN_UNCLAIMED'
    Assert-Condition ($null -eq $manifest.postgresql.integrity.publisher_signature_url) 'POSTGRES_SIGNATURE_MUST_REMAIN_UNCLAIMED'
    Assert-Condition ([string]$manifest.postgresql.integrity.status -ceq 'BLOCKED_PUBLISHER_ARCHIVE_ATTESTATION_UNAVAILABLE') 'POSTGRES_INTEGRITY_STATUS'
    Assert-Condition ([string]$manifest.postgresql.portable_status -ceq 'CANDIDATE_NOT_ACCEPTED_OR_INSTALLED') 'POSTGRES_RUNTIME_STATUS'
    Assert-Condition ([string]$manifest.postgresql.listen_address -ceq '127.0.0.1') 'POSTGRES_BIND'
    Assert-Condition ([int]$manifest.postgresql.port -eq 55432) 'POSTGRES_PORT'
    Assert-Condition ([int64]$manifest.postgresql.maximum_total_postgresql_bytes -lt 1073741824) 'POSTGRES_ALLOCATION'

    Assert-Condition ([string]$manifest.wsl_fallback.status -ceq 'NOT_ACTIVATED_REQUIRES_RESOURCE_ACCOUNTING_AND_HUMAN_SYSTEM_CHANGE') 'WSL_STATUS'
    Assert-Condition ([string]$manifest.compose.index_digest -cmatch '^sha256:[0-9a-f]{64}$') 'COMPOSE_INDEX_DIGEST'
    Assert-Condition ([string]$manifest.compose.linux_amd64_manifest_digest -cmatch '^sha256:[0-9a-f]{64}$') 'COMPOSE_AMD64_DIGEST'
    Assert-Condition ([int64]$manifest.compose.linux_amd64_compressed_layer_bytes -eq 156095657) 'COMPOSE_SIZE'
    Assert-Condition ($raw -notmatch '(?i)C:\\Users\\|/home/|/Users/') 'PRIVATE_PATH'
    Assert-Condition ($raw -notmatch '(?i)(password|token|secret)"\s*:\s*"[^"\s]+"') 'SECRET_VALUE'

    if ($failures.Count -gt 0) {
        [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) } | ConvertTo-Json -Compress
        exit 1
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; assertions = 31 } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; codes = @('MANIFEST_TEST_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 2
}
