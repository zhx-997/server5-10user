import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
from path_config import load_paths

parser = argparse.ArgumentParser()
parser.add_argument('--synthesis', type=Path, required=True)
parser.add_argument('--candidate', type=Path, required=True)
parser.add_argument('--testbench', type=Path, required=True)
parser.add_argument('--paths', type=Path, default=Path(__file__).with_name('paths.tcl'))
parser.add_argument('--functional', action='store_true')
args = parser.parse_args()
paths = load_paths(args.paths)
candidate = args.candidate.resolve(strict=True)
synthesis = args.synthesis.resolve(strict=True)
testbench = args.testbench.resolve(strict=True)
result = json.loads((candidate/'verification_pass.json').read_text())
if result['passed'] is not True:
    raise RuntimeError('RTL 功能验证没有通过')
manifest = json.loads((candidate/'verified_inputs.json').read_text())
for name,digest in manifest.items():
    if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:
        raise RuntimeError('已验证输入发生变化：'+name)
models = [Path(name) for name in manifest if Path(name).suffix=='.v'
          and ('scc40' in Path(name).name.lower()
               or Path(name).name.startswith(('RAMSP','ROM1KX32','ROM2KX32')))]
if len([p for p in models if 'scc40' in p.name.lower()])!=1:
    raise RuntimeError('必须指定唯一 HVT 标准单元模型')
netlist = synthesis/'netlist/soc_mapped.v'
sdf = synthesis/'netlist/soc_mapped.sdf'
firmware = candidate/'firmware/firmware.hex'
output = synthesis/('gate_functional' if args.functional else 'sdf_soc_checks')
output.mkdir(exist_ok=False)
purposes = ['functional'] if args.functional else ['setup','hold']
records = []
for purpose in purposes:
    run = output/purpose
    scratch = run/'scratch'
    scratch.mkdir(parents=True)
    environment = dict(os.environ)
    environment.update({name:str(scratch) for name in ('TMPDIR','TMP','TEMP')})
    definitions = ['+define+GATE_LEVEL']
    if args.functional:
        definitions += ['+define+KWT_GATE_FUNCTIONAL+functional+ARM_UD_MODEL']
    else:
        if not sdf.is_file() or not sdf.stat().st_size:
            raise FileNotFoundError(sdf)
        shutil.copyfile(str(sdf),str(run/'soc.sdf'))
        if purpose=='hold':
            definitions += ['+define+KWT_SDF_MINIMUM']
    inputs = [testbench,netlist,firmware,*models]
    if not args.functional:
        inputs += [sdf]
    hashes = {str(p):hashlib.sha256(p.read_bytes()).hexdigest() for p in inputs}
    (run/'input_sha256.json').write_text(json.dumps(hashes,indent=2))
    command = [paths['VCS'],'-full64','-sverilog','-timescale=1ns/1ps',
               '-top','tb_soc_gate','+neg_tchk','-negdelay',*definitions,
               '+incdir+'+str(Path(paths['OFFICIAL'])/'core'),
               str(testbench),str(netlist),*map(str,models),'-o',str(run/'simv')]
    (run/'compile_command.json').write_text(json.dumps(command,indent=2))
    with (run/'compile.log').open('w') as log:
        subprocess.run(command,cwd=run,env=environment,stdin=subprocess.DEVNULL,
                       stdout=log,stderr=subprocess.STDOUT,check=True,timeout=1800)
    command = [str(run/'simv'),'+sdfverbose','+FIRMWARE='+str(firmware),'+VEC_DIR='+paths['VECTOR_PATH']]
    with (run/'simulation.log').open('w') as log:
        subprocess.run(command,cwd=run,env=environment,stdin=subprocess.DEVNULL,
                       stdout=log,stderr=subprocess.STDOUT,check=True,timeout=14400)
    text = (run/'simulation.log').read_text(errors='replace')
    if 'SOC_EXECUTION_ALL_PASS tasks=12 checked_words=58547 boots=2' not in text:
        raise RuntimeError('整机门级功能验证失败：'+purpose)
    if re.search(r'(?i)timing violation|Warning-\[SDF|Error-\[|Fatal:|\$setuphold.*violat',text):
        raise RuntimeError('出现标注或时序检查错误：'+str(run/'simulation.log'))
    for name,digest in hashes.items():
        if hashlib.sha256(Path(name).read_bytes()).hexdigest()!=digest:
            raise RuntimeError('仿真期间输入发生变化：'+name)
    records.append({'purpose':purpose,'passed':True,'timing_annotated':not args.functional,
                    'log_sha256':hashlib.sha256((run/'simulation.log').read_bytes()).hexdigest()})
    (output/'execution_records.json').write_text(json.dumps(records,indent=2))
    print('SOC_GATE_TEST_PASS',purpose,flush=True)
