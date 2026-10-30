// 블록 마스터 밸런스·킬 점수전 목표 (2026-10-30 재혁): 인원별 마스터 블록 하드드롭 빠르기, 생존자 반격 아이템 (봇도 먹음), 인원별·체력전별 목표 킬
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { BotBrain } from '../server/bot.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;
const run = (g, ms) => {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
};

function master(n) {
  const g = new Game(() => {}, { countdownMs: 0 });
  g.rng = () => 0.5;
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  g.setMode('master');
  g.startRound();
  return g;
}

test('마스터 블록 하드드롭 빠르기: 인원별 표 (2~8인), 마스터 편만 (다른 조종 블록은 HARD_DROP_STEP_MS)', () => {
  assert.deepEqual(C.MASTER_DROP_STEP_BY_COUNT, { 2: 42, 3: 75, 4: 70, 5: 65, 6: 60, 7: 60, 8: 55 });
  for (const n of [2, 4, 8]) {
    const g = master(n);
    run(g, C.FIRST_SPAWN_DELAY_MS + C.MASTER_NEXT_PIECE_MS + 2 * TICK);
    const m = g.master();
    const piece = g.controlledPiece(m);
    assert.ok(piece, `${n}인 마스터 블록`);
    g.handleAction(m.id, { name: 'drop' });
    assert.equal(piece.stepMs, C.MASTER_DROP_STEP_BY_COUNT[n], `${n}인`);
  }
  // 생존 모드 조종 블록은 예전 그대로
  const g = new Game(() => {}, { countdownMs: 0 });
  g.rng = () => 0.5;
  for (const id of [1, 2]) g.addPlayer(id);
  g.startRound();
  const p = g.players.get(1);
  const piece = g.spawnControlled(p);
  g.dropPiece(piece);
  assert.equal(piece.stepMs, C.HARD_DROP_STEP_MS);
});

test('반격 아이템: 블록 마스터 판에만 MASTER_COUNTER_FIRST_MS 뒤 하나 생김, 생존자가 먹으면 마스터 편 다음 블록이 MASTER_COUNTER_STALL_MS 멈춤 (masterStall 이벤트)', () => {
  const g = master(3);
  run(g, C.MASTER_COUNTER_FIRST_MS - 500);
  assert.ok(!g.items.some((it) => it.type === 'counter'), '아직');
  run(g, 600);
  const item = g.items.find((it) => it.type === 'counter');
  assert.ok(item, '생김');
  assert.equal(g.items.filter((it) => it.type === 'counter').length, 1);
  // 생존자를 그 자리에 세움
  const m = g.master();
  const s = [...g.players.values()].find((p) => !p.master && p.alive);
  Object.assign(s, { x: item.x + 0.5, y: item.y + 0.5, z: g.columnTop(item.x, item.y), vz: 0, kbx: 0, kby: 0 });
  g.drainEvents();
  g.pickupItems();
  const ev = g.drainEvents().find((e) => e.type === 'masterStall');
  assert.ok(ev, 'masterStall 이벤트');
  assert.equal(ev.who, s.id);
  assert.equal(ev.ms, C.MASTER_COUNTER_STALL_MS);
  assert.equal(g.masterStallUntil, g.time + C.MASTER_COUNTER_STALL_MS);
  // 들고 있던 블록을 떨어뜨리면 멈춤 동안 새 블록 없음, 끝나면 다시
  const held = g.controlledPiece(m);
  if (held) g.handleAction(m.id, { name: 'drop' });
  run(g, C.MASTER_COUNTER_STALL_MS - 500);
  assert.equal(g.controlledPiece(m), null, '멈춤 중엔 새 블록 없음');
  run(g, 1000);
  assert.ok(g.controlledPiece(m), '멈춤 끝나면 다시');
  // 겹쳐 먹으면 이어 붙음
  const t0 = g.time;
  g.givePower(s, 'counter');
  g.givePower(s, 'counter');
  assert.equal(g.masterStallUntil, t0 + 2 * C.MASTER_COUNTER_STALL_MS);
});

test('반격 아이템은 블록 마스터 판에만 (생존·킬 점수전엔 안 생김)', () => {
  for (const mode of ['survival', 'kills']) {
    const g = new Game(() => {}, { countdownMs: 0 });
    g.rng = () => 0.5;
    for (const id of [1, 2, 3]) g.addPlayer(id);
    if (mode !== 'survival') g.setMode(mode);
    g.startRound();
    g.nextSpawnAt = Infinity;
    for (const p of g.players.values()) p.z = 0;
    run(g, C.MASTER_COUNTER_FIRST_MS + 2000);
    assert.ok(!g.items.some((it) => it.type === 'counter'), mode);
  }
});

test('봇: 반격 아이템은 상대보다 멀어도 먹으러 감 (다른 아이템은 상대보다 가까울 때만)', () => {
  const g = master(3);
  const bot = new BotBrain(() => 0.5);
  const s = [...g.players.values()].find((p) => !p.master);
  Object.assign(s, { x: 2.5, y: 2.5, z: 0 });
  const target = { x: 8.5, y: 2.5, z: 0 };
  g.items = [{ type: 'counter', x: 6, y: 2, z: 0 }]; // 나 3.5칸, 상대 2칸
  assert.equal(bot.pickItem(g, s, target)?.type, 'counter');
  g.items = [{ type: 'jump', x: 6, y: 2, z: 0 }];
  assert.equal(bot.pickItem(g, s, target), null, '다른 아이템은 예전대로');
});

test('킬 점수전 목표 킬: 인원별·팀전·체력전 표에서 판 시작 때 하나 → 스냅샷 round.killsTarget·로그 모드 줄', () => {
  const cases = [
    [2, false, false, C.KILLS_TARGET_BY_COUNT.off[2]],
    [4, false, false, C.KILLS_TARGET_BY_COUNT.off[3]],
    [8, false, true, C.KILLS_TARGET_BY_COUNT.hp[8]],
    [5, false, true, C.KILLS_TARGET_BY_COUNT.hp[5]],
    [7, false, true, C.KILLS_TARGET_BY_COUNT.hp[6]], // 7 칸 없음 → 6 칸
    [4, true, false, C.KILLS_TARGET_TEAM_BY_COUNT.off[2]],
    [8, true, true, C.KILLS_TARGET_TEAM_BY_COUNT.hp[8]],
  ];
  for (const [n, team, hp, want] of cases) {
    const lines = [];
    const g = new Game((l) => lines.push(l), { countdownMs: 0, hpMode: hp });
    g.rng = () => 0.5;
    for (let i = 1; i <= n; i++) g.addPlayer(i);
    if (team) g.setTeamMode(true);
    g.setMode('kills');
    g.startRound();
    assert.equal(g.killsTarget, want, `${n}인 팀${team} 체력${hp}`);
    assert.equal(g.snapshot().round.killsTarget, want);
    assert.ok(lines.some((l) => l.includes(`또는 ${team ? `팀 ${want}` : want}킬)`)), lines.find((l) => l.includes('모드')));
  }
  // 다른 모드 스냅샷엔 없음 (예전과 같게)
  const g = master(3);
  assert.equal(JSON.parse(JSON.stringify(g.snapshot())).round.killsTarget, undefined);
});
