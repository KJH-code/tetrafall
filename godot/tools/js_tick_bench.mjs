// 서버 틱 시간 비교 (JS 쪽): tests/bench.gd 와 같은 각본 — 2명이 서로 쪽으로 걸으며 20틱마다 밀치기, 자동 블록,
// 판이 끝나면 다시. 틱마다 game.tick + 스냅샷 JSON 만들기 시간을 잼. 실행: node godot/tools/js_tick_bench.mjs [틱 수]
import { Game } from '../../server/game.js';
import { CONFIG as C } from '../../shared/config.js';

const N = Number(process.argv[2] || 36000);
const TICK = 1000 / C.TICK_RATE;
let s = 12345;
const g = new Game();
g.rng = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
g.addPlayer(1);
g.addPlayer(2);
g.startRound();
const times = [];
let rounds = 0;
for (let i = 0; i < N; i++) {
  if (g.phase === 'over') {
    rounds++;
    g.startRound();
  }
  for (const [id, other] of [[1, 2], [2, 1]]) {
    const a = g.players.get(id);
    const b = g.players.get(other);
    g.handleInput(id, { fwd: 1, strafe: 0, jump: i % 45 === 0, yaw: Math.atan2(b.y - a.y, b.x - a.x) });
    if (i % 20 === id * 5) g.handleAction(id, { name: 'push' });
  }
  const t0 = process.hrtime.bigint();
  g.tick(TICK);
  JSON.stringify(g.snapshot()); // 격자 없이 (고도도 격자는 바뀔 때만 따로)
  g.drainEvents();
  times.push(Number(process.hrtime.bigint() - t0) / 1e6);
}
times.sort((a, b) => a - b);
const avg = times.reduce((a, b) => a + b, 0) / times.length;
console.log(`JS (node ${process.version}): 틱 ${N}번, 판 ${rounds}번 끝남 — 평균 ${avg.toFixed(4)}ms, 중앙 ${times[N >> 1].toFixed(4)}ms, 99% ${times[Math.floor(N * 0.99)].toFixed(4)}ms, 최대 ${times[N - 1].toFixed(3)}ms`);
