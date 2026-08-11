#Requires -Version 7.0

[CmdletBinding()]
param([string]$ArtifactPath)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The artifact and target-size pins exclude installer TEMP/TMP scratch and any
# persistent installer cache. Until ceilings and counted paths exist, this
# blocker intentionally does not inspect ArtifactPath or start any process.
[pscustomobject]@{
    schema_version = 1
    status = 'BLOCKED'
    code = 'PYTHON_INSTALL_DISABLED_UNMEASURED_SCRATCH_CACHE'
    projection_status = 'INCOMPLETE'
} | ConvertTo-Json -Compress
exit 2
