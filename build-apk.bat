@echo off
rem ============================================================
rem  LifeRestart Android (Tauri) APK build script
rem  Usage:  build-apk.bat [debug|release] [arch] [-y]
rem    arch: arm64 (default) | arm | x86 | x86_64 | all
rem    -y:   Auto-confirm dependency installation
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
if /i "%~3"=="-y" set "AUTO_CONFIRM=y"

rem ---- Environment setup ----
rem Adjust these paths if your installation differs
set "NODE_HOME=%LOCALAPPDATA%\Programs\node-v22.16.0-win-x64"
set "JAVA_HOME=%LOCALAPPDATA%\Programs\jdk-17.0.13+11"
set "ANDROID_HOME=%LOCALAPPDATA%\Android\Sdk"
set "NDK_VERSION=27.2.12479018"
set "NDK_HOME=%ANDROID_HOME%\ndk\%NDK_VERSION%"
set "PATH=%NODE_HOME%;%JAVA_HOME%\bin;%ANDROID_HOME%\cmdline-tools\latest\bin;%ANDROID_HOME%\platform-tools;%USERPROFILE%\.cargo\bin;%APPDATA%\npm;%PATH%"

rem Auto-detect installed JDK 17.x if hardcoded path is stale
if not exist "%JAVA_HOME%\bin\java.exe" (
    for /d %%d in ("%LOCALAPPDATA%\Programs\jdk-17*") do (
        if exist "%%d\bin\java.exe" (
            set "JAVA_HOME=%%d"
            set "PATH=%%d\bin;%PATH%"
        )
    )
)

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

rem Ensure Rust Android targets are installed
if "%TARGET_ARCH%"=="all" (
    rustup target add aarch64-linux-android armv7-linux-androideabi i686-linux-android x86_64-linux-android >nul 2>&1
) else (
    if "%TARGET_ARCH%"=="arm64"  rustup target add aarch64-linux-android >nul 2>&1
    if "%TARGET_ARCH%"=="arm"    rustup target add armv7-linux-androideabi >nul 2>&1
    if "%TARGET_ARCH%"=="x86"    rustup target add i686-linux-android >nul 2>&1
    if "%TARGET_ARCH%"=="x86_64" rustup target add x86_64-linux-android >nul 2>&1
)

rem ---- Auto-install missing dependencies ----
set "NEED_JDK=0"
set "NEED_SDK=0"
if not exist "%JAVA_HOME%\bin\java.exe" set "NEED_JDK=1"
if not exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" set "NEED_SDK=1"

if %NEED_JDK%==1 set NEED_SDK=1
set "DONE_INSTALL=0"

if %NEED_JDK%==1 if %NEED_SDK%==1 if %DONE_INSTALL%==0 (
    echo.
    echo Missing build dependencies:
    echo   - JDK 17   ^(not found at %JAVA_HOME%^)
    echo   - Android SDK  ^(not found at %ANDROID_HOME%^)
    echo.
    if not defined AUTO_CONFIRM (
        set /p "AUTO_INSTALL=Auto-download and install? [Y/n]: "
        if /i "!AUTO_INSTALL!"=="n" (
            echo Install manually, then re-run this script.
            exit /b 1
        )
    )
    call :install_jdk
    if errorlevel 1 goto :error
    call :install_android_sdk
    if errorlevel 1 goto :error
    set "DONE_INSTALL=1"
)

if %NEED_JDK%==1 if %DONE_INSTALL%==0 (
    echo.
    echo   JDK 17 not found at %JAVA_HOME%
    if not defined AUTO_CONFIRM (
        set /p "AUTO_INSTALL=Auto-download and install JDK 17? [Y/n]: "
        if /i "!AUTO_INSTALL!"=="n" (
            echo Install manually, then re-run this script.
            exit /b 1
        )
    )
    call :install_jdk
    if errorlevel 1 goto :error
    set "DONE_INSTALL=1"
)

if %NEED_SDK%==1 if %DONE_INSTALL%==0 (
    echo.
    echo   Android SDK not found at %ANDROID_HOME%
    if not defined AUTO_CONFIRM (
        set /p "AUTO_INSTALL=Auto-download and install Android SDK? [Y/n]: "
        if /i "!AUTO_INSTALL!"=="n" (
            echo Install manually, then re-run this script.
            exit /b 1
        )
    )
    call :install_android_sdk
    if errorlevel 1 goto :error
)

rem ---- Ensure SDK licenses and components are present ----
if exist "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" (
    if not exist "%ANDROID_HOME%\licenses\android-sdk-license" (
        echo   Accepting Android SDK licenses ...
        if not exist "%ANDROID_HOME%\licenses" mkdir "%ANDROID_HOME%\licenses"
        echo 24333f8a63b6825ea9c5514f83c2829b004d1fee> "%ANDROID_HOME%\licenses\android-sdk-license"
        echo 84831b9409646a918e30573bab4c9c91346d8abd> "%ANDROID_HOME%\licenses\android-sdk-preview-license"
    )
    if not exist "%ANDROID_HOME%\platform-tools\adb.exe" (
        echo   Installing SDK components ^(this may take a while^) ...
        call "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" "platform-tools" "build-tools;34.0.0" "platforms;android-34" --no_https
        if errorlevel 1 echo [WARN] SDK component install had issues.
    )
    if not exist "%NDK_HOME%\source.properties" (
        if exist "%NDK_HOME%" (
            echo   Removing incomplete NDK...
            rmdir /s /q "%NDK_HOME%" 2>nul
        )
        echo   Installing NDK %NDK_VERSION% ...
        call "%ANDROID_HOME%\cmdline-tools\latest\bin\sdkmanager.bat" "ndk;%NDK_VERSION%" --no_https
        if errorlevel 1 echo [WARN] NDK install had issues.
    )
)

echo ============================================
echo  LifeRestart APK Build  [%BUILD_MODE%] [%TARGET_ARCH%]
echo ============================================
echo.

rem ---- Auto-generate signing keystore if missing ----
set "SIGNING_DIR=%~dp0signing"
set "SIGNING_KEYSTORE=%SIGNING_DIR%\liferestart.keystore"
set "SIGNING_PROPS=%SIGNING_DIR%\keystore.properties"

if not exist "%SIGNING_KEYSTORE%" (
    echo   Generating signing keystore...
    if not exist "%SIGNING_DIR%" mkdir "%SIGNING_DIR%"
    keytool -genkeypair -keystore "%SIGNING_KEYSTORE%" -alias liferestart -keyalg RSA -keysize 2048 -validity 10000 -storepass lr2024sign -keypass lr2024sign -dname "CN=LifeRestart, OU=Dev, O=LifeRestart, L=Beijing, ST=Beijing, C=CN"
    if errorlevel 1 (
        echo [ERROR] Failed to generate signing keystore.
        goto :error
    )
    if not exist "%SIGNING_PROPS%" (
        echo storePassword=lr2024sign> "%SIGNING_PROPS%"
        echo keyAlias=liferestart>> "%SIGNING_PROPS%"
        echo keyPassword=lr2024sign>> "%SIGNING_PROPS%"
    )
    echo   Keystore generated: %SIGNING_KEYSTORE%
    echo   Credentials: %SIGNING_PROPS%
    echo   NOTE: Back up the signing/ directory! Losing it means you cannot update the APK.
    echo.
)

rem ---- Step 1: Build game data ----
echo [1/3] Building game data...
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
echo [2/3] Building frontend (vite)...
call pnpm --filter @remake/web build:tauri
if errorlevel 1 goto :error

rem ---- Ensure Tauri Android project is initialized ----
if not exist "apps\web\src-tauri\gen\android" (
    echo   Initializing Tauri Android project...
    call pnpm --filter @remake/web exec tauri android init
    if errorlevel 1 goto :error
)

rem ---- Configure Cargo linker for Android cross-compilation ----
set "NDK_TOOLCHAIN=%ANDROID_HOME%\ndk\%NDK_VERSION%\toolchains\llvm\prebuilt\windows-x86_64\bin"
set "NDK_TOOLCHAIN_FWD=%NDK_TOOLCHAIN:\=/%"
if not exist "apps\web\src-tauri\.cargo" mkdir "apps\web\src-tauri\.cargo"
(
echo [target.aarch64-linux-android]
echo linker = "%NDK_TOOLCHAIN_FWD%/clang.exe"
echo rustflags = ["-C", "link-arg=--target=aarch64-linux-android21"]
echo.
echo [target.armv7-linux-androideabi]
echo linker = "%NDK_TOOLCHAIN_FWD%/clang.exe"
echo rustflags = ["-C", "link-arg=--target=armv7a-linux-androideabi21"]
echo.
echo [target.i686-linux-android]
echo linker = "%NDK_TOOLCHAIN_FWD%/clang.exe"
echo rustflags = ["-C", "link-arg=--target=i686-linux-android21"]
echo.
echo [target.x86_64-linux-android]
echo linker = "%NDK_TOOLCHAIN_FWD%/clang.exe"
echo rustflags = ["-C", "link-arg=--target=x86_64-linux-android21"]
) > "apps\web\src-tauri\.cargo\config.toml"

rem ---- Step 3: Build APK via Tauri CLI ----
echo [3/3] Building APK with Tauri CLI...
set "TAURI_TARGET=aarch64"
if "%TARGET_ARCH%"=="arm"    set "TAURI_TARGET=armv7"
if "%TARGET_ARCH%"=="x86"    set "TAURI_TARGET=i686"
if "%TARGET_ARCH%"=="x86_64" set "TAURI_TARGET=x86_64"

set "TAURI_MODE="
if "%BUILD_MODE%"=="debug" set "TAURI_MODE=--debug"

rem Ensure Gradle uses the default user-home cache (not a stale subst path)
set "GRADLE_USER_HOME=%USERPROFILE%\.gradle"

if "%TARGET_ARCH%"=="all" (
    rem Remove buildArch so universal flavor is created
    powershell -NoProfile -Command "if (Test-Path 'apps\web\src-tauri\gen\android\gradle.properties') { (Get-Content 'apps\web\src-tauri\gen\android\gradle.properties') | Where-Object { $_ -notmatch '^buildArch=' } | Set-Content 'apps\web\src-tauri\gen\android\gradle.properties' }"
) else (
    rem Set buildArch in gradle.properties so RustPlugin creates only the target flavor
    set "GRADLE_ARCH=arm64"
    if "%TARGET_ARCH%"=="arm"    set "GRADLE_ARCH=arm"
    if "%TARGET_ARCH%"=="x86"    set "GRADLE_ARCH=x86"
    if "%TARGET_ARCH%"=="x86_64" set "GRADLE_ARCH=x86_64"
    powershell -NoProfile -Command "$f='apps\web\src-tauri\gen\android\gradle.properties'; $c=if(Test-Path $f){(Get-Content $f)|Where-Object{$_ -notmatch '^buildArch='}}else{@()}; $c+='buildArch=!GRADLE_ARCH!'; Set-Content $f $c"
)

rem Build with retry for Gradle transforms cache bug (Gradle #31438)
set "BUILD_RETRIES=30"
set "BUILD_RETRY=0"
:buildRetryLoop
set /a BUILD_RETRY+=1
if "%TARGET_ARCH%"=="all" (
    call pnpm --filter @remake/web exec tauri android build %TAURI_MODE% --target aarch64 armv7 i686 x86_64
) else (
    call pnpm --filter @remake/web exec tauri android build %TAURI_MODE% --target %TAURI_TARGET%
)
if not errorlevel 1 goto buildSuccess
if %BUILD_RETRY% geq %BUILD_RETRIES% goto :error

rem Fix Gradle cache atomic-move errors (Gradle #31438)
powershell -NoProfile -Command "$gh=$env:GRADLE_USER_HOME; if(-not $gh){$gh=\"$env:USERPROFILE\.gradle\"}; $cp=Join-Path $gh 'caches'; function Fix-Dir($p){if(Test-Path $p){Get-ChildItem -Path $p ^| Where-Object {$_.PSIsContainer -and $_.Name -match '^[a-f0-9]{32}-.+'} ^| ForEach-Object {$h=$_.Name.Substring(0,32); $d=Join-Path (Split-Path $p) $h; if(-not (Test-Path $d)){Rename-Item $_.FullName $h -EA SilentlyContinue; Write-Host \"  [retry] Fixed $h\"}}}}; if(Test-Path $cp){Get-ChildItem -Path $cp ^| Where-Object {$_.PSIsContainer} ^| ForEach-Object {Fix-Dir (Join-Path $_.FullName 'transforms'); Fix-Dir (Join-Path $_.FullName 'kotlin-dsl\scripts')}}"

echo   [build-retry] Attempt %BUILD_RETRY%/%BUILD_RETRIES% failed, retrying...
goto buildRetryLoop

:buildSuccess

rem ---- Collect artifacts ----
echo.
echo Build succeeded! APK output:
set "OUT=dist"
set "APK_DIR=apps\web\src-tauri\gen\android\app\build\outputs\apk"
if not exist "%OUT%" mkdir "%OUT%"
for /r "%APK_DIR%" %%f in (*.apk) do (
    copy /y "%%f" "%OUT%\" >nul
    echo   %%~nxf
)
endlocal
exit /b 0

rem ---- Auto-install subroutines ----
:install_jdk
echo.
echo ============================================
echo  Installing JDK 17 (Eclipse Temurin)
echo ============================================
set "JDK_URL=https://mirrors.tuna.tsinghua.edu.cn/Adoptium/17/jdk/x64/windows/OpenJDK17U-jdk_x64_windows_hotspot_17.0.20_8.zip"
set "JDK_ZIP=%TEMP%\liferestart-jdk17.zip"
set "JDK_DIR=%LOCALAPPDATA%\Programs"

echo   Downloading JDK 17 ...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%JDK_URL%','%JDK_ZIP%')"
if errorlevel 1 (
    echo [ERROR] JDK download failed. Check your network.
    exit /b 1
)

echo   Extracting ...
if not exist "%JDK_DIR%" mkdir "%JDK_DIR%"
powershell -NoProfile -Command "Expand-Archive -Path '%JDK_ZIP%' -DestinationPath '%JDK_DIR%' -Force"
if errorlevel 1 (
    echo [ERROR] JDK extraction failed.
    exit /b 1
)
del /q "%JDK_ZIP%" 2>nul

rem Find extracted directory (jdk-17.x.y+z)
set "JAVA_HOME="
for /d %%d in ("%JDK_DIR%\jdk-17*") do set "JAVA_HOME=%%d"
if not defined JAVA_HOME (
    echo [ERROR] JDK extracted but directory not found at %JDK_DIR%\jdk-17*
    exit /b 1
)

set "PATH=%JAVA_HOME%\bin;%PATH%"
setx JAVA_HOME "%JAVA_HOME%" >nul 2>&1
echo   JDK installed: !JAVA_HOME!

java -version 2>&1 | findstr /i "17" >nul
if errorlevel 1 (
    echo [WARN] java -version did not report 17. Verify installation.
)
exit /b 0

:install_android_sdk
echo.
echo ============================================
echo  Installing Android SDK
echo ============================================
set "CMDLINE_URL=https://dl.google.com/android/repository/commandlinetools-win-11076708_latest.zip"
set "CMDLINE_ZIP=%TEMP%\liferestart-android-cmdline.zip"
set "CMDLINE_DIR=%ANDROID_HOME%\cmdline-tools"

echo   Downloading Android command-line tools ...
powershell -NoProfile -Command "[Net.ServicePointManager]::SecurityProtocol=[Net.SecurityProtocolType]::Tls12; (New-Object System.Net.WebClient).DownloadFile('%CMDLINE_URL%','%CMDLINE_ZIP%')"
if errorlevel 1 (
    echo [ERROR] Android cmdline-tools download failed. Check your network.
    exit /b 1
)

echo   Extracting ...
if not exist "%CMDLINE_DIR%" mkdir "%CMDLINE_DIR%"
powershell -NoProfile -Command "Expand-Archive -Path '%CMDLINE_ZIP%' -DestinationPath '%CMDLINE_DIR%' -Force"
if errorlevel 1 (
    echo [ERROR] Android cmdline-tools extraction failed.
    exit /b 1
)
del /q "%CMDLINE_ZIP%" 2>nul

rem Rename extracted directory to latest/
if exist "%CMDLINE_DIR%\latest" rmdir /s /q "%CMDLINE_DIR%\latest" 2>nul
for /d %%d in ("%CMDLINE_DIR%\*-*") do (
    rename "%%d" latest
    goto :cmdline_renamed
)
for /d %%d in ("%CMDLINE_DIR%\cmdline-tools") do (
    rename "%%d" latest
    goto :cmdline_renamed
)
:cmdline_renamed

if not exist "%CMDLINE_DIR%\latest\bin\sdkmanager.bat" (
    echo [ERROR] sdkmanager.bat not found after extraction.
    exit /b 1
)

set "PATH=%CMDLINE_DIR%\latest\bin;%ANDROID_HOME%\platform-tools;%PATH%"
setx ANDROID_HOME "%ANDROID_HOME%" >nul 2>&1

echo   Accepting licenses ...
if not exist "%ANDROID_HOME%\licenses" mkdir "%ANDROID_HOME%\licenses"
echo 24333f8a63b6825ea9c5514f83c2829b004d1fee> "%ANDROID_HOME%\licenses\android-sdk-license"
echo 84831b9409646a918e30573bab4c9c91346d8abd> "%ANDROID_HOME%\licenses\android-sdk-preview-license"

echo   Installing SDK components (this may take a while) ...
call "%CMDLINE_DIR%\latest\bin\sdkmanager.bat" "platform-tools" "build-tools;34.0.0" "platforms;android-34" --no_https 2>nul
if errorlevel 1 (
    echo [WARN] SDK component install had issues. Continuing ...
)

echo   Installing NDK %NDK_VERSION% ...
call "%CMDLINE_DIR%\latest\bin\sdkmanager.bat" "ndk;%NDK_VERSION%" --no_https 2>nul
if errorlevel 1 (
    echo [WARN] NDK install had issues. You may need to install it manually.
)

echo   Android SDK installed: %ANDROID_HOME%
exit /b 0

:setup_env
rem Main auto-install entry point
echo.
echo ============================================
echo  Setting up build environment
echo ============================================

if %NEED_JDK%==1 (
    call :install_jdk
    if errorlevel 1 (
        echo [ERROR] JDK setup failed.
        exit /b 1
    )
)

if %NEED_SDK%==1 (
    call :install_android_sdk
    if errorlevel 1 (
        echo [ERROR] Android SDK setup failed.
        exit /b 1
    )
)

echo.
echo   Environment ready:
if defined JAVA_HOME     echo     JAVA_HOME     = %JAVA_HOME%
if defined ANDROID_HOME  echo     ANDROID_HOME  = %ANDROID_HOME%
if defined NDK_HOME      echo     NDK_HOME      = %NDK_HOME%
echo.
exit /b 0

:error
echo.
echo [ERROR] Build failed. Check the logs above.
endlocal
exit /b 1
