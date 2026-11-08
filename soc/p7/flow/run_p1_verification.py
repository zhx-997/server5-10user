import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import time
from path_config import load_paths, relocate_manifest

parser = argparse.ArgumentParser()
parser.add_argument("--paths", type=Path, default=Path(__file__).with_name("paths.tcl"))
args = parser.parse_args()
paths = load_paths(args.paths)
root = Path(paths["PROJECT"])
candidate = Path(paths["PIPELINE"]).resolve(strict=True)
package_manifest = json.loads((candidate / "package_manifest.json").read_text())
for name, digest in package_manifest.items():
    if hashlib.sha256((candidate / name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("测试包文件校验失败：" + name)
official = Path(paths["OFFICIAL"])
baseline = Path(paths["BASELINE"])
accel = Path(paths["ACCEL"])
reference_root = Path(paths["REFERENCE"])
baseline_manifest = relocate_manifest(json.loads((baseline / "source_manifest.json").read_text()), paths)
for name, digest in baseline_manifest.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("e2 基准输入已经变化：" + name)
original = official / "core/e203_itcm_ctrl.v"
reference = reference_root / "e203_itcm_ctrl.v"
if original.read_text() != reference.read_text():
    raise RuntimeError("服务器 ITCM 原始控制器与修改基准不同，必须先检查差异")
for relative in ("core/e203_ifu.v", "core/e203_ifu_ift2icb.v", "core/e203_lsu_ctrl.v", "core/e203_reset_ctrl.v", "perips/sirv_ResetCatchAndSync_2.v", "mems/sirv_mrom.v"):
    if (official / relative).read_text() != (reference_root / Path(relative).name).read_text():
        raise RuntimeError("复位或启动源码与核查依据不同：" + relative)
if (Path(paths["PLATFORM_RTL"]) / "kwt_e203_soc_top.v").read_text() != (reference_root / "kwt_e203_soc_top.v").read_text():
    raise RuntimeError("顶层源码与修改基准不同")

vcs = paths["VCS"]
run_root = candidate / "verification"
run_root.mkdir()
records = []
definitions = "+define+functional+KWT_USE_FOUNDRY_SRAM+ARM_UD_MODEL+DISABLE_SV_ASSERTION+KWT_PERIOD_NS=6.666666667+KWT_MEM_BASE=32'hA0000000+KWT_MEM_BYTES=524288"
include_dirs = sorted({str(path.parent) for path in official.rglob("*.v")})

def check_inputs(inputs):
    unique = list(dict.fromkeys(map(Path, inputs)))
    for source in unique:
        if not source.is_file():
            raise FileNotFoundError(source)
    return unique

def execute(top, sources, runtime_arguments, required, label=None, extra_definitions=()):
    run = run_root / (label or top)
    run.mkdir()
    scratch = run / "scratch"
    scratch.mkdir()
    env = dict(os.environ)
    env.update({key: str(scratch) for key in ("TMPDIR", "TMP", "TEMP")})
    inputs = check_inputs(sources)
    manifest = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (run / "source_manifest.json").write_text(json.dumps(manifest, indent=2))
    command = [vcs, "-full64", "-sverilog", "-timescale=1ns/1ps", "-top", top, definitions]
    command += ["+define+" + value for value in extra_definitions]
    command += ["+incdir+" + value for value in include_dirs]
    command += ["+incdir+" + str(accel / "rtl")]
    command += list(map(str, inputs)) + ["-o", "simv"]
    (run / "command.json").write_text(json.dumps(command, indent=2))
    with (run / "compile.log").open("w") as log:
        compilation = subprocess.run(command, cwd=run, env=env, stdin=subprocess.DEVNULL,
                                     stdout=log, stderr=subprocess.STDOUT, timeout=1800)
    if compilation.returncode:
        raise RuntimeError("VCS 编译失败，退出码 {}，日志 {}".format(compilation.returncode, run / "compile.log"))
    print("P1_COMPILED", top, flush=True)
    started = time.monotonic()
    with (run / "simulation.log").open("w") as log:
        simulation = subprocess.run([str(run / "simv"), *runtime_arguments], cwd=run, env=env,
                                    stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
                                    timeout=3600)
    if simulation.returncode:
        raise RuntimeError("VCS 仿真失败，退出码 {}，日志 {}".format(simulation.returncode, run / "simulation.log"))
    result = (run / "simulation.log").read_text(errors="replace")
    if any(text not in result for text in required) or re.search(r"(?im)^\s*(fatal|error)[:\[]", result):
        raise RuntimeError("功能验证未通过：" + str(run))
    record = {"test": run.name, "passed": True, "seconds": time.monotonic() - started,
              "log_sha256": hashlib.sha256((run / "simulation.log").read_bytes()).hexdigest()}
    records.append(record)
    (run_root / "progress.json").write_text(json.dumps(records, indent=2))
    print("P1_TEST_PASS", json.dumps(record), flush=True)
    return result

unit_sources = [candidate / "tb/tb_itcm_pipeline.sv", candidate / "rtl/e203_itcm_ctrl.v",
                candidate / "rtl/kwt_itcm_sram_icb_ctrl.sv", candidate / "rtl/kwt_generic_hvt.v",
                official / "core/e203_clkgate.v"]
unit_sources += [official / ("general/" + name) for name in (
    "sirv_gnrl_dffs.v", "sirv_gnrl_bufs.v", "sirv_gnrl_icbs.v",
    "sirv_1cyc_sram_ctrl.v", "sirv_sram_icb_ctrl.v", "sirv_sim_ram.v")]
vendor = [Path(name) for name in baseline_manifest if Path(name).suffix == ".v"
          and ("scc40" in Path(name).name.lower() or Path(name).name.startswith("RAMSP"))]
if len([p for p in vendor if "scc40" in p.name.lower()]) != 1:
    raise RuntimeError("必须从已核实清单中确定唯一 HVT 仿真库")
unit_sources += [p for p in vendor if "scc40" in p.name.lower()]
for seed in (20304007, 7919, 65537, 104729):
    execute("tb_itcm_pipeline", unit_sources, ["+SEED=" + str(seed)],
            ["ITCM_PIPELINE_PASS", "reset_aborted=4", "max_pending=3"], "unit_" + str(seed))

replaced = {"e203_ifu.v", "e203_ifu_ift2icb.v", "e203_lsu_ctrl.v", "e203_itcm_ctrl.v", "e203_subsys_top.v", "e203_subsys_nice_core.v",
            "sram_wrap_64KX32.v", "sram_wrap_32KX64.v", "GENERIC_RVT_SMIC.v", "sirv_mrom_top.v"}
design_sources = []
for directory in ("core", "general", "subsys", "perips", "debug", "mems", "fab"):
    design_sources += [p for p in sorted((official / directory).rglob("*.v")) if p.name not in replaced]
for name in ("kwt_quantize.sv", "kwt_mul16_pipe.sv", "kwt_sp_ram.sv", "kwt_rice_pack.sv",
             "kwt43_icb_master.sv", "kwt43_unpack.sv", "kwt43_dot.sv", "kwt43_xram.sv",
             "kwt43_wram.sv", "kwt43_yram.sv", "kwt43_reader.sv", "kwt43_writer.sv",
             "kwt43_compute.sv", "kwt43_core.sv", "kwt_nice_core.sv"):
    directory = candidate / "rtl" if name in {"kwt43_icb_master.sv", "kwt43_reader.sv", "kwt43_writer.sv", "kwt43_xram.sv", "kwt43_wram.sv"} else accel / "rtl"
    design_sources.append(directory / name)
design_sources.append(candidate / "rtl/e203_subsys_nice_core.v")
design_sources += [candidate / ("rtl/" + name) for name in ("kwt_generic_hvt.v", "kwt_banked_sram.sv",
                   "sram_wrap_64KX32.v", "sram_wrap_32KX64.v", "kwt_shared_sram.sv", "e203_subsys_top.v")]
design_sources += [candidate / ("rtl/" + name) for name in ("e203_ifu.v", "e203_ifu_ift2icb.v", "e203_lsu_ctrl.v", "e203_itcm_ctrl.v", "kwt_itcm_sram_icb_ctrl.sv", "kwt_e203_soc_top.v", "sirv_mrom_top.v")]
models = vendor + [official / ("mem_gen/{0}/verilog/{0}.v".format(name)) for name in ("RAMSP8KX32", "RAMSP4KX64", "ROM1KX32", "ROM2KX32")]
soc_sources = [candidate / "tb/tb_soc_boot.sv", *design_sources, *models]
firmware = candidate / "firmware/firmware.hex"
vectors = Path(paths["VECTOR_PATH"])
soc_result = execute("tb_soc_boot", soc_sources, ["+FIRMWARE=" + str(firmware), "+VEC_DIR=" + str(vectors)],
                     ["SOC_EXECUTION_ALL_PASS tasks=12 checked_words=58547 boots=2", "FETCH_REQUEST_STAGE_PASS", "LSU_REQUEST_STAGE_PASS", "SOC_PERFORMANCE_TOTAL"],
                     extra_definitions=("KWT_LSU_REQUEST_STAGE",))
if soc_result.count("SOC_BOOT_PASS") != 2 or soc_result.count("SOC_MATRIX_PASS") != 12:
    raise RuntimeError("整机启动或运算覆盖数量不符")
previous = Path(paths["PREVIOUS"])
previous_sources = relocate_manifest(json.loads((previous / "verification/tb_soc_boot/source_manifest.json").read_text()), paths)
comparison_sources = []
for name, digest in previous_sources.items():
    source = Path(name)
    if hashlib.sha256(source.read_bytes()).hexdigest() != digest:
        raise RuntimeError("P5 比较基准发生变化：" + name)
    comparison_sources.append(candidate / "tb/tb_soc_boot.sv" if source.name == "tb_soc_boot.sv" else source)
previous_result = execute("tb_soc_boot", comparison_sources,
    ["+FIRMWARE=" + str(firmware), "+VEC_DIR=" + str(vectors)],
    ["SOC_EXECUTION_ALL_PASS tasks=12 checked_words=58547 boots=2", "SOC_PERFORMANCE_TOTAL"],
    label="tb_soc_boot_p5_comparison")
performance_pattern = re.compile(r"SOC_TASK_PERFORMANCE layer=(\d+) nice_cycles=(\d+) read_commands=(\d+) write_commands=(\d+) checked_words=(\d+) workload_cycles=(\d+)")
performance = {}
for name, log in (("p5", previous_result), (candidate.name, soc_result)):
    measurements = [dict(zip(("layer", "nice_cycles", "read_commands", "write_commands", "checked_words", "workload_cycles"), map(int, row)))
                    for row in performance_pattern.findall(log)]
    if len(measurements) != 12 or [item["layer"] for item in measurements] != list(range(12)):
        raise RuntimeError("性能统计没有覆盖全部12项任务：" + name)
    performance[name] = measurements
(candidate / "performance_comparison.json").write_text(json.dumps(performance, indent=2))
accelerator_sources = [candidate / "rtl" / Path(name).name
                       if Path(name).name in {"kwt43_icb_master.sv", "kwt43_reader.sv", "kwt43_writer.sv", "kwt43_xram.sv", "kwt43_wram.sv"}
                       else Path(name) for name in baseline_manifest]
for top in ("tb_kwt_integrated", "tb_kwt_integrated_wait", "tb_kwt_integrated_zero", "tb_kwt_integrated_public"):
    execute(top, accelerator_sources, ["+VEC_DIR=" + str(vectors)],
            ["ALL PASS, 29/29", "STREAM GUARD PASS 25/25"])

verified = check_inputs([*design_sources, *models, firmware, *candidate.glob("tb/*.sv"), args.paths.resolve(strict=True)])
for directory in [*include_dirs, str(accel / "rtl"), str(candidate / "rtl")]:
    for extension in ("*.vh", "*.svh"):
        verified += sorted(Path(directory).glob(extension))
vector_hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(vectors.glob("*.hex"))}
(candidate / "verified_vectors.json").write_text(json.dumps(vector_hashes, indent=2))
hashes = {str(p): hashlib.sha256(p.read_bytes()).hexdigest() for p in verified}
(candidate / "verified_inputs.json").write_text(json.dumps(hashes, indent=2))
with (candidate / "verified_inputs.sha256").open("w") as stream:
    for name, digest in hashes.items():
        stream.write(digest + "  " + name + "\n")
result = {"passed": True, "candidate": str(candidate), "rtl_tests": records,
          "soc_tasks": 12, "soc_checked_words": 58547, "boot_runs": 2,
          "source_manifest_sha256": hashlib.sha256((candidate / "verified_inputs.json").read_bytes()).hexdigest(),
          "synthesis_started": False, "sdf_annotated": False}
(candidate / "verification_pass.json").write_text(json.dumps(result, indent=2))
print("P1_VERIFICATION_COMPLETE", json.dumps(result), flush=True)
