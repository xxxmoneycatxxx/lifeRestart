@echo off
rem ============================================================
rem  LifeRestart Android (Tauri) APK build script
rem  Usage:  build-apk.bat [debug|release] [arch]
rem    arch: arm64 (default) | arm | x86 | x86_64 | all
rem  Output: dist\*.apk
rem ============================================================
setlocal enabledelayedexpansion
cd /d "%~dp0"

rem ---- Build mode (default: release) ----
set "BUILD_MODE=release"
if /i "%~1"=="debug" set "BUILD_MODE=debug"
if /i "%~1"=="release" set "BUILD_MODE=release"

rem ---- Target arch (default: arm64) ----
set "TARGET_ARCH=arm64"
if /i "%~2"=="arm64"   set "TARGET_ARCH=arm64"
if /i "%~2"=="arm"     set "TARGET_ARCH=arm"
if /i "%~2"=="x86"     set "TARGET_ARCH=x86"
if /i "%~2"=="x86_64"  set "TARGET_ARCH=x86_64"
if /i "%~2"=="all"     set "TARGET_ARCH=all"

rem ---- Environment setup ----
rem Adjust these paths if your installation differs
set "NODE_HOME=%LOCALAPPDATA%\Programs\node-v22.16.0-win-x64"
set "JAVA_HOME=%LOCALAPPDATA%\Programs\jdk-17.0.13+11"
set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
set "NDK_HOME=%ANDROID_HOME%\ndk\27.2.12479018"
set "PATH=%NODE_HOME%;%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%USERPROFILE%\.cargo\bin;%APPDATA%\npm;%PATH%"

rem ---- Pre-flight checks ----
where node >nul 2>&1
if errorlevel 1 (
    echo [ERROR] node not found. Install Node.js 22+ first.
    exit /b 1
)
where pnpm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] pnpm not found. Install it first: npm i -g pnpm
    exit /b 1
)
where cargo >nul 2>&1
if errorlevel 1 (
    echo [ERROR] cargo not found. Install Rust first: https://rustup.rs
    exit /b 1
)
if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
    echo [ERROR] Android SDK not found at %ANDROID_HOME%
    echo         Install Android SDK or adjust ANDROID_HOME in this script.
    exit /b 1
)
if not exist "%NDK_HOME%" (
    echo [ERROR] Android NDK not found at %NDK_HOME%
    echo         Install NDK or adjust NDK_HOME in this script.
    exit /b 1
)
if not exist "%JAVA_HOME%\bin\java.exe" (
    echo [ERROR] JDK not found at %JAVA_HOME%
    echo         Install JDK 17+ or adjust JAVA_HOME in this script.
    exit /b 1
)

echo ============================================
echo  LifeRestart APK Build  [%BUILD_MODE%] [%TARGET_ARCH%]
echo ============================================
echo.

rem ---- Step 1: Build game data ----
echo [1/5] Building game data...
if exist "packages\data\dist\achievement.ts" (
    echo   ^> Data already built, skipping...
) else (
    call pnpm build:data
    if errorlevel 1 (
        echo   ^> Retrying with vt directly...
        pushd packages\data
        if not exist "node_modules\.bin\vt.cmd" (
            call npm install v-transform --no-save
        )
        call node_modules\.bin\vt.cmd transform -t ts -w src -d dist "**\*.xlsx" --map
        if errorlevel 1 (
            popd
            goto :error
        )
        popd
    )
)

rem ---- Step 2: Build frontend ----
echo [2/5] Building frontend (vite)...
call pnpm --filter @remake/web build:tauri
if errorlevel 1 goto :error

rem ---- Step 3: Compile Rust for Android ----
echo [3/5] Compiling Rust for Android...
set "CARGO_MODE=--release"
if "%BUILD_MODE%"=="debug" set "CARGO_MODE="

if "%TARGET_ARCH%"=="all" (
    call :build_rust aarch64-linux-android arm64
    if errorlevel 1 goto :error
    call :build_rust armv7-linux-androideabi arm
    if errorlevel 1 goto :error
    call :build_rust i686-linux-android x86
    if errorlevel 1 goto :error
    call :build_rust x86_64-linux-android x86_64
    if errorlevel 1 goto :error
) else if "%TARGET_ARCH%"=="arm64" (
    call :build_rust aarch64-linux-android arm64
) else if "%TARGET_ARCH%"=="arm" (
    call :build_rust armv7-linux-androideabi arm
) else if "%TARGET_ARCH%"=="x86" (
    call :build_rust i686-linux-android x86
) else if "%TARGET_ARCH%"=="x86_64" (
    call :build_rust x86_64-linux-android x86_64
)
if errorlevel 1 goto :error

rem ---- Step 4: Copy .so to jniLibs & run Gradle ----
echo [4/5] Packaging APK with Gradle...
set "JNI_DIR=apps\web\src-tauri\gen\android\app\src\main\jniLibs"

if "%TARGET_ARCH%"=="all" (
    call :copy_so aarch64-linux-android arm64
    call :copy_so armv7-linux-androideabi arm
    call :copy_so i686-linux-android x86
    call :copy_so x86_64-linux-android x86_64
) else if "%TARGET_ARCH%"=="arm64" (
    call :copy_so aarch64-linux-android arm64
) else if "%TARGET_ARCH%"=="arm" (
    call :copy_so armv7-linux-androideabi arm
) else if "%TARGET_ARCH%"=="x86" (
    call :copy_so i686-linux-android x86
) else if "%TARGET_ARCH%"=="x86_64" (
    call :copy_so x86_64-linux-android x86_64
)

set "GRADLE_TASK=assembleUniversalRelease"
if "%BUILD_MODE%"=="debug" set "GRADLE_TASK=assembleUniversalDebug"

pushd apps\web\src-tauri\gen\android
call gradlew.bat %GRADLE_TASK% -x rustBuildUniversalRelease -x rustBuildArm64Release -x rustBuildArmRelease -x rustBuildX86Release -x rustBuildX86_64Release -x rustBuildUniversalDebug -x rustBuildArm64Debug -x rustBuildArmDebug -x rustBuildX86Debug -x rustBuildX86_64Debug
if errorlevel 1 (
    popd
    goto :error
)
popd

rem ---- Step 5: Collect artifacts ----
echo [5/5] Collecting APK to dist\ ...
set "OUT=dist"
set "APK_DIR=apps\web\src-tauri\gen\android\app\build\outputs\apk"

if "%BUILD_MODE%"=="release" (
    set "APK_SRC=%APK_DIR%\universal\release"
) else (
    set "APK_SRC=%APK_DIR%\universal\debug"
)

if not exist "%APK_SRC%" (
    echo [ERROR] APK output not found in %APK_DIR%
    goto :error
)

if not exist "%OUT%" mkdir "%OUT%"
copy /y "%APK_SRC%\*.apk" "%OUT%\" >nul
if errorlevel 1 goto :error

echo.
echo Build succeeded! APK output:
dir /b "%OUT%\*.apk" 2>nul
if errorlevel 1 (
    echo [WARN] No .apk files found in %OUT%
    goto :error
)
endlocal
exit /b 0

rem ---- Subroutines ----
:build_rust
rem %1 = rust target, %2 = short name
echo   ^> Building %2 (%1)...
pushd apps\web\src-tauri
cargo build --lib --target %1 %CARGO_MODE%
if errorlevel 1 (
    popd
    exit /b 1
)
popd
exit /b 0

:copy_so
rem %1 = rust target, %2 = android abi
set "SO_SRC=apps\web\src-tauri\target\%1\%BUILD_MODE%\libliferestart_desktop_lib.so"
set "SO_DST=%JNI_DIR%\%2"
if not exist "%SO_DST%" mkdir "%SO_DST%"
copy /y "%SO_SRC%" "%SO_DST%\" >nul
echo   ^> Copied .so for %2
exit /b 0

:error
echo.
echo [ERROR] Build failed. Check the logs above.
endlocal
exit /b 1
