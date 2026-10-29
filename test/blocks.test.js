// 블록 모습 (shared/block-style.js · config WORLD_BLOCK_STYLES · 테마 terrain.block · PIECE_LOOK, 화면은 client/blocks.js · render.js)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { blockStyle, openBits } from '../shared/block-style.js';

const NUM = ['segs', 'disp', 'step', 'edge', 'wear', 'mottle', 'topLift', 'veins', 'veinScale', 'lip', 'sheen'];
const PAIRS = ['chamfer', 'blotch', 'height', 'grid', 'strata'];
const BLOCK_KEYS = new Set([...NUM, ...PAIRS, 'brick', 'top', 'side', 'rim', 'tints']);

test('지형 블록 스타일: 재혁이 고른 주상절리, 윗면에만 칸 경계', () => {
  assert.equal(C.WORLD_BLOCK_STYLE, 'columns');
  const s = C.WORLD_BLOCK_STYLES.columns;
  assert.ok(s.step > 0, '윗면 칸마다 높낮이');
  assert.ok(s.grid[0] > 0 && s.grid[0] <= 0.3, '윗면 칸 경계는 알아볼 정도로만');
  assert.ok(s.grid[1] > 0 && s.grid[1] < 0.06);
});

test('테마마다 셰이더 값이 다 있고 범위 안', () => {
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    const s = blockStyle(t.terrain);
    assert.ok(s, id);
    for (const k of NUM) assert.ok(Number.isFinite(s[k]) && s[k] >= 0, `${id}.${k}`);
    for (const k of PAIRS) assert.ok(s[k].length === 2 && s[k].every(Number.isFinite), `${id}.${k}`);
    assert.ok(s.brick === null || (s.brick.length === 4 && s.brick.every((v) => v >= 0)), `${id}.brick`);
    assert.ok(s.segs >= 1 && Number.isInteger(s.segs), `${id}.segs`);
    assert.equal(s.tints.length, 3, `${id}.tints`);
    for (const c of [s.top, s.side, s.rim, ...s.tints]) assert.ok(Number.isInteger(c) && c >= 0 && c <= 0xffffff, `${id} 색`);
    // 판정 칸은 그대로라 화면 윗면이 크게 오르내리면 발이 떠 보이거나 묻힘
    assert.ok(s.step / 2 + s.disp * 0.3 <= 0.09, `${id}: 발 높이 어긋남`);
    assert.ok(s.chamfer[0] <= s.chamfer[1] && s.chamfer[1] < 0.25, `${id}.chamfer`);
    if (t.terrain.block) for (const k of Object.keys(t.terrain.block)) assert.ok(BLOCK_KEYS.has(k), `${id}.block.${k} 모르는 값`);
  }
});

test('테마 결: 재질마다 다르게', () => {
  const s = (id) => blockStyle(C.WORLD_THEMES[id].terrain);
  assert.ok(s('meadow').lip > 0, '초원 잔디가 옆으로');
  assert.ok(s('mushroom').lip > 0, '버섯 숲 이끼');
  assert.ok(s('desert').strata[1] > 0, '사막 사암 층');
  assert.ok(s('crystal').sheen > 0 && s('crystal').veins > 0, '수정 결정 면 + 맥');
  assert.ok(s('volcano').veins > 0 && s('volcano').veins < C.WORLD_BLOCK_STYLES.columns.veins, '화산 용암 금 약하게');
  assert.ok(s('skycastle').brick && s('castle').brick, '성 돌벽돌');
  for (const id of ['meadow', 'desert', 'skycastle', 'mushroom', 'castle']) assert.equal(s(id).veins, 0, `${id}: 빛 색이 없으면 빛 금 없음`);
});

test('스타일 이름이 표에 없으면 예전 텍스처 블록 (null)', () => {
  assert.equal(blockStyle(C.WORLD_THEMES.volcano.terrain, 'tex'), null);
  assert.equal(blockStyle(null), null);
});

test('이웃 빈 방향 비트: 같은 지형 칸끼리만 막힘, 바닥 아래는 막힘, 건너뛴 칸 빠짐', () => {
  const W = 3, D = 2, H = 2;
  const grid = new Uint8Array(W * D * H);
  const at = (x, y, z) => (z * D + y) * W + x;
  grid[at(0, 0, 0)] = CELL.TERRAIN;
  grid[at(1, 0, 0)] = CELL.TERRAIN;
  grid[at(2, 0, 0)] = CELL.SHAPE_BASE; // 다른 블록이 옆에 와도 지형 모서리는 드러난 채
  grid[at(0, 0, 1)] = CELL.TERRAIN;
  const bits = openBits(grid, W, D, H);
  assert.deepEqual(bits, [2 | 4 | 8, 1 | 4 | 8 | 16, 1 | 2 | 4 | 8 | 16]);
  assert.deepEqual(openBits(grid, W, D, H, new Set([at(1, 0, 0)])), [1 | 2 | 4 | 8, 1 | 2 | 4 | 8 | 16], '건너뛴 칸은 빈 칸으로');
});

test('테트리미노 칸: 작고 둥글고 살짝 빛나서 지형과 구분', () => {
  const P = C.PIECE_LOOK;
  assert.ok(P.size < 1 && P.size >= 0.9, '칸 사이 틈');
  assert.ok(P.bevel > 0 && P.bevel < P.size / 2, '둥근 모서리');
  assert.ok(P.glow > 0 && P.glow < 0.4, '살짝 빛남');
});
