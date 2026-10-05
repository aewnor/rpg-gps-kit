// Editor de misiones: campañas = capítulos de data/missions.json (API /api/campaigns de tools/web_server.py,
// validación y LLM en tools/campaigns.py). Formulario para misiones y pasos; plantillas y cadena en la
// pestaña JSON. Exporta cada campaña en un JSON autodescriptivo para un LLM e importa lo que devuelva.
'use strict';
const $ = (id) => document.getElementById(id);
const S = {
  list: [], ref: null, doc: '', sel: null, draft: null, saved: null, rev: null, dirty: false,
  tab: 'form', open: new Set(), issues: { errors: [], warnings: [] }, ai: null, imp: null, isNew: false,
};
const CAT_LABEL = { nav: 'Orientación', social: 'Familia y amigos', safety: 'Seguridad', job: 'Encargos', epic: 'Aventura' };
const STEP_LABEL = {
  goto: 'Ir a un lugar', talk: 'Hablar con…', deliver: 'Entregar objeto', buy: 'Comprar', have: 'Tener objeto',
  enter: 'Entrar en escena', level: 'Llegar a nivel', defeat: 'Vencer', event: 'Evento del mundo',
  crosswalk: 'Pasos de peatones', light: 'Semáforos en verde', recycle: 'Reciclar', bus: 'Coger el bus', meet_olaf: 'Encontrar a Olaf',
};
const FIELD = {   // tipo de control y etiqueta de cada campo de paso
  target: ['target', 'Objetivo (brújula)'], radius: ['int', 'Radio (px; 16 = 1 casilla)'], alt: ['list-target', 'Alternativos (coma)'],
  item: ['item', 'Objeto'], count: ['int', 'Cantidad'], items: ['list-item', 'Objetos (coma)'], at: ['list-service', 'Tiendas (coma)'],
  scene: ['scene', 'Escena'], event: ['event', 'Evento'], text: ['text', 'Texto de la brújula'], give: ['item', 'Da al acabar'],
  say: ['lines', 'Diálogo al acabar (una frase por línea)'], who: ['text', 'Quién lo dice'], inside: ['text', 'Prefijo de escena (inside)'],
  done_text: ['lines', 'Frases al entregar (una por línea)'],
  join: ['text', 'Amigo que se une y te sigue ({id})'], leave: ['text', 'El amigo se va a casa (true)'],
};

function setStatus(t, cls) { const s = $('status'); s.textContent = t; s.style.color = cls === 'err' ? 'var(--danger)' : cls === 'ok' ? 'var(--ok)' : ''; }
function esc(s) { return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c])); }
const clone = (o) => JSON.parse(JSON.stringify(o));
function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v == null || v === false) continue;
    if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'class') e.className = v;
    else if (k === 'html') e.innerHTML = v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const k of kids.flat()) if (k != null && k !== false) e.append(k.nodeType ? k : document.createTextNode(k));
  return e;
}

async function api(method, url, body) {
  const headers = { 'X-Roda-Request': '1' };
  if (method === 'PUT' || method === 'DELETE' || url === '/api/campaigns/order') headers['If-Match'] = S.rev || '"missing"';
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  const send = () => fetch(url, { method, headers, body: body !== undefined ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(url.endsWith('/llm') ? 330000 : 20000) });
  let r = await send();
  if (r.status === 401 && await window.RodaAdult.ensure()) r = await send();
  const j = await r.json().catch(() => ({}));
  if (!r.ok) throw new Error(j.error || 'No se puede completar la petición');
  if (r.headers.get('ETag') && url.startsWith('/api/campaigns') && method !== 'POST') S.rev = r.headers.get('ETag');
  return j;
}

// ---------------------------------------------------------------- borrador local (por si se cierra la pestaña)
const DRAFT_KEY = (id) => 'roda-missions-draft:' + id;
function stashDraft() { try { if (S.draft && S.dirty) localStorage.setItem(DRAFT_KEY(S.sel || S.draft.id), JSON.stringify(S.draft)); } catch {} }
function dropDraft(id) { try { localStorage.removeItem(DRAFT_KEY(id)); } catch {} }
function readDraft(id) { try { return JSON.parse(localStorage.getItem(DRAFT_KEY(id)) || 'null'); } catch { return null; } }

function markDirty() {
  S.dirty = true;
  stashDraft();
  setStatus('Cambios sin guardar');
  scheduleValidate();
  renderList();
}

// ---------------------------------------------------------------- carga
async function loadList() {
  const j = await api('GET', '/api/campaigns');
  S.list = j.campaigns; S.doc = j.doc;
  renderList();
}
async function loadRef() {
  S.ref = await api('GET', '/api/campaigns/reference');
  const r = S.ref, opt = (v, l) => `<option value="${esc(v)}">${esc(l || '')}</option>`;
  const targets = [opt('home', 'Casa del jugador'), opt('wallet', 'La cartera perdida')];
  for (const [k, v] of Object.entries(r.services)) targets.push(opt('service:' + k, v.label + ' · ' + v.npc));
  for (const [k, v] of Object.entries(r.areas)) targets.push(opt('area:' + k, v));
  for (const [k, v] of Object.entries(r.spots || {})) targets.push(opt('spot:' + k, v));
  for (const [k, v] of Object.entries(r.chests || {})) targets.push(opt('chest:' + k, v || 'cofre'));
  for (const k of r.nearest) targets.push(opt('nearest:' + k, 'el más cercano'));
  for (const k of r.roles) targets.push(opt('friend:' + k, 'personaje del perfil'));
  for (const k of r.bosses) targets.push(opt(k, 'jefe final'));
  for (const k of r.streets || []) targets.push(opt('street:' + k, 'calle'));
  $('dlTargets').innerHTML = targets.join('');
  $('dlItems').innerHTML = Object.entries(r.items).map(([k, v]) => opt(k, v.name + ' · ' + v.kind)).join('');
  $('dlScenes').innerHTML = r.scenes.map((k) => opt(k)).join('');
  $('dlEvents').innerHTML = ['wallet_started', 'wallet_returned', 'parent_pare', 'parent_mare', 'home_'].map((k) => opt(k)).join('');
  $('dlServices').innerHTML = Object.entries(r.services).map(([k, v]) => opt(k, v.label)).join('');
}
async function openCampaign(id, force) {
  if (!force && S.dirty && !confirm('Hay cambios sin guardar en esta campaña. ¿Descartarlos?')) return;
  try {
    const j = await api('GET', '/api/campaigns/' + id);
    S.sel = id; S.saved = j.campaign; S.isNew = false;
    S.draft = clone(j.campaign); S.dirty = false; S.ai = null; S.open.clear();
    const stash = readDraft(id);
    if (stash && JSON.stringify(stash) !== JSON.stringify(j.campaign) &&
        confirm('Hay un borrador sin guardar de «' + (stash.title || id) + '» en este navegador. ¿Recuperarlo?')) {
      S.draft = stash; S.dirty = true;
    } else dropDraft(id);
    S.issues = { errors: j.errors, warnings: j.warnings };
    try { history.replaceState(null, '', '#' + id); } catch {}
    setStatus(S.dirty ? 'Borrador recuperado (sin guardar)' : 'Campaña cargada');
    render();
    if (S.dirty) scheduleValidate();
  } catch (e) { setStatus(e.message, 'err'); }
}

// ---------------------------------------------------------------- lista
function renderList() {
  const box = $('camps'); box.innerHTML = '';
  const items = S.list.slice();
  if (S.isNew && S.draft && !items.some((c) => c.id === S.sel)) items.push({ id: S.sel, title: S.draft.title || '(nueva)', missions: 0, isNew: true });
  for (const c of items) {
    const sel = c.id === S.sel;
    const nerr = sel ? S.issues.errors.length : c.errors, nw = sel ? S.issues.warnings.length : c.warnings;
    const n = sel && S.draft ? (S.draft.missions || []).length : c.missions;
    box.append(h('button', { class: 'camp' + (sel ? ' sel' : ''), onclick: () => c.id !== S.sel && openCampaign(c.id) },
      h('span', { class: 't' }, sel && S.draft ? S.draft.title || c.id : c.title,
        sel && S.dirty ? h('span', { class: 'badge d', title: 'sin guardar' }, '●') : null,
        nerr ? h('span', { class: 'badge e', title: 'errores' }, nerr) : null,
        nw ? h('span', { class: 'badge w', title: 'avisos' }, nw) : null),
      h('span', { class: 'm' }, `${c.id} · ${n} misiones` + (c.templates ? ` · ${c.templates} plantillas` : '') +
        (c.after ? ` · tras ${c.after} (${c.unlock})` : '') + (c.isNew ? ' · nueva' : ''))));
  }
}

// ---------------------------------------------------------------- formulario
function field(obj, key, kind, label, opts = {}) {
  const v = obj[key];
  const set = (val) => {
    if (val === '' || val == null || (Array.isArray(val) && !val.length)) { if (opts.keep) obj[key] = val; else delete obj[key]; }
    else obj[key] = val;
    opts.after && opts.after();
    markDirty();
  };
  let input;
  const list = { target: 'dlTargets', item: 'dlItems', scene: 'dlScenes', event: 'dlEvents' }[kind];
  if (kind === 'int') {
    input = h('input', { type: 'number', min: opts.min ?? 0, step: 1, value: v ?? '', oninput: (e) => set(e.target.value === '' ? '' : Math.round(+e.target.value)) });
  } else if (kind === 'lines') {
    input = h('textarea', { rows: Math.max(2, (v || []).length), oninput: (e) => set(e.target.value.split('\n').map((s) => s.trim()).filter(Boolean)) });
    input.value = (v || []).join('\n');
  } else if (kind.startsWith('list-')) {
    const dl = { 'list-target': 'dlTargets', 'list-item': 'dlItems', 'list-service': 'dlServices' }[kind];
    input = h('input', { type: 'text', list: dl, value: (v || []).join(', '), spellcheck: 'false',
      oninput: (e) => set(e.target.value.split(',').map((s) => s.trim()).filter(Boolean)) });
  } else if (kind === 'select') {
    input = h('select', { onchange: (e) => set(e.target.value) },
      ...opts.options.map(([val, l]) => h('option', { value: val, selected: val === (v ?? '') }, l)));
  } else if (kind === 'check') {
    input = h('input', { type: 'checkbox', checked: !!(opts.is ? opts.is(v) : v), onchange: (e) => set(opts.map ? opts.map(e.target.checked) : e.target.checked || '') });
    return h('label', { class: 'f check' + (opts.wide ? ' wide' : '') }, input, h('span', {}, label));
  } else {
    input = h('input', { type: 'text', value: v ?? '', list, spellcheck: kind === 'text' ? 'true' : 'false', maxlength: opts.max,
      oninput: (e) => set(e.target.value) });
  }
  return h('label', { class: 'f' + (opts.wide ? ' wide' : '') }, h('span', {}, label), input);
}

function render() {
  renderList();
  const main = $('main'); main.innerHTML = '';
  if (!S.draft) { main.append(h('div', { class: 'empty' }, 'Elige una campaña a la izquierda o crea una nueva.')); renderIssues(); renderAi(); return; }
  main.append(h('div', { class: 'tabs' },
    h('button', { class: S.tab === 'form' ? 'on' : '', onclick: () => switchTab('form') }, '📝 Formulario'),
    h('button', { class: S.tab === 'json' ? 'on' : '', onclick: () => switchTab('json') }, '{ } JSON')));
  if (S.tab === 'json') renderJson(main); else renderForm(main);
  renderIssues(); renderAi();
}

function switchTab(t) {
  if (t === S.tab) return;
  if (S.tab === 'json' && !applyJson()) return;
  S.tab = t; render();
}
function renderJson(main) {
  const ta = h('textarea', { id: 'json', spellcheck: 'false', oninput: () => { S.jsonDirty = true; setStatus('JSON editado (se aplica al cambiar de pestaña o guardar)'); } });
  ta.value = JSON.stringify(S.draft, null, 2);
  S.jsonDirty = false;
  main.append(h('p', { class: 'hint' }, 'Edición directa de la campaña. Aquí van también las plantillas por personaje (templates, pair_templates) y la cadena (chain). Formato del motor: ', h('a', { href: '#', onclick: (e) => { e.preventDefault(); alert(S.doc); } }, 'ver documentación')), ta);
}
function applyJson() {
  if (S.tab !== 'json' || !S.jsonDirty) return true;
  try {
    const v = JSON.parse($('json').value);
    if (!v || typeof v !== 'object' || Array.isArray(v)) throw new Error('debe ser un objeto');
    S.draft = v; S.jsonDirty = false; markDirty(); return true;
  } catch (e) { setStatus('JSON no válido: ' + e.message, 'err'); return false; }
}

function renderForm(main) {
  const d = S.draft;
  const afterOpts = [['', '— (se abre con la primera campaña)']].concat(S.list.filter((c) => c.id !== S.sel).map((c) => [c.id, c.title + ' (' + c.id + ')']));
  main.append(h('h2', {}, 'Campaña'),
    h('div', { class: 'grid' },
      field(d, 'title', 'text', 'Título', { max: 60, after: renderList }),
      field(d, 'id', 'text', 'Id (minúsculas y _)', { after: renderList }),
      field(d, 'after', 'select', 'Se abre después de', { options: afterOpts }),
      field(d, 'unlock', 'int', 'Misiones hechas para abrirla', { keep: true }),
      field(d, 'parallel', 'check', 'Todas abiertas a la vez (parallel)')));
  const extras = ['templates', 'pair_templates', 'chain'].filter((k) => d[k]);
  if (extras.length) {
    const nt = Object.keys(d.templates || {}).length + Object.keys(d.pair_templates || {}).length;
    main.append(h('div', { class: 'note' }, `Esta campaña genera misiones por personaje del perfil (${nt ? nt + ' plantillas' : ''}${nt && d.chain ? ' y ' : ''}${d.chain ? 'cadena «' + (d.chain.id || 'chain') + '»' : ''}). `,
      'Se editan en la pestaña JSON; aquí solo aparecen las misiones fijas.'));
  }
  const ms = d.missions = d.missions || [];
  main.append(h('div', { class: 'row', style: 'margin-top:14px' }, h('h2', { style: 'margin:0;flex:1' }, `Misiones (${ms.length})`),
    h('button', { class: 'ghost', onclick: () => { ms.forEach((m) => S.open.add(m.id)); render(); } }, 'Abrir todas'),
    h('button', { class: 'ghost', onclick: () => { S.open.clear(); render(); } }, 'Cerrar todas')));
  if (!ms.length) main.append(h('div', { class: 'empty' }, 'Sin misiones fijas todavía.'));
  const errIdx = missionErrorIndexes();
  ms.forEach((m, i) => main.append(renderMission(m, i, ms, errIdx.has(i + 1))));
  main.append(h('div', { class: 'row', style: 'margin-top:10px' },
    h('button', { class: 'primary', onclick: () => addMission() }, '＋ Misión nueva')));
}

function missionErrorIndexes() {
  const s = new Set();
  for (const e of S.issues.errors) { const m = e.match(/^missió (\d+)/); if (m) s.add(+m[1]); }
  return s;
}

function uniqueId(base) {
  const used = new Set();
  for (const c of S.list) if (c.id !== S.sel) used.add('chapter:' + c.id);
  (S.draft.missions || []).forEach((m) => used.add(m.id));
  let id = base, n = 2;
  while (used.has(id)) id = base + '_' + n++;
  return id;
}
function addMission() {
  const id = uniqueId((S.draft.id || 'missio') + '_' + ((S.draft.missions || []).length + 1));
  S.draft.missions.push({ id, cat: 'nav', title: 'Missió nova', xp: 30, coins: 5, intro: ['…'],
    steps: [{ type: 'goto', target: 'area:Plaça Major', radius: 40, text: 'Ves a la Plaça Major' }] });
  S.open.add(id); markDirty(); render();
}

function move(arr, i, d) { const j = i + d; if (j < 0 || j >= arr.length) return; [arr[i], arr[j]] = [arr[j], arr[i]]; markDirty(); render(); }

function renderMission(m, i, arr, hasErr) {
  const open = S.open.has(m.id);
  const card = h('div', { class: 'mission' + (hasErr ? ' err' : ''), style: `--c: var(--${m.cat || 'line'})`, 'data-i': i + 1 });
  const head = h('div', { class: 'head', onclick: (e) => { if (e.target.closest('button')) return; open ? S.open.delete(m.id) : S.open.add(m.id); render(); } },
    h('span', { class: 'n' }, i + 1 + '.'),
    h('span', { class: 'ttl' }, m.title || '(sin título)'),
    h('span', { class: 'id' }, m.id),
    h('span', { class: 'n' }, (m.steps || []).length + ' pasos'),
    h('button', { class: 'ghost', title: 'Subir', onclick: () => move(arr, i, -1) }, '↑'),
    h('button', { class: 'ghost', title: 'Bajar', onclick: () => move(arr, i, 1) }, '↓'),
    h('button', { class: 'ghost', title: 'Duplicar', onclick: () => { const c = clone(m); c.id = uniqueId(m.id + '_copia'); arr.splice(i + 1, 0, c); S.open.add(c.id); markDirty(); render(); } }, '⧉'),
    h('button', { class: 'ghost', title: 'Borrar', onclick: () => { if (confirm('¿Borrar la misión «' + m.title + '»?')) { arr.splice(i, 1); markDirty(); render(); } } }, '🗑️'),
    h('span', { class: 'n' }, open ? '▾' : '▸'));
  card.append(head);
  if (!open) return card;
  const oldId = m.id;
  const body = h('div', { class: 'body' },
    h('div', { class: 'grid' },
      field(m, 'title', 'text', 'Título', { max: 60, after: () => { card.querySelector('.ttl').textContent = m.title || ''; } }),
      field(m, 'id', 'text', 'Id', { after: () => { S.open.delete(oldId); S.open.add(m.id); card.querySelector('.id').textContent = m.id; } }),
      field(m, 'cat', 'select', 'Categoría', { options: Object.entries(CAT_LABEL), after: () => card.style.setProperty('--c', `var(--${m.cat})`) }),
      field(m, 'xp', 'int', 'XP', { keep: true }),
      field(m, 'coins', 'int', 'Monedas', { keep: true }),
      field(m, 'min_level', 'int', 'Nivel mínimo', { min: 1 }),
      field(m, 'give', 'item', 'Da al empezar'),
      field(m, 'give_coins', 'int', 'Monedas al empezar', { min: 1 }),
      field(m, 'reward_item', 'item', 'Premio al acabar'),
      field(m, 'needs', 'check', 'Solo si el jugador tiene casa', { is: (v) => v === 'home', map: (c) => (c ? 'home' : '') }),
      field(m, 'intro', 'lines', 'Introducción (una frase por línea, en catalán)', { wide: true })),
    h('h2', {}, 'Pasos'));
  const steps = m.steps = m.steps || [];
  steps.forEach((s, si) => body.append(renderStep(s, si, steps)));
  body.append(h('div', { class: 'row' },
    h('select', { id: 'newStep' + i }, ...Object.entries(STEP_LABEL).map(([k, l]) => h('option', { value: k }, l))),
    h('button', { onclick: () => { const t = $('newStep' + i).value; steps.push({ type: t, text: '' }); markDirty(); render(); } }, '＋ Paso')));
  card.append(body);
  return card;
}

function renderStep(s, si, steps) {
  const spec = S.ref.step_types[s.type] || { required: [], optional: [], what: '' };
  const box = h('div', { class: 'step' });
  box.append(h('div', { class: 'shead' },
    h('span', { class: 'num' }, 'Paso ' + (si + 1)),
    h('select', { onchange: (e) => { s.type = e.target.value; markDirty(); render(); } },
      ...Object.entries(STEP_LABEL).map(([k, l]) => h('option', { value: k, selected: k === s.type }, l))),
    h('span', { class: 'what' }, spec.what),
    h('button', { class: 'ghost', title: 'Subir', onclick: () => move(steps, si, -1) }, '↑'),
    h('button', { class: 'ghost', title: 'Bajar', onclick: () => move(steps, si, 1) }, '↓'),
    h('button', { class: 'ghost', title: 'Borrar paso', onclick: () => { steps.splice(si, 1); markDirty(); render(); } }, '🗑️')));
  const keys = ['text', ...spec.required, ...spec.optional.filter((k) => !['text'].includes(k))];
  // done_text solo tiene sentido al entregar; se enseña igualmente si ya trae algo
  const shown = [...new Set(keys)].filter((k) => k !== 'done_text' || s.type === 'deliver' || s.done_text);
  const grid = h('div', { class: 'grid' });
  for (const k of shown) {
    const [kind, label] = FIELD[k] || ['text', k];
    const req = spec.required.includes(k);
    const wide = k === 'text' || kind === 'lines';
    grid.append(field(s, k, kind, label + (req ? ' *' : ''), { wide, min: k === 'count' || k === 'radius' ? 1 : 0 }));
  }
  box.append(grid);
  return box;
}

// ---------------------------------------------------------------- validación en vivo
let vTimer = null, vSeq = 0;
function scheduleValidate() { clearTimeout(vTimer); vTimer = setTimeout(validateNow, 500); }
async function validateNow() {
  if (!S.draft) return;
  const seq = ++vSeq;
  try {
    const j = await api('POST', '/api/campaigns/validate', { campaign: S.draft, id: S.isNew ? null : S.sel });
    if (seq !== vSeq) return;
    S.issues = { errors: j.errors, warnings: j.warnings };
    renderIssues(); renderList();
    document.querySelectorAll('.mission').forEach((c) => c.classList.toggle('err', missionErrorIndexes().has(+c.dataset.i)));
  } catch (e) { if (seq === vSeq) $('issues').textContent = 'No se puede validar: ' + e.message; }
}
function renderIssues() {
  const box = $('issues'); box.innerHTML = '';
  if (!S.draft) { box.textContent = '—'; return; }
  const { errors, warnings } = S.issues;
  if (!errors.length && !warnings.length) { box.append(h('div', { class: 'ok' }, '✓ Todo correcto')); return; }
  const go = (t) => {
    const m = t.match(/^missió (\d+)/); if (!m) return;
    const mm = S.draft.missions[+m[1] - 1]; if (!mm) return;
    if (S.tab !== 'form') { if (!applyJson()) return; S.tab = 'form'; }
    S.open.add(mm.id); render();
    document.querySelector(`.mission[data-i="${m[1]}"]`)?.scrollIntoView({ behavior: 'smooth', block: 'start' });
  };
  if (errors.length) box.append(h('div', { class: 'hint' }, `${errors.length} errores (impiden guardar):`));
  for (const e of errors) box.append(h('div', { class: 'e', onclick: () => go(e) }, e));
  if (warnings.length) box.append(h('div', { class: 'hint', style: 'margin-top:6px' }, `${warnings.length} avisos:`));
  for (const w of warnings) box.append(h('div', { class: 'w', onclick: () => go(w) }, w));
}

// ---------------------------------------------------------------- guardar, borrar, ordenar, nueva
async function save() {
  if (!S.draft) return false;
  if (!applyJson()) return false;
  const target = S.isNew ? S.draft.id : S.sel;
  if (!target || !/^[a-z][a-z0-9_]{1,39}$/.test(target)) { setStatus('Pon un id válido a la campaña (minúsculas y _)', 'err'); return false; }
  if (S.isNew && S.list.some((c) => c.id === target)) { setStatus('Ya existe una campaña con id «' + target + '»', 'err'); return false; }
  setStatus('Guardando…');
  try {
    if (!S.rev) await api('GET', '/api/campaigns');
    const j = await api('PUT', '/api/campaigns/' + target, S.draft);
    dropDraft(S.sel); dropDraft(target);
    S.dirty = false; S.isNew = false;
    await loadList();
    await openCampaign(S.draft.id, true);
    setStatus('Guardado ✓' + (j.warnings.length ? ` (${j.warnings.length} avisos)` : '') + ' · publica para verlo en el juego', 'ok');
    return true;
  } catch (e) {
    setStatus(e.message, 'err');
    if (/canviat|409/.test(e.message)) stashDraft();
    return false;
  }
}
function newCampaign() {
  if (S.dirty && !confirm('Hay cambios sin guardar. ¿Descartarlos?')) return;
  let id = 'campanya_nova', n = 2;
  while (S.list.some((c) => c.id === id)) id = 'campanya_nova_' + n++;
  S.sel = id; S.isNew = true; S.saved = null; S.ai = null; S.open.clear();
  S.draft = { id, title: 'Campanya nova', after: S.list.length ? S.list[S.list.length - 1].id : undefined, unlock: 1, missions: [] };
  if (!S.draft.after) delete S.draft.after;
  S.dirty = true; S.tab = 'form';
  setStatus('Campaña nueva sin guardar');
  render(); scheduleValidate();
}
async function delCampaign() {
  if (!S.sel) return;
  if (S.isNew) { S.draft = null; S.sel = null; S.isNew = false; S.dirty = false; render(); return; }
  if (!confirm('¿Borrar la campaña «' + S.sel + '» de data/missions.json? (queda copia en data/.history/)')) return;
  try {
    await api('GET', '/api/campaigns');
    await api('DELETE', '/api/campaigns/' + S.sel);
    dropDraft(S.sel);
    S.draft = null; S.sel = null; S.dirty = false;
    await loadList(); render();
    setStatus('Campaña borrada · publica para quitarla del juego', 'ok');
  } catch (e) { setStatus(e.message, 'err'); }
}
async function moveCampaign(d) {
  if (!S.sel || S.isNew) return;
  const ids = S.list.map((c) => c.id), i = ids.indexOf(S.sel), j = i + d;
  if (i < 0 || j < 0 || j >= ids.length) return;
  if ((i === 0 || j === 0) && !confirm('La primera campaña es la que está abierta al empezar el juego. ¿Cambiarla?')) return;
  [ids[i], ids[j]] = [ids[j], ids[i]];
  try {
    await api('GET', '/api/campaigns');
    await api('POST', '/api/campaigns/order', { ids });
    await loadList();
    setStatus('Orden guardado', 'ok');
  } catch (e) { setStatus(e.message, 'err'); }
}

// ---------------------------------------------------------------- exportar
async function exportDoc() {
  if (S.isNew) throw new Error('Guarda la campaña nueva antes de exportarla');
  if (S.dirty && !confirm('Hay cambios sin guardar: se exportará la versión guardada. ¿Seguir?')) return null;
  return api('GET', '/api/campaigns/' + S.sel + '/export');
}
async function download() {
  try {
    const doc = await exportDoc(); if (!doc) return;
    const blob = new Blob([JSON.stringify(doc, null, 2)], { type: 'application/json' });
    const a = h('a', { href: URL.createObjectURL(blob), download: `roda-campanya-${S.sel}-${new Date().toISOString().slice(0, 10)}.json` });
    document.body.append(a); a.click(); a.remove();
    setTimeout(() => URL.revokeObjectURL(a.href), 5000);
    setStatus('Descargado ✓', 'ok');
  } catch (e) { setStatus(e.message, 'err'); }
}
async function copyForLlm() {
  try {
    const doc = await exportDoc(); if (!doc) return;
    const text = JSON.stringify(doc, null, 1);
    if (navigator.clipboard && window.isSecureContext) await navigator.clipboard.writeText(text);
    else {   // http:// en la red local: sin API de portapapeles, se copia desde un textarea temporal
      const ta = h('textarea', { style: 'position:fixed;top:-1000px;opacity:0' }); ta.value = text;
      document.body.append(ta); ta.select();
      const ok = document.execCommand('copy'); ta.remove();
      if (!ok) throw new Error('El navegador no deja copiar aquí: usa ⬇️ Descargar');
    }
    setStatus('Copiado ✓ · pégalo en el chat del LLM con lo que quieres cambiar', 'ok');
  } catch (e) { setStatus(e.name === 'NotAllowedError' ? 'El navegador no deja copiar aquí: usa ⬇️ Descargar' : e.message, 'err'); }
}

// ---------------------------------------------------------------- importar
function diffHtml(df) {
  if (!df) return '';
  const p = [];
  if (df.added.length) p.push(`<div class="a">＋ ${df.added.length} nuevas: ${df.added.map(esc).join(', ')}</div>`);
  if (df.removed.length) p.push(`<div class="r">－ ${df.removed.length} quitadas: ${df.removed.map(esc).join(', ')}</div>`);
  const ch = Object.entries(df.changed);
  if (ch.length) p.push(`<div class="c">✎ ${ch.length} cambiadas: ${ch.map(([k, v]) => esc(k) + ' <span class="hint">(' + v.map(esc).join(', ') + ')</span>').join('; ')}</div>`);
  if (df.chapter.length) p.push(`<div class="c">✎ campaña: ${df.chapter.map(esc).join(', ')}</div>`);
  if (df.reordered) p.push('<div class="c">↕ orden de misiones cambiado</div>');
  return `<div class="diff">${p.join('') || 'Sin cambios'}</div>`;
}
function issuesHtml(errors, warnings) {
  const e = errors.slice(0, 12).map((x) => `<div class="e">${esc(x)}</div>`).join('') + (errors.length > 12 ? `<div class="hint">… y ${errors.length - 12} más</div>` : '');
  const w = warnings.slice(0, 8).map((x) => `<div class="w">${esc(x)}</div>`).join('') + (warnings.length > 8 ? `<div class="hint">… y ${warnings.length - 8} avisos más</div>` : '');
  return `<div class="issues" style="margin-top:6px">${errors.length ? `<div class="hint">${errors.length} errores (puedes cargarlo y corregirlo antes de guardar):</div>` + e : '<div class="ok">✓ Sin errores</div>'}${w}</div>`;
}
function openImport() {
  S.imp = null; $('impText').value = ''; $('impFile').value = ''; $('impResult').innerHTML = ''; $('impApply').disabled = true;
  $('dlgImport').showModal();
}
async function checkImport() {
  let doc;
  try { doc = JSON.parse($('impText').value.replace(/^\s*```(?:json)?\s*|\s*```\s*$/g, '')); }
  catch (e) { $('impResult').innerHTML = `<div class="warn" style="color:var(--danger)">JSON no válido: ${esc(e.message)}</div>`; return; }
  const isPatch = doc && (doc.format === 'roda-rpg-campaign-patch' || (doc.upsert && !doc.campaign && !doc.missions));
  if (isPatch && !S.draft) { $('impResult').innerHTML = '<div style="color:var(--danger)">Un parche se aplica sobre la campaña abierta: abre una primero.</div>'; return; }
  try {
    const j = await api('POST', '/api/campaigns/import', { doc, base: isPatch ? S.draft : undefined, id: isPatch ? S.sel : undefined });
    S.imp = j;
    const c = j.campaign;
    $('impResult').innerHTML = `<p><b>${esc(c.title || '(sin título)')}</b> <code>${esc(c.id)}</code> — ${(c.missions || []).length} misiones · `
      + (isPatch ? 'parche sobre la campaña abierta' : j.exists ? 'sustituye a la campaña existente' : 'campaña nueva') + '</p>'
      + (j.notes ? `<p class="hint">Notas: ${esc(j.notes)}</p>` : '') + diffHtml(j.diff) + issuesHtml(j.errors, j.warnings);
    $('impApply').disabled = false;
  } catch (e) { $('impResult').innerHTML = `<div style="color:var(--danger)">${esc(e.message)}</div>`; }
}
async function applyImport() {
  const j = S.imp; if (!j) return;
  const c = j.campaign;
  const target = S.list.find((x) => x.id === c.id);
  if (S.dirty && S.sel !== c.id && !confirm('Hay cambios sin guardar en la campaña abierta. ¿Descartarlos?')) return;
  $('dlgImport').close();
  if (target) { await openCampaign(c.id, true); S.draft = clone(c); }
  else { S.sel = c.id; S.isNew = true; S.saved = null; S.draft = clone(c); }
  S.open.clear(); (j.diff?.added || []).concat(Object.keys(j.diff?.changed || {})).forEach((id) => S.open.add(id));
  S.tab = 'form'; markDirty(); render();
  setStatus('Importado en el editor: revisa y 💾 guarda', 'ok');
}

// ---------------------------------------------------------------- IA
const AI_PRESETS = [
  ['＋3 misiones', 'Afegeix 3 missions noves que continuïn la història de la campanya, en llocs reals diferents del poble.'],
  ['Textos más vivos', 'Millora els textos (intro, passos, diàlegs) perquè siguin més divertits i clars per a un infant de 7 anys, sense canviar la mecànica.'],
  ['Seguridad vial', 'Afegeix 2 missions que ensenyin seguretat viària (passos de vianants, semàfors) integrades a la història.'],
  ['Revisar coherencia', 'Revisa la coherència: que cada objecte que es lliura s\'hagi aconseguit abans, recompenses equilibrades (xp i monedes) i dificultat creixent. Corregeix el que calgui.'],
  ['Misión con cofre', 'Afegeix una missió on calgui trobar un cofre (chest) de la referència i portar el que conté a algú del poble.'],
];
function renderAi() {
  const chips = $('aiChips');
  if (!chips.childElementCount) for (const [l, t] of AI_PRESETS) chips.append(h('button', { onclick: () => { $('aiText').value = t; $('aiText').focus(); } }, l));
  $('btnAi').disabled = !S.draft || !!S.aiBusy;
  const box = $('aiResult');
  if (S.aiBusy) { box.innerHTML = '<p class="hint"><span class="spin">✨</span> Pensando… (IA del hub, 5–60 s)</p>'; return; }
  if (!S.ai) { box.innerHTML = ''; return; }
  const a = S.ai;
  box.innerHTML = (a.notes ? `<p>${esc(a.notes)}</p>` : '') + diffHtml(a.diff) + issuesHtml(a.errors, a.warnings)
    + `<p class="hint">${a.attempts > 1 ? 'La IA corrigió su primera propuesta. ' : ''}${(a.models || []).length ? 'Modelo: ' + esc([...new Set(a.models)].join(' → ')) + '. ' : ''}${a.tokens ? a.tokens + ' tokens.' : ''}</p>`;
  box.append(h('div', { class: 'row' },
    h('button', { class: 'primary', onclick: () => {
      S.draft = clone(a.campaign); S.ai = null;
      (a.diff.added || []).concat(Object.keys(a.diff.changed || {})).forEach((id) => S.open.add(id));
      S.tab = 'form'; markDirty(); render(); setStatus('Cambios de la IA aplicados al borrador: revisa y 💾 guarda', 'ok');
    } }, 'Aplicar al borrador'),
    h('button', { onclick: () => { S.ai = null; renderAi(); } }, 'Descartar')));
}
async function runAi() {
  if (!S.draft || S.aiBusy) return;
  if (!applyJson()) return;
  const instruction = $('aiText').value.trim();
  if (instruction.length < 3) { setStatus('Escribe qué quieres que haga la IA', 'err'); $('aiText').focus(); return; }
  S.aiBusy = true; S.ai = null; renderAi();
  try { S.ai = await api('POST', '/api/campaigns/llm', { campaign: S.draft, instruction }); }
  catch (e) { setStatus(e.message, 'err'); }
  finally { S.aiBusy = false; renderAi(); }
}

// ---------------------------------------------------------------- publicar
async function publish() {
  if (S.dirty && !(await save())) return;
  try { await api('POST', '/api/publish'); } catch (e) { setStatus(e.message, 'err'); return; }
  $('btnPublish').disabled = true;
  setStatus('Publicando… (1–3 min)');
  const poll = async () => {
    let st;
    try { st = await api('GET', '/api/publish'); } catch (e) { setTimeout(poll, 3000); return; }
    $('log').textContent = st.log.join('\n') || '…';
    $('log').scrollTop = 1e9;
    if (st.running) { setTimeout(poll, 2000); return; }
    $('btnPublish').disabled = false;
    setStatus(st.ok ? 'Publicado ✓ · recarga el juego para verlo' : 'La publicación ha fallado (mira el registro)', st.ok ? 'ok' : 'err');
  };
  poll();
}

// ---------------------------------------------------------------- arranque
async function init() {
  $('btnSave').onclick = save;
  $('btnPublish').onclick = publish;
  $('btnNew').onclick = newCampaign;
  $('btnImport').onclick = openImport;
  $('btnDel').onclick = delCampaign;
  $('btnUp').onclick = () => moveCampaign(-1);
  $('btnDown').onclick = () => moveCampaign(1);
  $('btnDownload').onclick = download;
  $('btnCopy').onclick = copyForLlm;
  $('btnAi').onclick = runAi;
  $('impCheck').onclick = checkImport;
  $('impApply').onclick = applyImport;
  $('impFile').onchange = async (e) => { const f = e.target.files[0]; if (f) { $('impText').value = await f.text(); checkImport(); } };
  document.addEventListener('keydown', (e) => { if ((e.ctrlKey || e.metaKey) && e.key === 's') { e.preventDefault(); save(); } });
  window.addEventListener('beforeunload', (e) => { if (S.dirty) { stashDraft(); e.preventDefault(); e.returnValue = ''; } });
  try {
    await loadRef();
    await loadList();
    const want = decodeURIComponent(location.hash.slice(1));
    const first = S.list.find((c) => c.id === want) || S.list[0];
    if (first) await openCampaign(first.id, true); else render();
  } catch (e) {
    setStatus(e.message, 'err');
    $('main').innerHTML = `<div class="empty">No se pueden cargar las campañas: ${esc(e.message)}<br><br><button onclick="location.reload()">Reintentar</button></div>`;
  }
}
init();
