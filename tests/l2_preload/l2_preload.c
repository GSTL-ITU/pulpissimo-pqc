/*
 * Checks that the testbench preloads every L2 region correctly: a 96 KiB
 * initialized table does not fit in the private banks and spills into the
 * word-interleaved banks. Every word holds a distinct value, so a wrong
 * bank/row mapping in the backdoor loader shows up as a mismatch.
 */
#include <stdio.h>
#include <stdint.h>

#define F(i)     ((uint32_t)(i) * 2654435761u)
#define R4(i)    F(i), F((i) + 1), F((i) + 2), F((i) + 3)
#define R16(i)   R4(i), R4((i) + 4), R4((i) + 8), R4((i) + 12)
#define R64(i)   R16(i), R16((i) + 16), R16((i) + 32), R16((i) + 48)
#define R256(i)  R64(i), R64((i) + 64), R64((i) + 128), R64((i) + 192)
#define R1K(i)   R256(i), R256((i) + 256), R256((i) + 512), R256((i) + 768)
#define R4K(i)   R1K(i), R1K((i) + 1024), R1K((i) + 2048), R1K((i) + 3072)

#define N_WORDS 24576

static const uint32_t table[N_WORDS] = { R4K(0), R4K(4096), R4K(8192), R4K(12288), R4K(16384), R4K(20480) };

int main(void)
{
    int errors = 0;

    printf("table: 0x%08x - 0x%08x\n", (unsigned)&table[0], (unsigned)&table[N_WORDS - 1]);

    for (int i = 0; i < N_WORDS; i++) {
        if (table[i] != F(i)) {
            if (errors < 8)
                printf("mismatch @0x%08x: got 0x%08x, expected 0x%08x\n",
                       (unsigned)&table[i], (unsigned)table[i], (unsigned)F(i));
            errors++;
        }
    }

    printf("%d errors\n", errors);
    return errors;
}
