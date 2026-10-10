// Pretty-prints TI-Nspire linear input (solve(derivative(f(x),x)=0,x),
// (x^2-3)/(x-2), integral(v/(−(1+v^2)),v,1,0) ...) as 2D HTML, the way the
// Calculator app shows entries: stacked fractions, raised powers, root bars,
// d/dx and ∫ templates.
(function (root) {
  'use strict';

  const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

  function tokenize(src) {
    const out = [];
    const re = /\s*(?:(\d+(?:\.\d+)?)|([A-Za-zα-ωπθ][A-Za-z0-9α-ωπθ⁻¹']*)|(≠|≤|≥|−|[-+*/^=<>|,(){}√∞·]))/uy;
    let i = 0;
    while (i < src.length) {
      re.lastIndex = i;
      const m = re.exec(src);
      if (!m) {
        if (/\s/.test(src[i])) { i++; continue; }
        out.push({ k: 'op', v: src[i] });
        i++;
        continue;
      }
      if (m[1] !== undefined) out.push({ k: 'num', v: m[1] });
      else if (m[2] !== undefined) out.push({ k: m[2] === 'or' || m[2] === 'and' ? 'kw' : 'id', v: m[2] });
      else out.push({ k: 'op', v: m[3] === '−' ? '-' : m[3] === '·' ? '*' : m[3], neg: m[3] === '−' });
      i = re.lastIndex;
    }
    return out;
  }

  function parse(src) {
    const t = tokenize(src);
    let p = 0;
    const peek = () => t[p];
    const isOp = (v) => t[p] && t[p].k === 'op' && t[p].v === v;
    const eat = (v) => { if (isOp(v)) { p++; return true; } return false; };

    function expr() {
      let a = logic();
      while (isOp('|')) { p++; a = { t: 'with', a, b: logic() }; }
      return a;
    }
    function logic() {
      let a = rel();
      while (peek() && peek().k === 'kw') { const op = t[p++].v; a = { t: 'kw', op, a, b: rel() }; }
      return a;
    }
    function rel() {
      let a = add();
      while (peek() && peek().k === 'op' && ['=', '<', '>', '≤', '≥', '≠'].includes(peek().v)) {
        const op = t[p++].v;
        a = { t: 'bin', op, a, b: add() };
      }
      return a;
    }
    function add() {
      let a = mul();
      while (isOp('+') || isOp('-')) { const op = t[p++].v; a = { t: 'bin', op, a, b: mul() }; }
      return a;
    }
    function startsPrimary() {
      const k = peek();
      if (!k) return false;
      return k.k === 'num' || k.k === 'id' || (k.k === 'op' && (k.v === '(' || k.v === '√' || k.v === '{'));
    }
    function mul() {
      let a = unary();
      for (;;) {
        if (isOp('*')) { p++; a = { t: 'bin', op: '*', a, b: unary() }; } else if (isOp('/')) { p++; a = { t: 'frac', a, b: unary() }; } else if (startsPrimary()) a = { t: 'bin', op: '', a, b: unary() };
        else break;
      }
      return a;
    }
    function unary() {
      if (isOp('-')) { p++; return { t: 'neg', e: unary() }; }
      if (isOp('+')) { p++; return unary(); }
      return pow();
    }
    function pow() {
      const a = postfix();
      if (isOp('^')) { p++; return { t: 'pow', a, b: unary() }; }
      return a;
    }
    function args() {
      const list = [];
      if (isOp(')')) { p++; return list; }
      do { list.push(expr()); } while (eat(','));
      eat(')');
      return list;
    }
    function postfix() {
      const k = peek();
      if (k && k.k === 'id' && t[p + 1] && t[p + 1].k === 'op' && t[p + 1].v === '(') {
        p += 2;
        return { t: 'call', name: k.v, args: args() };
      }
      return primary();
    }
    function primary() {
      const k = t[p++];
      if (!k) return { t: 'txt', v: '' };
      if (k.k === 'num') return { t: 'num', v: k.v };
      if (k.k === 'id') return { t: 'id', v: k.v };
      if (k.k === 'op' && k.v === '(') { const e = expr(); eat(')'); return { t: 'paren', e }; }
      if (k.k === 'op' && k.v === '{') {
        const items = [];
        if (!isOp('}')) do { items.push(expr()); } while (eat(','));
        eat('}');
        return { t: 'list', items };
      }
      if (k.k === 'op' && k.v === '√') {
        if (eat('(')) { const e = expr(); eat(')'); return { t: 'sqrt', e }; }
        return { t: 'sqrt', e: postfix() };
      }
      if (k.k === 'op' && k.v === '∞') return { t: 'id', v: '∞' };
      return { t: 'txt', v: k.v };
    }
    const e = expr();
    if (p < t.length) {
      const rest = t.slice(p).map((x) => x.v).join('');
      return { t: 'seq', items: [e, { t: 'txt', v: rest }] };
    }
    return e;
  }

  const strip = (n) => (n.t === 'paren' ? n.e : n);
  const tall = (n) => {
    if (!n || typeof n !== 'object') return false;
    if (n.t === 'frac' || n.t === 'call' && (n.name === 'derivative' || n.name === 'integral')) return true;
    return ['a', 'b', 'e'].some((k) => tall(n[k])) || (n.items || n.args || []).some(tall);
  };
  const OPS = { '=': '=', '<': '&lt;', '>': '&gt;', '≤': '≤', '≥': '≥', '≠': '≠', '+': '+', '-': '−', '*': '·', '': '' };

  function paren(inner, isTall) {
    return `<span class="tm-paren${isTall ? ' tall' : ''}"><span class="tm-pl">(</span>${inner}<span class="tm-pr">)</span></span>`;
  }

  function frac(a, b) {
    return `<span class="tm-frac"><span class="tm-num">${a}</span><span class="tm-den">${b}</span></span>`;
  }

  function html(n) {
    switch (n.t) {
      case 'num':
        return esc(n.v);
      case 'id':
        return `<span class="tm-id">${esc(n.v === 'pi' ? 'π' : n.v)}</span>`;
      case 'txt':
        return esc(n.v);
      case 'seq':
        return n.items.map(html).join('');
      case 'paren':
        return paren(html(n.e), tall(n.e));
      case 'list':
        return '{' + n.items.map(html).join(',') + '}';
      case 'neg':
        return '−' + html(n.e);
      case 'frac':
        return frac(html(strip(n.a)), html(strip(n.b)));
      case 'pow':
        return `${html(n.a)}<sup class="tm-sup">${html(strip(n.b))}</sup>`;
      case 'sqrt':
        return `<span class="tm-sqrt"><span class="tm-rad">√</span><span class="tm-under">${html(strip(n.e))}</span></span>`;
      case 'with':
        return `${html(n.a)}<span class="tm-with">|</span>${html(n.b)}`;
      case 'kw':
        return `${html(n.a)} <span class="tm-kw">${n.op}</span> ${html(n.b)}`;
      case 'bin': {
        const op = OPS[n.op] !== undefined ? OPS[n.op] : esc(n.op);
        const sp = ['=', '<', '>', '≤', '≥', '≠'].includes(n.op) ? '<span class="tm-rel">' + op + '</span>' : op;
        return html(n.a) + sp + html(n.b);
      }
      case 'call':
        return call(n);
      default:
        return '';
    }
  }

  function call(n) {
    const a = n.args;
    const arg = (x) => (x.t === 'paren' || x.t === 'id' || x.t === 'num' || x.t === 'call' ? html(x) : paren(html(x), tall(x)));
    if (n.name === 'derivative' && a.length >= 2) {
      const order = a[2] ? html(a[2]) : '';
      const d = frac('d' + (order ? `<sup class="tm-sup">${order}</sup>` : ''), 'd' + html(a[1]) + (order ? `<sup class="tm-sup">${order}</sup>` : ''));
      return d + paren(html(a[0]), tall(a[0]));
    }
    if (n.name === 'integral' && a.length >= 2) {
      const lim = a.length >= 4
        ? `<span class="tm-lims"><span class="tm-hi">${html(a[3])}</span><span class="tm-lo">${html(a[2])}</span></span>` : '';
      return `<span class="tm-int"><span class="tm-intsign">∫</span>${lim}</span>${arg(a[0])}<span class="tm-dx">d${html(a[1])}</span>`;
    }
    if (n.name === 'sqrt' && a.length === 1) return html({ t: 'sqrt', e: a[0] });
    const name = n.name === 'Define' ? 'Define ' : esc(n.name);
    return `<span class="tm-fn">${name}</span>${paren(a.map(html).join(','), a.some(tall))}`;
  }

  // TI linear text → HTML. "Define f(x)=…" keeps its keyword.
  function render(src) {
    src = String(src).trim();
    const def = /^Define\s+/.exec(src);
    if (def) return '<span class="tm-kw">Define</span> ' + html(parse(src.slice(def[0].length)));
    if (/^[A-Za-z][a-z]*$/.test(src) && src.length > 2 && !/^(pi)$/.test(src)) return esc(src);
    return html(parse(src));
  }

  // Replace $…$ in a caption with inline maths
  function inline(text) {
    return String(text).split(/(\$[^$]+\$)/).map((part) =>
      part.length > 2 && part[0] === '$' && part[part.length - 1] === '$'
        ? `<span class="tm tm-inline">${render(part.slice(1, -1))}</span>`
        : part).join('');
  }

  const api = { render, inline, parse };
  if (typeof module !== 'undefined' && module.exports) module.exports = api;
  else root.TIMath = api;
})(typeof globalThis !== 'undefined' ? globalThis : this);
