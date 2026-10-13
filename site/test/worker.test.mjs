// Tests the website Worker (src/worker.mjs) with an in-memory SQLite
// database standing in for D1. Run: node site/test/worker.test.mjs
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import worker from '../src/worker.mjs';

// Just enough of the D1 API: prepare().bind().first()/all()/run(), batch()
function fakeD1() {
  const db = new DatabaseSync(':memory:');
  const stmt = (sql, args = []) => ({
    bind: (...a) => stmt(sql, a),
    first: async () => db.prepare(sql).get(...args) || null,
    all: async () => ({ results: db.prepare(sql).all(...args) }),
    run: async () => { db.prepare(sql).run(...args); return { success: true }; },
    exec: () => db.prepare(sql).run(...args),
  });
  return {
    raw: db,
    prepare: (sql) => stmt(sql),
    batch: async (list) => { for (const s of list) s.exec(); return []; },
  };
}

const ASSETS = {
  fetch: async (req) => {
    const url = new URL(req.url);
    if (url.pathname === '/downloads/vce.tns') return new Response('TNS', { headers: { 'content-type': 'text/plain' } });
    if (url.pathname === '/admin') return new Response('<html>admin</html>', { headers: { 'content-type': 'text/html' } });
    return new Response('not found', { status: 404 });
  },
};

const post = (body, ip = '203.0.113.7', type = 'application/json') => new Request('https://site.test/api/feedback', {
  method: 'POST',
  headers: { 'content-type': type, 'cf-connecting-ip': ip, 'user-agent': 'test' },
  body: typeof body === 'string' ? body : JSON.stringify(body),
});
const get = (q = '', token) => new Request('https://site.test/api/feedback' + q, {
  headers: token ? { authorization: 'Bearer ' + token } : {},
});

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

const count = (env) => env.DB.raw.prepare('SELECT COUNT(*) AS n FROM feedback').get().n;

await test('stores feedback and creates the table', async () => {
  const env = { DB: fakeD1(), ASSETS };
  const res = await worker.fetch(post({ message: '  很好用  ', email: 'a@b.co', name: 'Lin', edition: 'zh', notify: true, lang: 'zh', appVersion: '2.1' }), env);
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  const row = env.DB.raw.prepare('SELECT * FROM feedback').get();
  assert.equal(row.message, '很好用');
  assert.equal(row.email, 'a@b.co');
  assert.equal(row.name, 'Lin');
  assert.equal(row.edition, 'zh');
  assert.equal(row.notify, 1);
  assert.equal(row.app_version, '2.1');
  assert.match(row.ip_hash, /^[0-9a-f]{32}$/);
  assert.notEqual(row.ip_hash, '203.0.113.7');
  assert.match(row.created_at, /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/);
});

await test('name and edition are optional', async () => {
  const env = { DB: fakeD1(), ASSETS };
  const res = await worker.fetch(post({ message: 'ok', email: 'x@y.org' }), env);
  assert.equal(res.status, 200);
  const row = env.DB.raw.prepare('SELECT * FROM feedback').get();
  assert.equal(row.name, null);
  assert.equal(row.edition, null);
  assert.equal(row.notify, 0);
});

await test('rejects a missing email or message', async () => {
  const env = { DB: fakeD1(), ASSETS };
  let res = await worker.fetch(post({ message: 'hi', email: 'not-an-email' }), env);
  assert.equal(res.status, 400);
  assert.deepEqual((await res.json()).fields, ['email']);
  res = await worker.fetch(post({ message: '   ', email: 'a@b.co' }), env);
  assert.equal(res.status, 400);
  assert.deepEqual((await res.json()).fields, ['message']);
  res = await worker.fetch(post('message=hi', undefined, 'application/x-www-form-urlencoded'), env);
  assert.equal(res.status, 415);
  res = await worker.fetch(post('{bad json'), env);
  assert.equal(res.status, 400);
});

await test('drops bot posts quietly (hidden field filled)', async () => {
  const env = { DB: fakeD1(), ASSETS };
  const res = await worker.fetch(post({ message: 'buy now', email: 'spam@x.co', website: 'http://spam' }), env);
  assert.equal(res.status, 200);
  assert.throws(() => count(env), /no such table/);
});

await test('limits each address to 5 messages in 10 minutes', async () => {
  const env = { DB: fakeD1(), ASSETS };
  for (let i = 0; i < 5; i++) {
    const res = await worker.fetch(post({ message: 'm' + i, email: 'a@b.co' }), env);
    assert.equal(res.status, 200);
  }
  const res = await worker.fetch(post({ message: 'one more', email: 'a@b.co' }), env);
  assert.equal(res.status, 429);
  const other = await worker.fetch(post({ message: 'someone else', email: 'c@d.co' }, '198.51.100.9'), env);
  assert.equal(other.status, 200);
  assert.equal(count(env), 6);
});

await test('long text is cut to the limits', async () => {
  const env = { DB: fakeD1(), ASSETS };
  const res = await worker.fetch(post({ message: 'x'.repeat(6000), email: 'a@b.co', name: 'n'.repeat(300) }), env);
  assert.equal(res.status, 200);
  const row = env.DB.raw.prepare('SELECT * FROM feedback').get();
  assert.equal(row.message.length, 5000);
  assert.equal(row.name.length, 100);
});

await test('admin list needs ADMIN_TOKEN', async () => {
  const env = { DB: fakeD1(), ASSETS };
  await worker.fetch(post({ message: 'hello, "quoted"', email: 'a@b.co', notify: true }), env);
  await worker.fetch(post({ message: 'second', email: 'c@d.co' }, '198.51.100.9'), env);
  let res = await worker.fetch(get(), env);
  assert.equal(res.status, 404, 'off without a token');
  env.ADMIN_TOKEN = 'secret-token';
  res = await worker.fetch(get('', 'wrong-token!'), env);
  assert.equal(res.status, 401);
  res = await worker.fetch(get(), env);
  assert.equal(res.status, 401);
  res = await worker.fetch(get('', 'secret-token'), env);
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.rows.length, 2);
  assert.equal(data.rows[0].message, 'second', 'newest first');
  assert.equal(data.rows[0].ip_hash, undefined, 'no address hash in the list');
  res = await worker.fetch(get('?notify=1', 'secret-token'), env);
  assert.equal((await res.json()).rows.length, 1);
  res = await worker.fetch(get('?format=csv', 'secret-token'), env);
  assert.match(res.headers.get('content-type'), /text\/csv/);
  const csv = await res.text();
  assert.match(csv, /"hello, ""quoted"""/);
});

await test('downloads are attachments; /admin is not cached', async () => {
  const env = { DB: fakeD1(), ASSETS };
  let res = await worker.fetch(new Request('https://site.test/downloads/vce.tns'), env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('content-disposition'), 'attachment; filename="vce.tns"');
  assert.equal(res.headers.get('content-type'), 'application/octet-stream');
  res = await worker.fetch(new Request('https://site.test/admin'), env);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get('cache-control'), 'no-store');
  res = await worker.fetch(new Request('https://site.test/api/nothing'), env);
  assert.equal(res.status, 404);
  res = await worker.fetch(new Request('https://site.test/api/feedback', { method: 'DELETE' }), env);
  assert.equal(res.status, 405);
});

if (failures) {
  console.log(`${failures} failed`);
  process.exit(1);
}
console.log('all passed');
