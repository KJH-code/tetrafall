// 플레이어 색 고르기 (2026-10-27 재혁): PLAYER_PALETTE 에서 고름, 같은 색은 먼저 고른 사람 우선, 판 중엔 못 바꿈, 봇은 빈 색 자동
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { Rooms } from '../server/rooms.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';

function game() {
  const g = new Game(() => {}, { countdownMs: 0 });
  g.rng = () => 0.5;
  return g;
}

test('팔레트: 12~16색, 서로 다름, 유령 투하 격자 값이 다른 칸 값과 안 겹침', () => {
  const pal = C.PLAYER_PALETTE;
  assert.ok(pal.length >= 12 && pal.length <= 16);
  assert.equal(new Set(pal).size, pal.length);
  assert.ok(CELL.GHOST_BASE > CELL.SHAPE_BASE + 6, '모양 칸 값 위');
});

test('들어오면 빈 색 중 앞 번호 자동 (사람·봇 모두), 스냅샷에 color', () => {
  const g = game();
  g.addPlayer(1);
  g.addPlayer(2);
  const bot = g.addBot();
  assert.deepEqual([g.players.get(1).color, g.players.get(2).color, bot.color], [0, 1, 2]);
  assert.equal(g.snapshot().players.find((p) => p.id === 2).color, 1);
});

test('고르기: 범위 안 빈 색만, 남이 쓰는 색·범위 밖·정수 아님은 거절', () => {
  const g = game();
  g.addPlayer(1);
  g.addPlayer(2);
  assert.ok(g.setColor(1, 9));
  assert.equal(g.players.get(1).color, 9);
  assert.ok(!g.setColor(2, 9), '먼저 고른 사람 우선');
  assert.equal(g.players.get(2).color, 1);
  for (const bad of [-1, C.PLAYER_PALETTE.length, 2.5, 'x', '3', null, undefined]) assert.ok(!g.setColor(2, bad), `거절 ${bad}`);
  assert.equal(g.players.get(2).color, 1);
  assert.ok(g.setColor(1, 9), '같은 색 다시는 그대로 됨');
});

test('판 중에는 못 바꿈, 판 끝나면 됨', () => {
  const g = game();
  g.addPlayer(1);
  g.addPlayer(2);
  g.startRound();
  assert.ok(g.inRound());
  assert.ok(!g.setColor(1, 5));
  assert.equal(g.players.get(1).color, 0);
});

test('나가면 색이 풀려 다른 사람이 고를 수 있음, 새로 들어온 봇은 빈 색', () => {
  const g = game();
  g.addPlayer(1);
  g.addPlayer(2);
  g.setColor(1, 4);
  assert.ok(!g.setColor(2, 4));
  g.removePlayer(1);
  assert.ok(g.setColor(2, 4));
  const bot = g.addBot();
  assert.equal(bot.color, 0, '빈 색 중 앞 번호');
});

test('팀전: 색 고르기는 그대로 받아 둠 (몸 색은 화면이 팀 계열로), 팀전 켜고 끄기·팀 바꾸기로 색이 안 바뀜', () => {
  const g = game();
  g.addPlayer(1);
  g.addPlayer(2);
  g.setColor(1, 7);
  g.setTeamMode(true);
  g.setTeam(1, 'blue');
  assert.equal(g.players.get(1).color, 7);
  assert.ok(g.setColor(2, 3));
  assert.ok(!g.setColor(2, 7), '팀전이어도 같은 색은 안 됨 (개인전으로 돌아갈 때 겹치지 않게)');
  g.setTeamMode(false);
  assert.deepEqual([g.players.get(1).color, g.players.get(2).color], [7, 3]);
});

test('방 메시지 setColor: 받으면 바꾸고, 남의 색이면 그대로', () => {
  const rooms = new Rooms();
  const ws = () => ({ OPEN: 1, readyState: 1, msgs: [], send(t) { this.msgs.push(JSON.parse(t)); } });
  const a = rooms.connect(ws());
  rooms.message(a, { type: 'create', name: 'r' });
  const code = a.room.code;
  const b = rooms.connect(ws());
  rooms.message(b, { type: 'join', code });
  rooms.message(a, { type: 'setColor', color: 11 });
  rooms.message(b, { type: 'setColor', color: 11 });
  const g = a.room.game;
  assert.equal(g.players.get(a.id).color, 11);
  assert.notEqual(g.players.get(b.id).color, 11);
});
