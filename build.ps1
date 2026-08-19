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

# ---- Environment setup ----
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

# ---- Step 1: Build game data ----
Write-Host "[1/3] Building game data..." -ForegroundColor Cyan
if (Test-Path 'packages\data\dist\achievement.ts') {
    Write-Host '  > Data already built, skipping...'
} else {
    & pnpm build:data
    if ($LASTEXITCODE -ne 0) {
        Write-Error "[ERROR] Game data build failed."
        exit 1
    }
}

# ---- Step 2: Build desktop app ----
Write-Host "[2/3] Building desktop app (portable, no bundle)..." -ForegroundColor Cyan
& pnpm --filter @remake/web exec tauri build --no-bundle
if ($LASTEXITCODE -ne 0) {
    Write-Error "[ERROR] Tauri build failed."
    exit 1
}

# ---- Step 3: Collect artifacts ----
Write-Host "[3/3] Collecting artifacts to dist\ ..." -ForegroundColor Cyan
$releaseDir = Join-Path $PSScriptRoot "apps\web\src-tauri\target\release"
$exePath = Join-Path $releaseDir "liferestart-desktop.exe"

if (-not (Test-Path $exePath)) {
    Write-Error "[ERROR] Artifact not found: $exePath"
    exit 1
}

$outDir = Join-Path $PSScriptRoot "dist"
if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $outDir | Out-Null

Copy-Item $exePath $outDir -Force

Write-Host "`nBuild succeeded. Artifacts:" -ForegroundColor Green
Get-ChildItem $outDir | ForEach-Object { Write-Host "  $($_.Name)" }
exit 0
