# Dilithium sources are shared with tests/dilithium_ref (single copy of the
# code). test_dilithium.c is left out: this test has its own main().
DILITHIUM_DIR := ../dilithium_ref
PULP_APP_SRCS += $(filter-out $(DILITHIUM_DIR)/test_dilithium.c,$(wildcard $(DILITHIUM_DIR)/*.c))
PULP_APP_CFLAGS += -I$(DILITHIUM_DIR)

# Dilithium parameter set: 2, 3 or 5 (Dilithium2 / 3 / 5)
DILITHIUM_MODE ?= 2
PULP_APP_CFLAGS += -DDILITHIUM_MODE=$(DILITHIUM_MODE)
# Separate build directory per configuration (see tests/Makefile)
SW_VARIANT = mode$(DILITHIUM_MODE)

# The reference code keeps the public matrix and other polynomial vectors on
# the stack. Sized from the peak usage this test measures (see README.md):
# Dilithium2 stays at 128 KiB so its code layout, and therefore its cycle
# counts, match earlier runs; the larger modes get 192 KiB.
ifeq ($(DILITHIUM_MODE),2)
STACK_SIZE = 0x20000
else
STACK_SIZE = 0x30000
endif

# Simulated-time limit; signing time varies (rejection sampling)
TIMEOUT_US = 8000000
