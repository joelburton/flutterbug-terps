@echo off
setlocal enabledelayedexpansion

rem Set up and build flutterbug-terps on a new Windows machine.
rem
rem Tooling required (install ahead of this script):
rem   - git, cmake, cargo, bash (Git for Windows) on PATH
rem   - Visual Studio 2019/2022 Build Tools or Community with the
rem     "Desktop development with C++" workload (provides MSVC headers,
rem     link.exe, libs, vcvars64.bat, and a bundled ninja.exe).
rem   - LLVM (https://releases.llvm.org/) installed at C:\Program Files\LLVM
rem     OR the VS "C++ Clang tools for Windows" component (clang-cl).
rem
rem Why clang-cl: four of the bundled gargoyle terps (alan3, scott, tads,
rem plus) won't compile under MSVC. They use C99 VLAs, GCC-style
rem __attribute__((packed)), and assume <stdalign.h>. clang-cl accepts
rem all three while still producing MSVC-ABI binaries that link against
rem the same UCRT.

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
echo === Locating Visual Studio ===

set "VSWHERE=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer\vswhere.exe"
if not exist "%VSWHERE%" (
    echo ERROR: vswhere.exe not found at "%VSWHERE%".
    echo Install Visual Studio 2019/2022 Build Tools or Community.
    goto :fail
)

rem Delayed expansion via setlocal enabledelayedexpansion above so we can
rem use exclamation-style references inside if-blocks without the "(x86)"
rem in the VS install path closing the block early.
set "VSDIR="
for /f "usebackq tokens=*" %%I in (`"%VSWHERE%" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath`) do set "VSDIR=%%I"
if not defined VSDIR goto :no_vs
echo   VS install: !VSDIR!

set "VCVARS=!VSDIR!\VC\Auxiliary\Build\vcvars64.bat"
if not exist "!VCVARS!" goto :no_vcvars

set "CLANGCL_DIR="
if exist "C:\Program Files\LLVM\bin\clang-cl.exe" set "CLANGCL_DIR=C:\Program Files\LLVM\bin"
if not defined CLANGCL_DIR if exist "!VSDIR!\VC\Tools\Llvm\x64\bin\clang-cl.exe" set "CLANGCL_DIR=!VSDIR!\VC\Tools\Llvm\x64\bin"
if not defined CLANGCL_DIR goto :no_clang
echo   clang-cl:   !CLANGCL_DIR!

set "NINJA_DIR=!VSDIR!\Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja"
if not exist "!NINJA_DIR!\ninja.exe" set "NINJA_DIR="

echo.
echo === Building (Ninja + clang-cl inside VS dev env) ===

rem vcvars64.bat needs vswhere on PATH itself
set "PATH=%ProgramFiles(x86)%\Microsoft Visual Studio\Installer;%PATH%"
call "%VCVARS%" >nul
if errorlevel 1 goto :fail

if defined NINJA_DIR set "PATH=%NINJA_DIR%;%PATH%"
set "PATH=%CLANGCL_DIR%;%PATH%"
set "CC=clang-cl"
set "CXX=clang-cl"

rem Note: on Windows there is no system zlib, so the cmake configure step
rem below will FetchContent madler/zlib v1.3.1 and build it from source for
rem the scare terp. This needs git on PATH (already required above).
cmake -B "%REPO_DIR%\build" -S "%REPO_DIR%" -G Ninja
if errorlevel 1 goto :fail
cmake --build "%REPO_DIR%\build"
if errorlevel 1 goto :fail

echo.
echo === Testing ===
rem PATH usually puts WSL's bash (System32) ahead of git-bash. WSL bash
rem won't auto-resolve foo -> foo.exe and uses /mnt/c paths, so all the
rem terps come out SKIP. Use git-bash explicitly.
set "GIT_BASH="
if exist "%ProgramFiles%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles%\Git\bin\bash.exe"
if not defined GIT_BASH if exist "%ProgramFiles(x86)%\Git\bin\bash.exe" set "GIT_BASH=%ProgramFiles(x86)%\Git\bin\bash.exe"
if not defined GIT_BASH (
    echo WARNING: git-bash not found; skipping smoke tests.
    echo Run them manually with: bash tests/smoke.sh
    goto :done
)

rem git-bash on Windows does not understand C:\... or C:/... in argv;
rem cd into the repo first so we can invoke smoke.sh with a relative path.
pushd "%REPO_DIR%"
"%GIT_BASH%" tests/smoke.sh
set "SMOKE_RC=!errorlevel!"
popd
if not "!SMOKE_RC!"=="0" goto :fail

:done

echo.
echo All done.
exit /b 0

:no_vs
echo ERROR: no VS install with the C++ toolchain found.
echo Install the "Desktop development with C++" workload.
goto :fail

:no_vcvars
echo ERROR: vcvars64.bat missing under !VSDIR!
goto :fail

:no_clang
echo ERROR: clang-cl.exe not found.
echo Install LLVM (https://releases.llvm.org/) to C:\Program Files\LLVM
echo or the VS "C++ Clang tools for Windows" component.
goto :fail

:fail
echo.
echo Setup failed.
exit /b 1
