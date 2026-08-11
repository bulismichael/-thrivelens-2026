#Requires -Version 7.0

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ThriveLensProjectRoot {
    $root = Join-Path $PSScriptRoot '..\..\..'
    return (Resolve-Path -LiteralPath $root).Path
}

function Get-ThriveLensManifest {
    $manifestPath = Join-Path (Get-ThriveLensProjectRoot) 'config\toolchains\backend.json'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw 'BACKEND_MANIFEST_UNAVAILABLE'
    }
    try {
        return Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    }
    catch {
        throw 'BACKEND_MANIFEST_INVALID'
    }
}

function Get-ThriveLensAttributableRoot {
    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        throw 'LOCALAPPDATA_UNAVAILABLE'
    }
    $root = [IO.Path]::GetFullPath((Join-Path $env:LOCALAPPDATA 'ThriveLens'))
    $volumeRoot = [IO.Path]::GetPathRoot($root)
    if ([string]::IsNullOrWhiteSpace($volumeRoot) -or $root.TrimEnd('\') -ieq $volumeRoot.TrimEnd('\')) {
        throw 'ATTRIBUTABLE_ROOT_UNSAFE'
    }
    return $root.TrimEnd('\')
}

function Assert-ThriveLensOwnedPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [switch]$AllowMissing
    )

    $root = Get-ThriveLensAttributableRoot
    $candidate = [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd('\')
    $prefix = $root + [IO.Path]::DirectorySeparatorChar
    if (-not $candidate.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'PATH_OUTSIDE_ATTRIBUTABLE_ROOT'
    }

    $relative = [IO.Path]::GetRelativePath($root, $candidate)
    $cursor = $root
    foreach ($segment in $relative.Split([IO.Path]::DirectorySeparatorChar, [StringSplitOptions]::RemoveEmptyEntries)) {
        $cursor = Join-Path $cursor $segment
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'REPARSE_PATH_REJECTED'
            }
        }
        elseif (-not $AllowMissing) {
            throw 'REQUIRED_PATH_UNAVAILABLE'
        }
    }
    return $candidate
}

function Get-ThriveLensPostgresPaths {
    $manifest = Get-ThriveLensManifest
    $binaryRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.binary_root) -AllowMissing
    $dataRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.data_root) -AllowMissing
    $logRoot = Assert-ThriveLensOwnedPath -Path ([string]$manifest.postgresql.log_root) -AllowMissing
    return [pscustomobject]@{
        BinaryRoot = $binaryRoot
        DataRoot = $dataRoot
        LogRoot = $logRoot
        PgCtl = Join-Path $binaryRoot 'bin\pg_ctl.exe'
        InitDb = Join-Path $binaryRoot 'bin\initdb.exe'
        Postgres = Join-Path $binaryRoot 'bin\postgres.exe'
        PgIsReady = Join-Path $binaryRoot 'bin\pg_isready.exe'
        Port = [int]$manifest.postgresql.port
        ListenAddress = [string]$manifest.postgresql.listen_address
    }
}

function Get-ThriveLensFreeMemoryBytes {
    if (-not $IsWindows) {
        throw 'WINDOWS_HOST_REQUIRED'
    }
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        return [int64]$os.FreePhysicalMemory * 1KB
    }
    catch {
        throw 'MEMORY_MEASUREMENT_UNAVAILABLE'
    }
}

function Get-ThriveLensResourcePhase {
    $configPath = Join-Path (Get-ThriveLensProjectRoot) 'config\resource-budget.json'
    try {
        $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
        return [string]$config.phase
    }
    catch {
        throw 'RESOURCE_CONFIG_INVALID'
    }
}

function Invoke-ThriveLensResourceGate {
    $scriptPath = Join-Path (Get-ThriveLensProjectRoot) 'scripts\check_resource_budget.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw 'RESOURCE_GATE_UNAVAILABLE'
    }
    $null = & pwsh -NoProfile -File $scriptPath 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw 'RESOURCE_GATE_FAILED'
    }
}

function Test-ThriveLensPostgresRunning {
    $paths = Get-ThriveLensPostgresPaths
    if (-not (Test-Path -LiteralPath $paths.PgCtl -PathType Leaf) -or
        -not (Test-Path -LiteralPath (Join-Path $paths.DataRoot 'PG_VERSION') -PathType Leaf)) {
        return $false
    }
    $null = & $paths.PgCtl status '-D' $paths.DataRoot 2>&1
    return $LASTEXITCODE -eq 0
}

function Assert-ThriveLensLoopbackListener {
    $paths = Get-ThriveLensPostgresPaths
    $listeners = @(Get-NetTCPConnection -State Listen -LocalPort $paths.Port -ErrorAction SilentlyContinue)
    if ($listeners.Count -eq 0) {
        throw 'POSTGRES_LISTENER_UNAVAILABLE'
    }
    foreach ($listener in $listeners) {
        if ([string]$listener.LocalAddress -cne '127.0.0.1') {
            throw 'POSTGRES_NON_LOOPBACK_LISTENER'
        }
    }
}

Export-ModuleMember -Function @(
    'Get-ThriveLensProjectRoot',
    'Get-ThriveLensManifest',
    'Get-ThriveLensAttributableRoot',
    'Assert-ThriveLensOwnedPath',
    'Get-ThriveLensPostgresPaths',
    'Get-ThriveLensFreeMemoryBytes',
    'Get-ThriveLensResourcePhase',
    'Invoke-ThriveLensResourceGate',
    'Test-ThriveLensPostgresRunning',
    'Assert-ThriveLensLoopbackListener'
)
