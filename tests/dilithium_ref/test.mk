# Dilithium parameter set: 2, 3 or 5 (Dilithium2 / 3 / 5)
DILITHIUM_MODE ?= 2
# Iterations of the checks in test_dilithium.c (upstream default: 10000)
NTESTS ?= 1

PULP_APP_CFLAGS += -DDILITHIUM_MODE=$(DILITHIUM_MODE) -DNTESTS=$(NTESTS)
# Separate build directory per configuration (see tests/Makefile)
SW_VARIANT = mode$(DILITHIUM_MODE)-n$(NTESTS)

# The reference code keeps the public matrix and other polynomial vectors on
# the stack. Sized from the peak usage measured by dilithium_cycles (see
# README.md): Dilithium2 stays at 128 KiB so its code layout, and therefore
# its cycle counts, match earlier runs; the larger modes get 192 KiB.
ifeq ($(DILITHIUM_MODE),2)
STACK_SIZE = 0x20000
else
STACK_SIZE = 0x30000
endif

# Simulated-time limit; signing time varies (rejection sampling)
TIMEOUT_US = 8000000
