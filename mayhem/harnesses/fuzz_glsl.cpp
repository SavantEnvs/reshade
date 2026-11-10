// Fuzzes the ReShade FX parser and the GLSL back-end (source/effect_codegen_glsl.cpp).
// Each input is compiled with two back-end configurations: the plain one, and one with debug info,
// specialization constants and the API-specific options enabled.
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (fuzz::names_include(data, size))
		return -1;

	reshadefx::preprocessor pp;
	if (!fuzz::preprocess(pp, data, size))
		return -1;

	const std::unique_ptr<reshadefx::codegen> plain(reshadefx::create_codegen_glsl(false, false, false));
	if (!fuzz::compile(pp.output(), plain.get()))
		return -1;

	const std::unique_ptr<reshadefx::codegen> extended(reshadefx::create_codegen_glsl(true, true, true, true, true));
	fuzz::compile(pp.output(), extended.get());
	return 0;
}
