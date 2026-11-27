"""Reconstruct signed APKs using verified compile-only inputs and public signatures."""
import base64
import hashlib
import json
import re
import sys
import zlib
from pathlib import Path


def sha(data):
    return hashlib.sha256(data).hexdigest()


def main():
    patch_dir, compiled, outputs = (Path(arg) for arg in sys.argv[1:])
    encoded = ''.join(part.read_text() for part in sorted(patch_dir.glob('part-*.txt')))
    plan = json.loads(zlib.decompress(base64.b64decode(encoded, validate=True)))
    if len(plan) != 4:
        raise ValueError('Expected four original signing results')
    outputs.mkdir(parents=True, exist_ok=True)
    for name, patch in plan.items():
        if not re.fullmatch(r'venera-1\.7\.10(?:-arm64-v8a|-armeabi-v7a|-x86_64)?\.apk', name):
            raise ValueError(f'Unexpected APK name: {name}')
        original = (compiled / name).read_bytes()
        if sha(original) != patch['input_sha256']:
            raise ValueError(f'APK build digest mismatch: {name}')
        parts = []
        for entry in patch['copy_and_insert']:
            if isinstance(entry, str):
                parts.append(base64.b64decode(entry, validate=True))
            else:
                start, length = entry
                if start < 0 or length < 0 or start + length > len(original):
                    raise ValueError(f'Invalid APK patch segment: {name}')
                parts.append(original[start:start + length])
        data = b''.join(parts)
        if sha(data) != patch['signed_sha256']:
            raise ValueError(f'Signed APK digest mismatch: {name}')
        (outputs / name).write_bytes(data)
        print(f'Reconstructed signed package {name}')


if __name__ == '__main__':
    main()
