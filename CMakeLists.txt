cmake_minimum_required(VERSION 3.20)

project(flutterbug-terps
    LANGUAGES C CXX
    DESCRIPTION "Headless RemGlk-backed builds of Gargoyle's vendored interpreters")

set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

set(GARGOYLE_DIR "${CMAKE_SOURCE_DIR}/../garglk"
    CACHE PATH "Path to the Gargoyle checkout supplying terp source trees")

list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/cmake")
include(RemGlkRs)

#
# terp(<name>
#     SRCS <files...>           — terp source files (relative to ${terp_dir})
#     INCLUDE_DIRS <dirs...>    — extra include dirs
#     MACROS <name[=value]...>  — extra preprocessor macros
#     LIBS <libs...>            — extra link libraries
#     CXXSTD <14|17|...>        — override C++ standard for this terp
# )
#
# Builds an executable that links remglk_capi for its Glk implementation. We
# do NOT define the GARGLK macro here; terps fall through to portable paths
# for anything not gated by a GLK_MODULE_* feature-test macro.
#
function(terp target)
    set(options POSIX)
    set(oneval CXXSTD)
    set(multival SRCS INCLUDE_DIRS MACROS LIBS)
    cmake_parse_arguments(TERP "${options}" "${oneval}" "${multival}" ${ARGN})

    set(terp_dir "${GARGOYLE_DIR}/terps/${target}")
    set(prefixed_srcs)
    foreach(src ${TERP_SRCS})
        list(APPEND prefixed_srcs "${terp_dir}/${src}")
    endforeach()

    add_executable(${target} ${prefixed_srcs})
    target_include_directories(${target} PRIVATE ${TERP_INCLUDE_DIRS} "${terp_dir}")
    target_compile_definitions(${target} PRIVATE ${TERP_MACROS})
    target_link_libraries(${target} PRIVATE remglk_capi ${TERP_LIBS})

    if(TERP_CXXSTD)
        set_target_properties(${target} PROPERTIES CXX_STANDARD ${TERP_CXXSTD})
    endif()

    if(TERP_POSIX)
        target_compile_definitions(${target} PRIVATE
            $<$<COMPILE_LANGUAGE:C>:_XOPEN_SOURCE=600>)
    endif()
endfunction()

#
# bocfel — Z-machine
#
set(BOCFEL_MACROS
    ZTERP_GLK ZTERP_GLK_BLORB ZTERP_GLK_UNIX
    "ZTERP_STATIC_PATCH_FILE=\"static-patches.h\"")
if(UNIX)
    list(APPEND BOCFEL_MACROS ZTERP_OS_UNIX)
endif()

terp(bocfel
    SRCS
        blorb.cpp branch.cpp dict.cpp iff.cpp io.cpp mathop.cpp meta.cpp
        memory.cpp objects.cpp options.cpp osdep.cpp patches.cpp process.cpp
        random.cpp screen.cpp sound.cpp stack.cpp stash.cpp unicode.cpp
        util.cpp zterp.cpp glkstart.cpp glkautosave.cpp
    CXXSTD 14
    MACROS ${BOCFEL_MACROS})

#
# glulxe — Glulx (Inform 7's modern target)
#
set(GLULXE_MACROS FLOAT_COMPILE_SAFER_POWF)
if(APPLE)
    list(APPEND GLULXE_MACROS OS_MAC)
elseif(UNIX)
    list(APPEND GLULXE_MACROS OS_UNIX)
    if(CMAKE_SYSTEM_NAME STREQUAL "Linux")
        list(APPEND GLULXE_MACROS UNIX_RAND_GETRANDOM)
    endif()
endif()

terp(glulxe
    SRCS
        main.c files.c vm.c exec.c funcs.c operand.c string.c glkop.c
        heap.c serial.c search.c gestalt.c osdepend.c unixstrt.c accel.c
        profile.c float.c
    MACROS ${GLULXE_MACROS}
    POSIX)

if(APPLE)
    set_source_files_properties("${GARGOYLE_DIR}/terps/glulxe/osdepend.c"
        PROPERTIES COMPILE_DEFINITIONS _DARWIN_C_SOURCE)
endif()

#
# git — Iain Merrick's faster Glulx interpreter (maintained by David Kinder)
#
terp(git
    SRCS
        git.c memory.c compiler.c opcodes.c operands.c peephole.c terp.c
        glkop.c search.c git_unix.c savefile.c saveundo.c gestalt.c
        heap.c accel.c
    MACROS USE_INLINE)

#
# tadsr — TADS 2 + TADS 3 (one binary handles both versions)
#
set(TADS_GLK_SRCS
    glk/memicmp.c glk/osbuffer.c glk/osextra.c glk/osglk.c glk/osglkban.c
    glk/osmisc.c glk/osparse.c glk/osportable.cc glk/t23run.cpp
    glk/t2askf.c glk/t2indlg.c glk/t3askf.cpp glk/t3indlg.cpp glk/vmuni_cs.cpp)

set(TADS_TADS2_SRCS
    tads2/argize.c tads2/bif.c tads2/bifgdum.c tads2/cmap.c tads2/cmd.c
    tads2/dat.c tads2/dbgtr.c tads2/errmsg.c tads2/execmd.c tads2/fio.c
    tads2/fioxor.c tads2/getstr.c tads2/ler.c tads2/linfdum.c tads2/lst.c
    tads2/mch.c tads2/mcm.c tads2/mcs.c tads2/obj.c tads2/oem.c tads2/os0.c
    tads2/oserr.c tads2/osifc.c tads2/osnoui.c tads2/osrestad.c
    tads2/osstzprs.c tads2/ostzposix.c tads2/out.c tads2/output.c
    tads2/ply.c tads2/qas.c tads2/regex.c tads2/run.c tads2/runstat.c
    tads2/suprun.c tads2/trd.c tads2/voc.c tads2/vocab.c)

set(TADS_TADS3_SRCS
    tads3/charmap.cpp tads3/md5.cpp tads3/resldexe.cpp tads3/resload.cpp
    tads3/sha2.cpp tads3/std.cpp tads3/tcerr.cpp tads3/tcerrmsg.cpp
    tads3/tcgen.cpp tads3/tcglob.cpp tads3/tcmain.cpp tads3/tcprs.cpp
    tads3/tcprs_rt.cpp tads3/tcprsnf.cpp tads3/tcprsnl.cpp tads3/tcprsstm.cpp
    tads3/tcsrc.cpp tads3/tct3.cpp tads3/tct3_d.cpp tads3/tct3nl.cpp
    tads3/tct3stm.cpp tads3/tct3unas.cpp tads3/tctok.cpp tads3/utf8.cpp
    tads3/vmanonfn.cpp tads3/vmbif.cpp tads3/vmbifl.cpp tads3/vmbifreg.cpp
    tads3/vmbift3.cpp tads3/vmbiftad.cpp tads3/vmbiftio.cpp tads3/vmbignum.cpp
    tads3/vmbignumlib.cpp tads3/vmbt3_nd.cpp tads3/vmbytarr.cpp
    tads3/vmcfgmem.cpp tads3/vmcoll.cpp tads3/vmconhmp.cpp tads3/vmconsol.cpp
    tads3/vmcrc.cpp tads3/vmcset.cpp tads3/vmdate.cpp tads3/vmdict.cpp
    tads3/vmdynfunc.cpp tads3/vmerr.cpp tads3/vmerrmsg.cpp tads3/vmfile.cpp
    tads3/vmfilnam.cpp tads3/vmfilobj.cpp tads3/vmfref.cpp tads3/vmfunc.cpp
    tads3/vmglob.cpp tads3/vmgram.cpp tads3/vmhash.cpp tads3/vmhostsi.cpp
    tads3/vmhosttx.cpp tads3/vmimage.cpp tads3/vmimg_nd.cpp tads3/vmini_nd.cpp
    tads3/vminit.cpp tads3/vminitim.cpp tads3/vmintcls.cpp tads3/vmisaac.cpp
    tads3/vmiter.cpp tads3/vmlog.cpp tads3/vmlookup.cpp tads3/vmlst.cpp
    tads3/vmmain.cpp tads3/vmmcreg.cpp tads3/vmmeta.cpp tads3/vmnetfillcl.cpp
    tads3/vmobj.cpp tads3/vmop.cpp tads3/vmpack.cpp tads3/vmpat.cpp
    tads3/vmpool.cpp tads3/vmpoolim.cpp tads3/vmregex.cpp tads3/vmrun.cpp
    tads3/vmrunsym.cpp tads3/vmsa.cpp tads3/vmsave.cpp tads3/vmsort.cpp
    tads3/vmsortv.cpp tads3/vmsrcf.cpp tads3/vmstack.cpp tads3/vmstr.cpp
    tads3/vmstrbuf.cpp tads3/vmstrcmp.cpp tads3/vmtmpfil.cpp tads3/vmtobj.cpp
    tads3/vmtype.cpp tads3/vmtypedh.cpp tads3/vmtz.cpp tads3/vmtzobj.cpp
    tads3/vmundo.cpp tads3/vmvec.cpp tads3/vmconnom.cpp)

# Note: the gargoyle source layout puts glk/, tads2/, and tads3/ inside
# garglk/terps/tads/, and the binary is conventionally named "tadsr". Our
# terp() helper expects a directory matching the target name, so we name
# the target "tads" (matching the dir) and rename the output to "tadsr".
terp(tads
    SRCS ${TADS_GLK_SRCS} ${TADS_TADS2_SRCS} ${TADS_TADS3_SRCS}
    INCLUDE_DIRS
        "${GARGOYLE_DIR}/terps/tads/glk"
        "${GARGOYLE_DIR}/terps/tads/tads2"
        "${GARGOYLE_DIR}/terps/tads/tads3"
    MACROS GLK VMGLOB_STRUCT GLK_UNICODE GLK_TIMERS TC_TARGET_T3 RUNTIME
    CXXSTD 11
    POSIX)
set_target_properties(tads PROPERTIES OUTPUT_NAME tadsr)

if(CMAKE_C_COMPILER_ID STREQUAL "Clang"
   OR CMAKE_CXX_COMPILER_ID STREQUAL "Clang"
   OR CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    target_compile_options(tads PRIVATE "-Wno-logical-not-parentheses")
endif()

# ----------------------------------------------------------------------------
# Helper libraries shared by scott / plus / taylor (all by Petter Sjölund).
# These mirror the gargoyle definitions in terps/{c64diskimage,unp64}/.
# ----------------------------------------------------------------------------

add_library(c64diskimage STATIC
    "${GARGOYLE_DIR}/terps/c64diskimage/c64diskimage.c")
target_include_directories(c64diskimage INTERFACE
    "${GARGOYLE_DIR}/terps/c64diskimage")

set(UNP64_DIR "${GARGOYLE_DIR}/terps/unp64")
add_library(unp64 STATIC
    ${UNP64_DIR}/6502_emu.cpp ${UNP64_DIR}/exo_util.cpp ${UNP64_DIR}/globals.cpp
    ${UNP64_DIR}/unp64.cpp
    ${UNP64_DIR}/scanners/scanners.cpp ${UNP64_DIR}/scanners/abuze_crunch.cpp
    ${UNP64_DIR}/scanners/action_packer.cpp ${UNP64_DIR}/scanners/byte_boiler.cpp
    ${UNP64_DIR}/scanners/caution.cpp ${UNP64_DIR}/scanners/ccs.cpp
    ${UNP64_DIR}/scanners/cruel.cpp ${UNP64_DIR}/scanners/eca.cpp
    ${UNP64_DIR}/scanners/exomizer.cpp ${UNP64_DIR}/scanners/expert.cpp
    ${UNP64_DIR}/scanners/final_super_comp.cpp ${UNP64_DIR}/scanners/intros.cpp
    ${UNP64_DIR}/scanners/master_compressor.cpp ${UNP64_DIR}/scanners/megabyte.cpp
    ${UNP64_DIR}/scanners/mr_cross.cpp ${UNP64_DIR}/scanners/mr_z.cpp
    ${UNP64_DIR}/scanners/pu_crunch.cpp ${UNP64_DIR}/scanners/section8.cpp
    ${UNP64_DIR}/scanners/tbc_multicomp.cpp ${UNP64_DIR}/scanners/tcs_crunch.cpp
    ${UNP64_DIR}/scanners/time_cruncher.cpp ${UNP64_DIR}/scanners/xtc.cpp)
target_include_directories(unp64 INTERFACE ${UNP64_DIR} PRIVATE ${UNP64_DIR})
set_target_properties(unp64 PROPERTIES CXX_STANDARD 17)

#
# scott — ScottFree (Alan Cox) + saga / ai_uk / ti994a extensions (Petter Sjölund)
#
terp(scott
    SRCS
        scott.c bsd.c
        ai_uk/c64decrunch.c ai_uk/debug.c ai_uk/decompresstext.c
        ai_uk/decompressz80.c ai_uk/game_specific.c ai_uk/gremlins.c
        ai_uk/hulk.c ai_uk/line_drawing.c ai_uk/ringbuffer.c
        ai_uk/robinofsherwood.c ai_uk/sagadraw.c ai_uk/seasofblood.c
        detectgame.c layouttext.c parser.c restorestate.c scottgameinfo.c
        titleimage.c
        saga/apple2detect.c saga/apple2draw.c saga/atari8c64draw.c
        saga/atari8detect.c saga/ciderpress.c saga/pcdraw.c saga/saga.c
        saga/sagagraphics.c saga/woz2nib.c
        ti994a/load_ti99_4a.c ti994a/ti99_4a_terp.c
    INCLUDE_DIRS
        "${GARGOYLE_DIR}/terps/scott/saga"
        "${GARGOYLE_DIR}/terps/scott/ai_uk"
        "${GARGOYLE_DIR}/terps/scott/ti994a"
    LIBS c64diskimage unp64)

#
# plus — Plus 1.0 by Petter Sjölund (US Adventure International games)
#
terp(plus
    SRCS
        plusmain.c animations.c apple2detect.c apple2draw.c atari8c64draw.c
        atari8detect.c c64detect.c extracommands.c companionfile.c gameinfo.c
        graphics.c layouttext.c loaddatabase.c parseinput.c pcdraw.c
        restorestate.c stdetect.c stdraw.c
    LIBS c64diskimage)
target_sources(plus PRIVATE "${CMAKE_SOURCE_DIR}/cmake/empty_glkunix_args.c")
# plus declares glkunix_arguments[10]; as a tentative definition. -fcommon
# lets the linker treat that as common and resolve to our shim's strong
# definition instead of erroring on duplicate symbols.
set_source_files_properties("${GARGOYLE_DIR}/terps/plus/plusmain.c"
    PROPERTIES COMPILE_FLAGS "-fcommon")

#
# taylor — TaylorMade by Alan Cox / Petter Sjölund (Adventure Soft UK games)
#
terp(taylor
    SRCS
        animations.c c64decrunch.c decompressz80.c decrypttotloader.c
        extracommands.c extracttape.c gameinfo.c layouttext.c
        loadtotpicture.c parseinput.c player.c restorestate.c sagadraw.c
        ui.c utility.c
    LIBS c64diskimage unp64)
target_sources(taylor PRIVATE "${CMAKE_SOURCE_DIR}/cmake/empty_glkunix_args.c")

#
# advsys — AdvSys 1.2 (Dave Betz, 1980s). Small Lisp-flavored adventure system.
#
terp(advsys
    SRCS
        advmsg.c advtrm.c advprs.c advdbs.c advint.c advjunk.c advexe.c
        glkstart.c)
if(CMAKE_C_COMPILER_ID MATCHES "Clang$")
    target_compile_options(advsys PRIVATE "-Wno-parentheses")
endif()

#
# hugo — Hugo (Kent Tessman, 1995). Standalone VM and IF system.
#
terp(hugo
    SRCS
        heglk/heglk.c heglk/heglkunix.c
        source/he.c source/hemisc.c source/heparse.c source/herun.c
        source/heexpr.c source/heobject.c source/heres.c source/heset.c
        source/stringfn.c
    INCLUDE_DIRS "${GARGOYLE_DIR}/terps/hugo/source"
    MACROS GLK HUGO_GLKUNIX COMPILE_V25 NO_KEYPRESS_CURSOR "HUGO_INLINE=static inline")
