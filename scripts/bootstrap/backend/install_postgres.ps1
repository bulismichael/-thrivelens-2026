#Requires -Version 7.0

[CmdletBinding()]
param([string]$ArtifactPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The Windows EDB artifact is permanently rejected for this release. This
# blocker intentionally does not inspect ArtifactPath, open an archive, create
# staging, execute a binary, or mutate the host.
[pscustomobject]@{
    schema_version = 1
    status = 'BLOCKED'
    code = 'WINDOWS_POSTGRES_INSTALL_DISABLED'
    portable_status = 'REJECTED_FOR_RUNTIME'
    fallback = 'WSL_REQUIRED_BUT_NOT_ACTIVATED'
} | ConvertTo-Json -Compress
exit 2
