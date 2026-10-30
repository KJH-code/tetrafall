// 서버 지키기 (2026-10-30 코드 감사): 방 하나의 예외가 서버를 죽이지 않음, 잘못된 주소, 블록 마스터 카운트다운 중 마스터 나감,
// 큰 메시지·메시지 빈도·긴 글자, 바드 앰프 중 대시 거부 (재혁 S2)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { parseLog } from '../tools/stats.js';

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
  let clock = 0;
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(m), close() {} };
    },
    serverLog: (m) => server.push(m),
    rng: (() => {
      let s = 7;
      return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 2 ** 32);
    })(),
    now: () => clock,
  });
  const join = () => {
    const ws = fakeWs();
    return { ws, conn: rooms.connect(ws) };
  };
  // 방 둘 (각각 사람 1 + 봇 1, 판 시작)
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const b = join();
  rooms.message(b.conn, { type: 'create' });
  for (const x of [a, b]) {
    rooms.message(x.conn, { type: 'addBot' });
    rooms.message(x.conn, { type: 'start' });
  }
  const A = a.conn.room;
  const B = b.conn.room;
  return { rooms, logs, server, a, b, A, B, join, advance: (ms) => (clock += ms) };
}

test('방 하나의 틱 예외: 그 방만 오류 로그 남기고 닫음, 사람은 방 밖 목록으로, 다른 방은 계속', () => {
  const { rooms, logs, server, a, b, A, B } = setup();
  A.game.tick = () => {
    throw new Error('펑');
  };
  const tB = B.game.time;
  rooms.tick(TICK);
  assert.ok(!rooms.rooms.has(A.code));
  assert.equal(a.conn.room, null);
  assert.match(a.ws.last('left').reason, /오류/);
  assert.ok(a.ws.last('rooms'), '방 밖 목록 받음');
  assert.ok(logs[A.code].some((l) => l.startsWith('[오류] 틱: Error: 펑')));
  assert.ok(server.some((l) => l.includes(`방 ${A.code} 오류로 닫음`)));
  assert.ok(rooms.rooms.has(B.code));
  assert.ok(B.game.time > tB, '다른 방 틱은 돎');
  rooms.broadcast();
  assert.ok(b.ws.last('state'));
  // 닫힌 방 사람은 새 방을 만들 수 있음
  rooms.message(a.conn, { type: 'create' });
  assert.ok(a.conn.room);
});

test('방 안 메시지 예외·스냅샷 예외도 그 방만 닫음', () => {
  const { rooms, a, b, A, B } = setup();
  A.game.handleInput = () => {
    throw new Error('입력');
  };
  rooms.message(a.conn, { type: 'input', fwd: 1 });
  assert.ok(!rooms.rooms.has(A.code));
  rooms.message(b.conn, { type: 'input', fwd: 1 });
  assert.ok(rooms.rooms.has(B.code));
  B.game.snapshot = () => {
    throw new Error('스냅샷');
  };
  rooms.broadcast();
  assert.ok(!rooms.rooms.has(B.code));
  assert.match(b.ws.last('left').reason, /오류/);
});

test('블록 마스터: 카운트다운 중 마스터가 나가도 예외 없이 시작 → 생존자 승으로 끝, 로그는 마스터 이름 없이 (stats 가 마스터로 안 읽음)', () => {
  const lines = [];
  const g = new Game((m) => lines.push(m), { countdownMs: 3000 });
  for (const id of [1, 2, 3]) g.addPlayer(id);
  g.setMode('master');
  assert.ok(g.startRound());
  const m = g.master();
  g.removePlayer(m.id);
  for (let t = 0; t < 4000; t += TICK) g.tick(TICK);
  assert.equal(g.phase, 'over');
  assert.deepEqual([...g.winnerIds].sort(), [2, 3]);
  assert.ok(lines.some((l) => l.includes('모드: 블록 마스터 (마스터가 나감, 1:00 버티기)')));
  const rounds = parseLog(lines.join('\n'));
  assert.equal(rounds[0].master, null);
});

test('블록 마스터: 대기실에서 끊긴 사람이 마스터로 뽑히고 카운트다운 중 자리 유지 시간이 끝나도 서버가 안 죽음', () => {
  const logs = {};
  const rooms = new Rooms({
    openLog: (code) => ((logs[code] = []), { log: (m) => logs[code].push(m), close() {} }),
    countdownMs: 3000,
  });
  const a = { ws: fakeWs() };
  a.conn = rooms.connect(a.ws);
  rooms.message(a.conn, { type: 'create' });
  const room = a.conn.room;
  const others = [1, 2].map(() => {
    const x = { ws: fakeWs() };
    x.conn = rooms.connect(x.ws);
    rooms.message(x.conn, { type: 'join', code: room.code });
    return x;
  });
  rooms.message(a.conn, { type: 'setMode', mode: 'master' }); // 마스터는 판마다 자리 순서 → 첫 판은 a (호스트)
  rooms.disconnect(a.conn); // 대기실에서 끊김 (자리 유지)
  rooms.message(others[0].conn, { type: 'start' }); // 방장이 아니라 거절
  room.game.hostId = others[0].conn.id; // (테스트) 다른 사람이 시작
  rooms.message(others[0].conn, { type: 'start' });
  assert.equal(room.game.phase, 'countdown');
  assert.ok(room.game.master(), '끊긴 사람도 마스터로 뽑힘');
  room.seats.get(a.conn.id).awayAt = room.game.time - C.RECONNECT_GRACE_MS; // 자리 유지 끝
  for (let t = 0; t < 4000; t += TICK) rooms.tick(TICK);
  assert.ok(rooms.rooms.has(room.code), '방도 그대로 (오류로 닫히지 않음)');
  assert.ok(!logs[room.code].some((l) => l.startsWith('[오류]')), logs[room.code].filter((l) => l.startsWith('[오류]')).join('\n'));
});

test('메시지 빈도: 연결마다 초당 NET_MSG_RATE (몰리면 NET_MSG_BURST) 까지, 넘는 건 버림 (한 번만 로그)', () => {
  const { rooms, server, join, advance } = setup();
  const x = join();
  const pongs = () => x.ws.msgs.filter((m) => m.type === 'pong').length;
  for (let i = 0; i < 500; i++) rooms.message(x.conn, { type: 'ping', t: i });
  assert.equal(pongs(), C.NET_MSG_BURST, '한꺼번에는 통 크기만큼');
  assert.equal(server.filter((l) => l.includes('메시지가 너무 많아')).length, 1);
  advance(500);
  for (let i = 0; i < 500; i++) rooms.message(x.conn, { type: 'ping', t: i });
  assert.equal(pongs(), C.NET_MSG_BURST + Math.min(C.NET_MSG_BURST, C.NET_MSG_RATE / 2), '0.5초 뒤엔 그만큼 다시');
  // 입력 30Hz + 핑은 10초 내내 다 받음
  const y = join();
  let sent = 0;
  for (let t = 0; t < 10000; t += 1000 / C.INPUT_SEND_RATE) {
    advance(1000 / C.INPUT_SEND_RATE);
    rooms.message(y.conn, { type: 'ping', t });
    sent++;
    if (sent % C.INPUT_SEND_RATE === 0) rooms.message(y.conn, { type: 'ping', t }), sent++; // 1초에 핑 하나 더
  }
  assert.equal(y.ws.msgs.filter((m) => m.type === 'pong').length, sent);
});

test('긴 글자: 1천만 자 이름·방 이름도 먼저 TEXT_RAW_MAX 로 잘라서 정리 (긴 문자열에 정규식을 통째로 안 돌림 → 틱이 안 멈춤)', () => {
  const { rooms, join } = setup();
  const long = 'ㄱ'.repeat(10_000_000);
  const x = join();
  // 시간 대신 (느린 기계·첫 실행에 흔들림) 정규식이 실제로 본 가장 긴 글자 수로 판정
  const replace = String.prototype.replace;
  let longest = 0;
  String.prototype.replace = function (...a) {
    longest = Math.max(longest, this.length);
    return replace.apply(this, a);
  };
  try {
    rooms.message(x.conn, { type: 'create', name: long, nick: long });
    rooms.message(x.conn, { type: 'setName', name: long });
  } finally {
    String.prototype.replace = replace;
  }
  assert.ok(longest <= C.TEXT_RAW_MAX, `정규식이 ${longest}자를 봄`);
  const p = x.conn.room.game.players.get(x.conn.id);
  assert.equal([...p.nick].length, C.NAME_MAX_LEN);
  assert.equal([...x.conn.room.name].length, C.ROOM_NAME_MAX_LEN);
});

test('바드 앰프 연주 중 대시는 거부 (제자리, 재혁 S2), 광전사 회전 중 대시는 됨', () => {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.setChar(1, 'bard');
  g.addPlayer(2);
  g.setChar(2, 'berserker');
  g.startRound();
  g.nextSpawnAt = Infinity;
  const bard = g.players.get(1);
  Object.assign(bard, { x: 3, y: 5, z: 0, yaw: 0, form: 'metal', ult: C.ULT_MAX });
  g.handleAction(1, { name: 'ult' });
  assert.ok(bard.amp);
  g.handleAction(1, { name: 'dash' });
  assert.equal(bard.dashReadyAt, 0, '대시 안 나감');
  for (let t = 0; t < 500; t += TICK) g.tick(TICK);
  assert.ok(Math.hypot(bard.x - 3, bard.y - 5) < 0.05, `제자리 (${bard.x.toFixed(2)}, ${bard.y.toFixed(2)})`);
  const bz = g.players.get(2);
  Object.assign(bz, { x: 7, y: 7, z: 0, ult: C.ULT_MAX });
  g.handleAction(2, { name: 'ult' });
  assert.ok(bz.spin, '광전사 회전');
  g.handleAction(2, { name: 'dash' });
  assert.ok(bz.dashReadyAt > g.time, '회전 중 대시는 됨');
});

test('서버 프로세스: 잘못된 % 주소는 400 (서버 안 죽음), 64KB 넘는 메시지는 그 연결만 끊김', async () => {
  const { default: WebSocket } = await import('ws');
  const { startServer } = await import('./server-process.js');
  const { srv, port, stop } = await startServer();
  try {
    const bad = await fetch(`http://localhost:${port}/%E0%A4%A`);
    assert.equal(bad.status, 400);
    const ok = await fetch(`http://localhost:${port}/`);
    assert.equal(ok.status, 200, '서버 살아 있음');
    // 큰 메시지 → 그 연결 끊김 (1009), 다른 연결은 그대로
    const open = () =>
      new Promise((res, rej) => {
        const ws = new WebSocket(`ws://localhost:${port}`);
        ws.on('open', () => res(ws));
        ws.on('error', rej);
      });
    const big = await open();
    const other = await open();
    const closed = new Promise((res) => big.on('close', (code) => res(code)));
    big.send(JSON.stringify({ type: 'setName', name: 'x'.repeat(C.NET_MAX_PAYLOAD_BYTES + 10) }));
    assert.equal(await closed, 1009);
    const pong = new Promise((res) => other.on('message', (raw) => JSON.parse(raw).type === 'pong' && res(true)));
    other.send(JSON.stringify({ type: 'ping', t: 1 }));
    assert.ok(await pong, '다른 연결은 그대로');
    other.close();
    assert.equal(srv.exitCode, null, '서버 프로세스 살아 있음');
  } finally {
    stop();
  }
});
