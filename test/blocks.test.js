// 블록 모습 (shared/block-style.js · config WORLD_BLOCK_STYLES · 테마 terrain.block · PIECE_LOOK, 화면은 client/blocks.js · render.js)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { blockStyle, openBits, cellLooks, cellRand, sproutSpots } from '../shared/block-style.js';

const NUM = ['segs', 'disp', 'step', 'edge', 'wear', 'mottle', 'topLift', 'veins', 'veinScale', 'lip', 'sheen', 'sideShade', 'ao', 'hi'];
const PAIRS = ['chamfer', 'blotch', 'height', 'grid', 'strata'];
const BLOCK_KEYS = new Set([...NUM, ...PAIRS, 'brick', 'top', 'side', 'rim', 'tints', 'sprout']);
const SPROUTS = ['crystal', 'basalt', 'mushroom', 'brick', 'ledge', 'tuft'];

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

test('입체감: 옆면이 윗면보다 어둡고, 벽 밑 그늘·윗 모서리 하이라이트', () => {
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    const s = blockStyle(t.terrain);
    assert.ok(s.sideShade < 0.8 && s.sideShade > 0.4, `${id}.sideShade`);
    assert.ok(s.ao > 0 && s.ao < 0.8, `${id}.ao`);
    assert.ok(s.hi > 0, `${id}.hi`);
    assert.ok(s.topLift > 1, `${id}.topLift`);
  }
});

test('튀어나온 조각: 테마마다 하나, 값 범위', () => {
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    const sp = blockStyle(t.terrain).sprout;
    assert.ok(sp && SPROUTS.includes(sp.kind), `${id}.sprout`);
    assert.ok(sp.side >= 0 && sp.side <= 0.4 && sp.top >= 0 && sp.top <= 0.4, `${id}: 과하지 않게`);
    assert.ok(sp.size[0] > 0 && sp.size[0] <= sp.size[1] && sp.size[1] <= 2, `${id}.size`);
  }
  assert.equal(blockStyle(C.WORLD_THEMES.crystal.terrain).sprout.kind, 'crystal', '수정 동굴은 결정이 튀어나옴');
  assert.ok(C.BLOCK_SPROUT_TOP_SCALE < 1 && C.BLOCK_SPROUT_MAX > 0);
});

test('그늘 비트: 위 칸 블록 → 윗면 가장자리, 바깥 아래 막힘(바닥 포함) → 옆면 아래', () => {
  const W = 3, D = 1, H = 2;
  const grid = new Uint8Array(W * D * H);
  const at = (x, y, z) => (z * D + y) * W + x;
  grid[at(0, 0, 0)] = CELL.TERRAIN;
  grid[at(1, 0, 0)] = CELL.TERRAIN;
  grid[at(1, 0, 1)] = CELL.SHAPE_BASE; // (0,0,0) 의 +x 위에 블록 → (0,0,0) 윗면 +x 가장자리 그늘
  const { open, ao, lift } = cellLooks(grid, W, D, H);
  assert.equal(open.length, 2);
  assert.ok(ao[0] & 1, '윗면 +x 그늘');
  assert.ok(ao[0] & 32, '바닥 층 옆면은 바닥에 닿음 (−x)');
  assert.ok(lift.every((v) => v >= -0.5 && v < 0.5));
});

test('칸 난수: 0..1, 같은 자리 같은 값, 자리마다 다름', () => {
  const vals = new Set();
  for (let x = 0; x < 20; x++) for (let y = 0; y < 20; y++) {
    const v = cellRand(x, y, 3, 2);
    assert.ok(v >= 0 && v < 1);
    assert.equal(v, cellRand(x, y, 3, 2));
    vals.add(Math.floor(v * 10));
  }
  assert.equal(vals.size, 10, '고르게 퍼짐');
});

test('튀어나온 조각 자리: 드러난 면에만, 윗면은 가장자리, 최대 수', () => {
  const W = 6, D = 6, H = 3;
  const grid = new Uint8Array(W * D * H);
  for (let y = 0; y < D; y++) for (let x = 0; x < W; x++) grid[y * W + x] = CELL.TERRAIN; // 바닥 한 층 꽉
  grid[(1 * D + 2) * W + 2] = CELL.TERRAIN; // 위에 한 칸
  const sp = { kind: 'crystal', side: 1, top: 1, size: [0.5, 1] };
  const spots = sproutSpots(grid, W, D, H, null, sp, 1000);
  const open = openBits(grid, W, D, H);
  assert.ok(spots.length > 0);
  for (const p of spots) {
    if (p.face < 4) {
      const nx = [1, -1, 0, 0][p.face], ny = [0, 0, 1, -1][p.face];
      const x = p.x + nx, y = p.y + ny;
      assert.ok(x < 0 || y < 0 || x >= W || y >= D || grid[(p.z * D + y) * W + x] !== CELL.TERRAIN, '옆이 빈 면');
    } else {
      assert.ok(Math.max(Math.abs(p.u), Math.abs(p.v)) >= 0.35, '윗면은 가장자리');
      assert.ok(p.s <= sp.size[1] * C.BLOCK_SPROUT_TOP_SCALE + 1e-9, '윗면은 작게');
      assert.ok(p.z + 1 >= H || grid[((p.z + 1) * D + p.y) * W + p.x] === 0, '위가 빈 칸');
    }
    assert.ok(p.s >= 0 && p.s <= sp.size[1]);
  }
  assert.ok(open.length === W * D + 1);
  assert.deepEqual(sproutSpots(grid, W, D, H, null, sp, 1000), spots, '같은 판이면 같은 자리');
  const few = sproutSpots(grid, W, D, H, null, sp, 5);
  assert.equal(few.length, 5, '최대 수');
  assert.ok(few[4].y > few[0].y || few[4].z > few[0].z, '넘치면 앞쪽만이 아니라 고르게 솎음');
  assert.equal(sproutSpots(grid, W, D, H, null, null, 50).length, 0);
});
