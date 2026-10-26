// 하늘 계단 (대기실 옵션): 다음 블록들이 미리 높은 하늘에 떠서 천천히 내려오고, 이웃끼리 점프로 건너는 계단이 된다
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game, skyReach, cellGap, warmUpPlacement } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL, SHAPE_NAMES, rotatedCells, footprint } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;

function seeded(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

// 2명 판 (사람 둘은 가장자리 근처에 가만히). 아이템은 안 나오게
function setup({ sky = true, seed = 1, n = 2 } = {}) {
  const lines = [];
  const g = new Game((s) => lines.push(s), { skyStairs: sky });
  g.rng = seeded(seed);
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  assert.ok(g.startRound());
  g.powerItemNextAt = Infinity;
  g.controlItemNextAt = Infinity;
  return { g, lines };
}

const skies = (g) => g.pieces.filter((pc) => pc.sky).sort((a, b) => a.id - b.id);

test('하늘 계단: 닿는 거리 R(h) = 이동 속도 × 공중 시간 (꼭대기에서 공중 점프)', () => {
  assert.ok(Math.abs(skyReach(0) - 5.76) < 0.05);
  assert.ok(Math.abs(skyReach(1) - 5.29) < 0.05);
  assert.ok(Math.abs(skyReach(2) - 4.66) < 0.05);
  assert.equal(skyReach(3), 0, '2단 점프 최고(약 2.8칸)보다 높으면 못 닿음');
  assert.equal(cellGap({ px: 0, py: 0, cells: [[0, 0]] }, { px: 1, py: 0, cells: [[0, 0]] }), 0, '붙은 칸');
  assert.equal(cellGap({ px: 0, py: 0, cells: [[0, 0]] }, { px: 3, py: 0, cells: [[0, 0]] }), 2);
  assert.ok(Math.abs(cellGap({ px: 0, py: 0, cells: [[0, 0]] }, { px: 2, py: 2, cells: [[0, 0]] }) - Math.SQRT2) < 1e-9);
});

test('하늘 계단 끔: new Game() 기본은 끔이고 격자 높이·낙하·동시 수가 예전 그대로', () => {
  const { g, lines } = setup({ sky: false });
  assert.equal(g.skyStairs, false);
  assert.equal(g.H, C.GRID_H);
  assert.equal(g.grid.length, g.W * g.D * C.GRID_H);
  assert.equal(g.snapshot().field.h, C.GRID_H);
  run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
  assert.equal(g.pieces.length, 1, '판 시작 첫 블록 (두 번째는 AUTO_SPAWN_DELAY 뒤)');
  const pc = g.pieces[0];
  assert.equal(pc.sky, undefined);
  assert.ok(Math.abs(pc.stepMs - C.AUTO_FALL_STEP_MS) < 5, '판 시작 낙하 간격 (RAMP 시작값)');
  assert.equal(pc.pz, C.PIECE_SPAWN_Z);
  assert.ok(!lines.some((l) => l.includes('하늘 계단')), '끔은 판 시작 로그도 예전과 같음');
});

test('하늘 계단 끔: 옵션을 켰다 끈 게임은 처음부터 끈 게임과 같은 시드에서 똑같이 흘러감', () => {
  const a = new Game(() => {}, { skyStairs: false });
  const b = new Game(() => {}, { skyStairs: true });
  assert.ok(b.setSkyStairs(false));
  for (const g of [a, b]) {
    g.rng = seeded(7);
    g.addPlayer(1);
    g.addPlayer(2);
    g.startRound();
    run(g, 40000);
  }
  assert.deepEqual(Array.from(b.grid), Array.from(a.grid));
  assert.deepEqual(
    b.pieces.map((pc) => [pc.shape, pc.px, pc.py, pc.pz]),
    a.pieces.map((pc) => [pc.shape, pc.px, pc.py, pc.pz]),
  );
});

test('하늘 계단 켬: 격자 높이 32, 하늘에 7개, 이웃끼리 높이차 1~2·점프로 닿는 틈, 최고 32', () => {
  for (const seed of [1, 2, 3, 4, 5]) {
    const { g, lines } = setup({ seed });
    assert.equal(g.H, C.SKY_GRID_H);
    assert.equal(g.grid.length, g.W * g.D * C.SKY_GRID_H);
    assert.equal(g.snapshot().field.h, C.SKY_GRID_H);
    assert.ok(lines.includes('  하늘 계단: 켬'));
    run(g, C.FIRST_SPAWN_DELAY_MS + TICK * (C.SKY_COUNT + 1)); // 한 틱에 하나씩 (SKY_SPAWN_PER_TICK)
    const s = skies(g);
    assert.equal(s.length, C.SKY_COUNT);
    for (const pc of s) {
      assert.equal(pc.stepMs, C.SKY_FALL_STEP_MS);
      assert.ok(pc.pz + 1 <= C.SKY_TOP_Z);
      assert.ok(pc.pz > pc.landZ);
    }
    assert.equal(s[0].pz, s[0].landZ + C.SKY_BASE_UP, '사슬 첫 블록 = 착지 높이 + SKY_BASE_UP');
    for (let i = 1; i < s.length; i++) {
      const rise = s[i].pz - s[i - 1].pz;
      assert.ok(rise >= C.SKY_RISE_MIN && rise <= C.SKY_RISE_MAX, `높이차 ${rise}`);
      const gap = cellGap(s[i], s[i - 1]);
      assert.ok(gap >= C.SKY_GAP_MIN && gap <= skyReach(rise) * C.SKY_REACH_SAFETY, `틈 ${gap}`);
    }
    // 공중 블록끼리 같은 기둥 없음
    const cols = new Set();
    for (const pc of s) for (const [dx, dy] of pc.cells) {
      const k = (pc.px + dx) * 100 + pc.py + dy;
      assert.ok(!cols.has(k));
      cols.add(k);
    }
    assert.ok(g.snapshot().pieces.every((pc) => pc.sky === true));
  }
});

test('하늘 계단 켬: 모든 하늘 블록이 같은 순간에 한 칸씩 내려가서 높이차가 그대로', () => {
  const { g } = setup({ seed: 3 });
  run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
  const before = new Map(skies(g).map((pc) => [pc.id, pc.pz]));
  for (let k = 1; k <= 3; k++) {
    run(g, C.SKY_FALL_STEP_MS);
    for (const pc of skies(g)) if (before.has(pc.id) && pc.landZ < before.get(pc.id) - k) assert.equal(pc.pz, before.get(pc.id) - k);
  }
});

test('하늘 계단 켬: 용암 전에는 바닥에 쌓이고 (압사 포함), 착지하면 맨 위에 새 블록이 붙어 7개 유지', () => {
  const { g } = setup({ seed: 2, n: 3 }); // 한 명 깔려도 판이 안 끝나게
  run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
  const low = skies(g)[0];
  // 가장 낮은 블록 밑에 2번을 세움 → 깔림
  const [cx, cy] = low.cells[0];
  const p2 = g.players.get(2);
  Object.assign(p2, { x: low.px + cx + 0.5, y: low.py + cy + 0.5, z: g.columnTop(low.px + cx, low.py + cy), vx: 0, vy: 0, vz: 0 });
  const steps = low.pz - low.landZ;
  run(g, steps * C.SKY_FALL_STEP_MS + TICK);
  assert.ok(!g.pieces.includes(low), '착지함');
  for (const [dx, dy] of low.cells) assert.ok(g.gridAt(low.px + dx, low.py + dy, low.landZ), '격자에 남음');
  assert.equal(p2.alive, false);
  assert.equal(g.deaths[0].cause, 'crush');
  assert.equal(skies(g).length, C.SKY_COUNT, '맨 위에 새로 붙음');
});

test('하늘 계단 켬: 용암이 켜진 뒤 용암 표면에 닿은 하늘 블록은 녹아 사라짐 (격자에 안 남음)', () => {
  const { g } = setup({ seed: 4 });
  run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
  const low = skies(g)[0];
  g.lava = { active: true, z: low.pz - 0.5, startedAt: g.time };
  g.drainEvents();
  for (let t = 0; t < C.SKY_FALL_STEP_MS + TICK; t += TICK) {
    for (const p of g.players.values()) Object.assign(p, { z: 25, vz: 0 }); // 용암에 안 죽게 (테스트용)
    g.tick(TICK);
  }
  assert.ok(!g.pieces.includes(low), '녹음');
  for (const [dx, dy] of low.cells) for (let z = 0; z < g.H; z++) assert.equal(g.gridAt(low.px + dx, low.py + dy, z), 0);
  assert.ok(g.drainEvents().some((e) => e.type === 'melt' && e.cells.length === 4));
});

test('하늘 계단: 켬 판에는 조종권 아이템이 안 나옴 (CONTROL_ITEM 이 켜져도)', () => {
  const old = C.CONTROL_ITEM;
  C.CONTROL_ITEM = true;
  try {
    const on = setup({ sky: true }).g;
    const off = setup({ sky: false }).g;
    for (const g of [on, off]) g.controlItemNextAt = g.time;
    run(on, TICK * 3);
    run(off, TICK * 3);
    assert.equal(on.controlItemOn(), false);
    assert.ok(!on.items.some((it) => it.type === 'control'));
    assert.equal(off.controlItemOn(), true);
    assert.ok(off.items.some((it) => it.type === 'control'), '끔 판은 그대로 나옴');
  } finally {
    C.CONTROL_ITEM = old;
  }
});

test('하늘 계단: 블록 마스터는 옵션을 무시 (자동 블록이 없음)', () => {
  const g = new Game(() => {}, { skyStairs: true });
  g.rng = seeded(1);
  for (let i = 1; i <= 3; i++) g.addPlayer(i);
  g.setMode('master');
  g.startRound();
  assert.equal(g.sky, false);
  assert.equal(g.H, C.GRID_H);
});

test('하늘 계단: 판 사이에만 바꿈, 방은 기본 켬이고 호스트만 바꿈', () => {
  const g = new Game(() => {});
  assert.ok(g.setSkyStairs(true));
  assert.equal(g.setSkyStairs(true), false, '같은 값');
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  assert.equal(g.setSkyStairs(false), false, '판 중엔 못 바꿈');

  const ws = () => ({ OPEN: 1, readyState: 1, msgs: [], send(t) { this.msgs.push(JSON.parse(t)); } });
  const rooms = new Rooms({ openLog: () => ({ log() {}, close() {} }), rng: seeded(1) });
  const a = rooms.connect(ws());
  const b = rooms.connect(ws());
  rooms.message(a, { type: 'create', name: 'x' });
  const room = a.room;
  assert.equal(room.game.skyStairs, C.SKY_STAIRS_DEFAULT);
  rooms.message(b, { type: 'join', code: room.code });
  rooms.message(b, { type: 'skyStairs', on: false });
  assert.equal(room.game.skyStairs, true, '호스트 아님');
  rooms.message(a, { type: 'skyStairs', on: false });
  assert.equal(room.game.skyStairs, false);
  assert.equal(room.game.snapshot().skyStairs, false);
});

test('하늘 계단: 봇은 용암이 다가오면 점프로 닿는 하늘 블록에 올라탐 (3번 돌려 확인)', () => {
  for (const seed of [11, 12, 13]) {
    const g = new Game(() => {}, { skyStairs: true });
    g.rng = seeded(seed);
    const h = g.addPlayer(1);
    g.setSpectator(h.id, true);
    g.addBot();
    g.addBot();
    g.startRound();
    g.powerItemNextAt = Infinity;
    g.controlItemNextAt = Infinity;
    run(g, C.FIRST_SPAWN_DELAY_MS + TICK);
    // 가장 낮은 하늘 블록을 바닥 1칸 위로 내리고 (윗면 2칸), 봇 하나를 그 옆 바닥에, 다른 봇은 멀리
    const low = skies(g)[0];
    low.pz = low.landZ + 1;
    g.updateLanding(low);
    g.refreshPieceCells();
    low.nextStepAt = g.time + 60000; // 테스트 동안 안 내려옴
    const [bot, other] = [...g.players.values()].filter((p) => p.isBot);
    const [cx, cy] = low.cells[0];
    const x = low.px + cx + 0.5;
    const y = low.py + cy + 0.5;
    const nx = x + (x < g.W / 2 ? -1.5 : 1.5);
    Object.assign(bot, { x: Math.max(0.5, Math.min(g.W - 0.5, nx)), y, z: g.columnTop(Math.floor(nx), Math.floor(y)), vx: 0, vy: 0, vz: 0 });
    Object.assign(other, { x: 0.5, y: 0.5 });
    let onIt = false;
    for (let t = 0; t < 3000 && !onIt; t += TICK) {
      g.lava = { active: true, z: -0.5, startedAt: g.time }; // 바닥 바로 아래에 멈춘 용암 (봇이 "가깝다"고만 느낌)
      g.tick(TICK);
      onIt = bot.grounded && Math.abs(bot.z - (low.pz + 1)) < 0.1;
    }
    assert.ok(onIt, `seed ${seed}: 봇이 하늘 블록 위에 올라섬`);
  }
});

test('하늘 계단: 켬 판은 SKY_LAVA_TRIGGER_MS 가 지나면 쌓인 높이와 상관없이 용암 시작, 끔 판은 예전 그대로 (높이만)', () => {
  assert.equal(C.SKY_LAVA_TRIGGER_MS, 60000);
  for (const sky of [true, false]) {
    const { g, lines } = setup({ sky, n: 3 });
    g.updateSpawning = () => {}; // 블록 없이 (쌓인 높이 0) 시간만 보냄
    for (const p of g.players.values()) p.shieldUntil = Infinity;
    run(g, C.SKY_LAVA_TRIGGER_MS - 500);
    assert.equal(g.lava.active, false, `${sky}: 아직`);
    run(g, 1000);
    assert.equal(g.lava.active, sky, sky ? '켬: 시간이 지나 시작' : '끔: 쌓인 게 없으면 안 옴');
    if (sky) assert.ok(lines.some((l) => l.startsWith('  [용암] 1:00 지남 (하늘 계단)') && l.includes('용암 상승 시작')), lines.filter((l) => l.includes('[용암]')).join('\n'));
  }
});

// ---------- 판 시작 랙 (2026-10-26 버그: 사슬 7개를 한 틱에 놓아 서버 틱이 0.2~0.9초 멈춤) ----------

test('자리 점수 빠른 계산 (placementScorer) 은 placementScore 와 같은 값 — 무작위 지형 여러 판, 모든 자리', () => {
  const rng = seeded(42);
  for (let trial = 0; trial < 40; trial++) {
    const g = new Game(() => {});
    g.setFieldSize([10, 12, 14][trial % 3]);
    // 무작위 기둥 (가장 낮은 층에 구멍·덩어리가 여러 모양으로 생기게 0~2 위주)
    for (let x = 0; x < g.W; x++) for (let y = 0; y < g.D; y++) {
      const h = rng() < 0.6 ? 0 : Math.floor(rng() * 3);
      for (let z = 0; z < h; z++) g.grid[g.idx(x, y, z)] = CELL.TERRAIN;
    }
    const sc = g.placementScorer();
    assert.equal(sc.L, g.lowestLayer());
    for (const shape of SHAPE_NAMES) for (let r = 0; r < 4; r++) {
      const { w, d } = footprint(rotatedCells(shape, r));
      for (let px = 0; px <= g.W - w; px++) for (let py = 0; py <= g.D - d; py++) {
        const pc = g.makePiece(shape, r, px, py, 20);
        assert.equal(sc.score(pc.cells, px, py, pc.landZ), g.placementScore(pc, sc.L), `${trial} ${shape}${r} (${px},${py})`);
      }
    }
  }
});

test('하늘 계단: 사슬은 한 틱에 SKY_SPAWN_PER_TICK(1) 개씩, 같은 시드면 같은 자리', () => {
  assert.equal(C.SKY_SPAWN_PER_TICK, 1);
  const place = (seed) => {
    const { g } = setup({ seed, n: 4 });
    const counts = [];
    while (g.time < C.FIRST_SPAWN_DELAY_MS + TICK * (C.SKY_COUNT + 2)) {
      g.tick(TICK);
      counts.push(skies(g).length);
    }
    return { counts: counts.filter((n, i) => i === 0 || n !== counts[i - 1]), at: skies(g).map((pc) => [pc.shape, pc.rot, pc.px, pc.py, pc.pz]) };
  };
  const a = place(9);
  assert.deepEqual(a.counts, [0, 1, 2, 3, 4, 5, 6, 7], '틱마다 하나씩');
  assert.deepEqual(place(9).at, a.at, '같은 시드 → 같은 자리');
});

test('판 시작 랙: 4인 봇 판 첫 5초 — 한 틱에 자리 고르기 많아야 1번씩, 느린 placementScore 는 안 씀 (하늘 계단 켬·끔, 평지·피라미드)', () => {
  // 벽시계 시간 대신 계산량으로 (기계가 바쁘면 시간은 흔들림). 예전 랙 = 한 틱에 하늘 블록 7개 + 후보마다 느린 placementScore
  const P = Game.prototype;
  const orig = { sky: P.chooseSkyPlacement, auto: P.chooseAutoPlacement, slow: P.placementScore, scorer: P.placementScorer };
  let calls = { sky: 0, auto: 0, slow: 0, scored: 0 };
  P.chooseSkyPlacement = function (...a) {
    calls.sky++;
    return orig.sky.apply(this, a);
  };
  P.chooseAutoPlacement = function (...a) {
    calls.auto++;
    return orig.auto.apply(this, a);
  };
  P.placementScore = function (...a) {
    calls.slow++;
    return orig.slow.apply(this, a);
  };
  P.placementScorer = function () {
    const sc = orig.scorer.call(this);
    const score = sc.score;
    return { ...sc, score: (...b) => (calls.scored++, score(...b)) };
  };
  try {
    for (const sky of [true, false]) {
      for (const map of ['flat', 'pyramid']) {
        const g = new Game(() => {}, { characters: true, skyStairs: sky });
        g.rng = seeded(3);
        const h = g.addPlayer(1);
        g.setSpectator(h.id, true);
        for (let k = 0; k < 4; k++) g.addBot();
        g.setMap(map);
        g.startRound();
        const maxScored = SHAPE_NAMES.length * 4 * g.W * g.D * 2; // 자리 고르기 한 번의 후보 수 상한 (높이차 두 번까지)
        let placed = 0;
        for (let i = 0; i < 150 && g.phase === 'playing'; i++) {
          calls = { sky: 0, auto: 0, slow: 0, scored: 0 };
          g.tick(TICK);
          const tag = `${sky ? '켬' : '끔'} ${map} 틱 ${i}`;
          assert.ok(calls.sky <= 1, `${tag}: 하늘 자리 고르기 ${calls.sky}번`);
          assert.ok(calls.auto <= 1, `${tag}: 자동 블록 자리 고르기 ${calls.auto}번`);
          assert.equal(calls.slow, 0, `${tag}: 느린 placementScore`);
          assert.ok(calls.scored <= maxScored, `${tag}: 후보 ${calls.scored}개`);
          placed += sky ? calls.sky : calls.auto;
        }
        assert.ok(placed >= (sky ? C.SKY_COUNT : 1), `${sky ? '켬' : '끔'} ${map}: 블록이 놓임 (${placed})`);
      }
    }
  } finally {
    Object.assign(P, { chooseSkyPlacement: orig.sky, chooseAutoPlacement: orig.auto, placementScore: orig.slow, placementScorer: orig.scorer });
  }
});

test('판 시작 랙: 서버 시작 때 블록 자리 고르기 데우기 (warmUpPlacement) 가 오류 없이 끝남', () => {
  warmUpPlacement(1);
});
