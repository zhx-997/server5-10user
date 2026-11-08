# 修改本文件中的位置即可迁移工程；目录中的库型号、RC 组合和测试内容保持固定。
set PIPELINE [file normalize [file join [file dirname [info script]] ..]]
set PROJECT [file normalize ~/soc_20261107]
set OFFICIAL $PROJECT/official
set ACCEL [file normalize ~/v4.3]
set BASELINE $PROJECT/candidate_e2
set PREVIOUS $PROJECT/candidate_astra_p5
set PLATFORM_RTL $PROJECT/rtl
set REFERENCE $PIPELINE/reference
set VECTOR_PATH $ACCEL/vec/streams/worst

set LIB_PATH [file normalize ~/shared/libraries]
set SMALL_SRAM_ORIGINAL $LIB_PATH
set SMALL_SRAM_DERIVED $PROJECT/astra_sram_corners_g5/libraries
set LARGE_SRAM_ROOT $OFFICIAL/mem_gen

set PHYSICAL_INPUT $PROJECT/astra_physical_inputs_g8
set TECHNOLOGY_FILE $PROJECT/astra_physical_technology_g12/technology.tf
set TECHNOLOGY_HASHES $PROJECT/astra_physical_technology_g12/inputs.sha256
set MW_REFERENCE $PROJECT/astra_physical_library_g14/reference
set PHYSICAL_HASHES $PROJECT/astra_physical_library_g9/input_sha256.txt
set BIAS_HASHES $PROJECT/astra_physical_library_g14/bias_input_sha256.txt
set REFERENCE_HASHES $PROJECT/astra_physical_library_g14/reference_sha256.json
set MACRO_LEF_ROOT $PROJECT/astra_macro_physical_g9
set RC_DIRECTORY $PHYSICAL_INPUT/rc/1P9M_2TM
set TECH_MAP $PROJECT/astra_arm_physical_g10/1P9M_2TM/tluplus.map

set DC /eda/synopsys/dc/dc_2022.03-SP5-5/bin/dc_shell
set VCS /eda/synopsys/vcs/vcs_2020.03-SP2-6/bin/vcs
set PYTHON /bin/python3
set RUN_ROOT $PIPELINE/work/dc
set REPORT_ROOT $PIPELINE/work/reports

# 迁移已有 E2/P5 验证记录时，逐项填写原路径前缀与新路径前缀。
# 只替换文件位置；原记录的 SHA256 和测试判据继续逐项检查。
set MANIFEST_PATH_MAP {}
