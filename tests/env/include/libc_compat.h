/*
 * Force-included into every test (see env/sw.mk).
 *
 * Declarations missing from pulp-runtime's minimal libc headers for functions
 * it does implement (lib/libc/minimal/io.c).
 */
#ifndef LIBC_COMPAT_H
#define LIBC_COMPAT_H

#ifndef LANGUAGE_ASSEMBLY
#include <stddef.h>

/* Not declared in lib/libc/minimal/include/string.h */
int memcmp(const void *m1, const void *m2, size_t n);
#endif

#endif
