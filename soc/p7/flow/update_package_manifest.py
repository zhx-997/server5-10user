import argparse
import hashlib
import json
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
root = Path(__file__).resolve().parent.parent
files = [root / name for name in ('README.md', 'HANDOFF.txt', 'AGENTS.md', '.gitignore', '.gitattributes')]
for directory in ('rtl', 'tb', 'firmware', 'reference', 'flow', 'results'):
    files += [path for path in (root / directory).rglob('*') if path.is_file()
              and '__pycache__' not in path.parts and path.suffix not in ('.pyc', '.pyo')
              and path != root / 'results/source_sha256.json']
hashes = {path.relative_to(root).as_posix(): hashlib.sha256(path.read_bytes()).hexdigest()
          for path in sorted(files)}
package = {name: digest for name, digest in hashes.items() if name != 'flow/paths.tcl'}
for name, expected in (('package_manifest.json', package), ('results/source_sha256.json', hashes)):
    path = root / name
    if args.check:
        if json.loads(path.read_text(encoding='utf-8')) != expected:
            raise RuntimeError('交付清单与实际文件不一致：' + name)
    else:
        path.write_text(json.dumps(expected, indent=2) + '\n', encoding='utf-8')
print('PACKAGE_MANIFEST_CHECKED' if args.check else 'PACKAGE_MANIFEST_WRITTEN', len(hashes))
