// Preprocessor-heavy input
#define EMPTY
#define LIST(...) __VA_ARGS__
#define F(x, y) x + y * 2
#define TWICE(f, a) f(a) f(a)
#define VALUE 0x10
#undef EMPTY
#ifdef VALUE
	#if VALUE == 16 && (defined(VALUE) || !defined(NOPE)) && (1 << 2) == 4
		#pragma reshade skipoptimization
		#define RESULT 1
	#else
		#error value mismatch
	#endif
#endif
#line 100 "virtual.fx"
#ifndef GUARD
#define GUARD
static const int A[3] = { LIST(1, 2, 3) };
static const int B = F(1, 2) + RESULT;
#endif
#if __LINE__ != 0
float Dummy = 1.0;
#endif
