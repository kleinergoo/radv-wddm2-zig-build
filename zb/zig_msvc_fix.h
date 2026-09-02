#ifndef ZIG_MSVC_FIX_H
#define ZIG_MSVC_FIX_H

#if defined(_MSC_VER) && defined(_WIN32) && !defined(__ASSEMBLER__)
#ifndef _USE_MATH_DEFINES
#define _USE_MATH_DEFINES
#endif
#include <intrin.h>

/* clang doesn't implicitly know the lowercase intrinsic names that MSVC's cl
 * treats as builtins. Alias them to the camelCase forms declared by intrin.h. */
#define _interlockedexchange64     _InterlockedExchange64
#define _interlockedexchangeadd64  _InterlockedExchangeAdd64
#define _interlockedincrement64    _InterlockedIncrement64
#define _interlockeddecrement64    _InterlockedDecrement64

/* _InterlockedAdd/_InterlockedAdd64 are not declared by intrin.h under clang.
 * p_atomic_add_return needs the result of the add, so return old + incr. */
static inline long
_interlockedadd(long volatile *p, long v)
{
   return _InterlockedExchangeAdd(p, v) + v;
}

static inline __int64
_interlockedadd64(__int64 volatile *p, __int64 v)
{
   return _InterlockedExchangeAdd64(p, v) + v;
}

#endif

#endif