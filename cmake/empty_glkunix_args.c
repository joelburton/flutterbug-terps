/*
 * Fallback glkunix_arguments[] table.
 *
 * remglk_capi's support.c references glkunix_arguments unconditionally
 * (via glkunix_arguments_addr) and rejects any positional argument not
 * registered here. Terps that define their own table (with a positional
 * "" entry) supersede this one. Terps that don't — currently taylor and
 * plus — link this shim instead to register a positional filename.
 *
 * Plus declares its own glkunix_arguments[10]; as a tentative
 * definition; we need -fcommon on its translation unit so this strong
 * definition wins at link time.
 */
#include "glk.h"
#include "glkstart.h"

glkunix_argumentlist_t glkunix_arguments[] = {
    { (char *)"", glkunix_arg_ValueFollows, (char *)"filename    file to load" },
    { NULL, glkunix_arg_End, NULL }
};
