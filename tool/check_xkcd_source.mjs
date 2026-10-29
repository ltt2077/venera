import assert from 'node:assert/strict';
import fs from 'node:fs';
import vm from 'node:vm';

const calls = [];
const context = vm.createContext({
  ComicSource: class {},
  ComicDetails: class { constructor(data) { Object.assign(this, data); } },
  Network: { get: async url => {
    calls.push(url);
    const id = Number(url.match(/xkcd.com\/(\d+)\//)?.[1] ?? 407);
    assert.notEqual(id, 404, 'the source must skip the missing comic');
    return { status: 200, body: JSON.stringify({
      num: id, title: `Comic ${id}`, safe_title: `Comic ${id}`,
      img: `https://imgs.xkcd.com/comics/${id}.png`,
      year: '2026', month: '10', day: '30', alt: 'Alt text', transcript: 'Transcript',
    }) };
  } },
});
const source = vm.runInContext(fs.readFileSync('comic_sources/xkcd.js', 'utf8') + '\nnew Xkcd()', context);
const first = await source.explore[0].load(1);
assert.deepEqual(Array.from(first.comics, c => c.id), ['407', '406', '405', '403']);
const second = await source.explore[0].load(2);
assert.deepEqual(Array.from(second.comics, c => c.id), ['402', '401', '400', '399']);
assert.equal(first.maxPage, 102);
const before = calls.length;
assert.equal((await source.search.load('403', [], 1)).comics[0].id, '403');
assert.equal(calls.length, before, 'cached comics avoid repeat network requests');
assert.equal((await source.search.load('404', [], 1)).comics.length, 0);
assert.equal((await source.search.load('not numeric', [], 1)).comics.length, 0);
assert.equal((await source.search.load('403', [], 2)).comics.length, 0);
const details = await source.comic.loadInfo('403');
assert.equal(details.description, 'Alt text\n\nTranscript');
assert.equal(details.url, 'https://xkcd.com/403/');
assert.equal((await source.comic.loadEp('403', null)).images[0], 'https://imgs.xkcd.com/comics/403.png');
console.log('xkcd browsing, pagination, search, details, images, missing #404, and cache checks passed');

if (process.argv.includes('--live')) {
  const liveContext = vm.createContext({
    ComicSource: class {},
    ComicDetails: class { constructor(data) { Object.assign(this, data); } },
    Network: { get: async url => {
      const response = await fetch(url, { signal: AbortSignal.timeout(15000) });
      return { status: response.status, body: await response.text() };
    } },
  });
  const live = vm.runInContext(fs.readFileSync('comic_sources/xkcd.js', 'utf8') + '\nnew Xkcd()', liveContext);
  const recent = await live.explore[0].load(1);
  assert.equal(recent.comics.length, 4);
  const search = await live.search.load('614', [], 1);
  assert.equal(search.comics[0].id, '614');
  const details = await live.comic.loadInfo('614');
  const chapter = await live.comic.loadEp('614', null);
  assert.equal(chapter.images[0], details.cover);
  const image = await fetch(chapter.images[0], { signal: AbortSignal.timeout(15000) });
  assert.equal(image.status, 200);
  assert.ok((await image.arrayBuffer()).byteLength > 1000);
  console.log('Live xkcd latest page, #614 search/details/reading image download passed');
}
