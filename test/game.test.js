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

test('플레이어 접속 제한: PLAYER_COUNT 초과는 거부', () => {
  const g = new Game();
  for (let i = 0; i < C.PLAYER_COUNT; i++) assert.ok(g.addPlayer(i + 1));
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
  assert.equal(g.snapshot().piece.shadowVisible, false);
  // 12칸 × 500ms = 6초 낙하. 3.5초 후엔 보여야 한다
  run(g, 3500);
  assert.equal(g.snapshot().piece.shadowVisible, true);
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
  // z=0 층을 O 자리 (4..5, 4..5) 빼고 채운다
  for (let y = 0; y < C.GRID_D; y++) for (let x = 0; x < C.GRID_W; x++) if (!(x >= 4 && y >= 4)) g.grid[g.idx(x, y, 0)] = 1;
  g.grid[g.idx(0, 0, 1)] = 1; // 위에 블록 하나
  p1.x = 0.5;
  p1.y = 0.5;
  p1.z = 2; // 그 블록 위에 서 있음
  fallingPiece(g, 'O', 0, 4, 4, 3, 50);
  run(g, 50 * 5);
  assert.equal(g.piece, null);
  assert.equal(g.gridAt(0, 0, 0), 1, '위에 있던 블록이 z=0 으로 내려와야 함');
  assert.equal(g.gridAt(0, 0, 1), 0);
  assert.equal(g.gridAt(4, 4, 0), 0, '착지한 O 는 층과 함께 사라져야 함');
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
  run(g, C.HARD_DROP_STEP_MS * 14);
  assert.equal(g.piece, null);
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
  g.handleAction(1, { name: 'fire' });
  assert.equal(g.projectiles.length, 0, '탄 없으면 발사 안 됨');
  p1.ammo = 1;
  g.handleAction(1, { name: 'fire' });
  assert.equal(p1.ammo, 0);
  assert.equal(g.projectiles.length, 1);
  run(g, 500);
  assert.equal(g.projectiles.length, 0);
  assert.ok(p2.kbx > 0 && p2.stunUntil > 0, '투사체 맞고 넉백');
});

test('아이템 스폰·획득', () => {
  const { g, p1 } = setup();
  g.controlItemNextAt = g.time;
  g.knockbackItemNextAt = g.time;
  const seq = [0.3, 0.3, 0.5, 0.5]; // 조종권 (1,1), 넉백 (3,3)
  g.rng = () => (seq.length ? seq.shift() : 0.5);
  g.tick(TICK);
  assert.equal(g.items.length, 2);
  p1.x = 1.5;
  p1.y = 1.5;
  g.tick(TICK);
  assert.equal(p1.hasControl, true);
  p1.x = 3.5;
  p1.y = 3.5;
  run(g, 100);
  assert.equal(p1.hasControl, true);
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
