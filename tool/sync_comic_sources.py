"""Merge upstream catalog metadata with optional Glass sources; no script copies."""
import argparse
import json
import re
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen

UPSTREAM = 'https://raw.githubusercontent.com/venera-app/venera-configs/main/index.json'
ROOT = Path(__file__).resolve().parents[1]


def merge(upstream):
    if not isinstance(upstream, list) or not upstream:
        raise ValueError('Expected a nonempty upstream source list')
    result = []
    seen = set()
    for row in upstream:
        if not isinstance(row, dict):
            raise ValueError('Invalid upstream catalog entry')
        entry = {key: row[key] for key in ('name', 'key', 'version')}
        if any(not isinstance(value, str) or not value for value in entry.values()):
            raise ValueError('Invalid source metadata')
        location = row.get('url') or row.get('fileName') or row.get('filename')
        entry['url'] = urljoin(UPSTREAM, location)
        if urlparse(entry['url']).scheme != 'https':
            raise ValueError('Expected HTTPS script URL')
        if isinstance(row.get('description'), str):
            entry['description'] = row['description']
        if entry['key'] in seen:
            raise ValueError('Duplicate source key')
        seen.add(entry['key'])
        result.append(entry)
    if 'xkcd' in seen:
        raise ValueError('Upstream now includes xkcd; review the duplicate')
    script = (ROOT / 'comic_sources/xkcd.js').read_text()
    version = re.search(r'^\s*version\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"', script, re.M)
    if not version:
        raise ValueError('Missing xkcd script version')
    result.append({
        'name': 'xkcd', 'key': 'xkcd', 'version': version[1],
        'url': 'https://raw.githubusercontent.com/ltt2077/venera/glass-cloud/comic_sources/xkcd.js',
        'description': 'Official JSON API. English comics; search by number. 官方接口，英文漫画，支持按编号搜索。',
    })
    return result


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--upstream-file', type=Path)
    args = parser.parse_args()
    if args.upstream_file:
        data = json.loads(args.upstream_file.read_text())
    else:
        request = Request(UPSTREAM, headers={'User-Agent': 'Venera-Glass-catalog'})
        with urlopen(request, timeout=30) as response:
            data = json.load(response)
    output = ROOT / 'comic_sources/index.json'
    output.write_text(json.dumps(merge(data), ensure_ascii=False, indent=2) + '\n')
    print('Updated source catalog metadata')


if __name__ == '__main__':
    main()
