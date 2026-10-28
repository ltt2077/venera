"""Use the existing release identity without exposing signing credentials."""
import base64
import os
import re
from pathlib import Path


def main():
    names = ('ANDROID_KEYSTORE', 'ANDROID_KEY_PROPERTIES')
    missing = [name for name in names if not os.environ.get(name, '').strip()]
    if missing:
        raise SystemExit('Missing repository signing secrets: ' + ', '.join(missing)
                         + '. Configure the original 1.7.6 signing key; do not generate a replacement.')
    encoded = ''.join(os.environ['ANDROID_KEYSTORE'].split())
    key = base64.b64decode(encoded, validate=True)
    props = os.environ['ANDROID_KEY_PROPERTIES']
    for field in ('storePassword', 'keyPassword', 'keyAlias'):
        if not re.search(r'^\s*' + field + r'\s*[=:]\s*\S+', props, re.M):
            raise SystemExit('Signing properties are missing ' + field)
    keyfile = Path(os.environ['RUNNER_TEMP']) / 'venera-release.jks'
    keyfile.write_bytes(key)
    keyfile.chmod(0o600)
    lines = [line for line in props.splitlines()
             if not re.match(r'^\s*storeFile\s*[=:]', line)]
    lines.append('storeFile=' + keyfile.as_posix())
    config = Path('android/key.properties')
    config.write_text('\n'.join(lines) + '\n')
    config.chmod(0o600)
    print('Original signing credentials configured (values are hidden).')


if __name__ == '__main__':
    main()
