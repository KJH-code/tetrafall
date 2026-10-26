// 연습 모드 (2026-10-26 재혁): 혼자 쓰는 방, 판이 안 끝남, 토글, 허수아비 (콤보 기록), 판 중 캐릭터 바꾸기
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;

function fakeWs() {
  return {
    OPEN: 1,
    readyState: 1,
    msgs: [],
    send(text) {
      this.msgs.push(JSON.parse(text));
    },
    last(type) {
      return [...this.msgs].reverse().find((m) => m.type === type);
    },
  };
}

function setup() {
  const logs = {};
  const server = [];
  let s = 1;
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(m), close() {} };
    },
    serverLog: (m) => server.push(m),
    rng: () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    },
  });
  const join = () => {
    const ws = fakeWs();
    return { ws, conn: rooms.connect(ws) };
  };
  const a = join();
  rooms.message(a.conn, { type: 'practice', nick: '재혁', char: 'ninja' });
  const room = a.conn.room;
  const g = room.game;
  const me = g.players.get(a.conn.id);
  const run = (ms) => {
    for (let t = 0; t < ms; t += TICK) rooms.tick(TICK);
  };
  return { rooms, logs, server, join, a, room, g, me, run, dummy: () => g.dummies()[0] };
}

test('연습 방: 바로 시작 (혼자, 카운트다운 없음), 허수아비 1개, 비공개·목록에 안 뜸·공개 못 함, 로그 파일 없음', () => {
  const { rooms, logs, server, a, room, g, me, dummy } = setup();
  assert.ok(room.practice);
  assert.equal(a.ws.last('welcome').room.practice, true);
  assert.equal(g.mode, 'practice');
  assert.equal(g.phase, 'playing');
  assert.equal(me.char, 'ninja');
  assert.equal(me.nick, '재혁');
  assert.ok(me.alive);
  assert.equal(g.dummies().length, 1);
  assert.equal(dummy().dummy, true);
  assert.equal(dummy().char, null);
  assert.equal(g.humanCount(), 1, '허수아비는 사람 수에 안 셈');
  rooms.message(a.conn, { type: 'setPublic', on: true });
  assert.equal(room.public, false);
  assert.equal(rooms.publicList().rooms.length, 0);
  assert.deepEqual(Object.keys(logs), [], '방 로그 파일을 안 엶');
  assert.ok(server.some((l) => l.includes('연습')));
  const snap = g.snapshot();
  assert.deepEqual({ ...snap.practice, dummies: undefined }, { noCooldown: false, fullUlt: false, noBlocks: true, noDeath: true, dummies: undefined });
  assert.equal(snap.players.find((p) => p.dummy).id, dummy().id);
});

test('연습 방: 판이 안 끝나고 (허수아비만 남아도), 블록·용암 없음 기본, 친구는 같은 코드로 들어와 바로 연습, 사람이 다 나가면 닫힘', () => {
  const { rooms, join, a, room, g, run } = setup();
  run(20000);
  assert.equal(g.phase, 'playing');
  assert.equal(g.pieces.length, 0, '블록 안 떨어짐');
  assert.equal(g.lava.active, false);
  const b = join();
  rooms.message(b.conn, { type: 'join', code: room.code });
  const friend = g.players.get(b.conn.id);
  assert.ok(friend.alive && !friend.spectator, '친구는 관전 말고 바로');
  rooms.message(a.conn, { type: 'leave' });
  rooms.message(b.conn, { type: 'leave' });
  assert.equal(rooms.rooms.has(room.code), false);
});

test('연습 토글: 블록 켜기·끄기, F 쿨 없음, R 게이지 가득, 안 죽음 (떨어지면 바로 처음 자리, 피해 % 는 내 설정값) · 끄면 죽고 잠깐 뒤 되살아남', () => {
  const { rooms, a, g, me, run } = setup();
  const set = (key, value) => rooms.message(a.conn, { type: 'practiceSet', key, value });
  set('noBlocks', false);
  run(C.FIRST_SPAWN_DELAY_MS + 500);
  assert.ok(g.pieces.length > 0, '블록이 떨어짐');
  set('noBlocks', true);
  assert.equal(g.pieces.length, 0, '켜면 떨어지던 블록 치움');
  // F 쿨 없음
  Object.assign(me, { x: 2.5, y: 2.5, yaw: 0, grounded: true, vz: 0 });
  set('noCooldown', true);
  rooms.message(a.conn, { type: 'action', name: 'skill' });
  run(500);
  assert.ok(me.skillReadyAt <= g.time, 'F 쿨 없음');
  // R 가득
  set('fullUlt', true);
  run(TICK * 2);
  assert.equal(me.ult, g.ultMax(me));
  // 안 죽음 + 내 피해 %
  set('myDamage', 120);
  assert.equal(me.damage, 120);
  const home = { ...me.home };
  Object.assign(me, { x: -3, y: 4, z: C.FALL_DEATH_Z - 1 });
  run(TICK * 2);
  assert.ok(me.alive);
  assert.deepEqual([me.x, me.y], [home.x, home.y], '처음 자리');
  assert.equal(me.damage, 120, '되살아나도 내 설정값');
  assert.equal(g.deaths.length, 0, '죽음 기록 없음');
  // 끄면 죽고 잠깐 뒤
  set('noDeath', false);
  Object.assign(me, { x: -3, y: 4, z: C.FALL_DEATH_Z - 1 });
  run(TICK * 2);
  assert.equal(me.alive, false);
  run(C.PRACTICE_RESPAWN_MS + TICK * 2);
  assert.ok(me.alive, '잠깐 뒤 되살아남');
  assert.equal(g.phase, 'playing');
  // 잘못된 값은 무시
  set('noCooldown', 'yes');
  assert.equal(g.practice.noCooldown, true);
  set('myDamage', 'abc');
  assert.equal(me.damage, 120);
  set('myDamage', 5000);
  assert.equal(me.damage, C.PRACTICE_DAMAGE_MAX);
});

test('허수아비: 추가(내 앞, 최대 PRACTICE_DUMMY_MAX)·삭제·피해 % 설정, 떨어지면 원래 자리에 설정 % 로', () => {
  const { rooms, a, g, me } = setup();
  Object.assign(me, { x: 3, y: 5, yaw: 0 });
  rooms.message(a.conn, { type: 'dummyAdd' });
  const d2 = g.dummies()[1];
  assert.ok(Math.abs(d2.x - (3 + C.PRACTICE_DUMMY_DIST)) < 1e-9 && d2.y === 5, '내 앞');
  for (let k = 0; k < 5; k++) rooms.message(a.conn, { type: 'dummyAdd' });
  assert.equal(g.dummies().length, C.PRACTICE_DUMMY_MAX);
  rooms.message(a.conn, { type: 'dummyRemove' });
  assert.equal(g.dummies().length, C.PRACTICE_DUMMY_MAX - 1, '마지막 것');
  rooms.message(a.conn, { type: 'dummyRemove', id: d2.id });
  assert.ok(!g.players.has(d2.id));
  assert.equal(g.deaths.length, 0);
  const d = g.dummies()[0];
  rooms.message(a.conn, { type: 'dummySet', id: d.id, damage: 150 });
  assert.equal(d.damage, 150);
  assert.equal(g.snapshot().practice.dummies[0].damageSet, 150);
  const home = { ...d.home };
  Object.assign(d, { x: -3, z: C.FALL_DEATH_Z - 1, damage: 40 });
  rooms.tick(TICK);
  assert.ok(d.alive);
  assert.deepEqual([d.x, d.y, d.damage], [home.x, home.y, 150]);
  assert.ok(g.drainEvents().some((e) => e.type === 'practiceReset' && e.who === d.id && e.cause === 'fall'));
});

test('허수아비 콤보 기록: 맞을 때마다 dummyCombo (타 수·피해·날아간 거리·높이), 콤보가 끝나고 땅에 닿으면 done + 피해 % 는 설정값으로', () => {
  const { rooms, a, g, me, run, dummy } = setup();
  const d = dummy();
  Object.assign(me, { x: d.x - 1.2, y: d.y, z: 0, yaw: 0, grounded: true });
  rooms.message(a.conn, { type: 'dummySet', damage: 30 });
  g.drainEvents();
  // 평타 1타 → 2타
  rooms.message(a.conn, { type: 'action', name: 'push' });
  let first = null;
  for (let t = 0; t < 400 && !first; t += TICK) {
    rooms.tick(TICK);
    first = g.events.find((e) => e.type === 'dummyCombo');
  }
  assert.ok(first && first.hits === 1 && !first.done);
  assert.equal(d.damage, 30 + first.damage, '콤보 중엔 피해 % 가 쌓임');
  run(200);
  Object.assign(me, { x: d.x - 1.2, y: d.y });
  rooms.message(a.conn, { type: 'action', name: 'push' });
  run(400);
  const ev = g.drainEvents().filter((e) => e.type === 'dummyCombo');
  assert.ok(ev.length >= 2, `맞을 때마다 ${ev.length}`);
  const last = ev.filter((e) => !e.done).at(-1);
  assert.ok(last.hits >= 2 && last.damage > 0, JSON.stringify(last));
  run(3000);
  const done = [...ev, ...g.drainEvents()].find((e) => e.type === 'dummyCombo' && e.done);
  assert.ok(done, '끝');
  assert.equal(done.hits, last.hits);
  assert.ok(done.dist > 0);
  assert.equal(d.damage, 30, '설정값으로');
  assert.deepEqual(g.snapshot().practice.dummies[0].last, { hits: done.hits, damage: done.damage, dist: done.dist, height: done.height });
});

test('연습: 판 중 캐릭터 바꾸기 (상태 새로, 위치·피해 % 그대로) · 보통 방은 판 중에 못 바꿈', () => {
  const { rooms, a, g, me } = setup();
  Object.assign(me, { x: 4.2, y: 3.3, damage: 77, skillReadyAt: g.time + 5000 });
  rooms.message(a.conn, { type: 'setChar', char: 'cannon' });
  assert.equal(me.char, 'cannon');
  assert.deepEqual([me.x, me.y, me.damage], [4.2, 3.3, 77]);
  assert.equal(me.skillReadyAt, 0, '쿨 새로');
  assert.equal(me.cannonAmmo, C.CANNON_AMMO_MAX);
  assert.ok(g.drainEvents().some((e) => e.type === 'charChange' && e.who === me.id && e.char === 'cannon'));
  // 보통 방
  const b = { ws: fakeWs() };
  b.conn = rooms.connect(b.ws);
  rooms.message(b.conn, { type: 'create', name: 'x' });
  const c = { ws: fakeWs() };
  c.conn = rooms.connect(c.ws);
  rooms.message(c.conn, { type: 'join', code: b.conn.room.code });
  const ng = b.conn.room.game;
  ng.countdownMs = 0;
  rooms.message(b.conn, { type: 'start' });
  assert.equal(ng.phase, 'playing');
  rooms.message(b.conn, { type: 'setChar', char: 'cannon' });
  assert.notEqual(ng.players.get(b.conn.id).char, 'cannon');
});

test('연습: 판 중 맵 바꾸기 — 지형 바로 바꾸고 블록·아이템 치우고 모두 제자리 (지형 위), 누구나', () => {
  const { rooms, join, a, room, g, me, dummy } = setup();
  assert.equal(g.mapId, 'flat');
  const b = join();
  rooms.message(b.conn, { type: 'join', code: room.code });
  rooms.message(b.conn, { type: 'setMap', map: 'pyramid' }); // 호스트 아님
  assert.equal(g.mapId, 'pyramid');
  assert.equal(g.phase, 'playing');
  assert.ok(g.grid.some((v) => v === 1), '지형 생김');
  assert.ok(g.drainEvents().some((e) => e.type === 'mapChange' && e.map === 'pyramid'));
  const d = dummy();
  assert.equal(d.z, g.spawnZ(d.x, d.y), '허수아비는 지형 위');
  assert.equal(me.z, g.spawnZ(me.x, me.y));
  rooms.message(a.conn, { type: 'setMap', map: 'nope' });
  assert.equal(g.mapId, 'pyramid', '없는 맵은 무시');
  rooms.message(a.conn, { type: 'setMap', map: 'flat' });
  assert.ok(g.grid.every((v) => v === 0), '평지로');
});
