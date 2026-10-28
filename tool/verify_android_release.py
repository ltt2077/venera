"""Verify every APK's identity, version and signing certificate before release."""
import hashlib
import json
import os
import re
import shutil
import subprocess
from pathlib import Path


def main():
    spec = json.loads(Path('tool/android_release.json').read_text())
    tools = Path(os.environ['ANDROID_HOME']) / 'build-tools'
    versions = sorted(tools.iterdir(), key=lambda p: tuple(
        int(n) for n in re.findall(r'\d+', p.name)))
    signer = next((p / 'apksigner' for p in reversed(versions)
                   if (p / 'apksigner').is_file()), None)
    aapt = next((p / 'aapt' for p in reversed(versions)
                if (p / 'aapt').is_file()), None)
    if not signer or not aapt:
        raise SystemExit('Android apksigner/aapt tools are missing')
    source = Path('build/app/outputs/apk/release')
    output = Path('dist')
    output.mkdir(exist_ok=True)
    checksums = []
    for abi, abi_code in [('arm64-v8a', 2), ('armeabi-v7a', 1), ('x86_64', 3), ('universal', 0)]:
        suffix = '' if abi == 'universal' else '-' + abi
        apk = source / ('venera-' + spec['version'] + suffix + '.apk')
        if not apk.is_file():
            raise SystemExit('Missing APK: ' + apk.name)
        certs = subprocess.check_output([str(signer), 'verify', '--verbose', '--print-certs', str(apk)], text=True)
        fingerprints = re.findall(r'Signer #\d+ certificate SHA-256 digest:\s*([0-9a-fA-F]+)', certs)
        if not fingerprints or {value.lower() for value in fingerprints} != {spec['certificate_sha256']}:
            raise SystemExit('Signing identity differs from 1.7.6; refusing to publish ' + apk.name)
        badging = subprocess.check_output([str(aapt), 'dump', 'badging', str(apk)], text=True)
        package = re.search(r"package: name='([^']+)' versionCode='(\d+)' versionName='([^']+)'", badging)
        expected_code = spec['build'] * 10 + abi_code
        if not package or (package[1], int(package[2]), package[3]) != (spec['application_id'], expected_code, spec['version']):
            raise SystemExit('APK package/version mismatch: ' + apk.name)
        target = output / ('venera-' + spec['version'] + '-' + abi + '.apk')
        shutil.copy2(apk, target)
        checksums.append(hashlib.sha256(target.read_bytes()).hexdigest() + '  ' + target.name)
        print('Verified', target.name, 'versionCode=' + str(expected_code), 'original signing identity')
    (output / 'SHA256SUMS.txt').write_text('\n'.join(checksums) + '\n')
    (output / 'signing-certificate-sha256.txt').write_text(spec['certificate_sha256'] + '\n')


if __name__ == '__main__':
    main()
