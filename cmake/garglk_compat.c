/*
 * garglk_compat.c
 *
 * No-op stubs for the cosmetic garglk_* extension functions that some
 * terps call unconditionally inside #ifdef GARGLK blocks. RemGlk-rs
 * doesn't provide these (they configure window-title text in a real
 * GUI; meaningless in a headless RemGlk JSON pipe), but the symbols
 * still need to resolve at link time.
 *
 * Used by terps where (a) the GARGLK macro must be defined (often
 * because non-GARGLK code paths require headers we don't have, e.g.
 * jacl's glkterm/gi_blorb.h fallback), and (b) the only consequences
 * of GARGLK being on are calls to these three functions.
 *
 * Add more stubs here as new terps surface other unconditional
 * garglk_ extensions (garglk_unput_string_uni, garglk_zbleep, etc.).
 */

#include "glk.h"

void garglk_set_program_name(const char *name)
{
    (void)name;
}

void garglk_set_program_info(const char *info)
{
    (void)info;
}

void garglk_set_story_name(const char *name)
{
    (void)name;
}
