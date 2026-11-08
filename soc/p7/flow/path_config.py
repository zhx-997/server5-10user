from pathlib import Path, PurePosixPath
import subprocess


def load_paths(config):
    config = config.resolve(strict=True)
    process = subprocess.run(
        ["tclsh", str(Path(__file__).with_name("emit_paths.tcl")), str(config)],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
    fields = process.stdout.decode("utf-8").split("\0")
    if fields.pop() != "" or len(fields) % 2:
        raise RuntimeError("Tcl 路径配置输出不完整")
    values = dict(zip(fields[::2], fields[1::2]))
    return values


def relocate_manifest(manifest, config):
    relocated = {}
    for name, digest in manifest.items():
        source = PurePosixPath(name)
        matches = []
        for index in range(int(config["REMAP_COUNT"])):
            old = PurePosixPath(config["REMAP_OLD_" + str(index)])
            if source == old or old in source.parents:
                matches.append(Path(config["REMAP_NEW_" + str(index)]) / source.relative_to(old))
        if len(matches) > 1:
            raise RuntimeError("验证记录的路径迁移规则重叠：" + name)
        actual = str((matches[0] if matches else Path(name)).resolve(strict=True))
        if actual in relocated:
            raise RuntimeError("验证记录出现重复目标文件：" + actual)
        relocated[actual] = digest
    return relocated
