# Builds one test with pulp-runtime. Invoked by tests/Makefile from inside the
# test directory:
#
#   make -C tests/<name> -f ../env/sw.mk TEST=<name> TARGET_BUILD_DIR=<dir> all
#
# Every *.c / *.S file in the test directory is compiled. A test can add flags
# or sources through an optional `test.mk` in its directory, e.g.
#   PULP_APP_CFLAGS += -DFOO=1
#   PULP_APP_SRCS   += ../common/util.c

ENV_DIR := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Equivalent of `source sw/pulp-runtime/configs/pulpissimo_cv32.sh`
export PULPRT_HOME   := $(abspath $(ENV_DIR)/../../sw/pulp-runtime)
export PULP_SDK_HOME := $(PULPRT_HOME)
export PULPRT_TARGET := pulpissimo
export PULPRUN_TARGET := pulpissimo
export CONFIG_PLUSARG_SIM := 1
ifeq ($(CORE),ibex)
export USE_IBEX := 1
else
export USE_CV32E40P := 1
endif

# The upstream defaults (-march=rv32imfc_xcorev) need the PULP GCC fork. These
# work with a stock riscv32-unknown-elf GCC:
# * no PULP extensions (xcorev / xpulp)
# * link with rv32imafc so a matching ilp32f libgcc multilib is picked; the
#   code itself is compiled without atomics, which the core lacks
# * gnu11, since pulp-runtime does not build as C23 (default of GCC >= 15)
ifeq ($(CORE),ibex)
PULP_ARCH_CFLAGS  ?= -march=rv32imc_zicsr_zifencei -mabi=ilp32 -std=gnu11
PULP_ARCH_LDFLAGS ?= -march=rv32imc_zicsr_zifencei -mabi=ilp32
else
PULP_ARCH_CFLAGS  ?= -march=rv32imfc_zicsr_zifencei -mabi=ilp32f -std=gnu11
PULP_ARCH_LDFLAGS ?= -march=rv32imafc_zicsr_zifencei -mabi=ilp32f
endif

PULP_APP          = $(TEST)
PULP_APP_SRCS     = $(wildcard *.c)
PULP_APP_ASM_SRCS = $(wildcard *.S)
PULP_CFLAGS      += -O2 -g
# Shared test helpers, e.g. #include "cycles.h"
PULP_APP_CFLAGS  += -I$(ENV_DIR)include

-include test.mk

include $(PULPRT_HOME)/rules/pulp.mk
