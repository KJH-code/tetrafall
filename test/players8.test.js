// 방 최대 8명 (2026-10-28 재혁): 사람 + 봇 8명까지, 9번째 거절, 인원별 필드 크기, 시작 위치, 맵 모양, 팀 4:4, 봇 8명 판이 끝남, 스냅샷 압축
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { MAP_IDS, mapColumns } from '../shared/maps.js';
import { overviewScale } from '../shared/camera.js';

const TICK = 1000 / C.TICK_RATE;
const SEED0 = Number(process.env.TEST_SEED || 1);
function seeded(k) {
  let s = (SEED0 * 7919 + k * 104729) >>> 0;
  return () => ((s = (s * 1664525 + 1013904223) >>> 0), s / 2 ** 32);
}

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
function rooms() {
  const r = new Rooms({ rng: seeded(1) });
  const join = () => {
    const ws = fakeWs();
    return { ws, conn: r.connect(ws) };
  };
  return { r, join };
}

test('최대 8명 (사람 + 봇), 시작 위치도 8곳', () => {
  assert.equal(C.MAX_PLAYERS, 8);
  assert.ok(C.SPAWN_POINTS.length >= C.MAX_PLAYERS);
});

test('방: 사람 8명까지 들어오고 9번째는 거절', () => {
  const { r, join } = rooms();
  const a = join();
  r.message(a.conn, { type: 'create', nick: 'a' });
  const code = a.ws.last('welcome').room.code;
  for (let i = 1; i < 8; i++) {
    const p = join();
    r.message(p.conn, { type: 'join', code });
    assert.ok(p.ws.last('welcome'), `${i + 1}번째`);
  }
  assert.equal(r.rooms.get(code).game.players.size, 8);
  const late = join();
  r.message(late.conn, { type: 'join', code });
  assert.match(late.ws.last('joinError').reason, /꽉 찼습니다 \(최대 8명\)/);
  assert.equal(late.conn.room, null);
});

test('방: 봇도 합쳐 8명까지 (사람 2 + 봇 6), 그 뒤 봇 추가·사람 참가 거절', () => {
  const { r, join } = rooms();
  const a = join();
  r.message(a.conn, { type: 'create', nick: 'a' });
  const code = a.ws.last('welcome').room.code;
  const b = join();
  r.message(b.conn, { type: 'join', code });
  const g = r.rooms.get(code).game;
  for (let i = 0; i < 10; i++) r.message(a.conn, { type: 'addBot' });
  assert.equal(g.players.size, 8);
  assert.equal([...g.players.values()].filter((p) => p.isBot).length, 6);
  const late = join();
  r.message(late.conn, { type: 'join', code });
  assert.ok(late.ws.last('joinError'));
  assert.equal(new Set([...g.players.values()].map((p) => p.slot)).size, 8, '자리 겹치지 않음');
});

test('필드 크기 표: 2~8명 모두 있고 인원이 늘면 커짐, 한 사람 넓이 40칸 이상 (2인 10×10 그대로)', () => {
  assert.equal(C.FIELD_SIZES[2], C.GRID_W);
  let prev = 0;
  for (let n = 2; n <= C.MAX_PLAYERS; n++) {
    const size = C.FIELD_SIZES[n];
    assert.ok(size > prev, `${n}명 ${size}`);
    assert.ok((size * size) / n >= 40, `${n}명 한 사람 넓이 ${(size * size) / n}`);
    prev = size;
  }
  // 판 시작 때 인원으로 정해짐
  for (const n of [5, 8]) {
    const g = new Game(() => {}, { countdownMs: 0, characters: true });
    g.rng = seeded(n);
    for (let i = 0; i < n; i++) g.addBot();
    g.startRound();
    assert.equal(g.W, C.FIELD_SIZES[n]);
    assert.equal(g.snapshot().field.w, C.FIELD_SIZES[n]);
  }
});

test('시작 위치: 5~8명 판에서 서로 5칸 이상 떨어짐, 필드 안, 맵 블록 속이 아님 (맵 7개 × 인원)', () => {
  for (let n = 5; n <= C.MAX_PLAYERS; n++) {
    const pts = C.spawnPointsFor(C.FIELD_SIZES[n], C.FIELD_SIZES[n]).slice(0, n);
    for (let i = 0; i < n; i++) for (let j = i + 1; j < n; j++) assert.ok(Math.hypot(pts[i].x - pts[j].x, pts[i].y - pts[j].y) >= 5, `${n}명 ${i}·${j}`);
    for (const map of MAP_IDS) {
      const g = new Game(() => {}, { countdownMs: 0 });
      g.rng = seeded(n);
      for (let i = 0; i < n; i++) g.addBot();
      g.setMap(map);
      g.startRound();
      for (const p of g.players.values()) {
        assert.ok(p.x > 0 && p.x < g.W && p.y > 0 && p.y < g.D, `${map} ${n}명 필드 안`);
        assert.ok(!g.solidAt(Math.floor(p.x), Math.floor(p.y), Math.floor(p.z + 0.1)), `${map} ${n}명 ${p.name} 블록 속 (${p.x},${p.y},${p.z})`);
      }
    }
  }
});

test('맵 모양: 큰 판에서도 가장 높은 층이 10×10 과 같음 (계단 4층·그릇 3층…), 10×10 모양은 그대로', () => {
  const top = (id, W) => Math.max(0, ...mapColumns(id, W, W).map((c) => c[2]));
  const expect10 = { flat: 0, pyramid: 3, stairs: 4, bowl: 3, spiral: 5, pillars: 3, fortress: 3 };
  for (const id of MAP_IDS) {
    assert.equal(top(id, 10), expect10[id], `${id} 10×10`);
    for (const W of Object.values(C.FIELD_SIZES)) {
      assert.equal(top(id, W), expect10[id], `${id} ${W}×${W}`);
      for (const [x, y] of mapColumns(id, W, W)) assert.ok(x >= 0 && x < W && y >= 0 && y < W);
    }
  }
  // 10×10 계단·그릇은 예전 식 그대로
  const stairs10 = mapColumns('stairs', 10, 10);
  assert.deepEqual(stairs10.filter(([, y]) => y === 0).map(([x, , h]) => [x, h]), [[2, 1], [3, 1], [4, 2], [5, 2], [6, 3], [7, 3], [8, 4], [9, 4]]);
  const bowl10 = mapColumns('bowl', 10, 10);
  assert.deepEqual(bowl10.filter(([, y]) => y === 4).map(([x, , h]) => [x, h]), [[0, 3], [1, 2], [2, 1], [7, 1], [8, 2], [9, 3]]);
});

test('팀전 4:4: 8명이 들어오면 빨강 4 · 파랑 4, 시작 가능', () => {
  const g = new Game(() => {}, { countdownMs: 0 });
  g.rng = seeded(4);
  g.addPlayer(1);
  g.setTeamMode(true);
  for (let i = 0; i < 7; i++) g.addBot();
  const ps = [...g.players.values()];
  assert.equal(ps.filter((p) => p.team === 'red').length, 4);
  assert.equal(ps.filter((p) => p.team === 'blue').length, 4);
  assert.ok(g.canStart());
  assert.ok(g.startRound());
});

test('봇 8명 판 (생존·캐릭터·하늘 계단): 끝까지 돌고 4분 안에 끝남, 사망 7명 이상 (시드 여러 개)', () => {
  for (let k = 0; k < 3; k++) {
    const g = new Game(() => {}, { countdownMs: 0, characters: true, skyStairs: true });
    g.rng = seeded(800 + k);
    for (let i = 0; i < 8; i++) {
      const b = g.addBot();
      g.setChar(b.id, C.CHARACTERS[(i + k) % C.CHARACTERS.length]);
    }
    g.setMap(MAP_IDS[(k * 3) % MAP_IDS.length]);
    g.startRound();
    let t = 0;
    while (g.phase !== 'over' && t < 240000) {
      g.tick(TICK);
      t += TICK;
      g.drainEvents();
    }
    assert.equal(g.phase, 'over', `시드 ${k}: ${Math.round(t / 1000)}초에도 안 끝남`);
    assert.ok(g.deaths.length >= 7, `사망 ${g.deaths.length}`);
  }
});

test('전체 보기 카메라: 큰 판은 판 크기만큼 멀리 (10×10 은 그대로)', () => {
  assert.equal(overviewScale(10, C.GRID_W), 1);
  assert.equal(overviewScale(8, C.GRID_W), 1);
  assert.ok(Math.abs(overviewScale(19, C.GRID_W) - 1.9) < 1e-9);
});

test('스냅샷 압축: 서버가 permessage-deflate 를 켬, 큰 메시지(스냅샷)만 압축', async () => {
  assert.ok(C.NET_DEFLATE_MIN_BYTES > 200 && C.NET_DEFLATE_MIN_BYTES <= 4096);
  const { spawn } = await import('node:child_process');
  const path = await import('node:path');
  const { fileURLToPath } = await import('node:url');
  const { default: WebSocket } = await import('ws');
  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  const port = String(30000 + Math.floor(Math.random() * 20000));
  const srv = spawn(process.execPath, [path.join(root, 'server', 'index.js')], { stdio: ['ignore', 'pipe', 'pipe'], env: { ...process.env, PORT: port } });
  let out = '';
  srv.stdout.on('data', (b) => (out += b));
  try {
    for (let t = 0; t < 5000 && !/실행 중/.test(out); t += 50) await new Promise((r) => setTimeout(r, 50));
    const ws = new WebSocket(`ws://localhost:${port}`);
    await new Promise((ok, bad) => {
      ws.on('open', ok);
      ws.on('error', bad);
    });
    assert.match(ws.extensions, /permessage-deflate/);
    ws.send(JSON.stringify({ type: 'create', nick: 'a' }));
    for (let i = 0; i < 7; i++) ws.send(JSON.stringify({ type: 'addBot' }));
    const state = await new Promise((ok) => ws.on('message', (raw) => {
      const m = JSON.parse(raw);
      if (m.type === 'state' && m.players.length === 8) ok(m);
    }));
    assert.equal(state.players.length, 8);
    ws.close();
  } finally {
    srv.kill();
  }
});
