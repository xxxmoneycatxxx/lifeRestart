#Requires -Version 5.1
<#
.SYNOPSIS
    LifeRestart Desktop (Tauri) build script
.DESCRIPTION
    Builds the desktop application as a portable executable.
    Output: dist\liferestart-desktop.exe
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

# ---- Timing helper ----
$script:timings = @()
function Start-StepTimer {
    $script:stepWatch = [System.Diagnostics.Stopwatch]::StartNew()
}
function Stop-StepTimer {
    param([string]$Name)
    $script:stepWatch.Stop()
    $elapsed = $script:stepWatch.Elapsed
    $script:timings += [pscustomobject]@{
        Step     = $Name
        Duration = '{0:mm\:ss\.ff}' -f $elapsed
        Seconds  = $elapsed.TotalSeconds
    }
    Write-Host "  Done in $('{0:mm\:ss\.ff}' -f $elapsed)." -ForegroundColor DarkGray
    $script:stepWatch = $null
}

$totalWatch = [System.Diagnostics.Stopwatch]::StartNew()

# ---- Environment setup ----
Write-Host "[Setup] Configuring environment..." -ForegroundColor Cyan
$nodeHome = Join-Path $env:LOCALAPPDATA 'Programs\node-v22.16.0-win-x64'
if (Test-Path (Join-Path $nodeHome 'node.exe')) {
    $env:NODE_HOME = $nodeHome
    $env:PATH = "$nodeHome;$env:PATH"
}

# ---- Pre-flight checks ----
if (-not (Get-Command pnpm -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] pnpm not found. Install it first: npm i -g pnpm"
    exit 1
}
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Error "[ERROR] cargo not found. Install Rust toolchain first."
    exit 1
}

# ---- Step 1: Build game data ----
Write-Host "`n[1/3] Building game data..." -ForegroundColor Cyan
Start-StepTimer
$dataSrcDir = Join-Path $PSScriptRoot 'packages\data\src'
$dataOutFile = Join-Path $PSScriptRoot 'packages\data\dist\achievement.ts'
$srcNewest = if (Test-Path $dataSrcDir) {
    (Get-ChildItem $dataSrcDir -Recurse -File | Sort-Object LastWriteTime -Descending | Select-Object -First 1).LastWriteTime
} else { [datetime]::MaxValue }
$outOldest = if (Test-Path $dataOutFile) {
    (Get-Item $dataOutFile).LastWriteTime
} else { [datetime]::MinValue }

if ($srcNewest -lt $outOldest) {
    Write-Host '  > Data up-to-date, skipping...'
} else {
    & pnpm build:data
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Game data build failed."
        exit 1
    }
}
Stop-StepTimer -Name '1. Build game data'

# ---- Step 2: Build desktop app ----
Write-Host "`n[2/3] Building desktop app (portable, no bundle)..." -ForegroundColor Cyan
Start-StepTimer
& pnpm --filter @remake/web exec tauri build --no-bundle
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] Tauri build failed."
    exit 1
}
Stop-StepTimer -Name '2. Tauri build'

# ---- Step 3: Collect artifacts ----
Write-Host "`n[3/3] Collecting artifacts to dist\ ..." -ForegroundColor Cyan
Start-StepTimer
$releaseDir = Join-Path $PSScriptRoot "apps\web\src-tauri\target\release"
$exePath = Join-Path $releaseDir "liferestart-desktop.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "[ERROR] Artifact not found: $exePath"
    exit 1
}

$outDir = Join-Path $PSScriptRoot "dist"
if (-not (Test-Path $outDir)) {
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
}

Copy-Item $exePath $outDir -Force
Stop-StepTimer -Name '3. Collect artifacts'

# ---- Summary ----
$totalWatch.Stop()
$totalElapsed = $totalWatch.Elapsed

Write-Host "`n========================================" -ForegroundColor Green
Write-Host " Build succeeded!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host "`nArtifacts:" -ForegroundColor Cyan
Get-ChildItem $outDir | ForEach-Object { Write-Host "  $($_.Name)  ($([math]::Round($_.Length / 1MB, 2)) MB)" }

Write-Host "`nTime breakdown:" -ForegroundColor Cyan
foreach ($t in $script:timings) {
    Write-Host ("  {0,-25} {1}" -f $t.Step, $t.Duration)
}
Write-Host ("  {0,-25} {1}" -f 'Total', ('{0:mm\:ss\.ff}' -f $totalElapsed)) -ForegroundColor Yellow
exit 0
