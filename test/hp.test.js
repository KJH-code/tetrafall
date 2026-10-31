// 체력전 (2026-10-30 재혁 '체력전을 모디파이어/설정으로'): 대기실 옵션 hpMode. HP = HP_MAX − 피해 %, 0 이하면 그 자리에서 KO (원인 '체력', 막타 킬).
// 끄면 예전 그대로 (스냅샷에 hp 칸도 없음 → tools/game-hash.js 해시 같음)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { parseLog, summarize, formatReport } from '../tools/stats.js';

const TICK = 1000 / C.TICK_RATE;

function setup({ hp = true, mode = 'survival', n = 3 } = {}) {
  const lines = [];
  const g = new Game((m) => lines.push(m), { hpMode: hp });
  g.rng = () => 0.5;
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  if (mode !== 'survival') g.setMode(mode);
  assert.ok(g.startRound());
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return { g, lines, p: (id) => g.players.get(id) };
}

// a 가 b 를 피해 gain 만큼 때림 (넉백은 0 → 제자리). 앞 타의 콤보 끝 무적이 풀릴 때까지 틱을 돌린 뒤
const hit = (g, a, b, gain) => {
  const t = g.players.get(b);
  for (let k = 0; k < 100 && g.invulnerable(t); k++) g.tick(TICK);
  assert.ok(g.applyKnockback(t, 1, 0, 0, 0, 0, gain, { by: a, kind: 'push' }, true), '맞음');
};

test('체력전 끔 (기본): 피해 % 가 HP 최대를 넘어도 안 죽고, 스냅샷에 hp 칸이 없음', () => {
  const { g, p } = setup({ hp: false });
  assert.equal(g.hpMode, false);
  hit(g, 1, 2, C.HP_MAX_BY_MODE.survival + 50);
  g.tick(TICK);
  assert.ok(p(2).alive);
  const s = g.snapshot();
  assert.ok(!('hpMode' in JSON.parse(JSON.stringify(s))));
  assert.equal(JSON.parse(JSON.stringify(s)).players[1].hp, undefined);
});

test('체력전 켬 (생존): HP = HP_MAX_BY_MODE.survival − 피해 %, 0 이하면 그 자리에서 KO (원인 체력, 막타 친 사람 킬), 로그·이벤트', () => {
  const max = C.HP_MAX_BY_MODE.survival;
  const { g, lines, p } = setup();
  assert.ok(lines.includes(`  체력전: 켬 (HP ${max})`));
  hit(g, 1, 2, 70);
  const s = g.snapshot();
  assert.equal(s.hpMode, true);
  assert.equal(s.hpMax, max);
  assert.equal(s.players.find((x) => x.id === 2).hp, max - 70);
  g.tick(TICK);
  assert.ok(p(2).alive);
  hit(g, 3, 2, max - 71); // HP 1
  g.tick(TICK);
  assert.ok(p(2).alive, 'HP 1 은 살아 있음');
  hit(g, 1, 2, 1); // HP 0
  const { x, y, z } = p(2);
  g.drainEvents();
  g.tick(TICK);
  assert.equal(p(2).alive, false);
  assert.equal(p(2).deathCause, 'hp');
  assert.deepEqual([p(2).x, p(2).y, p(2).z], [x, y, z], '그 자리');
  const death = g.drainEvents().find((e) => e.type === 'death');
  assert.equal(death.cause, 'hp');
  assert.equal(death.by, 1, '막타 친 사람');
  assert.ok(lines.some((l) => /^ {2}\[사망\] P2 체력 @ .*킬 P1 밀치기/.test(l)), lines.filter((l) => l.includes('[사망]')).join('\n'));
});

test('체력전 킬 점수전: 체력 KO 도 킬 +1, 부활하면 HP 꽉 참', () => {
  const { g, p } = setup({ mode: 'kills' });
  assert.equal(g.snapshot().hpMax, C.HP_MAX_BY_MODE.kills);
  hit(g, 1, 2, C.HP_MAX_BY_MODE.kills);
  g.tick(TICK);
  assert.equal(p(2).alive, false);
  assert.equal(g.scores.get(1), 1);
  for (let t = 0; t < C.KILLS_RESPAWN_MS + 500; t += TICK) g.tick(TICK);
  assert.ok(p(2).alive, '부활');
  assert.equal(g.snapshot().players.find((x) => x.id === 2).hp, C.HP_MAX_BY_MODE.kills);
});

test('체력전 블록 마스터: 생존자만 (마스터는 필드 밖), 체력 KO 된 생존자는 마스터 편으로', () => {
  const { g, p } = setup({ mode: 'master' });
  const m = g.master();
  const survivor = [1, 2, 3].find((id) => id !== m.id);
  m.damage = 999;
  g.tick(TICK);
  assert.ok(m.alive && m.master, '마스터는 안 죽음');
  const other = [1, 2, 3].find((id) => id !== m.id && id !== survivor);
  hit(g, other, survivor, C.HP_MAX_BY_MODE.master);
  g.tick(TICK);
  assert.ok(g.deaths.some((d) => d.name === p(survivor).name && d.cause === 'hp'), '체력 사망 기록');
  assert.ok(p(survivor).master || g.phase === 'over', '마스터 편 합류 (또는 판 끝)');
});

test('체력전 옵션: 판 사이에만 바뀜, 연습 방은 늘 끔', () => {
  const g = new Game(() => {});
  g.addPlayer(1);
  g.addPlayer(2);
  assert.equal(g.setHpMode(true), true);
  assert.equal(g.setHpMode(true), false, '같은 값');
  g.startRound();
  assert.equal(g.setHpMode(false), false, '판 중엔 안 됨');
  const pr = new Game(() => {}, { hpMode: true });
  pr.addPlayer(1);
  pr.startPractice();
  assert.equal(pr.hpMode, false);
  assert.equal(pr.setHpMode(true), false);
});

test('방: 호스트만 체력전을 켬, 공개 목록에 보임', () => {
  const rooms = new Rooms({});
  const ws = () => ({ OPEN: 1, readyState: 1, msgs: [], send(t) { this.msgs.push(JSON.parse(t)); } });
  const a = { ws: ws() };
  a.conn = rooms.connect(a.ws);
  rooms.message(a.conn, { type: 'create' });
  const room = a.conn.room;
  const b = { ws: ws() };
  b.conn = rooms.connect(b.ws);
  rooms.message(b.conn, { type: 'join', code: room.code });
  rooms.message(b.conn, { type: 'hpMode', on: true });
  assert.equal(room.game.hpMode, false, '호스트 아님');
  rooms.message(a.conn, { type: 'hpMode', on: true });
  assert.equal(room.game.hpMode, true);
  rooms.message(a.conn, { type: 'setPublic', on: true });
  assert.equal(rooms.publicList().rooms[0].hpMode, true);
});

test('npm run stats: 체력 사망·체력전별 표', () => {
  const { g, lines } = setup();
  hit(g, 1, 2, C.HP_MAX_BY_MODE.survival);
  g.tick(TICK);
  hit(g, 1, 3, C.HP_MAX_BY_MODE.survival);
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  const rounds = parseLog(lines.join('\n'));
  assert.equal(rounds[0].hp, true);
  const s = summarize(rounds);
  assert.equal(s.byCause.hp, 2);
  const rep = formatReport(s);
  assert.match(rep, /체력 2 \(100%\)/);
  assert.match(rep, /== 체력전별 ==/);
});

test('체력전 캐릭터별 HP: 모드 값 × HP_CHAR_MULT (반올림), 사람마다 스냅샷 hpMax, 맨 위 hpMax 는 모드 값 그대로', () => {
  for (const mode of ['survival', 'kills', 'master']) {
    const g = new Game(() => {}, { hpMode: true, characters: true });
    g.rng = () => 0.5;
    C.CHARACTERS.forEach((c, i) => {
      g.addPlayer(i + 1);
      g.setChar(i + 1, c);
    });
    if (mode !== 'survival') g.setMode(mode);
    assert.ok(g.startRound());
    const base = C.HP_MAX_BY_MODE[mode];
    const s = JSON.parse(JSON.stringify(g.snapshot()));
    assert.equal(s.hpMax, base, '맨 위는 모드 값 (예전 화면 호환)');
    for (const sp of s.players) {
      const want = Math.round(base * C.HP_CHAR_MULT[sp.char]);
      assert.equal(sp.hpMax, want, `${mode} ${sp.char}`);
      assert.equal(sp.hp, want);
    }
  }
  assert.equal(Math.round(C.HP_MAX_BY_MODE.survival * C.HP_CHAR_MULT.tank), new Game(() => {}, { hpMode: true, characters: true }).hpMax({ char: 'tank' }));
  for (const c of C.CHARACTERS) assert.ok(C.HP_CHAR_MULT[c] > 0, `${c} 배율`);
});

test('체력전 캐릭터별 HP: KO 문턱이 사람마다 (높은 배율은 더 버팀), 캐릭터 끄면 모두 모드 값', () => {
  const g = new Game(() => {}, { hpMode: true, characters: true });
  g.rng = () => 0.5;
  const hi = C.CHARACTERS.reduce((a, b) => (C.HP_CHAR_MULT[a] >= C.HP_CHAR_MULT[b] ? a : b));
  const lo = C.CHARACTERS.reduce((a, b) => (C.HP_CHAR_MULT[a] <= C.HP_CHAR_MULT[b] ? a : b));
  [hi, lo, 'builder'].forEach((c, i) => {
    g.addPlayer(i + 1);
    g.setChar(i + 1, c);
  });
  assert.ok(g.startRound());
  g.nextSpawnAt = Infinity;
  const [a, b] = [g.players.get(1), g.players.get(2)];
  const loMax = g.hpMax(b);
  assert.ok(g.hpMax(a) > loMax);
  a.damage = loMax;
  b.damage = loMax - 1;
  g.tick(TICK);
  assert.ok(a.alive && b.alive, '높은 배율은 낮은 쪽 최대에서도 삶');
  b.damage = loMax;
  g.tick(TICK);
  assert.equal(b.alive, false);
  assert.equal(b.deathCause, 'hp');
  const off = new Game(() => {}, { hpMode: true });
  off.addPlayer(1);
  off.players.get(1).char = 'tank';
  assert.equal(off.hpMax(off.players.get(1)), C.HP_MAX_BY_MODE.survival, '캐릭터 끔 → 배율 없음');
});
