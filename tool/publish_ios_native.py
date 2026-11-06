"""Publish only the verified iOS repair, preserving the other platform assets."""
import hashlib
import json
import os
import re
import subprocess
from pathlib import Path
from urllib.request import urlopen


def gh(*args):
    return subprocess.check_output(['gh', *args], text=True)


def main():
    repo = os.environ['GITHUB_REPOSITORY']
    commit = os.environ.get('REPAIR_SOURCE_COMMIT', os.environ['GITHUB_SHA'])
    feature = 'codex/ios-1.7.9-native-glass'
    source = json.loads(gh('api', f'repos/{repo}/branches/{feature}'))['commit']['sha']
    assert source == commit, 'A newer repair commit exists'
    release = json.loads(gh('api', f'repos/{repo}/releases/tags/v1.7.9-glass'))
    assert not release['draft'], 'Expected the published 1.7.9 release'
    dist = Path('dist')
    ipa = dist / 'venera-1.7.9-ios-unsigned.ipa'
    provenance = json.loads((dist / 'BUILD-INFO-ios.txt').read_text())
    assert provenance['source_commit'] == commit
    digest = hashlib.sha256(ipa.read_bytes()).hexdigest()
    assert digest == provenance['sha256']
    # Keep previously published checksum files consistent with the replaced IPA.
    for asset in release['assets']:
        if not asset['name'].startswith('SHA256') or not asset['name'].endswith('.txt'):
            continue
        with urlopen(asset['browser_download_url'], timeout=30) as response:
            text = response.read().decode()
        changed = False
        lines = []
        for line in text.splitlines():
            match = re.fullmatch(r'[0-9a-fA-F]{64}\s+\*?(.*)', line)
            if match and Path(match[1]).name == ipa.name:
                line = f'{digest}  {ipa.name}'
                changed = True
            lines.append(line)
        if changed:
            (dist / asset['name']).write_text('\n'.join(lines) + '\n')
    current = json.loads(gh('api', f'repos/{repo}/branches/glass-cloud'))['commit']['sha']
    if current != commit:
        comparison = json.loads(gh('api', f'repos/{repo}/compare/{current}...{commit}'))
        assert comparison['status'] == 'ahead', 'Application branch changed; review before publishing'
        gh('api', '--method', 'PATCH', f'repos/{repo}/git/refs/heads/glass-cloud', '-f', f'sha={commit}', '-F', 'force=false')
    files = sorted(str(path) for path in dist.iterdir() if path.is_file())
    gh('release', 'upload', 'v1.7.9-glass', *files, '--repo', repo, '--clobber')
    marker = '\n\n### iOS 1.7.9 native UI repair\n'
    notes = release['body'].split(marker)[0] + marker + (
        f'Source: `{commit}`; revision `{provenance["native_ui_revision"]}`. '
        'Version/build remain **1.7.9 (180)** and the bundle identifier is unchanged.\n\n'
        '- Real system UITabBarController, UINavigationBar and UIBarButtonItem controls on iOS 26+.\n'
        '- Restored native glass surfaces; removed material-flattening masks and redundant per-build control creation.\n'
        '- Native chrome follows Flutter navigation, modal dialogs, keyboard and application visibility.\n'
        '- Flutter regression tests and iOS simulator UIKit/runtime checks passed. Hardware FPS/power was not profiled.\n'
        '- Unsigned IPA for user signing, packaged without AppleDouble files or ZIP extra fields.\n'
        '- Download the replaced `venera-1.7.9-ios-unsigned.ipa`; checksum and BUILD-INFO identify this revision.\n'
    )
    Path('ios-repair-notes.md').write_text(notes)
    gh('release', 'edit', 'v1.7.9-glass', '--repo', repo, '--notes-file', 'ios-repair-notes.md')
    print('Published iOS native UI repair:', digest)


if __name__ == '__main__':
    main()
