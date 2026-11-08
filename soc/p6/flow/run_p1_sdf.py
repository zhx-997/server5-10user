import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess

parser = argparse.ArgumentParser()
parser.add_argument("--synthesis", type=Path, required=True)
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--testbench", type=Path, required=True)
args = parser.parse_args()
candidate = args.candidate.resolve(strict=True)
synthesis = args.synthesis.resolve(strict=True)
testbench = args.testbench.resolve(strict=True)
functional = json.loads((candidate / "verification_pass.json").read_text())
if functional["passed"] is not True:
    raise RuntimeError("RTL 功能验证没有通过")
with (synthesis / "reports/corner_matrix.tsv").open() as stream:
    matrix = list(csv.DictReader(stream, delimiter="\t"))
if len(matrix) != 35 or len({(row["pvt"], row["rc_corner"]) for row in matrix}) != 35:
    raise RuntimeError("35 个 PVT 和 RC 组合分析未完成")
selected = [
    ("setup", min(matrix, key=lambda row: float(row["setup_slack_ns"])), "MAXIMUM"),
    ("hold", min(matrix, key=lambda row: float(row["hold_slack_ns"])), "MINIMUM"),
]
manifest = json.loads((candidate / "verified_inputs.json").read_text())
for name, digest in manifest.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("已验证的输入发生变化：" + name)
models = [Path(name) for name in manifest if Path(name).suffix == ".v" and
          ("scc40" in Path(name).name.lower() or Path(name).name.startswith(("RAMSP", "ROM1KX32", "ROM2KX32")))]
if len([p for p in models if "scc40" in p.name.lower()]) != 1:
    raise RuntimeError("必须指定唯一的真实 HVT 标准单元仿真库")
netlist = synthesis / "netlist/soc_mapped.v"
firmware = candidate / "firmware/firmware.hex"
root = Path.home() / "soc_20261107"
output = synthesis / "sdf_soc_checks"
output.mkdir(exist_ok=False)
scratch = output / "scratch"
scratch.mkdir()
env = dict(os.environ)
env.update({key: str(scratch) for key in ("TMPDIR", "TMP", "TEMP")})
command = ["/eda/synopsys/vcs/vcs_2020.03-SP2-6/bin/vcs", "-full64", "-sverilog",
           "-timescale=1ns/1ps", "-top", "tb_soc_gate", "+neg_tchk", "-negdelay",
           "+define+GATE_LEVEL", "+incdir+" + str(root / "official/core"),
           str(testbench), str(netlist), *map(str, models), "-o", str(output / "simv")]
(output / "compile_command.json").write_text(json.dumps(command, indent=2))
with (output / "compile.log").open("w") as stream:
    subprocess.run(command, cwd=output, env=env, stdin=subprocess.DEVNULL, stdout=stream,
                   stderr=subprocess.STDOUT, check=True, timeout=1800)
records = []
for purpose, row, mode in selected:
    run = output / purpose
    run.mkdir()
    sdf = synthesis / "corner_checks" / row["pvt"] / row["rc_corner"] / "netlist/soc_corner.sdf"
    if not sdf.is_file() or sdf.stat().st_size == 0:
        raise FileNotFoundError(sdf)
    inputs = [testbench, netlist, firmware, sdf, *models]
    hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs}
    (run / "input_sha256.json").write_text(json.dumps(hashes, indent=2))
    command = [str(output / "simv"), "+sdfverbose", "+SDF=" + str(sdf), "+SDF_MODE=" + mode,
               "+FIRMWARE=" + str(firmware), "+VEC_DIR=" + str(Path.home() / "v4.3/vec/streams/worst")]
    with (run / "simulation.log").open("w") as stream:
        subprocess.run(command, cwd=run, env=env, stdin=subprocess.DEVNULL, stdout=stream,
                       stderr=subprocess.STDOUT, check=True, timeout=14400)
    text = (run / "simulation.log").read_text(errors="replace")
    if "SOC_EXECUTION_ALL_PASS tasks=12 checked_words=58547 boots=2" not in text:
        raise RuntimeError("带延迟的整机功能验证失败：" + purpose)
    if re.search(r"(?i)timing violation|Warning-\[SDF|Error-\[|Fatal:|\$setuphold.*violat", text):
        raise RuntimeError("出现 SDF 标注或时序检查诊断：" + str(run / "simulation.log"))
    for name, digest in hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("门级仿真期间输入发生变化：" + name)
    record = {"purpose": purpose, "pvt": row["pvt"], "rc": row["rc_corner"],
              "sdf_mode": mode, "functional_completed": True,
              "log": str(run / "simulation.log"),
              "log_sha256": hashlib.sha256((run / "simulation.log").read_bytes()).hexdigest()}
    records.append(record)
    (output / "execution_records.json").write_text(json.dumps(records, indent=2))
    print("P1_SDF_FUNCTIONAL_COMPLETED", json.dumps(record), flush=True)
