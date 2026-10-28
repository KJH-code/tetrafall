// 재접속 (2026-10-28 재혁): 자리 토큰, 끊김 → RECONNECT_GRACE_MS 동안 자리 유지 (판 중 봇 대리) → 토큰으로 같은 자리, 지나면 나감
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;
const SEED0 = Number(process.env.TEST_SEED || 1);

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

function setup(seed = SEED0) {
  const logs = {};
  let s = seed >>> 0;
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(m), close() {} };
    },
    rng: () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 2 ** 32),
  });
  const connect = () => {
    const ws = fakeWs();
    return { ws, conn: rooms.connect(ws) };
  };
  return { rooms, logs, connect };
}

// 방장 a + b 가 들어온 방
function twoInRoom(seed) {
  const env = setup(seed);
  const a = env.connect();
  env.rooms.message(a.conn, { type: 'create', nick: '재혁' });
  const code = a.ws.last('welcome').room.code;
  const b = env.connect();
  env.rooms.message(b.conn, { type: 'join', code });
  const room = env.rooms.rooms.get(code);
  room.game.rng = (() => {
    let s = (seed * 7919) >>> 0;
    return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 2 ** 32);
  })();
  return { ...env, a, b, code, room, game: room.game };
}

const ticks = (rooms, ms) => {
  for (let t = 0; t < ms; t += TICK) rooms.tick(TICK);
};

test('자리 토큰: 들어오면 welcome 에 추측 못 할 토큰 (16바이트), 사람마다 다름', () => {
  const { a, b } = twoInRoom(1);
  const ta = a.ws.last('welcome').token;
  const tb = b.ws.last('welcome').token;
  assert.match(ta, /^[0-9a-f]{32}$/);
  assert.match(tb, /^[0-9a-f]{32}$/);
  assert.notEqual(ta, tb);
});

test('대기실에서 끊김 → 자리 유지 (방장도 그대로), 60초 안에 토큰으로 오면 같은 자리·이름·색·캐릭터·팀', () => {
  const { rooms, logs, a, b, code, game } = twoInRoom(1);
  rooms.message(a.conn, { type: 'teamMode', on: true });
  rooms.message(a.conn, { type: 'setChar', char: 'bard' });
  rooms.message(a.conn, { type: 'setColor', color: 9 });
  const id = a.conn.id;
  const before = { ...game.players.get(id) };
  const token = a.ws.last('welcome').token;
  rooms.disconnect(a.conn);
  assert.ok(game.players.has(id), '자리 유지');
  assert.ok(game.isHost(id), '방장 유지');
  assert.equal(game.snapshot().players.find((p) => p.id === id).away, true);
  ticks(rooms, C.RECONNECT_GRACE_MS - 1000);
  const a2 = { ws: fakeWs() };
  a2.conn = rooms.connect(a2.ws);
  rooms.message(a2.conn, { type: 'rejoin', code: code.toLowerCase(), token });
  const w = a2.ws.last('welcome');
  assert.ok(w && w.rejoined);
  assert.equal(w.id, id);
  assert.equal(a2.conn.id, id);
  const p = game.players.get(id);
  for (const k of ['slot', 'name', 'color', 'char', 'team', 'wins']) assert.deepEqual(p[k], before[k], k);
  assert.equal(p.away, false);
  assert.ok(game.isHost(id));
  assert.ok(a2.ws.last('state'), '전체 스냅샷');
  assert.ok(logs[code].some((l) => l.includes('[끊김] P1 자리 유지 60초')));
  assert.ok(logs[code].some((l) => l.includes('[복귀] P1')));
  // 다시 들어온 뒤에도 메시지가 그 자리로
  rooms.message(a2.conn, { type: 'setChar', char: 'ninja' });
  assert.equal(game.players.get(id).char, 'ninja');
  assert.equal(game.players.size, 2, '자리가 늘지 않음');
  void b;
});

test('60초가 지나면 예전처럼 나감 (방장은 넘어감), 그 뒤 토큰은 거절', () => {
  const { rooms, logs, a, b, code, game } = twoInRoom(2);
  const id = a.conn.id;
  const token = a.ws.last('welcome').token;
  rooms.disconnect(a.conn);
  ticks(rooms, C.RECONNECT_GRACE_MS + TICK);
  assert.ok(!game.players.has(id));
  assert.ok(game.isHost(b.conn.id), '방장은 남은 사람에게');
  assert.ok(logs[code].some((l) => l.includes('[끊김 만료] P1')));
  const a2 = { ws: fakeWs() };
  a2.conn = rooms.connect(a2.ws);
  rooms.message(a2.conn, { type: 'rejoin', code, token });
  assert.ok(a2.ws.last('rejoinError'));
  assert.equal(a2.conn.room, null);
});

test('틀린 토큰·없는 방은 거절, 방 안에 있는 접속의 rejoin 은 무시', () => {
  const { rooms, a, code, game } = twoInRoom(3);
  rooms.disconnect(a.conn);
  const x = { ws: fakeWs() };
  x.conn = rooms.connect(x.ws);
  for (const msg of [{ code, token: 'f'.repeat(32) }, { code, token: 123 }, { code: 'ZZZZ', token: a.ws.last('welcome').token }, { code }]) {
    rooms.message(x.conn, { type: 'rejoin', ...msg });
    assert.equal(x.conn.room, null, JSON.stringify(msg));
  }
  assert.equal(x.ws.msgs.filter((m) => m.type === 'rejoinError').length, 4);
  assert.equal(game.players.get(a.conn.id).away, true, '끊긴 자리는 그대로');
});

test('같은 토큰 두 창: 새 창이 자리를 가져가고 옛 창은 방 밖으로 (새 id 라 다른 방에 들어가도 안 겹침)', () => {
  const { rooms, a, code, game } = twoInRoom(4);
  const id = a.conn.id;
  const token = a.ws.last('welcome').token;
  const tab2 = { ws: fakeWs() };
  tab2.conn = rooms.connect(tab2.ws);
  rooms.message(tab2.conn, { type: 'rejoin', code, token });
  assert.equal(tab2.conn.id, id);
  assert.equal(tab2.conn.room.code, code);
  assert.equal(a.conn.room, null);
  assert.notEqual(a.conn.id, id);
  assert.ok(a.ws.last('left').replaced);
  assert.equal(game.players.size, 2);
  assert.ok(!game.players.get(id).away, '끊긴 적 없음');
  // 옛 창이 새 방을 만들어도 id 가 안 겹침
  rooms.message(a.conn, { type: 'create' });
  assert.ok(a.ws.last('welcome').id !== id);
  // 스냅샷은 새 창에만
  tab2.ws.msgs.length = 0;
  rooms.broadcast();
  assert.equal(tab2.ws.last('state').players.length, 2);
});

test('판 중 끊김: 봇이 handleInput·handleAction 으로 대신 조종, 돌아오면 바로 돌려받음 (피해 % 그대로, 입력은 멈춤)', () => {
  let checked = 0;
  for (const seed of [1, 2, 3, 4, 5].map((k) => k + SEED0 * 10)) {
    const { rooms, logs, a, b, code, game } = twoInRoom(seed);
    rooms.message(a.conn, { type: 'addBot' });
    rooms.message(a.conn, { type: 'start' });
    ticks(rooms, 4000); // 카운트다운 0 + 조금
    const id = b.conn.id;
    const token = b.ws.last('welcome').token;
    const calls = [];
    const hi = game.handleInput.bind(game);
    const ha = game.handleAction.bind(game);
    game.handleInput = (pid, inp) => {
      if (pid === id) calls.push('input');
      return hi(pid, inp);
    };
    game.handleAction = (pid, act) => {
      if (pid === id) calls.push(act.name);
      return ha(pid, act);
    };
    const p = game.players.get(id);
    const start = { x: p.x, y: p.y };
    rooms.disconnect(b.conn);
    assert.ok(logs[code].some((l) => l.includes('[끊김] P2 자리 유지 60초 (봇 대리)')), `시드 ${seed}`);
    assert.ok(game.proxies.has(id));
    ticks(rooms, 5000);
    if (!game.players.get(id).alive || game.phase !== 'playing') continue; // 그사이 죽거나 판이 끝났으면 다음 시드
    assert.ok(calls.filter((c) => c === 'input').length > 10, `시드 ${seed} 봇이 입력을 넣음`);
    assert.ok(Math.hypot(p.x - start.x, p.y - start.y) > 0.5 || calls.some((c) => c !== 'input'), `시드 ${seed} 움직이거나 행동함`);
    assert.equal(p.isBot, false, '사람 그대로 (봇 판정 특혜 없음, 이름에 봇 안 붙음)');
    const dmg = p.damage;
    const b2 = { ws: fakeWs() };
    b2.conn = rooms.connect(b2.ws);
    rooms.message(b2.conn, { type: 'rejoin', code, token });
    assert.equal(b2.conn.id, id);
    assert.ok(!game.proxies.has(id), '봇 대리 끝');
    assert.deepEqual([p.input.fwd, p.input.strafe, p.input.jump], [0, 0, false], '봇 입력이 남지 않음');
    assert.equal(p.damage, dmg);
    const n = calls.length;
    ticks(rooms, 1000);
    assert.equal(calls.length, n, '돌아온 뒤엔 봇이 안 건드림');
    checked++;
  }
  assert.ok(checked >= 3, `5판 중 ${checked}판만 끝까지 확인 (나머지는 그사이 죽음)`);
});

test('판 중 끊기고 60초 안 옴: 예전처럼 접속 끊김 사망 (살아 있었으면), 판은 계속', () => {
  const { rooms, logs, a, b, code, game } = twoInRoom(6);
  rooms.message(a.conn, { type: 'addBot' });
  rooms.message(a.conn, { type: 'start' });
  ticks(rooms, 1000);
  rooms.disconnect(b.conn);
  const room = rooms.rooms.get(code);
  room.seats.get(b.conn.id).awayAt = game.time - C.RECONNECT_GRACE_MS; // 60초 지난 것으로
  const alive = game.players.get(b.conn.id).alive;
  rooms.tick(TICK);
  assert.ok(!game.players.has(b.conn.id));
  if (alive) assert.ok(logs[code].some((l) => /사망: .*P2 접속 끊김/.test(l)) || game.deaths.some((d) => d.name === 'P2' && d.cause === 'disconnect'));
});

test('사람이 다 끊겨도 방은 60초 뒤에 없어짐, 그 안에 돌아오면 방 그대로', () => {
  const { rooms, a, b, code } = twoInRoom(7);
  const tb = b.ws.last('welcome').token;
  rooms.disconnect(a.conn);
  rooms.disconnect(b.conn);
  ticks(rooms, 30000);
  assert.ok(rooms.rooms.has(code));
  const b2 = { ws: fakeWs() };
  b2.conn = rooms.connect(b2.ws);
  rooms.message(b2.conn, { type: 'rejoin', code, token: tb });
  assert.ok(b2.ws.last('welcome'));
  ticks(rooms, 31000);
  assert.ok(rooms.rooms.has(code), 'b 가 있으니 방 유지 (a 만 나감)');
  assert.equal(rooms.rooms.get(code).game.players.size, 1);
  assert.ok(rooms.rooms.get(code).game.isHost(b2.conn.id), '방장은 b 에게');
  rooms.disconnect(b2.conn);
  ticks(rooms, C.RECONNECT_GRACE_MS + TICK);
  assert.ok(!rooms.rooms.has(code), '아무도 안 오면 방 없음');
});

test('스스로 나가기·내보내기는 자리를 바로 없앰 (토큰 무효), 끊긴 사람도 내보낼 수 있음', () => {
  const { rooms, a, b, code, game } = twoInRoom(8);
  const tb = b.ws.last('welcome').token;
  rooms.message(b.conn, { type: 'leave' });
  const b2 = { ws: fakeWs() };
  b2.conn = rooms.connect(b2.ws);
  rooms.message(b2.conn, { type: 'rejoin', code, token: tb });
  assert.ok(b2.ws.last('rejoinError'), '나가면 토큰 무효');
  // 끊긴 사람 내보내기
  rooms.message(b2.conn, { type: 'join', code });
  const id = b2.conn.id;
  const t2 = b2.ws.last('welcome').token;
  rooms.disconnect(b2.conn);
  rooms.message(a.conn, { type: 'kick', target: id });
  assert.ok(!game.players.has(id));
  const b3 = { ws: fakeWs() };
  b3.conn = rooms.connect(b3.ws);
  rooms.message(b3.conn, { type: 'rejoin', code, token: t2 });
  assert.ok(b3.ws.last('rejoinError'));
});

test('로그: 끊김·봇 대리·복귀(걸린 초)·만료를 npm run stats 가 셈', async () => {
  const { parseLog, summarize, formatReport } = await import('../tools/stats.js');
  const { rooms, logs, a, b, code, game } = twoInRoom(9);
  rooms.message(a.conn, { type: 'addBot' });
  rooms.message(a.conn, { type: 'start' });
  ticks(rooms, 1000);
  const tb = b.ws.last('welcome').token;
  rooms.disconnect(b.conn);
  ticks(rooms, 2000);
  const b2 = { ws: fakeWs() };
  b2.conn = rooms.connect(b2.ws);
  rooms.message(b2.conn, { type: 'rejoin', code, token: tb });
  rooms.disconnect(b2.conn);
  rooms.rooms.get(code).seats.get(b2.conn.id).awayAt = game.time - C.RECONNECT_GRACE_MS;
  rooms.tick(TICK);
  for (let t = 0; t < 300000 && game.phase !== 'over'; t += TICK) rooms.tick(TICK);
  const rounds = parseLog(logs[code].join('\n'));
  const s = summarize(rounds);
  assert.equal(s.reconnect.away, 2);
  assert.equal(s.reconnect.proxied, 2);
  assert.equal(s.reconnect.back, 1);
  assert.ok(Math.abs(s.reconnect.backMedian - 2) < 0.1, `${s.reconnect.backMedian}`);
  assert.equal(s.reconnect.expired, 1);
  assert.match(formatReport(s), /== 재접속 ==\n끊김 2번 \(판 중 봇 대리 2\) · 돌아옴 1번 \(걸린 시간 중앙값 2초\) · 60초 안에 안 옴 1번/);
});
