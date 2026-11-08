if {$argc != 1} {error "需要指定 paths.tcl"}
source [file normalize [lindex $argv 0]]
fconfigure stdout -encoding utf-8 -translation binary
foreach key {PIPELINE PROJECT OFFICIAL ACCEL BASELINE PREVIOUS PLATFORM_RTL REFERENCE VECTOR_PATH
    LIB_PATH SMALL_SRAM_ORIGINAL SMALL_SRAM_DERIVED LARGE_SRAM_ROOT PHYSICAL_INPUT
    TECHNOLOGY_FILE TECHNOLOGY_HASHES MW_REFERENCE PHYSICAL_HASHES BIAS_HASHES
    REFERENCE_HASHES MACRO_LEF_ROOT RC_DIRECTORY TECH_MAP DC VCS PYTHON RUN_ROOT REPORT_ROOT} {
    if {![info exists $key] || [set $key] eq ""} {error "路径配置缺失：$key"}
    puts -nonewline stdout "$key\0[file normalize [set $key]]\0"
}
if {[llength $MANIFEST_PATH_MAP] % 2} {error "路径迁移配置必须成对填写"}
puts -nonewline stdout "REMAP_COUNT\0[expr {[llength $MANIFEST_PATH_MAP] / 2}]\0"
set index 0
foreach {old new} $MANIFEST_PATH_MAP {
    puts -nonewline stdout "REMAP_OLD_$index\0$old\0REMAP_NEW_$index\0[file normalize $new]\0"
    incr index
}
