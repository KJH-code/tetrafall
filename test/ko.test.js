// KO 연출용 서버 이벤트 (마지막 킬·낙사 방향) + 접속 상태 (ping/pong) 테스트
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;

function setupN(n) {
  const g = new Game(() => {});
  g.rng = () => 0.5;
  for (let i = 1; i <= n; i++) g.addPlayer(i);
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return { g, p: (id) => g.players.get(id) };
}

test('KO: 사망 이벤트에 죽은 자리, 낙사면 떨어진 쪽 (필드 밖이면 그쪽, 안이면 가까운 가장자리 바깥)', () => {
  const { g, p } = setupN(3);
  g.drainEvents();
  Object.assign(p(2), { x: -0.7, y: 4, z: -4.5 });
  g.kill(p(2), 'fall');
  const e = g.drainEvents().find((x) => x.type === 'death' && x.who === 2);
  assert.deepEqual(e.out, { x: -1, y: 0 });
  assert.equal(e.x, -0.7);
  // 필드 안 (밀려 떨어지기 직전 가장자리 근처)
  Object.assign(p(3), { x: 4, y: g.D - 0.2, z: -4.1 });
  g.kill(p(3), 'fall');
  assert.deepEqual(g.drainEvents().find((x) => x.type === 'death' && x.who === 3).out, { x: 0, y: 1 });
  // 압사는 방향 없음
  const q = setupN(2);
  q.g.drainEvents();
  q.g.kill(q.p(2), 'crush');
  assert.equal(q.g.drainEvents().find((x) => x.type === 'death').out, null);
});

test('KO: 판을 끝낸 죽음은 finalKill (누가·어떻게·자리·이긴 사람), 그 전 죽음은 아님. 서버 시간은 그대로', () => {
  const { g, p } = setupN(3);
  Object.assign(p(3), { x: 2, y: g.D + 0.5, z: -4.2 });
  g.kill(p(3), 'fall');
  g.tick(TICK);
  assert.ok(!g.drainEvents().some((e) => e.type === 'finalKill'), '판이 안 끝났으면 없음');
  for (let t = 0; t < 1000; t += TICK) g.tick(TICK);
  p(2).lastHit = { by: 1, kind: 'push', name: p(1).name };
  Object.assign(p(2), { x: g.W + 0.6, y: 3, z: -4.1 });
  const t0 = g.time;
  g.kill(p(2), 'fall');
  g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.equal(g.time, t0 + TICK, '서버 시간은 안 느려짐');
  const f = g.drainEvents().find((e) => e.type === 'finalKill');
  assert.ok(f, 'finalKill');
  assert.equal(f.who, 2);
  assert.equal(f.by, 1);
  assert.equal(f.cause, 'fall');
  assert.deepEqual(f.out, { x: 1, y: 0 });
  assert.deepEqual(f.winners, [1]);
  // 죽음 없이 끝난 판 (무승부 처리 등) 은 finalKill 없음
  const q = setupN(2);
  q.g.drainEvents();
  q.g.endRound(null);
  assert.ok(!q.g.drainEvents().some((e) => e.type === 'finalKill'));
});

// 가짜 소켓
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

test('접속: ping → pong 은 보낸 시각을 그대로 + 서버 틱 부하 (방 안·밖 둘 다), 잘못된 ping 은 무시', () => {
  const rooms = new Rooms({ rng: () => 0.5 });
  const ws = fakeWs();
  const conn = rooms.connect(ws);
  rooms.message(conn, { type: 'ping', t: 12345.5 });
  const a = ws.last('pong');
  assert.equal(a.t, 12345.5);
  assert.equal(a.tickMs, 1000 / C.TICK_RATE);
  assert.equal(a.workMs, 0);
  rooms.noteTick(25, 10);
  rooms.noteTick(5, 0);
  rooms.message(conn, { type: 'create', name: '방', nick: 'a' });
  rooms.message(conn, { type: 'ping', t: 7 });
  const b = ws.last('pong');
  assert.equal(b.t, 7);
  assert.ok(b.workMs > 20 && b.workMs <= 25, `일한 시간은 천천히 줄어듦 ${b.workMs}`);
  assert.equal(b.behindMs, 0);
  const n = ws.msgs.length;
  rooms.message(conn, { type: 'ping', t: 'x' });
  rooms.message(conn, { type: 'ping' });
  assert.equal(ws.msgs.length, n, '숫자가 아니면 답 없음');
});
