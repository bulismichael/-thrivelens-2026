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

try {
    Import-Module -Name $modulePath -Force
    $attributableRoot = Get-ThriveLensAttributableRoot
    $fixtureParent = Assert-ThriveLensOwnedPath -Path (Join-Path $attributableRoot 'test-temp') -AllowMissing
    $fixtureRoot = Assert-ThriveLensOwnedPath -Path (Join-Path $fixtureParent ('security-' + [guid]::NewGuid().ToString('N'))) -AllowMissing
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force

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

    $childFatal = Resolve-ThriveLensStartChildFailure `
        -ExitCode 3 `
        -OutputText '{"status":"ERROR","code":"POSTGRES_START_CLEANUP_FAILED"}'
    Assert-Condition ($childFatal.Code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and $childFatal.ExitCode -eq 3) `
        'START_CHILD_CLEANUP_FATAL_PRESERVED'
    $childUnknownFatal = Resolve-ThriveLensStartChildFailure -ExitCode 3 -OutputText 'malformed'
    Assert-Condition ($childUnknownFatal.Code -ceq 'RUNTIME_START_CHILD_FATAL' -and $childUnknownFatal.ExitCode -eq 3) `
        'START_CHILD_UNKNOWN_FATAL_PRESERVED'
    $childOrdinary = Resolve-ThriveLensStartChildFailure -ExitCode 2 -OutputText 'blocked'
    Assert-Condition ($childOrdinary.Code -ceq 'RUNTIME_START_PROBE_FAILED' -and $childOrdinary.ExitCode -eq 2) `
        'START_CHILD_ORDINARY_FAILURE_CLASSIFIED'

    $fatalCleanupOk = Resolve-ThriveLensRuntimeFailureOutcome `
        -OriginalCode POSTGRES_START_CLEANUP_FAILED -OriginalExitCode 3 `
        -StartInvoked $true -CleanupAttempted $true -CleanupExitCode 0 -AbsenceVerified $true
    Assert-Condition (
        $fatalCleanupOk.Code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and
        $fatalCleanupOk.ExitCode -eq 3 -and $fatalCleanupOk.CleanupVerified
    ) 'START_FATAL_NOT_DOWNGRADED_AFTER_CLEANUP'
    $fatalCleanupBad = Resolve-ThriveLensRuntimeFailureOutcome `
        -OriginalCode POSTGRES_START_CLEANUP_FAILED -OriginalExitCode 3 `
        -StartInvoked $true -CleanupAttempted $true -CleanupExitCode 2 -AbsenceVerified $false
    Assert-Condition (
        $fatalCleanupBad.Code -ceq 'POSTGRES_START_CLEANUP_FAILED' -and
        $fatalCleanupBad.ExitCode -eq 3 -and -not $fatalCleanupBad.CleanupVerified
    ) 'START_FATAL_NOT_DOWNGRADED_WHEN_CLEANUP_FAILS'
    $ordinaryCleanupOk = Resolve-ThriveLensRuntimeFailureOutcome `
        -OriginalCode RUNTIME_START_PROBE_FAILED -OriginalExitCode 2 `
        -StartInvoked $true -CleanupAttempted $true -CleanupExitCode 0 -AbsenceVerified $true
    Assert-Condition ($ordinaryCleanupOk.ExitCode -eq 2 -and $ordinaryCleanupOk.CleanupVerified) `
        'NONZERO_START_REQUIRES_VERIFIED_CLEANUP'
    $ordinaryCleanupMissing = Resolve-ThriveLensRuntimeFailureOutcome `
        -OriginalCode RUNTIME_START_PROBE_FAILED -OriginalExitCode 2 `
        -StartInvoked $true -CleanupAttempted $false -CleanupExitCode 0 -AbsenceVerified $false
    Assert-Condition (
        $ordinaryCleanupMissing.Code -ceq 'RUNTIME_CLEANUP_FAILED' -and
        $ordinaryCleanupMissing.ExitCode -eq 3
    ) 'MISSING_START_CLEANUP_ESCALATES'

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
