"""Package the existing version with a clean SideStore-compatible archive."""
import hashlib
import json
import os
import plistlib
import stat
import zipfile
from pathlib import Path


def main():
    app = Path('build/ios/iphoneos/Runner.app')
    info = plistlib.loads((app / 'Info.plist').read_bytes())
    assert info['CFBundleShortVersionString'] == '1.7.9'
    assert str(info['CFBundleVersion']) == '180'
    assert info['CFBundleIdentifier'] == 'com.github.wgh136.venera'
    assert info['VeneraNativeUIRevision'] == 'ios-179-system-controls-1'
    assert int(info['DTSDKName'].replace('iphoneos', '').split('.')[0]) >= 26
    assert info.get('UIDesignRequiresCompatibility') is not True
    binary = (app / info['CFBundleExecutable']).read_bytes()
    for marker in (b'VeneraNativeChromeController', b'VeneraNativeChromeHost', b'venera/native_dock'):
        assert marker in binary, 'Missing compiled native UI: ' + marker.decode()
    dist = Path('dist')
    dist.mkdir(exist_ok=True)
    target = dist / 'venera-1.7.9-ios-unsigned.ipa'
    with zipfile.ZipFile(target, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for path in sorted(app.rglob('*')):
            if any(p == '__MACOSX' or p == '.DS_Store' or p.startswith('._') for p in path.parts):
                continue
            if path.is_dir() and not path.is_symlink():
                continue
            name = 'Payload/Runner.app/' + path.relative_to(app).as_posix()
            if path.is_symlink():
                entry = zipfile.ZipInfo(name)
                entry.create_system = 3
                entry.external_attr = (stat.S_IFLNK | 0o777) << 16
                archive.writestr(entry, os.readlink(path))
            else:
                archive.write(path, name)
    with zipfile.ZipFile(target) as archive:
        assert archive.testzip() is None
        assert all(name.startswith('Payload/Runner.app/') for name in archive.namelist())
        assert all(not entry.extra for entry in archive.infolist())
        assert 'Payload/Runner.app/Info.plist' in archive.namelist()
    sha = hashlib.sha256(target.read_bytes()).hexdigest()
    (dist / 'SHA256-ios-native-ui.txt').write_text(f'{sha}  {target.name}\n')
    provenance = {
        'source_commit': os.environ['GITHUB_SHA'],
        'version': '1.7.9', 'build': '180',
        'bundle_id': info['CFBundleIdentifier'],
        'native_ui_revision': info['VeneraNativeUIRevision'],
        'sdk': info['DTSDKName'], 'xcode': info['DTXcode'],
        'native_controls': ['UITabBarController', 'UINavigationBar', 'UIBarButtonItem'],
        'signing': 'Unsigned; sign with your own Apple identity for installation.',
        'packaging': 'Single Payload/Runner.app; no AppleDouble, __MACOSX, or ZIP extra fields.',
        'sha256': sha,
    }
    (dist / 'BUILD-INFO-ios.txt').write_text(json.dumps(provenance, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(provenance, ensure_ascii=False))


if __name__ == '__main__':
    main()
