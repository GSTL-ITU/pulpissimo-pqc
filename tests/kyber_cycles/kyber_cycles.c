/*
 * Cycle counts of the three Kyber KEM operations: key generation,
 * encapsulation and decapsulation, plus the peak stack usage.
 *
 * Each call is measured on its own, with nothing but the call between the two
 * counter reads; all printing happens after the measurements. The Kyber
 * sources are compiled from ../kyber_ref (see test.mk).
 *
 * randombytes() is a fixed-seed PRNG, so every run uses the same keys and the
 * counts are reproducible. With NTESTS > 1 the three operations are repeated;
 * each iteration continues the PRNG stream, i.e. gets new keys and new
 * encapsulation randomness, as with a different seed. Iteration 1 is the same
 * as a run with NTESTS = 1. The counts of every iteration are printed, then
 * min, median and max.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "kem.h"
#include "cycles.h"
#include "stack.h"

#ifndef NTESTS
#define NTESTS 1
#endif

int main(void)
{
    static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    static uint8_t sk[CRYPTO_SECRETKEYBYTES];
    static uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
    static uint8_t key_a[CRYPTO_BYTES];
    static uint8_t key_b[CRYPTO_BYTES];
    static uint64_t cyc_keypair[NTESTS], cyc_enc[NTESTS], cyc_dec[NTESTS];
    int failed = 0;
    uint64_t t0, overhead;

    stack_paint();
    cycles_enable();
    overhead = cycles_overhead();

    for (int i = 0; i < NTESTS; i++) {
        t0 = cycles_read();
        crypto_kem_keypair(pk, sk);
        cyc_keypair[i] = cycles_read() - t0 - overhead;

        t0 = cycles_read();
        crypto_kem_enc(ct, key_b, pk);
        cyc_enc[i] = cycles_read() - t0 - overhead;

        t0 = cycles_read();
        crypto_kem_dec(key_a, ct, sk);
        cyc_dec[i] = cycles_read() - t0 - overhead;

        /* The measurements only count if the operations were correct */
        if (memcmp(key_a, key_b, CRYPTO_BYTES))
            failed++;
    }

    /* Everything below is outside the measured regions */
    printf("Kyber%d\n", KYBER_K * 256);
    for (int i = 0; i < NTESTS; i++) {
        if (NTESTS > 1)
            printf("iteration %d\n", i + 1);
        cycles_print("crypto_kem_keypair", cyc_keypair[i]);
        cycles_print("crypto_kem_enc    ", cyc_enc[i]);
        cycles_print("crypto_kem_dec    ", cyc_dec[i]);
    }
    if (NTESTS > 1) {
        printf("over %d iterations\n", NTESTS);
        cycles_print_stats("crypto_kem_keypair", cyc_keypair, NTESTS);
        cycles_print_stats("crypto_kem_enc    ", cyc_enc, NTESTS);
        cycles_print_stats("crypto_kem_dec    ", cyc_dec, NTESTS);
    }
    cycles_print("measurement overhead (subtracted)", overhead);
    printf("peak stack usage: %u of %u bytes\n",
           (unsigned)stack_max_used(), (unsigned)stack_size());

    if (stack_overflowed()) {
        printf("ERROR: stack overflow, raise STACK_SIZE in test.mk\n");
        return 1;
    }
    if (failed) {
        printf("ERROR: shared keys differ in %d of %d iterations\n", failed, NTESTS);
        return 1;
    }
    printf("shared keys match\n");
    return 0;
}
