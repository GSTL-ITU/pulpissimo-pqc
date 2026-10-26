# Dilithium sources are shared with tests/dilithium_ref (single copy of the
# code). test_dilithium.c is left out: this test has its own main().
DILITHIUM_DIR := ../dilithium_ref
PULP_APP_SRCS += $(filter-out $(DILITHIUM_DIR)/test_dilithium.c,$(wildcard $(DILITHIUM_DIR)/*.c))
PULP_APP_CFLAGS += -I$(DILITHIUM_DIR)

# Dilithium parameter set: 2, 3 or 5 (Dilithium2 / 3 / 5)
DILITHIUM_MODE ?= 2
PULP_APP_CFLAGS += -DDILITHIUM_MODE=$(DILITHIUM_MODE)

# See dilithium_ref/test.mk
STACK_SIZE = 0x20000

TIMEOUT_US = 4000000
