# Kyber parameter set: 2 = Kyber512, 3 = Kyber768, 4 = Kyber1024
KYBER_K ?= 3
# Iterations of the three checks in test_kyber.c (upstream default: 1000)
NTESTS  ?= 1

PULP_APP_CFLAGS += -DKYBER_K=$(KYBER_K) -DNTESTS=$(NTESTS)

# Keys, ciphertexts and polynomial vectors live on the stack
STACK_SIZE = 0x8000

TIMEOUT_US = 2000000
