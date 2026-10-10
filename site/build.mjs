// Builds the website into site/dist (served by the Worker in src/worker.js).
//
// Needs, from the repo root: vce.tns and vce_zh.tns (npm run build:vce,
// npm run build:vce-zh), Lua 5.4 or 5.1 (LUA=...), and npm ci in the root and
// in site/. Run: node site/build.mjs
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const SITE = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(SITE, '..');
const DIST = path.join(SITE, 'dist');
const PUBLIC = path.join(SITE, 'public');

function lua() {
  for (const cmd of [process.env.LUA, 'lua5.4', 'lua', 'lua5.1'].filter(Boolean)) {
    try {
      execFileSync(cmd, ['-v'], { stdio: 'ignore' });
      return cmd;
    } catch {
      // try the next one
    }
  }
  throw new Error('Lua not found: set LUA=/path/to/lua');
}

function copyDir(from, to) {
  fs.mkdirSync(to, { recursive: true });
  for (const e of fs.readdirSync(from, { withFileTypes: true })) {
    const a = path.join(from, e.name);
    const b = path.join(to, e.name);
    if (e.isDirectory()) copyDir(a, b);
    else fs.copyFileSync(a, b);
  }
}

const sha256 = (buf) => createHash('sha256').update(buf).digest('hex');
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');

fs.rmSync(DIST, { recursive: true, force: true });
copyDir(PUBLIC, DIST);

// The toolkit for the browser demo: real app + mock CAS + exact example answers
fs.mkdirSync(path.join(DIST, 'emu'), { recursive: true });
// (served as .txt: text/plain is compressed on the way)
execFileSync(path.join(ROOT, 'node_modules/.bin/luabundler'),
  ['bundle', 'site/emu/web.lua', '-p', './?.lua', '-o', 'site/dist/emu/vce_web.txt'], { cwd: ROOT, stdio: 'inherit' });
fs.renameSync(path.join(DIST, 'emu/host.lua'), path.join(DIST, 'emu/host.txt'));

// Lua in WebAssembly
fs.mkdirSync(path.join(DIST, 'vendor'), { recursive: true });
for (const f of ['index.js', 'glue.wasm']) {
  fs.copyFileSync(path.join(SITE, 'node_modules/wasmoon/dist', f), path.join(DIST, 'vendor', f === 'index.js' ? 'wasmoon.js' : f));
}

// Topics, version and downloads
const features = JSON.parse(execFileSync(lua(), ['site/tools/features.lua'], { cwd: ROOT, encoding: 'utf8' }));
const version = features.version;
const changelog = JSON.parse(fs.readFileSync(path.join(SITE, 'changelog.json'), 'utf8'));
if (!changelog.length || changelog[0].version !== version) {
  throw new Error(`site/changelog.json must start with version ${version} (apps/vce/version.lua)`);
}

const downloads = path.join(DIST, 'downloads');
fs.mkdirSync(downloads, { recursive: true });
const files = {};
for (const [key, name] of [['en', 'vce'], ['zh', 'vce_zh']]) {
  const src = path.join(ROOT, name + '.tns');
  if (!fs.existsSync(src)) throw new Error(`${name}.tns is missing: run npm run build:vce and build:vce-zh first`);
  const buf = fs.readFileSync(src);
  fs.writeFileSync(path.join(downloads, `${name}.tns`), buf);
  fs.writeFileSync(path.join(downloads, `${name}-${version}.tns`), buf);
  files[key] = { file: `${name}.tns`, url: `/downloads/${name}.tns`, versioned: `/downloads/${name}-${version}.tns`, size: buf.length, sha256: sha256(buf) };
}

// Source code (GPL-3.0): the repository at this commit, without the videos
let commit = '';
try {
  commit = execFileSync('git', ['rev-parse', '--short', 'HEAD'], { cwd: ROOT, encoding: 'utf8' }).trim();
  execFileSync('git', ['archive', '--format=tar.gz', `--prefix=vce-toolkit-${version}/`, '-o', path.join(downloads, `vce-toolkit-${version}-source.tar.gz`),
    'HEAD', '--', '.', ':(exclude)doc/*.mp4', ':(exclude)doc/*.gif'], { cwd: ROOT });
  files.source = { file: `vce-toolkit-${version}-source.tar.gz`, url: `/downloads/vce-toolkit-${version}-source.tar.gz` };
} catch (e) {
  console.warn('no source archive (not a git checkout?)', e.message);
}
fs.copyFileSync(path.join(ROOT, 'LICENSE'), path.join(DIST, 'LICENSE.txt'));

const date = changelog[0].date;
const info = { version, date, commit, files, changelog };
fs.writeFileSync(path.join(DIST, 'version.json'), JSON.stringify(info, null, 2));
fs.writeFileSync(path.join(DIST, 'features.json'), JSON.stringify(features));

// Fill the page: topics, changelog, version, sizes; cache-busting stamp
const stamp = sha256(JSON.stringify(info) + fs.readFileSync(path.join(DIST, 'emu/vce_web.txt'), 'utf8') +
  ['assets/site.js', 'assets/nspire-usb.js', 'assets/site.css', 'assets/tutorials.js', 'assets/timath.js', 'emu/emulator.js', 'emu/core.js', 'emu/host.txt']
    .map((f) => fs.readFileSync(path.join(DIST, f), 'utf8')).join('')).slice(0, 10);

const both = (zh, en) => `<span lang="zh">${zh}</span><span lang="en">${en}</span>`;
const badge = (c) => `<span class="badge ${c.toLowerCase()}" title="${c === 'MM' ? 'Mathematical Methods' : 'Specialist Mathematics'}">${c}</span>`;

function topicCard(t, i) {
  const members = (t.members || []).map((m) =>
    `<li>${m.course.map(badge).join('')} ${both(esc(m.zh.title || m.title), esc(m.title))}</li>`).join('');
  return `<li class="topic" id="topic-${esc(t.id)}">
  <div class="topic-head"><span class="topic-num" aria-hidden="true">${(i + 1) % 10}</span>
  <h3>${both(esc(t.zh.short || t.short), esc(t.short))}</h3><span class="badges">${t.course.map(badge).join('')}</span></div>
  <p class="topic-blurb">${both(esc(t.zh.blurb || t.blurb), esc(t.blurb))}</p>
  ${members ? `<ul class="members">${members}</ul>` : ''}
</li>`;
}

function changelogHtml() {
  return changelog.map((c) => `<li><h4>v${esc(c.version)} <time datetime="${esc(c.date)}">${esc(c.date)}</time></h4>
<ul>${c.zh.map((z, k) => `<li>${both(esc(z), esc(c.en[k] || ''))}</li>`).join('')}</ul></li>`).join('\n');
}

const kb = (n) => (n / 1024).toFixed(0) + ' KB';
const fill = {
  '{{VERSION}}': esc(version),
  '{{DATE}}': esc(date),
  '{{STAMP}}': stamp,
  '{{SIZE_EN}}': kb(files.en.size),
  '{{SIZE_ZH}}': kb(files.zh.size),
  '{{SHA_EN}}': files.en.sha256,
  '{{SHA_ZH}}': files.zh.sha256,
  '{{SOURCE_URL}}': files.source ? files.source.url : '/LICENSE.txt',
  '<!--TOPICS-->': features.topics.map(topicCard).join('\n'),
  '<!--CHANGELOG-->': changelogHtml(),
};
for (const page of ['index.html', 'admin.html']) {
  const p = path.join(DIST, page);
  let html = fs.readFileSync(p, 'utf8');
  for (const [k, v] of Object.entries(fill)) html = html.split(k).join(v);
  fs.writeFileSync(p, html);
}

console.log(`site built: v${version} (${commit}), stamp ${stamp}, en ${kb(files.en.size)}, zh ${kb(files.zh.size)}`);
