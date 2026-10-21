// 서버 규칙 단위 테스트: node --test test/
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;

function setup({ log = () => {} } = {}) {
  const lines = [];
  const g = new Game((s) => {
    lines.push(s);
    log(s);
  });
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  g.piece = null; // 자동 스폰은 테스트가 직접 제어
  g.nextSpawnAt = Infinity;
  return { g, lines, p1: g.players.get(1), p2: g.players.get(2) };
}

function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

function fallingPiece(g, shape, rot, px, py, pz = C.PIECE_SPAWN_Z, stepMs = C.AUTO_FALL_STEP_MS) {
  const piece = g.makePiece(shape, rot, px, py, pz);
  Object.assign(piece, { phase: 'falling', controller: null, stepMs, nextStepAt: g.time + stepMs, controlEndsAt: 0 });
  g.piece = piece;
  g.refreshPieceCells();
  return piece;
}

test('플레이어 접속 제한: MAX_PLAYERS 초과는 거부, MIN_PLAYERS 부터 시작 가능', () => {
  const g = new Game();
  g.addPlayer(1);
  assert.equal(g.canStart(), C.MIN_PLAYERS <= 1);
  for (let i = 1; i < C.MAX_PLAYERS; i++) {
    assert.ok(g.addPlayer(i + 1));
    if (g.players.size >= C.MIN_PLAYERS) assert.equal(g.canStart(), true);
  }
  assert.equal(g.addPlayer(99), null);
});

test('자동 낙하: O 블록이 바닥에 착지해 격자에 기록된다', () => {
  const { g, p1 } = setup();
  p1.x = 3.5;
  p1.y = 3.5;
  fallingPiece(g, 'O', 0, 0, 0);
  run(g, C.AUTO_FALL_STEP_MS * (C.PIECE_SPAWN_Z + 1));
  assert.equal(g.piece, null);
  assert.equal(g.gridAt(0, 0, 0), 1);
  assert.equal(g.gridAt(1, 1, 0), 1);
  assert.equal(g.gridAt(0, 0, 1), 0);
});

test('그림자: 착지 SHADOW_LEAD_MS 전부터만 보인다', () => {
  const { g } = setup();
  fallingPiece(g, 'O', 0, 0, 0);
  g.tick(TICK);
  assert.equal(g.snapshot().pieces[0].shadowVisible, false);
  // 12칸 × 500ms = 6초 낙하. 3.5초 후엔 보여야 한다
  run(g, 3500);
  assert.equal(g.snapshot().pieces[0].shadowVisible, true);
});

test('압사: 블록 아래 서 있던 플레이어는 crush 로 죽는다', () => {
  const { g, p1, p2 } = setup();
  p1.x = 0.5;
  p1.y = 0.5;
  p2.x = 4.5;
  p2.y = 4.5;
  fallingPiece(g, 'O', 0, 0, 0); // (0..1, 0..1) 위로 떨어짐
  run(g, C.AUTO_FALL_STEP_MS * (C.PIECE_SPAWN_Z + 1));
  assert.equal(p1.alive, false);
  assert.equal(p1.deathCause, 'crush');
  assert.equal(p2.alive, true);
  assert.equal(g.phase, 'over');
  assert.equal(g.winnerId, 2);
  assert.equal(g.totals.crush, 1);
});

test('낙사: 필드 밖으로 걸어 나가면 fall 로 죽는다', () => {
  const { g, p1 } = setup();
  p1.x = 0.5;
  p1.y = 0.5;
  p1.yaw = Math.PI; // -x 방향
  g.handleInput(1, { fwd: 1, strafe: 0, jump: false, yaw: Math.PI, pitch: 0 });
  run(g, 3000);
  assert.equal(p1.alive, false);
  assert.equal(p1.deathCause, 'fall');
  assert.equal(g.totals.fall, 1);
});

test('블록 위에 설 수 있다 (AABB 충돌)', () => {
  const { g, p1 } = setup();
  g.grid[g.idx(2, 2, 0)] = 1;
  g.grid[g.idx(2, 2, 1)] = 1;
  p1.x = 2.5;
  p1.y = 2.5;
  p1.z = 5;
  run(g, 2000);
  assert.ok(Math.abs(p1.z - 2) < 1e-6, `z=${p1.z}`);
  assert.equal(p1.grounded, true);
});

test('층 클리어: 꽉 찬 층이 사라지고 위 블록·플레이어가 한 칸 내려앉는다', () => {
  const { g, p1, p2 } = setup();
  p2.x = 2.5;
  p2.y = 2.5;
  p2.z = 1;
  // z=0 층을 구석 O 자리 (W-2..W-1, D-2..D-1) 빼고 채운다
  const gx = C.GRID_W - 2;
  const gy = C.GRID_D - 2;
  for (let y = 0; y < C.GRID_D; y++) for (let x = 0; x < C.GRID_W; x++) if (!(x >= gx && y >= gy)) g.grid[g.idx(x, y, 0)] = 1;
  g.grid[g.idx(0, 0, 1)] = 1; // 위에 블록 하나
  p1.x = 0.5;
  p1.y = 0.5;
  p1.z = 2; // 그 블록 위에 서 있음
  fallingPiece(g, 'O', 0, gx, gy, 3, 50);
  run(g, 50 * 5);
  assert.equal(g.piece, null);
  assert.equal(g.gridAt(0, 0, 0), 1, '위에 있던 블록이 z=0 으로 내려와야 함');
  assert.equal(g.gridAt(0, 0, 1), 0);
  assert.equal(g.gridAt(gx, gy, 0), 0, '착지한 O 는 층과 함께 사라져야 함');
  assert.ok(Math.abs(p1.z - 1) < 1e-6, `플레이어 z=${p1.z}, 1 이어야 함`);
});

test('조종권: 아이템 획득 → 다음 블록 조종, 조종 중 대시·공격 무시, 하드드롭', () => {
  const { g, p1, p2 } = setup();
  p1.hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  assert.ok(g.piece && g.piece.phase === 'control' && g.piece.controller === 1);
  assert.equal(p1.hasControl, false);
  assert.ok(g.isControlling(p1));
  // 대시 무시
  const kbBefore = p1.kbx;
  g.handleAction(1, { name: 'dash' });
  assert.equal(p1.kbx, kbBefore);
  assert.equal(p1.dashReadyAt, 0);
  // 밀치기 무시: p2 가 바로 앞에 있어도 넉백 없음
  p1.x = 1.5;
  p1.y = 1.5;
  p1.yaw = 0;
  p2.x = 2.5;
  p2.y = 1.5;
  g.handleAction(1, { name: 'push' });
  assert.equal(p2.stunUntil, 0);
  // 블록 이동·회전·드롭
  const px0 = g.piece.px;
  g.handleAction(1, { name: 'pieceMove', dx: 1, dy: 0 });
  assert.equal(g.piece.px, px0 + 1);
  g.handleAction(1, { name: 'rotate', dir: 1 });
  g.handleAction(1, { name: 'drop' });
  assert.equal(g.piece.phase, 'falling');
  assert.equal(g.isControlling(p1), false);
  run(g, C.HARD_DROP_STEP_MS * (C.GRID_H + 3));
  // 조종 블록은 착지해서 사라짐 (그 사이 자동 블록은 따로 떨어질 수 있다)
  assert.ok(!g.pieces.some((pc) => pc.controller === 1), '조종 블록이 착지해야 함');
  assert.ok(g.grid.reduce((a, b) => a + b, 0) >= 4);
});

test('조종권: 8초 안에 안 떨구면 자동 낙하', () => {
  const { g, p1 } = setup();
  p1.hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  assert.equal(g.piece.phase, 'control');
  run(g, C.CONTROL_TIME_MS + TICK * 2);
  assert.ok(!g.piece || g.piece.phase === 'falling');
});

test('넉백 + 경직: 경직 중 두 번째 넉백은 안 들어간다', () => {
  const { g, p1, p2 } = setup();
  p1.x = 2.5;
  p1.y = 2.5;
  p1.yaw = 0;
  p2.x = 3.5;
  p2.y = 2.5;
  g.handleAction(1, { name: 'push' });
  assert.ok(p2.kbx > 0, '첫 밀치기는 넉백');
  assert.ok(p2.stunUntil > g.time);
  const stun1 = p2.stunUntil;
  p2.kbx = 0;
  p1.pushReadyAt = 0; // 쿨다운 무시하고 바로 다시
  g.handleAction(1, { name: 'push' });
  assert.equal(p2.kbx, 0, '경직 중엔 넉백 없음');
  assert.equal(p2.stunUntil, stun1);
  // 경직 중엔 이동 입력도 무시
  g.handleInput(2, { fwd: 1, strafe: 0, jump: false, yaw: 0, pitch: 0 });
  const x0 = p2.x;
  g.tick(TICK);
  assert.ok(p2.x - x0 < C.MOVE_SPEED * (TICK / 1000) * 0.5 + p2.kbx * (TICK / 1000) + 1e-9);
  // 경직 끝난 뒤엔 다시 넉백 가능
  run(g, C.STUN_MS + 100);
  p2.x = 3.5;
  p2.y = 2.5;
  p2.z = 0;
  g.handleAction(1, { name: 'push' });
  assert.ok(p2.kbx > 0, '경직 후엔 다시 넉백');
});

test('넉백 아이템 + 투사체: 맞으면 넉백, 탄 소모', () => {
  const { g, p1, p2 } = setup();
  p1.x = 1.5;
  p1.y = 2.5;
  p1.yaw = 0;
  p1.pitch = 0;
  p2.x = 4.5;
  p2.y = 2.5;
  p1.hand = 2; // 핫바 2번 칸 (투사체·설치 블록)
  g.handleAction(1, { name: 'fire' });
  assert.equal(g.projectiles.length, 0, '탄 없으면 발사 안 됨');
  p1.ammo = 1;
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.ammo, 0);
  assert.equal(g.projectiles.length, 1);
  run(g, 500);
  assert.equal(g.projectiles.length, 0);
  assert.ok(p2.kbx > 0 && p2.stunUntil > 0, '투사체 맞고 넉백');
  assert.equal(p2.damage, C.DAMAGE_GAIN.projectile, '투사체 피해 %');
});

test('아이템 스폰·획득', () => {
  const { g, p1 } = setup();
  p1.x = C.GRID_W - 0.5; // 시작 위치가 아이템 칸과 겹치지 않게 구석으로 비켜둔다
  p1.y = 0.5;
  g.controlItemNextAt = g.time;
  g.powerItemNextAt = g.time;
  const seq = [0.3, 0.3, 0.5, 0.5]; // 조종권 (0.3W, 0.3D), 넉백 (0.5W, 0.5D)
  g.rng = () => (seq.length ? seq.shift() : 0.5);
  const savedPool = C.ITEM_POOL;
  C.ITEM_POOL = ['knockback'];
  g.tick(TICK);
  C.ITEM_POOL = savedPool;
  assert.equal(g.items.length, 2);
  const ctl = g.items.find((it) => it.type === 'control');
  const kb = g.items.find((it) => it.type === 'knockback');
  p1.x = ctl.x + 0.5;
  p1.y = ctl.y + 0.5;
  g.tick(TICK);
  // CONTROL_TAKEOVER: 블록이 없으면 먹는 즉시 새 블록 조종 시작
  assert.ok(g.isControlling(p1), '조종권을 먹으면 바로 조종 시작');
  p1.x = kb.x + 0.5;
  p1.y = kb.y + 0.5;
  run(g, 100);
  assert.equal(p1.ammo, C.KNOCKBACK_AMMO);
  assert.equal(g.items.length, 0);
});

test('디버그 로그: 판 종료 시 압사/낙사 횟수와 누적이 찍힌다', () => {
  const { g, p1, p2, lines } = setup();
  p1.x = 0.5;
  p1.y = 0.5;
  p2.x = 4.5;
  p2.y = 4.5;
  fallingPiece(g, 'O', 0, 0, 0, 3, 50);
  run(g, 50 * 5);
  assert.equal(g.phase, 'over');
  assert.ok(lines.some((l) => l.includes('이번 판: 압사 1 / 낙사 0')), lines.join('\n'));
  assert.ok(lines.some((l) => l.includes('누적 1판: 압사 1 (판당 1.00)')), lines.join('\n'));
  // 재시작
  assert.ok(g.startRound());
  assert.equal(g.phase, 'playing');
  assert.ok(p1.alive && p2.alive);
  assert.equal(g.grid.reduce((a, b) => a + b, 0), 0);
});

test('밀치기 거리: 피해 0% 면 약 1.5칸 × DAMAGE_KB_BASE (PUSH_KB_SPEED 4.2)', () => {
  const { g, p1, p2 } = setup();
  p1.x = 1.5;
  p1.y = 3;
  p1.yaw = 0;
  p2.x = 2.5;
  p2.y = 3;
  g.handleAction(1, { name: 'push' });
  run(g, 2000);
  const d = p2.x - 2.5;
  const k = C.DAMAGE_KB_BASE;
  assert.ok(d > 1.35 * k && d < 1.6 * k, `밀린 거리 ${d.toFixed(2)}`);
  assert.equal(p2.alive, true);
});

test('시작 위치: 가장자리에서 1.5칸 이상 안쪽이라 밀치기 한 번으로 안 떨어진다', () => {
  const { g, p1, p2 } = setup();
  const sp = C.SPAWN_POINTS;
  assert.deepEqual([p1.x, p1.y, p2.x, p2.y], [sp[0].x, sp[0].y, sp[1].x, sp[1].y]);
  assert.ok(sp[0].x >= 1.5 && sp[0].y >= 1.5);
  // p2 를 가장자리에서 1.5칸 (x=1.5) 에 두고 바깥쪽(-x)으로 밀어도 산다
  p2.x = 1.5;
  p2.y = 1.5;
  p1.x = 2.5;
  p1.y = 1.5;
  p1.yaw = Math.PI;
  g.handleAction(1, { name: 'push' });
  run(g, 2000);
  assert.equal(p2.alive, true, `p2.x=${p2.x.toFixed(2)}`);
});

test('이벤트: 밀치기 명중/경직 무효, 아이템 획득, 조종 시작이 이벤트로 나온다', () => {
  const { g, p1, p2 } = setup();
  p1.x = 2.5;
  p1.y = 2.5;
  p1.yaw = 0;
  p2.x = 3.5;
  p2.y = 2.5;
  g.drainEvents();
  g.handleAction(1, { name: 'push' });
  p1.pushReadyAt = 0;
  g.handleAction(1, { name: 'push' });
  const ev = g.drainEvents().filter((e) => e.type === 'hit');
  assert.deepEqual(
    ev.map((e) => [e.type, e.kind, e.by, e.target, e.ok]),
    [
      ['hit', 'push', 1, 2, true],
      ['hit', 'push', 1, 2, false],
    ],
  );
  assert.equal(g.drainEvents().length, 0, 'drain 후엔 비어 있어야 함');
  p1.hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  assert.ok(g.drainEvents().some((e) => e.type === 'controlStart' && e.who === 1));
});

test('nextSpawnIn: 조종 블록 없음 → 다음 생성까지, 남의 조종 블록 낙하 중 → 그 착지까지, 조종 중 → null', () => {
  const { g, p1 } = setup();
  g.nextSpawnAt = g.time + 1500;
  assert.equal(g.snapshot().nextSpawnIn, 1500);
  fallingPiece(g, 'O', 0, 4, 4, 2, 100); // 자동 블록은 영향 없음
  assert.equal(g.snapshot().nextSpawnIn, 1500);
  g.piece.controller = 2; // 남이 조종해서 떨어뜨린 블록: 2칸 → 200ms 후 착지
  const n = g.snapshot().nextSpawnIn;
  assert.ok(Math.abs(n - 200) < 1e-6, `nextSpawnIn=${n}`);
  g.piece = null;
  p1.hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  assert.equal(g.snapshot().nextSpawnIn, null);
});

test('점프: 1칸 블록 위로는 올라가고 2칸 벽은 못 넘는다', () => {
  const { g, p1 } = setup();
  // x>=3 에 1칸 턱, x=5 에는 턱보다 2칸 높은 벽
  for (let y = 0; y < C.GRID_D; y++) {
    for (let x = 3; x < C.GRID_W; x++) g.grid[g.idx(x, y, 0)] = 1;
    g.grid[g.idx(5, y, 1)] = 1;
    g.grid[g.idx(5, y, 2)] = 1;
  }
  p1.x = 2.5;
  p1.y = 2.5;
  let landedOnStep = false;
  let maxX = 0;
  for (let i = 0; i < 120; i++) {
    g.handleInput(1, { fwd: 1, strafe: 0, jump: true, yaw: 0, pitch: 0 });
    g.tick(TICK);
    if (p1.grounded && Math.abs(p1.z - 1) < 1e-6 && p1.x > 3) landedOnStep = true;
    maxX = Math.max(maxX, p1.x);
  }
  assert.ok(landedOnStep, '1칸 턱 위에 착지해야 함');
  assert.ok(maxX <= 5 - C.PLAYER_HALF + 1e-6 && p1.alive, `2칸 벽에 막혀야 함: maxX=${maxX.toFixed(2)}`);
});

test('조종권 넘겨받기: 자동 블록이 떨어지는 중에 먹으면 그 블록을 하늘로 올려 바로 조종', () => {
  const { g, p1 } = setup();
  const piece = fallingPiece(g, 'T', 0, 0, 0, 5);
  g.items.push({ type: 'control', x: 4, y: 4, z: 0 });
  p1.x = 4.5;
  p1.y = 4.5;
  g.tick(TICK);
  assert.equal(g.piece, piece, '같은 블록이어야 함');
  assert.equal(piece.phase, 'control');
  assert.equal(piece.controller, 1);
  assert.equal(piece.pz, C.CONTROL_HOVER_Z);
  assert.equal(p1.hasControl, false);
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'controlStart' && e.who === 1));
});

test('조종권 넘겨받기: 남이 조종해서 떨어지는 블록은 못 뺏고, 착지 후 다음 블록을 조종', () => {
  const { g, p1, p2 } = setup();
  const piece = fallingPiece(g, 'O', 0, 0, 0, 3, 50);
  piece.controller = 2;
  g.nextSpawnAt = Infinity;
  g.items.push({ type: 'control', x: 4, y: 4, z: 0 });
  p1.x = 4.5;
  p1.y = 4.5;
  p2.x = 2.5;
  p2.y = 4.5;
  g.tick(TICK);
  assert.equal(piece.controller, 2);
  assert.equal(p1.hasControl, true);
  run(g, 400 + C.AUTO_SPAWN_DELAY_MS); // 착지 후 다음 블록 대기시간까지
  assert.ok(g.isControlling(p1), '착지 후 다음 블록은 p1 조종');
});

test('조종권 넘겨받기 끄기 (CONTROL_TAKEOVER=false): 먹어도 떨어지던 블록은 그대로', () => {
  const { g, p1 } = setup();
  const saved = C.CONTROL_TAKEOVER;
  C.CONTROL_TAKEOVER = false;
  try {
    const piece = fallingPiece(g, 'T', 0, 0, 0, 5);
    g.items.push({ type: 'control', x: 4, y: 4, z: 0 });
    p1.x = 4.5;
    p1.y = 4.5;
    g.tick(TICK);
    assert.equal(piece.phase, 'falling');
    assert.equal(p1.hasControl, true);
  } finally {
    C.CONTROL_TAKEOVER = saved;
  }
});

test('대시 거리: 평지에서 약 1칸 (DASH_SPEED 6)', () => {
  const { g, p1 } = setup();
  p1.x = 1.5;
  p1.y = 3;
  p1.yaw = 0;
  g.handleAction(1, { name: 'dash' });
  run(g, 2000);
  const d = p1.x - 1.5;
  assert.ok(d > 0.85 && d < 1.15, `대시 거리 ${d.toFixed(2)}`);
});

test('로그: 8초 초과 낙하는 하드드롭과 구분되고, 누적 압사 비율과 합격선이 찍힌다', () => {
  const { g, p1, p2, lines } = setup();
  p1.hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  run(g, C.CONTROL_TIME_MS + 200);
  assert.ok(lines.some((l) => l.includes('자동 낙하 (8초 초과, 조종자 P1)')), lines.join('\n'));
  assert.ok(!lines.some((l) => l.includes('하드드롭 by')), '자동 낙하가 하드드롭으로 찍히면 안 됨');
  g.kill(p2, 'crush');
  g.checkRoundEnd();
  assert.ok(lines.some((l) => l.includes('누적 사망 중 압사 비율: 100% (합격선 50% → 합격선 이상)')), lines.join('\n'));
  assert.ok(p1.alive);
});

function setupN(n, log = () => {}) {
  const lines = [];
  const g = new Game((x) => {
    lines.push(x);
    log(x);
  });
  g.rng = () => 0.5;
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  g.startRound();
  g.piece = null;
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return { g, lines, ps: [...g.players.values()] };
}

test('4인: 시작 위치가 모두 다르고 가장자리에서 1.5칸 이상 안쪽', () => {
  const saved = C.MAX_PLAYERS;
  C.MAX_PLAYERS = 8;
  try {
    const { ps } = setupN(8);
    const keys = new Set(ps.map((p) => `${p.x},${p.y}`));
    assert.equal(keys.size, 8);
    for (const p of ps) {
      assert.ok(p.x >= 1.5 && p.x <= C.GRID_W - 1.5 && p.y >= 1.5 && p.y <= C.GRID_D - 1.5, `${p.name} (${p.x},${p.y})`);
      // 중앙을 바라봄
      const toCenter = Math.atan2(C.GRID_D / 2 - p.y, C.GRID_W / 2 - p.x);
      const diff = Math.atan2(Math.sin(p.yaw - toCenter), Math.cos(p.yaw - toCenter));
      assert.ok(Math.abs(diff) < 1e-9, `${p.name} yaw`);
    }
  } finally {
    C.MAX_PLAYERS = saved;
  }
});

test('3인: 한 명 죽어도 판이 계속되고, 마지막 생존자가 이긴다', () => {
  const { g, ps } = setupN(3);
  g.kill(ps[0], 'fall');
  g.checkRoundEnd();
  assert.equal(g.phase, 'playing');
  g.kill(ps[2], 'crush');
  g.checkRoundEnd();
  assert.equal(g.phase, 'over');
  assert.equal(g.winnerId, ps[1].id);
  assert.deepEqual(g.totalsByCount['3인'], { rounds: 1, crush: 1, fall: 1, lava: 0 });
});

test('3인: 진행 중 한 명이 나가도 나머지 둘로 계속', () => {
  const { g, ps } = setupN(3);
  g.removePlayer(ps[0].id);
  assert.equal(g.phase, 'playing');
  g.kill(ps[1], 'fall');
  g.checkRoundEnd();
  assert.equal(g.winnerId, ps[2].id);
});

test('인원이 섞이면 로그에 인원수별 압사 비율이 따로 찍힌다', () => {
  const { g, ps, lines } = setupN(3);
  g.kill(ps[0], 'crush');
  g.kill(ps[1], 'fall');
  g.checkRoundEnd();
  for (const p of ps) g.removePlayer(p.id); // 3명 다 나가고 2명이 새로 들어옴
  g.addPlayer(10);
  g.addPlayer(11);
  g.startRound();
  const [a] = [...g.players.values()].filter((p) => p.alive);
  g.kill(a, 'crush');
  g.checkRoundEnd();
  assert.ok(lines.some((l) => l.includes('3인 판 1판: 압사 1 / 낙사 1 / 용암 0 → 50%')), lines.join('\n'));
  assert.ok(lines.some((l) => l.includes('2인 판 1판: 압사 1 / 낙사 0 / 용암 0 → 100%')), lines.join('\n'));
});

test('층 클리어 유도: 유도를 세게 하면 한 칸 모양 빈자리를 거의 항상 채운다 (기본값은 약하게)', () => {
  const g = new Game();
  g.rng = Math.random;
  const saved = C.CLEAR_BIAS;
  C.CLEAR_BIAS = 2;
  try {
    // z=0 층을 구석 2x2 만 빼고 채운다 → O 블록이 들어가면 층 클리어
    const gx = C.GRID_W - 2;
    const gy = C.GRID_D - 2;
    for (let y = 0; y < C.GRID_D; y++) for (let x = 0; x < C.GRID_W; x++) if (!(x >= gx && y >= gy)) g.grid[g.idx(x, y, 0)] = 1;
    let hit = 0;
    for (let i = 0; i < 200; i++) {
      const p = g.chooseAutoPlacement('I');
      if (p.shape === 'O' && p.px === gx && p.py === gy && p.landZ === 0) hit++;
    }
    assert.ok(hit >= 180, `200번 중 ${hit}번`);
  } finally {
    C.CLEAR_BIAS = saved;
  }
});

test('층 클리어 유도 끄기 (CLEAR_BIAS=0): 주어진 무작위 모양 그대로', () => {
  const g = new Game();
  const saved = C.CLEAR_BIAS;
  C.CLEAR_BIAS = 0;
  try {
    for (let i = 0; i < 50; i++) assert.equal(g.chooseAutoPlacement('T').shape, 'T');
  } finally {
    C.CLEAR_BIAS = saved;
  }
});

test('층 클리어 유도: 유도를 세게 하면 구멍을 만드는 자리는 거의 안 고른다', () => {
  const g = new Game();
  g.rng = Math.random;
  const saved = C.CLEAR_BIAS;
  C.CLEAR_BIAS = 2;
  // 바닥에 계단: x<3 은 1칸 높이. 걸치면 구멍이 생긴다
  for (let y = 0; y < C.GRID_D; y++) for (let x = 0; x < 3; x++) g.grid[g.idx(x, y, 0)] = 1;
  let holes = 0;
  for (let i = 0; i < 200; i++) {
    const p = g.chooseAutoPlacement('I');
    for (const [dx, dy] of p.cells) if (g.columnTop(p.px + dx, p.py + dy) < p.landZ) { holes++; break; }
  }
  C.CLEAR_BIAS = saved;
  assert.ok(holes <= 10, `200번 중 구멍 ${holes}번`);
});

// ---------- 봇 ----------
function setupBot() {
  const lines = [];
  const g = new Game((x) => lines.push(x));
  g.rng = Math.random;
  const human = g.addPlayer(1);
  const bot = g.addBot();
  return { g, lines, human, bot };
}

test('봇: 호스트는 사람, 사람 1 + 봇 1 이면 시작 가능, 판 중엔 추가·제거 불가, 마지막 봇부터 빠짐', () => {
  const { g, human, bot } = setupBot();
  assert.equal(g.hostId, human.id);
  assert.equal(bot.isBot, true);
  assert.equal(bot.name, 'P2(봇)');
  assert.equal(g.canStart(), true);
  const bot2 = g.addBot();
  g.startRound();
  assert.equal(g.addBot(), null);
  assert.equal(g.removeBot(), false);
  g.phase = 'over';
  assert.equal(g.removeBot(), true);
  assert.ok(!g.players.has(bot2.id) && g.players.has(bot.id), '나중에 넣은 봇이 먼저 빠짐');
  g.removePlayer(human.id);
  assert.equal(g.hostId, null, '봇은 호스트가 안 됨');
});

test('봇: 떨어지는 블록 그림자를 보고 피한다', () => {
  const { g, human, bot } = setupBot();
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  human.x = 5.5;
  human.y = 0.5;
  bot.x = 2.5;
  bot.y = 3.5;
  fallingPiece(g, 'O', 0, 2, 3, 8, 350); // 2.8초 뒤 착지, 바로 그림자가 보임
  run(g, 3500);
  assert.equal(bot.alive, true, `봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)})`);
});

test('봇: 조종권으로 가만히 선 상대 위에 블록을 떨어뜨려 압사시킨다 (10번 중 8번 이상)', () => {
  let crushed = 0;
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    human.x = 4.5;
    human.y = 3.5;
    bot.x = 1.5;
    bot.y = 1.5;
    bot.hasControl = true;
    g.startControlNow(bot);
    assert.ok(g.isControlling(bot));
    run(g, C.CONTROL_TIME_MS + 2000);
    if (!human.alive && human.deathCause === 'crush' && bot.alive) crushed++;
  }
  // 100번 재현에서 98번. 나머지는 시간 안에 못 맞추거나 떨어뜨린 뒤 밀어서 낙사
  assert.ok(crushed >= 8, `10번 중 ${crushed}번`);
});

test('봇: 가까이 있는 상대를 민다', () => {
  const { g, human, bot } = setupBot();
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  human.x = 2.5;
  human.y = 3;
  bot.x = 3.5;
  bot.y = 3;
  run(g, 3000);
  assert.ok(g.drainEvents().some((e) => e.type === 'hit' && e.kind === 'push' && e.by === bot.id && e.ok));
});

test('봇끼리 20판: 예외 없이 판이 끝나고, 봇 판은 로그에 따로 센다', () => {
  const lines = [];
  const g = new Game((x) => lines.push(x));
  g.rng = Math.random;
  g.addBot();
  g.addBot();
  for (let r = 0; r < 20; r++) {
    g.startRound();
    const t0 = g.time;
    while (g.phase === 'playing' && g.time - t0 < 180000) g.tick(TICK);
    assert.equal(g.phase, 'over', `${r + 1}판이 3분 안에 안 끝남`);
  }
  assert.ok(lines.some((l) => l.includes('2인(봇 2) 판 20판')), lines.slice(-3).join('\n'));
});

test('봇: 거리가 같은 상대가 여럿이면 늘 사람만 노리지 않는다 (사람 1 + 봇 3)', () => {
  let p3HitsHumanFirst = 0;
  let p3Pushed = 0;
  for (let r = 0; r < 40; r++) {
    const g = new Game();
    g.rng = Math.random;
    g.addPlayer(1);
    g.addBot();
    const p3 = g.addBot();
    g.addBot();
    g.startRound();
    const t0 = g.time;
    let first = null;
    while (g.phase === 'playing' && g.time - t0 < 3000 && first === null) {
      g.tick(TICK);
      for (const e of g.drainEvents()) if (first === null && e.type === 'hit' && e.kind === 'push' && e.by === p3.id) first = e.target;
    }
    if (first !== null) {
      p3Pushed++;
      if (first === 1) p3HitsHumanFirst++;
    }
  }
  // 수정 전에는 200판 중 200판이 사람. 지금은 대략 절반
  assert.ok(p3Pushed >= 20 && p3HitsHumanFirst / p3Pushed < 0.85, `P3 첫 밀치기 ${p3Pushed}번 중 사람 ${p3HitsHumanFirst}번`);
});

// ---------- 2단계 A: 여러 블록·가속·용암 ----------
test('블록 가속: 처음엔 자동 블록 1개, 시간이 지나면 동시에 여러 개 (최대 CONCURRENT_MAX)', () => {
  const { g, p1, p2 } = setup();
  p1.x = 0.5; // 블록에 안 깔리게 구석에 둔다 (판정은 블록 수만 본다)
  p2.x = 0.5;
  g.nextSpawnAt = g.time;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  let max0 = 0;
  for (let t = 0; t < 15000; t += TICK) {
    g.tick(TICK);
    if (g.phase !== 'playing') break;
    max0 = Math.max(max0, g.pieces.length);
  }
  assert.equal(max0, 1, '첫 20초는 1개');
  g.roundStartTime = g.time - C.CONCURRENT_RAMP_MS * 10; // 판 후반으로
  assert.equal(g.targetConcurrent(), C.CONCURRENT_MAX);
  assert.equal(g.autoFallStepMs(), C.AUTO_FALL_STEP_MIN_MS);
  let maxLate = 0;
  for (let t = 0; t < 8000; t += TICK) {
    g.tick(TICK);
    maxLate = Math.max(maxLate, g.pieces.length);
  }
  assert.ok(maxLate >= 3, `후반 동시 블록 최대 ${maxLate}`);
});

test('자동 블록은 다른 블록과 같은 기둥에 안 떨어진다', () => {
  const { g } = setup();
  g.rng = Math.random;
  for (let i = 0; i < 30; i++) {
    g.pieces = [];
    g.refreshPieceCells();
    for (let k = 0; k < 4; k++) g.spawnAuto();
    const cols = new Set();
    for (const pc of g.pieces) {
      for (const [dx, dy] of pc.cells) {
        const key = (pc.px + dx) * 100 + (pc.py + dy);
        assert.ok(!cols.has(key), '기둥 겹침');
        cols.add(key);
      }
    }
  }
});

test('하드드롭한 블록은 아래에서 떨어지는 블록을 뚫지 않고 그 위에 쌓인다', () => {
  const { g, p1, p2 } = setup();
  p1.x = C.GRID_W - 0.5;
  p2.x = C.GRID_W - 0.5;
  p2.y = C.GRID_D - 0.5;
  const low = g.makePiece('O', 0, 0, 0, 6);
  g.addPiece(low, { phase: 'falling', controller: null, stepMs: 500, nextStepAt: g.time + 500, controlEndsAt: 0 });
  const high = g.makePiece('O', 0, 0, 0, 12);
  g.addPiece(high, { phase: 'falling', controller: null, stepMs: C.HARD_DROP_STEP_MS, nextStepAt: g.time + C.HARD_DROP_STEP_MS, controlEndsAt: 0 });
  for (let t = 0; t < 6000; t += TICK) {
    g.tick(TICK);
    // 공중에서 두 블록의 셀이 겹치면 안 된다
    const a = new Set(g.pieces.flatMap((pc) => g.pieceWorldCells(pc).map((c) => c.join())));
    assert.equal(a.size, g.pieces.length * 4);
  }
  assert.equal(g.pieces.length, 0);
  assert.equal(g.gridAt(0, 0, 0), 1);
  assert.equal(g.gridAt(0, 0, 1), 1, '위 블록은 아래 블록 위에 쌓임');
});

function fillAvgHeight(g, h) {
  // (0,0) 기둥만 통째로 비운 1칸 구덩이
  for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) for (let z = 0; z < h; z++) if (!(x === 0 && y === 0)) g.grid[g.idx(x, y, z)] = 1;
}

test('용암: 평균 높이가 기준에 닿으면 올라오고, 닿은 사람은 용암사', () => {
  const { g, p1, p2, lines } = setup();
  assert.equal(g.lava.active, false);
  // 평균 높이를 기준 위로 (구덩이 하나만 남기고 채움)
  fillAvgHeight(g, Math.ceil(C.LAVA_TRIGGER_AVG_HEIGHT) + 1);
  g.gridVersion++;
  p1.x = 5.5;
  p1.y = 5.5;
  p1.z = 20; // 공중에서 떨어져 꼭대기에 선다
  p2.x = 0.5;
  p2.y = 0.5;
  p2.z = 0; // 구덩이 (0,0) 바닥에 갇힌 사람 (점프 1.28칸으로 못 나옴)
  g.tick(TICK);
  assert.equal(g.lava.active, true);
  assert.ok(g.drainEvents().some((e) => e.type === 'lava'));
  run(g, C.LAVA_RISE_MS_PER_CELL * 1.5);
  assert.equal(p2.alive, false);
  assert.equal(p2.deathCause, 'lava');
  assert.equal(p1.alive, true);
  assert.ok(lines.some((l) => l.includes('용암 1')), lines.join('\n'));
});

test('용암: 필드 밖으로 밀려 떨어지다 용암 높이 아래로 가면 낙사, 필드 안은 용암사', () => {
  const { g, p1, p2 } = setup();
  g.lava = { active: true, z: 1, startedAt: g.time };
  p1.x = 5.5;
  p1.y = 5.5;
  p1.z = 0;
  p2.x = -0.8; // 가장자리 밖
  p2.y = 5;
  p2.z = 0.5;
  g.tick(TICK);
  assert.equal(p1.deathCause, 'lava');
  assert.equal(p2.deathCause, 'fall');
});

test('봇: 용암이 오면 막힌 가까운 칸 대신 길이 이어진 높은 칸으로 올라간다 (10번 모두)', () => {
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    // x=6 줄 전체가 3칸 벽. 벽 너머 (7,5) 는 1칸이라 가장 가깝지만 못 감. (1,5) 1칸은 걸어서 감
    for (let y = 0; y < C.GRID_D; y++) for (let z = 0; z < 3; z++) g.grid[g.idx(6, y, z)] = 1;
    g.grid[g.idx(7, 5, 0)] = 1;
    g.grid[g.idx(1, 5, 0)] = 1;
    for (let z = 0; z < 3; z++) g.grid[g.idx(9, 9, z)] = 1; // 사람은 벽 너머 3칸 기둥 위 (못 밀러 감)
    g.gridVersion++;
    human.x = 9.5;
    human.y = 9.5;
    human.z = 3;
    bot.x = 5.5;
    bot.y = 5.5;
    bot.z = 0;
    g.lava = { active: true, z: -0.95, startedAt: g.time };
    let climbed = false;
    for (let t = 0; t < 6000 && !climbed; t += TICK) {
      g.tick(TICK);
      if (bot.grounded && bot.z > 0.99) climbed = true;
    }
    assert.ok(climbed, `${k}번째: 봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)}, ${bot.z.toFixed(2)})`);
  }
});

test('봇: 용암이 켜졌으면 높은 곳에서 바닥의 상대를 쫓아 내려오지 않는다 (10번 모두)', () => {
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    // 가운데 3×3 이 3칸 높이 언덕, 사람은 바닥
    for (let x = 4; x <= 6; x++) for (let y = 4; y <= 6; y++) for (let z = 0; z < 3; z++) g.grid[g.idx(x, y, z)] = 1;
    g.gridVersion++;
    human.x = 1.5;
    human.y = 5.5;
    human.z = 0;
    bot.x = 5.5;
    bot.y = 5.5;
    bot.z = 3;
    g.lava = { active: true, z: -0.5, startedAt: g.time };
    run(g, 4000);
    assert.ok(bot.z > 2.99, `${k}번째: 봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)}, ${bot.z.toFixed(2)})`);
  }
});

test('용암: 층 클리어로 지형이 내려앉으면 용암도 같이 내려간다', () => {
  const { g } = setup();
  g.lava = { active: true, z: 1.5, startedAt: g.time };
  for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) g.grid[g.idx(x, y, 0)] = 1;
  g.clearLayers();
  assert.ok(Math.abs(g.lava.z - 0.5) < 1e-9, `lava.z=${g.lava.z}`);
});

// ---------- 2단계 B: 타격감 ----------
test('히트스톱: 명중하면 맞은 쪽·때린 쪽이 HITSTOP_MS 동안 멈췄다가 날아간다 (거리는 그대로)', () => {
  const { g, p1, p2 } = setup();
  p1.x = 3.5;
  p1.y = 5;
  p1.yaw = 0;
  p2.x = 4.5;
  p2.y = 5;
  g.handleInput(1, { fwd: 1, strafe: 0, jump: false, yaw: 0, pitch: 0 }); // 때린 쪽은 앞으로 걷는 중
  g.handleAction(1, { name: 'push' });
  const ev = g.drainEvents();
  assert.ok(ev.some((e) => e.type === 'swing' && e.who === 1));
  const x1 = p1.x;
  const x2 = p2.x;
  run(g, C.HITSTOP_MS - TICK); // 멈칫 동안
  assert.equal(p1.x, x1, '때린 쪽 멈춤');
  assert.equal(p2.x, x2, '맞은 쪽 멈춤');
  g.handleInput(1, { fwd: 0, strafe: 0, jump: false, yaw: 0, pitch: 0 });
  run(g, 2000);
  const d = p2.x - x2;
  const k = C.DAMAGE_KB_BASE;
  assert.ok(d > 1.35 * k && d < 1.6 * k, `밀린 거리 ${d.toFixed(2)}`);
});

test('블록이 착지하면 land 이벤트(셀 위치)가 나온다', () => {
  const { g, p1, p2 } = setup();
  p1.x = C.GRID_W - 0.5;
  p2.x = C.GRID_W - 0.5;
  fallingPiece(g, 'O', 0, 0, 0, 2, 50);
  g.drainEvents();
  run(g, 300);
  const land = g.drainEvents().find((e) => e.type === 'land');
  assert.ok(land && land.cells.length === 4 && land.cells.every((c) => c[2] === 0));
});

// ---------- 2단계 C: 아이템 ----------
test('아이템 생성: 조종권 말고는 필드에 ITEM_MAX_ON_FIELD 개까지, 종류는 ITEM_POOL 에서', () => {
  const { g, p1, p2 } = setup();
  g.rng = Math.random;
  p1.x = 0.5;
  p2.x = 0.5;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = g.time;
  const seen = new Set();
  for (let t = 0; t < 120000; t += TICK) {
    g.tick(TICK);
    const power = g.items.filter((it) => it.type !== 'control');
    assert.ok(power.length <= C.ITEM_MAX_ON_FIELD);
    for (const it of power) seen.add(it.type);
    if (power.length === C.ITEM_MAX_ON_FIELD) g.items = []; // 계속 새로 나오게 비움
    g.powerItemNextAt = Math.min(g.powerItemNextAt, g.time + 200);
  }
  for (const type of C.ITEM_POOL) assert.ok(seen.has(type), `${type} 안 나옴`);
});

test('망치: WEAPON_USES 번 동안 밀치기 대신 — 넉백 약 2배, 경직 WEAPON_STUN_MS, 맞혔을 때만 소모', () => {
  const { g, p1, p2 } = setup();
  g.givePower(p1, 'weapon');
  assert.equal(p1.weaponUses, C.WEAPON_USES);
  p1.x = 2.5;
  p1.y = 5;
  p1.yaw = 0;
  p2.x = 3.5;
  p2.y = 5;
  g.handleAction(1, { name: 'push' });
  assert.equal(p1.weaponUses, C.WEAPON_USES - 1);
  assert.equal(p2.stunUntil, g.time + C.WEAPON_STUN_MS);
  assert.equal(p2.damage, C.DAMAGE_GAIN.weapon, '망치 피해 %');
  assert.ok(g.drainEvents().some((e) => e.type === 'hit' && e.kind === 'weapon' && e.ok));
  run(g, 2000);
  const d = p2.x - 3.5;
  assert.ok(d > 2.5 * C.DAMAGE_KB_BASE, `망치 넉백 거리 ${d.toFixed(2)} (피해 0% 밀치기 약 ${(1.5 * C.DAMAGE_KB_BASE).toFixed(2)})`);
  // 빗나가면 소모 안 함
  p1.pushReadyAt = 0;
  g.handleAction(1, { name: 'push' });
  assert.equal(p1.weaponUses, C.WEAPON_USES - 1, '빗나감');
  // 경직 중이라 무시돼도 소모 안 함
  Object.assign(p2, { x: 3.5, y: 5, z: 0, stunUntil: g.time + 1000 });
  p1.pushReadyAt = 0;
  g.handleAction(1, { name: 'push' });
  assert.equal(p1.weaponUses, C.WEAPON_USES - 1, '경직 중 무시');
  // 맞히면 소모 → 다 쓰면 다시 밀치기
  for (let k = 0; k < C.WEAPON_USES - 1; k++) {
    p2.stunUntil = 0;
    Object.assign(p2, { x: 3.5, y: 5, z: 0, kbx: 0, kby: 0 });
    p1.pushReadyAt = 0;
    g.handleAction(1, { name: 'push' });
  }
  assert.equal(p1.weaponUses, 0);
  p1.pushReadyAt = 0;
  g.handleAction(1, { name: 'push' });
  assert.ok(g.drainEvents().some((e) => e.type === 'swing' && e.kind === 'push'));
});

test('점프력 상승: 2칸 벽은 넘고 3칸 벽은 못 넘는다, 시간이 지나면 원래대로', () => {
  const { g, p1 } = setup();
  for (let y = 0; y < C.GRID_D; y++) {
    for (let z = 0; z < 2; z++) g.grid[g.idx(4, y, z)] = 1; // x=4 에 2칸 벽
    for (let z = 0; z < 3; z++) g.grid[g.idx(7, y, z)] = 1; // x=7 에 3칸 벽 (2칸 벽 위에서 보면 1칸 더)
  }
  for (let y = 0; y < C.GRID_D; y++) for (let x = 5; x < 7; x++) for (let z = 0; z < 2; z++) g.grid[g.idx(x, y, z)] = 1; // 2칸 벽 뒤는 2칸 높이 고원
  p1.x = 3.5;
  p1.y = 5;
  let landedOnPlateau = false;
  const jumpInto = (ms) => {
    let maxX = 0;
    for (let t = 0; t < ms; t += TICK) {
      g.handleInput(1, { fwd: 1, strafe: 0, jump: true, yaw: 0, pitch: 0 });
      g.tick(TICK);
      maxX = Math.max(maxX, p1.x);
      if (p1.grounded && Math.abs(p1.z - 2) < 1e-6 && p1.x > 4) landedOnPlateau = true;
    }
    return maxX;
  };
  assert.ok(jumpInto(1500) < 4, '부스트 없으면 2칸 벽 못 넘음');
  g.givePower(p1, 'jump');
  jumpInto(1500);
  assert.ok(landedOnPlateau, '부스트면 2칸 벽 위에 착지');
  // 고원(z=2)에서 3칸 벽(꼭대기 z=3)은 1칸 차이라 넘어감 — 바닥(z=0)에서 3칸은 못 넘는지 따로 확인
  p1.x = 8.5;
  p1.z = 0;
  for (let y = 0; y < C.GRID_D; y++) for (let x = 8; x < C.GRID_W; x++) for (let z = 0; z < 3; z++) g.grid[g.idx(x, y, z)] = 0;
  p1.x = 9.5;
  p1.yaw = Math.PI;
  let minX = 99;
  for (let t = 0; t < 1500; t += TICK) {
    g.handleInput(1, { fwd: 1, strafe: 0, jump: true, yaw: Math.PI, pitch: 0 });
    g.tick(TICK);
    minX = Math.min(minX, p1.x);
  }
  assert.ok(minX > 8 - 0.01 + C.PLAYER_HALF - 0.02, `바닥에서 3칸 벽은 못 넘음 (minX=${minX.toFixed(2)})`);
  run(g, C.JUMP_BOOST_MS);
  assert.equal(g.snapshot().players.find((p) => p.id === 1).jumpLeft, 0);
});

test('유령화: 옆으로 블록 통과, 점프하면 위 블록을 뚫고 올라가 그 위에 섬, 아래로는 안 빠짐, 끝나면 블록 밖으로', () => {
  const { g, p1 } = setup();
  for (let y = 0; y < C.GRID_D; y++) for (let z = 0; z < 3; z++) g.grid[g.idx(4, y, z)] = 1; // x=4 에 3칸 벽
  p1.x = 3.5;
  p1.y = 5;
  g.givePower(p1, 'ghost');
  // 옆으로 통과
  for (let t = 0; t < 800; t += TICK) {
    g.handleInput(1, { fwd: 1, strafe: 0, jump: false, yaw: 0, pitch: 0 });
    g.tick(TICK);
  }
  assert.ok(p1.x > 5, `벽 통과 (x=${p1.x.toFixed(2)})`);
  assert.ok(Math.abs(p1.z) < 1e-6, '바닥에 그대로');
  // 1칸 높이 블록 안으로 걸어 들어가 (유령이라 통과) 그 안에서 점프 → 위로 뚫고 나와 그 블록 위에 섬
  g.handleInput(1, { fwd: 0, strafe: 0, jump: false, yaw: 0, pitch: 0 });
  run(g, 300);
  const cx = Math.floor(p1.x);
  const cy = Math.floor(p1.y);
  for (let dx = -1; dx <= 1; dx++) for (let dy = -1; dy <= 1; dy++) g.grid[g.idx(cx + dx, cy + dy, 0)] = 1;
  run(g, 200);
  assert.ok(Math.abs(p1.z) < 1e-6, '블록 안 바닥에 서 있음 (아래로 안 빠짐)');
  g.handleInput(1, { fwd: 0, strafe: 0, jump: true, yaw: 0, pitch: 0 });
  run(g, 200);
  g.handleInput(1, { fwd: 0, strafe: 0, jump: false, yaw: 0, pitch: 0 });
  run(g, 800);
  assert.ok(Math.abs(p1.z - 1) < 1e-6, `블록 위에 섬 (z=${p1.z.toFixed(2)})`);
  // 다시 벽 안으로 걸어 들어간 채로 유령이 끝나면 꼭대기로
  p1.x = 4.5;
  p1.z = 0;
  run(g, C.GHOST_MS);
  assert.ok(p1.alive && p1.z >= 3 - 1e-6, `끝나면 벽 꼭대기 (z=${p1.z.toFixed(2)})`);
});

// ---------- 2단계 D: 맵 ----------
test('맵: 피라미드·계단 지형이 깔리고, 시작 위치는 지형 위, 용암은 시작 지형을 빼고 잰다', () => {
  for (const id of ['pyramid', 'stairs']) {
    const g = new Game();
    g.addPlayer(1);
    g.addPlayer(2);
    assert.ok(g.setMap(id));
    g.startRound();
    assert.equal(g.mapId, id);
    assert.ok(g.grid.reduce((a, b) => a + b, 0) > 0, `${id} 지형 있음`);
    for (const p of g.players.values()) assert.equal(p.z, g.spawnZ(p.x, p.y), `${id} ${p.name} 지형 위에서 시작`);
    g.nextSpawnAt = Infinity;
    g.tick(TICK);
    assert.equal(g.lava.active, false, `${id} 시작하자마자 용암 X (평균 ${g.avgHeight().toFixed(2)})`);
    // 올라가는 방향의 단차는 1칸 (기본 점프로 올라감): 피라미드는 모든 이웃, 계단은 계단 따라(x 방향)
    for (let x = 0; x < C.GRID_W; x++) {
      for (let y = 0; y < C.GRID_D; y++) {
        if (x + 1 < C.GRID_W) assert.ok(Math.abs(g.columnTop(x, y) - g.columnTop(x + 1, y)) <= 1, `${id} (${x},${y})→x+1`);
        if (id === 'pyramid' && y + 1 < C.GRID_D) assert.ok(Math.abs(g.columnTop(x, y) - g.columnTop(x, y + 1)) <= 1, `${id} (${x},${y})→y+1`);
      }
    }
  }
});

test('맵: 모든 맵에서 시작 위치마다 걸어서(한 걸음 1칸까지) 그 맵의 맨 위까지 갈 수 있다', () => {
  for (const id of ['flat', 'pyramid', 'stairs', 'bowl', 'spiral', 'pillars', 'fortress']) {
    const g = new Game();
    for (let i = 1; i <= 4; i++) g.addPlayer(i);
    assert.ok(g.setMap(id), id);
    g.startRound();
    let max = 0;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) max = Math.max(max, g.columnTop(x, y));
    if (id !== 'flat') assert.ok(max >= 2, `${id} 최고 ${max}층`);
    g.nextSpawnAt = Infinity;
    g.tick(TICK);
    assert.equal(g.lava.active, false, `${id} 시작하자마자 용암 X`);
    for (const p of g.players.values()) {
      assert.equal(p.z, g.spawnZ(p.x, p.y), `${id} ${p.name} 지형 위에서 시작`);
      const sx = Math.floor(p.x);
      const sy = Math.floor(p.y);
      const seen = new Set([sx * 100 + sy]);
      const q = [[sx, sy]];
      let best = 0;
      while (q.length) {
        const [x, y] = q.shift();
        const h = g.columnTop(x, y);
        best = Math.max(best, h);
        for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
          const nx = x + dx;
          const ny = y + dy;
          if (nx < 0 || ny < 0 || nx >= C.GRID_W || ny >= C.GRID_D || seen.has(nx * 100 + ny)) continue;
          if (g.columnTop(nx, ny) > h + 1) continue;
          seen.add(nx * 100 + ny);
          q.push([nx, ny]);
        }
      }
      assert.equal(best, max, `${id} ${p.name} 시작 위치에서 최고 ${best}층 (맵 최고 ${max})`);
    }
  }
});

test('맵: 무작위는 판마다 바뀌고, 이상한 값·판 진행 중 변경은 거부', () => {
  const g = new Game();
  g.rng = Math.random;
  g.addPlayer(1);
  g.addPlayer(2);
  assert.equal(g.setMap('nope'), false);
  assert.ok(g.setMap('random'));
  const seen = new Set();
  for (let i = 0; i < 30; i++) {
    g.startRound();
    seen.add(g.mapId);
    assert.equal(g.setMap('flat'), false, '판 중엔 못 바꿈');
    g.phase = 'over';
  }
  assert.ok(seen.size >= 2, `무작위로 ${[...seen].join(',')}`);
});

// ---------- 설치 블록 (던져서 떨어뜨림) ----------
function brickSetup() {
  const s = setup();
  const { g, p1, p2 } = s;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  // +x 를 보고 앞 2칸 바닥을 내려다봄 → 기준 칸 (4,5)
  Object.assign(p1, { x: 2.5, y: 5.5, z: 0, yaw: 0, pitch: -Math.atan2(C.EYE_HEIGHT, 2) });
  Object.assign(p2, { x: 8.5, y: 8.5, z: 0 });
  g.givePower(p1, 'brick');
  return s;
}

test('설치 블록: 먹으면 1×2 를 BRICK_USES 개, 2번 칸으로 바뀌고, 투사체와 2번 칸을 같이 써서 나중에 먹은 쪽만 남는다', () => {
  const { g, p1 } = brickSetup();
  assert.equal(p1.bricks, C.BRICK_USES);
  assert.equal(p1.hand, 2);
  g.givePower(p1, 'knockback');
  assert.equal(p1.bricks, 0, '투사체를 먹으면 설치 블록은 버림');
  g.givePower(p1, 'brick');
  assert.equal(p1.ammo, 0, '설치 블록을 먹으면 투사체는 버림');
});

test('설치 블록: 조준한 칸 위 BRICK_DROP_HEIGHT 칸에서 떨어져 그 기둥 위에 쌓이고, 다 쓰면 우클릭은 아무것도 안 한다', () => {
  const { g, p1, lines } = brickSetup();
  const plan = g.brickPlan(p1);
  assert.deepEqual(plan.cells, [[4, 5, 0], [5, 5, 0]], '1×2 는 바라보는 쪽으로');
  assert.equal(plan.spawnZ, C.BRICK_DROP_HEIGHT);
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.bricks, C.BRICK_USES - 1);
  assert.equal(g.projectiles.length, 0, '투사체는 안 나감');
  const piece = g.pieces.find((pc) => pc.thrownBy === 1);
  assert.ok(piece && piece.phase === 'falling', '떨어지는 블록이 생김');
  assert.ok(lines.some((l) => l.includes('[투척] P1 1×2 → (4,5) z=0')), lines.join('\n'));
  run(g, C.BRICK_FALL_STEP_MS * (C.BRICK_DROP_HEIGHT + 1));
  assert.equal(g.gridAt(4, 5, 0), 1);
  assert.equal(g.gridAt(5, 5, 0), 1);
  assert.equal(g.pieces.length, 0);
  g.handleAction(1, { name: 'fire' });
  run(g, C.BRICK_FALL_STEP_MS * (C.BRICK_DROP_HEIGHT + 1));
  assert.equal(g.gridAt(4, 5, 1), 1, '두 번째는 그 위에');
  assert.equal(p1.bricks, 0);
  g.handleAction(1, { name: 'fire' });
  assert.equal(g.pieces.length, 0, '다 쓰면 안 던짐');
});

test('설치 블록 조준: 시선이 안 닿으면 BRICK_RANGE 끝 칸, 벽에 닿으면 그 칸 위. Q/E 로 옆', () => {
  const { g, p1 } = brickSetup();
  p1.pitch = 0; // 수평: 평지라 끝까지 안 닿음 → 4칸 앞 (6,5)
  assert.deepEqual(g.brickPlan(p1).cells, [[6, 5, 0], [7, 5, 0]]);
  for (let z = 0; z < 3; z++) g.grid[g.idx(4, 5, z)] = 1; // 2칸 앞 3층 벽
  const plan = g.brickPlan(p1);
  assert.deepEqual(plan.cells[0], [4, 5, 3], '벽에 닿은 칸 위');
  g.handleAction(1, { name: 'rotate', dir: 1 });
  assert.equal(p1.brickSide, true);
  assert.deepEqual(g.brickPlan(p1).cells.map(([x, y]) => [x, y]), [[4, 5], [4, 6]]);
});

test('설치 블록: 필드 밖·떨어지는 블록이 있는 자리면 못 던지고 소모도 안 한다', () => {
  const { g, p1 } = brickSetup();
  Object.assign(p1, { x: 9.5, y: 5.5, yaw: 0 }); // 앞이 필드 밖
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.bricks, C.BRICK_USES);
  Object.assign(p1, { x: 2.5, y: 5.5, yaw: 0 });
  fallingPiece(g, 'O', 0, 4, 4, C.BRICK_DROP_HEIGHT); // 생길 자리에 떨어지는 블록
  assert.equal(g.brickPlan(p1).ok, false);
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.bricks, C.BRICK_USES);
});

test('설치 블록: 밑에 있으면 압사, 착지한 칸 바로 옆이면 충격파로 망치급 넉백 + 피해 %, 멀면 무사', () => {
  const { g, p1, p2, lines } = brickSetup();
  g.addPlayer(3);
  const p3 = g.players.get(3);
  g.phase = 'playing';
  p3.alive = true;
  Object.assign(p2, { x: 4.5, y: 5.5, z: 0 }); // 떨어질 칸 (4,5) 밑
  Object.assign(p3, { x: 6.5, y: 5.5, z: 0 }); // (5,5) 바로 옆
  g.addPlayer(4);
  const p4 = g.players.get(4);
  Object.assign(p4, { x: 7.6, y: 5.5, z: 0, alive: true }); // 블록 가장자리(x=6)에서 1.3칸: BRICK_SHOCK_RANGE 밖
  g.handleAction(1, { name: 'fire' });
  run(g, C.BRICK_FALL_STEP_MS * (C.BRICK_DROP_HEIGHT + 1));
  assert.equal(p2.deathCause, 'crush');
  assert.ok(lines.some((l) => l.includes('[투척] P1 의 1×2 에 P2 깔림')), lines.join('\n'));
  assert.equal(p3.alive, true);
  assert.equal(p3.damage, C.DAMAGE_GAIN.shock);
  assert.ok(p3.kbx > C.PUSH_KB_SPEED, `바깥쪽(+x)으로 세게: kbx ${p3.kbx}`);
  assert.equal(p4.damage, 0, '충격파 범위 밖은 무사');
  assert.equal(p4.kbx, 0);
  // 던진 사람은 바로 옆이어도 자기 충격파를 안 맞음
  g.phase = 'playing';
  Object.assign(p1, { x: 3.5, y: 5.5, z: 0, pitch: -Math.atan2(C.EYE_HEIGHT, 1.5), alive: true });
  g.handleAction(1, { name: 'fire' });
  run(g, C.BRICK_FALL_STEP_MS * (C.BRICK_DROP_HEIGHT + 1));
  assert.equal(p1.damage, 0, '던진 사람은 자기 충격파 X');
  assert.ok(lines.some((l) => l.includes(`[충격파] P1 → P3 넉백 (P3 ${C.DAMAGE_GAIN.shock}%)`)), lines.join('\n'));
});

// ---------- 피해 % ----------
test('피해 %: 맞을 때마다 종류별로 쌓이고, 쌓인 만큼 멀리 날아간다 (거리 ∝ DAMAGE_KB_BASE + % × DAMAGE_KB_PER_PERCENT)', () => {
  const pushDist = (dmg) => {
    const { g, p1, p2 } = setup();
    Object.assign(p1, { x: 3.5, y: 5, yaw: 0 });
    Object.assign(p2, { x: 4.5, y: 5, damage: dmg });
    g.handleAction(1, { name: 'push' });
    const x2 = p2.x;
    run(g, 2500);
    return { d: p2.x - x2, p2 };
  };
  const a = pushDist(0);
  assert.equal(a.p2.damage, C.DAMAGE_GAIN.push);
  const b = pushDist(100);
  const want = (C.DAMAGE_KB_BASE + 100 * C.DAMAGE_KB_PER_PERCENT) / C.DAMAGE_KB_BASE;
  assert.ok(Math.abs(b.d / a.d - want) < 0.15 * want, `0%: ${a.d.toFixed(2)}칸, 100%: ${b.d.toFixed(2)}칸 (기대 비 ${want.toFixed(2)})`);
});

test('피해 %: 경직 중이라 무시된 공격은 안 쌓이고, 새 판이면 0, 로그에 남는다', () => {
  const { g, p1, p2, lines } = setup();
  Object.assign(p1, { x: 3.5, y: 5, yaw: 0 });
  Object.assign(p2, { x: 4.5, y: 5 });
  g.handleAction(1, { name: 'push' });
  assert.equal(p2.damage, 10);
  p1.pushReadyAt = 0;
  Object.assign(p2, { x: 4.5, y: 5 });
  g.handleAction(1, { name: 'push' }); // 경직 중
  assert.equal(p2.damage, 10);
  assert.ok(lines.some((l) => l.includes('[밀치기] P1 → P2 넉백 (P2 10%)')), lines.join('\n'));
  g.kill(p2, 'fall');
  assert.ok(lines.some((l) => l.includes('피해 10%)')), lines.join('\n'));
  g.phase = 'over';
  g.startRound();
  assert.equal(p2.damage, 0);
});

test('봇: 용암이 오는데 구덩이에 갇히면 설치 블록을 던져 발판을 만들고 올라간다 (10번 모두)', () => {
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    // 필드 전체 2층, 가운데 3×3 만 바닥까지 파인 구덩이 (점프 1.28칸으로는 못 나옴)
    const pit = (x, y) => x >= 5 && x <= 7 && y >= 5 && y <= 7;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) if (!pit(x, y)) for (let z = 0; z < 2; z++) g.grid[g.idx(x, y, z)] = 1;
    g.gridVersion++;
    Object.assign(human, { x: 0.5, y: 0.5, z: 2 });
    Object.assign(bot, { x: 5.5, y: 5.5, z: 0 });
    g.givePower(bot, 'brick');
    bot.blocks = 0; // 쌓기 블록 없이 설치 블록만으로
    g.lava = { active: true, z: -0.9, startedAt: g.time };
    let out = false;
    for (let t = 0; t < 8000 && !out; t += TICK) {
      g.tick(TICK);
      if (bot.grounded && bot.z > 1.99) out = true;
    }
    assert.ok(out, `${k}번째 (남은 ${bot.bricks}, ${bot.alive ? '' : bot.deathCause}): 봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)}, ${bot.z.toFixed(2)})`);
  }
});

function brickDuel() {
  const { g, human, bot, lines } = setupBot();
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  Object.assign(human, { x: 6.5, y: 5.5, z: 0 });
  Object.assign(bot, { x: 3.5, y: 5.5, z: 0 });
  g.givePower(bot, 'brick');
  run(g, 2500);
  return { human, lines };
}

test('봇: 용암 전에는 가만히 선 상대 발밑에 설치 블록을 던져 깔아 죽인다 (조준 오차 0 으로 고정)', () => {
  const saved = C.BOT_BRICK_AIM_ERROR;
  C.BOT_BRICK_AIM_ERROR = 0;
  try {
    const { human, lines } = brickDuel();
    assert.ok(lines.some((l) => l.includes('[투척] P2(봇)')), lines.join('\n'));
    assert.equal(human.deathCause, 'crush');
  } finally {
    C.BOT_BRICK_AIM_ERROR = saved;
  }
});

test('봇: 설치 블록 조준 오차 때문에 가끔 빗나간다 (30번 중 한 번 이상 빗나가고 10번 이상은 맞힘)', () => {
  // 실측 (BOT_BRICK_AIM_ERROR 1.2, 200번): 오차 0 이면 200/200, 1.2 면 136/200 압사
  let hit = 0;
  for (let k = 0; k < 30; k++) if (brickDuel().human.deathCause === 'crush') hit++;
  assert.ok(hit < 30 && hit >= 10, `30번 중 ${hit}번 압사`);
});

test('승수: 이긴 사람 승수가 쌓이고 스냅샷·로그에 나온다, 무승부는 안 셈', () => {
  const { g, p1, p2, lines } = setup();
  g.kill(p2, 'fall');
  g.tick(TICK);
  assert.equal(p1.wins, 1);
  assert.ok(lines.some((l) => l.includes('승수: P1 1 / P2 0')), lines.join('\n'));
  assert.equal(g.snapshot().players.find((p) => p.id === 1).wins, 1);
  g.startRound();
  g.kill(p1, 'fall');
  g.kill(p2, 'fall');
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.equal(p1.wins + p2.wins, 1, '무승부는 안 셈');
});

test('카운트다운: 시작하면 3초 동안 시작 위치에서 대기 (블록·아이템·이동 없음), 그 뒤 판 시계가 0 부터', () => {
  const lines = [];
  const g = new Game((x) => lines.push(x), { countdownMs: 3000 });
  g.addPlayer(1);
  g.addPlayer(2);
  const p1 = g.players.get(1);
  assert.equal(g.startRound(), true);
  assert.equal(g.phase, 'countdown');
  assert.equal(g.canStart(), false, '카운트다운 중엔 다시 시작 못 함');
  assert.equal(g.addBot(), null, '카운트다운 중엔 봇 추가 못 함');
  const x0 = p1.x;
  g.handleInput(1, { fwd: 1, strafe: 0, jump: true, yaw: 0, pitch: 0 });
  g.handleAction(1, { name: 'dash' });
  run(g, 2900);
  assert.equal(g.phase, 'countdown');
  assert.equal(p1.x, x0, '안 움직임');
  assert.equal(g.pieces.length, 0);
  assert.equal(g.items.length, 0);
  assert.ok(g.snapshot().round.countdownLeft > 0);
  assert.ok(!lines.some((l) => l.includes('시작 (')), '판 시작 로그는 카운트다운 뒤');
  run(g, 200);
  assert.equal(g.phase, 'playing');
  assert.ok(g.elapsed() < 200, `판 시계 ${g.elapsed()}`);
  assert.ok(lines.some((l) => l.includes('ROUND 1 시작')), lines.join('\n'));
  g.addPlayer(3);
  assert.equal(g.players.get(3).alive, false, '진행 중 난입은 관전');
});

test('카운트다운 중에 나가서 혼자 남으면 카운트다운이 끝나는 순간 판이 끝난다', () => {
  const g = new Game(() => {}, { countdownMs: 3000 });
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  g.removePlayer(2);
  run(g, 3100);
  assert.equal(g.phase, 'over');
  assert.equal(g.winnerId, 1);
});

// ---------- 핫바 · 쌓기 블록 · 폭탄 ----------
test('핫바: 판마다 쌓기 블록 BUILD_BLOCKS_PER_ROUND 개, 숫자키·휠로 칸을 고르고 우클릭은 고른 칸을 쓴다', () => {
  const { g, p1 } = setup();
  assert.equal(p1.blocks, C.BUILD_BLOCKS_PER_ROUND);
  assert.equal(p1.hand, 1);
  g.handleAction(1, { name: 'hand', n: 3 });
  assert.equal(p1.hand, 3);
  g.handleAction(1, { name: 'handNext', dir: 1 });
  assert.equal(p1.hand, 1, '3 다음은 1');
  g.handleAction(1, { name: 'handNext', dir: -1 });
  assert.equal(p1.hand, 3, '1 이전은 3');
  g.handleAction(1, { name: 'hand', n: 7 });
  assert.equal(p1.hand, 3, '없는 칸은 무시');
  g.givePower(p1, 'bomb');
  assert.equal(p1.hand, 3);
  assert.equal(p1.bombs, C.BOMB_USES);
  g.givePower(p1, 'knockback');
  assert.equal(p1.hand, 2, '먹으면 그 칸으로');
  assert.equal(p1.bombs, C.BOMB_USES, '폭탄은 다른 칸이라 그대로');
});

function buildSetup() {
  const s = setup();
  const { p1, p2 } = s;
  Object.assign(p1, { x: 2.5, y: 5.5, z: 0, yaw: 0, hand: 1 });
  Object.assign(p2, { x: 8.5, y: 8.5, z: 0 });
  return s;
}

test('쌓기 블록: 조준한 면에 바로 붙는다 (바닥 위·옆면·꼭대기), 사거리 밖이나 사람 자리면 안 됨, 다 쓰면 끝', () => {
  const { g, p1, p2, lines } = buildSetup();
  p1.pitch = -Math.atan2(C.EYE_HEIGHT, 1.8); // 1.8칸 앞(x=4.3) 바닥 → (4,5) 바닥 위
  assert.deepEqual(g.buildPlan(p1).cells, [[4, 5, 0]]);
  g.handleAction(1, { name: 'fire' });
  assert.equal(g.gridAt(4, 5, 0), 1);
  assert.equal(p1.blocks, C.BUILD_BLOCKS_PER_ROUND - 1);
  assert.ok(lines.some((l) => l.includes('[쌓기] P1 → (4,5,0)')), lines.join('\n'));
  // 옆면: 2칸 앞 3층 기둥을 수평으로 보면 눈높이 칸의 옆면 → 그 앞 칸 (3,5) 공중
  for (let z = 0; z < 3; z++) g.grid[g.idx(5, 5, z)] = 1;
  Object.assign(p1, { x: 3.5, pitch: 0 });
  const side = g.buildPlan(p1).cells[0];
  assert.deepEqual(side, [4, 5, Math.floor(C.EYE_HEIGHT)], `옆면 앞 칸 ${side}`);
  // 수평으로 평지를 보면 사거리 안에 닿는 게 없음
  Object.assign(p1, { x: 2.5, y: 1.5, pitch: 0 });
  assert.equal(g.buildPlan(p1).ok, false);
  // 사람이 서 있는 칸엔 못 놓음
  Object.assign(p1, { x: 2.5, y: 5.5, pitch: -Math.atan2(C.EYE_HEIGHT, 1.8) });
  g.grid[g.idx(4, 5, 0)] = 0;
  Object.assign(p2, { x: 4.5, y: 5.5, z: 0 });
  assert.equal(g.buildPlan(p1).ok, false);
  p2.x = 8.5;
  p1.blocks = 0;
  g.handleAction(1, { name: 'fire' });
  assert.equal(g.gridAt(4, 5, 0), 0, '다 쓰면 안 놓임');
});

test('폭탄: 조준한 칸 위에 놓여 BOMB_FUSE_MS 뒤 3×3×3 블록을 부수고 근처 사람을 날린다 (던진 사람·먼 블록은 무사)', () => {
  const { g, p1, p2, lines } = buildSetup();
  for (let x = 3; x <= 7; x++) for (let z = 0; z < 3; z++) g.grid[g.idx(x, 5, z)] = 1; // y=5 줄에 3층 벽
  for (let z = 0; z < 2; z++) g.grid[g.idx(3, 6, z)] = 1; // 폭탄 옆 2층 기둥 (상대가 설 자리)
  g.gridVersion++;
  Object.assign(p1, { x: 1.5, y: 5.5, z: 0, pitch: 0 });
  g.givePower(p1, 'bomb');
  const plan = g.bombPlan(p1);
  const [bx, by, bz] = plan.cells[0];
  assert.deepEqual([bx, by, bz], [3, 5, 3], `벽 첫 칸 위 ${plan.cells[0]}`);
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.bombs, 0);
  assert.equal(g.bombs.length, 1);
  run(g, C.BOMB_FUSE_MS - 100);
  assert.equal(g.gridAt(3, 5, 2), 1, '터지기 전');
  Object.assign(p2, { x: 3.5, y: 6.5, z: 2, vz: 0 }); // 폭탄 바로 옆 기둥 위
  g.addPlayer(3);
  const p3 = g.players.get(3);
  Object.assign(p3, { x: 6.5, y: 5.5, z: 3, vz: 0, alive: true }); // 같은 높이 벽 위, 수평 3칸: BOMB_BLAST_RANGE 밖
  run(g, 200);
  assert.equal(g.bombs.length, 0);
  assert.equal(g.gridAt(3, 5, 2), 0, '폭탄 밑 칸 부서짐');
  assert.equal(g.gridAt(4, 5, 2), 0, '옆 칸 부서짐');
  assert.equal(g.gridAt(3, 5, 1), 1, 'z-2 는 남음');
  assert.equal(g.gridAt(5, 5, 2), 1, '범위 밖 남음');
  assert.equal(p2.damage, C.DAMAGE_GAIN.bomb);
  assert.ok(g.time < p2.stunUntil, '맞은 사람 경직');
  assert.equal(p1.damage, 0, '던진 사람 면제');
  assert.equal(p3.damage, 0, '폭발 범위 밖은 무사');
  assert.equal(g.gridAt(3, 6, 1), 1, '옆 기둥은 범위(z 2~4) 밖이라 남음');
  assert.ok(lines.some((l) => l.includes('블록 2칸 파괴')), lines.join('\n'));
});

test('봇: 용암이 오는데 구덩이에 갇히면 쌓기 블록으로 발판을 놓고 올라간다 (10번 모두)', () => {
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    const pit = (x, y) => x >= 5 && x <= 7 && y >= 5 && y <= 7;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) if (!pit(x, y)) for (let z = 0; z < 2; z++) g.grid[g.idx(x, y, z)] = 1;
    g.gridVersion++;
    Object.assign(human, { x: 0.5, y: 0.5, z: 2 });
    Object.assign(bot, { x: 5.5, y: 5.5, z: 0 });
    assert.equal(bot.blocks, C.BUILD_BLOCKS_PER_ROUND);
    g.lava = { active: true, z: -0.9, startedAt: g.time };
    let out = false;
    for (let t = 0; t < 8000 && !out; t += TICK) {
      g.tick(TICK);
      if (bot.grounded && bot.z > 1.99) out = true;
    }
    assert.ok(out, `${k}번째 (블록 ${bot.blocks}): 봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)}, ${bot.z.toFixed(2)})`);
  }
});

test('봇: 상대가 폭발 범위에 들면 폭탄을 던진다', () => {
  const { g, human, bot, lines } = setupBot();
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  Object.assign(human, { x: 6.5, y: 5.5, z: 0 });
  Object.assign(bot, { x: 3.5, y: 5.5, z: 0 });
  g.givePower(bot, 'bomb');
  run(g, 1000);
  assert.ok(lines.some((l) => l.includes('[폭탄] P2(봇) →')), lines.join('\n'));
});

test('봇: 놓인 폭탄의 폭발 범위를 보고 피한다 (옆에 때릴 상대가 있어도, 10번 모두)', () => {
  for (let k = 0; k < 10; k++) {
    const { g, human, bot } = setupBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.controlItemNextAt = Infinity;
    g.powerItemNextAt = Infinity;
    Object.assign(human, { x: 6.5, y: 5.5, z: 0, stunUntil: 1e12 }); // 계속 경직이라 밀려나지 않는 상대
    Object.assign(bot, { x: 5.5, y: 5.5, z: 0 });
    g.bombs.push({ id: 99, x: 5, y: 5, z: 0, by: human.id, explodeAt: g.time + C.BOMB_FUSE_MS });
    run(g, C.BOMB_FUSE_MS + 100);
    assert.equal(bot.damage, 0, `${k}번째: 봇 위치 (${bot.x.toFixed(2)}, ${bot.y.toFixed(2)})`);
  }
});

test('이름: 제어 문자 빼고 NAME_MAX_LEN 글자까지 (한글도 한 글자), 판 사이에만, 스냅샷에 nick', () => {
  const { g, p1, lines } = setup();
  assert.equal(g.setNick(1, '재혁'), false, '판 진행 중엔 못 바꿈');
  g.phase = 'over';
  assert.equal(g.setNick(1, '  재혁\u0007  최고   '), true);
  assert.equal(p1.nick, '재혁 최고');
  g.setNick(1, '가나다라마바사아자차카');
  assert.equal(Array.from(p1.nick).length, C.NAME_MAX_LEN);
  assert.equal(p1.name, 'P1', '로그·승수용 이름은 그대로');
  assert.equal(g.snapshot().players.find((p) => p.id === 1).nick, p1.nick);
  assert.ok(lines.some((l) => l.startsWith('P1 이름: ')), lines.join('\n'));
  g.setNick(1, null);
  assert.equal(p1.nick, '');
});

test('카운트다운 중에 나간 사람: 사망 목록에 남고, 인원수 통계는 실제로 시작한 인원으로 센다', () => {
  const lines = [];
  const g = new Game((x) => lines.push(x), { countdownMs: 3000 });
  for (let i = 1; i <= 3; i++) g.addPlayer(i);
  g.startRound();
  g.removePlayer(3);
  run(g, 3100);
  assert.equal(g.phase, 'playing');
  assert.equal(g.roundPlayerCount, 2);
  assert.ok(lines.some((l) => l.includes('ROUND 1 시작 (2명')), lines.join('\n'));
  assert.ok(g.deaths.some((d) => d.name === 'P3' && d.cause === 'disconnect' && d.t === 0));
  g.kill(g.players.get(2), 'fall');
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.ok(g.totalsByCount['2인'], `인원수 통계 ${Object.keys(g.totalsByCount)}`);
  assert.equal(g.totalsByCount['3인'], undefined);
});

test('관전 전환: 판 사이에만, 관전자는 판에 안 들어가고 시작 인원·인원수 통계에서 빠진다', () => {
  const g = new Game(() => {});
  for (let i = 1; i <= 3; i++) g.addPlayer(i);
  const p3 = g.players.get(3);
  assert.equal(g.setSpectator(3, true), true);
  g.setSpectator(2, true);
  assert.equal(g.canStart(), false, '참가자 1명이면 시작 못 함');
  g.setSpectator(2, false);
  g.startRound();
  assert.equal(p3.alive, false, '관전자는 판에 안 들어감');
  assert.equal(g.roundPlayerCount, 2);
  assert.equal(g.setSpectator(3, false), false, '판 중엔 못 바꿈');
  g.kill(g.players.get(2), 'fall');
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.ok(g.totalsByCount['2인'] && !g.totalsByCount['3인'], Object.keys(g.totalsByCount).join());
  assert.equal(g.snapshot().players.find((p) => p.id === 3).spectator, true);
  g.setSpectator(3, false);
  g.startRound();
  assert.equal(p3.alive, true, '참가로 돌리면 다음 판에 들어감');
});
