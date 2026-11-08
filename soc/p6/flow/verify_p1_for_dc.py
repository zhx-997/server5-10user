import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument("--candidate", type=Path, required=True)
parser.add_argument("--sources", type=Path, required=True)
args = parser.parse_args()
candidate = args.candidate.resolve(strict=True)
result = json.loads((candidate / "verification_pass.json").read_text())
required = {"unit_20304007", "unit_7919", "unit_65537", "unit_104729", "tb_soc_boot", "tb_soc_boot_p5_comparison",
            "tb_kwt_integrated", "tb_kwt_integrated_wait", "tb_kwt_integrated_zero", "tb_kwt_integrated_public"}
records = result["rtl_tests"]
if result["passed"] is not True or {r["test"] for r in records} != required or len(records) != len(required):
    raise RuntimeError("完整功能验证没有通过")
if result["soc_tasks"] != 12 or result["soc_checked_words"] != 58547 or result["boot_runs"] != 2:
    raise RuntimeError("整机验证覆盖数量不符")
manifest_path = candidate / "verified_inputs.json"
if hashlib.sha256(manifest_path.read_bytes()).hexdigest() != result["source_manifest_sha256"]:
    raise RuntimeError("已验证的输入清单发生变化")
manifest = json.loads(manifest_path.read_text())
for name, digest in manifest.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("功能验证后的文件发生变化：" + name)
compiled = {}
for record in records:
    if record["passed"] is not True:
        raise RuntimeError("功能测试失败：" + record["test"])
    directory = candidate / "verification" / record["test"]
    if hashlib.sha256((directory / "simulation.log").read_bytes()).hexdigest() != record["log_sha256"]:
        raise RuntimeError("仿真日志发生变化")
    for name, digest in json.loads((directory / "source_manifest.json").read_text()).items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
            raise RuntimeError("源码与实际仿真编译版本不一致：" + name)
        compiled[name] = digest
for name, digest in json.loads((candidate / "package_manifest.json").read_text()).items():
    if hashlib.sha256((candidate / name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("测试包输入发生变化：" + name)
for name, digest in json.loads((candidate / "verified_vectors.json").read_text()).items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest() != digest:
        raise RuntimeError("测试向量发生变化：" + name)
sources = [str(Path(line).resolve(strict=True)) for line in args.sources.read_text().splitlines()]
for source in sources:
    if source not in manifest or source not in compiled:
        raise RuntimeError("综合源码未出现在实际仿真编译清单：" + source)
print("P1_FUNCTIONAL_GATE_PASSED", len(sources), result["source_manifest_sha256"])
