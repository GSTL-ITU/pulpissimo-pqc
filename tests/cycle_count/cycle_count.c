/*
 * Measures how many core cycles one function call takes.
 *
 * Only the call is inside the measured region: the counter is read right
 * before and right after it, and the result is printed afterwards, so printf
 * (cheap in simulation, slow over UART on hardware) does not distort it.
 *
 * Replace function_under_test() with the code you want to measure.
 */
#include <stdio.h>
#include <stdint.h>
#include "cycles.h"

#define N_WORDS 256

static uint32_t data[N_WORDS];

/* noinline: keep it a real call so the measurement includes call/return and
 * the compiler cannot move work out of the measured region. */
__attribute__((noinline)) uint32_t function_under_test(const uint32_t *buf, int n)
{
    /* FNV-1a over the buffer */
    uint32_t h = 2166136261u;
    for (int i = 0; i < n; i++) {
        h ^= buf[i];
        h *= 16777619u;
    }
    return h;
}

int main(void)
{
    for (int i = 0; i < N_WORDS; i++)
        data[i] = (uint32_t)i * 2654435761u;

    cycles_enable();
    uint64_t overhead = cycles_overhead();

    uint64_t start  = cycles_read();
    uint32_t result = function_under_test(data, N_WORDS);
    uint64_t end    = cycles_read();

    uint64_t cycles = end - start - overhead;

    /* Everything below is outside the measured region */
    cycles_print("function_under_test", cycles);
    cycles_print("measurement overhead (subtracted)", overhead);
    printf("result: 0x%08x\n", (unsigned)result);

    if (cycles == 0) {
        printf("ERROR: cycle counter did not advance\n");
        return 1;
    }
    return 0;
}
