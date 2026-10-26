# Verilator test environment for PULPissimo
#
#   make                  list available tests and targets
#   make hw               verilate the SoC + testbench (done automatically)
#   make run TEST=hello   build and simulate one test
#   make all-tests        build and simulate every test, print a summary
#
# A test is any directory next to this Makefile that contains *.c or *.S
# files. See README.md for details.

ROOT      := $(abspath $(CURDIR)/..)
TESTS_DIR := $(CURDIR)
ENV_DIR   := $(TESTS_DIR)/env
BUILD_DIR := $(TESTS_DIR)/build
BENDER    := $(ROOT)/utils/bin/bender

# Simulation options
CORE       ?= cv32e40p
TIMEOUT_US ?= 100000
WAVES      ?= 0
SW_VERBOSE ?= 0
JOBS       ?= $(shell nproc)

ifeq ($(CORE),ibex)
CORE_TYPE := 1
USE_FPU   := 0
else ifeq ($(CORE),cv32e40p)
CORE_TYPE := 0
USE_FPU   := 1
else
$(error CORE must be cv32e40p or ibex)
endif

SIM_DIR := $(BUILD_DIR)/sim-$(CORE)
SIM_BIN := $(SIM_DIR)/Vtb_verilator

TESTS := $(sort $(patsubst %/,%,$(dir $(wildcard */*.c */*.S))))
TESTS := $(filter-out env build,$(TESTS))

.PHONY: help
help:
	@echo "Tests: $(TESTS)"
	@echo ""
	@echo "Targets:"
	@echo "  make run TEST=<name>   build + simulate one test"
	@echo "  make sw TEST=<name>    only build the test binary"
	@echo "  make all-tests         run every test and print a summary"
	@echo "  make hw                (re)build the Verilator model"
	@echo "  make clean / clean-sw"
	@echo ""
	@echo "Options: CORE=cv32e40p|ibex  TIMEOUT_US=$(TIMEOUT_US)  WAVES=1  SW_VERBOSE=1  JOBS=$(JOBS)"

############
# Hardware #
############

# The vendored adv_dbg_if manifest lists `rtl/adbg_axi_biu.sv,` (stray comma),
# which bender >= 0.29 rejects. Exclude the package and add its files here.
ADV_DBG_DIR = $(shell $(BENDER) -d $(ROOT) path adv_dbg_if 2>/dev/null)
ADV_DBG_FILES = adbg_axi_biu.sv adbg_axi_module.sv adbg_lint_biu.sv \
  adbg_lint_module.sv adbg_crc32.v adbg_or1k_biu.sv adbg_or1k_module.sv \
  adbg_or1k_status_reg.sv adbg_top.sv bytefifo.v syncflop.v syncreg.v \
  adbg_tap_top.v adv_dbg_if.sv adbg_axionly_top.sv adbg_lintonly_top.sv

VERILATOR_FLAGS := --binary --timing -j $(JOBS) --top-module tb_verilator \
  --timescale 1ns/1ps --trace-fst --trace-structs \
  -GCORE_TYPE=$(CORE_TYPE) -GUSE_FPU=$(USE_FPU) \
  -Wno-fatal -Wno-lint -Wno-style -Wno-MULTIDRIVEN -Wno-TIMESCALEMOD \
  -Wno-UNOPTFLAT -Wno-PINMISSING -Wno-SPLITVAR -Wno-ZERODLY -Wno-ENUMVALUE \
  -O3 --x-assign fast --x-initial fast --output-split 20000 \
  $(VERILATOR_EXTRA_FLAGS)

$(BENDER):
	$(MAKE) -C $(ROOT) checkout

# --no-default-target: `bender script verilator` otherwise also implies the
# `synthesis` target, which drops simulation-only RTL like the virtual stdout
# (tb_fs_handler). The switch-level pad models are swapped for env/ versions
# and tbtools (Questa DPI VIPs, unused here) is left out.
$(SIM_DIR)/files.f: $(ROOT)/Bender.lock $(MAKEFILE_LIST) | $(BENDER)
	@mkdir -p $(SIM_DIR)
	$(BENDER) -d $(ROOT) script verilator --no-default-target -t rtl -t rtl_sim -t verilator \
	  -e adv_dbg_if -e tbtools | grep -v "deprecated/pad_functional.sv" > $@.tmp
	echo "$(ENV_DIR)/pad_functional_verilator.sv" >> $@.tmp
	echo "$(ROOT)/hw/vendored_ips/gpio/src/gpio_input_stage.sv" >> $@.tmp
	echo "+incdir+$(ADV_DBG_DIR)/rtl" >> $@.tmp
	for f in $(ADV_DBG_FILES); do echo "$(ADV_DBG_DIR)/rtl/$$f" >> $@.tmp; done
	echo "$(SIM_DIR)/padframe_adapter.sv" >> $@.tmp
	echo "$(ENV_DIR)/clock_gen_verilator.sv" >> $@.tmp
	echo "$(ENV_DIR)/tb_verilator.sv" >> $@.tmp
	mv $@.tmp $@

# padframe_adapter.sv is excluded from the `verilator` target in Bender.yml.
# Use a copy with its $error format/argument mismatch fixed (Verilator rejects
# it, commercial simulators let it slide). The original is left untouched.
$(SIM_DIR)/padframe_adapter.sv: $(ROOT)/hw/padframe/padframe_adapter.sv
	@mkdir -p $(SIM_DIR)
	sed 's/udma_cfg_pkg::N_QSPIM);/udma_cfg_pkg::N_QSPIM, N_CONNECTED_QSPIM);/' $< > $@

$(SIM_BIN): $(SIM_DIR)/files.f $(SIM_DIR)/padframe_adapter.sv $(ENV_DIR)/tb_verilator.sv $(ENV_DIR)/clock_gen_verilator.sv
	verilator $(VERILATOR_FLAGS) -f $< --Mdir $(SIM_DIR)/obj -o $@ 2>&1 | tee $(SIM_DIR)/verilator.log
	@test -x $@

.PHONY: hw
hw: $(SIM_BIN)

############
# Software #
############

SW_DIR = $(BUILD_DIR)/sw-$(CORE)/$(TEST)
ELF    = $(SW_DIR)/$(TEST)/$(TEST)
MEM    = $(SW_DIR)/$(TEST).mem

.PHONY: check-test
check-test:
ifndef TEST
	$(error Set TEST=<name>. Available: $(TESTS))
endif
	@test -d $(TESTS_DIR)/$(TEST) || (echo "No such test: $(TEST)"; exit 1)

.PHONY: sw
sw: check-test
	@$(MAKE) --no-print-directory -C $(TESTS_DIR)/$(TEST) -f $(ENV_DIR)/sw.mk TEST=$(TEST) CORE=$(CORE) \
	  TARGET_BUILD_DIR=$(SW_DIR) $(if $(filter 1,$(SW_VERBOSE)),,QUIET=1) all
	@python3 -I $(ENV_DIR)/elf2mem.py $(ELF) $(MEM)
	@riscv32-unknown-elf-objdump -d -S $(ELF) > $(SW_DIR)/$(TEST).dis

#######
# Run #
#######

PLUSARGS := +MEM=$(MEM) +TIMEOUT_US=$(TIMEOUT_US)
ifeq ($(WAVES),1)
PLUSARGS += +WAVES=$(SW_DIR)/waves.fst
endif

.PHONY: run
run: sw $(SIM_BIN)
	cd $(SW_DIR) && $(SIM_BIN) $(PLUSARGS) 2>&1 | tee $(SW_DIR)/sim.log; exit $${PIPESTATUS[0]}

.PHONY: all-tests
all-tests: $(SIM_BIN)
	@pass=0; fail=0; failed=""; \
	for t in $(TESTS); do \
	  echo "=== $$t ==="; \
	  if $(MAKE) --no-print-directory run TEST=$$t > /dev/null 2>&1; then \
	    echo "PASS"; pass=$$((pass+1)); \
	  else \
	    echo "FAIL (log: $(BUILD_DIR)/sw-$(CORE)/$$t/sim.log)"; fail=$$((fail+1)); failed="$$failed $$t"; \
	  fi; \
	done; \
	echo ""; echo "Passed: $$pass  Failed: $$fail$$failed"; \
	test $$fail -eq 0

.PHONY: clean clean-sw
clean:
	rm -rf $(BUILD_DIR)
clean-sw:
	rm -rf $(BUILD_DIR)/sw-*

SHELL := /bin/bash
