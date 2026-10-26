/*
 * Cycle counting with the standard RISC-V mcycle/mcycleh CSRs.
 *
 * Works on CV32E40P and Ibex, in simulation and on hardware. The counter
 * counts core clock cycles, so results are comparable between the two as long
 * as no printf/UART output happens inside the measured region.
 *
 * Usage:
 *   cycles_enable();                    // once, CV32E40P resets with it off
 *   uint64_t t0 = cycles_read();
 *   f();
 *   uint64_t n = cycles_read() - t0 - cycles_overhead();
 *   ... print n afterwards (cycles_print) ...
 */
#ifndef CYCLES_H
#define CYCLES_H

#include <stdint.h>
#include <stdio.h>

#define CSR_MCOUNTINHIBIT 0x320
#define CSR_MCYCLE        0xB00
#define CSR_MCYCLEH       0xB80

/* Clear mcountinhibit.CY. CV32E40P disables its counters out of reset. */
static inline void cycles_enable(void)
{
    asm volatile("csrci %0, 1" :: "i"(CSR_MCOUNTINHIBIT));
}

/* 64-bit cycle count. Re-reads if the low word wrapped between the reads. */
static inline uint64_t cycles_read(void)
{
    uint32_t hi, lo, hi2;
    do {
        asm volatile("csrr %0, %1" : "=r"(hi)  : "i"(CSR_MCYCLEH));
        asm volatile("csrr %0, %1" : "=r"(lo)  : "i"(CSR_MCYCLE));
        asm volatile("csrr %0, %1" : "=r"(hi2) : "i"(CSR_MCYCLEH));
    } while (hi != hi2);
    return ((uint64_t)hi << 32) | lo;
}

/* Cycles measured for an empty region, i.e. the cost of cycles_read() itself.
 * Subtract it from measurements to get the cycles of the code in between. */
static inline uint64_t cycles_overhead(void)
{
    uint64_t t0 = cycles_read();
    uint64_t t1 = cycles_read();
    return t1 - t0;
}

/* The minimal libc printf has no 64-bit integer support, so format here. */
static inline void cycles_print(const char *label, uint64_t cycles)
{
    char buf[21];
    int  i = sizeof(buf) - 1;

    buf[i] = '\0';
    do {
        buf[--i] = '0' + (char)(cycles % 10);
        cycles /= 10;
    } while (cycles != 0);

    printf("%s: %s cycles\n", label, &buf[i]);
}

#endif
