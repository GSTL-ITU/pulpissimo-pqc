# Kyber sources are shared with tests/kyber_ref (single copy of the code).
# test_kyber.c is left out: this test has its own main().
KYBER_DIR := ../kyber_ref
PULP_APP_SRCS += $(filter-out $(KYBER_DIR)/test_kyber.c,$(wildcard $(KYBER_DIR)/*.c))
PULP_APP_CFLAGS += -I$(KYBER_DIR)

# Kyber parameter set: 2 = Kyber512, 3 = Kyber768, 4 = Kyber1024
KYBER_K ?= 3
PULP_APP_CFLAGS += -DKYBER_K=$(KYBER_K)
# Separate build directory per configuration (see tests/Makefile)
SW_VARIANT = k$(KYBER_K)

# Keys, ciphertexts and polynomial vectors live on the stack
STACK_SIZE = 0x8000

TIMEOUT_US = 2000000
