/*
 * Cycle counts of the three Dilithium (ML-DSA) operations: key generation,
 * signing and verification, plus the peak stack usage.
 *
 * Each call is measured on its own, with nothing but the call between the two
 * counter reads; all printing happens after the measurements. The Dilithium
 * sources are compiled from ../dilithium_ref (see test.mk). Message length and
 * context are the same as in test_dilithium.c.
 *
 * randombytes() is a fixed-seed PRNG, so every run uses the same keys,
 * message and signing randomness, and the counts are reproducible. Signing
 * time depends on how many rejection-sampling rounds a given input needs, so
 * a different seed or message gives a different signing count.
 *
 * With NTESTS > 1 the three operations are repeated; each iteration continues
 * the PRNG stream, i.e. gets a new message, new keys and new signing
 * randomness, as with a different seed. Iteration 1 is the same as a run with
 * NTESTS = 1. The counts of every iteration are printed, then min, median and
 * max.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "randombytes.h"
#include "sign.h"
#include "cycles.h"
#include "stack.h"

#define MLEN   59
#define CTXLEN 14

#ifndef NTESTS
#define NTESTS 1
#endif

int main(void)
{
    static uint8_t ctx[CTXLEN];
    static uint8_t m[MLEN];
    static uint8_t m2[MLEN + CRYPTO_BYTES];
    static uint8_t sm[MLEN + CRYPTO_BYTES];
    static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    static uint8_t sk[CRYPTO_SECRETKEYBYTES];
    static uint64_t cyc_keypair[NTESTS], cyc_sign[NTESTS], cyc_open[NTESTS];
    size_t smlen, mlen;
    int ret, failed = 0;
    uint64_t t0, overhead;

    snprintf((char *)ctx, CTXLEN, "test_dilitium");

    stack_paint();
    cycles_enable();
    overhead = cycles_overhead();

    for (int i = 0; i < NTESTS; i++) {
        randombytes(m, MLEN);

        t0 = cycles_read();
        crypto_sign_keypair(pk, sk);
        cyc_keypair[i] = cycles_read() - t0 - overhead;

        t0 = cycles_read();
        crypto_sign(sm, &smlen, m, MLEN, ctx, CTXLEN, sk);
        cyc_sign[i] = cycles_read() - t0 - overhead;

        t0 = cycles_read();
        ret = crypto_sign_open(m2, &mlen, sm, smlen, ctx, CTXLEN, pk);
        cyc_open[i] = cycles_read() - t0 - overhead;

        /* The measurements only count if the operations were correct */
        if (ret != 0 || mlen != MLEN || smlen != MLEN + CRYPTO_BYTES ||
            memcmp(m, m2, MLEN) != 0)
            failed++;
    }

    /* Everything below is outside the measured regions */
    printf("Dilithium%d\n", DILITHIUM_MODE);
    for (int i = 0; i < NTESTS; i++) {
        if (NTESTS > 1)
            printf("iteration %d\n", i + 1);
        cycles_print("crypto_sign_keypair", cyc_keypair[i]);
        cycles_print("crypto_sign        ", cyc_sign[i]);
        cycles_print("crypto_sign_open   ", cyc_open[i]);
    }
    if (NTESTS > 1) {
        printf("over %d iterations\n", NTESTS);
        cycles_print_stats("crypto_sign_keypair", cyc_keypair, NTESTS);
        cycles_print_stats("crypto_sign        ", cyc_sign, NTESTS);
        cycles_print_stats("crypto_sign_open   ", cyc_open, NTESTS);
    }
    cycles_print("measurement overhead (subtracted)", overhead);
    printf("peak stack usage: %u of %u bytes\n",
           (unsigned)stack_max_used(), (unsigned)stack_size());

    if (stack_overflowed()) {
        printf("ERROR: stack overflow, raise STACK_SIZE in test.mk\n");
        return 1;
    }
    if (failed) {
        printf("ERROR: signature verification failed in %d of %d iterations\n",
               failed, NTESTS);
        return 1;
    }
    printf("signature verified\n");
    return 0;
}
