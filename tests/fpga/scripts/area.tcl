# Area (and optionally timing) reports for PULPissimo on the Nexys 4 DDR.
#
#   vivado -mode batch -source area.tcl -tclargs <out_dir> <root> <core_type> <use_fpu> <regfile> <impl> <jobs>
#
# <out_dir>    build directory; must contain compile.tcl and xilinx_pulpissimo.v
#              (written by tests/fpga/Makefile)
# <root>       PULPissimo repository root
# <core_type>  0: CV32E40P, 1: Ibex RV32IMC (top-level parameter CORE_TYPE)
# <use_fpu>    0/1, CV32E40P only (top-level parameter USE_FPU)
# <regfile>    Ibex register file: fpga (PULPissimo's FPGA default) or ff
# <impl>       0: synthesis + opt_design; 1: also place and route + timing
#
# Reports (in <out_dir>/reports):
#   util_<stage>.rpt       utilization of the whole design
#   util_hier_<stage>.rpt  utilization per hierarchy level
#   timing_route.rpt       timing summary (impl=1 only)
# <stage> is "opt" (after synthesis and opt_design) or "route" (impl=1).
#
# Follows target/fpga/pulpissimo-nexys/tcl/run.tcl (same sources, defines,
# clock IPs and constraints) but builds everything in <out_dir> and stops
# after the reports instead of writing a bitstream.

lassign $argv out_dir root core_type use_fpu regfile impl jobs

set part   xc7a100tcsg324-1
set nexys  $root/target/fpga/pulpissimo-nexys
set rpt    $out_dir/reports
file mkdir $rpt

create_project -force pulpissimo_area $out_dir/project -part $part
# tc_sram_xilinx.sv (all SoC memories) uses xpm_memory_spram; with -sfcu,
# Vivado doesn't detect that on its own
set_property XPM_LIBRARIES {XPM_MEMORY XPM_CDC} [current_project]

# Same message settings as the upstream flow
set_msg_config -id {[Synth 8-3352]}         -new_severity "critical warning"
set_msg_config -id {[Synth 8-350]}          -new_severity "critical warning"
set_msg_config -id {[Synth 8-2490]}         -new_severity "warning"
set_msg_config -id {[Synth 8-2306]}         -new_severity "info"
set_msg_config -id {[Synth 8-3331]}         -new_severity "critical warning"
set_msg_config -id {[Synth 8-3332]}         -new_severity "info"
set_msg_config -id {[Synth 8-2715]}         -new_severity "error"
set_msg_config -id {[Opt 31-35]}            -new_severity "info"
set_msg_config -id {[Opt 31-32]}            -new_severity "info"
set_msg_config -id {[Shape Builder 18-119]} -new_severity "warning"
set_msg_config -id {[Filemgmt 20-742]}      -new_severity "error"

# RTL from Bender (targets fpga, xilinx), plus the adv_dbg_if files that the
# Makefile lists by hand (see tests/Makefile)
source $out_dir/compile.tcl
source $out_dir/adv_dbg_if.tcl

# Defines: the upstream flow's, plus the Bender target defines. (Bender 0.31
# puts those on the simulation fileset only, so the upstream flow loses them.
# TARGET_FPGA selects Ibex's FPGA register file, as fc_subsystem.sv intends.)
set defines {FPGA_TARGET_XILINX=1 PULP_FPGA_EMUL=1 AXI4_XCHECK_OFF=1 NEXYS=1
             TARGET_FPGA TARGET_XILINX TARGET_SYNTHESIS TARGET_VIVADO}
if {$regfile == "ff"} {
  lappend defines TARGET_IBEX_USE_FF_REGFILE
}
set_property verilog_define $defines [current_fileset]

# Top level: copy of the Nexys wrapper with CORE_TYPE / USE_FPU as parameters
add_files -norecurse $out_dir/xilinx_pulpissimo.v
set_property top xilinx_pulpissimo [current_fileset]
set_property generic "CORE_TYPE=$core_type USE_FPU=$use_fpu" [current_fileset]

# Xilinx-specific wrappers and tech cells, as in run.tcl
add_files -norecurse [lmap f {fpga_clk_gen.sv fpga_slow_clk_gen.sv fpga_bootrom.sv
                               pad_functional_xilinx.sv pulp_clock_gating_xilinx.sv
                               cv32e40p_clock_gate_xilinx.sv} {string cat $nexys/rtl/$f}]

# Clocking wizard IPs, configured as in ips/*/tcl/run.tcl with the Nexys
# settings (fpga-settings.mk): SoC 10 MHz, peripherals 5 MHz, slow clock
set FC_CLK_FREQ_MHZ   [expr 1000 / 100]
set PER_CLK_FREQ_MHZ  [expr 1000 / 200]
set SLOW_CLK_FREQ_MHZ [expr 1000 * 256 / 30517]

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name xilinx_clk_mngr
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
                        CONFIG.NUM_OUT_CLKS {2} \
                        CONFIG.CLKOUT2_USED {true} \
                        CONFIG.RESET_TYPE {ACTIVE_LOW} \
                        CONFIG.RESET_PORT {resetn} \
                        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $FC_CLK_FREQ_MHZ \
                        CONFIG.CLKOUT2_REQUESTED_OUT_FREQ $PER_CLK_FREQ_MHZ \
                        CONFIG.CLKIN1_JITTER_PS {50.0} \
                       ] [get_ips xilinx_clk_mngr]

create_ip -name clk_wiz -vendor xilinx.com -library ip -module_name xilinx_slow_clk_mngr
set_property -dict [list CONFIG.PRIM_IN_FREQ {100.000} \
                        CONFIG.CLKOUT1_REQUESTED_OUT_FREQ $SLOW_CLK_FREQ_MHZ \
                        CONFIG.USE_SAFE_CLOCK_STARTUP {true} \
                        CONFIG.USE_LOCKED {false} \
                        CONFIG.RESET_TYPE {ACTIVE_LOW} \
                        CONFIG.CLKIN1_JITTER_PS {50.0} \
                        CONFIG.FEEDBACK_SOURCE {FDBK_AUTO} \
                        CONFIG.RESET_PORT {resetn} \
                       ] [get_ips xilinx_slow_clk_mngr]
generate_target all [get_ips]

add_files -fileset constrs_1 -norecurse $nexys/constraints/nexys4DDR.xdc
update_compile_order -fileset sources_1

# Synthesis as upstream: single file compilation unit, hierarchy kept, so
# every block shows up in the hierarchical report
set_property STEPS.SYNTH_DESIGN.ARGS.FLATTEN_HIERARCHY none [get_runs synth_1]
set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -value -sfcu -objects [get_runs synth_1]
launch_runs synth_1 -jobs $jobs
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
  puts "ERROR: synthesis failed, see [get_property DIRECTORY [get_runs synth_1]]/runme.log"
  exit 1
}
open_run synth_1

# Tie off the unused pads, as run.tcl does: the pad driver also drives the
# input, so these IOBUFs would otherwise not be optimized away
set pads i_pulpissimo/i_padframe/i_pulpissimo_pads/i_all_pads/i_all_pads_pads
set soc  i_pulpissimo/i_soc_domain
remove_cell [get_cells $pads/i_pad_bootsel*]
disconnect_net -objects [get_nets $soc/bootsel_i*]
connect_net -objects [get_nets $soc/bootsel_i*] -net i_pulpissimo/<const0>
remove_cell [get_cells $pads/i_pad_hyper*]
disconnect_net -objects [get_nets $soc/pad_to_hyper_i*]
connect_net -objects [get_nets $soc/pad_to_hyper_i*] -net i_pulpissimo/<const0>
remove_cell [get_cells $pads/i_pad_jtag_trst*]
disconnect_net -objects [get_nets $soc/jtag_trst_ni]
connect_net -objects [get_nets $soc/jtag_trst_ni] -net i_pulpissimo/<const1>

proc write_reports {rpt stage} {
  report_utilization -file $rpt/util_${stage}.rpt
  report_utilization -hierarchical -hierarchical_depth 12 \
    -file $rpt/util_hier_${stage}.rpt
}

# opt_design removes logic without loads and propagates constants, like the
# implementation flow does, so the numbers are what really ends up on the FPGA
opt_design
write_reports $rpt opt

if {$impl} {
  place_design
  route_design
  write_reports $rpt route
  report_timing_summary -file $rpt/timing_route.rpt
}

puts "INFO: reports written to $rpt"
