# Dilithium parameter set: 2, 3 or 5 (Dilithium2 / 3 / 5)
DILITHIUM_MODE ?= 2
# Iterations of the checks in test_dilithium.c (upstream default: 10000)
NTESTS ?= 1

PULP_APP_CFLAGS += -DDILITHIUM_MODE=$(DILITHIUM_MODE) -DNTESTS=$(NTESTS)

# The reference code keeps the public matrix and other polynomial vectors on
# the stack. Sized from the peak usage measured by dilithium_cycles; see
# README.md.
STACK_SIZE = 0x20000

TIMEOUT_US = 4000000
