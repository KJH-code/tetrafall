// 2026-10-30 코드 감사 서버 결함 S1·S3~S10 (재혁 W1): 항목마다 테스트. C# 쪽은 godot/server/tests/Tetrafall.Tests/AuditTests.cs 가 같은 내용
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C, maxPlayers } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { fakeWs } from './support/fake-ws.js';
import { TICK, run } from './support/tick.js';
import { lcg } from './support/rng.js';


function chars(list) {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  list.forEach((c, i) => {
    g.addPlayer(i + 1);
    g.setChar(i + 1, c);
  });
  g.startRound();
  g.nextSpawnAt = Infinity;
  g.controlItemNextAt = Infinity;
  g.powerItemNextAt = Infinity;
  return g;
}

test('S1 갈고리 R 로 블록을 뽑는 400ms 안에 나가면 뽑던 칸이 제자리로 (격자에서 안 사라짐)', () => {
  const g = chars(['hook', 'ninja', 'tank']);
  const [a, b] = [g.players.get(1), g.players.get(2)];
  Object.assign(b, { x: 1, y: 9, z: 0 });
  Object.assign(a, { x: 3.5, y: 4.5, z: 0, yaw: 0, vz: 0, grounded: true });
  g.grid[g.idx(5, 4, 0)] = CELL.THROWN;
  g.gridChanged();
  a.pitch = -Math.atan2(C.EYE_HEIGHT - 0.5, 2);
  a.ult = C.ULT_MAX;
  g.handleAction(1, { name: 'ult' });
  assert.ok(a.grab, '뽑는 중');
  assert.equal(g.grid[g.idx(5, 4, 0)], 0, '뽑는 동안 격자에선 빠져 있음');
  g.removePlayer(1);
  assert.equal(g.grid[g.idx(5, 4, 0)], CELL.THROWN, '나가면 제자리로');
});

// 조종 블록 하나 잡은 게임 (조종권 아이템으로 p1 이 조종)
function controlling() {
  const g = new Game(() => {});
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  g.players.get(1).hasControl = true;
  g.nextSpawnAt = g.time;
  g.tick(TICK);
  assert.ok(g.isControlling(g.players.get(1)));
  return g;
}

test('S3 pieceMove: dx·dy 크기는 -1·0·1 로, 한 틱에 PIECE_MOVE_PER_TICK 번까지만', () => {
  assert.equal(C.PIECE_MOVE_PER_TICK, 2);
  const g = controlling();
  const pc = g.controlledPiece(g.players.get(1));
  pc.px = 3;
  pc.py = 3;
  g.handleAction(1, { name: 'pieceMove', dx: 99, dy: 0 });
  assert.equal(pc.px, 4, '큰 dx 도 한 칸');
  g.handleAction(1, { name: 'pieceMove', dx: -50, dy: 1e9 });
  assert.equal([pc.px, pc.py].join(), '3,4', '-1·+1 칸');
  g.handleAction(1, { name: 'pieceMove', dx: 1, dy: 0 });
  assert.equal(pc.px, 3, '한 틱에 세 번째는 버림');
  g.tick(TICK);
  const pc2 = g.controlledPiece(g.players.get(1));
  const [x0, y0] = [pc2.px, pc2.py];
  g.handleAction(1, { name: 'pieceMove', dx: 'x', dy: NaN });
  g.handleAction(1, { name: 'pieceMove', dx: Infinity, dy: undefined });
  assert.equal([pc2.px, pc2.py].join(), [x0, y0].join(), '숫자가 아니면 0');
  g.tick(TICK);
  g.handleAction(1, { name: 'pieceMove', dx: 1, dy: 0 });
  assert.equal(g.controlledPiece(g.players.get(1)).px, x0 + 1, '다음 틱엔 다시 받음');
});

test('S7 호스트가 나가면 방장은 연결된 사람에게 먼저 (끊겨 자리만 남은 사람은 마지막)', () => {
  const g = new Game(() => {});
  for (const id of [1, 2, 3]) g.addPlayer(id);
  g.setAway(2, true);
  assert.equal(g.hostId, 1);
  g.removePlayer(1);
  assert.equal(g.hostId, 3, '끊긴 2 가 아니라 연결된 3');
  g.removePlayer(3);
  assert.equal(g.hostId, 2, '연결된 사람이 없으면 끊긴 사람에게라도');
  g.removePlayer(2);
  assert.equal(g.hostId, null);
});

test('S9 연습·튜토리얼에서 끊기면 대리 봇 없이 입력만 0 (생존 판은 예전처럼 봇 대리)', () => {
  const lines = [];
  const g = new Game((s) => lines.push(s), { characters: true });
  g.addPlayer(1);
  g.startPractice();
  g.addDummy(1);
  g.handleInput(1, { fwd: 1, strafe: 1, jump: true });
  assert.ok(g.setAway(1, true));
  assert.equal(g.proxies.size, 0, '대리 봇 없음');
  assert.deepEqual([g.players.get(1).input.fwd, g.players.get(1).input.strafe, g.players.get(1).input.jump], [0, 0, false]);
  assert.ok(lines.some((l) => l.includes('[끊김]') && !l.includes('봇 대리')));
  const [x, y] = [g.players.get(1).x, g.players.get(1).y];
  run(g, 3000);
  assert.equal([g.players.get(1).x, g.players.get(1).y].join(), [x, y].join(), '가만히 있음');
  g.setAway(1, false);
  const g2 = new Game((s) => lines.push(s));
  g2.addPlayer(1);
  g2.addPlayer(2);
  g2.startRound();
  g2.setAway(1, true);
  assert.equal(g2.proxies.size, 1, '생존 판은 봇 대리');
  assert.ok(lines.some((l) => l.includes('(봇 대리)')));
});

test('S10 columnTop: 판 밖 칸은 0 (격자 번호가 옆 칸으로 새지 않음)', () => {
  const g = new Game(() => {});
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  g.grid[g.idx(0, 1, 3)] = 1; // x=-1 이 (0,1) 쪽 번호로 새던 칸
  g.grid[g.idx(g.W - 1, 0, 2)] = 1;
  assert.equal(g.columnTop(0, 1) >= 4, true);
  for (const [x, y] of [[-1, 1], [g.W, 0], [0, g.D], [0, -1], [g.W + 5, g.D + 5]]) assert.equal(g.columnTop(x, y), 0, `${x},${y}`);
  assert.equal(g.columnTop(g.W - 1, 0) >= 3, true, '판 안은 그대로');
});

// ---------- 방 (rooms.js) ----------
function roomsSetup(opts = {}) {
  const logs = {};
  const server = [];
  const rooms = new Rooms({
    openLog: (code) => {
      logs[code] = [];
      return { log: (m) => logs[code].push(m), close() {} };
    },
    serverLog: (m) => server.push(m),
    ...opts,
  });
  const join = () => {
    const ws = fakeWs();
    return { ws, conn: rooms.connect(ws) };
  };
  return { rooms, logs, server, join };
}

test('S4 판을 한 번도 안 한 방은 연결 0명이면 짧은 유예(ROOM_EMPTY_LOBBY_GRACE_MS) 뒤 닫힘 — 그 안에 토큰으로 오면 같은 자리, 반복해도 ROOM_MAX 가 오래 안 참', () => {
  const { rooms, logs, join } = roomsSetup();
  const ticks = (ms) => {
    for (let t = 0; t < ms; t += TICK) rooms.tick(TICK);
  };
  assert.ok(C.ROOM_EMPTY_LOBBY_GRACE_MS > 0 && C.ROOM_EMPTY_LOBBY_GRACE_MS < C.RECONNECT_GRACE_MS);
  // 유예 안 재접속 성공: 같은 방·같은 자리
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  const code = a.ws.last('welcome').room.code;
  const token = a.ws.last('welcome').token;
  const id = a.ws.last('welcome').id;
  rooms.disconnect(a.conn);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS - 1000);
  assert.ok(rooms.rooms.has(code), '유예 안에는 방 유지');
  const a2 = join();
  rooms.message(a2.conn, { type: 'rejoin', code, token });
  assert.equal(a2.ws.last('welcome').rejoined, true);
  assert.equal(a2.ws.last('welcome').id, id, '같은 자리');
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS * 2);
  assert.ok(rooms.rooms.has(code), '돌아왔으면 방 유지');
  // 유예 지나면 닫힘 (로그에도 남음)
  rooms.disconnect(a2.conn);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS + 1000);
  assert.ok(!rooms.rooms.has(code), '유예 지나면 닫힘');
  assert.ok(logs[code].some((l) => l.includes('끊김 만료')));
  const late = join();
  rooms.message(late.conn, { type: 'rejoin', code, token });
  assert.ok(late.ws.last('rejoinError'), '닫힌 뒤엔 못 돌아옴');
  // 만들고 끊기 반복: ROOM_MAX 를 채워도 유예 뒤엔 다시 만들 수 있음 (60초까지 안 기다림)
  for (let i = 0; i < C.ROOM_MAX; i++) {
    const x = join();
    rooms.message(x.conn, { type: 'create' });
    rooms.disconnect(x.conn);
  }
  assert.equal(rooms.rooms.size, C.ROOM_MAX);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS + 1000);
  assert.equal(rooms.rooms.size, 0, '유예 뒤 모두 닫힘');
  const b = join();
  rooms.message(b.conn, { type: 'create' });
  assert.ok(b.ws.last('welcome'), '방이 다시 만들어짐');
  // 둘이 있는 방: 하나 끊겨도 방 유지, 남은 하나도 끊기면 유예 뒤 닫힘
  const code1 = b.ws.last('welcome').room.code;
  const c = join();
  rooms.message(c.conn, { type: 'join', code: code1 });
  rooms.disconnect(b.conn);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS + 1000);
  assert.ok(rooms.rooms.has(code1), '연결이 남아 있으면 유예 없이 유지(끊긴 자리는 RECONNECT_GRACE_MS)');
  rooms.disconnect(c.conn);
  ticks(C.RECONNECT_GRACE_MS); // b 의 끊긴 자리도 만료
  assert.ok(!rooms.rooms.has(code1));
  // 한 판 한 방은 예전처럼 RECONNECT_GRACE_MS
  const d = join();
  rooms.message(d.conn, { type: 'create' });
  const code2 = d.ws.last('welcome').room.code;
  rooms.rooms.get(code2).game.totals.rounds = 1;
  rooms.disconnect(d.conn);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS + 1000);
  assert.ok(rooms.rooms.has(code2), '한 판 한 방은 예전 자리 유지');
  ticks(C.RECONNECT_GRACE_MS);
  assert.ok(!rooms.rooms.has(code2));
  // 연습 방은 이 규칙 밖
  const e = join();
  rooms.message(e.conn, { type: 'practice' });
  const code3 = e.ws.last('welcome').room.code;
  rooms.disconnect(e.conn);
  ticks(C.ROOM_EMPTY_LOBBY_GRACE_MS + 1000);
  assert.ok(rooms.rooms.has(code3));
});

test('S5 방 코드는 crypto 난수 (Math.random 을 안 씀), 판 시드(game.rng)와 무관', () => {
  const { rooms, join } = roomsSetup();
  const real = Math.random;
  let calls = 0;
  Math.random = () => {
    calls++;
    return 0;
  };
  const codes = new Set();
  try {
    for (let i = 0; i < 20; i++) {
      const a = join();
      rooms.message(a.conn, { type: 'create' });
      codes.add(a.ws.last('welcome').room.code);
      rooms.message(a.conn, { type: 'leave' });
    }
  } finally {
    Math.random = real;
  }
  assert.equal(calls, 0, 'Math.random 호출 없음');
  assert.ok(codes.size > 10, `코드가 골고루 나옴 (${codes.size}종)`);
  for (const code of codes) assert.match(code, new RegExp(`^[${C.ROOM_CODE_CHARS}]{${C.ROOM_CODE_LEN}}$`));
  // 판 시드: 방 코드를 몇 번 뽑든 같은 시드의 판은 똑같이 재현됨
  const play = () => {
    const g = new Game(() => {});
    g.rng = lcg(5);
    g.addPlayer(1);
    g.addBot();
    g.startRound();
    run(g, 2000);
    return JSON.stringify(g.snapshot(true));
  };
  const first = play();
  const a = join();
  rooms.message(a.conn, { type: 'create' });
  assert.equal(play(), first);
  // 정해진 rng 를 넣으면 (테스트용) 그대로 따름
  const fixed = roomsSetup({ rng: () => 0 });
  const f = fixed.join();
  fixed.rooms.message(f.conn, { type: 'create' });
  assert.equal(f.ws.last('welcome').room.code, C.ROOM_CODE_CHARS[0].repeat(C.ROOM_CODE_LEN));
});

test('S6 join·rejoin 에러 문구에는 받은 코드를 ROOM_CODE_LEN 글자까지만', () => {
  const { rooms, join } = roomsSetup();
  const a = join();
  rooms.message(a.conn, { type: 'join', code: 'x'.repeat(5000) });
  const e = a.ws.last('joinError');
  assert.ok(e.reason.startsWith('XXXX: '), e.reason.slice(0, 20));
  assert.ok(e.reason.length < 100);
  rooms.message(a.conn, { type: 'rejoin', code: 'y'.repeat(5000), token: 't' });
  assert.equal(a.ws.last('rejoinError').code, 'YYYY');
  rooms.message(a.conn, { type: 'join', code: '   ' });
  assert.ok(a.ws.last('joinError').reason.startsWith('빈 코드'));
  // 진짜 방은 앞뒤 공백·소문자여도 들어감
  const h = join();
  rooms.message(h.conn, { type: 'create' });
  const code = h.ws.last('welcome').room.code;
  rooms.message(a.conn, { type: 'join', code: ` ${code.toLowerCase()} ` });
  assert.ok(a.ws.last('welcome'));
});

test('S8 튜토리얼 방에는 손님이 못 들어감 (연습 방은 예전처럼 같이 연습)', () => {
  const { rooms, join } = roomsSetup();
  const a = join();
  rooms.message(a.conn, { type: 'tutorial', char: 'tank' });
  const code = a.ws.last('welcome').room.code;
  const b = join();
  rooms.message(b.conn, { type: 'join', code });
  assert.ok(b.ws.last('joinError'));
  assert.equal(b.ws.last('welcome'), undefined);
  assert.equal(rooms.rooms.get(code).game.players.size, 1);
  const p = join();
  rooms.message(p.conn, { type: 'practice' });
  const pcode = p.ws.last('welcome').room.code;
  const q = join();
  rooms.message(q.conn, { type: 'join', code: pcode });
  assert.ok(q.ws.last('welcome'), '연습 방은 같이');
});

test('T2 서버 프로세스: LOG_DIR 의 임시 폴더에만 로그를 남김 (레포 logs/ 안 건드림)', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const { default: WebSocket } = await import('ws');
  const { startServer } = await import('./server-process.js');
  const repoLogs = path.join(path.dirname(new URL(import.meta.url).pathname), '..', 'logs');
  const before = fs.existsSync(repoLogs) ? fs.readdirSync(repoLogs).sort().join() : null;
  const { port, logDir, stop } = await startServer();
  try {
    const ws = await new Promise((res, rej) => {
      const w = new WebSocket(`ws://localhost:${port}`);
      w.on('open', () => res(w));
      w.on('error', rej);
    });
    const joined = new Promise((res) => ws.on('message', (raw) => JSON.parse(raw).type === 'welcome' && res(true)));
    ws.send(JSON.stringify({ type: 'create', nick: '로그' }));
    assert.ok(await joined);
    const files = fs.readdirSync(logDir).flatMap((d) => fs.readdirSync(path.join(logDir, d)));
    assert.ok(files.some((f) => f.endsWith('.txt')), `임시 로그 폴더에 방 로그: ${files}`);
    ws.close();
  } finally {
    stop();
  }
  assert.ok(!fs.existsSync(logDir), 'stop 이 임시 폴더를 지움');
  assert.equal(fs.existsSync(repoLogs) ? fs.readdirSync(repoLogs).sort().join() : null, before, '레포 logs/ 는 그대로');
});

// ---------- T4·T5: config 정리 ----------
test('T4 안 쓰던 config 키를 지움 (BARD_FORM_NAMES·FIGURE_ARM_SPREAD·SKY_LAVA_TRIGGER_MS·SFX_BANKS.metalL)', () => {
  for (const k of ['BARD_FORM_NAMES', 'FIGURE_ARM_SPREAD', 'SKY_LAVA_TRIGGER_MS']) assert.ok(!(k in C), k);
  assert.ok(!('metalL' in C.SFX_BANKS));
  assert.deepEqual(Object.keys(C.SKY_LAVA_TRIGGER_BY_COUNT), ['2', '5', '7'], '용암 시작 시각은 인원별 표 하나');
  const g = new Game(() => {});
  assert.equal(g.skyLavaMs, C.SKY_LAVA_TRIGGER_BY_COUNT[2]);
});

test('T5 손으로 따로 적던 값을 한 곳에서: 시작 위치 안쪽 칸·하늘 높이·재접속 시도 횟수·캐릭터 목록·최대 인원', async () => {
  assert.equal(C.SPAWN_POINTS[0].x, C.SPAWN_INSET);
  assert.equal(C.spawnPointsFor(C.GRID_W, C.GRID_D)[0].x, C.SPAWN_INSET);
  assert.equal(C.spawnPointsFor(13, 13)[1].x, 13 - C.SPAWN_INSET);
  assert.equal(C.SKY_TOP_Z, C.SKY_GRID_H);
  assert.equal(C.NET_RECONNECT_TRIES * C.NET_RECONNECT_MS, C.RECONNECT_GRACE_MS, '화면이 다시 붙어 보는 시간 = 서버가 자리를 지키는 시간');
  assert.deepEqual(C.FIGURE_CHARS, C.CHARACTERS);
  assert.deepEqual(C.RAGDOLL_CHARS, C.CHARACTERS);
  assert.notEqual(C.FIGURE_CHARS, C.CHARACTERS, '복사본 (한쪽을 고쳐도 다른 쪽이 안 변함)');
  assert.equal(maxPlayers(), 8);
  // 최대 인원 식은 shared/config.js 한 곳 — 서버·도구에는 따로 안 적음. 화면(client/main.js) 두 곳은 같은 식 그대로 (client 는 이번 일의 범위 밖)
  const fs = await import('node:fs');
  const path = await import('node:path');
  const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
  const expr = 'Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length)';
  for (const dir of ['server', 'tools']) {
    for (const f of fs.readdirSync(path.join(root, dir)).filter((n) => n.endsWith('.js') || n.endsWith('.mjs'))) {
      assert.ok(!fs.readFileSync(path.join(root, dir, f), 'utf8').includes(expr), `${dir}/${f}`);
    }
  }
  assert.equal(fs.readFileSync(path.join(root, 'client', 'main.js'), 'utf8').split(expr).length - 1, 2, '화면 쪽은 같은 식 두 곳');
});

// ---------- T7·T8: 문서·패키지 ----------
test('T7 없는 docs/characters.md 를 가리키는 곳이 없음, CLAUDE.md 에 shared/victory.js, CREDITS.md 에 cannon-es(MIT)', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
  assert.ok(!fs.existsSync(path.join(root, 'docs', 'characters.md')), '문서가 없으니 가리키면 안 됨');
  const skip = new Set(['node_modules', '.git', 'bin', 'obj', 'logs', 'sim-logs', 'dist', '.godot']);
  const walk = (dir, out = []) => {
    for (const e of fs.readdirSync(dir, { withFileTypes: true })) {
      if (skip.has(e.name)) continue;
      const p = path.join(dir, e.name);
      if (e.isDirectory()) walk(p, out);
      else if (/\.(js|mjs|cjs|md|cs|gd|json|html)$/.test(e.name) && !p.endsWith('w1-audit.test.js')) out.push(p);
    }
    return out;
  };
  const bad = walk(root).filter((p) => fs.readFileSync(p, 'utf8').includes('docs/characters.md'));
  assert.deepEqual(bad.map((p) => path.relative(root, p)), []);
  assert.match(fs.readFileSync(path.join(root, 'CLAUDE.md'), 'utf8'), /`shared\/victory\.js`/);
  assert.ok(fs.existsSync(path.join(root, 'shared', 'victory.js')));
  const credits = fs.readFileSync(path.join(root, 'client', 'assets', 'CREDITS.md'), 'utf8');
  assert.match(credits, /cannon-es[^\n]*MIT/);
});

test('T8 package.json engines.node 는 >=20.6 (package-lock 도 같음)', async () => {
  const fs = await import('node:fs');
  const path = await import('node:path');
  const root = path.join(path.dirname(new URL(import.meta.url).pathname), '..');
  const pkg = JSON.parse(fs.readFileSync(path.join(root, 'package.json'), 'utf8'));
  const lock = JSON.parse(fs.readFileSync(path.join(root, 'package-lock.json'), 'utf8'));
  assert.equal(pkg.engines.node, '>=20.6');
  assert.equal(lock.packages[''].engines.node, '>=20.6');
  const [maj, min] = process.versions.node.split('.').map(Number);
  assert.ok(maj > 20 || (maj === 20 && min >= 6), '지금 쓰는 node 도 조건을 만족');
});
