// Shared helpers for the ReShade FX effect-compiler harnesses (preprocessor -> parser -> code generators).
// Mirrors how ReShade's runtime (source/runtime.cpp) and upstream's tools/fxc.cpp drive reshadefx.
#pragma once

#include "effect_codegen.hpp"
#include "effect_parser.hpp"
#include "effect_preprocessor.hpp"
#include <cstddef>
#include <cstdint>
#include <cstring>
#include <memory>
#include <string>

namespace fuzz
{
	// Keeps results observable so the optimizer cannot discard the work.
	inline volatile size_t sink = 0;

	// The preprocessor opens whatever file a `#include` names, absolute paths included, so an input
	// containing one would make the result depend on the host file system (and let it read e.g. /dev/zero).
	// The lexer only recognises the directive from the identifier text "include", so reject those inputs.
	inline bool names_include(const uint8_t *data, size_t size)
	{
		return std::memchr(data, 'i', size) != nullptr && memmem(data, size, "include", 7) != nullptr;
	}

	inline void define_predefined_macros(reshadefx::preprocessor &pp)
	{
		pp.add_macro_definition("__RESHADE__", "60000");
		pp.add_macro_definition("__RESHADE_PERFORMANCE_MODE__", "0");
		pp.add_macro_definition("BUFFER_WIDTH", "800");
		pp.add_macro_definition("BUFFER_HEIGHT", "600");
		pp.add_macro_definition("BUFFER_RCP_WIDTH", "(1.0 / BUFFER_WIDTH)");
		pp.add_macro_definition("BUFFER_RCP_HEIGHT", "(1.0 / BUFFER_HEIGHT)");
	}

	// append_string() itself refuses sources that do not end in a line feed (its documented contract).
	inline bool preprocess(reshadefx::preprocessor &pp, const uint8_t *data, size_t size)
	{
		define_predefined_macros(pp);
		return pp.append_string(std::string(reinterpret_cast<const char *>(data), size));
	}

	// Parses preprocessed source with a code generator, then generates the code for the whole module and for
	// every entry point separately, as the runtime does. Returns false if the parser rejects the source.
	// The runtime refuses compute entry points on D3D9/D3D10 before assembling them (source/runtime.cpp, "compute
	// shaders are not supported in D3D9/D3D10"), so callers modelling those targets pass compute_ok = false.
	inline bool compile(const std::string &source, reshadefx::codegen *backend, bool compute_ok = true)
	{
		reshadefx::parser parser;
		if (!parser.parse(source, backend))
			return false;

		sink += backend->finalize_code().size();

		const auto entry_points = backend->module().entry_points;
		for (const auto &entry_point : entry_points)
		{
			if (entry_point.second == reshadefx::shader_type::compute && !compute_ok)
				continue;
			std::string code, assembly, errors;
			if (backend->assemble_code_for_entry_point(entry_point.first, code, assembly, errors))
				sink += code.size();
		}
		return true;
	}
}
