#Requires -Version 5.1
<#
.SYNOPSIS
    LifeRestart Android (Tauri) APK build script
.DESCRIPTION
    Builds Android APK via Cargo + Gradle (bypasses Tauri CLI symlink issues on Windows).
    Usage:  .\build-apk.ps1 [-BuildMode debug|release] [-Arch arm64|arm|x86|x86_64|all] [-AutoConfirm]
    Arguments can be in any order.
    Output: dist\*.apk
#>
[CmdletBinding()]
param(
    [ValidateSet('debug', 'release')]
    [string]$BuildMode = 'release',

    [ValidateSet('arm64', 'arm', 'x86', 'x86_64', 'all')]
    [string]$Arch = 'arm64',

    [Alias('y')]
    [switch]$AutoConfirm
)

$ErrorActionPreference = 'Continue'
Set-Location $PSScriptRoot

# ============================================================
#  Architecture mappings
# ============================================================
$ArchMap = @{
    'arm64'   = @{ RustTriple = 'aarch64-linux-android';   JniDir = 'arm64-v8a';    GradleName = 'Arm64' }
    'arm'     = @{ RustTriple = 'armv7-linux-androideabi';  JniDir = 'armeabi-v7a';  GradleName = 'Arm' }
    'x86'     = @{ RustTriple = 'i686-linux-android';       JniDir = 'x86';          GradleName = 'X86' }
    'x86_64'  = @{ RustTriple = 'x86_64-linux-android';     JniDir = 'x86_64';       GradleName = 'X86_64' }
}
$AllTriples = @('aarch64-linux-android', 'armv7-linux-androideabi', 'i686-linux-android', 'x86_64-linux-android')

# ============================================================
#  Environment setup — adjust these paths if your installation differs
# ============================================================
$env:NODE_HOME    = Join-Path $env:LOCALAPPDATA 'Programs\node-v22.16.0-win-x64'
$env:JAVA_HOME    = Join-Path $env:LOCALAPPDATA 'Programs\jdk-17.0.13+11'
$env:ANDROID_HOME = Join-Path $env:LOCALAPPDATA 'Android\Sdk'
$NDK_VERSION      = '27.2.12479018'
$env:NDK_HOME     = Join-Path $env:ANDROID_HOME "ndk\$NDK_VERSION"
$env:GRADLE_USER_HOME = Join-Path $env:USERPROFILE '.gradle'

$pathsToAdd = @(
    $env:NODE_HOME,
    (Join-Path $env:JAVA_HOME 'bin'),
    (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin'),
    (Join-Path $env:ANDROID_HOME 'platform-tools'),
    (Join-Path $env:USERPROFILE '.cargo\bin'),
    (Join-Path $env:APPDATA 'npm')
)
$env:PATH = ($pathsToAdd + $env:PATH -join ';')

# Auto-detect JDK 17 if hardcoded path is stale
if (-not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))) {
    $found = Get-ChildItem (Join-Path $env:LOCALAPPDATA 'Programs') -Directory -Filter 'jdk-17*' -ErrorAction SilentlyContinue |
             Where-Object { Test-Path (Join-Path $_.FullName 'bin\java.exe') } |
             Select-Object -First 1
    if ($found) {
        $env:JAVA_HOME = $found.FullName
        $env:PATH = "$(Join-Path $env:JAVA_HOME 'bin');$env:PATH"
    }
}

# ============================================================
#  Pre-flight checks
# ============================================================
function Assert-Command {
    param([string]$Name, [string]$InstallHint)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        Write-Error "[ERROR] $Name not found. $InstallHint"
        exit 1
    }
}
Assert-Command node   'Install Node.js 22+ first.'
Assert-Command pnpm  'Install it first: npm i -g pnpm'
Assert-Command cargo 'Install Rust first: https://rustup.rs'

# Ensure Rust Android targets are installed
$targetTriples = if ($Arch -eq 'all') { $AllTriples } else { $ArchMap[$Arch].RustTriple }
foreach ($triple in $targetTriples) {
    & rustup target add $triple 2>&1 | Out-Null
}

# ============================================================
#  Auto-install missing dependencies
# ============================================================
$needJdk = -not (Test-Path (Join-Path $env:JAVA_HOME 'bin\java.exe'))
$needSdk = -not (Test-Path (Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin\sdkmanager.bat'))
if ($needJdk) { $needSdk = $true }

function Confirm-Install {
    param([string]$What)
    if ($AutoConfirm) { return }
    $ans = Read-Host "  Auto-download and install $What? [Y/n]"
    if ($ans -eq 'n') { Write-Error 'Install manually, then re-run this script.'; exit 1 }
}

function Install-Jdk {
    Write-Host "`n============================================" -ForegroundColor Yellow
    Write-Host " Installing JDK 17 (Eclipse Temurin)" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow
    $url = 'https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20_8.zip'
    $zip = Join-Path $env:TEMP 'liferestart-jdk17.zip'
    $dir = Join-Path $env:LOCALAPPDATA 'Programs'

    Write-Host '  Downloading JDK 17 ...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($url, $zip)
    if (-not (Test-Path $zip)) { Write-Error 'JDK download failed.'; exit 1 }

    Write-Host '  Extracting ...'
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    Expand-Archive -Path $zip -DestinationPath $dir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    $jdkDir = Get-ChildItem $dir -Directory -Filter 'jdk-17*' | Select-Object -First 1
    if (-not $jdkDir) { Write-Error 'JDK extracted but directory not found.'; exit 1 }
    $env:JAVA_HOME = $jdkDir.FullName
    $env:PATH = "$(Join-Path $env:JAVA_HOME 'bin');$env:PATH"
    Write-Host "  JDK installed: $($env:JAVA_HOME)" -ForegroundColor Green
}

function Install-AndroidSdk {
    Write-Host "`n============================================" -ForegroundColor Yellow
    Write-Host " Installing Android SDK" -ForegroundColor Yellow
    Write-Host "============================================" -ForegroundColor Yellow
    $url = 'https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip'
    $zip = Join-Path $env:TEMP 'liferestart-android-cmdline.zip'
    $cmdDir = Join-Path $env:ANDROID_HOME 'cmdline-tools'

    Write-Host '  Downloading Android command-line tools ...'
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    (New-Object System.Net.WebClient).DownloadFile($url, $zip)

    Write-Host '  Extracting ...'
    if (-not (Test-Path $cmdDir)) { New-Item -ItemType Directory -Path $cmdDir -Force | Out-Null }
    Expand-Archive -Path $zip -DestinationPath $cmdDir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    # Rename extracted directory to latest/
    $latestDir = Join-Path $cmdDir 'latest'
    if (Test-Path $latestDir) { Remove-Item $latestDir -Recurse -Force }
    $extracted = Get-ChildItem $cmdDir -Directory | Where-Object { $_.Name -match '-' } | Select-Object -First 1
    if (-not $extracted) { $extracted = Get-ChildItem $cmdDir -Directory -Filter 'cmdline-tools' | Select-Object -First 1 }
    if ($extracted) { Rename-Item $extracted.FullName 'latest' }

    $env:PATH = "$(Join-Path $cmdDir 'latest\bin');$(Join-Path $env:ANDROID_HOME 'platform-tools');$env:PATH"

    # Accept licenses
    $licDir = Join-Path $env:ANDROID_HOME 'licenses'
    if (-not (Test-Path $licDir)) { New-Item -ItemType Directory -Path $licDir -Force | Out-Null }
    '24333f8a63b6825ea9c5514f83c2829b004d1fee' | Set-Content (Join-Path $licDir 'android-sdk-license')
    '84831b9409646a918e30573bab4c9c91346d8abd' | Set-Content (Join-Path $licDir 'android-sdk-preview-license')

    $sdkMgr = Join-Path $cmdDir 'latest\bin\sdkmanager.bat'
    Write-Host '  Installing SDK components ...'
    & $sdkMgr 'platform-tools' 'build-tools;34.0.0' 'platforms;android-34' --no_https 2>&1 | Out-Null

    Write-Host "  Installing NDK $NDK_VERSION ..."
    & $sdkMgr "ndk;$NDK_VERSION" --no_https 2>&1 | Out-Null
    Write-Host "  Android SDK installed: $env:ANDROID_HOME" -ForegroundColor Green
}

if ($needJdk -and $needSdk) {
    Write-Host "`nMissing build dependencies:" -ForegroundColor Red
    Write-Host "  - JDK 17   (not found at $env:JAVA_HOME)"
    Write-Host "  - Android SDK (not found at $env:ANDROID_HOME)"
    Confirm-Install 'JDK 17 + Android SDK'
    Install-Jdk; Install-AndroidSdk
} elseif ($needJdk) {
    Write-Host "`n  JDK 17 not found at $env:JAVA_HOME" -ForegroundColor Red
    Confirm-Install 'JDK 17'
    Install-Jdk
} elseif ($needSdk) {
    Write-Host "`n  Android SDK not found at $env:ANDROID_HOME" -ForegroundColor Red
    Confirm-Install 'Android SDK'
    Install-AndroidSdk
}

# Ensure SDK licenses and components
$sdkMgr = Join-Path $env:ANDROID_HOME 'cmdline-tools\latest\bin\sdkmanager.bat'
if (Test-Path $sdkMgr) {
    $licFile = Join-Path $env:ANDROID_HOME 'licenses\android-sdk-license'
    if (-not (Test-Path $licFile)) {
        Write-Host '  Accepting Android SDK licenses ...'
        $licDir = Join-Path $env:ANDROID_HOME 'licenses'
        if (-not (Test-Path $licDir)) { New-Item -ItemType Directory -Path $licDir -Force | Out-Null }
        '24333f8a63b6825ea9c5514f83c2829b004d1fee' | Set-Content $licFile
        '84831b9409646a918e30573bab4c9c91346d8abd' | Set-Content (Join-Path $env:ANDROID_HOME 'licenses\android-sdk-preview-license')
    }
    if (-not (Test-Path (Join-Path $env:ANDROID_HOME 'platform-tools\adb.exe'))) {
        Write-Host '  Installing SDK components ...'
        & $sdkMgr 'platform-tools' 'build-tools;34.0.0' 'platforms;android-34' --no_https 2>&1 | Out-Null
    }
    if (-not (Test-Path (Join-Path $env:NDK_HOME 'source.properties'))) {
        if (Test-Path $env:NDK_HOME) { Remove-Item $env:NDK_HOME -Recurse -Force -ErrorAction SilentlyContinue }
        Write-Host "  Installing NDK $NDK_VERSION ..."
        & $sdkMgr "ndk;$NDK_VERSION" --no_https 2>&1 | Out-Null
    }
}

# ============================================================
#  Banner
# ============================================================
Write-Host '============================================' -ForegroundColor Cyan
Write-Host " LifeRestart APK Build  [$BuildMode] [$Arch]" -ForegroundColor Cyan
Write-Host '============================================' -ForegroundColor Cyan

# ============================================================
#  Signing keystore
# ============================================================
$signingDir = Join-Path $PSScriptRoot 'signing'
$keystore   = Join-Path $signingDir 'liferestart.keystore'
$signProps  = Join-Path $signingDir 'keystore.properties'
$androidKeyProps = Join-Path $PSScriptRoot 'apps\web\src-tauri\gen\android\app\key.properties'

if (-not (Test-Path $keystore)) {
    Write-Host '  Generating signing keystore...'
    if (-not (Test-Path $signingDir)) { New-Item -ItemType Directory -Path $signingDir -Force | Out-Null }
    & keytool -genkeypair -keystore $keystore -alias liferestart -keyalg RSA -keysize 2048 `
        -validity 10000 -storepass lr2024sign -keypass lr2024sign `
        -dname 'CN=LifeRestart, OU=Dev, O=LifeRestart, L=Beijing, ST=Beijing, C=CN'
    if ($LASTEXITCODE -ne 0) { Write-Error 'Failed to generate signing keystore.'; exit 1 }
    if (-not (Test-Path $signProps)) {
        @('storePassword=lr2024sign', 'keyAlias=liferestart', 'keyPassword=lr2024sign') | Set-Content $signProps
    }
    Write-Host "  Keystore generated: $keystore" -ForegroundColor Green
    Write-Host '  NOTE: Back up the signing/ directory! Losing it means you cannot update the APK.'
}

# Sync Android project's key.properties
Write-Host '  Syncing Android project signing config...'
$resolved = Resolve-Path $keystore -ErrorAction SilentlyContinue
$ksAbs = if ($resolved) { $resolved.Path } else { $keystore }
@(
    "storePassword=lr2024sign",
    "keyAlias=liferestart",
    "keyPassword=lr2024sign",
    "storeFile=$ksAbs"
) | Set-Content $androidKeyProps

# ============================================================
#  Step 1: Build game data
# ============================================================
Write-Host "`n[1/3] Building game data..." -ForegroundColor Cyan
if (Test-Path 'packages\data\dist\achievement.ts') {
    Write-Host '  > Data already built, skipping...'
} else {
    & pnpm build:data
    if ($LASTEXITCODE -ne 0) {
        Write-Host '  > Retrying with vt directly...'
        Push-Location 'packages\data'
        try {
            if (-not (Test-Path 'node_modules\.bin\vt.cmd')) { & npm install v-transform --no-save }
            & node_modules\.bin\vt.cmd transform -t ts -w src -d dist '**\*.xlsx' --map
            if ($LASTEXITCODE -ne 0) { Write-Error 'Data build retry failed.'; exit 1 }
        } finally { Pop-Location }
    }
}

# ============================================================
#  Step 2: Build frontend
# ============================================================
Write-Host "[2/3] Building frontend (vite)..." -ForegroundColor Cyan
& pnpm --filter @remake/web build:tauri
if ($LASTEXITCODE -ne 0) { Write-Error 'Frontend build failed.'; exit 1 }

# Ensure Tauri Android project is initialized
if (-not (Test-Path 'apps\web\src-tauri\gen\android')) {
    Write-Host '  Initializing Tauri Android project...'
    & pnpm --filter @remake/web exec tauri android init
    if ($LASTEXITCODE -ne 0) { Write-Error 'Tauri android init failed.'; exit 1 }
}

# ============================================================
#  Configure Cargo linker for Android cross-compilation
# ============================================================
$ndkToolchain = (Join-Path $env:ANDROID_HOME "ndk\$NDK_VERSION\toolchains\llvm\prebuilt\windows-x86_64\bin") -replace '\\', '/'
$cargoConfigDir = Join-Path $PSScriptRoot 'apps\web\src-tauri\.cargo'
if (-not (Test-Path $cargoConfigDir)) { New-Item -ItemType Directory -Path $cargoConfigDir -Force | Out-Null }

$cargoConfig = @"
[target.aarch64-linux-android]
linker = "$ndkToolchain/clang.exe"
rustflags = ["-C", "link-arg=--target=aarch64-linux-android21"]

[target.armv7-linux-androideabi]
linker = "$ndkToolchain/clang.exe"
rustflags = ["-C", "link-arg=--target=armv7a-linux-androideabi21"]

[target.i686-linux-android]
linker = "$ndkToolchain/clang.exe"
rustflags = ["-C", "link-arg=--target=i686-linux-android21"]

[target.x86_64-linux-android]
linker = "$ndkToolchain/clang.exe"
rustflags = ["-C", "link-arg=--target=x86_64-linux-android21"]
"@
Set-Content (Join-Path $cargoConfigDir 'config.toml') $cargoConfig

# ============================================================
#  Step 3: Compile Rust + Build APK via Gradle
# ============================================================
Write-Host "[3/3] Building APK..." -ForegroundColor Cyan

$cargoDir  = if ($BuildMode -eq 'debug') { 'debug' } else { 'release' }
$modeFlag  = if ($BuildMode -eq 'release') { '--release' } else { '' }
$gradleTask = if ($BuildMode -eq 'debug') { 'assembleDebug' } else { 'assembleRelease' }

$jniLibs = Join-Path $PSScriptRoot 'apps\web\src-tauri\gen\android\app\src\main\jniLibs'
$srcTauri = Join-Path $PSScriptRoot 'apps\web\src-tauri'

# ---- 3a: Compile Rust for Android target(s) ----
if ($Arch -eq 'all') {
    Write-Host '  Compiling Rust for all Android architectures...'
    foreach ($triple in $AllTriples) {
        Write-Host "    [cargo] $triple ..."
        Push-Location $srcTauri
        try {
            $cargoArgs = @('build', '--lib', '--target', $triple)
            if ($modeFlag) { $cargoArgs += $modeFlag }
            & cargo @cargoArgs
            if ($LASTEXITCODE -ne 0) { Write-Error "Cargo build failed for $triple"; exit 1 }
        } finally { Pop-Location }
    }
    # Copy all .so files to jniLibs
    $abiMap = @{ 'aarch64-linux-android' = 'arm64-v8a'; 'armv7-linux-androideabi' = 'armeabi-v7a'; 'i686-linux-android' = 'x86'; 'x86_64-linux-android' = 'x86_64' }
    foreach ($entry in $abiMap.GetEnumerator()) {
        $destDir = Join-Path $jniLibs $entry.Value
        if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
        $src = Join-Path $srcTauri "target\$($entry.Key)\$cargoDir\libliferestart_desktop_lib.so"
        Copy-Item $src $destDir -Force
    }
} else {
    $info = $ArchMap[$Arch]
    Write-Host "  Compiling Rust for $($info.RustTriple)..."
    Push-Location $srcTauri
    try {
        $cargoArgs = @('build', '--lib', '--target', $info.RustTriple)
        if ($modeFlag) { $cargoArgs += $modeFlag }
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) { Write-Error 'Cargo build failed.'; exit 1 }
    } finally { Pop-Location }
    $destDir = Join-Path $jniLibs $info.JniDir
    if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    $src = Join-Path $srcTauri "target\$($info.RustTriple)\$cargoDir\libliferestart_desktop_lib.so"
    Copy-Item $src $destDir -Force
}

# ---- 3b: Build APK via Gradle (bypasses Tauri CLI symlink step) ----
# Exclude ALL Rust plugin tasks (we already compiled + copied .so manually)
$rustExclude = @()
foreach ($name in @('Arm64', 'Arm', 'X86', 'X86_64')) {
    $rustExclude += '-x'; $rustExclude += "rustBuild${name}Debug"
    if ($BuildMode -eq 'release') {
        $rustExclude += '-x'; $rustExclude += "rustBuild${name}Release"
    }
}

$androidDir = Join-Path $PSScriptRoot 'apps\web\src-tauri\gen\android'
$maxRetries = 5

for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
    Write-Host "  Gradle $gradleTask (attempt $attempt/$maxRetries)..."
    Push-Location $androidDir
    try {
        $gradleArgs = @($gradleTask) + $rustExclude
        & cmd /c "gradlew.bat $gradleArgs"
        if ($LASTEXITCODE -eq 0) { break }
    } finally { Pop-Location }

    if ($attempt -ge $maxRetries) {
        Write-Error "[ERROR] Build failed after $maxRetries attempts."
        exit 1
    }

    # Fix Gradle transforms cache atomic-move errors (Gradle #31438)
    Write-Host '  [retry] Fixing Gradle cache...'
    $gradleHome = $env:GRADLE_USER_HOME
    if (-not $gradleHome) { $gradleHome = Join-Path $env:USERPROFILE '.gradle' }
    $cachesDir = Join-Path $gradleHome 'caches'
    if (Test-Path $cachesDir) {
        Get-ChildItem $cachesDir -Directory | ForEach-Object {
            foreach ($sub in @('transforms', 'kotlin-dsl\scripts')) {
                $dir = Join-Path $_.FullName $sub
                if (Test-Path $dir) {
                    Get-ChildItem $dir -Directory |
                        Where-Object { $_.Name -match '^[a-f0-9]{32}-.+' } |
                        ForEach-Object {
                            $hash = $_.Name.Substring(0, 32)
                            $dest = Join-Path (Split-Path $dir) $hash
                            if (-not (Test-Path $dest)) {
                                Rename-Item $_.FullName $hash -ErrorAction SilentlyContinue
                                Write-Host "    Fixed $hash"
                            }
                        }
                }
            }
        }
    }
    Write-Host "  [build-retry] Attempt $attempt/$maxRetries failed, retrying..."
}

# ============================================================
#  Collect artifacts
# ============================================================
Write-Host "`nBuild succeeded! APK output:" -ForegroundColor Green
$outDir = Join-Path $PSScriptRoot 'dist'
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }
$apkDir = Join-Path $PSScriptRoot 'apps\web\src-tauri\gen\android\app\build\outputs\apk'
Get-ChildItem $apkDir -Recurse -Filter '*.apk' | ForEach-Object {
    Copy-Item $_.FullName $outDir -Force
    Write-Host "  $($_.Name)"
}
exit 0
