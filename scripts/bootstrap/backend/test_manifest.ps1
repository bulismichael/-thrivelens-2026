#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot '..\..\..')).Path
$manifestPath = Join-Path $projectRoot 'config\toolchains\backend.json'
$failures = [Collections.Generic.List[string]]::new()
$assertionCount = 0

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    $script:assertionCount++
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
    Assert-Condition ([int64]$manifest.resource_policy.minimum_free_disk_reserve_bytes -eq 536870912) 'DISK_RESERVE'
    Assert-Condition ([int]$manifest.resource_policy.maximum_tree_entries -eq 50000) 'TREE_ENTRY_LIMIT'
    Assert-Condition ([int64]$manifest.resource_policy.python_known_artifact_and_target_bytes -eq 297888400) 'PYTHON_KNOWN_BYTES'
    Assert-Condition ($null -eq $manifest.resource_policy.python_worst_case_additional_bytes) 'PYTHON_PROJECTION_UNAVAILABLE'
    Assert-Condition ([string]$manifest.resource_policy.python_projection_status -ceq 'INCOMPLETE_TEMP_AND_PERSISTENT_INSTALLER_CACHE_UNMEASURED') 'PYTHON_PROJECTION_STATUS'
    Assert-Condition ([int64]$manifest.resource_policy.postgresql_worst_case_additional_bytes -eq 1340560230) 'POSTGRES_PROJECTION'
    Assert-Condition ([int64]$manifest.resource_policy.postgresql_initialization_worst_case_additional_bytes -eq 134217728) 'INIT_PROJECTION'
    Assert-Condition ($null -eq $manifest.resource_policy.worst_case_backend_additional_bytes) 'BACKEND_PROJECTION_UNAVAILABLE'
    Assert-Condition ((@($manifest.resource_policy.allowed_active_phases) -join ',') -ceq 'bootstrap_active,implementation,release') 'ACTIVE_PHASES'

    Assert-Condition ([string]$manifest.python.version -ceq '3.13.15') 'PYTHON_VERSION'
    Assert-Condition ([int64]$manifest.python.compressed_bytes -eq 29452944) 'PYTHON_SIZE'
    Assert-Condition ([string]$manifest.python.integrity.value -cmatch '^[0-9a-f]{64}$') 'PYTHON_SHA256'
    Assert-Condition ([string]$manifest.python.integrity.sigstore_bundle_url -cmatch '^https://www\.python\.org/') 'PYTHON_SIGSTORE'
    Assert-Condition (-not [bool]$manifest.python.integrity.sigstore_enforced) 'PYTHON_SIGSTORE_NOT_ENFORCED'
    Assert-Condition ((@($manifest.python.integrity.enforced_methods) -join ',') -ceq 'SHA-256,Authenticode') 'PYTHON_ENFORCED_INTEGRITY'
    Assert-Condition ([string]$manifest.python.integrity.status -ceq 'SHA256_AND_AUTHENTICODE_ENFORCED_SIGSTORE_RECORDED_ONLY') 'PYTHON_INTEGRITY_STATUS'
    Assert-Condition (-not [bool]$manifest.python.install_enabled) 'PYTHON_INSTALL_DISABLED'
    Assert-Condition ([string]$manifest.python.installation_status -ceq 'BLOCKED_UNMEASURED_TEMP_AND_PERSISTENT_INSTALLER_CACHE') 'PYTHON_INSTALL_STATUS'
    Assert-Condition ($null -eq $manifest.python.temporary_scratch_ceiling_bytes) 'PYTHON_TEMP_UNMEASURED'
    Assert-Condition ($null -eq $manifest.python.persistent_installer_cache_ceiling_bytes) 'PYTHON_CACHE_UNMEASURED'
    Assert-Condition ([string]$manifest.python.scratch_cache_counted_paths_status -ceq 'UNDEFINED') 'PYTHON_SCRATCH_PATHS_UNDEFINED'
    Assert-Condition (-not [bool]$manifest.python.install_policy.all_users) 'PYTHON_ALL_USERS'
    Assert-Condition (-not [bool]$manifest.python.install_policy.modify_machine_path) 'PYTHON_PATH_POLICY'

    Assert-Condition ([string]$manifest.postgresql.version -ceq '17.10') 'POSTGRES_VERSION'
    Assert-Condition ([string]$manifest.postgresql.package_revision -ceq '2') 'POSTGRES_REVISION'
    Assert-Condition ([int64]$manifest.postgresql.compressed_bytes -eq 333927270) 'POSTGRES_SIZE'
    Assert-Condition ($null -eq $manifest.postgresql.integrity.value) 'POSTGRES_HASH_MUST_REMAIN_UNCLAIMED'
    Assert-Condition ($null -eq $manifest.postgresql.integrity.publisher_signature_url) 'POSTGRES_SIGNATURE_MUST_REMAIN_UNCLAIMED'
    Assert-Condition ([string]$manifest.postgresql.integrity.status -ceq 'REJECTED_NO_PUBLISHER_ARCHIVE_ATTESTATION') 'POSTGRES_INTEGRITY_STATUS'
    Assert-Condition ([string]$manifest.postgresql.portable_status -ceq 'REJECTED_FOR_RUNTIME') 'POSTGRES_RUNTIME_STATUS'
    Assert-Condition (-not [bool]$manifest.postgresql.windows_portable_install_enabled) 'POSTGRES_WINDOWS_INSTALL_DISABLED'
    Assert-Condition ([string]$manifest.postgresql.windows_interactive_installer_status -ceq 'HARD_DISABLED') 'POSTGRES_INTERACTIVE_INSTALLER_DISABLED'
    Assert-Condition ([int64]$manifest.postgresql.projected_binary_footprint_ceiling_bytes -eq 805306368) 'POSTGRES_BINARY_PROJECTION'
    Assert-Condition ([string]$manifest.postgresql.binary_size_projection_status -ceq 'UNMEASURED_ARCHIVE_REJECTED_AND_NEVER_OPENED') 'POSTGRES_BINARY_PROJECTION_STATUS'
    Assert-Condition ([string]$manifest.postgresql.listen_address -ceq '127.0.0.1') 'POSTGRES_BIND'
    Assert-Condition ([int]$manifest.postgresql.port -eq 55432) 'POSTGRES_PORT'
    Assert-Condition ([int64]$manifest.postgresql.maximum_total_postgresql_bytes -lt 1073741824) 'POSTGRES_ALLOCATION'

    Assert-Condition ([string]$manifest.wsl_fallback.status -ceq 'REQUIRED_BUT_NOT_ACTIVATED') 'WSL_STATUS'
    Assert-Condition ([string]$manifest.wsl_fallback.human_system_authority -ceq 'REQUIRED') 'WSL_HUMAN_AUTHORITY'
    Assert-Condition ([string]$manifest.wsl_fallback.package_integrity_policy -cmatch 'Pin an exact supported PostgreSQL package version') 'WSL_SIGNED_PIN'
    Assert-Condition ([string]$manifest.wsl_fallback.storage_policy -cmatch 'dedicated ThriveLens WSL storage') 'WSL_COUNTED_STORAGE'
    Assert-Condition ([string]$manifest.compose.index_digest -cmatch '^sha256:[0-9a-f]{64}$') 'COMPOSE_INDEX_DIGEST'
    Assert-Condition ([string]$manifest.compose.linux_amd64_manifest_digest -cmatch '^sha256:[0-9a-f]{64}$') 'COMPOSE_AMD64_DIGEST'
    Assert-Condition ([int64]$manifest.compose.linux_amd64_compressed_layer_bytes -eq 156095657) 'COMPOSE_SIZE'
    Assert-Condition (-not [bool]$manifest.compose.enabled_by_default) 'COMPOSE_DEFAULT_DISABLED'
    Assert-Condition ([string]$manifest.compose.required_profile -ceq 'postgres-explicit') 'COMPOSE_PROFILE'
    Assert-Condition ([string]$manifest.compose.platform -ceq 'linux/amd64') 'COMPOSE_PLATFORM'
    Assert-Condition ([int64]$manifest.compose.projected_additional_bytes -eq 827184297) 'COMPOSE_PROJECTION'
    Assert-Condition ([string]$manifest.compose.activation_status -ceq 'BLOCKED_GATED_ACTIVATION_WRAPPER_NOT_IMPLEMENTED') 'COMPOSE_ACTIVATION_STATUS'
    Assert-Condition ([bool]$manifest.compose.activation_wrapper_required) 'COMPOSE_WRAPPER_REQUIRED'
    Assert-Condition ([string]$manifest.compose.activation_wrapper_status -ceq 'REQUIRED_NOT_IMPLEMENTED') 'COMPOSE_WRAPPER_STATUS'
    Assert-Condition (-not [bool]$manifest.compose.direct_compose_activation_permitted) 'COMPOSE_DIRECT_ACTIVATION_BLOCKED'
    Assert-Condition ([bool]$manifest.compose.same_process_validation_and_use_required) 'COMPOSE_SAME_PROCESS_POLICY'
    Assert-Condition ([string]$manifest.compose.listen_address -ceq '127.0.0.1') 'COMPOSE_LOOPBACK'
    Assert-Condition ([int]$manifest.compose.port -eq 55432) 'COMPOSE_EXACT_PORT'
    Assert-Condition ([int]$manifest.compose.port -gt 1024 -and [int]$manifest.compose.port -le 65535) 'COMPOSE_BOUNDED_PORT'
    Assert-Condition ([string]$manifest.compose.admin_user -ceq 'tl_bootstrap') 'COMPOSE_EXACT_ADMIN_USER'
    Assert-Condition ([string]$manifest.compose.database -ceq 'thrivelens_r0') 'COMPOSE_EXACT_DATABASE'
    Assert-Condition ([string]$manifest.compose.environment_contract.data_directory -ceq 'TL_POSTGRES_COMPOSE_DATA_DIR') 'COMPOSE_DATA_ENVIRONMENT'
    Assert-Condition ([string]$manifest.compose.environment_contract.password_file -ceq 'TL_POSTGRES_ADMIN_PASSWORD_FILE') 'COMPOSE_PASSWORD_ENVIRONMENT'
    Assert-Condition ([string]$manifest.compose.environment_contract.admin_user -ceq 'TL_POSTGRES_ADMIN_USER') 'COMPOSE_ADMIN_ENVIRONMENT'
    Assert-Condition ([string]$manifest.compose.environment_contract.database -ceq 'TL_POSTGRES_DATABASE') 'COMPOSE_DATABASE_ENVIRONMENT'
    Assert-Condition ([string]$manifest.compose.environment_contract.port -ceq 'TL_POSTGRES_PORT') 'COMPOSE_PORT_ENVIRONMENT'
    Assert-Condition ([string]$manifest.compose.data_root -ceq '%LOCALAPPDATA%\ThriveLens\data\postgresql\compose-r0') 'COMPOSE_EXACT_DATA_ROOT'
    Assert-Condition ([bool]$manifest.compose.initial_activation_requires_empty_data_root) 'COMPOSE_EMPTY_DATA_ROOT'
    Assert-Condition ([bool]$manifest.compose.password_must_be_outside_data_root) 'COMPOSE_SECRET_DISJOINT'
    Assert-Condition ([string]$manifest.compose.engine_storage_accounting_status -ceq 'REQUIRED_NOT_CONFIGURED') 'COMPOSE_ACCOUNTING_BLOCKED'
    Assert-Condition ([string]$manifest.data_inventory_gate.status -ceq 'REQUIRED_NOT_SATISFIED') 'DATA_INVENTORY_GATE'
    Assert-Condition ([string]$manifest.data_inventory_gate.owned_document -ceq 'docs/privacy/DATA_INVENTORY.md') 'DATA_INVENTORY_PATH'
    Assert-Condition ($raw -notmatch '(?i)C:\\Users\\|/home/|/Users/') 'PRIVATE_PATH'
    Assert-Condition ($raw -notmatch '(?i)(password|token|secret)"\s*:\s*"[^"\s]+"') 'SECRET_VALUE'
    Assert-Condition ($raw -notmatch 'maximum_archive_entries') 'NO_ARCHIVE_PARSER_POLICY'

    if ($failures.Count -gt 0) {
        [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) } | ConvertTo-Json -Compress
        exit 1
    }
    [pscustomobject]@{ schema_version = 1; status = 'PASS'; assertions = $assertionCount } | ConvertTo-Json -Compress
}
catch {
    [pscustomobject]@{ schema_version = 1; status = 'ERROR'; codes = @('MANIFEST_TEST_INTERNAL_ERROR') } | ConvertTo-Json -Compress
    exit 2
}
