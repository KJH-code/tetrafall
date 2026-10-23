// 방 (server/rooms.js) 테스트: 만들기·코드로 들어가기·공개 목록·나가기·내보내기·빈 방 삭제·방끼리 독립
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';

const TICK = 1000 / C.TICK_RATE;

// 가짜 소켓: 받은 메시지를 모아 둠
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

// 방마다 로그를 배열에 모으는 서버
function setup(seed = 1) {
  const logs = {};
  const closed = [];
  let s = seed;
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(m), close: () => closed.push(code) };
    },
    rng: () => {
      s = (s * 1664525 + 1013904223) >>> 0;
      return s / 4294967296;
    },
  });
  const join = () => {
    const ws = fakeWs();
    return { ws, conn: rooms.connect(ws) };
  };
  return { rooms, logs, closed, join };
}

test('방: 만들면 비공개 + 코드, 다른 사람은 코드로 들어옴 (소문자·공백 괜찮음)', () => {
  const { rooms, join } = setup();
  const a = join();
  assert.equal(a.ws.last('rooms').rooms.length, 0, '처음엔 방 밖에서 목록을 받음');
  rooms.message(a.conn, { type: 'create', name: '  우리   방 ', nick: '재혁' });
  const w = a.ws.last('welcome');
  assert.ok(w, '만든 사람은 바로 들어감');
  assert.match(w.room.code, new RegExp(`^[${C.ROOM_CODE_CHARS}]{${C.ROOM_CODE_LEN}}$`));
  assert.ok(!/[IO]/.test(w.room.code));
  assert.equal(w.room.name, '우리 방');
  assert.equal(w.room.public, false);
  assert.equal(rooms.publicList().rooms.length, 0, '비공개 방은 목록에 없음');
  const b = join();
  rooms.message(b.conn, { type: 'join', code: ` ${w.room.code.toLowerCase()} ` });
  assert.ok(b.ws.last('welcome'));
  const room = rooms.rooms.get(w.room.code);
  assert.equal(room.game.players.size, 2);
  assert.ok(room.game.isHost(a.conn.id), '만든 사람이 호스트');
});

test('방: 이름을 비우면 "<이름>의 방", 이름도 없으면 "방 <코드>"', () => {
  const { rooms, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create', name: '', nick: '민수' });
  assert.equal(a.ws.last('welcome').room.name, '민수의 방');
  const b = join();
  rooms.message(b.conn, { type: 'create' });
  const code = b.ws.last('welcome').room.code;
  assert.equal(b.ws.last('welcome').room.name, `방 ${code}`);
});

test('방: 없는 코드·꽉 찬 방은 거절하고 방 밖에 남김', () => {
  const { rooms, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'join', code: 'ZZZZ' });
  assert.match(a.ws.last('joinError').reason, /그런 방이 없습니다/);
  assert.equal(a.conn.room, null);
  rooms.message(a.conn, { type: 'create' });
  const code = a.ws.last('welcome').room.code;
  for (let i = 1; i < C.MAX_PLAYERS; i++) rooms.message(join().conn, { type: 'join', code });
  const late = join();
  rooms.message(late.conn, { type: 'join', code });
  assert.match(late.ws.last('joinError').reason, /꽉 찼습니다/);
  assert.equal(late.conn.room, null);
});

test('방: 공개는 호스트만, 판 사이에만. 목록엔 이름·사람/봇 인원·맵·모드·팀전·봇 난이도', () => {
  const { rooms, logs, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create', name: '같이 해요' });
  const code = a.ws.last('welcome').room.code;
  const b = join();
  rooms.message(b.conn, { type: 'join', code });
  rooms.message(b.conn, { type: 'setPublic', on: true });
  assert.equal(rooms.publicList().rooms.length, 0, '호스트가 아니면 못 바꿈');
  rooms.message(a.conn, { type: 'addBot' });
  rooms.message(a.conn, { type: 'teamMode', on: true });
  rooms.message(a.conn, { type: 'botLevel', level: 'hard' });
  rooms.message(a.conn, { type: 'setMap', map: 'stairs' });
  rooms.message(a.conn, { type: 'setMode', mode: 'kills' });
  rooms.message(b.conn, { type: 'setMode', mode: 'master' }); // 호스트 아님 → 무시
  rooms.message(a.conn, { type: 'setPublic', on: true });
  assert.deepEqual(rooms.publicList().rooms, [
    { code, name: '같이 해요', humans: 2, bots: 1, max: Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length), map: 'stairs', mode: 'kills', teamMode: true, botLevel: 'hard' },
  ]);
  assert.ok(logs[code].includes('[호스트] 방 공개'));
  // 판 중에는 못 바꿈
  rooms.message(a.conn, { type: 'start' });
  assert.ok(rooms.rooms.get(code).game.inRound());
  rooms.message(a.conn, { type: 'setPublic', on: false });
  assert.equal(rooms.publicList().rooms.length, 1);
  // 스냅샷에도 방 정보
  rooms.broadcast();
  assert.deepEqual(a.ws.last('state').room, { code, name: '같이 해요', public: true });
});

test('방: 사람이 다 나가면 봇이 있어도 방을 바로 없애고 로그를 닫음', () => {
  const { rooms, logs, closed, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const code = a.ws.last('welcome').room.code;
  rooms.message(a.conn, { type: 'addBot' });
  const b = join();
  rooms.message(b.conn, { type: 'join', code });
  rooms.message(a.conn, { type: 'leave' });
  assert.equal(a.conn.room, null);
  assert.ok(a.ws.last('left'), '나간 사람은 방 밖으로');
  assert.equal(a.ws.msgs.at(-1).type, 'rooms', '나간 뒤 목록을 받음');
  assert.ok(rooms.rooms.has(code), '사람이 남아 있으면 방 유지');
  assert.ok(rooms.rooms.get(code).game.isHost(b.conn.id), '호스트는 남은 사람에게');
  rooms.disconnect(b.conn); // 창 닫기
  assert.ok(!rooms.rooms.has(code), '사람 0명 → 방 없음');
  assert.deepEqual(closed, [code]);
  assert.ok(logs[code].at(-1).includes('닫음'));
  const c = join();
  rooms.message(c.conn, { type: 'join', code });
  assert.ok(c.ws.last('joinError'), '없어진 방 코드로는 못 들어감');
});

test(`방: 최대 ${C.ROOM_MAX}개, 넘으면 못 만듦. 하나가 닫히면 다시 됨`, () => {
  const { rooms, join } = setup();
  const owners = [];
  for (let i = 0; i < C.ROOM_MAX; i++) {
    const o = join();
    rooms.message(o.conn, { type: 'create' });
    owners.push(o);
  }
  assert.equal(new Set(rooms.rooms.keys()).size, C.ROOM_MAX, '코드가 겹치지 않음');
  const x = join();
  rooms.message(x.conn, { type: 'create' });
  assert.match(x.ws.last('joinError').reason, /더 못 만듭니다/);
  rooms.disconnect(owners[0].conn);
  rooms.message(x.conn, { type: 'create' });
  assert.ok(x.ws.last('welcome'));
});

test('방: 내보내면 대상은 방 밖 목록으로 (안내 문구), 방과 다른 사람은 그대로', () => {
  const { rooms, logs, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const code = a.ws.last('welcome').room.code;
  const b = join();
  rooms.message(b.conn, { type: 'join', code });
  rooms.message(b.conn, { type: 'kick', target: a.conn.id });
  assert.equal(a.conn.room?.code, code, '호스트가 아니면 못 내보냄');
  rooms.message(a.conn, { type: 'kick', target: b.conn.id });
  assert.equal(b.conn.room, null);
  assert.match(b.ws.last('left').reason, /내보냈습니다/);
  assert.ok(rooms.rooms.has(code));
  assert.equal(rooms.rooms.get(code).game.players.size, 1);
  assert.ok(logs[code].some((l) => /\[호스트\] P2 내보냄/.test(l)));
  // 내보내진 사람은 다시 들어올 수 있음 (새 사람으로)
  rooms.message(b.conn, { type: 'join', code });
  assert.ok(b.conn.room);
});

test('방: 두 방은 따로 돈다 — 상태·로그·스냅샷이 섞이지 않음', () => {
  const { rooms, logs, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const b = join();
  rooms.message(b.conn, { type: 'create' });
  const ca = a.ws.last('welcome').room.code;
  const cb = b.ws.last('welcome').room.code;
  assert.notEqual(ca, cb);
  rooms.message(a.conn, { type: 'addBot' });
  rooms.message(a.conn, { type: 'start' });
  // 방 B 는 혼자라 시작 못 함
  rooms.message(b.conn, { type: 'start' });
  assert.ok(rooms.rooms.get(ca).game.inRound());
  assert.equal(rooms.rooms.get(cb).game.phase, 'lobby');
  for (let i = 0; i < 30; i++) rooms.tick(TICK);
  a.ws.msgs.length = 0;
  b.ws.msgs.length = 0;
  rooms.broadcast();
  const sa = a.ws.last('state');
  const sb = b.ws.last('state');
  assert.equal(sa.room.code, ca);
  assert.equal(sb.room.code, cb);
  assert.deepEqual(sa.players.map((p) => p.id).sort(), [a.conn.id, -1].sort());
  assert.deepEqual(sb.players.map((p) => p.id), [b.conn.id]);
  assert.equal(a.ws.msgs.length, 1, '자기 방 스냅샷만 받음');
  assert.ok(logs[ca].some((l) => l.includes('ROUND 1 시작')));
  assert.ok(!logs[cb].some((l) => l.includes('ROUND')));
});

test('방: 판 중에 창을 닫으면 그 방 로그에 접속 끊김 사망, 마지막 사람이면 방도 닫힘', () => {
  const { rooms, logs, join } = setup();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const code = a.ws.last('welcome').room.code;
  const b = join();
  rooms.message(b.conn, { type: 'join', code });
  rooms.message(a.conn, { type: 'start' });
  rooms.tick(TICK);
  rooms.disconnect(b.conn);
  assert.ok(logs[code].some((l) => /ROUND 1 종료 .*승자: P1/.test(l)), '남은 한 명이 승리');
  assert.ok(logs[code].some((l) => /사망: .*P2 접속 끊김/.test(l)));
  rooms.disconnect(a.conn);
  assert.equal(rooms.rooms.size, 0);
});

test('방: 방 밖 목록은 바뀔 때만 다시 보냄, 방 안 사람에겐 안 보냄', () => {
  const { rooms, join } = setup();
  const out = join();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  rooms.broadcastList();
  const n = out.ws.msgs.length;
  rooms.broadcastList();
  assert.equal(out.ws.msgs.length, n, '그대로면 안 보냄');
  rooms.message(a.conn, { type: 'setPublic', on: true });
  const before = a.ws.msgs.filter((m) => m.type === 'rooms').length;
  rooms.broadcastList();
  assert.equal(out.ws.last('rooms').rooms.length, 1);
  assert.equal(a.ws.msgs.filter((m) => m.type === 'rooms').length, before, '방 안 사람은 목록을 안 받음');
});
