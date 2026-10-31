// G3 정답 자료 (JS 판 shared/block-style.js) → tests/fixtures/block_style.json. 실행: node godot/client/tools/fixtures_g3.mjs
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { CONFIG as C } from '../../../shared/config.js';
import { blockStyle, cellLooks, sproutSpots, cellRand } from '../../../shared/block-style.js';

const out = path.join(path.dirname(fileURLToPath(import.meta.url)), '../tests/fixtures');
let seed = 7;
const rnd = () => ((seed = (seed * 1103515245 + 12345) % 2147483648) / 2147483648);

// 작은 격자: 바닥 지형 + 기둥 몇 개 + 다른 블록 섞임
const W = 7, D = 6, H = 5;
const grid = new Array(W * D * H).fill(0);
for (let y = 0; y < D; y++) for (let x = 0; x < W; x++) {
  const h = 1 + Math.floor(rnd() * 3);
  for (let z = 0; z < h; z++) grid[(z * D + y) * W + x] = rnd() < 0.85 ? 1 : 10 + Math.floor(rnd() * 7);
}
const skip = [((1 * D + 2) * W + 3)];
const looks = cellLooks(grid, W, D, H, new Set(skip));
const themes = {};
for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
  const s = blockStyle(t.terrain);
  if (!s) continue;
  themes[id] = { style: s, sprouts: s.sprout ? sproutSpots(grid, W, D, H, new Set(skip), s.sprout, 1e9) : [], few: s.sprout ? sproutSpots(grid, W, D, H, new Set(skip), s.sprout, 9) : [] };
}
const rands = [];
for (let i = 0; i < 200; i++) {
  const a = [Math.floor(rnd() * 40) - 5, Math.floor(rnd() * 40) - 5, Math.floor(rnd() * 32), Math.floor(rnd() * 60)];
  rands.push([...a, cellRand(...a)]);
}
fs.writeFileSync(path.join(out, 'block_style.json'), JSON.stringify({ W, D, H, grid, skip, looks, themes, rands }));

// 비교 장면 (shaders/demo) 지형: 테마마다 그 맵의 시작 지형 12×12 (shared/maps.js mapColumns) → demo/terrain_grids.json
import { mapColumns } from '../../../shared/maps.js';
const TW = 12, TH = 8;
const grids = {};
for (const [map, theme] of Object.entries(C.WORLD_MAP_THEME)) {
  if (grids[theme]) continue;
  const g = new Array(TW * TW * TH).fill(0);
  for (const [x, y, z] of mapColumns(map === 'flat' ? 'stairs' : map, TW, TW)) // 초원(flat) 은 지형이 없어 계단 지형으
    for (let k = 0; k < Math.min(z, TH); k++) g[(k * TW + y) * TW + x] = 1;
  grids[theme] = g;
}
fs.writeFileSync(path.join(out, '../../shaders/demo/terrain_grids.json'), JSON.stringify({ W: TW, D: TW, H: TH, grids }));
