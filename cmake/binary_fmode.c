/*
 * Override MSVC's default file translation mode from text to binary.
 *
 * Several Petter Sjölund terps (plus, taylor) open binary game files with
 * fopen(name, "r") instead of "rb". On Linux/macOS that's a no-op — there
 * is no CR/LF translation. On Windows, MSVCRT defaults to _O_TEXT, which
 * mangles bytes (0x1a → EOF, CRLF collapsing) and breaks parsers that
 * expect raw bytes.
 *
 * Modern UCRT ignores the historical `int _fmode = _O_BINARY;` link-time
 * override. Instead we register a CRT pre-main initializer in the .CRT$XCU
 * section that calls _set_fmode(_O_BINARY) before any of the terp's own
 * code runs. This makes every fopen() in the process default to binary
 * unless the caller passes "t".
 */
#include <fcntl.h>
#include <stdlib.h>

static int set_binary_fmode(void) {
    _set_fmode(_O_BINARY);
    return 0;
}

/* CRT$XCU holds C initializer pointers walked between CRT$XCA and CRT$XCZ
 * during startup. The variable must have external linkage so the linker
 * keeps it through DCE — internal-linkage statics here have been observed
 * to get stripped by lld-link. */
#pragma section(".CRT$XCU", read)
__declspec(allocate(".CRT$XCU"))
int (*const p_set_binary_fmode)(void) = set_binary_fmode;
