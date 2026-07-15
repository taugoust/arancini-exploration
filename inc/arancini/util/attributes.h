#pragma once

#if __cplusplus >= 202002L
#define ARANCINI_LIKELY [[likely]]
#define ARANCINI_UNLIKELY [[unlikely]]
#else
#define ARANCINI_LIKELY
#define ARANCINI_UNLIKELY
#endif
