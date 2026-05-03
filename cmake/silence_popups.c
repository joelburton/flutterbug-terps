/*
 * Silence Windows runtime popups so the smoke runner (and anyone driving
 * a terp from a script) doesn't have to dismiss modal dialogs.
 *
 * The MSVCRT shows two kinds of popups by default:
 *   1. abort() prints "Debug Error! ... abort() has been called" with
 *      Abort/Retry/Ignore buttons. Several terps reach this when stdin
 *      closes mid-game or a parser hits a sanity-check failure.
 *   2. Unhandled SEH exceptions trigger Windows Error Reporting's
 *      "Program has stopped working" dialog.
 * Debug-CRT builds also surface _CrtDbgReport assertions as popups.
 *
 * Registered as a CRT pre-main initializer so it runs before any of the
 * terp's own startup code.
 */
#include <crtdbg.h>
#include <stdlib.h>

/* SetErrorMode lives in kernel32. Declare its signature locally so this
 * shim compiles even for terps (scare) that build with /U_WIN32 to dodge
 * a Windows-only block in os_glk.c — including <windows.h> there blows up. */
__declspec(dllimport) unsigned int __stdcall SetErrorMode(unsigned int uMode);
#define SEM_FAILCRITICALERRORS  0x0001U
#define SEM_NOGPFAULTERRORBOX   0x0002U
#define SEM_NOOPENFILEERRORBOX  0x8000U

static int silence_runtime_popups(void) {
    /* Disable the abort() message dialog and the WER fault report. */
    _set_abort_behavior(0, _WRITE_ABORT_MSG | _CALL_REPORTFAULT);

    /* Suppress OS-level crash and critical-error dialogs. */
    SetErrorMode(SEM_FAILCRITICALERRORS
                 | SEM_NOGPFAULTERRORBOX
                 | SEM_NOOPENFILEERRORBOX);

    /* Route debug-CRT asserts/errors/warnings to stderr instead of a
     * modal dialog. No-ops in release builds. */
    _CrtSetReportMode(_CRT_ASSERT, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ASSERT, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_ERROR, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_ERROR, _CRTDBG_FILE_STDERR);
    _CrtSetReportMode(_CRT_WARN, _CRTDBG_MODE_FILE);
    _CrtSetReportFile(_CRT_WARN, _CRTDBG_FILE_STDERR);

    return 0;
}

#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU"))
int (*const p_silence_runtime_popups)(void) = silence_runtime_popups;
