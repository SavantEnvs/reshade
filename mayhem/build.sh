#!/usr/bin/env bash
#
# mayhem/build.sh — builds the ReShade FX effect compiler (reshadefx: lexer, preprocessor, parser, symbol
# table and the HLSL/GLSL/SPIR-V code generators; the DXBC/DXIL back-ends wrap Windows-only compilers and
# are not built) twice:
#   1. sanitized + coverage-instrumented, linked into the libFuzzer harnesses and their -standalone twins;
#   2. with normal flags, linked into upstream's own tools/fxc.cpp, which mayhem/test.sh runs as the oracle.
set -euo pipefail

[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${STANDALONE_FUZZ_MAIN:=/opt/mayhem/StandaloneFuzzTargetMain.c}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

# `build/` is covered by upstream's .gitignore, so `git clean -ffdX` removes everything below it.
FUZZ_DIR="$SRC/build/fuzz"
ORACLE_DIR="$SRC/build/oracle"
SPIRV_INC=/opt/toolchains/deps/spirv-headers-7845730cab6ebbdeb621e7349b7dc1a59c3377be/include
[ -f "$SPIRV_INC/spirv.hpp" ] || { echo "missing SPIR-V headers in $SPIRV_INC" >&2; exit 1; }

LIB_SOURCES="effect_lexer effect_preprocessor effect_symbol_table effect_expression effect_parser_exp effect_parser_stmt effect_codegen_glsl effect_codegen_hlsl effect_codegen_spirv"
HARNESSES="fuzz_preprocessor fuzz_hlsl fuzz_glsl fuzz_spirv"

rm -rf "$FUZZ_DIR" "$ORACLE_DIR"
mkdir -p "$FUZZ_DIR" "$ORACLE_DIR"

# 1) Sanitized library. -fsanitize=fuzzer-no-link puts SanCov on the library itself (not only on the harness
#    translation unit), unconditionally, so the fuzzed code reports coverage even with SANITIZER_FLAGS empty.
FUZZ_CXXFLAGS="-std=c++17 -O1 $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -I source -I $SPIRV_INC"
for s in $LIB_SOURCES; do echo "$s"; done | xargs -P "$MAYHEM_JOBS" -I{} \
  $CXX $FUZZ_CXXFLAGS -c "source/{}.cpp" -o "$FUZZ_DIR/{}.o"
rm -f "$FUZZ_DIR/libreshadefx.a"
ar rcs "$FUZZ_DIR/libreshadefx.a" $(for s in $LIB_SOURCES; do echo "$FUZZ_DIR/$s.o"; done)

# 2) Harnesses: once with the fuzzing engine, once with the run-once standalone driver. The driver is C, so
#    compile it as such first or clang++ would mangle its LLVMFuzzerTestOneInput reference.
$CC $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link -c "$STANDALONE_FUZZ_MAIN" -o "$FUZZ_DIR/standalone_main.o"
$CXX $SANITIZER_FLAGS $DEBUG_FLAGS -c mayhem/lsan_off.cc -o "$FUZZ_DIR/lsan_off.o"
for h in $HARNESSES; do
  $CXX $FUZZ_CXXFLAGS -I mayhem/harnesses -c "mayhem/harnesses/$h.cpp" -o "$FUZZ_DIR/$h.o"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS $LIB_FUZZING_ENGINE "$FUZZ_DIR/$h.o" "$FUZZ_DIR/lsan_off.o" \
       "$FUZZ_DIR/libreshadefx.a" -o "/mayhem/$h"
  $CXX $SANITIZER_FLAGS $DEBUG_FLAGS -fsanitize=fuzzer-no-link "$FUZZ_DIR/standalone_main.o" "$FUZZ_DIR/$h.o" \
       "$FUZZ_DIR/lsan_off.o" "$FUZZ_DIR/libreshadefx.a" -o "/mayhem/$h-standalone"
done

# 3) Oracle: upstream's tools/fxc.cpp with the project's normal flags (no sanitizers, no DWARF pin). It needs
#    res/version.h (generated upstream, not committed) and the DXBC/DXIL factories; mayhem/oracle/ stubs both.
ORACLE_CXXFLAGS="-std=c++17 -O2 $COVERAGE_FLAGS -I source -I $SPIRV_INC -I mayhem/oracle/shim"
for s in $LIB_SOURCES; do echo "source/$s.cpp"; done | xargs -P "$MAYHEM_JOBS" -I{} sh -c \
  "$CXX $ORACLE_CXXFLAGS -c {} -o $ORACLE_DIR/\$(basename {} .cpp).o"
$CXX $ORACLE_CXXFLAGS $COVERAGE_FLAGS tools/fxc.cpp mayhem/oracle/codegen_stubs.cpp \
     $(for s in $LIB_SOURCES; do echo "$ORACLE_DIR/$s.o"; done) -o "$ORACLE_DIR/fxc"

for h in $HARNESSES; do [ -x "/mayhem/$h" ] && [ -x "/mayhem/$h-standalone" ]; done
[ -x "$ORACLE_DIR/fxc" ]
