#Requires -Version 7.0

[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$modulePath = Join-Path $PSScriptRoot 'Runtime.psm1'
$failures = [Collections.Generic.List[string]]::new()
$assertionCount = 0
$fixtureRoot = $null
$preliminaryResponse = $null
$preliminaryExitCode = 2
$cleanupSucceeded = $true
$runtimeModule = $null

function Assert-Condition {
    param([bool]$Condition, [string]$Code)
    $script:assertionCount++
    if (-not $Condition) { $script:failures.Add($Code) }
}

function Assert-ThrowsCode {
    param(
        [Parameter(Mandatory)][scriptblock]$Action,
        [Parameter(Mandatory)][string]$Expected,
        [Parameter(Mandatory)][string]$Code
    )
    $observed = $null
    try { & $Action | Out-Null }
    catch { $observed = $_.Exception.Message }
    Assert-Condition ($observed -ceq $Expected) $Code
}

function Set-SyntheticProtectedAcl {
    param([Parameter(Mandatory)][string]$Path)
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $aclOutput = @(& icacls.exe $Path '/inheritance:r' '/grant:r' ("*$currentSid`:(F)") 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'SYNTHETIC_ACL_SETUP_FAILED' }
    $aclOutput = $null
}

function Add-SyntheticEveryoneRight {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][ValidateSet('R', 'W')][string]$Right
    )
    $aclOutput = @(& icacls.exe $Path '/grant' ("*S-1-1-0:($Right)") 2>&1)
    if ($LASTEXITCODE -ne 0) { throw 'SYNTHETIC_ACL_MUTATION_FAILED' }
    $aclOutput = $null
}

function Resolve-SecurityFixtureOutcome {
    param(
        [Parameter(Mandatory)][string]$PreliminaryStatus,
        [Parameter(Mandatory)][int]$PreliminaryExitCode,
        [Parameter(Mandatory)][bool]$CleanupSucceeded
    )
    if (-not $CleanupSucceeded) {
        return [pscustomobject]@{
            Status = 'ERROR'
            Code = 'SECURITY_FIXTURE_CLEANUP_FAILED'
            ExitCode = 3
        }
    }
    return [pscustomobject]@{
        Status = $PreliminaryStatus
        Code = $null
        ExitCode = $PreliminaryExitCode
    }
}

function Set-ConfigurationLeaseFixtureDefinitions {
    param(
        [Parameter(Mandatory)][Management.Automation.PSModuleInfo]$Module,
        [Parameter(Mandatory)][string]$BackendPath,
        [Parameter(Mandatory)][string]$ResourcePath
    )
    $definitions = @(
        [pscustomobject]@{
            Role = 'BACKEND_MANIFEST'
            Path = [IO.Path]::GetFullPath($BackendPath)
            MaximumLength = [int64]1MB
        },
        [pscustomobject]@{
            Role = 'RESOURCE_BUDGET'
            Path = [IO.Path]::GetFullPath($ResourcePath)
            MaximumLength = [int64]256KB
        }
    )
    & $Module {
        param([object[]]$FixtureDefinitions)
        $script:ThriveLensConfigurationLeaseFixtureDefinitions = @($FixtureDefinitions)
        Set-Item -Path 'Function:Get-ThriveLensConfigurationLeaseDefinitions' -Value {
            return @($script:ThriveLensConfigurationLeaseFixtureDefinitions)
        }
    } $definitions
}

function Invoke-ConfigurationLeaseEntryProbe {
    $lease = $null
    $code = $null
    try { $lease = Enter-ThriveLensConfigurationLease }
    catch { $code = [string]$_.Exception.Message }
    finally {
        if ($null -ne $lease) {
            try { Exit-ThriveLensConfigurationLease -Lease $lease }
            catch { if ($null -eq $code) { $code = [string]$_.Exception.Message } }
        }
    }
    return $code
}

function Invoke-ResourceGateResultProbe {
    param(
        [Parameter(Mandatory)][string]$Json,
        [switch]$WithBom
    )
    $value = $null
    $code = $null
    try {
        $value = & $runtimeModule {
            param([string]$FixtureJson, [bool]$PrefixBom)
            $encoding = [Text.UTF8Encoding]::new($false, $true)
            $payload = $encoding.GetBytes($FixtureJson)
            if ($PrefixBom) {
                $payload = [byte[]](@(0xEF, 0xBB, 0xBF) + @($payload))
            }
            try { Read-ThriveLensResourceGateResult -Bytes $payload }
            finally { [Array]::Clear($payload, 0, $payload.Length) }
        } $Json ([bool]$WithBom)
    }
    catch { $code = [string]$_.Exception.Message }
    return [pscustomobject]@{ Value = $value; Code = $code }
}

try {
    $runtimeModule = Import-Module -Name $modulePath -Force -PassThru
    $attributableRoot = Get-ThriveLensAttributableRoot
    $fixtureParent = Assert-ThriveLensOwnedPath -Path (Join-Path $attributableRoot 'test-temp') -AllowMissing
    $fixtureRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $fixtureParent ('security-' + [guid]::NewGuid().ToString('N'))) -AllowMissing
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force

    $validIntegralPolicyValues = @(
        [sbyte]1, [byte]1, [int16]1, [uint16]1,
        [int32]1, [uint32]1, [int64]1, [uint64]1
    )
    foreach ($policyValue in $validIntegralPolicyValues) {
        $convertedPolicyValue = & $runtimeModule {
            param($Value)
            ConvertTo-ThriveLensResourcePolicyInt64 -Value $Value
        } $policyValue
        Assert-Condition (
            $convertedPolicyValue -is [int64] -and $convertedPolicyValue -eq 1
        ) ('RESOURCE_GATE_MANIFEST_ACCEPTS_' + $policyValue.GetType().Name.ToUpperInvariant())
    }
    $invalidIntegralPolicyValues = @(
        $true,
        [DayOfWeek]::Monday,
        [single]1,
        [double]1,
        [decimal]1,
        '1',
        [uint64]::MaxValue
    )
    foreach ($policyValue in $invalidIntegralPolicyValues) {
        $observedPolicyCode = $null
        try {
            $null = & $runtimeModule {
                param($Value)
                ConvertTo-ThriveLensResourcePolicyInt64 -Value $Value
            } $policyValue
        }
        catch { $observedPolicyCode = [string]$_.Exception.Message }
        Assert-Condition ($observedPolicyCode -ceq 'RESOURCE_GATE_MANIFEST_INVALID') `
            ('RESOURCE_GATE_MANIFEST_REJECTS_' + $policyValue.GetType().Name.ToUpperInvariant())
    }

    $validResourceResultJson = '{"cap_gb":18,"accounted_bytes":123,"accounted_gb":1,"remaining_gb":17,"used_percent":1,"warning_percent":80,"hard_stop_percent":90,"file_count":2,"roots":[],"missing_inactive_roots":[],"nested_roots_already_covered":[],"status":"OK","phase":"bootstrap_active","host_free_memory_gb":1}'
    $validResourceResult = Invoke-ResourceGateResultProbe -Json $validResourceResultJson
    Assert-Condition (
        $null -eq $validResourceResult.Code -and
        $null -ne $validResourceResult.Value -and
        ($validResourceResult.Value.PSObject.Properties.Name -join ',') -ceq 'AccountedBytes,Status' -and
        $validResourceResult.Value.AccountedBytes -is [int64] -and
        $validResourceResult.Value.AccountedBytes -eq 123 -and
        $validResourceResult.Value.Status -ceq 'OK'
    ) 'RESOURCE_GATE_RESULT_EXACT_14_PROPERTY_SCHEMA_ACCEPTED'
    $invalidResourceResults = @(
        [pscustomobject]@{ Name = 'DUPLICATE_CASE_ALIAS'; Json = $validResourceResultJson.Replace('"status":"OK"', '"status":"OK","Status":"OK"'); Bom = $false },
        [pscustomobject]@{ Name = 'COMMENT'; Json = $validResourceResultJson.Replace('{', '{/*synthetic*/'); Bom = $false },
        [pscustomobject]@{ Name = 'TRAILING_COMMA'; Json = $validResourceResultJson.Substring(0, $validResourceResultJson.Length - 1) + ',}'; Bom = $false },
        [pscustomobject]@{ Name = 'BOM'; Json = $validResourceResultJson; Bom = $true },
        [pscustomobject]@{ Name = 'EXTRA_PROPERTY'; Json = $validResourceResultJson.Substring(0, $validResourceResultJson.Length - 1) + ',"extra":1}'; Bom = $false },
        [pscustomobject]@{ Name = 'MISSING_PROPERTY'; Json = $validResourceResultJson.Replace(',"host_free_memory_gb":1', ''); Bom = $false },
        [pscustomobject]@{ Name = 'REORDERED_PROPERTIES'; Json = $validResourceResultJson.Replace('"cap_gb":18,"accounted_bytes":123', '"accounted_bytes":123,"cap_gb":18'); Bom = $false },
        [pscustomobject]@{ Name = 'ACCOUNTED_BOOLEAN'; Json = $validResourceResultJson.Replace('"accounted_bytes":123', '"accounted_bytes":true'); Bom = $false },
        [pscustomobject]@{ Name = 'ACCOUNTED_STRING'; Json = $validResourceResultJson.Replace('"accounted_bytes":123', '"accounted_bytes":"123"'); Bom = $false },
        [pscustomobject]@{ Name = 'ACCOUNTED_FLOAT'; Json = $validResourceResultJson.Replace('"accounted_bytes":123', '"accounted_bytes":123.0'); Bom = $false },
        [pscustomobject]@{ Name = 'ACCOUNTED_OVERFLOW'; Json = $validResourceResultJson.Replace('"accounted_bytes":123', '"accounted_bytes":9223372036854775808'); Bom = $false },
        [pscustomobject]@{ Name = 'ACCOUNTED_NEGATIVE'; Json = $validResourceResultJson.Replace('"accounted_bytes":123', '"accounted_bytes":-1'); Bom = $false },
        [pscustomobject]@{ Name = 'STATUS_CASE'; Json = $validResourceResultJson.Replace('"status":"OK"', '"status":"ok"'); Bom = $false }
    )
    foreach ($invalidResourceResult in $invalidResourceResults) {
        $probeParameters = @{ Json = [string]$invalidResourceResult.Json }
        if ([bool]$invalidResourceResult.Bom) { $probeParameters.WithBom = $true }
        $invalidResourceResultProbe = Invoke-ResourceGateResultProbe @probeParameters
        Assert-Condition (
            $invalidResourceResultProbe.Code -ceq 'RESOURCE_GATE_RESULT_INVALID' -and
            $null -eq $invalidResourceResultProbe.Value
        ) ('RESOURCE_GATE_RESULT_REJECTS_' + $invalidResourceResult.Name)
    }

    # Configuration lease tests use only disposable files beneath the attributable
    # test root.  They never rename, delete, or replace either real repository
    # control file.
    $leaseFixtureRoot = Join-Path $fixtureRoot 'configuration-lease'
    $null = New-Item -ItemType Directory -Path $leaseFixtureRoot
    $backendFixturePath = Join-Path $leaseFixtureRoot 'backend.json'
    $resourceFixturePath = Join-Path $leaseFixtureRoot 'resource-budget.json'
    $utf8NoBom = [Text.UTF8Encoding]::new($false, $true)
    $validBackendJson = '{"resource_policy":{"runtime_minimum_free_memory_bytes":1073741824,"allowed_active_phases":["bootstrap_active"]}}'
    $validResourceJson = '{"phase":"bootstrap_active","roots":[]}'
    [IO.File]::WriteAllText($backendFixturePath, $validBackendJson, $utf8NoBom)
    [IO.File]::WriteAllText($resourceFixturePath, $validResourceJson, $utf8NoBom)
    Set-ConfigurationLeaseFixtureDefinitions `
        -Module $runtimeModule `
        -BackendPath $backendFixturePath `
        -ResourcePath $resourceFixturePath

    $configurationLease = Enter-ThriveLensConfigurationLease
    $observerStreams = [Collections.Generic.List[IO.FileStream]]::new()
    try {
        $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
        $publicProperties = @($configurationLease.PSObject.Properties | ForEach-Object { [string]$_.Name })
        Assert-Condition (
            ($publicProperties -join ',') -ceq 'Version,Roles' -and
            $configurationLease.Version -is [int] -and
            $configurationLease.Version -eq 1 -and
            $configurationLease.Roles -is [string[]] -and
            ($configurationLease.Roles -join ',') -ceq 'BACKEND_MANIFEST,RESOURCE_BUDGET'
        ) 'CONFIGURATION_LEASE_MINIMAL_PUBLIC_SHAPE'
        Assert-Condition (
            $null -eq $configurationLease.PSObject.Properties['Records'] -and
            $null -eq $configurationLease.PSObject.Properties['Stream'] -and
            $null -eq $configurationLease.PSObject.Properties['RawJson'] -and
            $null -eq $configurationLease.PSObject.Properties['Path'] -and
            $null -eq $configurationLease.PSObject.Properties['Identity'] -and
            $null -eq $configurationLease.PSObject.Properties['Sha256']
        ) 'CONFIGURATION_LEASE_NO_INTERNAL_HANDLE_OR_CONTENT_DISCLOSURE'
        $leasedManifest = Get-ThriveLensLeasedBackendManifest -Lease $configurationLease
        $leasedResource = Get-ThriveLensLeasedResourceBudget -Lease $configurationLease
        $leaseFingerprint = Get-ThriveLensConfigurationLeaseFingerprint -Lease $configurationLease
        Assert-Condition (
            [int64]$leasedManifest.resource_policy.runtime_minimum_free_memory_bytes -eq 1073741824 -and
            [string]$leasedResource.phase -ceq 'bootstrap_active' -and
            $leaseFingerprint -cmatch '^[0-9A-F]{64}$'
        ) 'CONFIGURATION_LEASE_VALUES_AND_FINGERPRINT'

        foreach ($fixturePath in @($backendFixturePath, $resourceFixturePath)) {
            $observerStreams.Add([IO.FileStream]::new(
                $fixturePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Read,
                [IO.FileShare]::Read
            ))
        }
        Assert-Condition ($observerStreams.Count -eq 2 -and @($observerStreams | Where-Object { -not $_.CanRead }).Count -eq 0) `
            'CONFIGURATION_LEASE_FILESHARE_READ_ALLOWS_READERS'
        foreach ($fixturePath in @($backendFixturePath, $resourceFixturePath)) {
            $writeOpened = $false
            $writeProbe = $null
            try {
                $writeProbe = [IO.FileStream]::new(
                    $fixturePath,
                    [IO.FileMode]::Open,
                    [IO.FileAccess]::Write,
                    [IO.FileShare]::ReadWrite
                )
                $writeOpened = $true
            }
            catch { $writeOpened = $false }
            finally { if ($null -ne $writeProbe) { $writeProbe.Dispose() } }
            Assert-Condition (-not $writeOpened) 'CONFIGURATION_LEASE_FILESHARE_READ_BLOCKS_WRITER'

            $renamedPath = $fixturePath + '.renamed'
            $renameSucceeded = $false
            try {
                [IO.File]::Move($fixturePath, $renamedPath)
                $renameSucceeded = $true
            }
            catch { $renameSucceeded = $false }
            finally {
                if ($renameSucceeded -and (Test-Path -LiteralPath $renamedPath -PathType Leaf)) {
                    [IO.File]::Move($renamedPath, $fixturePath)
                }
            }
            Assert-Condition (
                -not $renameSucceeded -and
                (Test-Path -LiteralPath $fixturePath -PathType Leaf) -and
                -not (Test-Path -LiteralPath $renamedPath)
            ) 'CONFIGURATION_LEASE_FILESHARE_READ_BLOCKS_IDENTITY_RENAME'
        }
        $null = Assert-ThriveLensConfigurationLease -Lease $configurationLease
        Assert-Condition $true 'CONFIGURATION_LEASE_IDENTITY_STILL_VALID_AFTER_BLOCKED_MUTATION'
    }
    finally {
        for ($index = $observerStreams.Count - 1; $index -ge 0; $index--) {
            $observerStreams[$index].Dispose()
        }
        Exit-ThriveLensConfigurationLease -Lease $configurationLease
    }
    Assert-ThrowsCode { Assert-ThriveLensConfigurationLease -Lease $configurationLease } `
        'CONFIGURATION_LEASE_INVALID' 'CONFIGURATION_LEASE_ASSERT_AFTER_DISPOSE_REJECTED'
    foreach ($fixturePath in @($backendFixturePath, $resourceFixturePath)) {
        $postDisposeWriter = [IO.FileStream]::new(
            $fixturePath,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Write,
            [IO.FileShare]::Read
        )
        $postDisposeWriter.Dispose()
    }
    Assert-Condition $true 'CONFIGURATION_LEASE_INTERNAL_STREAMS_RELEASED_AFTER_DISPOSE'

    $forgedLease = [pscustomobject]@{
        Version = 1
        Roles = [string[]]@('BACKEND_MANIFEST', 'RESOURCE_BUDGET')
    }
    Assert-ThrowsCode { Assert-ThriveLensConfigurationLease -Lease $forgedLease } `
        'CONFIGURATION_LEASE_INVALID' 'CONFIGURATION_LEASE_FORGED_IDENTITY_REJECTED'

    foreach ($tamperCase in @('Version', 'RoleValue', 'RoleReference', 'ExtraProperty')) {
        $tamperedLease = Enter-ThriveLensConfigurationLease
        switch ($tamperCase) {
            'Version' { $tamperedLease.Version = 2 }
            'RoleValue' { $tamperedLease.Roles[0] = 'RESOURCE_BUDGET' }
            'RoleReference' {
                $tamperedLease.Roles = [string[]]@('BACKEND_MANIFEST', 'RESOURCE_BUDGET')
            }
            'ExtraProperty' {
                Add-Member -InputObject $tamperedLease -NotePropertyName Records -NotePropertyValue @()
            }
        }
        Assert-ThrowsCode { Assert-ThriveLensConfigurationLease -Lease $tamperedLease } `
            'CONFIGURATION_LEASE_INVALID' ('CONFIGURATION_LEASE_PUBLIC_' + $tamperCase.ToUpperInvariant() + '_TAMPER_REJECTED')
        Assert-ThrowsCode { Exit-ThriveLensConfigurationLease -Lease $tamperedLease } `
            'CONFIGURATION_LEASE_INVALID' ('CONFIGURATION_LEASE_TAMPER_' + $tamperCase.ToUpperInvariant() + '_DISPOSED')
        foreach ($fixturePath in @($backendFixturePath, $resourceFixturePath)) {
            $tamperReleaseWriter = [IO.FileStream]::new(
                $fixturePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Write,
                [IO.FileShare]::Read
            )
            $tamperReleaseWriter.Dispose()
        }
        Assert-Condition $true ('CONFIGURATION_LEASE_TAMPER_' + $tamperCase.ToUpperInvariant() + '_INTERNAL_STREAMS_CLOSED')
    }

    $strictJsonCases = @(
        [pscustomobject]@{ Name = 'DUPLICATE_CASE'; Target = 'BACKEND'; Bytes = $utf8NoBom.GetBytes('{"Policy":1,"policy":2}'); Expected = 'CONFIGURATION_LEASE_JSON_DUPLICATE_PROPERTY' },
        [pscustomobject]@{ Name = 'BOM'; Target = 'RESOURCE'; Bytes = [byte[]](@(0xEF, 0xBB, 0xBF) + @($utf8NoBom.GetBytes('{"phase":"bootstrap_active"}'))); Expected = 'CONFIGURATION_LEASE_BOM_REJECTED' },
        [pscustomobject]@{ Name = 'TRAILING_COMMA'; Target = 'BACKEND'; Bytes = $utf8NoBom.GetBytes('{"policy":1,}'); Expected = 'CONFIGURATION_LEASE_JSON_INVALID' },
        [pscustomobject]@{ Name = 'COMMENT'; Target = 'BACKEND'; Bytes = $utf8NoBom.GetBytes('{/*x*/"policy":1}'); Expected = 'CONFIGURATION_LEASE_JSON_INVALID' },
        [pscustomobject]@{ Name = 'NON_OBJECT'; Target = 'BACKEND'; Bytes = $utf8NoBom.GetBytes('[1,2]'); Expected = 'CONFIGURATION_LEASE_JSON_ROOT_INVALID' },
        [pscustomobject]@{ Name = 'RAW_CONTROL'; Target = 'BACKEND'; Bytes = [byte[]](0x7B,0x22,0x78,0x22,0x3A,0x22,0x00,0x22,0x7D); Expected = 'CONFIGURATION_LEASE_JSON_CONTROL_REJECTED' },
        [pscustomobject]@{ Name = 'INVALID_UTF8'; Target = 'BACKEND'; Bytes = [byte[]](0x7B,0x22,0x78,0x22,0x3A,0x22,0xC3,0x28,0x22,0x7D); Expected = 'CONFIGURATION_LEASE_UTF8_INVALID' }
    )
    foreach ($strictCase in $strictJsonCases) {
        [IO.File]::WriteAllText($backendFixturePath, $validBackendJson, $utf8NoBom)
        [IO.File]::WriteAllText($resourceFixturePath, $validResourceJson, $utf8NoBom)
        $targetPath = if ($strictCase.Target -ceq 'RESOURCE') { $resourceFixturePath } else { $backendFixturePath }
        [IO.File]::WriteAllBytes($targetPath, [byte[]]$strictCase.Bytes)
        Set-ConfigurationLeaseFixtureDefinitions `
            -Module $runtimeModule `
            -BackendPath $backendFixturePath `
            -ResourcePath $resourceFixturePath
        $observedLeaseCode = Invoke-ConfigurationLeaseEntryProbe
        Assert-Condition ($observedLeaseCode -ceq [string]$strictCase.Expected) `
            ('CONFIGURATION_LEASE_STRICT_' + $strictCase.Name)
        foreach ($fixturePath in @($backendFixturePath, $resourceFixturePath)) {
            $releasedWriter = [IO.FileStream]::new(
                $fixturePath,
                [IO.FileMode]::Open,
                [IO.FileAccess]::Write,
                [IO.FileShare]::Read
            )
            $releasedWriter.Dispose()
        }
        Assert-Condition $true ('CONFIGURATION_LEASE_STRICT_' + $strictCase.Name + '_PARTIAL_OPEN_DISPOSED')
    }
    [IO.File]::WriteAllText($backendFixturePath, $validBackendJson, $utf8NoBom)
    [IO.File]::WriteAllText($resourceFixturePath, $validResourceJson, $utf8NoBom)

    $mockCleanupFailure = Resolve-SecurityFixtureOutcome -PreliminaryStatus PASS -PreliminaryExitCode 0 -CleanupSucceeded $false
    Assert-Condition (
        $mockCleanupFailure.Status -ceq 'ERROR' -and
        $mockCleanupFailure.Code -ceq 'SECURITY_FIXTURE_CLEANUP_FAILED' -and
        $mockCleanupFailure.ExitCode -eq 3
    ) 'FIXTURE_CLEANUP_FAILURE_ESCALATES'

    $treeRoot = Join-Path $fixtureRoot 'safe-tree'
    $null = New-Item -ItemType Directory -Path $treeRoot
    [IO.File]::WriteAllBytes((Join-Path $treeRoot 'three.bin'), [byte[]](1, 2, 3))
    $treeScan = Measure-ThriveLensSafeTree -Root $treeRoot -MaximumBytes 3 -MaximumEntries 1
    Assert-Condition ($treeScan.Bytes -eq 3 -and $treeScan.Entries -eq 1) 'SAFE_TREE_EXACT_CEILING'
    Assert-ThrowsCode { Measure-ThriveLensSafeTree -Root $treeRoot -MaximumBytes 2 -MaximumEntries 1 } `
        'SAFE_TREE_SIZE_EXCEEDED' 'SAFE_TREE_SIZE_REJECTED'

    $outsidePath = Join-Path ([IO.Path]::GetPathRoot($attributableRoot)) 'Windows'
    Assert-ThrowsCode { Assert-ThriveLensOwnedPath -Path $outsidePath -AllowMissing } `
        'PATH_OUTSIDE_ATTRIBUTABLE_ROOT' 'OUTSIDE_PATH_REJECTED'

    $null = Assert-ThriveLensProjectedBudget -AccountedBytes 800 -AdditionalBytes 49 -CapBytes 1000 -HardStopPercent 85
    Assert-Condition $true 'PROJECTED_BELOW_HIGH_WATER'
    Assert-ThrowsCode { Assert-ThriveLensProjectedBudget -AccountedBytes 800 -AdditionalBytes 50 -CapBytes 1000 -HardStopPercent 85 } `
        'PROJECTED_RESOURCE_HARD_STOP' 'PROJECTED_85_PERCENT_REJECTED'
    Assert-ThrowsCode { Assert-ThriveLensProjectedBudget -AccountedBytes 900 -AdditionalBytes 100 -CapBytes 1000 -HardStopPercent 85 } `
        'PROJECTED_RESOURCE_CAP_EXCEEDED' 'PROJECTED_CAP_REJECTED'
    $null = Assert-ThriveLensFreeDiskBudget -FreeDiskBytes 150 -AdditionalBytes 100 -ReserveBytes 50
    Assert-Condition $true 'PROJECTED_FREE_DISK_EXACT_CEILING'
    Assert-ThrowsCode { Assert-ThriveLensFreeDiskBudget -FreeDiskBytes 149 -AdditionalBytes 100 -ReserveBytes 50 } `
        'PROJECTED_FREE_DISK_INSUFFICIENT' 'PROJECTED_FREE_DISK_REJECTED'

    foreach ($tool in @('postgres', 'pg_ctl', 'initdb', 'pg_isready')) {
        Assert-ThriveLensVersionText -Tool $tool -Observed "$tool (PostgreSQL) 17.10" -Version '17.10'
        Assert-Condition $true ('EXACT_VERSION_' + $tool)
    }
    Assert-ThrowsCode { Assert-ThriveLensVersionText -Tool postgres -Observed 'postgres (PostgreSQL) 17.10 extra' -Version '17.10' } `
        'POSTGRES_VERSION_OUTPUT_MISMATCH' 'VERSION_SUFFIX_REJECTED'

    $readSecretPath = Join-Path $fixtureRoot 'read-secret.txt'
    [IO.File]::WriteAllText($readSecretPath, 'synthetic-test-only')
    Set-SyntheticProtectedAcl -Path $readSecretPath
    Assert-ThriveLensSecretFileAcl -Path $readSecretPath
    Assert-Condition $true 'STRICT_SECRET_ACL_ACCEPTED'
    Add-SyntheticEveryoneRight -Path $readSecretPath -Right R
    Assert-ThrowsCode { Assert-ThriveLensSecretFileAcl -Path $readSecretPath } `
        'SECRET_ACL_ALLOWLIST_VIOLATION' 'BROAD_SECRET_READ_REJECTED'

    $writeSecretPath = Join-Path $fixtureRoot 'write-secret.txt'
    [IO.File]::WriteAllText($writeSecretPath, 'synthetic-test-only')
    Set-SyntheticProtectedAcl -Path $writeSecretPath
    Add-SyntheticEveryoneRight -Path $writeSecretPath -Right W
    Assert-ThrowsCode { Assert-ThriveLensSecretFileAcl -Path $writeSecretPath } `
        'SECRET_ACL_ALLOWLIST_VIOLATION' 'WRITE_ONLY_UNAPPROVED_SID_REJECTED'

    $composeExpected = Join-Path $fixtureRoot 'compose-data'
    $composeWrong = Join-Path $fixtureRoot 'wrong-data'
    $null = New-Item -ItemType Directory -Path $composeExpected
    $null = New-Item -ItemType Directory -Path $composeWrong
    Set-SyntheticProtectedAcl -Path $composeExpected
    Set-SyntheticProtectedAcl -Path $composeWrong
    $null = Assert-ThriveLensComposeDataDirectory -Path $composeExpected -ExpectedPath $composeExpected
    Assert-Condition $true 'COMPOSE_EXACT_EMPTY_DIRECTORY_ACCEPTED'
    Assert-ThrowsCode { Assert-ThriveLensComposeDataDirectory -Path $attributableRoot -ExpectedPath $composeExpected } `
        'COMPOSE_DATA_ROOT_FORBIDDEN' 'COMPOSE_ROOT_REJECTED'
    Assert-ThrowsCode { Assert-ThriveLensComposeDataDirectory -Path $composeWrong -ExpectedPath $composeExpected } `
        'COMPOSE_DATA_DIRECTORY_MISMATCH' 'COMPOSE_WRONG_DIRECTORY_REJECTED'

    $preseedPath = Join-Path $composeExpected 'PG_VERSION'
    [IO.File]::WriteAllText($preseedPath, 'unverified')
    Assert-ThrowsCode { Assert-ThriveLensComposeDataDirectory -Path $composeExpected -ExpectedPath $composeExpected } `
        'COMPOSE_DATA_DIRECTORY_NOT_EMPTY' 'COMPOSE_PRESEEDED_DIRECTORY_REJECTED'
    [IO.File]::Delete($preseedPath)

    Add-SyntheticEveryoneRight -Path $composeExpected -Right W
    Assert-ThrowsCode { Assert-ThriveLensComposeDataDirectory -Path $composeExpected -ExpectedPath $composeExpected } `
        'DIRECTORY_ACL_ALLOWLIST_VIOLATION' 'COMPOSE_DIRECTORY_ACL_REJECTED'

    $overlapSecret = Join-Path $composeExpected 'secret.txt'
    [IO.File]::WriteAllText($overlapSecret, 'synthetic-test-only')
    Assert-ThrowsCode { Assert-ThriveLensPathOutsideDirectory -DirectoryPath $composeExpected -OtherPath $overlapSecret } `
        'COMPOSE_SECRET_DATA_OVERLAP' 'COMPOSE_SECRET_OVERLAP_REJECTED'
    [IO.File]::Delete($overlapSecret)
    $externalSecret = Join-Path $fixtureRoot 'external-secret.txt'
    [IO.File]::WriteAllText($externalSecret, 'synthetic-test-only')
    $null = Assert-ThriveLensPathOutsideDirectory -DirectoryPath $composeExpected -OtherPath $externalSecret
    Assert-Condition $true 'COMPOSE_DISJOINT_SECRET_ACCEPTED'

    if ($failures.Count -gt 0) {
        $preliminaryResponse = [pscustomobject]@{ schema_version = 1; status = 'FAIL'; codes = @($failures) }
        $preliminaryExitCode = 1
    }
    else {
        $preliminaryResponse = [pscustomobject]@{ schema_version = 1; status = 'PASS'; assertions = $assertionCount }
        $preliminaryExitCode = 0
    }
}
catch {
    $preliminaryResponse = [pscustomobject]@{ schema_version = 1; status = 'ERROR'; code = 'SECURITY_CONTROL_TEST_INTERNAL_ERROR' }
    $preliminaryExitCode = 2
}
finally {
    $cleanupSucceeded = $true
    if ($null -ne $fixtureRoot -and (Test-Path -LiteralPath $fixtureRoot)) {
        try {
            $validatedFixtureRoot = Assert-ThriveLensOwnedPath -Path $fixtureRoot
            Remove-Item -LiteralPath $validatedFixtureRoot -Recurse -Force
            if (Test-Path -LiteralPath $validatedFixtureRoot) { throw 'FIXTURE_STILL_PRESENT' }
        }
        catch { $cleanupSucceeded = $false }
    }
}

$finalOutcome = Resolve-SecurityFixtureOutcome `
    -PreliminaryStatus ([string]$preliminaryResponse.status) `
    -PreliminaryExitCode $preliminaryExitCode `
    -CleanupSucceeded $cleanupSucceeded
if (-not $cleanupSucceeded) {
    $preliminaryResponse = [pscustomobject]@{
        schema_version = 1
        status = [string]$finalOutcome.Status
        code = [string]$finalOutcome.Code
    }
}
$preliminaryResponse | ConvertTo-Json -Compress
if ([int]$finalOutcome.ExitCode -ne 0) { exit ([int]$finalOutcome.ExitCode) }
