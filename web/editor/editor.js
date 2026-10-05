// Editor de zonas especiales de Roda RPG. Lee el mapa compilado (/data), edita
// maps/source/zones/<id>.json por la API (/api/zones) y publica (/api/publish).
'use strict';

const T = 16, CHUNK = 32, CPX = T * CHUNK, SCENE = 'overworld';
const LAYERS = ['ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead'];
const EDIT_LAYERS = [
  { key: 'ground', label: 'Suelo' }, { key: 'detail', label: 'Detalle' },
  { key: 'structures', label: 'Estructuras' }, { key: 'overhead', label: 'Por encima' },
  { key: 'height', label: 'Altura' }, { key: 'objects', label: 'Objetos' },
];
const TOOLS = [
  { key: 'brush', label: '✏️', title: 'Pincel (B)' }, { key: 'rect', label: '▭', title: 'Rectángulo (R)' },
  { key: 'fill', label: '🪣', title: 'Relleno (F)' }, { key: 'erase', label: '🧽', title: 'Goma (E)' },
  { key: 'pick', label: '💧', title: 'Cuentagotas (I)' }, { key: 'build', label: '🏠', title: 'Edificio' },
  { key: 'select', label: '✋', title: 'Seleccionar / mover objetos' }, { key: 'pan', label: '🧭', title: 'Mover la vista' },
];
const OBJ_TYPES = {
  door: { icon: '🚪', label: 'Puerta', where: 'ext' }, npc: { icon: '🧑', label: 'Personaje', where: 'both' },
  sign: { icon: '🪧', label: 'Cartel', where: 'both' }, spawn: { icon: '📍', label: 'Punto de aparición', where: 'ext' },
  exit: { icon: '⬇️', label: 'Salida', where: 'int' },
};
const NPC_SPRITES = ['npc_archaeologist', 'npc_gardener', 'npc_smith', 'npc_sailor', 'npc_musician', 'npc_librarian', 'npc_miner', 'npc_cook', 'npc_teacher', 'npc_elder', 'npc_girl', 'npc_baker', 'npc_fisher', 'npc_ranger', 'npc_postie', 'npc_tourist', 'npc_kid', 'npc_lady', 'npc_police', 'npc_doctor', 'npc_clerk', 'npc_coach', 'npc_builder', 'npc_builder2', 'npc_cat_orange', 'npc_cat_grey'];
const SCALES = [0.125, 0.25, 0.5, 1, 1.5, 2, 3, 4, 6];
const HEIGHT_COLORS = ['rgba(0,0,0,0)', 'rgba(230,189,107,.28)', 'rgba(226,109,92,.32)', 'rgba(170,110,220,.36)'];
const ID_RE = /^[a-z0-9_]{2,40}$/;

const $ = (id) => document.getElementById(id);
const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'on') for (const [ev, fn] of Object.entries(v)) e.addEventListener(ev, fn);
    else if (k in e && k !== 'list') e[k] = v; else e.setAttribute(k, v);
  }
  for (const k of kids) e.append(k);
  return e;
};

// ---------------------------------------------------------------- estado
const S = {
  tiles: null, byId: [], atlas: null, minimap: null, sprites: {}, lines: [], families: {},
  palette: [], zones: [], zone: null, areaKey: 'ext', dirty: false,
  tool: 'brush', layer: 'ground', brush: 1, height: 1, objType: 'npc', pal: null,
  cam: { x: 0, y: 0 }, scale: 2, undo: [], redo: [], sel: null, hover: null, drag: null,
  newZone: false, space: false, chunks: new Map(), view: { grid: true, height: true, trace: false },
  npcs: [], npcMode: false, selNpc: null, chat: null,
  newKind: 'zone', mapEdits: { cells: {} }, patchBase: null, polyEdit: null,
};

// ---------------------------------------------------------------- formas poligonales
function inPoly(poly, x, y) {
  let ins = false;
  for (let i = 0, j = poly.length - 1; i < poly.length; j = i++) {
    const [xi, yi] = poly[i], [xj, yj] = poly[j];
    if ((yi > y) !== (yj > y) && x < xi + (y - yi) * (xj - xi) / ((yj - yi) || 1e-9)) ins = !ins;
  }
  return ins;
}
function polyPath(g, poly, ox, oy, k) {
  g.beginPath();
  poly.forEach(([x, y], i) => (i ? g.lineTo : g.moveTo).call(g, ox + x * k, oy + y * k));
  g.closePath();
}

function setStatus(t, cls) { const s = $('status'); s.textContent = t; s.style.color = cls === 'err' ? 'var(--danger)' : cls === 'ok' ? 'var(--ok)' : ''; }
const revisions=new Map();
async function api(method, url, body) {
  const headers={'X-Roda-Request':'1'};
  if(method==='PUT'||method==='DELETE')headers['If-Match']=revisions.get(url)||'"missing"';
  if(body!==undefined)headers['Content-Type']='application/json';
  const send=()=>fetch(url,{method,headers,body:body!==undefined?JSON.stringify(body):undefined,signal:AbortSignal.timeout(20000)});
  let r=await send();
  if(r.status===401 && await window.RodaAdult.ensure())r=await send();
  const j=await r.json().catch(()=>({}));
  if(!r.ok)throw new Error(j.error||'No es pot completar la petició');
  if(r.headers.get('ETag'))revisions.set(url,r.headers.get('ETag'));
  return j;
}
const loadImg = (src) => new Promise((ok, ko) => { const i = new Image(); i.onload = () => ok(i); i.onerror = ko; i.src = src; });

// ---------------------------------------------------------------- tiles y familias
function buildTileIndex() {
  for (const [name, t] of Object.entries(S.tiles)) S.byId[t.id] = name;
  // familias autotile: base_<máscara 0..15> o base_<máscara>_0 (agua animada)
  const count = {};
  for (const name of Object.keys(S.tiles)) {
    let m = name.match(/^((?:sea|pool))_(\d+)_0$/);
    if (m) { (count[m[1]] = count[m[1]] || { kind: 'anim', n: 0 }).n++; continue; }
    m = name.match(/^([a-z]+_[a-z0-9]+)_(\d+)$/);
    if (m && +m[2] < 16) (count[m[1]] = count[m[1]] || { kind: 'auto', n: 0 }).n++;
  }
  for (const [base, c] of Object.entries(count)) {
    if (c.n === 16 && S.tiles[famName({ base, kind: c.kind }, 0)]) {
      S.families[base] = { base, kind: c.kind, edge: /^(d_|sea|pool)/.test(base), roof: base.startsWith('r_') };
    }
  }
}
function famName(f, m) { return f.kind === 'anim' ? `${f.base}_${m}_0` : `${f.base}_${m}`; }
function famOf(name) {
  if (!name) return null;
  let m = name.match(/^((?:sea|pool))_(\d+)_0$/) || name.match(/^([a-z]+_[a-z0-9]+)_(\d+)$/);
  return m && S.families[m[1]] && +m[2] < 16 ? S.families[m[1]] : null;
}
const tileProp = (name, p) => !!(name && S.tiles[name] && S.tiles[name][p]);

function suggestedLayer(name) {
  if (/_top$/.test(name)) return 'overhead';
  if (/^(g_|sea|pool|st_|i_floor|i_rug|i_exit)/.test(name)) return 'ground';
  if (/^d_/.test(name)) return 'detail';
  return 'structures';
}

function buildPalette() {
  const cats = [
    ['Suelo', (n) => /^g_/.test(n)],
    ['Caminos y pavimento', (n) => /^d_/.test(n) && !/^d_(rail|railhs|pending|tunnel|bridge|bridgemoto|pier)/.test(n)],
    ['Edificios', (n) => /^(r_|f_)/.test(n)],
    ['Muros y vallas', (n) => /^w_|^o_fence/.test(n)],
    ['Mobiliario y árboles', (n) => /^(o_|bush|tree)/.test(n) && n !== 'o_fence'],
    ['Agua', (n) => /^(sea|pool)/.test(n)],
    ['Escaleras', (n) => /^st_/.test(n)],
    ['Interior', (n) => /^i_/.test(n)],
    ['Otros', () => true],
  ];
  const seenFam = new Set(), used = new Set();
  const groups = cats.map(([label]) => ({ label, items: [] }));
  const names = Object.keys(S.tiles).sort((a, b) => S.tiles[a].id - S.tiles[b].id);
  for (const n of names) {
    if (/_top$/.test(n) && /^tree/.test(n)) continue;
    if (/^(sea|pool)_\d+_[1-9]$/.test(n)) continue;
    const ci = cats.findIndex(([, f]) => f(n));
    const fam = famOf(n);
    if (fam) {
      if (seenFam.has(fam.base)) continue;
      seenFam.add(fam.base);
      groups[ci].items.push({ kind: 'auto', fam, label: `${fam.base} (se ajusta solo)`, preview: famName(fam, fam.edge ? 15 : 0) });
      continue;
    }
    if (/^tree_.*_bot$/.test(n)) {
      const top = n.replace(/_bot$/, '_top');
      groups[ci].items.push({ kind: 'stamp', label: n.replace(/_bot$/, '') + ' (2 casillas)', preview: n,
        cells: [{ dx: 0, dy: 0, layer: 'structures', t: n }, { dx: 0, dy: -1, layer: 'overhead', t: top }] });
      continue;
    }
    if (used.has(n)) continue;
    used.add(n);
    groups[ci].items.push({ kind: 'tile', name: n, label: n, preview: n });
  }
  S.palette = groups.filter((g) => g.items.length);
  const sel = $('palCat');
  sel.innerHTML = '';
  S.palette.forEach((g, i) => sel.append(el('option', { value: i, textContent: `${g.label} (${g.items.length})` })));
  sel.onchange = renderPalette;
  renderPalette();
}

function drawTile(ctx, name, x, y, size = T) {
  const t = S.tiles[name];
  if (!t) return;
  const id = t.id;
  ctx.drawImage(S.atlas, (id % 32) * T, Math.floor(id / 32) * T, T, T, x, y, size, size);
}

function renderPalette() {
  const g = S.palette[+$('palCat').value || 0];
  const box = $('palette');
  box.innerHTML = '';
  for (const it of g.items) {
    const c = el('canvas', { width: 32, height: 32, title: it.label });
    const ctx = c.getContext('2d');
    ctx.imageSmoothingEnabled = false;
    drawTile(ctx, it.preview, 0, 0, 32);
    if (it === S.pal) c.classList.add('sel');
    c.onclick = () => selectPal(it);
    box.append(c);
  }
}
function selectPal(it, keepLayer) {
  S.pal = it;
  $('palname').textContent = it.label;
  if (!keepLayer && S.layer !== 'height' && S.layer !== 'objects') {
    setLayer(it.kind === 'stamp' ? 'structures' : suggestedLayer(it.kind === 'auto' ? it.preview : it.name));
  }
  if (!['brush', 'rect', 'fill'].includes(S.tool)) setTool('brush');
  renderPalette();
}

// ---------------------------------------------------------------- áreas (zona exterior o interior)
function area() {
  if (!S.zone) return null;
  return S.areaKey === 'ext' ? S.zone : S.zone.interiors[S.areaKey];
}
const isInterior = () => S.areaKey !== 'ext';
function areaOrigin() { return isInterior() || !S.zone ? { x: 0, y: 0 } : { x: S.zone.x * T, y: S.zone.y * T }; }
function normalizeArea(a, defGround) {
  const n = a.w * a.h;
  for (const k of ['ground', 'detail', 'structures', 'overhead']) {
    a[k] = Array.from({ length: n }, (_, i) => (a[k] && a[k][i]) || (k === 'ground' && defGround ? '' : ''));
  }
  a.height = Array.from({ length: n }, (_, i) => (a.height && +a.height[i]) || 0);
  a.objects = a.objects || [];
}
function blankArea(w, h, ground) {
  const n = w * h;
  return { w, h, ground: Array(n).fill(ground), detail: Array(n).fill(''), structures: Array(n).fill(''),
    overhead: Array(n).fill(''), height: Array(n).fill(0), objects: [] };
}
function interiorTemplate(name) {
  const w = 16, h = 12, a = blankArea(w, h, 'i_floor_wood_0');
  const put = (k, x, y, t) => { a[k][y * w + x] = t; };
  for (let x = 0; x < w; x++) { put('structures', x, 0, 'i_wall_top'); put('structures', x, 1, x % 5 === 2 ? 'i_wall_window' : 'i_wall'); }
  for (let y = 0; y < h; y++) { put('structures', 0, y, 'i_wall_top'); put('structures', w - 1, y, 'i_wall_top'); }
  const ex = Math.floor(w / 2);
  for (let x = 0; x < w; x++) if (x !== ex) put('structures', x, h - 1, 'i_wall_top');
  put('ground', ex, h - 1, 'i_exit');
  a.name = name;
  a.spawn = [ex, h - 2];
  a.objects = [{ type: 'exit', x: ex, y: h - 1 }];
  return a;
}

// celdas de talud: lindan con otra más baja (fuera = 0) y no son escalera (igual que tools/zones.py)
function cliffs(a) {
  const out = new Uint8Array(a.w * a.h);
  for (let y = 0; y < a.h; y++) for (let x = 0; x < a.w; x++) {
    const i = y * a.w + x, hv = a.height[i];
    if (!hv) continue;
    const stairs = ['ground', 'detail', 'structures'].some((k) => tileProp(a[k][i], 'stairs'));
    if (stairs) continue;
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const xx = x + dx, yy = y + dy;
      const nh = xx >= 0 && yy >= 0 && xx < a.w && yy < a.h ? a.height[yy * a.w + xx] : 0;
      if (nh < hv) { out[i] = 1; break; }
    }
  }
  return out;
}
// borde de roca: bits hacia los vecinos más bajos (N=1 E=2 S=4 W=8), igual que tools/zones.py
function cliffName(c, a, x, y) {
  let m = 0;
  const hv = a.height[y * a.w + x];
  [[1, 0, -1], [2, 1, 0], [4, 0, 1], [8, -1, 0]].forEach(([bit, dx, dy]) => {
    const xx = x + dx, yy = y + dy;
    const nh = xx < 0 || yy < 0 || xx >= a.w || yy >= a.h ? 0 : a.height[yy * a.w + xx];
    if (nh < hv) m |= bit;
  });
  return `w_ledge_${m}`;
}

// ---------------------------------------------------------------- edición
function snapshot() {
  if (!S.zone) return;  // en el mapa (personajes sueltos) no hay deshacer
  S.undo.push(JSON.stringify(S.zone));
  if (S.undo.length > 80) S.undo.shift();
  S.redo = [];
}
function restore(from, to) {
  if (!from.length) return;
  to.push(JSON.stringify(S.zone));
  S.zone = JSON.parse(from.pop());
  if (S.areaKey !== 'ext' && !S.zone.interiors[S.areaKey]) S.areaKey = 'ext';
  S.sel = null;
  markDirty();
  refreshAreaSel();
  renderProps();
}
function markDirty() { S.dirty = true; setStatus('Cambios sin guardar'); areaCache = null; validate(); draw(); }

function setCell(a, layer, x, y, val) {
  if (x < 0 || y < 0 || x >= a.w || y >= a.h) return false;
  const i = y * a.w + x;
  if (a[layer][i] === val) return false;
  a[layer][i] = val;
  return true;
}
function fixAuto(a, layer, x, y) {
  for (let yy = y - 1; yy <= y + 1; yy++) for (let xx = x - 1; xx <= x + 1; xx++) {
    if (xx < 0 || yy < 0 || xx >= a.w || yy >= a.h) continue;
    const i = yy * a.w + xx, f = famOf(a[layer][i]);
    if (!f) continue;
    let m = 0;
    [[1, 0, -1], [2, 1, 0], [4, 0, 1], [8, -1, 0]].forEach(([bit, dx, dy]) => {
      const nx = xx + dx, ny = yy + dy;
      if (nx < 0 || ny < 0 || nx >= a.w || ny >= a.h) { if (f.edge) m |= bit; return; }
      const nn = a[layer][ny * a.w + nx], nf = famOf(nn);
      if (nf && nf.base === f.base) m |= bit;
      else if (f.roof && bit === 4 && /^f_/.test(nn)) m |= bit;
    });
    a[layer][i] = famName(f, m);
  }
}
function paintCell(a, x, y, erase) {
  if (a === S.zone && a.poly && a.poly.length >= 3 && !inPoly(a.poly, x + 0.5, y + 0.5)) return false;
  if (S.layer === 'height') return setCell(a, 'height', x, y, erase ? 0 : S.height);
  if (S.layer === 'objects') return false;
  const it = S.pal;
  if (erase) {
    const ch = setCell(a, S.layer, x, y, '');
    if (ch) fixAuto(a, S.layer, x, y);
    return ch;
  }
  if (!it) return false;
  if (it.kind === 'stamp') {
    let ch = false;
    for (const c of it.cells) ch = setCell(a, c.layer, x + c.dx, y + c.dy, c.t) || ch;
    return ch;
  }
  if (it.kind === 'auto') {
    const cur = famOf(a[S.layer][y * a.w + x]);
    if (cur && cur.base === it.fam.base) return false;
    const ch = setCell(a, S.layer, x, y, famName(it.fam, 0));
    if (ch) fixAuto(a, S.layer, x, y);
    return ch;
  }
  // suelos con variantes (g_grass_0/1/2): se alternan para que el relleno no quede plano
  const mv = /^(g_[a-z]+)_\d+$/.exec(it.name);
  if (mv && S.tiles[mv[1] + '_1']) {
    const cur = a[S.layer][y * a.w + x];
    if (cur && cur.startsWith(mv[1] + '_')) return false;
    return setCell(a, S.layer, x, y, `${mv[1]}_${(x * 7 + y * 13) % 3}`);
  }
  return setCell(a, S.layer, x, y, it.name);
}
function inside(a, x, y) { return x >= 0 && y >= 0 && x < a.w && y < a.h; }
function brushAt(a, x, y, erase) {
  const r = S.brush - 1;
  let ch = false;
  for (let yy = y - Math.floor(r / 2); yy <= y + Math.ceil(r / 2); yy++)
    for (let xx = x - Math.floor(r / 2); xx <= x + Math.ceil(r / 2); xx++)
      if (inside(a, xx, yy)) ch = paintCell(a, xx, yy, erase) || ch;
  return ch;
}
function rectFill(a, r, erase) {
  for (let y = r.y0; y <= r.y1; y++) for (let x = r.x0; x <= r.x1; x++) if (inside(a, x, y)) paintCell(a, x, y, erase);
}
function cellKey(a, x, y) {
  const i = y * a.w + x;
  if (S.layer === 'height') return a.height[i];
  const v = a[S.layer][i], f = famOf(v);
  if (f) return 'fam:' + f.base;
  return /^g_[a-z]+_\d+$/.test(v || '') ? v.replace(/_\d+$/, '') : v;   // césped 0/1/2 = mismo césped
}
function floodFill(a, x, y, erase) {
  const k0 = cellKey(a, x, y);
  const seen = new Uint8Array(a.w * a.h), q = [[x, y]], cells = [];
  seen[y * a.w + x] = 1;
  while (q.length) {
    const [cx, cy] = q.pop();
    cells.push([cx, cy]);
    for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
      const nx = cx + dx, ny = cy + dy;
      if (!inside(a, nx, ny) || seen[ny * a.w + nx] || cellKey(a, nx, ny) !== k0) continue;
      seen[ny * a.w + nx] = 1;
      q.push([nx, ny]);
    }
  }
  for (const [cx, cy] of cells) paintCell(a, cx, cy, erase);
}
function pickAt(a, x, y) {
  const i = y * a.w + x;
  if (S.layer === 'height') { setHeight(a.height[i]); return; }
  const order = S.layer === 'objects' ? ['overhead', 'structures', 'detail', 'ground'] : [S.layer];
  for (const k of order) {
    const v = a[k][i];
    if (!v) continue;
    const f = famOf(v);
    for (const g of S.palette) for (const it of g.items) {
      if ((f && it.kind === 'auto' && it.fam.base === f.base) || (!f && (it.name === v || (it.kind === 'stamp' && it.cells[0].t === v)))) {
        $('palCat').value = S.palette.indexOf(g);
        setLayer(k);
        selectPal(it, true);
        return;
      }
    }
  }
}
function building(a, r) {
  const roof = $('bRoof').value, wall = $('bWall').value;
  const bw = r.x1 - r.x0 + 1, bh = r.y1 - r.y0 + 1;
  if (bh < 2) { setStatus('El edificio necesita al menos 2 filas', 'err'); return; }
  const fy = r.y1, doorX = r.x0 + Math.floor(bw / 2);
  // tejados de pendiente: vertiente norte, cumbrera en la fila central y vertiente sur (tools/buildings.py)
  const pitched = ['terra', 'brown', 'slate', 'stone'].includes(roof) && fy - r.y0 >= 2;
  const ridge = r.y0 + Math.floor((fy - 1 - r.y0) / 2);
  for (let y = r.y0; y < fy; y++) for (let x = r.x0; x <= r.x1; x++) {
    let m = 0;
    if (y > r.y0) m |= 1;
    if (x < r.x1) m |= 2;
    m |= 4; // la última fila de tejado continúa en la fachada
    if (x > r.x0) m |= 8;
    const part = pitched ? (y < ridge ? 'n_' : y === ridge ? 'k_' : 's_') : '';
    if (inside(a, x, y)) a.structures[y * a.w + x] = `r_${roof}_${part}${m}`;
  }
  for (let x = r.x0; x <= r.x1; x++) {
    const pos = bw === 1 ? 's' : x === r.x0 ? 'l' : x === r.x1 ? 'r' : 'm';
    if (inside(a, x, fy)) a.structures[fy * a.w + x] = `f_${wall}_${pos}_${x === doorX ? 'door' : 'win'}`;
  }
  if ($('bInterior').checked && !isInterior()) {
    const z = S.zone;
    let n = 1;
    while (z.interiors[`${z.id}_${n}_int`]) n++;
    const iid = `${z.id}_${n}_int`;
    z.interiors[iid] = interiorTemplate(`${z.name || z.id} ${n}`);
    a.objects.push({ type: 'door', x: doorX, y: fy, interior: iid });
    refreshAreaSel();
    setStatus(`Edificio con interior ${iid}`);
  }
}

// ---------------------------------------------------------------- objetos
function objAt(a, x, y) { return a.objects.find((o) => o.x === x && o.y === y); }
function placeObject(a, x, y) {
  const t = S.objType;
  if (OBJ_TYPES[t].where === 'ext' && isInterior()) return;
  if (OBJ_TYPES[t].where === 'int' && !isInterior()) return;
  const ex = objAt(a, x, y);
  if (ex) { S.sel = ex; renderProps(); return; }
  const o = { type: t, x, y };
  if (t === 'npc') Object.assign(o, { sprite: 'npc_elder', name: 'Veí', say: ['Hola!'], wander: 0, facing: 'down' });
  if (t === 'sign') o.say = ['Text del cartell'];
  if (t === 'spawn') o.name = `spawn_${S.zone.id}_${a.objects.length}`;
  if (t === 'door') {
    const ids = Object.keys(S.zone.interiors);
    o.interior = ids.find((iid) => !S.zone.objects.some((d) => d.type === 'door' && d.interior === iid)) || '';
  }
  a.objects.push(o);
  S.sel = o;
  renderProps();
}

// ---------------------------------------------------------------- mapa base (chunks + vectores)
async function inflate(buf) {
  const ds = new DecompressionStream('deflate');
  const out = new Response(new Blob([buf]).stream().pipeThrough(ds));
  return new Uint8Array(await out.arrayBuffer());
}
function decodeChunk(b) {
  if (b[0] !== 82 || b[1] !== 67 || b[2] !== 49) throw new Error('chunk desconocido');
  const w = b[3], h = b[4], mask = b[5] | (b[6] << 8), n = w * h;
  const c = { w, h };
  let p = 9;
  LAYERS.forEach((name, li) => {
    if (!(mask & (1 << li))) return;
    const t = new Uint16Array(n);
    for (let i = 0; i < n; i++, p += 2) t[i] = b[p] | (b[p + 1] << 8);
    c[name] = t;
  });
  return c;
}
// estilos de las vías: colores por nombre de la paleta común (data/palette.json, tools/pixel.py)
const VSTYLE_NAMES = {
  ROAD: [['white3', 2], ['white2', 0], ['asph', -8]], ROAD_MAIN: [['white3', 2], ['white2', 0], ['asph2', -8]],
  MOTORWAY: [['white3', 2], ['asph3', 0]], PEDESTRIAN: [['stone2', 2], ['white', 0]],
  FOOTWAY: [['stone2', 2], ['white', 0]], STEPS: [['stone2', 2], ['stone', 0]],
  PLATFORM: [['stone2', 2], ['white2', 0]], PATH: [['dry2', 0]], TRACK: [['dry3', 0], ['dry2', -8]],
  STREAM: [['stone', 0], ['sea2', -6]], TORRENT: [['stone3', 6], ['stone2', -2], ['sea2', -24]], RAIL: [['stone3', 16], ['stone2', 14], ['asph3', 2]],
  RAIL_HS: [['stone3', 16], ['stone2', 14], ['white3', 2]],
  ZEBRA: [null, null, ['white', -4]], SHADE: [null, null, ['rgba(20,15,26,.6)', 2]],
  PARAPET: [null, null, ['rgba(122,104,83,.0)', 0]], SHADOW: [['rgba(31,26,36,.35)', 6]],
};
const PAL_FALLBACK = { white: '#f6f1e3', white2: '#dcd3bf', white3: '#b2a790', asph: '#85827f', asph2: '#6c6a69',
  asph3: '#4a4749', stone: '#c9bba0', stone2: '#a6957a', stone3: '#786852', dry2: '#a68b62', dry3: '#806a4a', sea2: '#2e7a92' };
let VSTYLE = {};
function setVStyle(pal) {
  const col = (c) => (c && !c.startsWith('rgba') ? (pal[c] || PAL_FALLBACK[c] || c) : c);
  VSTYLE = {};
  for (const [k, v] of Object.entries(VSTYLE_NAMES)) VSTYLE[k] = v.map((e) => (e ? [col(e[0]), e[1]] : e));
}
setVStyle(PAL_FALLBACK);
function strokeLine(ctx, it, color, w) {
  const p = it.p;
  ctx.strokeStyle = color;
  ctx.lineWidth = Math.max(1, w);
  ctx.beginPath();
  ctx.moveTo(p[0], p[1]);
  for (let i = 2; i < p.length; i += 2) ctx.lineTo(p[i], p[i + 1]);
  if (it.k) ctx.closePath();
  ctx.stroke();
}
function drawLines(ctx, items, level) {
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  for (let pass = 0; pass < 3; pass++) for (const it of items) {
    if (it.l !== level && !(level === 0 && it.l === -1 && it.len < 600)) continue;
    const st = VSTYLE[it.c];
    if (!st || !st[pass]) continue;
    const [col, dw] = st[pass];
    const abs = it.c.startsWith('RAIL');
    strokeLine(ctx, it, col, abs ? dw : it.w + dw);
  }
}
function prepareLines(items) {
  for (const it of items) {
    let x0 = 1e9, y0 = 1e9, x1 = -1e9, y1 = -1e9, len = 0;
    const p = it.p;
    for (let i = 0; i < p.length; i += 2) {
      x0 = Math.min(x0, p[i]); x1 = Math.max(x1, p[i]); y0 = Math.min(y0, p[i + 1]); y1 = Math.max(y1, p[i + 1]);
      if (i >= 2) len += Math.hypot(p[i] - p[i - 2], p[i + 1] - p[i - 1]);
    }
    const m = it.w / 2 + 8;
    Object.assign(it, { bx0: x0 - m, by0: y0 - m, bx1: x1 + m, by1: y1 + m, len });
  }
  return items;
}
function getChunk(cx, cy) {
  const key = cx + ',' + cy;
  let c = S.chunks.get(key);
  if (c) { S.chunks.delete(key); S.chunks.set(key, c); return c; } // LRU
  c = { state: 'loading' };
  S.chunks.set(key, c);
  if (S.chunks.size > 220) S.chunks.delete(S.chunks.keys().next().value);
  fetch(`/data/${SCENE}/c_${cx}_${cy}.bin`).then((r) => (r.ok ? r.arrayBuffer() : Promise.reject(r.status)))
    .then(inflate).then((b) => {
      const d = decodeChunk(b);
      const cv = document.createElement('canvas');
      cv.width = cv.height = CPX;
      const ctx = cv.getContext('2d');
      ctx.imageSmoothingEnabled = false;
      const ox = cx * CPX, oy = cy * CPX;
      const items = S.lines.filter((it) => it.bx1 >= ox && it.bx0 <= ox + CPX && it.by1 >= oy && it.by0 <= oy + CPX);
      const layer = (name) => {
        const t = d[name];
        if (!t) return;
        for (let i = 0; i < t.length; i++) if (t[i]) drawTile(ctx, S.byId[t[i] - 1], (i % d.w) * T, Math.floor(i / d.w) * T);
      };
      // vías en un lienzo aparte: las zonas rediseñadas las tapan (igual que src/world/renderer.lua)
      const lineLayer = (level) => {
        if (!items.length) return;
        const lc = document.createElement('canvas');
        lc.width = lc.height = CPX;
        const g = lc.getContext('2d');
        g.translate(-ox, -oy); drawLines(g, items, level);
        for (const z of S.zones) {
          if (z.poly && z.poly.length >= 3) {
            g.save(); polyPath(g, z.poly, z.x * T, z.y * T, T); g.clip();
            g.clearRect(z.x * T, z.y * T, z.w * T, z.h * T); g.restore();
          } else g.clearRect(z.x * T, z.y * T, z.w * T, z.h * T);
        }
        ctx.drawImage(lc, 0, 0);
      };
      layer('ground');
      lineLayer(0);
      layer('ground_detail'); layer('structures'); layer('cover_low'); layer('bridge');
      lineLayer(1);
      layer('overhead');
      Object.assign(c, { state: 'ok', canvas: cv, data: d });
      draw();
    })
    .catch(() => { c.state = 'missing'; });
  return c;
}
async function chunkData(cx, cy) {
  for (let k = 0; k < 100; k++) {
    const c = getChunk(cx, cy);
    if (c.state === 'ok') return c.data;
    if (c.state === 'missing') return null;
    await new Promise((r) => setTimeout(r, 50));
  }
  return null;
}

// ---------------------------------------------------------------- dibujo
const cv = $('view');
const ctx = cv.getContext('2d');
let areaCache = null, raf = 0;
function draw() { if (!raf) raf = requestAnimationFrame(() => { raf = 0; render(); }); }

function renderAreaCanvas(a) {
  const c = document.createElement('canvas');
  c.width = a.w * T; c.height = a.h * T;
  const g = c.getContext('2d');
  g.imageSmoothingEnabled = false;
  const defG = isInterior() ? 'i_floor_wood_0' : 'g_grass_0';
  const cl = cliffs(a);
  for (let y = 0; y < a.h; y++) for (let x = 0; x < a.w; x++) {
    const i = y * a.w + x;
    drawTile(g, a.ground[i] || defG, x * T, y * T);
    if (a.detail[i]) drawTile(g, a.detail[i], x * T, y * T);
    if (a.structures[i]) drawTile(g, a.structures[i], x * T, y * T);
    else if (cl[i]) drawTile(g, cliffName(cl, a, x, y), x * T, y * T);
    if (a.overhead[i]) drawTile(g, a.overhead[i], x * T, y * T);
  }
  return { canvas: c, cliffs: cl };
}

function render() {
  const dpr = window.devicePixelRatio || 1;
  const W = cv.clientWidth, H = cv.clientHeight;
  if (cv.width !== Math.round(W * dpr) || cv.height !== Math.round(H * dpr)) { cv.width = Math.round(W * dpr); cv.height = Math.round(H * dpr); }
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  ctx.imageSmoothingEnabled = false;
  ctx.fillStyle = '#0d0c10';
  ctx.fillRect(0, 0, W, H);
  const s = S.scale, cam = S.cam;
  const sx = (wx) => (wx - cam.x) * s, sy = (wy) => (wy - cam.y) * s;
  const a = area();

  if (!isInterior()) {
    const low = S.overview || S.minimap;
    if (s < 0.25 && low) {
      // vista general (2 px por tile); con más zoom se dibujan los trozos reales del mapa
      ctx.imageSmoothingEnabled = s < 0.125;
      ctx.drawImage(low, sx(0), sy(0), 1600 * T * s, 1600 * T * s);
      ctx.imageSmoothingEnabled = false;
    } else {
      const c0x = Math.max(0, Math.floor(cam.x / CPX)), c0y = Math.max(0, Math.floor(cam.y / CPX));
      const c1x = Math.min(49, Math.floor((cam.x + W / s) / CPX)), c1y = Math.min(49, Math.floor((cam.y + H / s) / CPX));
      for (let cy = c0y; cy <= c1y; cy++) for (let cx = c0x; cx <= c1x; cx++) {
        const c = getChunk(cx, cy);
        if (c.state === 'ok') ctx.drawImage(c.canvas, sx(cx * CPX), sy(cy * CPX), CPX * s, CPX * s);
        else if (low) {  // mientras carga el trozo, su parte de la vista general (nunca un hueco negro)
          const k = low.width / 1600 * (CPX / T);
          ctx.drawImage(low, cx * k, cy * k, k, k, sx(cx * CPX), sy(cy * CPX), CPX * s, CPX * s);
        }
      }
    }
    if (!S.zone) drawNpcs(sx, sy);
    // otras zonas
    for (const z of S.zones) {
      if (S.zone && z.id === S.zone.id) continue;
      ctx.strokeStyle = '#55c6c3'; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
      ctx.strokeRect(sx(z.x * T), sy(z.y * T), z.w * T * s, z.h * T * s);
      ctx.setLineDash([]);
      ctx.fillStyle = '#55c6c3'; ctx.font = '12px system-ui';
      ctx.fillText(z.name || z.id, sx(z.x * T) + 4, sy(z.y * T) - 4);
    }
  }

  if (a) {
    const o = areaOrigin();
    if (!areaCache) areaCache = renderAreaCanvas(a);
    ctx.drawImage(areaCache.canvas, sx(o.x), sy(o.y), a.w * T * s, a.h * T * s);
    if (S.zone.patch) {  // retoque del mapa: las calles vectoriales siguen encima
      const x0 = o.x, y0 = o.y, x1 = o.x + a.w * T, y1 = o.y + a.h * T;
      const items = S.lines.filter((it) => it.bx1 >= x0 && it.bx0 <= x1 && it.by1 >= y0 && it.by0 <= y1);
      ctx.save();
      ctx.beginPath(); ctx.rect(sx(x0), sy(y0), a.w * T * s, a.h * T * s); ctx.clip();
      ctx.translate(-cam.x * s, -cam.y * s); ctx.scale(s, s);
      drawLines(ctx, items, 0); drawLines(ctx, items, 1);
      ctx.restore();
    }
    if (!isInterior() && a.poly && a.poly.length >= 3) {  // fuera de la forma se conserva el mapa
      ctx.save();
      ctx.beginPath(); ctx.rect(sx(o.x), sy(o.y), a.w * T * s, a.h * T * s);
      a.poly.slice().reverse().forEach(([x, y], i) => (i ? ctx.lineTo : ctx.moveTo).call(ctx, sx(o.x + x * T), sy(o.y + y * T)));
      ctx.closePath();
      ctx.fillStyle = 'rgba(13,12,16,.55)'; ctx.fill('evenodd');
      ctx.strokeStyle = '#55c6c3'; ctx.lineWidth = 2;
      polyPath(ctx, a.poly, sx(o.x), sy(o.y), T * s); ctx.stroke();
      ctx.restore();
    }
    if (S.polyEdit && !isInterior()) {
      const pts = S.polyEdit.pts;
      ctx.strokeStyle = '#ffd166'; ctx.lineWidth = 2; ctx.beginPath();
      pts.forEach(([x, y], i) => (i ? ctx.lineTo : ctx.moveTo).call(ctx, sx(o.x + x * T), sy(o.y + y * T)));
      if (S.hover && pts.length) ctx.lineTo(sx(S.hover.wx), sy(S.hover.wy));
      ctx.stroke();
      ctx.fillStyle = '#ffd166';
      for (const [x, y] of pts) ctx.fillRect(sx(o.x + x * T) - 3, sy(o.y + y * T) - 3, 6, 6);
    }
    if (S.view.trace && !isInterior()) {
      ctx.globalAlpha = 0.45;
      for (let cy = Math.floor(o.y / CPX); cy <= Math.floor((o.y + a.h * T) / CPX); cy++)
        for (let cx = Math.floor(o.x / CPX); cx <= Math.floor((o.x + a.w * T) / CPX); cx++) {
          const c = getChunk(cx, cy);
          if (c.state !== 'ok') continue;
          ctx.save();
          ctx.beginPath(); ctx.rect(sx(o.x), sy(o.y), a.w * T * s, a.h * T * s); ctx.clip();
          ctx.drawImage(c.canvas, sx(cx * CPX), sy(cy * CPX), CPX * s, CPX * s);
          ctx.restore();
        }
      ctx.globalAlpha = 1;
    }
    const cs = T * s;
    if (S.view.height || S.layer === 'height') {
      for (let y = 0; y < a.h; y++) for (let x = 0; x < a.w; x++) {
        const hv = a.height[y * a.w + x];
        if (!hv) continue;
        ctx.fillStyle = HEIGHT_COLORS[hv];
        ctx.fillRect(sx(o.x + x * T), sy(o.y + y * T), cs, cs);
        if (cs >= 20) { ctx.fillStyle = '#fff'; ctx.font = `${Math.min(14, cs / 2)}px system-ui`; ctx.fillText(hv, sx(o.x + x * T) + 3, sy(o.y + y * T) + cs - 4); }
      }
    }
    if (S.view.grid && cs >= 8) {
      ctx.strokeStyle = 'rgba(255,255,255,.22)'; ctx.lineWidth = 1;
      ctx.beginPath();
      for (let x = 0; x <= a.w; x++) { const X = Math.round(sx(o.x + x * T)) + 0.5; ctx.moveTo(X, sy(o.y)); ctx.lineTo(X, sy(o.y + a.h * T)); }
      for (let y = 0; y <= a.h; y++) { const Y = Math.round(sy(o.y + y * T)) + 0.5; ctx.moveTo(sx(o.x), Y); ctx.lineTo(sx(o.x + a.w * T), Y); }
      ctx.stroke();
    }
    ctx.strokeStyle = '#e6bd6b'; ctx.lineWidth = 2;
    ctx.strokeRect(sx(o.x), sy(o.y), a.w * T * s, a.h * T * s);
    // objetos
    const objs = a.objects.slice();
    if (isInterior() && a.spawn) objs.push({ type: '_spawn', x: a.spawn[0], y: a.spawn[1] });
    for (const ob of objs) {
      const X = sx(o.x + ob.x * T), Y = sy(o.y + ob.y * T);
      const spr = ob.type === 'npc' ? S.sprites[ob.sprite] : ob.type === 'sign' ? S.sprites.sign : null;
      if (spr && ob.type === 'npc') ctx.drawImage(spr, 64, 0, 16, 24, X, Y - 8 * s, cs, 24 * s);
      else if (spr) ctx.drawImage(spr, 0, 0, spr.width, spr.height, X, Y, cs, cs);
      else {
        ctx.font = `${Math.max(10, cs * 0.8)}px system-ui`;
        ctx.fillText(ob.type === '_spawn' ? '🧍' : OBJ_TYPES[ob.type].icon, X + cs * 0.05, Y + cs * 0.85);
      }
      if (ob === S.sel) { ctx.strokeStyle = '#55c6c3'; ctx.lineWidth = 2; ctx.strokeRect(X - 1, Y - 1, cs + 2, cs + 2); }
      if (ob.type === 'door' && cs >= 12) { ctx.fillStyle = '#e6bd6b'; ctx.font = '11px system-ui'; ctx.fillText(ob.interior || '¡sin interior!', X, Y - 3); }
    }
    // cursor / arrastre
    if (S.drag && S.drag.rect) {
      const r = normRect(S.drag.rect);
      ctx.strokeStyle = '#fff'; ctx.setLineDash([4, 3]);
      ctx.strokeRect(sx(o.x + r.x0 * T), sy(o.y + r.y0 * T), (r.x1 - r.x0 + 1) * cs, (r.y1 - r.y0 + 1) * cs);
      ctx.setLineDash([]);
    } else if (S.hover && inside(a, S.hover.x, S.hover.y) && !['select', 'pan'].includes(S.tool)) {
      const n = ['brush', 'erase'].includes(S.tool) ? S.brush : 1, off = Math.floor((n - 1) / 2);
      ctx.strokeStyle = S.tool === 'erase' ? '#e26d5c' : '#fff';
      ctx.strokeRect(sx(o.x + (S.hover.x - off) * T), sy(o.y + (S.hover.y - off) * T), n * cs, n * cs);
    }
  }
  if (S.newZone && S.drag && S.drag.rect) {
    const r = normRect(S.drag.rect);
    ctx.strokeStyle = '#e6bd6b'; ctx.lineWidth = 2; ctx.setLineDash([6, 4]);
    ctx.strokeRect(sx(r.x0 * T), sy(r.y0 * T), (r.x1 - r.x0 + 1) * T * s, (r.y1 - r.y0 + 1) * T * s);
    ctx.setLineDash([]);
  }
  updateHud();
}
function normRect(r) {
  return { x0: Math.min(r.x0, r.x1), y0: Math.min(r.y0, r.y1), x1: Math.max(r.x0, r.x1), y1: Math.max(r.y0, r.y1) };
}
function updateHud() {
  const h = S.hover;
  let t = `zoom ×${S.scale}`;
  if (h) {
    t = `celda ${h.x},${h.y} · ` + t;
    const a = area();
    if (a && inside(a, h.x, h.y)) {
      const i = h.y * a.w + h.x;
      t += ` · altura ${a.height[i]}`;
      const names = ['ground', 'detail', 'structures', 'overhead'].map((k) => a[k][i]).filter(Boolean);
      if (names.length) t += ` · ${names.join(' / ')}`;
      if (!isInterior()) t += ` · mapa ${S.zone.x + h.x},${S.zone.y + h.y}`;
    }
  }
  if (S.newZone) t = 'Arrastra para dibujar la zona nueva (Esc cancela) · ' + t;
  $('hud').textContent = t;
}

// ---------------------------------------------------------------- ratón
function cellFromEvent(e) {
  const r = cv.getBoundingClientRect();
  const wx = S.cam.x + (e.clientX - r.left) / S.scale, wy = S.cam.y + (e.clientY - r.top) / S.scale;
  const o = areaOrigin();
  return { x: Math.floor((wx - o.x) / T), y: Math.floor((wy - o.y) / T), wx, wy };
}
cv.addEventListener('contextmenu', (e) => e.preventDefault());
cv.addEventListener('pointerdown', (e) => {
  cv.setPointerCapture(e.pointerId);
  const c = cellFromEvent(e);
  if (S.npcMode && !S.zone && !S.newZone && e.button === 0 && !S.space) {
    const tx = Math.floor(c.wx / T), ty = Math.floor(c.wy / T);
    let n = npcAt(tx, ty);
    if (!n) {
      n = { id: 'npc_' + Date.now().toString(36), x: tx, y: ty, sprite: 'npc_elder', name: 'Veí', say: ['Hola!'], wander: 0, facing: 'down', ai: true, persona: '' };
      S.npcs.push(n);
      S.dirty = true; setStatus('Personajes sin guardar');
    }
    S.selNpc = n;
    S.drag = { npcMove: n };
    renderProps(); draw();
    return;
  }
  if (e.button === 1 || e.button === 2 || S.space || (S.tool === 'pan' && !S.newZone) || (!S.zone && !S.newZone)) {
    if (!S.zone && !S.newZone && e.button === 0) {
      const hit = S.zones.find((z) => c.wx >= z.x * T && c.wx < (z.x + z.w) * T && c.wy >= z.y * T && c.wy < (z.y + z.h) * T);
      if (hit) { openZone(hit.id); return; }
    }
    S.drag = { pan: true, sx: e.clientX, sy: e.clientY, cx: S.cam.x, cy: S.cam.y };
    return;
  }
  if (S.newZone) {
    const tx = Math.floor(c.wx / T), ty = Math.floor(c.wy / T);
    S.drag = { rect: { x0: tx, y0: ty, x1: tx, y1: ty }, newZone: true };
    return;
  }
  const a = area();
  if (!a) return;
  if (S.polyEdit && !isInterior()) {
    const o = areaOrigin();
    const vx = Math.max(0, Math.min(a.w, Math.round((c.wx - o.x) / T))), vy = Math.max(0, Math.min(a.h, Math.round((c.wy - o.y) / T)));
    const pts = S.polyEdit.pts;
    if (pts.length >= 3 && Math.hypot(vx - pts[0][0], vy - pts[0][1]) < 0.8) {
      snapshot(); S.zone.poly = pts; S.polyEdit = null; markDirty(); renderProps();
      setStatus(`Forma de ${pts.length} vértices: fuera de ella se conserva el mapa`, 'ok');
    } else { pts.push([vx, vy]); setStatus(`Vértice ${pts.length} · clic en el primero para cerrar · Esc cancela`); }
    draw();
    return;
  }
  if (S.tool === 'select' || S.layer === 'objects' && S.tool !== 'pick') {
    const ob = objAt(a, c.x, c.y);
    if (S.tool !== 'select' && !ob && inside(a, c.x, c.y)) { snapshot(); placeObject(a, c.x, c.y); markDirty(); return; }
    S.sel = ob || null;
    renderProps();
    if (ob) { snapshot(); S.drag = { move: ob }; }
    draw();
    return;
  }
  if (!inside(a, c.x, c.y)) return;
  if (S.tool === 'pick') { pickAt(a, c.x, c.y); return; }
  if (S.tool === 'rect' || S.tool === 'build') { S.drag = { rect: { x0: c.x, y0: c.y, x1: c.x, y1: c.y } }; return; }
  snapshot();
  if (S.tool === 'fill') { floodFill(a, c.x, c.y, false); markDirty(); return; }
  S.drag = { paint: true, erase: S.tool === 'erase', last: c };
  if (brushAt(a, c.x, c.y, S.drag.erase)) markDirty();
});
cv.addEventListener('pointermove', (e) => {
  const c = cellFromEvent(e);
  S.hover = c;
  const d = S.drag;
  if (d && d.pan) {
    S.cam.x = d.cx - (e.clientX - d.sx) / S.scale;
    S.cam.y = d.cy - (e.clientY - d.sy) / S.scale;
  } else if (d && d.rect) {
    if (d.newZone) { d.rect.x1 = Math.floor(c.wx / T); d.rect.y1 = Math.floor(c.wy / T); }
    else { d.rect.x1 = c.x; d.rect.y1 = c.y; }
  } else if (d && d.npcMove) {
    const tx = Math.floor(c.wx / T), ty = Math.floor(c.wy / T);
    if ((d.npcMove.x !== tx || d.npcMove.y !== ty) && !npcAt(tx, ty)) {
      d.npcMove.x = tx; d.npcMove.y = ty; S.dirty = true; setStatus('Personajes sin guardar');
    }
  } else if (d && d.move) {
    const a = area();
    if (inside(a, c.x, c.y) && (d.move.x !== c.x || d.move.y !== c.y) && !objAt(a, c.x, c.y)) {
      d.move.x = c.x; d.move.y = c.y; d.moved = true; renderProps();
    }
  } else if (d && d.paint) {
    const a = area();
    // interpola para no dejar huecos al mover rápido
    const steps = Math.max(Math.abs(c.x - d.last.x), Math.abs(c.y - d.last.y));
    let ch = false;
    for (let k = 1; k <= steps; k++) {
      const x = Math.round(d.last.x + (c.x - d.last.x) * k / steps), y = Math.round(d.last.y + (c.y - d.last.y) * k / steps);
      if (inside(a, x, y)) ch = brushAt(a, x, y, d.erase) || ch;
    }
    d.last = c;
    if (ch) { markDirty(); return; }
  }
  draw();
});
cv.addEventListener('pointerup', async () => {
  const d = S.drag;
  S.drag = null;
  if (!d) return;
  if (d.newZone) {
    S.newZone = false; $('btnNewZone').classList.remove('on'); $('btnMapEdit').classList.remove('on');
    if (S.newKind === 'patch') await openPatch(normRect(d.rect)); else await createZoneDialog(normRect(d.rect));
    return;
  }
  if (d.npcMove) { renderProps(); draw(); return; }
  if (d.move) { if (d.moved) markDirty(); else S.undo.pop(); return; }
  if (d.rect) {
    const a = area();
    snapshot();
    if (S.tool === 'build') building(a, normRect(d.rect)); else rectFill(a, normRect(d.rect), false);
    markDirty();
  }
  draw();
});
cv.addEventListener('pointerleave', () => { S.hover = null; draw(); });
cv.addEventListener('wheel', (e) => {
  e.preventDefault();
  const r = cv.getBoundingClientRect();
  const mx = e.clientX - r.left, my = e.clientY - r.top;
  const wx = S.cam.x + mx / S.scale, wy = S.cam.y + my / S.scale;
  let i = SCALES.indexOf(S.scale);
  if (i < 0) i = 3;
  i = Math.max(0, Math.min(SCALES.length - 1, i + (e.deltaY < 0 ? 1 : -1)));
  S.scale = SCALES[i];
  S.cam.x = wx - mx / S.scale; S.cam.y = wy - my / S.scale;
  draw();
}, { passive: false });
window.addEventListener('resize', draw);

function centerOn(px, py, w, h) {
  const W = cv.clientWidth, H = cv.clientHeight;
  if (w && h) {
    const fit = Math.min(W / w, H / h) * 0.9;
    S.scale = SCALES.filter((x) => x <= fit).pop() || SCALES[0];
  }
  S.cam.x = px + (w || 0) / 2 - W / 2 / S.scale;
  S.cam.y = py + (h || 0) / 2 - H / 2 / S.scale;
  draw();
}

// ---------------------------------------------------------------- teclado
window.addEventListener('keydown', (e) => {
  if (['INPUT', 'TEXTAREA', 'SELECT'].includes(document.activeElement.tagName)) return;
  if (e.key === ' ') { S.space = true; e.preventDefault(); return; }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); e.shiftKey ? restore(S.redo, S.undo) : restore(S.undo, S.redo); return; }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'y') { e.preventDefault(); restore(S.redo, S.undo); return; }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 's') { e.preventDefault(); save(); return; }
  if (e.key === 'Escape') { S.polyEdit = null; S.newZone = false; S.drag = null; $('btnMapEdit').classList.remove('on'); $('btnNewZone').classList.remove('on'); S.sel = null; renderProps(); draw(); return; }
  if ((e.key === 'Delete' || e.key === 'Backspace') && S.sel) { deleteSel(); return; }
  const n = +e.key;
  if (n >= 1 && n <= EDIT_LAYERS.length) { setLayer(EDIT_LAYERS[n - 1].key); return; }
  const tk = { b: 'brush', r: 'rect', f: 'fill', e: 'erase', i: 'pick', v: 'select', h: 'pan' }[e.key.toLowerCase()];
  if (tk) setTool(tk);
});
window.addEventListener('keyup', (e) => { if (e.key === ' ') S.space = false; });

// ---------------------------------------------------------------- UI lateral
function setTool(t) {
  S.tool = t;
  document.querySelectorAll('#tools button').forEach((b) => b.classList.toggle('on', b.dataset.k === t));
  $('buildBox').hidden = t !== 'build';
  if (t === 'build' && ['height', 'objects'].includes(S.layer)) setLayer('structures');
  draw();
}
function setLayer(k) {
  S.layer = k;
  document.querySelectorAll('#layers button').forEach((b) => b.classList.toggle('on', b.dataset.k === k));
  $('heightBox').hidden = k !== 'height';
  $('objBox').hidden = k !== 'objects';
  $('palBox').hidden = k === 'height' || k === 'objects';
  if (k === 'objects' && !['select', 'pick'].includes(S.tool)) setTool('brush');
  draw();
}
function setHeight(h) {
  S.height = h;
  document.querySelectorAll('#heights button').forEach((b) => b.classList.toggle('on', +b.dataset.h === h));
}
function setObjType(t) {
  S.objType = t;
  document.querySelectorAll('#objTypes button').forEach((b) => b.classList.toggle('on', b.dataset.t === t));
}
function buildSidebar() {
  for (const t of TOOLS) $('tools').append(el('button', { textContent: t.label, title: t.title, 'data-k': t.key, on: { click: () => setTool(t.key) } }));
  EDIT_LAYERS.forEach((l, i) => $('layers').append(el('button', { textContent: l.label, title: `Tecla ${i + 1}`, 'data-k': l.key, on: { click: () => setLayer(l.key) } })));
  for (let h = 0; h <= 3; h++) $('heights').append(el('button', { textContent: h === 0 ? '0 (calle)' : String(h), 'data-h': h, on: { click: () => setHeight(h) } }));
  for (const [k, v] of Object.entries(OBJ_TYPES)) $('objTypes').append(el('button', { textContent: `${v.icon} ${v.label}`, 'data-t': k, on: { click: () => setObjType(k) } }));
  document.querySelectorAll('#brushRow button').forEach((b) => b.addEventListener('click', () => {
    S.brush = +b.dataset.bs;
    document.querySelectorAll('#brushRow button').forEach((x) => x.classList.toggle('on', x === b));
  }));
  for (const k of ['grid', 'height', 'trace']) {
    const box = $('v' + k[0].toUpperCase() + k.slice(1));
    box.checked = S.view[k];
    box.onchange = () => { S.view[k] = box.checked; draw(); };
  }
  setTool('brush'); setLayer('ground'); setHeight(1); setObjType('npc');
}

function field(label, input) { return el('div', { className: 'row' }, el('label', { textContent: label }), input); }
function textInput(val, onch, type = 'text') {
  return el('input', { type, value: val ?? '', on: { change: (e) => { snapshot(); onch(type === 'number' ? +e.target.value : e.target.value); markDirty(); renderProps(); } } });
}
function selectInput(opts, val, onch) {
  const s = el('select', { on: { change: (e) => { snapshot(); onch(e.target.value); markDirty(); renderProps(); } } });
  for (const o of opts) s.append(el('option', { value: o, textContent: o || '—', selected: o === val }));
  return s;
}
function linesInput(arr, onch) {
  return el('textarea', { value: (arr || []).join('\n'), title: 'Una frase por línea (cada línea es una página)',
    on: { change: (e) => { snapshot(); onch(e.target.value.split('\n').map((x) => x.trim()).filter(Boolean)); markDirty(); } } });
}

function renderProps() {
  const box = $('props');
  box.innerHTML = '';
  const z = S.zone;
  if (!z && S.npcMode) { npcPanel(box); return; }
  if (!z) {
    box.append(el('h2', { textContent: 'Zonas' }),
      el('p', { className: 'hint', textContent: 'Elige una zona arriba, haz clic en un recuadro del mapa o crea una nueva con «＋ Zona nueva». Al publicar, la zona sustituye por completo ese trozo de mapa.' }));
    const list = el('div', { className: 'list' });
    for (const zz of S.zones) list.append(el('button', { textContent: `${zz.name || zz.id} (${zz.w}×${zz.h})`, on: { click: () => openZone(zz.id) } }));
    box.append(list);
    return;
  }
  const a = area(), o = S.sel;
  if (o && a.objects.includes(o)) {
    box.append(el('h2', { textContent: `${OBJ_TYPES[o.type].icon} ${OBJ_TYPES[o.type].label} (${o.x},${o.y})` }));
    if (o.type === 'door') {
      const ids = Object.keys(z.interiors);
      box.append(field('Interior', selectInput(['', ...ids], o.interior || '', (v) => { o.interior = v; })));
      box.append(el('div', { className: 'row' },
        el('button', { textContent: '＋ Interior nuevo', on: { click: () => { snapshot(); o.interior = newInterior(); markDirty(); renderProps(); } } }),
        o.interior && z.interiors[o.interior] ? el('button', { textContent: 'Editar interior →', on: { click: () => setArea(o.interior) } }) : ''));
      box.append(el('p', { className: 'hint', textContent: 'Al entrar se aparece en el punto 🧍 del interior; al salir, justo debajo de esta puerta.' }));
    }
    if (o.type === 'npc') {
      box.append(field('Nombre', textInput(o.name, (v) => { o.name = v; })));
      box.append(field('Aspecto', selectInput(NPC_SPRITES, o.sprite, (v) => { o.sprite = v; })));
      box.append(field('Mira', selectInput(['down', 'up', 'left', 'right'], o.facing || 'down', (v) => { o.facing = v; })));
      box.append(field('Pasea', textInput(o.wander || 0, (v) => { o.wander = Math.max(0, Math.min(8, v | 0)); }, 'number')));
      box.append(el('label', { className: 'hint', textContent: 'Diálogo (una página por línea)' }), linesInput(o.say, (v) => { o.say = v; }));
      aiFields(box, o, () => { markDirty(); });
    }
    if (o.type === 'sign') box.append(el('label', { className: 'hint', textContent: 'Texto (una página por línea)' }), linesInput(o.say, (v) => { o.say = v; }));
    if (o.type === 'spawn') box.append(field('Nombre', textInput(o.name, (v) => { o.name = v.replace(/[^a-z0-9_]/g, ''); })));
    if (o.type === 'exit') box.append(el('p', { className: 'hint', textContent: 'Devuelve al exterior, delante de la puerta que lleva aquí.' }));
    box.append(el('div', { className: 'row' }, el('button', { className: 'danger', textContent: '🗑️ Quitar', on: { click: deleteSel } })));
    return;
  }
  if (isInterior()) {
    box.append(el('h2', { textContent: `Interior ${S.areaKey}` }));
    box.append(field('Nombre', textInput(a.name, (v) => { a.name = v; })));
    const w = textInput(a.w, () => {}, 'number'), h = textInput(a.h, () => {}, 'number');
    w.onchange = h.onchange = null;
    box.append(field('Tamaño', el('span', { className: 'row' }, w, '×', h,
      el('button', { textContent: 'Aplicar', on: { click: () => resizeArea(a, +w.value, +h.value, 4, 60) } }))));
    const sp = a.spawn || [0, 0];
    box.append(field('Entrada 🧍', el('span', { className: 'row' },
      textInput(sp[0], (v) => { a.spawn = [v, sp[1]]; }, 'number'), textInput(sp[1], (v) => { a.spawn = [sp[0], v]; }, 'number'))));
    box.append(el('p', { className: 'hint', textContent: 'La salida ⬇️ devuelve a la calle. Si no pones ninguna se añade una abajo en el centro.' }));
    const kind = el('select', {});
    for (const [v, t] of [['house', '🏠 Casa'], ['shop', '🛒 Botiga'], ['block', '🏢 Portal']]) kind.append(el('option', { value: v, textContent: t, selected: v === S.procKind }));
    kind.onchange = () => { S.procKind = kind.value; };
    box.append(field('🎲 Procedural', el('span', { className: 'row' }, kind,
      el('button', { textContent: 'Generar', title: 'Sustituye este interior por uno generado (se puede deshacer)', on: { click: () => generateInterior(a, kind.value) } }))));
    box.append(el('p', { className: 'hint', textContent: 'Casa: salón, dormitorio y cocina o baño · Botiga: estanterías y mostrador · Portal: buzones y escalera. Cada clic, otra semilla.' }));
    box.append(el('div', { className: 'row' },
      el('button', { textContent: '← Exterior', on: { click: () => setArea('ext') } }),
      el('button', { className: 'danger', textContent: '🗑️ Borrar interior', on: { click: deleteInterior } })));
    return;
  }
  if (z.patch) {
    const n = Object.keys(S.mapEdits.cells).length;
    box.append(el('h2', { textContent: 'Retoque del mapa' }));
    box.append(el('p', { className: 'hint', textContent: `Recuadro ${z.w}×${z.h} en (${z.x},${z.y}). Pinta con cualquier herramienta (🪣 rellena las casillas iguales conectadas) y deshaz con ↶. Solo se guardan las casillas que cambias; las calles vectoriales se quedan encima.` }));
    box.append(el('p', { className: 'hint', textContent: `Retoques guardados en todo el mapa: ${n} casillas.` }));
    box.append(el('div', { className: 'row' },
      el('button', { className: 'primary', textContent: '💾 Guardar retoques', on: { click: save } }),
      el('button', { textContent: '🗺️ Cerrar', on: { click: () => closeZone() } })));
    return;
  }
  box.append(el('h2', { textContent: `Zona ${z.id}` }));
  box.append(field('Nombre', textInput(z.name, (v) => { z.name = v; })));
  const pos = el('span', { className: 'row' }, textInput(z.x, (v) => { z.x = v | 0; }, 'number'), textInput(z.y, (v) => { z.y = v | 0; }, 'number'));
  box.append(field('Posición', pos));
  const w = el('input', { type: 'number', value: z.w }), h = el('input', { type: 'number', value: z.h });
  box.append(field('Tamaño', el('span', { className: 'row' }, w, '×', h,
    el('button', { textContent: 'Aplicar', on: { click: () => resizeArea(z, +w.value, +h.value, 2, 120) } }))));
  box.append(el('p', { className: 'hint', textContent: `Interiores: ${Object.keys(z.interiors).join(', ') || 'ninguno'}. Crea uno con la herramienta 🏠 o con una 🚪 puerta.` }));
  box.append(field('Forma', el('span', { className: 'row' },
    el('button', { textContent: '⬠ Polígono', title: 'Clic en el mapa para cada vértice; clic en el primero para cerrar', on: { click: () => { S.polyEdit = { pts: [] }; setStatus('Clic para poner vértices (en las esquinas de las casillas); clic en el primero para cerrar'); draw(); } } }),
    z.poly ? el('button', { textContent: '▭ Rectángulo', on: { click: () => { snapshot(); delete z.poly; markDirty(); renderProps(); } } }) : '')));
  if (z.poly) box.append(el('p', { className: 'hint', textContent: `Zona poligonal (${z.poly.length} vértices): fuera de la forma el mapa no cambia y las calles se ven.` }));
  const file = el('input', { type: 'file', accept: 'image/*', style: 'display:none', on: { change: (e) => {
    const f = e.target.files[0];
    if (!f) return;
    const rd = new FileReader();
    rd.onload = () => satToPixel(z, rd.result);
    rd.readAsDataURL(f);
    e.target.value = '';
  } } });
  box.append(field('🛰️ Satélite → pixel art', el('span', { className: 'row' },
    el('button', { textContent: 'Ortofoto', title: 'Convierte la ortofoto PNOA de esta zona en tiles (se puede deshacer)', on: { click: () => satToPixel(z) } }),
    el('button', { textContent: '📷 Imagen…', title: 'Convierte una imagen propia (se estira al tamaño de la zona)', on: { click: () => file.click() } }), file)));
  box.append(el('p', { className: 'hint', textContent: 'Clasifica cada metro por color: agua, césped, árboles, tejados (con fachada y puerta), calles y tierra. Repasa después a mano.' }));
  box.append(el('div', { className: 'row' },
    el('button', { textContent: '🗺️ Ver mapa', on: { click: closeZone } }),
    el('button', { className: 'danger', textContent: '🗑️ Borrar zona', on: { click: deleteZone } })));
}

// ---------------------------------------------------------------- personajes con IA
function aiFields(box, o, changed) {
  const cb = el('input', { type: 'checkbox', checked: !!o.ai, on: { change: (e) => { snapshot(); o.ai = e.target.checked; changed(); renderProps(); } } });
  box.append(el('div', { className: 'row' }, cb, el('label', { textContent: 'Habla con IA (Groq)' })));
  if (!o.ai) return;
  box.append(el('label', { className: 'hint', textContent: 'Personalidad e historia (quién es, qué le gusta, qué sabe del pueblo)' }),
    el('textarea', { value: o.persona || '', maxLength: 600, on: { change: (e) => { snapshot(); o.persona = e.target.value.trim(); changed(); } } }));
  box.append(el('p', { className: 'hint', textContent: 'Las frases fijas se usan si la IA no responde. La IA contesta en catalán, corto y apto para niños.' }));
  const log = el('div', { id: 'chatlog', className: 'hint' });
  const run = async (ask) => {
    S.chat = S.chat && S.chat.npc === o ? S.chat : { npc: o, history: [] };
    log.textContent = 'Pensando…';
    try {
      const r = await api('POST', '/api/npc_chat', { npc: { id: o.id || (S.zone ? S.zone.id + '_npc_' + (S.zone.objects||[]).indexOf(o) : '') }, history: S.chat.history, ask });
      S.chat.history.push({ role: 'user', text: ask }, { role: 'npc', text: r.reply });
      log.innerHTML = '';
      log.append(el('div', { textContent: `${o.name || 'Personaje'}: ${r.reply}${r.ai ? '' : '  (frase fija: IA no disponible)'}` }));
      const opts = el('div', { className: 'row' });
      for (const op of r.options || []) opts.append(el('button', { textContent: op, on: { click: () => run(op) } }));
      log.append(opts);
    } catch (e) { log.textContent = 'Error: ' + e.message; }
  };
  box.append(el('div', { className: 'row' }, el('button', { textContent: '💬 Probar conversación', on: { click: () => { S.chat = null; run('Hola!'); } } })), log);
}
function npcAt(x, y) { return S.npcs.find((n) => n.x === x && n.y === y); }
function npcPanel(box) {
  const o = S.selNpc;
  const changed = () => { S.dirty = true; setStatus('Personajes sin guardar'); draw(); };
  if (!o) {
    box.append(el('h2', { textContent: '🧑 Personajes por el mapa' }),
      el('p', { className: 'hint', textContent: 'Clic en una casilla vacía del mapa para poner un personaje; clic en un personaje para editarlo o arrástralo. Guarda y publica para verlos en el juego.' }));
    const list = el('div', { className: 'list' });
    for (const n of S.npcs) list.append(el('button', { textContent: `${n.ai ? '💬' : '🧑'} ${n.name || n.id} (${n.x},${n.y})`, on: { click: () => { S.selNpc = n; centerOn(n.x * T, n.y * T); renderProps(); } } }));
    box.append(list);
    return;
  }
  const inp = (val, set, type = 'text') => el('input', { type, value: val ?? '', on: { change: (e) => { set(type === 'number' ? +e.target.value : e.target.value); changed(); renderProps(); } } });
  const sel = (opts, val, set) => { const s = el('select', { on: { change: (e) => { set(e.target.value); changed(); } } }); for (const v of opts) s.append(el('option', { value: v, textContent: v, selected: v === val })); return s; };
  box.append(el('h2', { textContent: `🧑 ${o.name || o.id} (${o.x},${o.y})` }));
  box.append(field('Nombre', inp(o.name, (v) => { o.name = v; })));
  box.append(field('Aspecto', sel(NPC_SPRITES, o.sprite, (v) => { o.sprite = v; })));
  box.append(field('Mira', sel(['down', 'up', 'left', 'right'], o.facing || 'down', (v) => { o.facing = v; })));
  box.append(field('Pasea', inp(o.wander || 0, (v) => { o.wander = Math.max(0, Math.min(8, v | 0)); }, 'number')));
  box.append(el('label', { className: 'hint', textContent: 'Frases fijas (una por línea)' }),
    el('textarea', { value: (o.say || []).join('\n'), on: { change: (e) => { o.say = e.target.value.split('\n').map((x) => x.trim()).filter(Boolean); changed(); } } }));
  aiFields(box, o, changed);
  box.append(el('div', { className: 'row' },
    el('button', { textContent: '← Todos', on: { click: () => { S.selNpc = null; renderProps(); draw(); } } }),
    el('button', { className: 'danger', textContent: '🗑️ Quitar', on: { click: () => { S.npcs = S.npcs.filter((n) => n !== o); S.selNpc = null; changed(); renderProps(); } } })));
}
function setNpcMode(on) {
  if (on && S.zone) { if (!confirmDiscard()) return; closeZone(true); }
  S.npcMode = on;
  S.selNpc = null;
  $('btnNpcs').classList.toggle('on', on);
  renderProps(); draw();
}
function drawNpcs(sx, sy) {
  const cs = T * S.scale;
  for (const n of S.npcs) {
    const X = sx(n.x * T), Y = sy(n.y * T);
    const spr = S.sprites[n.sprite];
    if (spr) ctx.drawImage(spr, 64, 0, 16, 24, X, Y - 8 * S.scale, cs, 24 * S.scale);
    if (n === S.selNpc) { ctx.strokeStyle = '#55c6c3'; ctx.lineWidth = 2; ctx.strokeRect(X - 1, Y - 9 * S.scale, cs + 2, 24 * S.scale + 2); }
    if (S.scale >= 0.5) {
      ctx.font = '12px system-ui'; ctx.fillStyle = '#16141a'; ctx.fillText((n.ai ? '💬 ' : '') + (n.name || n.id), X + 1, Y - 10 * S.scale + 1);
      ctx.fillStyle = '#ece6da'; ctx.fillText((n.ai ? '💬 ' : '') + (n.name || n.id), X, Y - 10 * S.scale);
    }
  }
}

function resizeArea(a, w, h, min, max) {
  if (!(w >= min && h >= min && w <= max && h <= max)) { setStatus(`Tamaño entre ${min} y ${max}`, 'err'); return; }
  snapshot();
  const old = JSON.parse(JSON.stringify(a));
  const nb = blankArea(w, h, '');
  for (const k of ['ground', 'detail', 'structures', 'overhead', 'height'])
    for (let y = 0; y < Math.min(h, old.h); y++) for (let x = 0; x < Math.min(w, old.w); x++) nb[k][y * w + x] = old[k][y * old.w + x];
  Object.assign(a, { w, h, ground: nb.ground, detail: nb.detail, structures: nb.structures, overhead: nb.overhead, height: nb.height });
  const lost = a.objects.filter((o) => o.x >= w || o.y >= h).length;
  a.objects = a.objects.filter((o) => o.x < w && o.y < h);
  markDirty(); renderProps();
  if (lost) setStatus(`Se han quitado ${lost} objetos que quedaban fuera`, 'err');
}
function deleteSel() {
  const a = area();
  if (!S.sel || !a) return;
  snapshot();
  a.objects = a.objects.filter((o) => o !== S.sel);
  S.sel = null;
  markDirty(); renderProps();
}
// interior procedural (src/world/procgen.lua vía el servidor); sustituye capas, objetos y tamaño
async function generateInterior(a, kind) {
  setStatus('Generando interior…');
  try {
    const g = await api('POST', '/api/procgen', { kind, seed: Math.floor(Math.random() * 1e9) });
    snapshot();
    for (const k of ['w', 'h', 'ground', 'detail', 'structures', 'overhead', 'height', 'objects', 'spawn']) a[k] = g[k];
    markDirty(); renderProps();
    setStatus(`Interior ${kind} generado (semilla ${g.seed})`);
  } catch (e) { setStatus(`Error: ${e.message}`); }
}
// ortofoto de la zona (o imagen propia) → capas de pixel art (tools/sat2pixel.py); conserva los objetos
async function satToPixel(z, image) {
  setStatus('Convirtiendo a pixel art…');
  try {
    const body = image ? { image, w: z.w, h: z.h } : { x: z.x, y: z.y, w: z.w, h: z.h };
    const g = await api('POST', '/api/sat2pixel', body);
    snapshot();
    for (const k of ['ground', 'detail', 'structures', 'overhead', 'height']) z[k] = g[k];
    markDirty(); renderProps();
    setStatus(`Pixel art: ${g.buildings} edificios`);
  } catch (e) { setStatus(`Error: ${e.message}`); }
}
function newInterior() {
  const z = S.zone;
  let n = 1;
  while (z.interiors[`${z.id}_${n}_int`]) n++;
  const iid = `${z.id}_${n}_int`;
  z.interiors[iid] = interiorTemplate(`${z.name || z.id} ${n}`);
  refreshAreaSel();
  return iid;
}
function deleteInterior() {
  if (!confirm(`¿Borrar el interior ${S.areaKey}?`)) return;
  snapshot();
  const iid = S.areaKey;
  delete S.zone.interiors[iid];
  for (const o of S.zone.objects) if (o.type === 'door' && o.interior === iid) o.interior = '';
  setArea('ext');
  markDirty();
}

// ---------------------------------------------------------------- avisos
function validate() {
  const z = S.zone, out = [];
  if (z && !z.patch) {
    const doors = z.objects.filter((o) => o.type === 'door');
    for (const d of doors) {
      if (!d.interior) out.push(`🚪 en (${d.x},${d.y}) sin interior: no se podrá entrar.`);
      else if (!z.interiors[d.interior]) out.push(`🚪 en (${d.x},${d.y}) apunta a ${d.interior}, que no existe.`);
      if (d.y + 1 >= z.h) out.push(`🚪 en (${d.x},${d.y}) está en el borde inferior: al salir aparecerás fuera de la zona.`);
    }
    for (const iid of Object.keys(z.interiors))
      if (!doors.some((d) => d.interior === iid)) out.push(`El interior ${iid} no tiene ninguna puerta.`);
    const check = (a, label) => {
      const cl = cliffs(a);
      let n = 0;
      for (const v of cl) n += v;
      const solidObj = a.objects.filter((o) => o.type === 'npc' && (['detail', 'structures'].some((k) => tileProp(a[k][o.y * a.w + o.x], 'solid')) || cl[o.y * a.w + o.x]));
      for (const o of solidObj) out.push(`${label}: ${o.name || 'personaje'} está sobre una casilla sólida.`);
      const levels = new Set(a.height);
      if (levels.size > 1) {
        const stairs = a.ground.concat(a.structures, a.detail).filter((t) => tileProp(t, 'stairs')).length;
        if (!stairs) out.push(`${label}: hay desniveles pero ninguna escalera; las partes altas serán inaccesibles.`);
      }
      if (n) out.push(`ℹ️ ${label}: ${n} casillas con borde de roca (desnivel; no se pisan).`);
    };
    check(z, 'Exterior');
    for (const [iid, it] of Object.entries(z.interiors)) {
      check(it, iid);
      if (it.spawn && ['structures'].some((k) => tileProp(it[k][it.spawn[1] * it.w + it.spawn[0]], 'solid'))) out.push(`${iid}: la entrada 🧍 está sobre algo sólido.`);
    }
    // calles con coches que cruzan la zona: quedarían tapadas y el tráfico pasaría por encima
    if (z.scene === SCENE || !z.scene) {
      const x0 = z.x * T, y0 = z.y * T, x1 = (z.x + z.w) * T, y1 = (z.y + z.h) * T;
      const roads = S.lines.filter((it) => ['ROAD', 'ROAD_MAIN', 'MOTORWAY'].includes(it.c) && it.l === 0
        && it.bx1 >= x0 && it.bx0 <= x1 && it.by1 >= y0 && it.by0 <= y1);
      const crosses = roads.some((it) => {
        const p = it.p;
        for (let i = 0; i + 3 < p.length; i += 2)
          for (let k = 0; k <= 8; k++) {
            const x = p[i] + (p[i + 2] - p[i]) * k / 8, y = p[i + 1] + (p[i + 3] - p[i + 1]) * k / 8;
            if (x > x0 + 8 && x < x1 - 8 && y > y0 + 8 && y < y1 - 8) return true;
          }
        return false;
      });
      if (crosses) out.push('Una calle con coches atraviesa la zona: quedará tapada y los coches pasarán por encima. Ajusta posición o tamaño.');
    }
    for (const o of S.zones) {
      if (o.id === z.id) continue;
      if (z.x < o.x + o.w && o.x < z.x + z.w && z.y < o.y + o.h && o.y < z.y + z.h) out.push(`Se solapa con la zona ${o.id}.`);
    }
  }
  const box = $('warnings');
  box.innerHTML = '';
  if (!out.length) box.textContent = z ? 'Sin avisos.' : '—';
  for (const t of out) box.append(el('div', { className: t.startsWith('ℹ️') ? 'hint' : 'warn', textContent: t.startsWith('ℹ️') ? t : '• ' + t }));
}

// ---------------------------------------------------------------- retoques del mapa (fuera de zonas)
const PATCH_LAYERS = ['ground', 'detail', 'structures', 'overhead'];
async function copyFromMap(z, r) {
  const map = { ground: 'ground', ground_detail: 'detail', structures: 'structures', cover_low: 'structures', overhead: 'overhead' };
  for (let y = 0; y < z.h; y++) for (let x = 0; x < z.w; x++) {
    const tx = r.x0 + x, ty = r.y0 + y;
    const d = await chunkData(Math.floor(tx / CHUNK), Math.floor(ty / CHUNK));
    if (!d) continue;
    const li = (ty % CHUNK) * d.w + (tx % CHUNK);
    for (const [src, dst] of Object.entries(map)) if (d[src] && d[src][li]) z[dst][y * z.w + x] = S.byId[d[src][li] - 1];
  }
}
async function openPatch(r) {
  const w = r.x1 - r.x0 + 1, h = r.y1 - r.y0 + 1;
  if (w < 1 || h < 1 || w > 160 || h > 160) { setStatus('El recuadro debe medir como mucho 160×160 casillas', 'err'); draw(); return; }
  const hit = S.zones.find((z) => r.x0 < z.x + z.w && z.x <= r.x1 && r.y0 < z.y + z.h && z.y <= r.y1);
  if (hit) setStatus(`Aviso: el recuadro toca la zona ${hit.id}; allí manda la zona (edítala desde su selector).`, 'err');
  setStatus('Copiando casillas del mapa…');
  S.mapEdits = await api('GET', '/api/map_edits');
  const z = Object.assign(blankArea(w, h, ''), { id: '__mapa__', name: 'Retoque del mapa', scene: SCENE, x: r.x0, y: r.y0, interiors: {}, patch: true });
  for (const k of PATCH_LAYERS) z[k] = Array(w * h).fill('');
  await copyFromMap(z, r);
  // retoques guardados que aún no se han publicado
  for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
    const e = S.mapEdits.cells[`${r.x0 + x},${r.y0 + y}`];
    if (e) for (const [k, v] of Object.entries(e)) z[k][y * w + x] = v;
  }
  S.zone = z; S.undo = []; S.redo = []; S.dirty = false; S.sel = null;
  S.patchBase = JSON.stringify(PATCH_LAYERS.map((k) => z[k]));
  if (S.layer === 'height' || S.layer === 'objects') setLayer('ground');
  setArea('ext');
  setStatus(`Retocando ${w}×${h} casillas del mapa en (${r.x0},${r.y0})`);
}
async function savePatch() {
  const z = S.zone, base = JSON.parse(S.patchBase);
  let n = 0;
  PATCH_LAYERS.forEach((k, li) => {
    for (let i = 0; i < z.w * z.h; i++) {
      if (z[k][i] === base[li][i]) continue;
      const key = `${z.x + (i % z.w)},${z.y + Math.floor(i / z.w)}`;
      (S.mapEdits.cells[key] = S.mapEdits.cells[key] || {})[k] = z[k][i] || '';
      n++;
    }
  });
  try {
    const r = await api('PUT', '/api/map_edits', S.mapEdits);
    S.patchBase = JSON.stringify(PATCH_LAYERS.map((k) => z[k]));
    S.dirty = false;
    renderProps();
    setStatus(`Retoques guardados ✓ (${n} cambios; ${r.cells} casillas en total) · publica para verlos en el juego`, 'ok');
    return true;
  } catch (e) { setStatus('Error al guardar: ' + e.message, 'err'); return false; }
}

// ---------------------------------------------------------------- zonas: abrir, crear, guardar, publicar
function refreshZoneSel() {
  const s = $('zoneSel');
  s.innerHTML = '';
  s.append(el('option', { value: '', textContent: '— Mapa completo —' }));
  for (const z of S.zones) s.append(el('option', { value: z.id, textContent: z.name || z.id, selected: S.zone && S.zone.id === z.id }));
  if (S.zone && !S.zones.some((z) => z.id === S.zone.id)) s.append(el('option', { value: S.zone.id, textContent: (S.zone.name || S.zone.id) + ' (nueva)', selected: true }));
}
function refreshAreaSel() {
  const s = $('areaSel');
  s.innerHTML = '';
  s.disabled = !S.zone;
  if (!S.zone) { s.append(el('option', { textContent: '—' })); return; }
  s.append(el('option', { value: 'ext', textContent: '🌳 Exterior', selected: S.areaKey === 'ext' }));
  for (const iid of Object.keys(S.zone.interiors)) s.append(el('option', { value: iid, textContent: `🏠 ${S.zone.interiors[iid].name || iid}`, selected: S.areaKey === iid }));
}
function setArea(key) {
  S.areaKey = key;
  S.sel = null;
  areaCache = null;
  refreshAreaSel();
  const a = area(), o = areaOrigin();
  centerOn(o.x, o.y, a.w * T, a.h * T);
  renderProps();
  validate();
}
function confirmDiscard() { return !S.dirty || confirm('Hay cambios sin guardar. ¿Descartarlos?'); }
async function openZone(id) {
  if (!confirmDiscard()) { refreshZoneSel(); return; }
  if (!id) { closeZone(true); return; }
  if (S.npcMode) { S.npcMode = false; S.selNpc = null; $('btnNpcs').classList.remove('on'); }
  try {
    const z = await api('GET', `/api/zones/${id}`);
    delete z._file;
    z.interiors = z.interiors || {};
    normalizeArea(z);
    for (const it of Object.values(z.interiors)) normalizeArea(it);
    S.zone = z; S.undo = []; S.redo = []; S.dirty = false;
    refreshZoneSel();
    setArea('ext');
    setStatus(`Zona ${z.name || z.id}`);
  } catch (e) { setStatus('No se pudo abrir: ' + e.message, 'err'); }
}
function closeZone(force) {
  if (!force && !confirmDiscard()) return;
  const z = S.zone;
  S.zone = null; S.sel = null; S.dirty = false; S.areaKey = 'ext'; areaCache = null;
  refreshZoneSel(); refreshAreaSel(); renderProps(); validate();
  if (z) centerOn(z.x * T, z.y * T, z.w * T * 4, z.h * T * 4);
  setStatus('Mapa completo');
}
function dialog(title, fields) {
  return new Promise((resolve) => {
    const f = $('dlgForm');
    f.innerHTML = '';
    f.append(el('h3', { textContent: title, style: 'margin-top:0' }));
    const inputs = {};
    for (const fd of fields) {
      let inp;
      if (fd.options) { inp = el('select'); for (const [v, t] of fd.options) inp.append(el('option', { value: v, textContent: t })); }
      else inp = el('input', { type: 'text', value: fd.value || '', placeholder: fd.placeholder || '' });
      inputs[fd.key] = inp;
      f.append(field(fd.label, inp));
      if (fd.hint) f.append(el('p', { className: 'hint', textContent: fd.hint }));
    }
    f.append(el('div', { className: 'row', style: 'justify-content:flex-end;margin-top:10px' },
      el('button', { value: 'cancel', textContent: 'Cancelar' }), el('button', { value: 'ok', className: 'primary', textContent: 'Aceptar' })));
    const dlg = $('dlg');
    dlg.onclose = () => {
      if (dlg.returnValue !== 'ok') return resolve(null);
      const out = {};
      for (const [k, i] of Object.entries(inputs)) out[k] = i.value.trim();
      resolve(out);
    };
    dlg.showModal();
  });
}
const slug = (s) => s.toLowerCase().normalize('NFD').replace(/[̀-ͯ]/g, '').replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '').slice(0, 36);

async function createZoneDialog(r) {
  const w = r.x1 - r.x0 + 1, h = r.y1 - r.y0 + 1;
  if (w < 2 || h < 2 || w > 120 || h > 120) { setStatus('La zona debe medir entre 2 y 120 casillas por lado', 'err'); draw(); return; }
  const res = await dialog(`Zona nueva (${w}×${h} casillas · ${w * 4}×${h * 4} m)`, [
    { key: 'name', label: 'Nombre', placeholder: 'Escola …' },
    { key: 'id', label: 'Id', placeholder: 'escola_x', hint: 'Minúsculas, números y _. Si lo dejas vacío se genera del nombre.' },
    { key: 'base', label: 'Partir de', options: [['map', 'Las casillas actuales del mapa'], ['urban', 'Vacía (suelo urbano)'], ['grass', 'Vacía (hierba)']],
      hint: 'Las calles vectoriales no se copian: dentro de la zona todo se redibuja desde cero.' },
  ]);
  if (!res) { draw(); return; }
  const id = res.id || slug(res.name || 'zona');
  if (!ID_RE.test(id)) { setStatus('Id no válido', 'err'); return; }
  if (S.zones.some((z) => z.id === id)) { setStatus('Ya existe una zona con ese id', 'err'); return; }
  const z = Object.assign(blankArea(w, h, res.base === 'grass' ? 'g_grass_0' : 'g_urban_0'),
    { id, name: res.name || id, scene: SCENE, x: r.x0, y: r.y0, interiors: {} });
  if (res.base === 'map') {
    setStatus('Copiando casillas del mapa…');
    const map = { ground: 'ground', ground_detail: 'detail', structures: 'structures', cover_low: 'structures', overhead: 'overhead' };
    for (let y = 0; y < h; y++) for (let x = 0; x < w; x++) {
      const tx = r.x0 + x, ty = r.y0 + y;
      const d = await chunkData(Math.floor(tx / CHUNK), Math.floor(ty / CHUNK));
      if (!d) continue;
      const li = (ty % CHUNK) * d.w + (tx % CHUNK);
      for (const [src, dst] of Object.entries(map)) if (d[src] && d[src][li]) z[dst][y * w + x] = S.byId[d[src][li] - 1];
    }
  }
  S.zone = z; S.undo = []; S.redo = []; S.dirty = true;
  refreshZoneSel();
  setArea('ext');
  setStatus('Zona nueva sin guardar');
}

function serialize() {
  const z = JSON.parse(JSON.stringify(S.zone));
  for (const a of [z, ...Object.values(z.interiors)]) {
    a.objects = (a.objects || []).map((o) => {
      const c = { ...o };
      if (c.say) c.say = c.say.filter(Boolean);
      return c;
    });
  }
  return z;
}
async function save() {
  if (!S.zone && S.npcMode) {
    try {
      await api('PUT', '/api/npcs', S.npcs);
      S.dirty = false;
      setStatus('Personajes guardados ✓ (publica para verlos en el juego)', 'ok');
      return true;
    } catch (e) { setStatus('Error al guardar: ' + e.message, 'err'); return false; }
  }
  if (!S.zone) return false;
  if (S.zone.patch) return savePatch();
  const z0 = S.zone, clash = S.zones.find((o) => o.id !== z0.id && z0.x < o.x + o.w && o.x < z0.x + z0.w && z0.y < o.y + o.h && o.y < z0.y + z0.h);
  if (clash) { setStatus(`No se guarda: se solapa con la zona ${clash.id}. Muévela o cambia su tamaño.`, 'err'); return false; }
  if (z0.x < 0 || z0.y < 0 || z0.x + z0.w > 1600 || z0.y + z0.h > 1600) { setStatus('No se guarda: la zona sale del mapa', 'err'); return false; }
  try {
    await api('PUT', `/api/zones/${S.zone.id}`, serialize());
    S.dirty = false;
    S.zones = await api('GET', '/api/zones');
    refreshZoneSel();
    setStatus('Guardado ✓ (publica para verlo en el juego)', 'ok');
    return true;
  } catch (e) { setStatus('Error al guardar: ' + e.message, 'err'); return false; }
}
async function deleteZone() {
  if (!confirm(`¿Borrar la zona ${S.zone.id}? Se guarda una copia en el historial; el mapa original vuelve al publicar.`)) return;
  try {
    if (S.zones.some((z) => z.id === S.zone.id)) await api('DELETE', `/api/zones/${S.zone.id}`);
    S.zones = await api('GET', '/api/zones');
    S.dirty = false;
    closeZone(true);
    setStatus('Zona borrada; publica para restaurar el mapa', 'ok');
  } catch (e) { setStatus('Error: ' + e.message, 'err'); }
}
async function publish() {
  if (S.dirty && !(await save())) return;
  try { await api('POST', '/api/publish'); } catch (e) { setStatus(e.message, 'err'); return; }
  $('btnPublish').disabled = true;
  setStatus('Publicando… (1–3 min)');
  const poll = async () => {
    const st = await api('GET', '/api/publish');
    $('log').textContent = st.log.join('\n') || '…';
    $('log').scrollTop = 1e9;
    if (st.running) { setTimeout(poll, 2000); return; }
    $('btnPublish').disabled = false;
    if (st.ok) {
      setStatus('Publicado ✓ · recarga el juego para verlo', 'ok');
      S.chunks.clear();
      S.lines = prepareLines(await (await fetch(`/data/${SCENE}/lines.json`, { cache: 'no-store' })).json());
      draw();
    } else setStatus('La publicación ha fallado (mira el registro)', 'err');
  };
  poll();
}

// ---------------------------------------------------------------- arranque
async function init() {
  buildSidebar();
  $('btnSave').onclick = save;
  $('btnPublish').onclick = publish;
  $('btnUndo').onclick = () => restore(S.undo, S.redo);
  $('btnRedo').onclick = () => restore(S.redo, S.undo);
  $('btnNewZone').onclick = () => {
    if (S.zone && !confirmDiscard()) return;
    if (S.zone) closeZone(true);
    S.newKind = 'zone';
    S.newZone = !S.newZone;
    $('btnNewZone').classList.toggle('on', S.newZone);
    if (S.newZone && S.scale < 0.5) { S.scale = 0.5; draw(); }
    updateHud();
  };
  $('zoneSel').onchange = (e) => openZone(e.target.value);
  $('btnNpcs').onclick = () => setNpcMode(!S.npcMode);
  $('btnMapEdit').onclick = () => {
    if (S.zone && !confirmDiscard()) return;
    if (S.zone) closeZone(true);
    if (S.npcMode) setNpcMode(false);
    S.newKind = 'patch';
    S.newZone = !S.newZone;
    $('btnMapEdit').classList.toggle('on', S.newZone);
    if (S.newZone) { setStatus('Arrastra un recuadro sobre la parte del mapa que quieres retocar'); if (S.scale < 0.5) { S.scale = 0.5; draw(); } }
    updateHud();
  };
  $('areaSel').onchange = (e) => setArea(e.target.value);
  window.addEventListener('beforeunload', (e) => { if (S.dirty) { e.preventDefault(); e.returnValue = ''; } });
  try {
    const [tj, atlas, lines, zones] = await Promise.all([
      fetch('/assets/tiles.json').then((r) => r.json()), loadImg('/assets/tiles.png'),
      fetch(`/data/${SCENE}/lines.json`).then((r) => r.json()), api('GET', '/api/zones'),
    ]);
    S.tiles = tj.tiles; S.atlas = atlas; S.lines = prepareLines(lines); S.zones = zones;
    setVStyle(await fetch('/assets/palette.json').then((r) => r.json()).catch(() => PAL_FALLBACK));
    S.npcs = await api('GET', '/api/npcs');
    S.overview = await loadImg('/editor/overview.jpg?v=' + Date.now()).catch(() => null);
    if (!S.overview) S.minimap = await loadImg('/assets/minimap.png').catch(() => null);
    for (const n of [...NPC_SPRITES, 'sign']) loadImg(`/assets/sprites/${n}.png`).then((i) => { S.sprites[n] = i; draw(); }).catch(() => {});
  } catch (e) { setStatus('No se pudo cargar el mapa: ' + e.message, 'err'); return; }
  buildTileIndex();
  buildPalette();
  selectPal(S.palette[0].items[0], true);
  refreshZoneSel(); refreshAreaSel(); renderProps(); validate();
  const q = new URLSearchParams(location.search).get('zona');
  if (q) openZone(q);
  else if (S.zones.length) { const z = S.zones[0]; centerOn(z.x * T, z.y * T, z.w * T * 2, z.h * T * 2); S.scale = Math.max(S.scale, 0.5); centerOn((z.x + z.w / 2) * T, (z.y + z.h / 2) * T); }
  else centerOn(800 * T, 800 * T, 80 * T, 50 * T);
  setStatus(q ? 'Abriendo zona…' : 'Listo');
}
init();
