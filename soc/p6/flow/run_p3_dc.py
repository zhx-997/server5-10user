import hashlib
import json
import os
from pathlib import Path
import subprocess
import time

directory = Path(__file__).resolve().parent
candidate = Path.home() / "soc_20261107/candidate_astra_p6"
verification = json.loads((candidate / "verification_pass.json").read_text())
if verification["passed"] is not True:
    raise RuntimeError("功能验证没有全部通过")
script = directory / "dc_synth.tcl"
output = Path.home() / "soc_20261107/reports" / ("astra_p6_execution_" + time.strftime("%Y%m%d_%H%M%S"))
output.mkdir(exist_ok=False)
scratch = output / "scratch"
scratch.mkdir()
environment = dict(os.environ)
environment.update({key: str(scratch) for key in ("TMPDIR", "TMP", "TEMP")})
environment["SOC_MODE"] = "synth"
hashes = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in (script, directory / "verify_p1_for_dc.py")}
(output / "input_sha256.json").write_text(json.dumps(hashes, indent=2))
records = []
for check_only, stage, marker in (("1", "structure", "SOC_STRUCTURE_CHECK_COMPLETED"),
                                 ("0", "synthesis", "SOC_SYNTHESIS_AND_CORNERS_COMPLETED")):
    for name, digest in hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("综合输入文件发生变化：" + name)
    environment["SOC_CHECK_ONLY"] = check_only
    logfile = output / (stage + ".log")
    command = ["/eda/synopsys/dc/dc_2022.03-SP5-5/bin/dc_shell", "-topographical_mode", "-f", str(script)]
    print("P6_DC_STARTED", stage, str(logfile), flush=True)
    with logfile.open("w") as log:
        process = subprocess.run(command, cwd=output, env=environment, stdin=subprocess.DEVNULL,
                                 stdout=log, stderr=subprocess.STDOUT)
    messages = [line for line in logfile.read_text(errors="replace").splitlines() if line.startswith(marker + " ")]
    if process.returncode or len(messages) != 1:
        raise RuntimeError("DC 阶段失败：{}，退出码 {}，日志 {}".format(stage, process.returncode, logfile))
    result_directory = Path(messages[0].split()[2])
    record = {"stage": stage, "directory": str(result_directory), "log": str(logfile)}
    records.append(record)
    (output / "progress.json").write_text(json.dumps(records, indent=2))
    print("P6_DC_COMPLETED", json.dumps(record), flush=True)
    if stage == "synthesis" and "TIMING_PASS=1" not in (result_directory / "reports/timing_acceptance.txt").read_text().splitlines():
        raise RuntimeError("35 角计算已完成，150MHz 时序验收失败；检查 " + str(result_directory / "reports/timing_acceptance.txt"))
print("P6_DC_EXECUTION_COMPLETE", str(output), flush=True)
