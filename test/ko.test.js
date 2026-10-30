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

test('접속 표시 계산 (shared/net.js): 핑 = 왕복 시간, 연속으로 높거나 튀면 알림, 스냅샷이 자주·길게 끊기면 알림, 서버가 느리면 알림, 알림은 잠깐 뒤 사라짐', async () => {
  const { NetMeter } = await import('../shared/net.js');
  const m = new NetMeter();
  assert.equal(m.view(0).ping, '…');
  const pong = (sent, now, extra = {}) => m.onPong({ type: 'pong', t: sent, workMs: 3, behindMs: 0, ...extra }, now);
  for (let i = 0; i < 5; i++) pong(i * 1000, i * 1000 + 40);
  let v = m.view(4100);
  assert.equal(v.ping, '40ms');
  assert.equal(v.warn, null);
  assert.equal(v.level, 'ok');
  const spikeRtt = 40 * C.NET_PING_SPIKE_MULT + 20; // 평균의 배수는 넘고 NET_PING_WARN_MS 는 안 넘음
  pong(5000, 5000 + spikeRtt); // 한 번 튐: 무시
  assert.equal(m.view(5200).warn, null, '한 번 튄 건 알림 없음');
  pong(6000, 6000 + spikeRtt); // 연속: 알림
  assert.match(m.view(6200).warn, /핑 튐/);
  assert.equal(m.view(6200 + C.NET_WARN_HOLD_MS + 100).warn, null, '잠깐 뒤 사라짐');
  pong(7000, 7040);
  const fresh = () => Object.assign(m, { warn: null, lastStateAt: null, gaps: [] }); // 앞 단계와 이어지지 않게
  // 스냅샷 끊김: 한 번 GAP 은 무시, 창 안에 두 번이면 알림, 한 번이라도 STALL 넘으면 바로
  fresh();
  m.onState(10000);
  m.onState(10033);
  m.onState(10033 + C.NET_SNAPSHOT_GAP_MS + 30);
  assert.equal(m.view(10033 + C.NET_SNAPSHOT_GAP_MS + 40).warn, null, '한 번 흔들림은 무시');
  m.onState(10600);
  m.onState(10600 + C.NET_SNAPSHOT_GAP_MS + 30);
  assert.match(m.view(10950).warn, /끊김/, '3초 안에 두 번');
  fresh();
  m.onState(20000);
  m.onState(20000 + C.NET_SNAPSHOT_GAP_MS + 30); // 앞 흔들림은 창 밖
  assert.equal(m.view(20000 + C.NET_SNAPSHOT_GAP_MS + 40).warn, null);
  fresh();
  m.onState(30000);
  m.onState(30000 + C.NET_SNAPSHOT_STALL_MS + 50);
  assert.match(m.view(30000 + C.NET_SNAPSHOT_STALL_MS + 60).warn, /끊김/, '길게 한 번');
  fresh();
  m.onState(40000);
  assert.equal(m.view(40000 + C.NET_SNAPSHOT_GAP_MS + 50).warn, null, '지금 조금 안 오는 건 무시');
  assert.match(m.view(40000 + C.NET_SNAPSHOT_STALL_MS + 50).warn, /끊김/, '지금도 길게 안 옴');
  // 서버 느림
  fresh();
  m.onState(50000);
  pong(50000, 50040, { workMs: C.NET_SERVER_SLOW_MS + 5 });
  assert.equal(m.view(50050).warn, '서버 느림');
  assert.equal(m.view(50050).server, C.NET_SERVER_SLOW_MS + 5);
  // 아주 높은 핑: 연속이면 bad, 한 번이면 아님
  const high = C.NET_PING_WARN_MS * 2 + 10;
  fresh();
  m.onState(60290);
  pong(60000, 60000 + high);
  m.onState(60300);
  assert.equal(m.view(60310).level, 'ok', '한 번은 아님');
  for (let t = 60333; t <= 61300; t += 33) m.onState(t);
  pong(61000, 61000 + high);
  assert.equal(m.view(61310).level, 'bad');
  assert.match(m.view(61310).warn, /핑 높음/);
});

test('접속 표시: 로컬 흔들림 (핑 5ms, 가끔 화면이 멈칫해 pong 하나·스냅샷 사이 하나가 늦음) 에는 1분 동안 노랑이 안 뜸', async () => {
  const { NetMeter } = await import('../shared/net.js');
  const m = new NetMeter();
  const tick = 1000 / C.TICK_RATE;
  let worst = 'ok';
  for (let now = 0, k = 0; now < 60000; k++) {
    const stall = k % 150 === 75 ? C.NET_SNAPSHOT_GAP_MS + 80 : 0; // 5초마다 한 번 멈칫
    now += tick + stall;
    m.onState(now);
    if (k % 30 === 0) m.onPong({ type: 'pong', t: now - 5 - stall, workMs: 2, behindMs: 0 }, now);
    const v = m.view(now + 5);
    if (v.level !== 'ok') worst = v.level + ' ' + v.warn;
  }
  assert.equal(worst, 'ok');
});

test('접속 표시: 느린 화면 (프레임 90ms, 헤드리스) 에서 pong·스냅샷이 프레임을 기다려 늦어도 노랑 없음, 그보다 큰 진짜 끊김·높은 핑은 알림', async () => {
  const { NetMeter } = await import('../shared/net.js');
  const m = new NetMeter();
  const frame = 90;
  let s = 7;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 2 ** 32);
  let worst = 'ok';
  for (let now = 0, k = 0; now < 30000; k++) {
    now += frame * (0.8 + 0.4 * rnd());
    m.onFrame(now);
    if (k % 3 !== 1) m.onState(now - rnd() * 20); // 스냅샷은 프레임에 몰려 처리됨
    if (k % 11 === 0) m.onPong({ type: 'pong', t: now - 5 - rnd() * frame, workMs: 2, behindMs: 0 }, now);
    const v = m.view(now);
    if (v.level !== 'ok') worst = v.level + ' ' + v.warn;
  }
  assert.equal(worst, 'ok');
  assert.ok(m.frameMs >= frame && m.frameMs <= frame * 1.2);
  // 화면이 1초 통째로 멈춤 (그 사이 프레임 없음): 멈춘 뒤 몰려 온 스냅샷·pong 은 렉 아님
  m.onFrame(30000);
  m.onState(30000);
  m.onState(31050);
  m.onPong({ type: 'pong', t: 30000, workMs: 2 }, 31060);
  m.onPong({ type: 'pong', t: 30010, workMs: 2 }, 31061);
  assert.equal(m.view(31070).warn, null, '화면 멈칫은 렉 아님');
  m.lastFrameAt = null; // 아래는 프레임 시각 없이 (프레임 간격만)
  // 진짜 렉: 핑 두 번 연속 크게 튐 / 스냅샷이 프레임 + 끊김 기준보다 오래 두 번
  for (let t = 31100; t <= 33000; t += 33) m.onState(t);
  m.onPong({ type: 'pong', t: 32000 - 300, workMs: 2 }, 32000);
  m.onPong({ type: 'pong', t: 33000 - 300, workMs: 2 }, 33000);
  assert.match(m.view(33010).warn, /핑/);
  m.warn = null;
  m.onState(40000);
  m.onState(40000 + C.NET_SNAPSHOT_GAP_MS + frame + 40);
  m.onState(40700);
  m.onState(40700 + C.NET_SNAPSHOT_GAP_MS + frame + 40);
  assert.match(m.view(41100).warn, /끊김/);
});

test('터널 링크: 서버가 터널 주소(https 만)를 받으면 방 정보 link = 주소/?room=코드, 없으면 필드 없음. 이상한 주소는 거부', async () => {
  const { roomLinkOf } = await import('../server/rooms.js');
  assert.equal(roomLinkOf('https://a-b.trycloudflare.com/', 'ABCD'), 'https://a-b.trycloudflare.com/?room=ABCD');
  const rooms = new Rooms({ rng: () => 0.5 });
  const ws = fakeWs();
  const conn = rooms.connect(ws);
  rooms.message(conn, { type: 'create', name: '방', nick: 'a' });
  const code = ws.last('welcome').room.code;
  assert.equal(ws.last('welcome').room.link, undefined, '터널 없으면 없음 (화면이 지금 주소로)');
  assert.equal(rooms.setPublicUrl('http://evil.example'), false, 'https 만');
  assert.equal(rooms.setPublicUrl('https://x.trycloudflare.com/"><script>'), false);
  assert.equal(rooms.setPublicUrl('https://pottery-sense.trycloudflare.com'), true);
  rooms.tick(TICK);
  rooms.broadcast();
  assert.equal(ws.last('state').room.link, `https://pottery-sense.trycloudflare.com/?room=${code}`, '다음 스냅샷부터 새 링크');
  const ws2 = fakeWs();
  const c2 = rooms.connect(ws2);
  rooms.message(c2, { type: 'join', code });
  assert.equal(ws2.last('welcome').room.link, `https://pottery-sense.trycloudflare.com/?room=${code}`);
});

test('터널 링크: npm run online 이 IPC 로 보낸 주소를 서버 프로세스가 받음, 클립보드 명령은 운영체제별', async () => {
  const { clipboardCommand } = await import('../tools/online.js');
  assert.deepEqual(clipboardCommand('win32'), ['clip', []]);
  assert.deepEqual(clipboardCommand('darwin'), ['pbcopy', []]);
  assert.equal(clipboardCommand('aix'), null);
  const { startServer } = await import('./server-process.js');
  const { srv, until, stop } = await startServer({ ipc: true });
  try {
    srv.send({ type: 'publicUrl', url: 'https://pottery-sense.trycloudflare.com' });
    assert.ok(await until(/친구용 주소: https:\/\/pottery-sense\.trycloudflare\.com/));
  } finally {
    stop();
  }
});
