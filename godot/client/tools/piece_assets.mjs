// G3 테트리미노 칸 자산을 JS 판에서 뽑음 (모양·면 그림이 JS 와 똑같게): 실행 node godot/client/tools/piece_assets.mjs
// - assets/pieces/shapes.json: 테마마다 (기본 'toy' 포함) 칸 모양 (client/piece-shapes.js pieceGeometry) 보통·low 두 벌 — 게임 좌표 (z 위) 삼각형 목록 pos·nrm·uv·acc
// - assets/pieces/<style>.png: 면 그림 (client/textures.js pieceTexture, 브라우저 캔버스라 Playwright 로)
import fs from 'node:fs';
import path from 'node:path';
import http from 'node:http';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../../../shared/config.js';
import { pieceSpec } from '../../../shared/piece-look.js';
import { pieceGeometry } from '../../../client/piece-shapes.js';

const here = path.dirname(fileURLToPath(import.meta.url));
const root = path.resolve(here, '../../..');
const out = path.join(here, '../assets/pieces');
const r4 = (v) => Math.round(v * 1e4) / 1e4;
const dump = (g) => {
  const a = g.attributes;
  return { pos: Array.from(a.position.array, r4), nrm: Array.from(a.normal.array, r4), uv: Array.from(a.uv.array, r4), acc: Array.from(a.aAcc.array) };
};
const shapes = {};
const styles = new Set();
for (const id of ['toy', ...Object.keys(C.WORLD_THEMES)]) {
  const s = pieceSpec(id === 'toy' ? null : id);
  if (id !== 'toy' && !C.WORLD_THEMES[id].piece) continue;
  styles.add(s.style);
  shapes[id] = { normal: dump(pieceGeometry(s, false)), low: dump(pieceGeometry(s, true)) };
}
fs.writeFileSync(path.join(out, 'shapes.json'), JSON.stringify(shapes));

// 면 그림: client/ 를 서빙하고 페이지에서 pieceTexture(style).image → PNG
const srv = http.createServer((req, res) => {
  const u = decodeURIComponent(req.url.split('?')[0]);
  const f = u === '/' ? null : u === '/vendor/three.module.js' ? path.join(root, 'node_modules/three/build/three.module.js') : u.startsWith('/vendor/jsm/') ? path.join(root, 'node_modules/three/examples/jsm', u.slice(12)) : u.startsWith('/shared/') ? path.join(root, u) : path.join(root, 'client', u);
  if (!f) { res.writeHead(200, { 'content-type': 'text/html' }); return res.end('<script type="importmap">{"imports":{"three":"/vendor/three.module.js","three/addons/":"/vendor/jsm/"}}</script>'); }
  if (!fs.existsSync(f)) { res.writeHead(404); return res.end(); }
  res.writeHead(200, { 'content-type': 'text/javascript' });
  fs.createReadStream(f).pipe(res);
}).listen(0);
const { chromium } = createRequire(import.meta.url)('playwright');
const b = await chromium.launch();
const p = await b.newPage();
await p.goto(`http://localhost:${srv.address().port}/`);
const pngs = await p.evaluate(async (list) => {
  const { pieceTexture } = await import('/textures.js');
  const o = {};
  for (const s of list) o[s] = pieceTexture(s).image.toDataURL('image/png');
  return o;
}, [...styles]);
for (const [s, url] of Object.entries(pngs)) fs.writeFileSync(path.join(out, `${s}.png`), Buffer.from(url.split(',')[1], 'base64'));
await b.close();
srv.close();
console.log('shapes', Object.keys(shapes).join(' '), '· faces', Object.keys(pngs).join(' '));
