// Fuzzes the ReShade FX preprocessor (source/effect_preprocessor.cpp, effect_lexer.cpp).
#include "fuzz_common.hpp"

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	if (fuzz::names_include(data, size))
		return -1;

	reshadefx::preprocessor pp;
	if (!fuzz::preprocess(pp, data, size))
		return -1;

	fuzz::sink += pp.output().size() + pp.errors().size() + pp.used_macro_definitions().size();
	return 0;
}
