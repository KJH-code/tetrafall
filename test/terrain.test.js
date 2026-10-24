// 지형 장치 테스트: 무너지는 바닥 맵 · 움직이는 발판 맵 · 바닥 없는 맵
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;
function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

// 사람 2명, 블록·아이템 없이
function setupMap(map) {
  const lines = [];
  const g = new Game((s) => lines.push(s));
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.addPlayer(2);
  assert.ok(g.setMap(map));
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return { g, lines, p: (id) => g.players.get(id) };
}

test('무너지는 바닥: 3층 바닥 (사이 2칸), 시작 위치는 맨 위층, 필드 바닥은 없음', () => {
  const { g, p } = setupMap('crumble');
  for (const z of [0, 3, 6]) assert.equal(g.gridAt(4, 4, z), CELL.CRUMBLE, `${z}층`);
  for (const z of [1, 2, 4, 5]) assert.equal(g.gridAt(4, 4, z), 0);
  assert.equal(p(1).z, 7);
  assert.equal(g.hasFloor(), false);
  assert.equal(g.solidAt(4, 4, -1), false, '바닥 아래는 허공');
  assert.equal(g.snapshot().map.floor, false);
});

test(`무너지는 바닥: 밟은 칸은 ${C.CRUMBLE_MS}ms 뒤 사라지고 아래층으로 떨어짐, 떨어진 블록은 안 무너짐`, () => {
  const { g, p } = setupMap('crumble');
  Object.assign(p(1), { x: 4.5, y: 4.5, z: 7 });
  Object.assign(p(2), { x: 8.5, y: 8.5, z: 7 });
  g.tick(TICK);
  assert.ok(g.snapshot().crumbling.some(([x, y, z]) => x === 4 && y === 4 && z === 6), '흔들리는 칸이 스냅샷에');
  run(g, C.CRUMBLE_MS - 3 * TICK);
  assert.equal(g.gridAt(4, 4, 6), CELL.CRUMBLE, '아직');
  run(g, 4 * TICK);
  assert.equal(g.gridAt(4, 4, 6), 0, '사라짐');
  assert.ok(g.drainEvents().some((e) => e.type === 'crumble' && e.x === 4 && e.y === 4));
  run(g, 800);
  assert.equal(p(1).z, 4, '가운데층으로 떨어짐');
  // 떨어진 테트리미노 칸 위는 안 무너짐
  g.grid[g.idx(1, 1, 7)] = CELL.SHAPE_BASE;
  g.gridChanged();
  Object.assign(p(2), { x: 1.5, y: 1.5, z: 8, vz: 0 });
  run(g, C.CRUMBLE_MS * 2);
  assert.equal(g.gridAt(1, 1, 7), CELL.SHAPE_BASE);
  assert.equal(p(2).z, 8);
});

test('무너지는 바닥: 층이 꽉 차 있어도 층 클리어로 안 지워짐, 용암은 1분 뒤부터 (쌓인 높이와 상관없이)', () => {
  const { g, lines } = setupMap('crumble');
  const piece = g.makePiece('O', 0, 0, 0, 7);
  g.addPiece(piece, { phase: 'falling', controller: null, stepMs: 1e9, nextStepAt: 1e18, controlEndsAt: 0 });
  g.landPiece(piece);
  assert.equal(g.gridAt(5, 5, 0), CELL.CRUMBLE, '바닥층 그대로');
  // 시간만 당겨 봄 (가만히 서 있으면 바닥이 무너져 판이 먼저 끝나므로 tick 대신 updateLava)
  g.roundStartTime = g.time - 59000;
  g.updateLava(TICK);
  assert.equal(g.lava.active, false);
  g.roundStartTime = g.time - 60100;
  g.updateLava(TICK);
  assert.equal(g.lava.active, true);
  assert.ok(lines.some((l) => l.includes('1:00 지남 → 용암 상승 시작')));
});

test('바닥 없는 맵: 구멍에 빠지면 낙사, 아이템은 구멍 위에 안 생김', () => {
  const { g, p } = setupMap('platforms');
  Object.assign(p(1), { x: 3.5, y: 3.5, z: 2 }); // 구석 섬·가운데 섬·발판 어디에도 안 걸치는 구멍
  run(g, 1500);
  assert.equal(p(1).alive, false);
  assert.equal(p(1).deathCause, 'fall');
  for (let i = 0; i < 30; i++) {
    g.rng = () => (i * 0.137) % 1;
    g.items = [];
    if (g.spawnItem('jump')) assert.ok(!g.holeAt(g.items[0].x, g.items[0].y), '구멍 위 아이템');
  }
});

test('움직이는 발판: 네 구석 섬 + 가운데 높은 섬, 시작 위치는 섬 위, 발판은 끝에서 돌아옴', () => {
  const { g, p } = setupMap('platforms');
  for (const id of [1, 2]) assert.equal(p(id).z, 2, '구석 섬 위');
  assert.equal(g.columnTop(4, 4), 5, '가운데 섬');
  assert.equal(g.columnTop(4, 1), 0, '섬 사이는 구멍');
  const pf = g.platforms[0];
  assert.equal(pf.x, 3);
  run(g, 1000);
  assert.ok(Math.abs(pf.x - (3 + C.PLATFORM_SPEED)) < 0.05, `1초에 ${C.PLATFORM_SPEED}칸`);
  run(g, 2000 / C.PLATFORM_SPEED);
  assert.ok(pf.x <= 5 && pf.x > 3.5, '끝(5)에서 돌아오는 중');
  const snap = g.snapshot().platforms;
  assert.equal(snap.length, g.platforms.length);
});

test('움직이는 발판: 위에 서면 같이 움직이고, 승강기는 태워 올림. 테트리미노는 발판을 통과', () => {
  const { g, p } = setupMap('platforms');
  const pf = g.platforms[0]; // 아래, x 3 → 5
  Object.assign(p(1), { x: pf.x + 1, y: pf.y + 1, z: pf.top, vz: 0, grounded: true });
  const x0 = p(1).x;
  run(g, 1000);
  assert.equal(p(1).alive, true, '발판 위에서 안 떨어짐');
  assert.ok(Math.abs(p(1).x - x0 - C.PLATFORM_SPEED) < 0.1, `발판과 같이 움직임 (${(p(1).x - x0).toFixed(2)})`);
  // 승강기 (z 2 → 5)
  const el = g.platforms.find((q) => q.axis === 'z' && q.from === 2);
  Object.assign(p(2), { x: el.x + 0.5, y: el.y + 1, z: el.top, vz: 0, grounded: true });
  run(g, 1500);
  assert.ok(p(2).z > 3, `승강기가 태워 올림 (z=${p(2).z.toFixed(2)})`);
  // 블록은 발판을 무시하고 격자 기준으로 착지
  const piece = g.makePiece('O', 0, 3, 1, 10);
  g.updateLanding(piece);
  assert.equal(piece.landZ, 0, '발판 밑 구멍 바닥(z=0)까지');
});
