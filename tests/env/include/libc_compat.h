/*
 * Force-included into every test (see env/sw.mk).
 *
 * Declarations missing from pulp-runtime's minimal libc headers for functions
 * it does implement (lib/libc/minimal/). GCC >= 14 rejects calls to
 * undeclared functions.
 */
#ifndef LIBC_COMPAT_H
#define LIBC_COMPAT_H

#ifndef LANGUAGE_ASSEMBLY
#include <stddef.h>
#include <stdio.h>

/* io.c; not declared in include/string.h */
int memcmp(const void *m1, const void *m2, size_t n);

/* fprintf.c / sprintf.c; not declared in include/stdio.h. All streams
 * (stdout, stderr) print to the same output. */
int fprintf(FILE *F, const char *format, ...);
int snprintf(char *s, size_t len, const char *format, ...);
#endif

#endif
