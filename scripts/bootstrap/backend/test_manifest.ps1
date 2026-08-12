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
    Assert-Condition ([int64]$manifest.resource_policy.postgresql_worst_case_additional_bytes -eq 251000000) 'POSTGRES_PROJECTION'
    Assert-Condition ([string]$manifest.resource_policy.wsl_foundation_projection_scope -ceq 'PACKAGE_ONLY_CEILING_EXCLUDES_UBUNTU_DISTRO_VHD_AND_APT_METADATA') 'POSTGRES_PROJECTION_SCOPE'
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

    Assert-Condition ([string]$manifest.wsl_fallback.status -ceq 'ACTIVATED_PACKAGES_VERIFIED') 'WSL_STATUS'
    Assert-Condition ([string]$manifest.wsl_fallback.human_system_authority -ceq 'AUTHORIZED_2026-08-12_FOR_DEDICATED_DISTRO_ONLY') 'WSL_HUMAN_AUTHORITY'
    Assert-Condition ([string]$manifest.wsl_fallback.distribution_name -ceq 'ThriveLens-R0') 'WSL_DISTRO_NAME'
    Assert-Condition ([string]$manifest.wsl_fallback.distribution_install_root -ceq '%LOCALAPPDATA%\ThriveLens\wsl\ThriveLens-R0') 'WSL_DISTRO_ROOT'
    Assert-Condition ([int64]$manifest.wsl_fallback.maximum_vhd_bytes -eq 6442450944) 'WSL_VHD_LIMIT'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.artifact_url -ceq 'https://releases.ubuntu.com/24.04.4/ubuntu-24.04.4-wsl-amd64.wsl') 'WSL_UBUNTU_ARTIFACT_URL'
    Assert-Condition ([int64]$manifest.wsl_fallback.ubuntu_image.compressed_size_bytes -eq 391541571) 'WSL_UBUNTU_ARTIFACT_BYTES'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.sha256 -ceq '9b2f7730dc68227dd04a9f3e5eab86ad85caf556b8606ad94f1f29ff5c4fd3f5') 'WSL_UBUNTU_ARTIFACT_SHA256'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.sha256sums_url -ceq 'https://releases.ubuntu.com/24.04.4/SHA256SUMS') 'WSL_UBUNTU_SHA256SUMS_URL'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.sha256sums_signature_url -ceq 'https://releases.ubuntu.com/24.04.4/SHA256SUMS.gpg') 'WSL_UBUNTU_SIGNATURE_URL'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.publisher_metadata_checked_at -ceq '2026-08-12') 'WSL_UBUNTU_METADATA_CHECK_DATE'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.web_download_payload_retention_status -ceq 'NOT_RETAINED') 'WSL_WEB_DOWNLOAD_NOT_RETAINED'
    Assert-Condition ([string]$manifest.wsl_fallback.ubuntu_image.current_vhd_byte_attestation -ceq 'NOT_ATTESTED_BY_RECORDED_UPSTREAM_HASH') 'WSL_VHD_NOT_BYTE_ATTESTED'
    Assert-Condition ([string]$manifest.wsl_fallback.measurement_snapshot.observed_at -ceq '2026-08-12') 'WSL_MEASUREMENT_DATE'
    Assert-Condition ([string]$manifest.wsl_fallback.measurement_snapshot.method -ceq 'LIGHTWEIGHT_READ_ONLY_WINDOWS_FILE_LENGTH_AND_AGGREGATE_ROOT_MEASUREMENT') 'WSL_MEASUREMENT_METHOD'
    Assert-Condition ([int64]$manifest.wsl_fallback.measurement_snapshot.vhd_file_bytes -eq 2131755008) 'WSL_VHD_OBSERVED_BYTES'
    Assert-Condition ([int64]$manifest.wsl_fallback.measurement_snapshot.aggregate_counted_bytes -gt [int64]$manifest.wsl_fallback.measurement_snapshot.vhd_file_bytes) 'WSL_AGGREGATE_OBSERVED_BYTES'
    Assert-Condition ([string]$manifest.wsl_fallback.measurement_snapshot.attestation_limit -ceq 'POINT_IN_TIME_SIZE_OBSERVATION_ONLY_NOT_AN_UPSTREAM_IMAGE_BYTE_ATTESTATION') 'WSL_MEASUREMENT_ATTESTATION_LIMIT'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.signing_key_fingerprint -ceq 'B97B0AFCAA1A47F044F244A07FCC7D46ACCC4CF8') 'WSL_PGDG_FINGERPRINT'
    Assert-Condition (@($manifest.wsl_fallback.pgdg.package_closure).Count -eq 9) 'WSL_PACKAGE_CLOSURE'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.apt_reported_archive_size -ceq '48.4 MB') 'WSL_APT_ARCHIVE_ROUNDED'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.apt_reported_installed_size -ceq '201 MB') 'WSL_APT_INSTALLED_ROUNDED'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.apt_reported_size_precision -ceq 'ROUNDED_DISPLAY_VALUES_NOT_EXACT_BYTE_ATTESTATION') 'WSL_APT_SIZE_PRECISION'
    Assert-Condition ([int64]$manifest.wsl_fallback.pgdg.package_only_ceiling_bytes -eq 251000000) 'WSL_PACKAGE_ONLY_CEILING'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.package_only_ceiling_scope -ceq 'POSTGRESQL_PACKAGE_ARCHIVES_AND_INSTALLED_PACKAGES_ONLY_EXCLUDES_UBUNTU_DISTRO_VHD_AND_APT_METADATA') 'WSL_PACKAGE_ONLY_SCOPE'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.installed_package_license_metadata_status -ceq 'POSTGRESQL_AND_UBUNTU_PACKAGE_COPYRIGHT_METADATA_PRESENT') 'WSL_PACKAGE_LICENSE_METADATA'
    Assert-Condition ([string]$manifest.wsl_fallback.pgdg.dependency_license_inventory_status -ceq 'NOT_INDEPENDENTLY_ENUMERATED_OR_APPROVED') 'WSL_DEPENDENCY_LICENSE_LIMIT'
    Assert-Condition ([string]$manifest.wsl_fallback.package_integrity_policy -cmatch 'Pin an exact supported PostgreSQL package version') 'WSL_SIGNED_PIN'
    Assert-Condition ([string]$manifest.wsl_fallback.storage_policy -cmatch 'dedicated ThriveLens WSL storage') 'WSL_COUNTED_STORAGE'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.availability_gate -ceq 'TL-R0-003_VERIFIED_WITH_TWO_CYCLE_RUNTIME_PASS') 'TL004_HANDOFF_GATE'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.host -ceq '127.0.0.1' -and [int]$manifest.tl_r0_004_handoff.port -eq 55432) 'TL004_HANDOFF_ENDPOINT'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.maintenance_database -ceq 'postgres' -and [string]$manifest.tl_r0_004_handoff.bootstrap_role -ceq 'tl_bootstrap') 'TL004_HANDOFF_BOOTSTRAP'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.bootstrap_password_file -ceq '%LOCALAPPDATA%\ThriveLens\secrets\postgres-r0-bootstrap.pw') 'TL004_HANDOFF_SECRET_PATH'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.target_application_database -ceq 'thrivelens_r0') 'TL004_HANDOFF_TARGET_DB'
    Assert-Condition ((@($manifest.tl_r0_004_handoff.tl_r0_004_owns) -join ',') -ceq 'target_application_database_creation,migration_role,runtime_role,baseline_migration,single_migration_head') 'TL004_HANDOFF_OWNERSHIP'
    Assert-Condition ([string]$manifest.tl_r0_004_handoff.secret_output_policy -ceq 'NEVER_EMIT_OR_RETAIN_SECRET_OR_DSN') 'TL004_HANDOFF_SECRET_POLICY'
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
    Assert-Condition ([string]$manifest.data_inventory_gate.status -ceq 'SATISFIED') 'DATA_INVENTORY_GATE'
    Assert-Condition ([string]$manifest.data_inventory_gate.owned_document -ceq 'docs/privacy/DATA_INVENTORY.md') 'DATA_INVENTORY_PATH'
    Assert-Condition ([string]$manifest.data_inventory_gate.ownership_note -cmatch 'integration owner added') 'DATA_INVENTORY_OWNERSHIP'
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
