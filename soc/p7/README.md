# E203 + KWT：NICE 接口与 RTL 时序优化

本版以已交付的 `5530ae6` 为基线。E203 通过 NICE 自定义指令启动加速器，访存继续经过原有 LSU 和系统总线；固件、地址分配、CPU 指令执行、定时器和 CPU 时钟门控均保持 P7 实现。

当前为开发交接版本。用户要求先完成 RTL 和功能验证，暂停 DC；本版尚无完整 SoC、综合、SDF 或 Formality 通过记录。接手先读 [交接说明](HANDOFF.txt)、[工作规范](AGENTS.md) 和 [验收记录](results/acceptance.json)。CPU 自带 GPIO、复位结构保持；SRAM 优化保持宏时钟相位，在前置寄存器和外围接口实施。

## RTL

- `sirv_sram_icb_ctrl.v`：通用 SRAM 接口适配草稿。先保存完整请求，再在下降沿驱动 SRAM，返回数据与来源信息一同保存。两个事务额度覆盖全部内部级，原有 ITCM 响应级仍保留。保留同相门控，但请求队列、响应队列和门控使能时序有改动，范围超过单纯增加前置寄存器；组件测试已通过，最小外围改动方案仍需审查。
- `kwt43_xram.sv`、`kwt43_wram.sv`：读有效标志取自与 SRAM 请求相同的下降沿采样。
- `kwt43_yram.sv`：结果 SRAM 的使能、地址、数据在下降沿寄存；读页选择与该请求对齐。
- `kwt43_core.sv`：向结果 SRAM 传递复位，原调度保持不变。
- `kwt_mul16_pipe.sv`：有符号 16 位乘法使用五级流水，每周期可以接收一组输入，数值精度保持不变。
- `kwt43_icb_master.sv`：单事务四状态控制，命令和响应分别寄存，握手由状态寄存器产生。对应 `tb_icb_registered.sv` 已编写，尚未运行。

其余本目录 RTL 保持交付 P7 的实现。综合和仿真均只读取每个模块的一份实现。CPU 官方源码来自 `OFFICIAL`；SRAM 实例在综合中链接 `.db`，在功能仿真中链接厂家模型。

## 目录配置与运行

迁移时编辑 `flow/paths.tcl`：填写官方 CPU、v4.3 加速器依赖、测试向量、标准单元和 SRAM 库、SMIC40 物理库与 RC 文件、工具和结果目录。工程自身目录由该配置文件的位置确定。完整验证还使用 E2/P5 基准源码及清单；这些依赖与受限工艺模型在比赛服务器，目录列表见交接说明。

在本目录运行：

```sh
python3 flow/run_p1_verification.py
```

完整功能脚本当前配置 12 项测试：四组 ITCM、乘法、点积、真实 CPU 启动及 12 项 NICE 矩阵任务、原 P5 同条件对照，以及四种总线条件的矩阵和错误保护测试。新 ICB 单元测试尚未接入此集合，接手应先完成它及 SRAM 边界验证，再同步两个验证入口的测试集合。

已执行的本地组件结果为 ITCM 26,600 笔完成事务、乘法 16,449 组、点积 64 组；见 [日志摘录](results/local_component_checks.txt)。可用 `flow/run_local_units.py` 选择组件，`--suite icb` 用于新 ICB TB。完整整机结果单独记录。

用户恢复综合后才运行 `python3 flow/run_p3_dc.py`。综合入口核对功能日志、实际编译源码和输入校验值；任一项失败即终止。

`verification/`、`work/` 保存本次运行记录。每次完整测试使用独立的工程版本目录，避免覆盖已有证据。`package_manifest.json` 记录交付包文件，迁移目录只调整 `paths.tcl`。

源码或说明修改后，使用 `python3 flow/update_package_manifest.py` 生成交付清单；使用 `--check` 检查清单。清单更新只记录文件内容，不生成任何功能通过标志。`results/source_sha256.json` 还包括交付时的路径配置；可迁移的 `package_manifest.json` 排除 `flow/paths.tcl`，实际测试仍单独核对配置。

## DC 脚本

`flow/dc_synth.tcl` 按设置、约束、综合、报告四部分组织。

1. 设置标准单元、SRAM、RTL、头文件路径和链接库，加载同工艺 Milkyway 与 TLUPlus，然后执行 `analyze`、`elaborate`、`link`。
2. 主时钟 150 MHz，JTAG 10 MHz，常开时钟 32.768 kHz。沿用原接口预算：建立/保持不确定度 0.300/0.100 ns，输入最大/最小延迟 1.000/0.100 ns，输出最大/最小延迟 1.000/−0.100 ns。输入驱动 `INV1_12TH40`，输出负载 0.003396 pF。保留复位与异步输入边界、SRAM 路径分组。
3. 只执行一次 `compile_ultra -no_autoungroup`，按 RTL 中的寄存级综合。
4. 输出 Verilog、DDC、SDC、SDF、SVF，以及面积、建立、保持、电气约束和连接检查报告。

建立使用 SS 0.99 V/−40 ℃、CMAX；保持使用 FF 1.21 V/125 ℃、CMIN，来源为 P6 的全角最差结果。本脚本报告这组最大/最小条件，`PRIMARY_TIMING_PASS` 只标记本组时序结果。

脚本包含工艺模型加载、多时钟和正常报告命令；电路结构与寄存级只在 RTL 中定义。综合流程不执行手工插入缓冲器、替换门或重新连接网表的操作，也不启用 retime 或增量综合。

## 比赛验收

本版功能与综合结果见 `results/acceptance.json`。比赛要求 150 MHz、规定数值精度和新增加速器及接口与内部 SRAM 面积不超过 2.25 mm²。吞吐量包含输入与参数装载、总线等待、CPU 调度和结果写回。整机功耗需要同一网表、同一计时窗口内的活动数据，不能由面积或频率推算。
