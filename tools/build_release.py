"""Verify the committed package and build its shareable Windows ZIP."""
from pathlib import Path
import hashlib
import json
import zipfile

root = Path(__file__).resolve().parents[1]
manifest = json.loads((root / 'SHA256.json').read_text(encoding='utf-8'))
for relative, expected in manifest.items():
    path = root / relative
    if path.resolve().is_relative_to(root) is False:
        raise SystemExit(f'Invalid manifest path: {relative}')
    if hashlib.sha256(path.read_bytes()).hexdigest().upper() != expected:
        raise SystemExit(f'Hash mismatch: {relative}')

names = set(manifest) | {'README.txt', 'SOURCES.txt', 'LICENSE'}
names.update(path.relative_to(root).as_posix() for path in (root / 'licenses').rglob('*') if path.is_file())
out = root / 'dist' / 'PUBG-Discord-Zapret-Windows.zip'
out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
    for name in sorted(names):
        archive.write(root / name, 'PUBG-Discord-Zapret/' + name)
with zipfile.ZipFile(out) as archive:
    if archive.testzip() is not None:
        raise SystemExit('ZIP integrity verification failed')
print(out)
print('SHA256:', hashlib.sha256(out.read_bytes()).hexdigest())
