"""Verify the four platform packages and publish them together."""

import argparse
import hashlib
import json
import os
import subprocess
import zipfile
from pathlib import Path


def verify_packages(spec, source, directory):
    version = spec['version']
    names = [
        *(f'venera-{version}-{abi}.apk'
          for abi in ('arm64-v8a', 'armeabi-v7a', 'x86_64', 'universal')),
        f'venera-{version}-ios-unsigned.ipa',
        f'venera-{version}-macos-universal.dmg',
        f'venera-{version}-macos-universal.zip',
        f'venera-{version}-windows-x64-setup.exe',
        f'venera-{version}-windows-x64.zip',
    ]
    hashes = {}
    for name in names:
        path = directory / name
        if not path.is_file() or path.stat().st_size < 100_000:
            raise ValueError(f'Missing or incomplete package: {name}')
        if path.suffix in ('.zip', '.ipa', '.apk'):
            with zipfile.ZipFile(path) as archive:
                if archive.testzip() is not None:
                    raise ValueError(f'Damaged archive: {name}')
        hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest()

    ios = json.loads((directory / 'BUILD-INFO-ios.txt').read_text())
    if (ios['source_commit'], ios['version'], int(ios['build']), ios['sha256']) != (
        source, version, spec['build'], hashes[f'venera-{version}-ios-unsigned.ipa'],
    ):
        raise ValueError('iOS build provenance does not match')
    expected_info = (f'Source commit: {source}', f"Version: {version}+{spec['build']}")
    for platform in ('android', 'macos', 'windows'):
        info = (directory / f'BUILD-INFO-{platform}.txt').read_text().splitlines()
        if not all(line in info for line in expected_info):
            raise ValueError(f'{platform} build provenance does not match')
    certificate = (directory / 'signing-certificate-sha256.txt').read_text().strip()
    if certificate != spec['certificate_sha256']:
        raise ValueError('Android signing certificate does not match')
    (directory / 'SHA256SUMS.txt').write_text(''.join(
        f'{digest}  {name}\n' for name, digest in sorted(hashes.items())
    ))
    print(f'Verified {len(names)} packages from {source}')


def publish(spec, source, directory):
    tag = spec['release']
    repo = os.environ['GITHUB_REPOSITORY']

    def gh(*args, check=True):
        return subprocess.run(
            ['gh', 'release', *args, '--repo', repo],
            check=check, stdout=subprocess.PIPE, text=True,
        )

    def api(*args):
        return json.loads(subprocess.check_output(['gh', 'api', *args], text=True))

    branch = os.environ['GITHUB_REF_NAME']
    if branch == 'codex/v1.7.10-maintenance':
        if spec['version'] != '1.7.10':
            raise ValueError('Unexpected version on the 1.7.10 branch')
        head = api(f'repos/{repo}/git/ref/heads/{branch}')['object']['sha']
        if head != source:
            raise ValueError('A newer maintenance commit exists')
        current = api(f'repos/{repo}/git/ref/heads/glass-cloud')['object']['sha']
        if current != source:
            # GitHub checks ancestry atomically when force is false.
            api('--method', 'PATCH', f'repos/{repo}/git/refs/heads/glass-cloud',
                '-f', f'sha={source}', '-F', 'force=false')
    elif branch != 'glass-cloud':
        raise ValueError(f'Unexpected release branch: {branch}')

    existing = gh('view', tag, '--json', 'isDraft,targetCommitish', check=False)
    if existing.returncode == 0:
        release = json.loads(existing.stdout)
        if not release['isDraft']:
            raise ValueError(f'{tag} is already public')
        if release['targetCommitish'] != source:
            raise ValueError(f'{tag} has a draft for a different commit')
    else:
        gh('create', tag, '--draft', '--target', source,
           '--title', f"Venera Glass {spec['version']}",
           '--notes-file', 'tool/release_notes_1.7.10.md')

    files = sorted(p for p in directory.iterdir() if p.is_file())
    gh('upload', tag, *(str(p) for p in files), '--clobber')
    uploaded = json.loads(gh('view', tag, '--json', 'assets').stdout)['assets']
    sizes = {asset['name']: asset['size'] for asset in uploaded}
    if sizes != {p.name: p.stat().st_size for p in files}:
        raise ValueError('Release assets do not match the verified build')
    gh('edit', tag, '--draft=false', '--latest')
    print(f'Published {tag} with {len(files)} assets')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--publish', action='store_true')
    args = parser.parse_args()
    spec = json.loads(Path('tool/desktop_release.json').read_text())
    source = os.environ['GITHUB_SHA']
    directory = Path('dist')
    verify_packages(spec, source, directory)
    if args.publish:
        publish(spec, source, directory)


if __name__ == '__main__':
    main()
