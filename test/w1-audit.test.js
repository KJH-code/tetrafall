// 2026-10-30 코드 감사 서버 결함 S1·S3~S10 (재혁 W1): 항목마다 테스트. C# 쪽은 godot/server/tests/Tetrafall.Tests/AuditTests.cs 가 같은 내용
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { fakeWs } from './support/fake-ws.js';

const TICK = 1000 / C.TICK_RATE;
const run = (g, ms) => {
  for (let t = 0; t < ms; t += TICK) g.tick(TICK);
};

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
