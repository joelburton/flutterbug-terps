@echo off
setlocal enabledelayedexpansion

rem Set up and build flutterbug-terps on a new Windows machine.
rem Run from anywhere; clones sibling repos next to this one.
rem Requires: git, cmake, cargo, and bash (Git for Windows) on PATH.

set "REPO_DIR=%~dp0"
rem Strip trailing backslash
if "%REPO_DIR:~-1%"=="\" set "REPO_DIR=%REPO_DIR:~0,-1%"
for %%D in ("%REPO_DIR%\..") do set "PARENT_DIR=%%~fD"

echo === Cloning sibling repos into %PARENT_DIR% ===

if exist "%PARENT_DIR%\garglk" (
    echo   garglk already exists, skipping
) else (
    git clone https://github.com/garglk/garglk "%PARENT_DIR%\garglk"
    if errorlevel 1 goto :fail
)

if exist "%PARENT_DIR%\remglk-rs" (
    echo   remglk-rs already exists, skipping
) else (
    git clone https://github.com/joelburton/remglk-rs "%PARENT_DIR%\remglk-rs"
    if errorlevel 1 goto :fail
    git -C "%PARENT_DIR%\remglk-rs" checkout fix-window-set-arrangement-reentrant-lock
    if errorlevel 1 goto :fail
)

if exist "%PARENT_DIR%\games" (
    echo   games already exists, skipping
) else (
    git clone https://github.com/joelburton/flutterbug-terps-games "%PARENT_DIR%\games"
    if errorlevel 1 goto :fail
)

echo.
echo === Building ===
cmake -B "%REPO_DIR%\build" -S "%REPO_DIR%"
if errorlevel 1 goto :fail
cmake --build "%REPO_DIR%\build" -j
if errorlevel 1 goto :fail

echo.
echo === Testing ===
bash "%REPO_DIR%\tests\smoke.sh"
if errorlevel 1 goto :fail

echo.
echo All done.
exit /b 0

:fail
echo.
echo Setup failed.
exit /b 1
