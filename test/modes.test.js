// 게임 모드 테스트: 블록 마스터 (1 대 다) · 킬 점수전 (부활)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { footprint } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;

function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

// n명 판. 아이템은 안 나오게 (테스트가 직접 제어)
function setupMode(mode, n = 3, { start = true } = {}) {
  const lines = [];
  const g = new Game((s) => lines.push(s));
  g.rng = () => 0.5;
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  assert.ok(g.setMode(mode));
  if (start) startQuiet(g);
  return { g, lines, p: (id) => g.players.get(id) };
}

function startQuiet(g) {
  assert.ok(g.startRound());
  g.powerItemNextAt = Infinity;
  g.controlItemNextAt = Infinity;
}

// 필드 밖 아래로 (다음 틱에 낙사). 필드 안 바닥 아래면 바닥이 밀어 올림
function fallOff(p) {
  Object.assign(p, { x: -3, z: C.FALL_DEATH_Z - 1 });
}

// 플레이어를 칸 가운데 바닥에 세움
function place(p, x, y, z = 0) {
  Object.assign(p, { x, y, z, vz: 0, kbx: 0, kby: 0, grounded: true });
}

test('모드: 판 사이에만, 호스트가 고른 것만. 블록 마스터를 고르면 팀전이 꺼지고 다시 못 켬', () => {
  const lines = [];
  const g = new Game((s) => lines.push(s));
  g.addPlayer(1);
  g.addPlayer(2);
  assert.equal(g.mode, 'survival');
  assert.equal(g.setMode('nope'), false);
  assert.ok(g.setTeamMode(true));
  assert.ok(g.setMode('master'));
  assert.equal(g.teamMode, false);
  assert.ok(lines.includes('[호스트] 모드: 블록 마스터'));
  assert.equal(g.setTeamMode(true), false, '블록 마스터는 팀전 없음');
  assert.ok(g.setMode('kills'));
  assert.ok(g.setTeamMode(true), '킬 점수전은 팀전 됨');
  g.startRound();
  assert.equal(g.setMode('survival'), false, '판 중엔 못 바꿈');
});

test('블록 마스터: 자리 순서로 마스터, 마스터는 필드에 없고 블록만 조종, 자동 블록·조종권 없음', () => {
  const { g, lines, p } = setupMode('master');
  const m = p(1);
  assert.ok(m.master && !p(2).master && !p(3).master);
  assert.ok(lines.some((l) => l.startsWith('  모드: 블록 마스터 (마스터 P1')));
  const z0 = m.z;
  run(g, C.FIRST_SPAWN_DELAY_MS + 100);
  assert.ok(g.controlledPiece(m), '첫 블록은 마스터가 조종');
  assert.equal(m.z, z0, '마스터 몸은 물리에서 빠짐 (안 떨어짐)');
  // 밀치기·대시는 무시
  g.handleAction(1, { name: 'push' });
  assert.equal(m.pushReadyAt, 0);
  // 떨어뜨리면 MASTER_NEXT_PIECE_MS 뒤 다음 블록
  g.handleAction(1, { name: 'drop' });
  assert.equal(g.controlledPiece(m), null);
  run(g, C.MASTER_NEXT_PIECE_MS + 2 * TICK);
  assert.ok(g.controlledPiece(m), '다음 블록');
  // 생존자를 가장자리로 피신시키고 오래 돌려도 자동 블록·조종권은 없음
  place(p(2), 0.5, 0.5);
  place(p(3), 9.5, 9.5);
  g.controlItemNextAt = 0; // 조종권 시계가 다 돌아도
  run(g, 20000);
  assert.ok(g.pieces.every((pc) => pc.controller === 1), '블록은 전부 마스터 것');
  assert.ok(!g.items.some((it) => it.type === 'control'), '조종권 안 나옴');
  assert.equal(g.itemTimers().control, null, '조종권 시계도 안 보임');
});

test('블록 마스터: 생존자끼리는 각자 도생 (서로 밀고 피해 % 쌓임), 마스터는 맞지 않음', () => {
  const { g, p } = setupMode('master');
  place(p(2), 4.5, 4.5);
  place(p(3), 5.5, 4.5);
  p(2).yaw = 0;
  g.handleAction(2, { name: 'push' });
  assert.ok(p(3).damage > 0, '생존자끼리 피해 %');
  // 폭탄이 마스터 자리 바로 옆에서 터져도 마스터는 그대로
  Object.assign(p(1), { x: 5.5, y: 5.5, z: 0 }); // 일부러 필드 위로 (원래는 하늘)
  g.bombs.push({ id: 1, by: 2, x: 5, y: 5, z: 0, explodeAt: g.time });
  g.updateBombs();
  assert.equal(p(1).damage, 0, '마스터는 판정에서 빠짐');
});

test('블록 마스터: 생존자가 다 깔리면 마스터 승 (마스터 킬)', () => {
  const { g, lines, p } = setupMode('master');
  run(g, C.FIRST_SPAWN_DELAY_MS + 100);
  const piece = g.controlledPiece(p(1));
  const cells = g.pieceWorldCells(piece);
  place(p(2), cells[0][0] + 0.5, cells[0][1] + 0.5);
  place(p(3), cells.at(-1)[0] + 0.5, cells.at(-1)[1] + 0.5);
  g.handleAction(1, { name: 'drop' });
  run(g, 3000);
  assert.equal(g.phase, 'over');
  assert.deepEqual(g.winnerIds, [1]);
  assert.equal(p(1).wins, 1);
  assert.ok(lines.some((l) => /\[사망\] P2 압사 .*킬 P1 조종블록/.test(l)));
  assert.ok(lines.some((l) => /ROUND 1 종료 .*승자: P1 =====/.test(l)));
  assert.ok(lines.includes('  결과: 마스터 P1 승 (생존자 전멸)'));
  assert.ok(!p(1).master && p(1).z <= C.GRID_H, '판이 끝나면 마스터는 필드 가운데로 내려옴 (승리 연출)');
  assert.ok(g.startEmote(p(1), 1), '판 끝 이모트도 됨');
});

test(`블록 마스터: ${C.MASTER_TIME_MS / 1000}초 버티면 살아남은 생존자 모두 승, 마스터는 다음 판에 다음 자리로`, () => {
  const { g, lines, p } = setupMode('master');
  place(p(2), 0.5, 0.5);
  place(p(3), 9.5, 9.5);
  run(g, C.MASTER_TIME_MS - 1000);
  assert.equal(g.phase, 'playing');
  assert.ok(g.snapshot().round.left <= 1000, '남은 시간이 스냅샷에');
  run(g, 1100);
  assert.equal(g.phase, 'over');
  assert.deepEqual(g.winnerIds.sort(), [2, 3]);
  assert.deepEqual([p(1).wins, p(2).wins, p(3).wins], [0, 1, 1]);
  assert.ok(lines.some((l) => /ROUND 1 종료 .*승자: P2 P3 =====/.test(l)));
  // 다음 판들: 마스터가 P2 → P3 → P1
  const masters = [];
  for (let r = 0; r < 3; r++) {
    startQuiet(g);
    masters.push([...g.players.values()].find((q) => q.master).id);
    g.endRound(null);
  }
  assert.deepEqual(masters, [2, 3, 1]);
});

test('블록 마스터: 마스터가 나가면 살아 있는 생존자 승', () => {
  const { g, p } = setupMode('master');
  g.removePlayer(1);
  assert.equal(g.phase, 'over');
  assert.deepEqual(g.winnerIds.sort(), [2, 3]);
  assert.equal(p(2).wins, 1);
});

test('킬 점수전: 킬 +1, 자멸 -1, 5초 뒤 피해 0% 로 부활, 부활 무적 동안 안 밀리고 안 깔림', () => {
  const { g, lines, p } = setupMode('kills', 2);
  assert.ok(lines.some((l) => l.startsWith('  모드: 킬 점수전')));
  g.nextSpawnAt = Infinity;
  // P1 이 날린 P2 가 떨어짐 → P1 +1
  p(2).damage = 80;
  p(2).lastHit = { by: 1, kind: 'push', name: 'P1' };
  fallOff(p(2));
  g.tick(TICK);
  assert.equal(p(2).alive, false);
  assert.equal(g.scores.get(1), 1);
  assert.ok(lines.includes('  [점수] P1 +1 → 1'));
  // P1 혼자 떨어짐 → P1 -1
  p(1).lastHit = null;
  fallOff(p(1));
  g.tick(TICK);
  assert.equal(g.scores.get(1), 0);
  assert.ok(lines.includes('  [점수] P1 자멸 -1 → 0'));
  assert.equal(g.phase, 'playing', '둘 다 죽어도 판은 계속');
  run(g, C.KILLS_RESPAWN_MS - 3 * TICK);
  assert.equal(p(2).alive, false, '부활 전');
  assert.ok(g.snapshot().players.find((q) => q.id === 2).respawnIn > 0);
  run(g, 4 * TICK);
  assert.equal(p(2).alive, true, '부활');
  assert.equal(p(2).damage, 0);
  assert.equal(p(2).blocks, C.BUILD_BLOCKS_PER_ROUND);
  assert.ok(lines.some((l) => l.startsWith('  [부활] P2 →')));
  // 무적: 넉백 무시, 블록이 통과
  assert.equal(g.applyKnockback(p(2), 1, 0, 5, 3, C.STUN_MS, 10, { by: 1, kind: 'push' }), false);
  const piece = g.makePiece('O', 0, Math.floor(p(2).x) - 0, Math.floor(p(2).y), Math.ceil(p(2).z) + 1);
  Object.assign(piece, { phase: 'falling', controller: null, stepMs: 30, nextStepAt: g.time, controlEndsAt: 0 });
  g.addPiece(piece, {});
  run(g, 300);
  assert.equal(p(2).alive, true, '무적이면 안 깔림');
  run(g, C.KILLS_SHIELD_MS);
  assert.equal(p(2).shieldUntil, 0, '무적 끝');
  assert.ok(!g.overlappingSolid(g.aabb(p(2))).length, '무적이 끝나면 블록 위로 밀려 올라감');
  assert.ok(g.applyKnockback(p(2), 1, 0, 5, 3, C.STUN_MS, 10, { by: 1, kind: 'push' }), '무적 끝나면 밀림');
});

test(`킬 점수전: 누가 ${C.KILLS_TARGET}킬에 닿으면 끝, 시간이 끝나면 최고 점수(동점이면 모두) 승`, () => {
  const { g, lines, p } = setupMode('kills', 3);
  g.nextSpawnAt = Infinity;
  g.scores.set(1, C.KILLS_TARGET - 1);
  p(2).lastHit = { by: 1, kind: 'push', name: 'P1' };
  fallOff(p(2));
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.deepEqual(g.winnerIds, [1]);
  assert.ok(lines.includes(`  ${C.KILLS_TARGET}킬 → 판 끝`));
  assert.ok(lines.some((l) => l === `  점수: P1 ${C.KILLS_TARGET} / P2 0 / P3 0`));
  // 다음 판: 점수 초기화, 시간 끝 동점
  startQuiet(g);
  g.nextSpawnAt = Infinity;
  assert.equal(g.scores.size, 0);
  g.scores.set(2, 2);
  g.scores.set(3, 2);
  for (const q of g.players.values()) place(q, q.x, q.y); // 바닥에 가만히
  run(g, C.KILLS_TIME_MS + TICK);
  assert.equal(g.phase, 'over');
  assert.deepEqual(g.winnerIds.sort(), [2, 3]);
  assert.ok(lines.some((l) => /ROUND 2 종료 .*승자: P2 P3 =====/.test(l)));
});

test(`킬 점수전 팀전: 팀 점수 합계, 팀 ${C.KILLS_TARGET_TEAM}킬이면 그 팀 승`, () => {
  const { g, lines, p } = setupMode('kills', 4, { start: false });
  g.setTeamMode(true);
  for (const [id, t] of [[1, 'red'], [2, 'blue'], [3, 'red'], [4, 'blue']]) g.setTeam(id, t);
  startQuiet(g);
  g.nextSpawnAt = Infinity;
  g.teamScores.red = C.KILLS_TARGET_TEAM - 1;
  p(2).lastHit = { by: 3, kind: 'push', name: 'P3' };
  fallOff(p(2));
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.equal(g.winnerTeam, 'red');
  assert.deepEqual([p(1).wins, p(2).wins, p(3).wins, p(4).wins], [1, 0, 1, 0]);
  assert.ok(lines.includes(`  팀 점수: 빨강 ${C.KILLS_TARGET_TEAM} : 0 파랑`));
});

test('킬 점수전: 용암 없음, 가장 높은 기둥이 KILLS_SINK_HEIGHT 에 닿으면 맨 아래 층을 지워 전체가 내려앉음', () => {
  const { g, lines, p } = setupMode('kills', 2);
  g.nextSpawnAt = Infinity;
  // 평균 높이를 용암 기준보다 높게 → 그래도 용암 없음 ((0,0) 은 비워 층이 꽉 차지 않게: 층 클리어 말고 가라앉기만 보려고)
  for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) for (let z = 0; z < 2; z++) if (x || y) g.grid[g.idx(x, y, z)] = 1;
  g.updateLava(TICK);
  assert.equal(g.lava.active, false);
  // (5,5) 기둥을 KILLS_SINK_HEIGHT - 1 까지, 그 위에 블록이 착지하면 한 층 지움
  for (let z = 0; z < C.KILLS_SINK_HEIGHT - 1; z++) g.grid[g.idx(5, 5, z)] = 1;
  place(p(1), 2.5, 2.5, 2); // 2층 바닥 위
  const piece = g.makePiece('O', 0, 4, 4, C.KILLS_SINK_HEIGHT - 1);
  g.addPiece(piece, { phase: 'falling', controller: null, stepMs: 1e9, nextStepAt: 1e18, controlEndsAt: 0 });
  g.landPiece(piece);
  assert.equal(g.columnTop(5, 5), C.KILLS_SINK_HEIGHT - 1, '한 칸 내려앉음');
  assert.equal(g.columnTop(2, 2), 1);
  assert.equal(p(1).z, 1, '서 있던 사람도 같이 내려감');
  assert.ok(lines.some((l) => l.startsWith('  [가라앉음]')));
});

test('블록 마스터: 죽은 생존자는 마스터 편 — 하늘에서 자기 블록을 따로, 그 블록 킬은 그 사람, 이겨도 승수는 처음 마스터만', () => {
  const { g, lines, p } = setupMode('master');
  run(g, C.FIRST_SPAWN_DELAY_MS + 100);
  // P2 를 마스터 블록 밑에, P3 는 멀리
  const cells = g.pieceWorldCells(g.controlledPiece(p(1)));
  place(p(2), cells[0][0] + 0.5, cells[0][1] + 0.5);
  place(p(3), 0.5, 9.5);
  g.handleAction(1, { name: 'drop' });
  run(g, 2000); // 하드드롭이 바닥까지 약 1.3초 + 마스터 편 첫 블록 MASTER_NEXT_PIECE_MS
  assert.equal(g.phase, 'playing');
  assert.ok(p(2).alive && p(2).master && p(2).zombie, 'P2 는 마스터 편');
  assert.ok(lines.includes('  [마스터 편] P2 → 하늘에서 블록'));
  assert.equal(g.master().id, 1, '처음 마스터는 그대로');
  const mine = g.controlledPiece(p(2));
  assert.ok(mine && g.controlledPiece(p(1)), '마스터 편 각자 블록 (동시에)');
  // P2 블록으로 P3 를 깔면 P2 의 킬, 생존자 전멸 → 처음 마스터 승
  g.movePiece(mine, -10, 10); // 왼쪽 위 구석으로
  place(p(3), g.pieceWorldCells(mine)[0][0] + 0.5, g.pieceWorldCells(mine)[0][1] + 0.5);
  g.handleAction(2, { name: 'drop' });
  run(g, 1500);
  assert.equal(g.phase, 'over');
  assert.ok(lines.some((l) => /\[사망\] P3 압사 .*킬 P2 조종블록/.test(l)));
  assert.deepEqual(g.winnerIds, [1]);
  assert.deepEqual([p(1).wins, p(2).wins, p(3).wins], [1, 0, 0]);
  assert.ok(!p(2).master && !p(2).zombie && !p(2).alive, '판이 끝나면 마스터 편은 원래대로 (죽은 상태)');
  assert.equal(g.pieces.filter((pc) => pc.phase === 'control').length, 0, '하늘의 다음 블록은 치움');
});

test(`블록 마스터: 둘레보다 ${C.MASTER_MAX_RISE}칸 넘게 튀어나오는 자리엔 못 놓음 (탑 방지)`, () => {
  const { g, p } = setupMode('master');
  run(g, C.FIRST_SPAWN_DELAY_MS + 100);
  const piece = g.controlledPiece(p(1));
  const foot = piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]);
  // 블록 발밑만 MASTER_MAX_RISE 높이 → 놓이면 둘레(0)보다 MASTER_MAX_RISE + 1 높음
  for (const [x, y] of foot) for (let z = 0; z < C.MASTER_MAX_RISE; z++) g.grid[g.idx(x, y, z)] = 1;
  g.gridChanged();
  g.updateLanding(piece);
  assert.equal(piece.fits, false, '너무 높음');
  g.handleAction(1, { name: 'drop' });
  assert.equal(piece.phase, 'control', 'Enter 를 눌러도 안 떨어짐');
  // 발밑을 한 칸 낮추면 됨
  for (const [x, y] of foot) g.grid[g.idx(x, y, C.MASTER_MAX_RISE - 1)] = 0;
  g.gridChanged();
  g.updateLanding(piece);
  assert.equal(piece.fits, true);
  // 생존 모드엔 이 제한이 없음
  const s = new Game();
  s.addPlayer(1);
  s.addPlayer(2);
  s.startRound();
  for (let z = 0; z < 8; z++) s.grid[s.idx(5, 5, z)] = 1;
  const pc = s.makePiece('O', 0, 4, 4, C.CONTROL_HOVER_Z);
  s.addPiece(pc, { phase: 'control', controller: 1, stepMs: 80, nextStepAt: 0, controlEndsAt: 1e9 });
  s.updateLanding(pc);
  assert.equal(pc.fits, true);
});

test('블록 마스터: 마스터 편 블록은 무작위 자리에서 시작', () => {
  const { g, p } = setupMode('master');
  const at = (r) => {
    g.rng = () => r;
    const pc = g.spawnControlled(p(2), true);
    g.removePiece(pc);
    return [pc.px, pc.py, footprint(pc.cells)];
  };
  const [x0, y0] = at(0);
  const [x1, y1, f] = at(0.999);
  assert.deepEqual([x0, y0], [0, 0]);
  assert.deepEqual([x1, y1], [C.GRID_W - f.w, C.GRID_D - f.d]);
});
