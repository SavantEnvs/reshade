// The DXBC/DXIL back-ends wrap Windows-only compilers (d3dcompiler, dxcompiler). On Linux they are absent;
// upstream's fxc tool references the factories, so provide stubs that decline to create a back-end.
#include "effect_codegen.hpp"

reshadefx::codegen *reshadefx::create_codegen_dxbc(unsigned int, bool, bool, int) { return nullptr; }
reshadefx::codegen *reshadefx::create_codegen_dxil(unsigned int, bool, bool, int) { return nullptr; }
