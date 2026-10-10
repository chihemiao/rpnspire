// Plays every tutorial on the website through the browser demo stack
// (wasmoon + public/emu/host.lua + dist/emu/vce_web.txt) and checks the
// toolkit's answers, in English and in the bilingual edition. Also checks
// that each CAS entry on the page can be pretty-printed. Run after the
// build: node site/test/emu.test.mjs
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const SITE = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const { LuaFactory } = require(path.join(SITE, 'node_modules/wasmoon'));
const NspireCore = require(path.join(SITE, 'public/emu/core.js'));
const TUTORIALS = require(path.join(SITE, 'public/assets/tutorials.js'));
const TIMath = require(path.join(SITE, 'public/assets/timath.js'));

const sources = {
  host: fs.readFileSync(path.join(SITE, 'public/emu/host.lua'), 'utf8'),
  app: fs.readFileSync(path.join(SITE, 'dist/emu/vce_web.txt'), 'utf8'),
};
const factory = new LuaFactory();

let failures = 0;
async function test(name, fn) {
  try {
    await fn();
    console.log('ok  ', name);
  } catch (e) {
    failures++;
    console.log('FAIL', name);
    console.log(e && e.stack ? e.stack : e);
  }
}

async function boot(lang) {
  const printed = [];
  const core = new NspireCore(factory, sources, { lang });
  const buf = await core.boot();
  return { core, buf, printed };
}

function play(core, script) {
  let last = null;
  for (const [name, arg] of NspireCore.parseScript(script)) {
    const res = core.event(name, arg);
    if (res !== null) last = res;
  }
  return last;
}

for (const lang of ['en', 'bi']) {
  await test(`home screen paints (${lang})`, async () => {
    const { core, buf } = await boot(lang);
    assert.equal(core.screen(), 'home');
    assert.ok(buf.includes(lang === 'bi' ? 'VCE 数学工具箱' : 'VCE Maths'), 'title drawn');
    const menu = core.menu();
    assert.ok(menu.length >= 5, 'toolpalette registered');
    assert.ok(menu.some((m) => m.items.length > 5), 'menu items');
    core.close();
  });

  for (const t of TUTORIALS) {
    await test(`tutorial ${t.id} (${lang})`, async () => {
      const { core } = await boot(lang);
      for (const step of t.app) {
        const buf = play(core, step.keys);
        assert.ok(buf === null || typeof buf === 'string');
        assert.doesNotMatch(core.paint(), /Internal Error|attempt to|stack traceback/, `no error after ${step.keys}`);
      }
      assert.equal(core.screen(), 'problem');
      const results = core.results().split('\n');
      for (const e of t.expect) assert.ok(results.includes(e), `${e} in\n${results.join('\n')}`);
      core.close();
    });
  }
}

await test('menu items run', async () => {
  const { core } = await boot('en');
  const menu = core.menu();
  const solvers = menu.findIndex((m) => m.title === 'Solvers');
  assert.ok(solvers >= 0, 'Solvers menu');
  const buf = core.menuSelect(solvers, 0);
  assert.ok(buf, 'repaint after a menu item');
  assert.equal(core.screen(), 'problem');
  core.close();
});

await test('CAS entries pretty-print', async () => {
  for (const t of TUTORIALS) {
    for (const step of t.cas) {
      for (const [input, output] of step.entries) {
        for (const s of [input, output]) {
          const html = TIMath.render(s);
          assert.ok(html.length > 0, s);
          assert.doesNotMatch(html, /undefined|NaN/, s);
        }
      }
    }
    for (const k of ['question', 'answer', 'casEnd']) {
      for (const lang of ['zh', 'en']) {
        const html = TIMath.inline(t[k][lang]);
        assert.doesNotMatch(html, /undefined|\$/, `${t.id} ${k} ${lang}`);
      }
    }
  }
  assert.match(TIMath.render('(x^2-3)/(x-2)'), /tm-frac/);
  assert.match(TIMath.render('integral(v/(−(1+v^2)),v,1,0)'), /tm-int/);
  assert.match(TIMath.render('derivative(f(x),x,2)|x=1'), /tm-with/);
});

if (failures) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log('all passed');
