# E203 + NICE，独立版本 astra_p7r1，DC Topographical综合与七角检查。
# 单文件结构沿用集创赛 LIB/HDL、CONSTRAINTS、COMPILE、REPORTS。
# 本安装在空会话中记录一次CMD-025手册查询错误；记录启动状态并检查全部新增错误。
set DC_STARTUP_ERRORS [get_message_info -error_count]
set DC_STARTUP_MANUAL_ERRORS [get_message_info -occurrences CMD-025]
if {$DC_STARTUP_ERRORS ni {0 1} || $DC_STARTUP_ERRORS != $DC_STARTUP_MANUAL_ERRORS} {
    error "DC启动诊断与已验证环境不符，错误数$DC_STARTUP_ERRORS，手册查询错误数$DC_STARTUP_MANUAL_ERRORS"
}
puts "DC_STARTUP_DIAGNOSTICS errors=$DC_STARTUP_ERRORS manual_lookup_errors=$DC_STARTUP_MANUAL_ERRORS"
print_message_info -summary
set_app_var sh_continue_on_error false
set_host_options -max_cores 1
set VERSION astra_p7r1
proc read_db_if_unloaded {path} {
    set name [file rootname [file tail $path]]
    if {[sizeof_collection [get_libs -quiet $name]] == 0} {read_db $path}
    if {[sizeof_collection [get_libs -quiet $name]] != 1} {error "时序库没有唯一加载结果：$path"}
    require_native_success "时序库加载$name"
}
proc require_native_success {stage} {
    global DC_STARTUP_ERRORS
    set count [get_message_info -error_count]
    if {![string is integer -strict $count] || $count != $DC_STARTUP_ERRORS} {
        error "${stage}出现新增原生工具错误，启动错误数$DC_STARTUP_ERRORS，累计错误数$count"
    }
}
proc is_constant_node {cell} {
    set reference [get_attribute $cell ref_name]
    if {$reference ni {**logic_0** **logic_1**}} {return 0}
    set pins [get_pins -of_objects $cell]
    if {[sizeof_collection [filter_collection $pins {direction == in}]] != 0 || \
        [sizeof_collection [filter_collection $pins {direction == out}]] != 1} {
        error "DC内建常量节点的端口结构不符：[get_object_name $cell]"
    }
    return 1
}
proc check_mapped_timing {report} {
    set before [get_message_info -warning_count]
    set before_input [get_message_info -occurrences TIM-216]
    redirect -file $report {check_timing}
    require_native_success "映射后时序覆盖检查"
    set warnings [expr {[get_message_info -warning_count] - $before}]
    set input_warnings [expr {[get_message_info -occurrences TIM-216] - $before_input}]
    if {$warnings != $input_warnings} {error "映射后存在时序覆盖警告，详见$report"}
    if {$warnings == 0} {return}
    # 异步输入没有同步到达预算；逐项核对TIM-216中列出的实际端口和首级边界。
    set inputs [get_object_name [all_inputs]]
    set gpio [get_object_name [get_ports {io_pads_gpioA_i_ival* io_pads_gpioB_i_ival*}]]
    set allowed [concat $gpio [list io_pads_aon_erst_n_i_ival]]
    set first_data [get_object_name [filter_collection [all_registers -data_pins] \
        {full_name =~ */u_perips_apb_gpio*/r_gpio_sync0_reg*/*}]]
    set f [open $report r]
    set lines [split [read $f] \n]
    close $f
    set reported {}
    foreach line $lines {
        if {[regexp {^\s*(\S+)} $line -> name] && $name in $inputs} {
            if {$name ni $allowed} {error "同步输入缺少到达预算：$name"}
            if {$name in $gpio} {
                set endpoints [all_fanout -flat -endpoints_only -from [get_ports $name]]
                if {[sizeof_collection $endpoints] != 1 || [get_object_name $endpoints] ni $first_data} {
                    error "异步GPIO的映射后边界与首级数据端不符：$name"
                }
            }
            lappend reported $name
        }
    }
    if {[llength $reported] == 0} {error "TIM-216报告没有可核对的输入端口：$report"}
    set f [open ${report}.async_inputs.txt w]
    puts $f [lsort -unique $reported]
    close $f
    require_native_success "异步输入覆盖核对"
}
proc configure_routing {} {
    # 方向取自HVT技术LEF的DIRECTION定义。
    set_preferred_routing_direction -layers {M1 M3 M5 M7 TM2} -direction vertical
    set_preferred_routing_direction -layers {M2 M4 M6 TM1 ALPA} -direction horizontal
    set_ignored_layers -min_routing_layer M1 -max_routing_layer TM2
    require_native_success "布线方向设置"
}
set SCRIPT [file normalize [info script]]
set PATH_CONFIG [file join [file dirname $SCRIPT] paths.tcl]
if {[info exists env(SOC_PATHS)]} {set PATH_CONFIG [file normalize $env(SOC_PATHS)]}
source $PATH_CONFIG
set env(SOC_PATHS) $PATH_CONFIG
set TOP kwt_e203_soc_top
set MODE synth
if {[info exists env(SOC_MODE)]} {set MODE $env(SOC_MODE)}
if {$MODE ni {synth corner}} {error "SOC_MODE必须为synth或corner"}
set CHECK_ONLY 0
if {[info exists env(SOC_CHECK_ONLY)]} {set CHECK_ONLY $env(SOC_CHECK_ONLY)}
if {$CHECK_ONLY ni {0 1}} {error "SOC_CHECK_ONLY 必须为 0 或 1"}
if {![shell_is_in_topographical_mode]} {error "请使用dc_shell -topographical_mode运行本脚本"}
set FUNCTIONAL_GATE [file join [file dirname $SCRIPT] verify_p1_for_dc.py]
set OUT $RUN_ROOT/${VERSION}_[clock format [clock seconds] -format %Y%m%d_%H%M%S]_[pid]
if {$MODE eq "corner"} {
    foreach key {SOC_PARENT_OUT SOC_CASE_OUT SOC_CORNER SOC_RC} {
        if {![info exists env($key)] || $env($key) eq ""} {error "逐角分析参数缺失：$key"}
    }
    set PARENT [file normalize $env(SOC_PARENT_OUT)]
    set OUT [file normalize $env(SOC_CASE_OUT)]
    if {[string first "$PARENT/corner_checks/" $OUT] != 0} {error "逐角输出目录必须位于本次综合结果目录内"}
}
if {[file exists $OUT]} {error "输出目录已存在"}
file mkdir $OUT $OUT/work $OUT/netlist $OUT/reports $OUT/scratch
cd $OUT
foreach key {TMPDIR TMP TEMP} {set env($key) $OUT/scratch}

# ==================== LIB / SRAM / HDL / INC ====================
set SRAM_LIB_PATH [list $SMALL_SRAM_ORIGINAL $SMALL_SRAM_DERIVED \
    $LARGE_SRAM_ROOT/RAMSP8KX32/db $LARGE_SRAM_ROOT/RAMSP4KX64/db \
    $LARGE_SRAM_ROOT/ROM1KX32/db $LARGE_SRAM_ROOT/ROM2KX32/db]
set HDL_PATH [list $OFFICIAL/core $OFFICIAL/general $OFFICIAL/subsys \
    $OFFICIAL/perips $OFFICIAL/debug $OFFICIAL/mems $OFFICIAL/fab \
    $ACCEL/rtl $PIPELINE/rtl]
set INC_PATH [list $OFFICIAL/core $ACCEL/rtl $PIPELINE/rtl]
# 标称 1.10 V 系列，0.99 V和1.21 V分别为-10%与+10%。
# 七角固定网表比较的建立时间最差角为SS 0.99 V/-40℃。
# FF 1.21 V/125℃在冻结网表的三个FF角中保持裕量最小；最终保持检查覆盖七角。
set CORNER_SPECS {
    {ss_v0p99_-40c ss_0p99v_0p99v_m40c derived}
    {ss_v0p99_125c ss_0p99v_0p99v_125c original}
    {tt_v1p1_25c tt_1p10v_1p10v_25c original}
    {tt_v1p1_125c tt_1p10v_1p10v_125c derived}
    {ff_v1p21_-40c ff_1p21v_1p21v_m40c original}
    {ff_v1p21_0c ff_1p21v_1p21v_0c derived}
    {ff_v1p21_125c ff_1p21v_1p21v_125c derived}
}
set CORNERS [dict create]
set STD_CORNERS {}
set ALL_SRAM_LIBRARIES {}
foreach specification $CORNER_SPECS {
    lassign $specification corner macro_corner origin
    set standard $LIB_PATH/scc40nll_vhsc40_hvt_${corner}_basic.db
    set small_directory $SMALL_SRAM_ORIGINAL
    if {$origin eq "derived"} {set small_directory $SMALL_SRAM_DERIVED}
    set macros {}
    foreach macro {RAMSP128X16 RAMSP1024X16} {
        lappend macros $small_directory/${macro}_${macro_corner}.db
    }
    foreach macro {RAMSP8KX32 RAMSP4KX64 ROM1KX32 ROM2KX32} {
        lappend macros $LARGE_SRAM_ROOT/$macro/db/${macro}_${macro_corner}.db
    }
    dict set CORNERS $corner [dict create standard $standard macros $macros]
    lappend STD_CORNERS $standard
    set ALL_SRAM_LIBRARIES [concat $ALL_SRAM_LIBRARIES $macros]
}
set MAX_CORNER ss_v0p99_-40c
set MIN_CORNER ff_v1p21_125c
set STD_MAX [dict get $CORNERS $MAX_CORNER standard]
set STD_MIN [dict get $CORNERS $MIN_CORNER standard]
set MAX_LIB_NAME [file rootname [file tail $STD_MAX]]
set MIN_LIB_NAME [file rootname [file tail $STD_MIN]]
set SRAM_MAX [dict get $CORNERS $MAX_CORNER macros]
set SRAM_MIN [dict get $CORNERS $MIN_CORNER macros]
set LIBRARIES [concat $STD_CORNERS $ALL_SRAM_LIBRARIES]
set MAPPING_LIBRARIES [concat [list $STD_MAX $STD_MIN] $SRAM_MAX $SRAM_MIN]
foreach path $LIBRARIES {if {![file isfile $path]} {error "缺少库：$path"}}
if {$MODE eq "corner"} {
    set SELECTED_CORNER $env(SOC_CORNER)
    if {![dict exists $CORNERS $SELECTED_CORNER]} {error "未知PVT组合：$SELECTED_CORNER"}
    set STD_SELECTED [dict get $CORNERS $SELECTED_CORNER standard]
    set SELECTED_LIBRARIES [concat [list $STD_SELECTED] [dict get $CORNERS $SELECTED_CORNER macros]]
    set MAPPING_LIBRARIES $SELECTED_LIBRARIES
}
set_app_var target_library [list $STD_MAX]
if {$MODE eq "corner"} {set_app_var target_library [list $STD_SELECTED]}
set_app_var synthetic_library [list dw_foundation.sldb]
set_app_var link_library [concat $MAPPING_LIBRARIES [list * dw_foundation.sldb]]
foreach path $STD_CORNERS {read_db_if_unloaded $path}
if {$MODE eq "synth"} {
    set_min_library $STD_MAX -min_version $STD_MIN
    foreach slow $SRAM_MAX fast $SRAM_MIN {set_min_library $slow -min_version $fast}
}

# 物理参考库由同一HVT技术LEF、标准单元和四类SRAM的真实LEF生成。
set RC_VARIANT 1P9M_2TM
set RC_CORNERS {RCMAX RCMIN CMAX CMIN TYP}
set PHYSICAL_FILES [list $TECHNOLOGY_FILE $TECH_MAP \
    $PHYSICAL_INPUT/hvt/technology.lef $PHYSICAL_INPUT/hvt/standard_cells.lef \
    $TECHNOLOGY_HASHES $PHYSICAL_HASHES $BIAS_HASHES $REFERENCE_HASHES]
foreach macro {RAMSP128X16 RAMSP1024X16 RAMSP8KX32 RAMSP4KX64} {
    lappend PHYSICAL_FILES $MACRO_LEF_ROOT/$macro.lef
}
foreach corner $RC_CORNERS {lappend PHYSICAL_FILES $RC_DIRECTORY/$corner.tluplus}
foreach path $PHYSICAL_FILES {
    if {![file isfile $path] || [file size $path] == 0} {error "缺少物理模型：$path"}
}
if {![file isdirectory $MW_REFERENCE]} {error "Milkyway参考库缺失：$MW_REFERENCE"}
create_mw_lib -technology $TECHNOLOGY_FILE -mw_reference_library [list $MW_REFERENCE] -open $OUT/design_mw
require_native_success "物理工作库创建"
# 参考库包含标准单元及四类实际使用的SRAM；同一PVT的五个逻辑库一起核对。
set physical_check_corners [dict keys $CORNERS]
if {$MODE eq "corner"} {set physical_check_corners [list $SELECTED_CORNER]}
foreach corner $physical_check_corners {
    set logic_libraries [concat [list [dict get $CORNERS $corner standard]] \
        [lrange [dict get $CORNERS $corner macros] 0 3]]
    redirect -file reports/${corner}_physical.rpt {
        set good [check_library -logic_library_name $logic_libraries]
    }
    require_native_success "逻辑与物理库检查$corner"
    if {![string is boolean -strict $good] || !$good} {error "逻辑与物理库不一致：$corner"}
}
# 冻结SRAM银行的五RC实测：CMAX建立裕量最小，CMIN保持裕量最小。
# 用于首轮映射；最终整机继续比较全部35个PVT与RC组合。
set RC_MAX CMAX
set RC_MIN CMIN
if {$MODE eq "corner"} {
    if {$env(SOC_RC) ni $RC_CORNERS} {error "未知RC角：$env(SOC_RC)"}
    set RC_MAX $env(SOC_RC)
    set RC_MIN $env(SOC_RC)
}
set_tlu_plus_files -max_tluplus $RC_DIRECTORY/$RC_MAX.tluplus \
    -min_tluplus $RC_DIRECTORY/$RC_MIN.tluplus -tech2itf_map $TECH_MAP
redirect -file reports/tluplus_check.rpt {set good [check_tlu_plus_files]}
if {!$good} {error "TLUPlus与物理库的技术层检查失败"}
redirect -file reports/tluplus_models.rpt {report_tlu_plus_files}
require_native_success "物理模型加载"

proc bind_single_corner {corner report} {
    global CORNERS
    set standard [dict get $CORNERS $corner standard]
    set macros [dict get $CORNERS $corner macros]
    set selected_libraries [concat [list $standard] $macros]
    set std_name [file rootname [file tail $standard]]
    set macro_libraries [dict create]
    foreach name {RAMSP128X16 RAMSP1024X16 RAMSP8KX32 RAMSP4KX64 ROM1KX32 ROM2KX32} path $macros {
        dict set macro_libraries $name [file rootname [file tail $path]]
    }
    foreach path $selected_libraries {read_db_if_unloaded $path}
    set_app_var target_library [list $standard]
    set_app_var link_library [concat $selected_libraries [list *]]
    # DDC中的局部链接库优先于全局搜索列表，必须一起切换。
    set_local_link_library $selected_libraries
    set references {}
    foreach_in_collection cell [get_cells -hierarchical -filter {is_hierarchical == false}] {
        if {[is_constant_node $cell]} {continue}
        lappend references [get_attribute $cell ref_name]
    }
    foreach reference [lsort -unique $references] {
        set library $std_name
        if {[dict exists $macro_libraries $reference]} {set library [dict get $macro_libraries $reference]}
        set target $library/$reference
        if {[sizeof_collection [get_lib_cells $target]] != 1} {error "目标PVT缺少单元：$target"}
        set cells [get_cells -hierarchical -filter "is_hierarchical == false && ref_name == $reference"]
        if {![change_link $cells $target -all_instances]} {error "时序模型更新失败：$target"}
    }
    if {![link]} {error "切换PVT后的链接失败：$corner"}
    set allowed {}
    foreach path $selected_libraries {lappend allowed [file rootname [file tail $path]]}
    set bound {}
    set constants {}
    foreach_in_collection cell [get_cells -hierarchical -filter {is_hierarchical == false}] {
        if {[is_constant_node $cell]} {
            lappend constants [list [get_object_name $cell] [get_attribute $cell ref_name]]
            continue
        }
        set model [get_lib_cells -of_objects $cell]
        if {[sizeof_collection $model] != 1} {error "提取互连前实例缺少唯一时序模型"}
        set name [lindex [split [get_object_name $model] /] 0]
        if {$name ni $allowed} {error "提取互连前实例绑定到所选PVT之外：[get_object_name $cell] -> $name"}
        lappend bound $name
    }
    set f [open $report w]
    puts $f [lsort -unique $bound]
    foreach constant $constants {puts $f [linsert $constant 0 constant_node]}
    close $f
    set_operating_conditions -analysis_type single -library $std_name $corner
    set clock_ports [get_ports {hfextclk lfextclk io_pads_jtag_TCK_i_ival}]
    set_driving_cell -library $std_name -lib_cell INV1_12TH40 -from_pin I -pin ZN \
        -input_transition_rise 0.100 -input_transition_fall 0.100 \
        [remove_from_collection [all_inputs] $clock_ports]
    require_native_success "提取互连前切换PVT与驱动模型"
}

proc timing_extrema {label directory {checks {max min}}} {
    file mkdir $directory
    set table [open $directory/path_groups.tsv w]
    puts $table "case\tcheck\tgroup\tslack_ns\tstartpoint\tendpoint"
    set result [dict create case $label]
    foreach delay $checks {
        set selected {}
        set worst 0
        foreach_in_collection group [get_path_groups *] {
            set name [get_object_name $group]
            redirect -file $directory/${delay}_${name}.rpt {
                report_timing -group $name -delay_type $delay -max_paths 10 \
                    -nets -transition_time -capacitance -significant_digits 8
            }
            foreach_in_collection path [get_timing_paths -group $name -delay_type $delay -max_paths 1] {
                set slack [get_attribute $path slack]
                set row [dict create slack_ns $slack group $name \
                    startpoint [get_object_name [get_attribute $path startpoint]] \
                    endpoint [get_object_name [get_attribute $path endpoint]]]
                puts $table [join [list $label $delay $name $slack [dict get $row startpoint] [dict get $row endpoint]] "\t"]
                if {$selected eq {} || $slack < $worst} {set worst $slack; set selected $row}
            }
        }
        if {$selected eq {}} {error "没有可分析的路径：$label/$delay"}
        dict set result $delay $selected
    }
    close $table
    set f [open $directory/extrema.tcldata w]
    puts $f $result
    close $f
    return $result
}

if {$MODE eq "corner"} {
    set CASE_DATABASE $PARENT/corner_databases/$SELECTED_CORNER/$env(SOC_RC).ddc
    set CASE_INPUTS [concat $SELECTED_LIBRARIES $PHYSICAL_FILES \
        [list $CASE_DATABASE $SCRIPT]]
    set case_hashes [dict create]
    set f [open reports/input_sha256.txt w]
    foreach path $CASE_INPUTS {
        if {![file isfile $path] || [file size $path] == 0} {error "逐角输入缺失：$path"}
        set digest [exec sha256sum -- $path]
        dict set case_hashes $path $digest
        puts $f $digest
    }
    close $f
    foreach path $SELECTED_LIBRARIES {read_db_if_unloaded $path}
    # DDC保存该角的实际库绑定、虚拟布局、约束及原生线延迟。
    read_ddc $CASE_DATABASE
    current_design $TOP
    set_local_link_library $SELECTED_LIBRARIES
    if {![link]} {error "逐角数据库链接失败：$SELECTED_CORNER"}
    set selected_name [file rootname [file tail $STD_SELECTED]]
    set_operating_conditions -analysis_type single -library $selected_name $SELECTED_CORNER
    configure_routing
    set case_clocks [get_ports {hfextclk lfextclk io_pads_jtag_TCK_i_ival}]
    set_driving_cell -library $selected_name -lib_cell INV1_12TH40 -from_pin I -pin ZN \
        -input_transition_rise 0.100 -input_transition_fall 0.100 \
        [remove_from_collection [all_inputs] $case_clocks]
    set allowed {}
    foreach path $SELECTED_LIBRARIES {lappend allowed [file rootname [file tail $path]]}
    set binding [open reports/bound_libraries.txt w]
    set bound {}
    foreach_in_collection cell [get_cells -hierarchical -filter {is_hierarchical == false}] {
        if {[is_constant_node $cell]} {
            puts $binding [list constant_node [get_object_name $cell] [get_attribute $cell ref_name]]
            continue
        }
        set model [get_lib_cells -of_objects $cell]
        if {[sizeof_collection $model] != 1} {error "叶级实例没有唯一模型：[get_object_name $cell]"}
        set name [lindex [split [get_object_name $model] /] 0]
        if {$name ni $allowed} {error "实例绑定到所选PVT之外的库：[get_object_name $cell] -> $name"}
        lappend bound $name
    }
    foreach name [lsort -unique $bound] {puts $binding $name}
    close $binding
    redirect -file reports/check_design.rpt {set good [check_design]}
    if {!$good} {error "逐角连接检查失败"}
    redirect -file reports/conditions.rpt {report_design}
    check_mapped_timing reports/check_timing.rpt
    foreach delay {max min} {
        redirect -file reports/${delay}_timing.rpt {
            report_timing -delay_type $delay -max_paths 100 -nets -transition_time -capacitance -significant_digits 8
        }
    }
    redirect -file reports/model_violations.rpt {report_constraint -all_violators -significant_digits 8}
    timing_extrema $SELECTED_CORNER/$env(SOC_RC) $OUT/reports
    write_sdf $OUT/netlist/soc_corner.sdf
    require_native_success "逐角时序报告"
    dict for {path digest} $case_hashes {
        if {[exec sha256sum -- $path] ne $digest} {error "逐角分析期间输入变化：$path"}
    }
    puts "SOC_CORNER_ANALYSIS_COMPLETED $SELECTED_CORNER/$env(SOC_RC) $OUT"
    exit
}

# HDL：官方目录提供CPU、总线和外设；集成模块和ITCM控制器使用下方指定的文件。
proc collect_files {directory extensions} {
    if {![file isdirectory $directory]} {error "目录不存在：$directory"}
    set files {}
    foreach path [lsort [glob -nocomplain -directory $directory *]] {
        if {[file isdirectory $path]} {
            set files [concat $files [collect_files $path $extensions]]
        } elseif {[file extension $path] in $extensions} {lappend files $path}
    }
    return $files
}
set SOURCES {}
set HEADERS {}
foreach directory {core general subsys perips debug mems fab} {
    foreach path [collect_files $OFFICIAL/$directory {.v}] {
        if {[file tail $path] in {e203_subsys_top.v e203_subsys_nice_core.v e203_ifu.v e203_ifu_ift2icb.v e203_lsu_ctrl.v e203_itcm_ctrl.v \
            sram_wrap_64KX32.v sram_wrap_32KX64.v GENERIC_RVT_SMIC.v sirv_mrom_top.v}} {continue}
        lappend SOURCES $path
        lappend INC_PATH [file dirname $path]
    }
    set HEADERS [concat $HEADERS [collect_files $OFFICIAL/$directory {.vh .svh}]]
}
foreach leaf {kwt_quantize.sv kwt_mul16_pipe.sv kwt_sp_ram.sv kwt_rice_pack.sv kwt43_icb_master.sv kwt43_unpack.sv kwt43_dot.sv kwt43_xram.sv kwt43_wram.sv kwt43_yram.sv kwt43_reader.sv kwt43_writer.sv kwt43_compute.sv kwt43_core.sv kwt_nice_core.sv} {
    set path $ACCEL/rtl/$leaf
    if {$leaf in {kwt43_reader.sv kwt43_writer.sv kwt43_icb_master.sv kwt43_xram.sv kwt43_wram.sv}} {set path $PIPELINE/rtl/$leaf}
    lappend SOURCES $path
}
# NICE 集成模块与加速器保持同一已验证版本；修正的顶层和 ITCM 来自功能验证目录。
lappend SOURCES $PIPELINE/rtl/e203_subsys_nice_core.v
foreach leaf {kwt_generic_hvt.v kwt_banked_sram.sv sram_wrap_64KX32.v sram_wrap_32KX64.v kwt_shared_sram.sv e203_subsys_top.v} {lappend SOURCES $PIPELINE/rtl/$leaf}
foreach leaf {e203_ifu.v e203_ifu_ift2icb.v e203_lsu_ctrl.v e203_itcm_ctrl.v kwt_itcm_sram_icb_ctrl.sv kwt_e203_soc_top.v sirv_mrom_top.v} {lappend SOURCES $PIPELINE/rtl/$leaf}
set source_list [open reports/simulation_checked_sources.txt w]
foreach path $SOURCES {puts $source_list $path}
close $source_list
puts [exec env -u LD_LIBRARY_PATH -u PYTHONHOME -u PYTHONPATH $PYTHON \
    $FUNCTIONAL_GATE --candidate $PIPELINE --sources $OUT/reports/simulation_checked_sources.txt]
foreach directory [list $PIPELINE/rtl $ACCEL/rtl] {
    set HEADERS [concat $HEADERS [collect_files $directory {.vh .svh}]]
}
set INPUTS [lsort -unique [concat $SOURCES $HEADERS $LIBRARIES $PHYSICAL_FILES \
    [list $SCRIPT $PATH_CONFIG $FUNCTIONAL_GATE $PIPELINE/verification_pass.json $PIPELINE/verified_inputs.json]]]
set manifest [open reports/input_sha256.txt w]
set HASHES [dict create]
foreach path $INPUTS {
    if {![file isfile $path]} {error "输入不存在：$path"}
    set digest [exec sha256sum -- $path]
    dict set HASHES $path $digest
    puts $manifest $digest
}
close $manifest
set DEFINES {SYNTHESIS KWT_USE_FOUNDRY_SRAM DISABLE_SV_ASSERTION KWT_MEM_BASE=32'hA0000000 KWT_MEM_BYTES=524288}
set f [open reports/run_parameters.txt w]
puts $f [list version $VERSION top $TOP defines $DEFINES sources $SOURCES \
    interconnect TLUPLUS_VIRTUAL_ROUTE technology $TECHNOLOGY_FILE reference $MW_REFERENCE \
    rc_variant $RC_VARIANT primary_max_rc $RC_MAX primary_min_rc $RC_MIN map $TECH_MAP]
close $f
set INC_PATH [lsort -unique $INC_PATH]
set_app_var search_path [concat [list . $LIB_PATH] $SRAM_LIB_PATH $HDL_PATH $INC_PATH $search_path]
define_design_lib WORK -path $OUT/work
set_svf $OUT/netlist/soc.svf
# RAMSP及ROM宏的实例接口、电气属性和时序弧由LIBRARIES中的.db提供。
if {![analyze -format sverilog -define $DEFINES $SOURCES]} {error "RTL 分析失败"}
elaborate $TOP
current_design $TOP
set_local_link_library [concat [list $STD_MAX] $SRAM_MAX]
if {![link]} {error "链接失败"}
uniquify
configure_routing
set_fix_multiple_port_nets -all -buffer_constants [get_designs *]
redirect -file reports/check_design_before.rpt {set good [check_design]}
if {!$good} {error "综合前连接检查失败"}

# ==================== CONSTRAINTS ====================
# 时间 ns、电容 pF；来自已查询的 HVT 库单位。
# 主时钟150MHz及AON 32.768kHz取自赛题；JTAG 10MHz为项目评估频率。
foreach port {hfextclk lfextclk io_pads_jtag_TCK_i_ival} name {core_clk aon_clk jtag_clk} period {6.666666667 30517.578125 100.000} {
    create_clock -name $name -period $period [get_ports $port]
}
# PLL旁路模式下，sys_clk导出hfextclk经过时钟选择电路后的同频时钟。
create_generated_clock -name sys_clk_out -source [get_ports hfextclk] -master_clock core_clk -divide_by 1 [get_ports sys_clk]
# sys_clk按生成时钟检查，数据路径例外仅到该时钟输出端口。
set_false_path -to [get_ports sys_clk]
# 接口预算数值沿用e2评估配置；JTAG参考边沿按DTM与调试器的采样方式设置。
set SETUP_UNCERTAINTY_NS 0.300
set HOLD_UNCERTAINTY_NS 0.100
set INPUT_MAX_DELAY_NS 1.000
set INPUT_MIN_DELAY_NS 0.100
set OUTPUT_MAX_DELAY_NS 1.000
set OUTPUT_MIN_DELAY_NS -0.100
set SOURCE_TRANSITION_NS 0.100
set_clock_uncertainty -setup $SETUP_UNCERTAINTY_NS [all_clocks]
set_clock_uncertainty -hold $HOLD_UNCERTAINTY_NS [all_clocks]
set_clock_transition 0.100 [all_clocks]
set_clock_groups -asynchronous -group [get_clocks {core_clk sys_clk_out}] -group aon_clk -group jtag_clk
set hclk u_e203_subsys_top/u_e203_subsys_main/u_e203_subsys_hclkgen
foreach pin {pllbypass plloutdivby1} {
    set object [get_pins $hclk/$pin]
    if {[sizeof_collection $object] != 1} {error "时钟模式引脚缺失：$pin"}
    set_case_analysis 1 $object
}
set normal [get_ports {io_pads_dbgmode0_n_i_ival io_pads_dbgmode1_n_i_ival io_pads_dbgmode2_n_i_ival}]
if {[sizeof_collection $normal] != 3} {error "正常模式引脚不完整"}
set_case_analysis 1 $normal
set clock_ports [get_ports {hfextclk lfextclk io_pads_jtag_TCK_i_ival}]
set reset [get_ports io_pads_aon_erst_n_i_ival]
set jtag_inputs [get_ports {io_pads_jtag_TMS_i_ival io_pads_jtag_TDI_i_ival}]
set aon_inputs [get_ports {io_pads_aon_pmu_dwakeup_n_i_ival io_pads_dbgmode0_n_i_ival io_pads_dbgmode1_n_i_ival io_pads_dbgmode2_n_i_ival io_pads_bootrom_n_i_ival}]
set excluded [add_to_collection $clock_ports [add_to_collection $reset [add_to_collection $jtag_inputs $aon_inputs]]]
set gpio_inputs [get_ports {io_pads_gpioA_i_ival* io_pads_gpioB_i_ival*}]
if {[sizeof_collection $gpio_inputs] != 64} {error "GPIO输入数量与已核对RTL不符"}
set excluded [add_to_collection $excluded $gpio_inputs]
set data_inputs [remove_from_collection [all_inputs] $excluded]
set jtag_outputs [get_ports {io_pads_jtag_TDO_o_oval io_pads_jtag_TDO_o_oe}]
set aon_outputs [get_ports {lfxoscen io_pads_aon_pmu_padrst_o_oval io_pads_aon_pmu_vddpaden_o_oval}]
set data_outputs [remove_from_collection [all_outputs] [add_to_collection [get_ports sys_clk] [add_to_collection $jtag_outputs $aon_outputs]]]
# 输入延迟描述外部数据到达时间；输出延迟描述外部接收器的建立与保持预算。
foreach collection [list $data_inputs $aon_inputs] name {core_clk aon_clk} {
    if {[sizeof_collection $collection] > 0} {
        set_input_delay -clock $name -max $INPUT_MAX_DELAY_NS $collection
        set_input_delay -clock $name -min $INPUT_MIN_DELAY_NS $collection
    }
}
# 调试接口按TCK下降沿发送TMS/TDI、DTM在下一上升沿采样的条件评估。
set_input_delay -clock jtag_clk -clock_fall -max $INPUT_MAX_DELAY_NS $jtag_inputs
set_input_delay -clock jtag_clk -clock_fall -min $INPUT_MIN_DELAY_NS $jtag_inputs
foreach collection [list $data_outputs $jtag_outputs $aon_outputs] name {core_clk jtag_clk aon_clk} {
    set_output_delay -clock $name -max $OUTPUT_MAX_DELAY_NS $collection
    set_output_delay -clock $name -min $OUTPUT_MIN_DELAY_NS $collection
}
# 输入驱动：使用库内INV1_12TH40的I→ZN时序弧作为统一接口评估条件。
# 0.100ns描述上游驱动单元的输入边沿，端口边沿由该单元与设计负载计算。
set DRIVER_CELL INV1_12TH40
set driven_ports [remove_from_collection [all_inputs] $clock_ports]
foreach lib_name [list $MAX_LIB_NAME $MIN_LIB_NAME] sense {-max -min} {
    set driver [get_lib_cells $lib_name/$DRIVER_CELL]
    if {[sizeof_collection $driver] != 1} {error "驱动单元缺失：$lib_name/$DRIVER_CELL"}
    set driver_inputs [filter_collection [get_lib_pins -of_objects $driver] {direction == in}]
    set driver_outputs [filter_collection [get_lib_pins -of_objects $driver] {direction == out}]
    if {[sizeof_collection $driver_inputs] != 1 || [sizeof_collection $driver_outputs] != 1} {error "驱动单元接口不符合单输入逆变器定义"}
    set input_pin [file tail [get_object_name $driver_inputs]]
    set output_pin [file tail [get_object_name $driver_outputs]]
    set_driving_cell $sense -library $lib_name -lib_cell $DRIVER_CELL -from_pin $input_pin -pin $output_pin \
        -input_transition_rise $SOURCE_TRANSITION_NS -input_transition_fall $SOURCE_TRANSITION_NS $driven_ports
}
# 七角审计中，INV1输入电容最大值位于FF 1.21 V/125℃。
set receiver_caps {}
foreach path $STD_CORNERS {
    set lib_name [file rootname [file tail $path]]
    set driver_input [get_lib_pins $lib_name/$DRIVER_CELL/I]
    if {[sizeof_collection $driver_input] != 1} {error "接收负载输入缺失：$lib_name/$DRIVER_CELL/I"}
    set pin_cap [get_attribute $driver_input capacitance]
    if {![string is double -strict $pin_cap] || $pin_cap <= 0} {error "输入引脚电容无效：$lib_name/$DRIVER_CELL/I"}
    lappend receiver_caps $pin_cap
}
# 输出负载为四个INV1输入，采用七角最大输入电容，单位pF。
set OUTPUT_FANOUT 4
set OUTPUT_LOAD_PF [expr {$OUTPUT_FANOUT * [lindex [lsort -real $receiver_caps] end]}]
set_load -pin_load $OUTPUT_LOAD_PF [all_outputs]
set electrical [open reports/io_electrical.txt w]
puts $electrical "driver=$DRIVER_CELL source_slew_ns=$SOURCE_TRANSITION_NS receiver_count=$OUTPUT_FANOUT receiver_caps_pf=$receiver_caps output_pin_load_pf=$OUTPUT_LOAD_PF"
puts $electrical "reference=EXISTING_E2_EVALUATION input_max_ns=$INPUT_MAX_DELAY_NS input_min_ns=$INPUT_MIN_DELAY_NS output_max_ns=$OUTPUT_MAX_DELAY_NS output_min_ns=$OUTPUT_MIN_DELAY_NS setup_uncertainty_ns=$SETUP_UNCERTAINTY_NS hold_uncertainty_ns=$HOLD_UNCERTAINTY_NS"
close $electrical
set_false_path -from $reset
# 外部异步复位无同步到达预算；内部复位释放路径保留分析。
# GPIO输入经两级同步；每个外部输入的例外只到已核对的首级D端。
# 按寄存器数据端口的语义查询，同时适用于展开模型与工艺映射单元。
set register_data [all_registers -data_pins]
set gpio_first_data [filter_collection $register_data {full_name =~ */u_perips_apb_gpio*/r_gpio_sync0_reg*/*}]
set gpio_second_data [filter_collection $register_data {full_name =~ */u_perips_apb_gpio*/r_gpio_sync1_reg*/*}]
set gpio_structure [open reports/gpio_register_data.txt w]
puts $gpio_structure "first_stage_bits=[sizeof_collection $gpio_first_data] second_stage_bits=[sizeof_collection $gpio_second_data]"
foreach_in_collection pin $gpio_first_data {puts $gpio_structure [list first [get_object_name $pin]]}
foreach_in_collection pin $gpio_second_data {puts $gpio_structure [list second [get_object_name $pin]]}
close $gpio_structure
if {[sizeof_collection $gpio_first_data] != 64 || [sizeof_collection $gpio_second_data] != 64} {
    error "GPIO两级同步器数据位与已核对设计不符，详见reports/gpio_register_data.txt"
}
set expected_gpio_data [lsort [get_object_name $gpio_first_data]]
set gpio_boundaries [dict create]
set actual_gpio_data {}
foreach_in_collection port $gpio_inputs {
    set endpoints [all_fanout -flat -endpoints_only -from $port]
    if {[sizeof_collection $endpoints] != 1} {error "GPIO输入存在额外时序端点：[get_object_name $port]"}
    set pin [get_object_name $endpoints]
    if {$pin ni $expected_gpio_data} {error "GPIO输入的端点不是首级D：$pin"}
    dict set gpio_boundaries [get_object_name $port] $pin
    lappend actual_gpio_data $pin
}
if {[lsort -unique $actual_gpio_data] ne $expected_gpio_data} {error "GPIO输入与首级D未形成完整对应"}
set gpio_report [open reports/gpio_async_boundaries.tsv w]
puts $gpio_report "input\tfirst_stage_D"
dict for {port pin} $gpio_boundaries {
    set_false_path -from [get_ports $port] -to [get_pins $pin]
    puts $gpio_report "$port\t$pin"
}
close $gpio_report
require_native_success "GPIO异步边界检查与约束"
puts "GPIO_ASYNC_BOUNDARIES inputs=64 first_stage_data=64 second_stage_data=64 exceptions=64"
proc check_macros {} {
    foreach ref {RAMSP128X16 RAMSP1024X16 RAMSP8KX32 RAMSP4KX64} expected {64 8 24 8} {
        set actual [sizeof_collection [get_cells -hierarchical -filter "ref_name == $ref"]]
        if {$actual != $expected} {error "$ref 数量：$actual，要求：$expected"}
    }
    if {[sizeof_collection [get_cells -hierarchical -filter {ref_name =~ RAMSP*}]] != 104} {error "SRAM 总数量错误"}
}
check_macros
set srams [get_cells -hierarchical -filter {ref_name =~ RAMSP*}]
set_dont_touch $srams true
set sram_outputs [get_pins -of_objects $srams -filter {direction == out}]
set sram_all_inputs [get_pins -of_objects $srams -filter {direction == in}]
set sram_clock_pins {}
foreach_in_collection pin $sram_all_inputs {
    if {[file tail [get_object_name $pin]] eq "CLK"} {
        set sram_clock_pins [add_to_collection $sram_clock_pins $pin]
    }
}
if {[sizeof_collection $sram_clock_pins] != 104} {error "SRAM时钟引脚数量错误"}
set sram_inputs [remove_from_collection $sram_all_inputs $sram_clock_pins]
if {[sizeof_collection $sram_inputs] == 0 || [sizeof_collection $sram_outputs] == 0} {error "SRAM接口引脚未解析"}
set macro_report [open reports/sram_pins.txt w]
puts $macro_report "macros=[sizeof_collection $srams] clocks=[sizeof_collection $sram_clock_pins] data_control_inputs=[sizeof_collection $sram_inputs] outputs=[sizeof_collection $sram_outputs]"
close $macro_report
group_path -name SRAM_TO_LOGIC -through $sram_outputs -weight 5 -critical_range 0.500
group_path -name LOGIC_TO_SRAM -to $sram_inputs -weight 5
# 0.500ns优化范围沿用集创赛设置；SRAM建立/保持、输出延迟及引脚电容由链接库提供。
set_operating_conditions -analysis_type bc_wc -max_library $MAX_LIB_NAME -max $MAX_CORNER -min_library $MIN_LIB_NAME -min $MIN_CORNER
# DRC：采用七角default_max_transition中的最小值1.27ns。
set transitions {}
foreach path $STD_CORNERS {
    set value [get_attribute [get_libs [file rootname [file tail $path]]] default_max_transition]
    if {![string is double -strict $value] || $value <= 0} {error "库默认最大转换时间无效：$path"}
    lappend transitions $value
}
set MAX_TRANSITION [lindex [lsort -real $transitions] 0]
set_max_transition $MAX_TRANSITION [current_design]
# 两角默认最大电容与最大扇出为空；保留输出引脚级库约束。
redirect -file reports/units.rpt {report_units}
redirect -file reports/libraries.rpt {list_libs}
redirect -file reports/design_conditions.rpt {report_design}
redirect -file reports/check_timing_before.rpt {check_timing}
require_native_success "RTL展开、物理库与时序约束检查"
write -format ddc -hierarchy -output netlist/soc_elaborated.ddc
write_sdc netlist/soc_elaborated.sdc
if {$CHECK_ONLY} {
    dict for {path digest} $HASHES {
        if {[exec sha256sum -- $path] ne $digest} {error "核查期间输入已变化：$path"}
    }
    set_svf -off
    puts "SOC_STRUCTURE_CHECK_COMPLETED $VERSION $OUT"
    exit
}

# ==================== COMPILE ====================
# 按RTL流水级评估并保留模块层次；SVF记录综合变换以供Formality。
set_fix_hold [all_clocks]
compile_ultra -no_autoungroup
require_native_success "Topographical综合"
write -format ddc -hierarchy -output netlist/soc_initial_mapping.ddc
redirect -file reports/initial_mapping_qor.rpt {report_qor}
redirect -file reports/initial_mapping_violations.rpt {report_constraint -all_violators}
# 增量阶段修复电气规则，随后提高短路径保持修复优先级。
compile_ultra -incremental -only_design_rule -no_autoungroup
require_native_success "增量电气规则修复"
set_cost_priority -min_delay
compile_ultra -incremental -no_autoungroup
require_native_success "增量保持修复"
set_cost_priority -default
change_names -rules verilog -hierarchy
set_svf -off
check_macros
set mapped_sram_outputs [get_pins -of_objects [get_cells -hierarchical -filter {ref_name =~ RAMSP*}] -filter {direction == out}]
if {[sizeof_collection [get_timing_paths -through $mapped_sram_outputs -delay_type max -max_paths 1]] == 0} {
    error "SRAM输出端没有可分析的建立路径"
}
if {[sizeof_collection [get_timing_paths -group SRAM_TO_LOGIC -delay_type max -max_paths 1]] == 0} {
    error "SRAM输出路径分组为空"
}
redirect -file reports/check_design.rpt {set good [check_design]}
if {!$good} {error "映射后连接检查失败"}
dict for {path digest} $HASHES {
    if {[exec sha256sum -- $path] ne $digest} {error "运行期间输入已变化：$path"}
}
extract_rc -estimate
set_app_var write_sdc_output_lumped_net_capacitance false
set_app_var write_sdc_output_net_resistance false
write -format verilog -hierarchy -output netlist/soc_mapped.v
write -format ddc -hierarchy -output netlist/soc_mapped.ddc
write_sdc netlist/soc_mapped.sdc
write_sdf netlist/soc_mapped.sdf
write_parasitics -output netlist/soc_primary_max.spef
write_parasitics -min -output netlist/soc_primary_min.spef
require_native_success "综合网表与寄生参数导出"

# ==================== POST-COMPILE CHECKS & REPORTS ====================
check_mapped_timing reports/check_timing.rpt
redirect -file reports/area.rpt {report_area -hierarchy}
redirect -file reports/references.rpt {report_reference -hierarchy}
redirect -file reports/qor.rpt {report_qor}
redirect -file reports/setup.rpt {report_timing -delay_type max -max_paths 100 -nets -transition_time -capacitance -significant_digits 6}
redirect -file reports/hold.rpt {report_timing -delay_type min -max_paths 100 -nets -transition_time -capacitance -significant_digits 6}
redirect -file reports/violations.rpt {report_constraint -all_violators}
redirect -file reports/clocks.rpt {report_clock -attributes}
timing_extrema primary_mapping $OUT/reports/primary

# 同一最终网表、同一布局，逐个PVT温度和RC模型重新提取互连并分析。
# 每角保存DDC并在独立进程恢复；实际库绑定检查覆盖全部叶级实例。
file mkdir $OUT/parasitics $OUT/corner_databases $OUT/corner_checks
set matrix [open reports/corner_matrix.tsv w]
puts $matrix "pvt\trc_corner\tsetup_slack_ns\thold_slack_ns\tsetup_group\thold_group\tsetup_restore_delta_ns\thold_restore_delta_ns"
set worst [dict create]
set cases 0
foreach library [concat [list $STD_MAX] $SRAM_MAX] {set_min_library $library -none}
require_native_success "解除双库配对，准备逐角提取"
foreach specification $CORNER_SPECS {
    set corner [lindex $specification 0]
    file mkdir $OUT/parasitics/$corner $OUT/corner_databases/$corner $OUT/corner_checks/$corner
    bind_single_corner $corner $OUT/corner_databases/$corner/bound_libraries.txt
    foreach rc $RC_CORNERS {
        set_tlu_plus_files -max_tluplus $RC_DIRECTORY/$rc.tluplus \
            -min_tluplus $RC_DIRECTORY/$rc.tluplus -tech2itf_map $TECH_MAP
        extract_rc -estimate
        set parasitic_max $OUT/parasitics/$corner/${rc}_max.spef
        set parasitic_min $OUT/parasitics/$corner/${rc}_min.spef
        write_parasitics -output $parasitic_max
        write_parasitics -min -output $parasitic_min
        require_native_success "RC提取$corner/$rc"
        foreach parasitic [list $parasitic_max $parasitic_min] {
            if {![file isfile $parasitic] || [file size $parasitic] == 0} {error "没有生成寄生参数：$parasitic"}
        }
        set native_result [timing_extrema $corner/$rc $OUT/reports/native_corners/$corner/$rc]
        write -format ddc -hierarchy -output $OUT/corner_databases/$corner/$rc.ddc
        require_native_success "逐角原生数据库保存"
        set case_output $OUT/corner_checks/$corner/$rc
        set env(SOC_MODE) corner
        set env(SOC_PARENT_OUT) $OUT
        set env(SOC_CASE_OUT) $case_output
        set env(SOC_CORNER) $corner
        set env(SOC_RC) $rc
        set case_log $OUT/corner_checks/$corner/${rc}.log
        exec $DC -topographical_mode -f $SCRIPT > $case_log 2>@1
        set f [open $case_log r]
        set text [read $f]
        close $f
        # 子进程逐阶段核对原生错误计数，完成标记只在这些检查全部通过后写出。
        if {[string first "\nSOC_CORNER_ANALYSIS_COMPLETED $corner/$rc " "\n$text"] < 0} {
            error "逐角分析没有完成：$corner/$rc，日志$case_log"
        }
        set f [open $case_output/reports/extrema.tcldata r]
        set result [read $f]
        close $f
        if {[dict get $result case] ne "$corner/$rc"} {error "逐角结果标识不一致"}
        set restore_deltas [dict create]
        foreach delay {max min} {
            set delta [expr {[dict get $result $delay slack_ns] - [dict get $native_result $delay slack_ns]}]
            if {abs($delta) > 0.0002} {error "原生数据库恢复后的时序不一致：$corner/$rc/$delay，差值$delta ns"}
            dict set restore_deltas $delay $delta
        }
        puts $matrix [join [list $corner $rc [dict get $result max slack_ns] \
            [dict get $result min slack_ns] [dict get $result max group] [dict get $result min group] \
            [dict get $restore_deltas max] [dict get $restore_deltas min]] "\t"]
        flush $matrix
        foreach delay {max min} {
            if {![dict exists $worst $delay] || \
                [dict get $result $delay slack_ns] < [dict get $worst $delay slack_ns]} {
                dict set worst $delay [dict merge [dict get $result $delay] [dict create pvt $corner rc $rc]]
            }
        }
        incr cases
        puts "SOC_CORNER_RESULT $corner $rc setup=[dict get $result max slack_ns] hold=[dict get $result min slack_ns]"
    }
}
close $matrix
if {$cases != 35} {error "工艺角与RC组合数量错误：$cases"}
dict for {path digest} $HASHES {
    if {[exec sha256sum -- $path] ne $digest} {error "多角检查期间输入已变化：$path"}
}
set f [open reports/corner_extrema.tcldata w]
puts $f $worst
close $f
set accepted [expr {[dict get $worst max slack_ns] >= 0 && [dict get $worst min slack_ns] >= 0}]
set f [open reports/timing_acceptance.txt w]
puts $f "SYNTHESIS=COMPLETED\nINTERCONNECT=TLUPLUS_VIRTUAL_ROUTE\nPVT_CORNERS=7\nRC_CORNERS=5\nANALYZED_COMBINATIONS=$cases"
puts $f "TIMING_PASS=$accepted"
foreach delay {max min} {puts $f "$delay [dict get $worst $delay]"}
close $f
puts "SOC_SYNTHESIS_AND_CORNERS_COMPLETED $VERSION $OUT"
if {!$accepted} {error "150MHz多角时序检查存在违例，具体路径和裕量见reports/timing_acceptance.txt"}
exit
