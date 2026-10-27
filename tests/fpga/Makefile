# FPGA area (and timing) reports for PULPissimo on the Nexys 4 DDR (XC7A100T).
#
#   make area                      CV32E40P with FPU (the upstream FPGA configuration)
#   make area CORE=ibex            Ibex RV32IMC
#   make compare                   both, plus a side-by-side summary
#   make help                      all targets and variables
#
# Uses Bender for the RTL list, scripts/area.tcl for the Vivado project,
# synthesis and reports, and scripts/area_summary.py for the breakdown.
# Nothing outside tests/build/fpga is written.

FPGA_DIR  := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ROOT      := $(abspath $(FPGA_DIR)/../..)
BUILD_DIR := $(abspath $(FPGA_DIR)/../build/fpga)
BENDER    := $(ROOT)/utils/bin/bender
NEXYS_TOP := $(ROOT)/target/fpga/pulpissimo-nexys/rtl/xilinx_pulpissimo.v

CORE    ?= cv32e40p
# CV32E40P only: 0 builds the core without its FPU (fpnew)
USE_FPU ?= 1
# Ibex only: register file, fpga (LUT RAM, what PULPissimo picks for FPGA) or ff
REGFILE ?= fpga
# 1: also place and route, with utilization and timing after routing
IMPL    ?= 0
JOBS    ?= $(shell nproc 2>/dev/null || echo 4)
VIVADO  ?= vivado

STAGE := $(if $(filter 1,$(IMPL)),route,opt)

ifeq ($(CORE),cv32e40p)
CORE_TYPE := 0
OUT       := $(BUILD_DIR)/cv32e40p$(if $(filter 0,$(USE_FPU)),-nofpu)
SYS_DESC  := CV32E40P, USE_FPU=$(USE_FPU)
else ifeq ($(CORE),ibex)
CORE_TYPE := 1
override USE_FPU := 0
OUT       := $(BUILD_DIR)/ibex$(if $(filter ff,$(REGFILE)),-regff)
SYS_DESC  := Ibex RV32IMC, $(REGFILE) register file
else
$(error CORE must be cv32e40p or ibex)
endif

# See tests/Makefile: the adv_dbg_if manifest has a typo that Bender rejects,
# so the package is excluded and its files are added here
ADV_DBG_DIR = $(shell $(BENDER) -d $(ROOT) path adv_dbg_if 2>/dev/null)
ADV_DBG_FILES = adbg_axi_biu.sv adbg_axi_module.sv adbg_lint_biu.sv \
  adbg_lint_module.sv adbg_crc32.v adbg_or1k_biu.sv adbg_or1k_module.sv \
  adbg_or1k_status_reg.sv adbg_top.sv bytefifo.v syncflop.v syncreg.v \
  adbg_tap_top.v adv_dbg_if.sv adbg_axionly_top.sv adbg_lintonly_top.sv

.PHONY: help area compare clean check-tools print-out

help:
	@echo "Usage:"
	@echo "  make area [CORE=cv32e40p|ibex]  synthesis + area report -> build/fpga/<core>/area.md"
	@echo "  make compare                    both cores + side-by-side summary -> build/fpga/compare.md"
	@echo "  make clean                      remove build/fpga"
	@echo ""
	@echo "Variables: CORE=$(CORE) USE_FPU=$(USE_FPU) REGFILE=$(REGFILE) IMPL=$(IMPL) JOBS=$(JOBS) VIVADO=$(VIVADO)"

check-tools:
	@command -v $(VIVADO) >/dev/null 2>&1 || { echo "Error: $(VIVADO) not found, add Vivado's bin/ to PATH or set VIVADO=<path>"; exit 1; }
	@test -x $(BENDER) || $(MAKE) -C $(ROOT) checkout

# Regenerated every time (seconds), so RTL and Bender.lock changes are picked up
area: check-tools
	@echo "=== $(SYS_DESC)"
	rm -rf $(OUT)
	mkdir -p $(OUT)
	$(BENDER) -d $(ROOT) script vivado -t fpga -t xilinx -e adv_dbg_if > $(OUT)/compile.tcl
	{ echo "add_files -norecurse [list \\"; \
	  for f in $(ADV_DBG_FILES); do echo "  $(ADV_DBG_DIR)/rtl/$$f \\"; done; \
	  echo "]"; \
	  echo "set_property include_dirs [concat [get_property include_dirs [current_fileset]] $(ADV_DBG_DIR)/rtl] [current_fileset]"; \
	} > $(OUT)/adv_dbg_if.tcl
	# The upstream top hard-codes CORE_TYPE and USE_FPU as localparams; the
	# copy makes them parameters that Vivado can set
	sed -e 's/localparam CORE_TYPE/parameter CORE_TYPE/' -e 's/localparam USE_FPU/parameter USE_FPU/' \
	  $(NEXYS_TOP) > $(OUT)/xilinx_pulpissimo.v
	@echo "Running Vivado (~15-30 min), log: $(OUT)/vivado.log"
	cd $(OUT) && $(VIVADO) -mode batch -nojournal -log $(OUT)/vivado.log -source $(FPGA_DIR)/scripts/area.tcl \
	  -tclargs $(OUT) $(ROOT) $(CORE_TYPE) $(USE_FPU) $(REGFILE) $(IMPL) $(JOBS) > $(OUT)/vivado_stdout.log 2>&1 || \
	  { grep -E "^ERROR" $(OUT)/vivado.log | head -20; echo "Error: Vivado failed, see $(OUT)/vivado.log"; exit 1; }
	@echo "$(SYS_DESC)" > $(OUT)/description.txt
	python3 $(FPGA_DIR)/scripts/area_summary.py "$(CORE)=$(OUT)/reports/util_hier_$(STAGE).rpt" \
	  -o $(OUT)/area.md
ifeq ($(IMPL),1)
	@grep -A3 "WNS(ns)" $(OUT)/reports/timing_route.rpt | head -4
endif

# Both cores with the current settings, then one summary
compare:
	$(MAKE) area CORE=cv32e40p
	$(MAKE) area CORE=ibex
	python3 $(FPGA_DIR)/scripts/area_summary.py \
	  "cv32e40p=$$($(MAKE) -s print-out CORE=cv32e40p)/reports/util_hier_$(STAGE).rpt" \
	  "ibex=$$($(MAKE) -s print-out CORE=ibex)/reports/util_hier_$(STAGE).rpt" \
	  -o $(BUILD_DIR)/compare.md

print-out:
	@echo $(OUT)

clean:
	rm -rf $(BUILD_DIR)
