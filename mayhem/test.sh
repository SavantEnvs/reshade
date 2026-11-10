#!/usr/bin/env bash
#
# mayhem/test.sh — known-answer tests for the ReShade FX effect compiler. Runs upstream's own command line
# compiler (tools/fxc.cpp, built by mayhem/build.sh with normal flags into build/oracle/fxc) on fixed effect
# files and asserts the exact preprocessed text, the exact HLSL/GLSL statements generated for known
# expressions, the SPIR-V header, and the diagnostics for a bad effect. Does not build anything.
set -uo pipefail
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH
: "${MAYHEM_JOBS:=$(nproc)}"
cd "$SRC"

# emit_ctrf <tool> <passed> <failed> [skipped] [pending] [other]
# Writes a CTRF report (file + stdout `CTRF {...}` marker) and returns non-zero iff failed>0.
emit_ctrf() {
  local tool="$1" passed="$2" failed="$3" skipped="${4:-0}" pending="${5:-0}" other="${6:-0}"
  local tests=$(( passed + failed + skipped + pending + other ))
  cat > "${CTRF_REPORT:-$SRC/ctrf-report.json}" <<JSON
{
  "results": {
    "tool": { "name": "$tool" },
    "summary": {
      "tests": $tests,
      "passed": $passed,
      "failed": $failed,
      "pending": $pending,
      "skipped": $skipped,
      "other": $other
    }
  }
}
JSON
  printf 'CTRF {"results":{"tool":{"name":"%s"},"summary":{"tests":%d,"passed":%d,"failed":%d,"pending":%d,"skipped":%d,"other":%d}}}\n' \
    "$tool" "$tests" "$passed" "$failed" "$pending" "$skipped" "$other"
  [ "$failed" -eq 0 ]
}

FXC="$SRC/build/oracle/fxc"
FIX="$SRC/mayhem/oracle/fixtures"
[ -x "$FXC" ] || { echo "missing $FXC: mayhem/build.sh did not build the oracle" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

passed=0
failed=0
ok()   { passed=$((passed + 1)); echo "PASS: $1"; }
fail() { failed=$((failed + 1)); echo "FAIL: $1" >&2; }

# expect_contains <name> <file> <fixed string>
expect_contains() {
  if grep -qF -- "$3" "$2" 2>/dev/null; then ok "$1"; else fail "$1 (missing: $3)"; fi
}

# 1. Preprocessor: macro expansion, #if arithmetic, #line, _Pragma, variadic macros.
cat > "$WORK/pp.expected" <<'EXPECTED'
#line 1 "pp.fx"
_Pragma("reshade skipoptimization")
#line 102
static const int A[3] = { 1, 2, 3 };
static const int B = 1 + 2 * 2 + 1;
#line 106
float Dummy = 1.0;


EXPECTED
(cd "$FIX" && "$FXC" -P - pp.fx > "$WORK/pp.out" 2> "$WORK/pp.err")
if [ "$(cat "$WORK/pp.out" 2>/dev/null)" = "$(cat "$WORK/pp.expected")" ]; then
  ok "preprocess pp.fx"
else
  fail "preprocess pp.fx"
  diff "$WORK/pp.expected" "$WORK/pp.out" >&2 || true
fi

# 2. Command line macro definitions reach the preprocessor.
printf '#ifdef WIDTH\nint w = WIDTH * 2;\n#endif\n' > "$WORK/def.fx"
"$FXC" -D WIDTH=21 -P - "$WORK/def.fx" > "$WORK/def.out" 2>/dev/null
expect_contains "-D macro expanded" "$WORK/def.out" "int w = 21 * 2;"

# 3. HLSL back-end, whole module.
"$FXC" --hlsl "$FIX/invert.fx" -Fo "$WORK/invert.hlsl" 2> "$WORK/hlsl.err"; hlsl_rc=$?
if [ "$hlsl_rc" -eq 0 ]; then ok "hlsl exit status"; else fail "hlsl exit status ($hlsl_rc)"; fi
expect_contains "hlsl uniform buffer"      "$WORK/invert.hlsl" "float V__Strength;"
expect_contains "hlsl sampler binding"     "$WORK/invert.hlsl" "Texture2D<float4> __V__BackBuffer_t : register(t0);"
expect_contains "hlsl vertex shader entry" "$WORK/invert.hlsl" "out float4 position : SV_POSITION,"
expect_contains "hlsl lerp lowering"       "$WORK/invert.hlsl" "float4 _37 = lerp(color, _35, V__Strength.xxxx);"
expect_contains "hlsl vector subtraction"  "$WORK/invert.hlsl" "float4 _35 = float4(1.00000000e+00, 1.00000000e+00, 1.00000000e+00, 1.00000000e+00) - color;"

# 4. HLSL back-end, single entry point.
"$FXC" --hlsl "$FIX/invert.fx" -E F__PS_Invert -Fo "$WORK/ps.hlsl" 2>/dev/null
expect_contains "hlsl entry point body" "$WORK/ps.hlsl" "float4 F__PS_Invert("
if [ -s "$WORK/ps.hlsl" ] && ! grep -qF "F__PostProcessVS" "$WORK/ps.hlsl"; then
  ok "hlsl entry point excludes unreferenced functions"
else
  fail "hlsl entry point excludes unreferenced functions"
fi

# 5. GLSL back-end.
"$FXC" --glsl "$FIX/invert.fx" -Fo "$WORK/invert.glsl" 2> "$WORK/glsl.err"; glsl_rc=$?
if [ "$glsl_rc" -eq 0 ]; then ok "glsl exit status"; else fail "glsl exit status ($glsl_rc)"; fi
expect_contains "glsl version"         "$WORK/invert.glsl" "#version 430"
expect_contains "glsl lerp is mix"     "$WORK/invert.glsl" "vec4 _37 = mix(color, _35, V_xStrength.xxxx);"
expect_contains "glsl pixel entry"     "$WORK/invert.glsl" "#ifdef E_xPS_Invert"
expect_contains "glsl vertex position" "$WORK/invert.glsl" "gl_Position = position;"

# 6. SPIR-V back-end: magic number, GLSL.std.450 import, exact size.
"$FXC" --spirv "$FIX/invert.fx" -E F__PS_Invert -Fo "$WORK/invert.spv" 2> "$WORK/spv.err"; spv_rc=$?
if [ "$spv_rc" -eq 0 ]; then ok "spirv exit status"; else fail "spirv exit status ($spv_rc)"; fi
magic="$(od -A n -t x1 -N 4 "$WORK/invert.spv" 2>/dev/null | tr -d ' \n')"
if [ "$magic" = "03022307" ]; then ok "spirv magic number"; else fail "spirv magic number ($magic)"; fi
if [ "$(wc -c < "$WORK/invert.spv" 2>/dev/null)" = "1536" ]; then ok "spirv module size"; else fail "spirv module size"; fi
expect_contains "spirv imports GLSL.std.450" "$WORK/invert.spv" "GLSL.std.450"

# 7. Diagnostics: an undeclared identifier is rejected with the documented message and exit status.
printf 'float4 f() { return undeclared; }\n' > "$WORK/bad.fx"
"$FXC" --hlsl "$WORK/bad.fx" -Fo "$WORK/bad.hlsl" 2> "$WORK/bad.err"; bad_rc=$?
if [ "$bad_rc" -eq 2 ]; then ok "bad effect exit status"; else fail "bad effect exit status ($bad_rc)"; fi
expect_contains "bad effect diagnostic" "$WORK/bad.err" "(1, 21): error X3004: undeclared identifier 'undeclared'"
if [ ! -e "$WORK/bad.hlsl" ]; then ok "bad effect produces no output"; else fail "bad effect produces no output"; fi

emit_ctrf "fxc-known-answer" "$passed" "$failed" 0
