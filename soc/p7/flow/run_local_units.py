import argparse
import os
from pathlib import Path
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--suite', choices=('all', 'itcm', 'multiply', 'dot', 'icb'), default='all')
parser.add_argument('--official', type=Path)
parser.add_argument('--accel', type=Path)
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent
rtl, tb = project / 'rtl', project / 'tb'
output = project / 'work' / ('local_units_' + time.strftime('%Y%m%d_%H%M%S') + '_' + str(os.getpid()))
output.mkdir(parents=True, exist_ok=False)
environment = dict(os.environ)
environment.update({name: str(output) for name in ('TMPDIR', 'TMP', 'TEMP')})


def execute(top, sources, required, arguments=(), compile_options=(), label=None):
    for path in sources:
        if not path.is_file():
            raise FileNotFoundError(path)
    name = label or top
    binary = output / (name + '.vvp')
    with (output / (name + '_compile.log')).open('w') as log:
        subprocess.run(['iverilog', '-g2012', '-s', top, *compile_options,
                        '-o', str(binary), *map(str, sources)], env=environment,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    log_path = output / (name + '.log')
    with log_path.open('w') as log:
        subprocess.run(['vvp', str(binary), *arguments], env=environment,
                       stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    result = log_path.read_text()
    if required not in result:
        raise RuntimeError('组件测试没有完成规定检查：' + str(log_path))
    print(result, end='', flush=True)


if args.suite in ('all', 'itcm'):
    if args.official is None:
        parser.error('ITCM 测试需要 --official 指向公开 E203 rtl/e203 目录')
    official = args.official.resolve(strict=True)
    core, general = official / 'core', official / 'general'
    sources = [tb / 'tb_itcm_pipeline.sv', rtl / 'e203_itcm_ctrl.v',
               rtl / 'kwt_itcm_sram_icb_ctrl.sv', rtl / 'sirv_sram_icb_ctrl.v', core / 'e203_clkgate.v']
    sources += [general / name for name in ('sirv_gnrl_dffs.v', 'sirv_gnrl_bufs.v',
                                          'sirv_gnrl_icbs.v', 'sirv_sim_ram.v')]
    for seed in (20304007, 7919, 65537, 104729):
        execute('tb_itcm_pipeline', sources, 'ITCM_PIPELINE_PASS', ['+SEED=' + str(seed)],
                ['-DDISABLE_SV_ASSERTION', '-I', str(core)], 'itcm_' + str(seed))
if args.suite in ('all', 'multiply'):
    execute('tb_mul16_pipeline', [tb / 'tb_mul16_pipeline.sv', rtl / 'kwt_mul16_pipe.sv'],
            'MULTIPLY_PIPELINE_PASS checked=16449 aborted=2')
if args.suite in ('all', 'dot'):
    accel = (args.accel or project.parent.parent / 'v4.3').resolve(strict=True)
    execute('tb_kwt_stream_dot', [accel / 'tb/tb_kwt_stream_dot.sv', rtl / 'kwt_mul16_pipe.sv',
                                accel / 'rtl/kwt43_dot.sv', accel / 'rtl/kwt_quantize.sv'], 'ALL PASS, 64/64')
if args.suite in ('all', 'icb'):
    execute('tb_icb_registered', [tb / 'tb_icb_registered.sv', rtl / 'kwt43_icb_master.sv'],
            'ICB_REGISTERED_PASS completed=2000 aborted=2 zero=1000 delayed=1001')
print('LOCAL_UNIT_RUN_COMPLETED', str(output), flush=True)
