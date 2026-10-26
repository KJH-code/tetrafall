// 탱크 R 솟는 땅 이벤트 id (2026-10-26 B 요청): quakeRise·quakeFall 이 같은 id. 층 클리어로 칸이 옮겨져도 id 그대로,
// 판 시작·연습 맵 바꿈으로 버릴 때도 quakeFall {id, gone: []}
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { Game } from '../server/game.js';
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';

const TICK = 1000 / C.TICK_RATE;

function setup() {
  const g = new Game(() => {}, { characters: true });
  g.rng = () => 0.5;
  g.addPlayer(1);
  g.addPlayer(2);
  g.setChar(1, 'tank');
  g.startRound();
  g.nextSpawnAt = Infinity;
  const p = g.players.get(1);
  Object.assign(p, { x: 5, y: 5, z: 0 });
  Object.assign(g.players.get(2), { x: 0.5, y: 0.5 });
  return { g, p };
}

test('솟는 땅: quakeRise 와 quakeFall 이 같은 id, 솟을 때마다 새 id', () => {
  const { g, p } = setup();
  g.drainEvents();
  g.tankRing(p);
  const r1 = g.drainEvents().find((e) => e.type === 'quakeRise');
  assert.ok(Number.isInteger(r1.id));
  for (let t = 0; t < C.TANK_RING_MS + TICK * 2; t += TICK) g.tick(TICK);
  const f1 = g.drainEvents().find((e) => e.type === 'quakeFall');
  assert.equal(f1.id, r1.id);
  assert.deepEqual(f1.gone, r1.cells, '가라앉은 칸');
  assert.deepEqual(f1.cells, f1.gone, '예전 이름 cells 도 같이');
  g.tankRing(p);
  const r2 = g.drainEvents().find((e) => e.type === 'quakeRise');
  assert.notEqual(r2.id, r1.id);
});

test('솟는 땅: 층 클리어로 칸이 한 칸 내려가도 id 그대로, 가라앉을 때 옮겨진 칸으로', () => {
  const { g, p } = setup();
  for (let x = 0; x < g.W; x++) for (let y = 0; y < g.D; y++) g.grid[g.idx(x, y, 0)] = CELL.TERRAIN;
  g.gridChanged();
  p.z = 1;
  g.drainEvents();
  g.tankRing(p);
  const rise = g.drainEvents().find((e) => e.type === 'quakeRise');
  assert.ok(rise.cells.every(([, , z]) => z === 1));
  g.dropLayers([0]);
  for (let t = 0; t < C.TANK_RING_MS + TICK * 2; t += TICK) g.tick(TICK);
  const fall = g.drainEvents().find((e) => e.type === 'quakeFall');
  assert.equal(fall.id, rise.id);
  assert.ok(fall.gone.length > 0 && fall.gone.every(([, , z]) => z === 0), '내려간 칸');
});

test('솟는 땅: 가라앉기 전에 판이 새로 시작하거나 연습 맵을 바꾸면 quakeFall {id, gone: []}', () => {
  const { g, p } = setup();
  g.tankRing(p);
  const rise = g.drainEvents().find((e) => e.type === 'quakeRise');
  g.endRound(null);
  g.startRound();
  const fall = g.drainEvents().find((e) => e.type === 'quakeFall');
  assert.deepEqual(fall, { type: 'quakeFall', id: rise.id, gone: [], cells: [] });
  // 연습 맵 바꿈
  const q = new Game(() => {}, { characters: true });
  q.addPlayer(1);
  q.setChar(1, 'tank');
  q.startPractice();
  const t = q.players.get(1);
  Object.assign(t, { x: 5, y: 5, z: 0 });
  q.tankRing(t);
  const r2 = q.drainEvents().find((e) => e.type === 'quakeRise');
  q.setMap('pyramid');
  assert.deepEqual(q.drainEvents().find((e) => e.type === 'quakeFall'), { type: 'quakeFall', id: r2.id, gone: [], cells: [] });
  assert.equal(q.quakes.length, 0);
});
