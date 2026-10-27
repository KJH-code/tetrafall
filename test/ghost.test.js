// 유령 투하 (2026-10-26 재혁): 먼저 죽은 사람이 하늘에서 1칸 블록을 떨어뜨림 (생존 모드)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;
function run(g, ms) {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
}

// 사람 3명 (P1 죽음, P2·P3 살아 있음), 블록·아이템 없이
function setup({ sky = false, mode = null, team = false } = {}) {
  const lines = [];
  const g = new Game((s) => lines.push(s), { skyStairs: sky });
  g.rng = () => 0.5;
  for (let i = 1; i <= 3; i++) g.addPlayer(i);
  if (mode) g.setMode(mode);
  if (team) {
    g.setTeamMode(true);
    g.setTeam(1, 'red');
    g.setTeam(2, 'red');
    g.setTeam(3, 'blue');
  }
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  const p = (id) => g.players.get(id);
  Object.assign(p(2), { x: 2.5, y: 2.5 });
  Object.assign(p(3), { x: 7.5, y: 7.5 });
  return { g, lines, p };
}

test('유령 투하: 수치·기본값 (사람만, 봇은 꺼 둠)', () => {
  assert.equal(C.GHOST_DROP_ENABLED, true);
  assert.equal(C.GHOST_DROP_CD_MS, 6000);
  assert.equal(C.GHOST_DROP_BOTS, false);
  assert.equal(C.GHOST_DROP_UP_SKY, 2);
});

test('유령 투하: 죽자마자 1개, 그 뒤 GHOST_DROP_CD_MS 쿨. 살아 있으면·필드 밖·같은 기둥 블록이면 거절, snapshot ghostCd', () => {
  const { g, lines, p } = setup();
  const cd = () => g.snapshot().players.find((q) => q.id === 1).ghostCd;
  assert.equal(cd(), null, '살아 있으면 null');
  g.drainEvents();
  assert.equal(g.ghostDrop(1, 5, 5), null);
  assert.ok(g.drainEvents().some((e) => e.type === 'ghostDropFail' && e.who === 1 && e.reason === 'notDead'));
  g.kill(p(1), 'fall');
  assert.equal(cd(), 0, '죽자마자 바로');
  const pc = g.ghostDrop(1, 5, 5);
  assert.ok(pc && pc.ghostBy === 1 && pc.cells.length === 1);
  assert.equal(pc.pz, C.GHOST_DROP_UP, '기둥 꼭대기(0) + UP');
  assert.ok(g.drainEvents().some((e) => e.type === 'ghostDrop' && e.who === 1 && e.x === 5 && e.y === 5 && e.slot === p(1).slot));
  assert.ok(lines.includes('  [유령] P1 → (5,5) 투하'));
  assert.equal(cd(), C.GHOST_DROP_CD_MS);
  const fails = (x, y) => (g.ghostDrop(1, x, y), g.drainEvents().find((e) => e.type === 'ghostDropFail').reason);
  assert.equal(fails(6, 6), 'cooldown');
  run(g, C.GHOST_DROP_CD_MS);
  assert.equal(fails(-1, 3), 'outside');
  g.piece = null;
  g.pieces = [Object.assign(g.makePiece('I', 0, 0, 0, 10), { id: 99, phase: 'falling', controller: null, stepMs: 1e9, nextStepAt: Infinity })];
  g.refreshPieceCells();
  assert.equal(fails(2, 0), 'busy', '같은 기둥에 떨어지는 블록');
  assert.ok(g.ghostDrop(1, 8, 2), '쿨 끝 → 다시');
});

test('유령 투하: 그 판 보통 블록 속도로 떨어져 착지하면 GHOST_BASE + 색 번호 값으로 남음 (하늘 계단 켬이면 그 속도)', () => {
  for (const sky of [false, true]) {
    const { g, p } = setup({ sky });
    g.kill(p(1), 'fall');
    const pc = g.ghostDrop(1, 5, 5);
    assert.equal(pc.stepMs, sky ? C.SKY_FALL_STEP_MS : g.autoFallStepMs());
    assert.equal(pc.pz, sky ? C.GHOST_DROP_UP_SKY : C.GHOST_DROP_UP, '켬 판은 낮게 (GHOST_DROP_UP_SKY 2)');
    assert.equal(g.snapshot().pieces.find((x) => x.id === pc.id).ghostSlot, p(1).slot);
    assert.equal(g.snapshot().pieces.find((x) => x.id === pc.id).ghostColor, p(1).color);
    run(g, pc.stepMs * (pc.pz + 1) + TICK);
    assert.ok(!g.pieces.includes(pc), '착지');
    assert.equal(g.gridAt(5, 5, 0), CELL.GHOST_BASE + p(1).color, '떨어뜨린 사람 색 (PLAYER_PALETTE 번호)');
    assert.equal(g.landed.ghost, 1);
  }
});

test('유령 투하: 깔리면 압사 + 킬은 떨어뜨린 사람 (무기 유령블록). 팀전에서 같은 팀이 깔리면 킬 없음', () => {
  let { g, lines, p } = setup();
  g.kill(p(1), 'fall');
  Object.assign(p(2), { x: 5.5, y: 5.5, z: 0 });
  const pc = g.ghostDrop(1, 5, 5);
  run(g, pc.stepMs * C.GHOST_DROP_UP + TICK);
  assert.equal(p(2).alive, false);
  const d = g.deaths.find((x) => x.name === 'P2');
  assert.deepEqual([d.cause, d.killer, d.weapon], ['crush', 'P1', 'ghost']);
  assert.ok(lines.some((l) => l.startsWith('  [사망] P2 압사') && l.includes('킬 P1 유령블록')));
  // 팀전: P1·P2 빨강
  ({ g, p } = setup({ team: true }));
  g.kill(p(1), 'fall');
  Object.assign(p(2), { x: 5.5, y: 5.5, z: 0 });
  const pc2 = g.ghostDrop(1, 5, 5);
  run(g, pc2.stepMs * C.GHOST_DROP_UP + TICK);
  assert.equal(p(2).alive, false, '같은 팀도 깔림');
  assert.equal(g.deaths.find((x) => x.name === 'P2').killer, null, '같은 팀은 킬 없음');
});

test('유령 투하: 킬 점수전·블록 마스터·연습 모드·관전자는 안 됨 (ghostCd null)', () => {
  for (const mode of ['kills', 'master']) {
    const { g, p } = setup({ mode });
    g.kill(p(2), 'fall');
    assert.equal(g.ghostCd(p(2)), null, mode);
    g.drainEvents();
    assert.equal(g.ghostDrop(2, 5, 5), null);
    assert.ok(g.drainEvents().some((e) => e.type === 'ghostDropFail' && e.reason === 'mode'));
  }
  const q = new Game(() => {}, { characters: true });
  q.addPlayer(1);
  q.startPractice();
  assert.equal(q.ghostCd(q.players.get(1)), null, '연습');
  const { g, p } = setup();
  p(1).spectator = true;
  p(1).alive = false;
  assert.equal(g.ghostCd(p(1)), null, '관전자');
});

test('유령 투하: 죽은 봇은 기본 안 함, GHOST_DROP_BOTS 켜면 쿨마다 살아 있는 상대 쪽에 떨어뜨림', () => {
  const mk = () => {
    const g = new Game(() => {});
    g.rng = () => 0.5;
    g.addPlayer(1);
    g.addBot();
    g.addBot();
    g.startRound();
    g.nextSpawnAt = Infinity;
    g.powerItemNextAt = Infinity;
    const bot = [...g.players.values()].find((x) => x.isBot);
    g.kill(bot, 'fall');
    return { g, bot };
  };
  let { g, bot } = mk();
  assert.equal(g.ghostCd(bot), null);
  run(g, 1000);
  assert.ok(!g.pieces.some((pc) => pc.ghostBy === bot.id));
  C.GHOST_DROP_BOTS = true;
  try {
    ({ g, bot } = mk());
    run(g, 200);
    assert.ok(g.pieces.some((pc) => pc.ghostBy === bot.id), '켜면 떨어뜨림');
  } finally {
    C.GHOST_DROP_BOTS = false;
  }
});
