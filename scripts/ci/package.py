#!/usr/bin/env python3
"""Package checked build output, checksums and the release manifest."""
import argparse
import hashlib
import json
import shutil
import zipfile
from pathlib import Path

parser = argparse.ArgumentParser()
parser.add_argument('platform', choices=['android', 'windows', 'manifest'])
parser.add_argument('--version', required=True)
parser.add_argument('--build', required=True, type=int)
args = parser.parse_args()
out = Path('artifacts')
out.mkdir(exist_ok=True)
prefix = f'VocabApp-{args.version}'
if args.platform == 'android':
    shutil.copy2('app/build/app/outputs/flutter-apk/app-release.apk', out / f'{prefix}-android-arm64.apk')
elif args.platform == 'windows':
    source = Path('app/build/windows/x64/runner/Release')
    for required in ['vocabapp.exe', 'flutter_windows.dll', 'sqlite3.dll', 'data/icudtl.dat', 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll']:
        if not (source / required).is_file():
            raise SystemExit(f'Missing Windows runtime: {required}')
    with zipfile.ZipFile(out / f'{prefix}-windows-x64.zip', 'w', zipfile.ZIP_DEFLATED) as archive:
        for file in sorted(source.rglob('*')):
            if file.is_file():
                archive.write(file, file.relative_to(source).as_posix())
else:
    files = [out / f'{prefix}-android-arm64.apk', out / f'{prefix}-windows-x64.zip', out / f'{prefix}-Setup.exe']
    assets = {}
    for file in files:
        with file.open('rb') as stream:
            digest = hashlib.file_digest(stream, 'sha256').hexdigest()
        (out / f'{file.name}.sha256').write_text(f'{digest}  {file.name}\n')
        assets['android-arm64' if file.suffix == '.apk' else 'windows-installer' if file.suffix == '.exe' else 'windows-x64'] = {
            'name': file.name, 'sha256': digest, 'size': file.stat().st_size,
            'url': f'https://github.com/chimsedibui/vocabapp/releases/download/v{args.version}/{file.name}',
        }
    (out / 'release.json').write_text(json.dumps({
        'version': args.version, 'build': args.build, 'assets': assets,
        'notes_url': f'https://github.com/chimsedibui/vocabapp/releases/tag/v{args.version}',
    }, indent=2) + '\n')
