// Cloudflare Worker for the VCE toolkit website.
//
// Static files (site/dist) are served by the assets binding. The Worker
// handles:
//   POST /api/feedback   store a message from the feedback form in D1
//   GET  /api/feedback   list messages (Authorization: Bearer ADMIN_TOKEN;
//                        ?format=csv, ?notify=1 for the update mailing list)
//   /admin               the page for reading feedback
//   /downloads/*.tns     calculator documents, sent as attachments
// Created on first use
const SCHEMA = `
CREATE TABLE IF NOT EXISTS feedback (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  created_at TEXT NOT NULL DEFAULT (strftime('%Y-%m-%dT%H:%M:%SZ', 'now')),
  email TEXT NOT NULL,
  name TEXT,
  message TEXT NOT NULL,
  edition TEXT,
  app_version TEXT,
  notify INTEGER NOT NULL DEFAULT 0,
  lang TEXT,
  page TEXT,
  ip_hash TEXT,
  user_agent TEXT
);
CREATE INDEX IF NOT EXISTS feedback_created ON feedback (created_at);
CREATE INDEX IF NOT EXISTS feedback_ip ON feedback (ip_hash, created_at)`;

const JSON_HEADERS = { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' };
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const EDITIONS = new Set(['', 'zh', 'en', 'none']);
const RATE_WINDOW_MIN = 10;
const RATE_MAX = 5;

function json(body, status = 200, extra = {}) {
  return new Response(JSON.stringify(body), { status, headers: { ...JSON_HEADERS, ...extra } });
}

const text = (v, max) => (typeof v === 'string' ? v.trim().slice(0, max) : '');

async function sha256(s) {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return Array.from(new Uint8Array(buf), (b) => b.toString(16).padStart(2, '0')).join('');
}

function safeEqual(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

async function ensureSchema(db) {
  const statements = SCHEMA.split(';').map((s) => s.trim()).filter(Boolean);
  await db.batch(statements.map((s) => db.prepare(s)));
}

// Run a D1 operation; create the table on first use
async function withSchema(db, fn) {
  try {
    return await fn();
  } catch (e) {
    if (!/no such table/i.test(String(e && e.message))) throw e;
    await ensureSchema(db);
    return fn();
  }
}

export async function submit(request, env) {
  if (!env.DB) return json({ ok: false, error: 'not configured' }, 503);
  const type = request.headers.get('content-type') || '';
  if (!type.includes('application/json')) return json({ ok: false, error: 'json expected' }, 415);
  const raw = await request.text();
  if (raw.length > 20000) return json({ ok: false, error: 'too long' }, 413);
  let body;
  try {
    body = JSON.parse(raw);
  } catch {
    return json({ ok: false, error: 'bad json' }, 400);
  }
  if (!body || typeof body !== 'object') return json({ ok: false, error: 'bad json' }, 400);

  // bots fill the hidden field: pretend it worked
  if (text(body.website, 200)) return json({ ok: true });

  const message = text(body.message, 5000);
  const email = text(body.email, 200);
  const name = text(body.name, 100);
  const edition = EDITIONS.has(body.edition) ? body.edition : '';
  const errors = [];
  if (!message) errors.push('message');
  if (!EMAIL_RE.test(email)) errors.push('email');
  if (errors.length) return json({ ok: false, error: 'invalid', fields: errors }, 400);

  const ip = request.headers.get('cf-connecting-ip') || '';
  const ipHash = ip ? (await sha256((env.IP_SALT || 'vce-maths-toolkit') + ip)).slice(0, 32) : '';
  const db = env.DB;

  if (ipHash) {
    const row = await withSchema(db, () => db.prepare(
      "SELECT COUNT(*) AS n FROM feedback WHERE ip_hash = ?1 AND created_at > strftime('%Y-%m-%dT%H:%M:%SZ', 'now', ?2)",
    ).bind(ipHash, `-${RATE_WINDOW_MIN} minutes`).first());
    if (row && row.n >= RATE_MAX) return json({ ok: false, error: 'slow down' }, 429, { 'retry-after': String(RATE_WINDOW_MIN * 60) });
  }

  await withSchema(db, () => db.prepare(
    `INSERT INTO feedback (email, name, message, edition, app_version, notify, lang, page, ip_hash, user_agent)
     VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)`,
  ).bind(email, name || null, message, edition || null, text(body.appVersion, 20) || null, body.notify === true ? 1 : 0,
    body.lang === 'en' ? 'en' : 'zh', text(body.page, 200) || null, ipHash || null,
    text(request.headers.get('user-agent') || '', 300) || null).run());

  return json({ ok: true });
}

function csv(rows) {
  const cols = ['id', 'created_at', 'name', 'email', 'edition', 'app_version', 'notify', 'lang', 'message'];
  const cell = (v) => {
    const s = v === null || v === undefined ? '' : String(v);
    return /[",\n\r]/.test(s) ? '"' + s.replace(/"/g, '""') + '"' : s;
  };
  return '﻿' + [cols.join(','), ...rows.map((r) => cols.map((c) => cell(r[c])).join(','))].join('\r\n') + '\r\n';
}

export async function list(request, env, url) {
  const token = env.ADMIN_TOKEN;
  if (!token) return json({ ok: false, error: 'admin is off (set the ADMIN_TOKEN secret)' }, 404);
  const auth = request.headers.get('authorization') || '';
  const given = auth.startsWith('Bearer ') ? auth.slice(7).trim() : '';
  if (!safeEqual(given, token)) return json({ ok: false, error: 'unauthorized' }, 401, { 'www-authenticate': 'Bearer' });
  if (!env.DB) return json({ ok: false, error: 'not configured' }, 503);

  const limit = Math.max(1, Math.min(1000, parseInt(url.searchParams.get('limit') || '200', 10) || 200));
  const notify = url.searchParams.get('notify') === '1';
  const db = env.DB;
  const res = await withSchema(db, () => db.prepare(
    `SELECT id, created_at, name, email, edition, app_version, notify, lang, message FROM feedback
     ${notify ? 'WHERE notify = 1' : ''} ORDER BY id DESC LIMIT ?1`,
  ).bind(limit).all());
  const rows = res.results || [];
  if (url.searchParams.get('format') === 'csv') {
    return new Response(csv(rows), {
      headers: {
        'content-type': 'text/csv; charset=utf-8',
        'content-disposition': `attachment; filename="feedback${notify ? '-notify' : ''}.csv"`,
        'cache-control': 'no-store',
      },
    });
  }
  return json({ ok: true, rows });
}

async function download(request, env, url) {
  const res = await env.ASSETS.fetch(request);
  if (!res.ok || !url.pathname.endsWith('.tns')) return res;
  const headers = new Headers(res.headers);
  const name = url.pathname.split('/').pop().replace(/[^\w.-]/g, '');
  headers.set('content-type', 'application/octet-stream');
  headers.set('content-disposition', `attachment; filename="${name}"`);
  headers.set('cache-control', 'public, max-age=300');
  headers.set('x-content-type-options', 'nosniff');
  return new Response(res.body, { status: res.status, headers });
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    try {
      if (url.pathname === '/api/feedback') {
        if (request.method === 'POST') return await submit(request, env);
        if (request.method === 'GET') return await list(request, env, url);
        return json({ ok: false, error: 'method not allowed' }, 405, { allow: 'GET, POST' });
      }
      if (url.pathname.startsWith('/api/')) return json({ ok: false, error: 'not found' }, 404);
      if (url.pathname === '/admin') {
        // the assets binding serves admin.html for /admin
        const res = await env.ASSETS.fetch(request);
        const headers = new Headers(res.headers);
        headers.set('cache-control', 'no-store');
        headers.set('x-robots-tag', 'noindex');
        return new Response(res.body, { status: res.status, headers });
      }
      if (url.pathname.startsWith('/downloads/')) return await download(request, env, url);
      return env.ASSETS.fetch(request);
    } catch (e) {
      console.error(e);
      return json({ ok: false, error: 'server error' }, 500);
    }
  },
};
