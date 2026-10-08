// Website behaviour: language switch, the live calculators, the step-by-step
// highlights (CAS by hand vs the toolkit), the feedback form.
(function () {
  'use strict';

  const $ = (s, r) => (r || document).querySelector(s);
  const $$ = (s, r) => Array.from((r || document).querySelectorAll(s));
  const root = document.documentElement;
  const lang = () => (root.getAttribute('data-lang') === 'en' ? 'en' : 'zh');
  const appLang = () => (lang() === 'zh' ? 'bi' : 'en');
  const both = (zh, en) => `<span lang="zh">${zh}</span><span lang="en">${en}</span>`;
  const inl = (o) => both(window.TIMath.inline(o.zh), window.TIMath.inline(o.en));

  function el(tag, attrs, html) {
    const e = document.createElement(tag);
    for (const [k, v] of Object.entries(attrs || {})) {
      if (k === 'class') e.className = v;
      else e.setAttribute(k, v);
    }
    if (html !== undefined) e.innerHTML = html;
    return e;
  }

  // Calculators ---------------------------------------------------------------

  const calcs = [];
  function makeCalc(node, onLang) {
    const calc = new window.NspireCalc(node, {
      lang: appLang(),
      doc: node.getAttribute('data-doc') || 'vce',
      label: lang() === 'zh' ? 'TI-Nspire 计算器屏幕：点击后可以用键盘操作' : 'TI-Nspire screen: click, then use the keyboard',
    });
    calcs.push({ calc, onLang });
    return calc;
  }

  function whenVisible(node, fn) {
    if (!('IntersectionObserver' in window)) { fn(); return; }
    const io = new IntersectionObserver((entries) => {
      if (entries.some((e) => e.isIntersecting)) { io.disconnect(); fn(); }
    }, { rootMargin: '200px' });
    io.observe(node);
  }

  // Language ------------------------------------------------------------------

  function setLang(l, save) {
    root.setAttribute('data-lang', l);
    root.lang = l === 'zh' ? 'zh-CN' : 'en';
    if (save) { try { localStorage.setItem('lang', l); } catch (e) { /* private mode */ } }
    $$('[data-ph-zh]').forEach((e) => { e.placeholder = e.getAttribute('data-ph-' + l) || ''; });
    document.title = l === 'zh' ? 'VCE Maths 工具箱 · TI-Nspire CX II CAS' : 'VCE Maths toolkit · TI-Nspire CX II CAS';
    for (const c of calcs) {
      if (c.calc.opts.lang === appLang()) continue;
      c.calc.opts.lang = appLang();
      if (c.calc.core) {
        if (c.onLang) c.onLang(); else c.calc.reset(appLang());
      }
    }
  }
  $$('[data-set-lang]').forEach((b) => b.addEventListener('click', () => setLang(b.getAttribute('data-set-lang'), true)));
  setLang(lang(), false);

  // Hero and playground ---------------------------------------------------------

  const heroNode = $('#hero-calc');
  if (heroNode) {
    const hero = makeCalc(heroNode);
    hero.start().catch(() => {});
  }
  const playNode = $('#play-calc');
  if (playNode) {
    const play = makeCalc(playNode);
    whenVisible(playNode, () => play.start().catch(() => {}));
    $$('[data-reset="play-calc"]').forEach((b) => b.addEventListener('click', () => play.reset(appLang())));
  }

  // Highlights -----------------------------------------------------------------

  const TUTORIALS = window.TUTORIALS || [];
  const tabs = $('#hl-tabs');
  const list = $('#hl-list');
  const panels = [];

  function badgeHtml(c) {
    return `<span class="badge ${c.toLowerCase()}" title="${c === 'MM' ? 'Mathematical Methods' : 'Specialist Mathematics'}">${c}</span>`;
  }

  function screenShell(extraClass) {
    const frame = el('div', { class: 'calc-frame' });
    const calc = el('div', { class: 'nspire ' + (extraClass || '') });
    frame.append(calc);
    return { frame, calc };
  }

  function buildTutorial(t, index) {
    const nCas = t.cas.reduce((n, s) => n + s.entries.length, 0);
    const art = el('article', { class: 'hl', id: 'hl-' + t.id, role: 'tabpanel', 'aria-labelledby': 'tab-' + t.id });
    art.innerHTML = `
      <div class="hl-head">
        <h3>${both(t.title.zh, t.title.en)}</h3>
        <span class="badges">${t.course.map(badgeHtml).join('')}</span>
        <span class="tag-rec">★ ${both('推荐', 'Recommended')}</span>
      </div>
      <p class="hl-pitch">${both(t.pitch.zh, t.pitch.en)}</p>
      <div class="question">
        <div class="label">${both('例题', 'Example')}</div>
        <p>${inl(t.question)}</p>
        <details class="answer"><summary>${both('看答案', 'Show the answer')}</summary><p>${inl(t.answer)}</p></details>
      </div>
      <div class="compare">
        <div class="way cas">
          <div class="way-head">
            <h4>${both('方法一 · 用 CAS 自己算', 'Way 1 · By hand in the CAS')}</h4>
            <span class="way-count">${both(nCas + ' 条命令', nCas + ' commands')}</span>
          </div>
          <div data-slot="cas"></div>
          <div class="caption" aria-live="polite" data-cap="cas"></div>
          <div class="stepper" data-step="cas">
            <button type="button" class="btn small" data-act="prev" aria-label="previous">◀</button>
            <span class="pos" data-pos></span>
            <button type="button" class="btn small primary" data-act="next">${both('下一步 ▶', 'Next ▶')}</button>
            <span class="spacer"></span>
            <button type="button" class="btn small" data-act="all">${both('全部显示', 'Show all')}</button>
            <button type="button" class="btn small" data-act="reset" aria-label="reset">↺</button>
          </div>
        </div>
        <div class="way app">
          <div class="way-head">
            <h4>${both('方法二 · 用这个程序', 'Way 2 · With this program')}</h4>
            <span class="way-count">${both('填 ' + t.boxes + ' 项', t.boxes + ' boxes')}</span>
          </div>
          <div data-slot="app"></div>
          <div class="caption" aria-live="polite" data-cap="app"></div>
          <div class="stepper" data-step="app">
            <button type="button" class="btn small" data-act="prev" aria-label="previous">◀</button>
            <span class="pos" data-pos></span>
            <button type="button" class="btn small primary" data-act="next">${both('下一步 ▶', 'Next ▶')}</button>
            <span class="spacer"></span>
            <button type="button" class="btn small" data-act="all">${both('一次做完', 'Do all')}</button>
            <button type="button" class="btn small" data-act="reset" aria-label="reset">↺</button>
          </div>
          <p class="web-note">${both('网页里是同一个程序，配了这道题的精确答案；装到计算器上用的是真正的 CAS。',
            'The same program as on the calculator, with this question\'s exact answers built in; on the calculator it uses the real CAS.')}</p>
        </div>
      </div>`;

    // Way 1: Calculator page mock
    const cas = screenShell('ti-calc');
    cas.calc.style.setProperty('--k', '1.6');
    const screen = el('div', { class: 'nspire-screen' });
    screen.innerHTML = `<div class="nspire-bar"><span class="nspire-tab">1.1</span><span class="nspire-doc">*Unsaved ▾</span><span class="nspire-mode">RAD</span><span class="nspire-batt"></span></div><div class="ti-page" tabindex="0"></div>`;
    cas.calc.append(screen);
    $('[data-slot="cas"]', art).append(cas.frame);
    const page = $('.ti-page', screen);
    if (window.ResizeObserver) {
      new ResizeObserver(() => cas.calc.style.setProperty('--k', String(screen.clientWidth / 320))).observe(screen);
    }

    const casState = { k: 0 };
    const casCap = $('[data-cap="cas"]', art);
    const casStep = $('[data-step="cas"]', art);
    function renderCas() {
      const k = casState.k;
      const n = t.cas.length;
      page.textContent = '';
      let any = false;
      for (let i = 0; i < k; i++) {
        for (const [a, b] of t.cas[i].entries) {
          const row = el('div', { class: 'ti-entry' + (i === k - 1 ? ' new' : '') });
          row.append(el('span', { class: 'in tm' }, window.TIMath.render(a)), el('span', { class: 'out tm' }, window.TIMath.render(b)));
          page.append(row);
          any = true;
        }
      }
      if (!any) page.append(el('div', { class: 'ti-empty' }, both('一个空白的 Calculator 页面', 'An empty Calculator page')));
      page.append(el('div', { class: 'ti-entry caret' }, '<span class="in"></span>'));
      page.scrollTop = page.scrollHeight;
      if (k === 0) {
        casCap.innerHTML = both('按“下一步”，看看平时在 Calculator 页面里要一条一条输入什么。',
          'Press “Next” to see what you would type into a Calculator page, one command at a time.');
      } else {
        casCap.innerHTML = inl(t.cas[k - 1]) + (k === n ? `<span class="end">${inl(t.casEnd)}</span>` : '');
      }
      $('[data-pos]', casStep).textContent = `${k} / ${n}`;
      $('[data-act="prev"]', casStep).disabled = k === 0;
      $('[data-act="next"]', casStep).disabled = k === n;
      $('[data-act="all"]', casStep).disabled = k === n;
    }
    casStep.addEventListener('click', (e) => {
      const b = e.target.closest('[data-act]');
      if (!b) return;
      const act = b.getAttribute('data-act');
      if (act === 'next') casState.k = Math.min(t.cas.length, casState.k + 1);
      else if (act === 'prev') casState.k = Math.max(0, casState.k - 1);
      else if (act === 'all') casState.k = t.cas.length;
      else casState.k = 0;
      renderCas();
    });
    renderCas();

    // Way 2: the live toolkit
    const app = screenShell();
    $('[data-slot="app"]', art).append(app.frame);
    app.calc.setAttribute('data-doc', 'vce');
    const appCap = $('[data-cap="app"]', art);
    const appStep = $('[data-step="app"]', art);
    const appState = { j: 0, busy: false };
    let calc = null;
    const ensure = () => {
      if (!calc) calc = makeCalc(app.calc, () => goTo(appState.j));
      return calc.start();
    };
    function renderApp() {
      const j = appState.j;
      const m = t.app.length;
      if (j === 0) {
        appCap.innerHTML = both('这是程序的首页。按“下一步”，看看这道题要输入什么（屏幕上会自动按键）。',
          'This is the program\'s home screen. Press “Next” to see what to type for this question (the keys are pressed for you).');
      } else {
        appCap.innerHTML = both(t.app[j - 1].zh, t.app[j - 1].en) + (j === m ? `<span class="end">${both(t.appEnd.zh, t.appEnd.en)}</span>` : '');
      }
      $('[data-pos]', appStep).textContent = `${j} / ${m}`;
      $('[data-act="prev"]', appStep).disabled = j === 0 || appState.busy;
      $('[data-act="next"]', appStep).disabled = j === m || appState.busy;
      $('[data-act="all"]', appStep).disabled = j === m || appState.busy;
      $('[data-act="reset"]', appStep).disabled = appState.busy;
    }
    // Jump to step j at once: fresh document, then the earlier key scripts
    async function goTo(j) {
      appState.busy = true;
      renderApp();
      try {
        await ensure();
        await calc.reset(appLang());
        calc.run(t.app.slice(0, j).map((s) => s.keys).join(''));
        appState.j = j;
      } finally {
        appState.busy = false;
        renderApp();
      }
    }
    appStep.addEventListener('click', async (e) => {
      const b = e.target.closest('[data-act]');
      if (!b || appState.busy) return;
      const act = b.getAttribute('data-act');
      if (act === 'next' && appState.j < t.app.length) {
        appState.busy = true;
        renderApp();
        try {
          await ensure();
          appState.j++;
          renderApp();
          appState.busy = true;
          await calc.play(t.app[appState.j - 1].keys);
        } finally {
          appState.busy = false;
          renderApp();
        }
      } else if (act === 'prev') {
        await goTo(Math.max(0, appState.j - 1));
      } else if (act === 'all') {
        await goTo(t.app.length);
      } else if (act === 'reset') {
        await goTo(0);
      }
    });
    renderApp();

    const tab = el('button', { class: 'hl-tab', id: 'tab-' + t.id, role: 'tab', type: 'button', 'aria-controls': 'hl-' + t.id, 'aria-selected': 'false' },
      `<span class="n">${index + 1}</span><span>${both(t.title.zh, t.title.en)}</span>`);
    tab.addEventListener('click', () => activate(t.id, true));
    tabs.append(tab);
    list.append(art);
    panels.push({ t, art, tab, show: () => whenVisible(app.calc, () => ensure().catch(() => {})) });
  }

  function activate(id, user) {
    for (const p of panels) {
      const on = p.t.id === id;
      p.art.classList.toggle('active', on);
      p.tab.setAttribute('aria-selected', on ? 'true' : 'false');
      p.tab.tabIndex = on ? 0 : -1;
      if (on) p.show();
    }
    if (user && history.replaceState) history.replaceState(null, '', '#hl-' + id);
  }

  if (tabs && list && TUTORIALS.length) {
    tabs.setAttribute('role', 'tablist');
    TUTORIALS.forEach(buildTutorial);
    tabs.addEventListener('keydown', (e) => {
      const i = panels.findIndex((p) => p.tab.getAttribute('aria-selected') === 'true');
      let k = -1;
      if (e.key === 'ArrowRight') k = (i + 1) % panels.length;
      if (e.key === 'ArrowLeft') k = (i + panels.length - 1) % panels.length;
      if (k >= 0) { e.preventDefault(); activate(panels[k].t.id, true); panels[k].tab.focus(); }
    });
    const m = /^#hl-([\w-]+)$/.exec(location.hash);
    const first = m && panels.some((p) => p.t.id === m[1]) ? m[1] : TUTORIALS[0].id;
    activate(first, false);
    if (m) { const target = $('#highlights'); if (target) target.scrollIntoView(); }
  }

  // Latest version (the page may be cached) -------------------------------------

  fetch('/version.json', { cache: 'no-store' }).then((r) => (r.ok ? r.json() : null)).then((v) => {
    if (!v || !v.version) return;
    const shown = $('[data-version]');
    if (shown && shown.textContent !== v.version) {
      shown.textContent = v.version;
      const note = $('[data-update-note]');
      if (note) {
        note.hidden = false;
        note.innerHTML = both('（有新版本，请刷新页面）', '(a new version is out, reload the page)');
      }
    }
  }).catch(() => {});

  // Feedback ---------------------------------------------------------------------

  const form = $('#fb-form');
  if (form) {
    const msg = $('#fb-msg');
    const email = $('#fb-email');
    const status = $('[data-status]', form);
    const count = $('[data-count]', form);
    const say = (cls, zh, en) => { status.className = 'fb-status ' + cls; status.innerHTML = both(zh, en); };
    const updateCount = () => {
      const n = [...msg.value.trim()].length;
      count.innerHTML = n ? both(n + ' 字', n + ' characters') : '';
    };
    msg.addEventListener('input', () => { updateCount(); msg.removeAttribute('aria-invalid'); });
    email.addEventListener('input', () => email.removeAttribute('aria-invalid'));
    form.addEventListener('submit', async (e) => {
      e.preventDefault();
      const message = msg.value.trim();
      const mail = email.value.trim();
      if (!message) {
        msg.setAttribute('aria-invalid', 'true');
        msg.focus();
        say('err', '写一点点就好，十个字也可以。', 'Write a little — even ten words is fine.');
        return;
      }
      if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(mail)) {
        email.setAttribute('aria-invalid', 'true');
        email.focus();
        say('err', '请填一个能收到回复的邮箱。', 'Please give an email address we can reply to.');
        return;
      }
      const data = new FormData(form);
      const body = {
        message,
        email: mail,
        name: String(data.get('name') || '').trim(),
        edition: String(data.get('edition') || ''),
        notify: data.get('notify') === '1',
        website: String(data.get('website') || ''),
        lang: lang(),
        appVersion: ($('[data-version]') || {}).textContent || '',
      };
      const button = $('button[type="submit"]', form);
      button.disabled = true;
      say('', '正在发送…', 'Sending…');
      try {
        const r = await fetch('/api/feedback', {
          method: 'POST',
          headers: { 'content-type': 'application/json' },
          body: JSON.stringify(body),
        });
        if (r.ok) {
          form.reset();
          updateCount();
          say('ok', '收到了，谢谢你！每一条我们都会看。', 'Got it, thank you! We read every message.');
        } else if (r.status === 429) {
          say('err', '发得有点快，过几分钟再试一次吧。', 'That was quick: please try again in a few minutes.');
        } else {
          say('err', '没发出去，请稍后再试。', 'It did not go through. Please try again later.');
        }
      } catch (err) {
        say('err', '网络好像断了，请稍后再试。', 'The network seems to be down. Please try again later.');
      } finally {
        button.disabled = false;
      }
    });
  }
})();
