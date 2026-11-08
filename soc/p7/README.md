# E203 + KWT 整机 P7

P7 基于 P6，修改输入缓存、权重缓存和外部复位输出三处 RTL。输入、权重 SRAM 的使能、地址和写数据在时钟下降沿保存，宏继续在上升沿执行读写；`sys_rst_n` 保留异步置位复位、同步释放，并将释放安排在下降沿。新增的半周期路径需要通过原有 150 MHz 约束检查。

本目录用于提交和验证这次 RTL 修改。实际验收状态见 `results/acceptance.json`。P6 已完成十项功能测试；P6 主条件仍有 401 个保持违例端点，包括输入、权重、输出 SRAM、ITCM、DTCM 和顶层输出。P7 的三处修改范围是输入缓存、权重缓存和 `sys_rst_n`。

## 队友如何配置目录

只编辑 `flow/paths.tcl`。仿真、综合和带延迟仿真共同读取该文件。`PIPELINE` 默认由配置文件自身位置确定，`rtl/`、`tb/`、`firmware/`、`reference/` 随整个 P7 目录移动。十九个交付 RTL 均从这里读取，其余 CPU 和加速器源码从配置中的原工程读取。

| 配置项 | 填写的内容 |
|---|---|
| `OFFICIAL` | 竞赛 E203 源码，目录中含 `core`、`general`、`subsys`、`perips`、`debug`、`mems`、`fab` |
| `ACCEL`、`VECTOR_PATH` | v4.3 工程和已验证的测试向量 |
| `BASELINE`、`PREVIOUS` | E2、P5 验证目录，保留原源码清单，用于四类总线测试和同条件性能比较 |
| `PLATFORM_RTL` | 原平台 RTL，供修改依据检查使用 |
| `LIB_PATH` | SMIC40 HVT 标准单元 `.db` |
| `SMALL_SRAM_ORIGINAL`、`SMALL_SRAM_DERIVED` | 小型 SRAM 原始库、补齐角的派生库 |
| `LARGE_SRAM_ROOT` | RAMSP8KX32、RAMSP4KX64、ROM1KX32、ROM2KX32 的宏目录，每种宏含 `db` |
| 物理模型配置项 | 同工艺技术文件、Milkyway 参考库、五组 TLUPlus、层映射、LEF 和校验记录 |
| `DC`、`VCS`、`PYTHON` | 已安装工具的可执行文件 |
| `RUN_ROOT`、`REPORT_ROOT` | 本次版本的综合结果和执行日志目录 |

现有目录结构与比赛服务器相同时，保留默认值。迁移已有 E2/P5 验证记录时，在 `MANIFEST_PATH_MAP` 中成对填写旧路径前缀与新路径前缀；脚本仍核对原文件 SHA256。Python 通过系统 `tclsh` 解释配置，支持服务器已安装的 Tcl 8.5。

工艺库、厂家宏模型、原始验证目录和测试向量需要由队友从授权的比赛环境取得。配置、源码位置发生变化后，重新执行功能验证，生成当前位置的真实编译清单。综合前逐项核对这些清单。

## 执行

在 P7 目录执行：

```sh
python3 flow/run_p1_verification.py
python3 flow/run_p3_dc.py
```

第一条运行原有十项 VCS 测试：四组 ITCM 随机测试、P7 整机启动和 12 项 NICE 任务、P5 同条件比较、四种加速器总线测试。第二条先核对功能结果，再执行结构检查，结构检查成功后开始完整综合。任何阶段失败均立即停止。

更换整份配置可使用 `--paths /实际位置/paths.tcl`。直接调用 DC 时，用 `SOC_PATHS` 指定同一文件：

```sh
SOC_PATHS=/实际位置/paths.tcl dc_shell -topographical_mode -f flow/dc_synth.tcl
```

所有 35 组时序通过后，用实际综合目录执行带延迟整机检查：

```sh
python3 flow/run_p1_sdf.py --synthesis /实际位置/本次综合目录 \
  --candidate /实际位置/P7目录 --testbench tb/tb_soc_gate.sv
```

每个 P7 目录仅用于一次完整验证，结果保存在自身的 `verification/` 和 `work/`。重跑时复制交付文件到新的版本目录，重新填写路径并运行。

## 固定的综合条件

沿用 P6 的 150 MHz 主时钟，建立/保持不确定度 0.300/0.100 ns，输入最大/最小延迟 1.000/0.100 ns，输出 1.000/−0.100 ns；JTAG 为 10 MHz，AON 为 32.768 kHz。驱动单元为 `INV1_12TH40`，输出负载为 0.003396 pF。

标准单元使用 SMIC40 HVT，SRAM 使用实际宏 `.db`；互连使用 1P9M_2TM Milkyway 与 TLUPlus。先执行原有 `compile_ultra -no_autoungroup`，再执行原有两次增量综合；没有启用 retime。最终对同一网表分析七个 PVT 与五个 RC 的 35 个组合。测试平台、功能判据、约束和综合策略沿用 P6。

`package_manifest.json` 核对 RTL、测试平台、固件、参考源码和流程脚本。可编辑的 `paths.tcl` 单独记录到每次实际验证清单。`results/source_sha256.json` 提供本次提交文件的下载校验值。
