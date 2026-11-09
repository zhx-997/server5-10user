# E203 + NICE：设置、约束、一次综合、结果输出。
# 运行：SOC_PATHS=/工程/flow/paths.tcl dc_shell -topographical_mode -f flow/dc_synth.tcl
set_app_var sh_continue_on_error false
set initial_errors [get_message_info -error_count]
set SCRIPT_DIR [file dirname [file normalize [info script]]]
set PATH_CONFIG $SCRIPT_DIR/paths.tcl
if {[info exists env(SOC_PATHS)]} {set PATH_CONFIG [file normalize $env(SOC_PATHS)]}
source $PATH_CONFIG
set TOP kwt_e203_soc_top
set OUT $RUN_ROOT/nice_rtl_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]
file mkdir $OUT/work $OUT/netlist $OUT/reports $OUT/scratch
foreach name {TMPDIR TMP TEMP} {set env($name) $OUT/scratch}
cd $OUT

# ==================== LIB / SRAM / HDL / INC ====================
# SS 低温用于建立、FF 高温用于保持，取自 P6 全角实测最差条件。
set MAX_CORNER ss_v0p99_-40c
set MIN_CORNER ff_v1p21_125c
set STD_MAX $LIB_PATH/scc40nll_vhsc40_hvt_${MAX_CORNER}_basic.db
set STD_MIN $LIB_PATH/scc40nll_vhsc40_hvt_${MIN_CORNER}_basic.db
set MAX_LIB_NAME [file rootname [file tail $STD_MAX]]
set MIN_LIB_NAME [file rootname [file tail $STD_MIN]]
set SRAM_LIB_PATH [list $SMALL_SRAM_ORIGINAL $SMALL_SRAM_DERIVED]
set SRAM_MAX {}
set SRAM_MIN {}
foreach macro {RAMSP128X16 RAMSP1024X16} {
    lappend SRAM_MAX $SMALL_SRAM_DERIVED/${macro}_ss_0p99v_0p99v_m40c.db
    lappend SRAM_MIN $SMALL_SRAM_DERIVED/${macro}_ff_1p21v_1p21v_125c.db
}
foreach macro {RAMSP8KX32 RAMSP4KX64 ROM1KX32 ROM2KX32} {
    lappend SRAM_LIB_PATH $LARGE_SRAM_ROOT/$macro/db
    lappend SRAM_MAX $LARGE_SRAM_ROOT/$macro/db/${macro}_ss_0p99v_0p99v_m40c.db
    lappend SRAM_MIN $LARGE_SRAM_ROOT/$macro/db/${macro}_ff_1p21v_1p21v_125c.db
}
foreach path [concat [list $STD_MAX $STD_MIN] $SRAM_MAX $SRAM_MIN] {
    if {![file isfile $path]} {error "库文件不存在：$path"}
}
set HDL_PATH [list $PIPELINE/rtl $ACCEL/rtl]
set INC_PATH [list $OFFICIAL/core $ACCEL/rtl $PIPELINE/rtl]
# 本版显式提供的同名模块替代官方副本，其余 CPU 文件保持原样。
set SOURCES [lsort [glob $PIPELINE/rtl/*.v $PIPELINE/rtl/*.sv]]
set replaced {GENERIC_RVT_SMIC.v GENERIC_RVT_ARM.v}
foreach path $SOURCES {lappend replaced [file tail $path]}
foreach directory {core general subsys perips debug mems fab} {
    lappend HDL_PATH $OFFICIAL/$directory
    lappend INC_PATH $OFFICIAL/$directory
    foreach path [lsort [glob $OFFICIAL/$directory/*.v]] {
        if {[file tail $path] ni $replaced} {lappend SOURCES $path}
    }
}
foreach name {kwt_quantize.sv kwt_mul16_pipe.sv kwt_sp_ram.sv kwt_rice_pack.sv
    kwt43_icb_master.sv kwt43_unpack.sv kwt43_dot.sv kwt43_xram.sv kwt43_wram.sv
    kwt43_yram.sv kwt43_reader.sv kwt43_writer.sv kwt43_compute.sv kwt43_core.sv kwt_nice_core.sv} {
    if {$name ni $replaced} {lappend SOURCES $ACCEL/rtl/$name}
}
set source_file [open reports/sources.txt w]
foreach path $SOURCES {puts $source_file [file normalize $path]}
close $source_file
exec $PYTHON $SCRIPT_DIR/verify_p1_for_dc.py --candidate $PIPELINE --sources $OUT/reports/sources.txt
set_app_var search_path [concat [list . $LIB_PATH] $SRAM_LIB_PATH $HDL_PATH $INC_PATH $search_path]
set_app_var target_library [list $STD_MAX]
set_app_var synthetic_library [list dw_foundation.sldb]
set_app_var link_library [concat [list * $STD_MAX] $SRAM_MAX [list $STD_MIN] $SRAM_MIN [list dw_foundation.sldb]]
set_min_library $STD_MAX -min_version $STD_MIN
foreach slow $SRAM_MAX fast $SRAM_MIN {set_min_library $slow -min_version $fast}

# SMIC40 配套物理库和 RC；厂家行为模型只供功能仿真使用。
if {![shell_is_in_topographical_mode]} {error "需要 dc_shell -topographical_mode"}
create_mw_lib -technology $TECHNOLOGY_FILE -mw_reference_library [list $MW_REFERENCE] -open $OUT/design_mw
set_tlu_plus_files -max_tluplus $RC_DIRECTORY/CMAX.tluplus \
    -min_tluplus $RC_DIRECTORY/CMIN.tluplus -tech2itf_map $TECH_MAP
if {![check_tlu_plus_files]} {error "RC 与工艺层映射不一致"}
set_preferred_routing_direction -layers {M1 M3 M5 M7 TM2} -direction vertical
set_preferred_routing_direction -layers {M2 M4 M6 TM1 ALPA} -direction horizontal
set_ignored_layers -min_routing_layer M1 -max_routing_layer TM2
define_design_lib WORK -path $OUT/work
set_svf $OUT/netlist/soc.svf
if {![analyze -format sverilog -define {SYNTHESIS KWT_USE_FOUNDRY_SRAM DISABLE_SV_ASSERTION KWT_MEM_BASE=32'hA0000000 KWT_MEM_BYTES=524288} $SOURCES]} {error "RTL 分析失败"}
elaborate $TOP
current_design $TOP
if {![link]} {error "整机链接失败"}
if {![check_design]} {error "整机结构检查失败"}

# ==================== CONSTRAINTS ====================
create_clock -name core_clk -period 6.666666667 [get_ports hfextclk]
create_clock -name aon_clk -period 30517.578125 [get_ports lfextclk]
create_clock -name jtag_clk -period 100.000 [get_ports io_pads_jtag_TCK_i_ival]
create_generated_clock -name sys_clk_out -source [get_ports hfextclk] \
    -master_clock core_clk -divide_by 1 [get_ports sys_clk]
set_clock_uncertainty -setup 0.300 [all_clocks]
set_clock_uncertainty -hold 0.100 [all_clocks]
set_clock_transition 0.100 [all_clocks]
set_clock_groups -asynchronous -group {core_clk sys_clk_out} -group aon_clk -group jtag_clk
set hclk u_e203_subsys_top/u_e203_subsys_main/u_e203_subsys_hclkgen
set_case_analysis 1 [get_pins [list $hclk/pllbypass $hclk/plloutdivby1]]
set_case_analysis 1 [get_ports {io_pads_dbgmode0_n_i_ival io_pads_dbgmode1_n_i_ival io_pads_dbgmode2_n_i_ival}]
set clock_ports [get_ports {hfextclk lfextclk io_pads_jtag_TCK_i_ival}]
set reset [get_ports io_pads_aon_erst_n_i_ival]
set jtag_inputs [get_ports {io_pads_jtag_TMS_i_ival io_pads_jtag_TDI_i_ival}]
set aon_inputs [get_ports {io_pads_aon_pmu_dwakeup_n_i_ival io_pads_dbgmode0_n_i_ival io_pads_dbgmode1_n_i_ival io_pads_dbgmode2_n_i_ival io_pads_bootrom_n_i_ival}]
set gpio_inputs [get_ports {io_pads_gpioA_i_ival* io_pads_gpioB_i_ival*}]
set excluded [add_to_collection $clock_ports [add_to_collection $reset [add_to_collection $jtag_inputs [add_to_collection $aon_inputs $gpio_inputs]]]]
set data_inputs [remove_from_collection [all_inputs] $excluded]
foreach ports [list $data_inputs $aon_inputs] clock {core_clk aon_clk} {
    set_input_delay -clock $clock -max 1.000 $ports
    set_input_delay -clock $clock -min 0.100 $ports
}
set_input_delay -clock jtag_clk -clock_fall -max 1.000 $jtag_inputs
set_input_delay -clock jtag_clk -clock_fall -min 0.100 $jtag_inputs
set jtag_outputs [get_ports {io_pads_jtag_TDO_o_oval io_pads_jtag_TDO_o_oe}]
set aon_outputs [get_ports {lfxoscen io_pads_aon_pmu_padrst_o_oval io_pads_aon_pmu_vddpaden_o_oval}]
set data_outputs [remove_from_collection [all_outputs] [add_to_collection [get_ports sys_clk] [add_to_collection $jtag_outputs $aon_outputs]]]
foreach ports [list $data_outputs $jtag_outputs $aon_outputs] clock {core_clk jtag_clk aon_clk} {
    set_output_delay -clock $clock -max 1.000 $ports
    set_output_delay -clock $clock -min -0.100 $ports
}
set_false_path -from $reset
set_false_path -to [get_ports sys_clk]
# GPIO 的异步例外仅到首级同步器，第二级和内部复位释放仍检查时序。
set gpio_first [filter_collection [all_registers -data_pins] {full_name =~ */u_perips_apb_gpio*/r_gpio_sync0_reg*/*}]
if {[sizeof_collection $gpio_first]!=64} {error "GPIO 首级同步器应为 64 位"}
set_false_path -from $gpio_inputs -to $gpio_first
foreach lib [list $MAX_LIB_NAME $MIN_LIB_NAME] sense {-max -min} {
    set_driving_cell $sense -library $lib -lib_cell INV1_12TH40 -from_pin I -pin ZN \
        -input_transition_rise 0.100 -input_transition_fall 0.100 \
        [remove_from_collection [all_inputs] $clock_ports]
}
# 七角库检查确认的四个 INV1 输入端总电容，单位 pF。
set_load 0.003396 [all_outputs]
set_max_transition 1.270 [current_design]
set_operating_conditions -analysis_type bc_wc -max_library $MAX_LIB_NAME -max $MAX_CORNER \
    -min_library $MIN_LIB_NAME -min $MIN_CORNER
set srams [get_cells -hierarchical -filter {ref_name =~ RAMSP*}]
if {[sizeof_collection $srams]!=104} {error "SRAM 宏数量应为 104"}
set_dont_touch $srams true
set sram_outputs [get_pins -of_objects $srams -filter {direction == out}]
set sram_inputs [get_pins -of_objects $srams -filter {direction == in}]
set sram_clocks [filter_collection $sram_inputs {full_name =~ */CLK}]
group_path -name SRAM_TO_LOGIC -through $sram_outputs -weight 5.0 -critical_range 0.500
group_path -name LOGIC_TO_SRAM -to [remove_from_collection $sram_inputs $sram_clocks] -weight 5.0
redirect -file reports/check_timing_before.rpt {check_timing}
if {[get_message_info -error_count]>$initial_errors} {error "展开或约束阶段出现工具错误"}
if {[info exists env(SOC_CHECK_ONLY)] && $env(SOC_CHECK_ONLY)} {
    set_svf -off
    puts "SOC_STRUCTURE_CHECK_COMPLETED nice_rtl $OUT"
    exit
}

# ==================== COMPILE ====================
compile_ultra -no_autoungroup
if {[get_message_info -error_count]>$initial_errors} {error "综合阶段出现工具错误"}

# ==================== REPORTS / OUTPUT ====================
change_names -rules verilog -hierarchy
set_svf -off
write -format verilog -hierarchy -output netlist/soc_mapped.v
write -format ddc -hierarchy -output netlist/soc_mapped.ddc
write_sdc netlist/soc_mapped.sdc
write_sdf netlist/soc_mapped.sdf
redirect -file reports/check_design.rpt {check_design}
redirect -file reports/check_timing.rpt {check_timing}
redirect -file reports/area.rpt {report_area -hierarchy}
redirect -file reports/references.rpt {report_reference -hierarchy}
redirect -file reports/setup.rpt {report_timing -delay_type max -max_paths 100 -nets -transition_time -capacitance -significant_digits 8}
redirect -file reports/hold.rpt {report_timing -delay_type min -max_paths 100 -nets -transition_time -capacitance -significant_digits 8}
redirect -file reports/violations.rpt {report_constraint -all_violators}
redirect -file reports/qor.rpt {report_qor}
redirect -file reports/clocks.rpt {report_clock -attributes}
redirect -file reports/units.rpt {report_units}
redirect -file reports/rc_models.rpt {report_tlu_plus_files}
set summary [open reports/timing_acceptance.txt w]
puts $summary "SYNTHESIS=COMPLETED\nCLOCK_MHZ=150\nSETUP_PVT=$MAX_CORNER\nHOLD_PVT=$MIN_CORNER\nRC_MAX=CMAX\nRC_MIN=CMIN"
set pass 1
foreach delay {max min} {
    set path [get_timing_paths -delay_type $delay -max_paths 1]
    if {[sizeof_collection $path]!=1} {error "缺少 $delay 时序路径"}
    set slack [get_attribute $path slack]
    puts $summary "${delay}_slack_ns=$slack"
    if {$slack<0} {set pass 0}
}
puts $summary "PRIMARY_TIMING_PASS=$pass"
close $summary
if {[get_message_info -error_count]>$initial_errors} {error "报告或输出阶段出现工具错误"}
puts "SOC_SYNTHESIS_COMPLETED nice_rtl $OUT"
exit
