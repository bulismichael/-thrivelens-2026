[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ExpectedRedHarness.psm1') -Force

$temporaryBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$temporaryRoot = Join-Path $temporaryBase ("thrivelens-r0-harness-" + [guid]::NewGuid().ToString('N'))
[void](New-Item -ItemType Directory -Path $temporaryRoot)

$groups = 0

function Assert-Passes {
    param([Parameter(Mandatory)] [scriptblock] $Action, [Parameter(Mandatory)] [string] $Label)
    try {
        & $Action | Out-Null
    }
    catch {
        throw "Harness self-test expected PASS for $Label but failed: $($_.Exception.Message)"
    }
    $script:groups++
}

function Assert-Fails {
    param([Parameter(Mandatory)] [scriptblock] $Action, [Parameter(Mandatory)] [string] $Label)
    $failed = $false
    try {
        & $Action | Out-Null
    }
    catch {
        $failed = $true
    }
    if (-not $failed) {
        throw "Harness self-test expected rejection for $Label."
    }
    $script:groups++
}

function Assert-ProcessGone {
    param(
        [Parameter(Mandatory)] [string] $PidPath,
        [Parameter(Mandatory)] [string] $Label
    )
    if (-not (Test-Path -LiteralPath $PidPath)) {
        throw "Harness self-test fixture did not publish a child PID for $Label."
    }
    $processId = [int](Get-Content -LiteralPath $PidPath -Raw)
    $deadline = [System.Diagnostics.Stopwatch]::StartNew()
    while ($deadline.ElapsedMilliseconds -lt 1000) {
        $child = $null
        try {
            $child = [System.Diagnostics.Process]::GetProcessById($processId)
            if ($child.HasExited) {
                $child.Dispose()
                return
            }
        }
        catch {
            return
        }
        finally {
            if ($null -ne $child) { $child.Dispose() }
        }
        [System.Threading.Thread]::Sleep(10)
    }
    throw "Harness containment left a live child for $Label."
}

function New-FixtureEntry {
    param(
        [Parameter(Mandatory)] [string] $Id,
        [Parameter(Mandatory)] [string] $Owner,
        [Parameter(Mandatory)] [string] $Mode,
        [Parameter(Mandatory)] [string] $ClassName,
        [int] $Timeout = 5,
        [string[]] $ExtraArguments = @()
    )
    $marker = "THRIVELENS_MISSING_IMPLEMENTATION::$Id"
    $argv = @('python', $script:runnerPath, $Mode, $ClassName, $marker) + @($ExtraArguments)
    return [ordered]@{
        id = $Id
        owner = $Owner
        working_directory = '.'
        argv = $argv
        timeout_seconds = $Timeout
        test_ids = @("__main__.$ClassName.test_case")
        expected_missing_behavior_marker = $marker
        future_green_command = "pwsh -NoProfile -File scripts/contracts/assert_expected_green.ps1 -Manifest fixture.json -Owner $Owner"
    }
}

try {
    $script:runnerPath = Join-Path $temporaryRoot 'fixture runner.py'
    $runnerSource = @'
import os
import subprocess
import sys
import time
import unittest

mode = sys.argv[1]
class_name = sys.argv[2]
marker = sys.argv[3]

def spawn_pipe_holder(pid_path):
    child = subprocess.Popen(
        [sys.executable, "-c", "import time; time.sleep(8)"],
    )
    with open(pid_path, "w", encoding="ascii") as handle:
        handle.write(str(child.pid))
    return child

if mode in ("kill_failure", "child_holds_pipe"):
    spawn_pipe_holder(sys.argv[4])

if mode != "no_collection":
    def test_case(self):
        if mode == "red":
            self.fail(marker)
        if mode == "green":
            return
        if mode == "canary_output":
            print("TL_SENSITIVE_CANARY_7F3A")
            return
        if mode == "wrong":
            self.fail("WRONG_ASSERTION")
        if mode == "assert_true":
            self.assertTrue(False, marker)
        if mode == "skip":
            self.skipTest("not allowed")
        if mode == "timeout":
            time.sleep(3)
            return
        if mode == "over_cap":
            sys.stdout.buffer.write(b"X" * 40000)
            sys.stdout.buffer.flush()
            sys.stderr.buffer.write(b"Y" * 40000)
            sys.stderr.buffer.flush()
            time.sleep(3)
            self.fail(marker)
        if mode == "kill_failure":
            time.sleep(8)
            return
        if mode == "child_holds_pipe":
            return
        if mode == "import_error":
            __import__("thrivelens_fixture_module_that_does_not_exist")
        if mode == "spoof":
            print("AssertionError: " + marker)
            self.fail("WRONG_ASSERTION")
        if mode == "injection":
            self.assertEqual(sys.argv[4], "value with spaces & | ; $()")
            return
        if mode == "touch":
            with open(sys.argv[4], "w", encoding="utf-8") as handle:
                handle.write("executed")
            return
        self.fail("UNKNOWN_FIXTURE_MODE")

    if mode == "expected_failure":
        test_case = unittest.expectedFailure(test_case)
    globals()[class_name] = type(class_name, (unittest.TestCase,), {"test_case": test_case})

unittest.main(argv=[sys.argv[0]], verbosity=2)
'@
    Set-Content -LiteralPath $script:runnerPath -Value $runnerSource -Encoding UTF8 -NoNewline

    $red = New-FixtureEntry -Id 'TL-R0-900-EXPECTED-RED' -Owner 'TL-R0-900' -Mode 'red' -ClassName 'ExpectedRedCase'
    Assert-Passes { Invoke-ExpectedRedEntries -Entries @($red) } 'one collected explicit missing-implementation assertion'

    $green = New-FixtureEntry -Id 'TL-R0-900-GREEN' -Owner 'TL-R0-900' -Mode 'green' -ClassName 'GreenCase'
    Assert-Passes { Invoke-ExpectedGreenEntries -Entries @($green) -Owner 'TL-R0-900' } 'one collected green test'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($green) } 'unexpected red pass'

    $canaryOutput = New-FixtureEntry -Id 'TL-R0-900-CANARY-OUTPUT' -Owner 'TL-R0-900' -Mode 'canary_output' -ClassName 'CanaryOutputCase'
    Assert-Fails { Invoke-ExpectedGreenEntries -Entries @($canaryOutput) -Owner 'TL-R0-900' } 'contract canary in green process output'

    $unreleasedPath = Join-Path $temporaryRoot 'assignment-failure-target-ran.txt'
    $unreleased = New-FixtureEntry -Id 'TL-R0-900-ASSIGNMENT-FAILURE' -Owner 'TL-R0-900' -Mode 'touch' -ClassName 'AssignmentFailureCase' -ExtraArguments @($unreleasedPath)
    Assert-Fails {
        Invoke-ExpectedGreenEntries -Entries @($unreleased) -Owner 'TL-R0-900' -AssignmentHook { throw 'simulated assignment failure' }
    } 'assignment failure never releases target argv'
    if (Test-Path -LiteralPath $unreleasedPath) {
        throw 'Supervisor released target argv after containment assignment failed.'
    }

    $wrong = New-FixtureEntry -Id 'TL-R0-900-WRONG-RED' -Owner 'TL-R0-900' -Mode 'wrong' -ClassName 'WrongCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($wrong) } 'wrong assertion failure'

    $assertTrue = New-FixtureEntry -Id 'TL-R0-900-ASSERT-TRUE' -Owner 'TL-R0-900' -Mode 'assert_true' -ClassName 'AssertTrueCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($assertTrue) } 'assertTrue-formatted marker rather than exact explicit assertion'

    $spoof = New-FixtureEntry -Id 'TL-R0-900-SPOOFED-MARKER' -Owner 'TL-R0-900' -Mode 'spoof' -ClassName 'SpoofCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($spoof) } 'marker printed outside the actual assertion'

    $noCollection = New-FixtureEntry -Id 'TL-R0-900-NO-COLLECTION' -Owner 'TL-R0-900' -Mode 'no_collection' -ClassName 'MissingCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($noCollection) } 'zero collected tests'
    Assert-Fails { Invoke-ExpectedGreenEntries -Entries @($noCollection) -Owner 'TL-R0-900' } 'zero collected tests hidden behind a green process'

    $skip = New-FixtureEntry -Id 'TL-R0-900-SKIP' -Owner 'TL-R0-900' -Mode 'skip' -ClassName 'SkipCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($skip) } 'skipped test'

    $expectedFailure = New-FixtureEntry -Id 'TL-R0-900-EXPECTED-FAILURE' -Owner 'TL-R0-900' -Mode 'expected_failure' -ClassName 'ExpectedFailureCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($expectedFailure) } 'unittest expectedFailure escape hatch'

    $importError = New-FixtureEntry -Id 'TL-R0-900-IMPORT-ERROR' -Owner 'TL-R0-900' -Mode 'import_error' -ClassName 'ImportErrorCase'
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($importError) } 'import failure'

    $syntaxPath = Join-Path $temporaryRoot 'syntax-error.py'
    Set-Content -LiteralPath $syntaxPath -Value 'def broken(:' -Encoding UTF8 -NoNewline
    $syntaxError = New-FixtureEntry -Id 'TL-R0-900-SYNTAX-ERROR' -Owner 'TL-R0-900' -Mode 'red' -ClassName 'SyntaxErrorCase'
    $syntaxError.argv = @('python', $syntaxPath)
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($syntaxError) } 'syntax failure'

    $missingTool = New-FixtureEntry -Id 'TL-R0-900-MISSING-TOOL' -Owner 'TL-R0-900' -Mode 'red' -ClassName 'MissingToolCase'
    $missingTool.argv = @('python', (Join-Path $temporaryRoot 'missing runner.py'))
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($missingTool) } 'missing test runner file'

    $timeout = New-FixtureEntry -Id 'TL-R0-900-TIMEOUT' -Owner 'TL-R0-900' -Mode 'timeout' -ClassName 'TimeoutCase' -Timeout 1
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($timeout) } 'timeout cleanup'

    $overCap = New-FixtureEntry -Id 'TL-R0-900-OUTPUT-CAP' -Owner 'TL-R0-900' -Mode 'over_cap' -ClassName 'OutputCapCase' -Timeout 5
    $overCapStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Assert-Fails { Invoke-ExpectedRedEntries -Entries @($overCap) } 'strict combined output byte cap'
    $overCapStopwatch.Stop()
    if ($overCapStopwatch.ElapsedMilliseconds -ge 5000) {
        throw 'Output-cap rejection did not terminate within the bounded deadline.'
    }

    $killFailurePidPath = Join-Path $temporaryRoot 'kill-failure-child.pid'
    $killFailure = New-FixtureEntry -Id 'TL-R0-900-KILL-FAILURE' -Owner 'TL-R0-900' -Mode 'kill_failure' -ClassName 'KillFailureCase' -Timeout 1 -ExtraArguments @($killFailurePidPath)
    $killFailureHook = { throw 'simulated process-tree termination failure before termination' }
    $killFailureStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Assert-Fails {
        Invoke-ExpectedRedEntries -Entries @($killFailure) -TerminationHook $killFailureHook
    } 'primary kill failure is contained without awaiting pending output reads'
    $killFailureStopwatch.Stop()
    if ($killFailureStopwatch.ElapsedMilliseconds -ge 5000) {
        throw 'Termination-failure rejection exceeded the bounded deadline.'
    }
    Assert-ProcessGone -PidPath $killFailurePidPath -Label 'primary kill failure'

    $heldPipePidPath = Join-Path $temporaryRoot 'held-pipe-child.pid'
    $heldPipe = New-FixtureEntry -Id 'TL-R0-900-HELD-PIPE' -Owner 'TL-R0-900' -Mode 'child_holds_pipe' -ClassName 'HeldPipeCase' -Timeout 5 -ExtraArguments @($heldPipePidPath)
    Assert-Fails {
        Invoke-ExpectedGreenEntries -Entries @($heldPipe) -Owner 'TL-R0-900'
    } 'parent exit with a descendant holding redirected pipes'
    Assert-ProcessGone -PidPath $heldPipePidPath -Label 'post-parent-exit held pipe'

    $unsafePidPath = Join-Path $temporaryRoot 'unsafe-containment-child.pid'
    $unsafeEntry = New-FixtureEntry -Id 'TL-R0-903-UNSAFE-CONTAINMENT' -Owner 'TL-R0-903' -Mode 'child_holds_pipe' -ClassName 'UnsafeContainmentCase' -Timeout 5 -ExtraArguments @($unsafePidPath)
    $unsafeLaterPath = Join-Path $temporaryRoot 'unsafe-later-entry-ran.txt'
    $unsafeLater = New-FixtureEntry -Id 'TL-R0-903-LATER' -Owner 'TL-R0-903' -Mode 'touch' -ClassName 'UnsafeLaterCase' -ExtraArguments @($unsafeLaterPath)
    Assert-Fails {
        Invoke-ExpectedGreenEntries -Entries @($unsafeEntry, $unsafeLater) -Owner 'TL-R0-903' -ContainmentResultHook { return $false }
    } 'unsafe termination aborts remaining owner entries'
    Assert-ProcessGone -PidPath $unsafePidPath -Label 'reported unsafe containment'
    if (Test-Path -LiteralPath $unsafeLaterPath) {
        throw 'Expected-green continued after an unsafe termination result.'
    }

    $quoted = New-FixtureEntry -Id 'TL-R0-900-ARGV-QUOTING' -Owner 'TL-R0-900' -Mode 'injection' -ClassName 'QuotedCase' -ExtraArguments @('value with spaces & | ; $()')
    Assert-Passes { Invoke-ExpectedGreenEntries -Entries @($quoted) -Owner 'TL-R0-900' } 'argument-array quoting without shell evaluation'

    $touchPath = Join-Path $temporaryRoot 'later-entry-ran.txt'
    $partialPass = New-FixtureEntry -Id 'TL-R0-901-PARTIAL-PASS' -Owner 'TL-R0-901' -Mode 'touch' -ClassName 'PartialPassCase' -ExtraArguments @($touchPath)
    $partialFail = New-FixtureEntry -Id 'TL-R0-901-PARTIAL-FAIL' -Owner 'TL-R0-901' -Mode 'wrong' -ClassName 'PartialFailCase'
    Assert-Fails {
        Invoke-ExpectedGreenEntries -Entries @($partialFail, $partialPass) -Owner 'TL-R0-901'
    } 'partial owner green result'
    if (-not (Test-Path -LiteralPath $touchPath)) {
        throw 'Expected-green did not continue through every owner entry after a failure.'
    }

    Assert-Fails {
        Invoke-ExpectedGreenEntries -Entries @($green) -Owner 'TL-R0-999'
    } 'unknown or empty green owner'

    $manifestPath = Join-Path $temporaryRoot 'duplicate-manifest.json'
    $duplicateManifest = [ordered]@{
        schema_version = 1
        entries = @($red, $red)
    } | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $manifestPath -Value $duplicateManifest -Encoding UTF8 -NoNewline
    Assert-Fails { Read-ExpectedRedManifest -ManifestPath $manifestPath } 'duplicate manifest ID'

    $inline = New-FixtureEntry -Id 'TL-R0-902-INLINE-PYTHON' -Owner 'TL-R0-902' -Mode 'red' -ClassName 'InlineCase'
    $inline.argv = @('python', '-c', 'raise SystemExit(1)')
    $inlineManifestPath = Join-Path $temporaryRoot 'inline-manifest.json'
    $inlineManifest = [ordered]@{ schema_version = 1; entries = @($inline) } | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $inlineManifestPath -Value $inlineManifest -Encoding UTF8 -NoNewline
    Assert-Fails { Read-ExpectedRedManifest -ManifestPath $inlineManifestPath } 'alternate python -c manifest'

    $alternateManifestPath = Join-Path $temporaryRoot 'alternate-valid-shape.json'
    $alternateManifest = [ordered]@{ schema_version = 1; entries = @($red) } | ConvertTo-Json -Depth 12
    Set-Content -LiteralPath $alternateManifestPath -Value $alternateManifest -Encoding UTF8 -NoNewline
    Assert-Passes {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'assert_expected_red.ps1') -Manifest $alternateManifestPath 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'Alternate manifest unexpectedly executed.'
        }
    } 'canonical manifest path binding'
    Assert-Passes {
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'assert_expected_green.ps1') -Manifest $alternateManifestPath -Owner 'TL-R0-900' 2>$null | Out-Null
        if ($LASTEXITCODE -eq 0) {
            throw 'Alternate manifest unexpectedly executed through green harness.'
        }
    } 'canonical green manifest path binding'

    Write-Output "TL-R0-002 expected-red harness self-test PASS: $groups adversarial groups."
}
finally {
    $resolvedTemporary = [System.IO.Path]::GetFullPath($temporaryRoot)
    if (-not $resolvedTemporary.StartsWith($temporaryBase, [System.StringComparison]::OrdinalIgnoreCase) -or
        $resolvedTemporary -eq $temporaryBase) {
        throw 'Refusing to remove an unexpected harness temporary path.'
    }
    if (Test-Path -LiteralPath $resolvedTemporary) {
        Remove-Item -LiteralPath $resolvedTemporary -Recurse -Force
    }
}
