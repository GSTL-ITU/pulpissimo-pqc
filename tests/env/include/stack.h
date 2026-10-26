/*
 * Peak stack usage measurement ("stack painting").
 *
 * stack_paint() fills the unused part of the stack with a pattern;
 * stack_max_used() later finds how much of it was overwritten. Call both from
 * main(), outside any cycle measurement (painting a large stack takes a while).
 *
 *   stack_paint();
 *   run_the_code();
 *   printf("%u bytes\n", (unsigned)stack_max_used());
 *
 * The result includes main()'s own frame and crt0's usage above it. If
 * stack_overflowed() is true, the stack was too small: raise STACK_SIZE in
 * the test's test.mk.
 */
#ifndef STACK_H
#define STACK_H

#include <stdint.h>
#include <stddef.h>

#define STACK_PAINT 0xDEADBEEFu

/* Defined by pulp-runtime's linker script: the stack grows down from
 * `stack` towards `stack_start`. */
extern uint32_t stack_start[];
extern uint32_t stack[];

static inline void stack_paint(void)
{
    uintptr_t sp;
    asm volatile("mv %0, sp" : "=r"(sp));

    /* Leave a margin below the current frame for this function itself */
    volatile uint32_t *end = (volatile uint32_t *)((sp - 64) & ~(uintptr_t)3);
    for (volatile uint32_t *p = stack_start; p < end; p++)
        *p = STACK_PAINT;
}

/* Bytes between the top of the stack and the deepest overwritten word */
static inline size_t stack_max_used(void)
{
    volatile uint32_t *p = stack_start;
    while (p < stack && *p == STACK_PAINT)
        p++;
    return (size_t)((uintptr_t)stack - (uintptr_t)p);
}

static inline size_t stack_size(void)
{
    return (size_t)((uintptr_t)stack - (uintptr_t)stack_start);
}

/* The lowest word was overwritten: the stack (very likely) overflowed */
static inline int stack_overflowed(void)
{
    return stack_start[0] != STACK_PAINT;
}

#endif
