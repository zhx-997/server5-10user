# E203 + KWT 整机 P6

P6 在 LSU 的 CPU/NICE 请求仲裁之后、ITCM/DTCM/BIU 地址分流之前增加一级请求寄存器。完整请求包含地址、读写方向、写数据、字节使能、锁定、独占、大小、突发、节拍和响应归属信息。该级使用官方 `sirv_gnrl_pipe_stage`，`DP=1`、`CUT_READY=1`，缓冲中仍有请求时保持 LSU 时钟工作。

本目录是整机时序优化版本，功能验证已通过。150 MHz 整机时序与规定面积的联合验收尚未通过；`results/acceptance.json` 分别记录 P5 已完成的综合结果和 P6 的功能结果。P6 的综合脚本使用 P6 自身源码重新计算。

## 文件

| 路径 | 内容 |
|---|---|
| `rtl/` | 七个 P6 修改模块、六个 SoC/工艺适配模块、四个 E203/NICE 集成修正模块 |
| `tb/` | ITCM 随机事务测试、真实 CPU 启动与 12 项任务、整机 SDF 测试平台 |
| `firmware/` | ROM 跳转后的启动程序、异常/中断检查、NICE 调度程序及实际使用的 HEX |
| `flow/dc_synth.tcl` | 标准单元、SRAM、RTL、约束、Topographical 综合、7×5 角检查 |
| `flow/verify_p1_for_dc.py` | 综合前核对十项功能测试、实际编译源码、向量与日志 SHA256 |
| `flow/run_p1_verification.py` | 服务器上的完整功能测试与 P5 同条件周期比较 |
| `flow/run_p3_dc.py` | 顺序执行结构检查、完整综合、时序验收 |
| `flow/run_p1_sdf.py` | 对最终建立/保持最差条件执行整机 SDF 仿真 |
| `results/source_sha256.json` | 本导出目录逐文件校验值 |

其余加速器源码沿用仓库 `v4.3/rtl/`；CPU、通用总线、外设和宏模型来自竞赛服务器已验证的 `official/`。厂家工艺模型、综合网表、波形、凭据与服务器个人路径保留在服务器环境中。

## 时序设置

主时钟 150 MHz，建立/保持不确定度为 0.300/0.100 ns，输入最大/最小延迟为 1.000/0.100 ns，输出为 1.000/−0.100 ns。JTAG 为 10 MHz，AON 为 32.768 kHz。驱动单元为实际 HVT 库的 `INV1_12TH40`，输出负载为 0.003396 pF。

标准单元使用 SMIC40 HVT，SRAM 使用真实宏 `.db`。互连使用同工艺 1P9M_2TM 物理库、TLUPlus 与层映射。七个工艺/电压/温度角分别搭配 CMAX、CMIN、RCMAX、RCMIN、TYP，最终对同一网表分析 35 个组合。

`SRAM_TO_LOGIC` 用 `-through` 指定宏输出端，`LOGIC_TO_SRAM` 指定除 CLK 外的宏输入端。映射后检查宏输出路径和分组非空。脚本保存初次映射结果，执行电气规则增量修复，再以 `set_cost_priority -min_delay` 执行保持修复，最后重新检查全部建立和保持路径。SVF 从读入 RTL 前开始记录至最终命名完成。当前流程未启用自动 retime。

## 服务器运行

脚本以当前用户主目录为根。下列既有平台目录须完整存在：`shared/libraries`、`v4.3`，以及 `soc_20261107` 下的 `official`、`rtl`、`candidate_e2`、`candidate_astra_p5`、`candidate_astra_p6` 和脚本所列物理/RC 派生目录。脚本会逐项检查文件、库、宏数量和功能验证记录。

源码位置对应如下：P6 七个模块来自 `candidate_astra_p6/rtl`；`kwt_generic_hvt`、`kwt_banked_sram`、两个 `sram_wrap`、`kwt_shared_sram`、`e203_subsys_top` 来自平台 `rtl`；`kwt43_reader`、`kwt43_writer`、`kwt43_icb_master`、`e203_subsys_nice_core` 来自 `candidate_e2`。导出文件保留其实际实现。

在服务器已有 P6 验证目录上，从本目录执行：

```sh
python3 flow/run_p3_dc.py
```

程序先运行 `SOC_CHECK_ONLY=1`，结构检查成功后才开始完整综合。35 组分析中存在负裕量时返回失败，不能用工具正常退出代替时序验收。

最终时序通过后，使用本次综合目录运行带延迟检查：

```sh
python3 flow/run_p1_sdf.py --synthesis "$SYNTHESIS_DIR" \
  --candidate "$HOME/soc_20261107/candidate_astra_p6" \
  --testbench tb/tb_soc_gate.sv
```

## 功能与性能记录

P6 的十项 VCS 测试全部通过，包含四组 ITCM 随机测试、P6 整机、P5 同条件比较和四种加速器测试。P6 整机完成两次 ROM 启动和 12 项真实 CPU 发起的 NICE 任务，核对 58,547 个结果及输出区保护值。新增 LSU 级接受/下游消费各 271,210 条请求，ITCM/DTCM/BIU 分别为 252/64/270,894 条。

任务区间从输入和参数开始装载，到最后一次结果写响应。12 项任务 P5 为 1,571,784 周期，P6 为 1,617,436 周期，增加 2.90447%。按 150 MHz 换算分别为 1,145.20 和 1,112.87 task/s；这是相同时钟下的周期效率比较，硬件频率是否通过由各版自身的时序验收决定。

面积要求按赛题统计新增计算逻辑、接口和内部 SRAM；复用 E203、共享 SRAM 与固定总线外设另列。整机总单元面积不能直接代入新增加速器的面积限制。

P5 的库面积已与 LEF 宽×高交叉核对，单位为 µm²。整机单元面积为 3.987172 mm²，`u_kwt` 层次面积为 0.868960 mm²。仅扣除复用 CPU 和共享存储的 24 个 RAMSP8KX32、8 个 RAMSP4KX64 宏，把其余 CPU 逻辑、外设、新增接口和加速器全部计入，面积上界为 1.020570 mm²，仍低于 2.25 mm²。由此 P5 满足新增电路的面积限制；P6 使用新综合网表单独检查面积。
