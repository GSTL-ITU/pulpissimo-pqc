/*
 * Cycle counts of the three Kyber KEM operations: key generation,
 * encapsulation and decapsulation, plus the peak stack usage.
 *
 * Each call is measured on its own, with nothing but the call between the two
 * counter reads; all printing happens after the measurements. The Kyber
 * sources are compiled from ../kyber_ref (see test.mk).
 *
 * randombytes() is a fixed-seed PRNG, so every run uses the same keys and the
 * counts are reproducible.
 */
#include <stdio.h>
#include <stdint.h>
#include <string.h>
#include "kem.h"
#include "cycles.h"
#include "stack.h"

int main(void)
{
    static uint8_t pk[CRYPTO_PUBLICKEYBYTES];
    static uint8_t sk[CRYPTO_SECRETKEYBYTES];
    static uint8_t ct[CRYPTO_CIPHERTEXTBYTES];
    static uint8_t key_a[CRYPTO_BYTES];
    static uint8_t key_b[CRYPTO_BYTES];
    uint64_t t0, overhead, cyc_keypair, cyc_enc, cyc_dec;

    stack_paint();
    cycles_enable();
    overhead = cycles_overhead();

    t0 = cycles_read();
    crypto_kem_keypair(pk, sk);
    cyc_keypair = cycles_read() - t0 - overhead;

    t0 = cycles_read();
    crypto_kem_enc(ct, key_b, pk);
    cyc_enc = cycles_read() - t0 - overhead;

    t0 = cycles_read();
    crypto_kem_dec(key_a, ct, sk);
    cyc_dec = cycles_read() - t0 - overhead;

    /* Everything below is outside the measured regions */
    printf("Kyber%d\n", KYBER_K * 256);
    cycles_print("crypto_kem_keypair", cyc_keypair);
    cycles_print("crypto_kem_enc    ", cyc_enc);
    cycles_print("crypto_kem_dec    ", cyc_dec);
    cycles_print("measurement overhead (subtracted)", overhead);
    printf("peak stack usage: %u of %u bytes\n",
           (unsigned)stack_max_used(), (unsigned)stack_size());

    if (stack_overflowed()) {
        printf("ERROR: stack overflow, raise STACK_SIZE in test.mk\n");
        return 1;
    }
    /* The measurements only count if the operations were correct */
    if (memcmp(key_a, key_b, CRYPTO_BYTES)) {
        printf("ERROR: shared keys differ\n");
        return 1;
    }
    printf("shared keys match\n");
    return 0;
}
