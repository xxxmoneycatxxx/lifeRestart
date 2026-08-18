@echo off
rem ============================================================
rem  LifeRestart Desktop (Tauri) build script
rem  Usage:  build.bat
rem  Output: dist\ [portable exe, no installation needed]
rem ============================================================
setlocal
cd /d "%~dp0"

where pnpm >nul 2>&1
if errorlevel 1 (
    echo [ERROR] pnpm not found. Install it first: npm i -g pnpm
    exit /b 1
)

echo [1/3] Building desktop app (portable, no bundle)...
call pnpm build:data
if errorlevel 1 goto :error
call pnpm --filter @remake/web exec tauri build --no-bundle
if errorlevel 1 goto :error

echo [2/3] Collecting artifacts to dist\ ...
set "OUT=dist"
set "RELEASE=apps\web\src-tauri\target\release"

if not exist "%RELEASE%\liferestart-desktop.exe" (
    echo [ERROR] Artifact not found: %RELEASE%\liferestart-desktop.exe
    goto :error
)

if exist "%OUT%" rd /s /q "%OUT%"
mkdir "%OUT%"

copy /y "%RELEASE%\liferestart-desktop.exe" "%OUT%\" >nul
if errorlevel 1 goto :error

echo [3/3] Build succeeded. Artifacts:
dir /b "%OUT%"
endlocal
exit /b 0

:error
echo.
echo [ERROR] Build failed. Check the logs above.
endlocal
exit /b 1
