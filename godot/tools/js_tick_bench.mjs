// 서버 틱 시간 비교 (JS 쪽): tests/bench.gd 와 같은 각본 (설명은 그 파일). 서버 방처럼 캐릭터 켬 (모두 닌자), 자동 블록 자리 고르기 CLEAR_BIAS.
// 틱마다 game.tick + 스냅샷 JSON 만들기 시간을 잼. 실행: node godot/tools/js_tick_bench.mjs [틱 수] [인원] [--no-chars]
import { Game } from '../../server/game.js';
import { CONFIG as C } from '../../shared/config.js';

const nums = process.argv.slice(2).filter((a) => /^\d+$/.test(a)).map(Number);
const N = nums[0] || 18000;
const P = nums[1] || 8;
const chars = !process.argv.includes('--no-chars');
const TICK = 1000 / C.TICK_RATE;
let s = 12345;
const g = new Game(() => {}, { characters: chars });
g.rng = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
for (let i = 0; i < P; i++) g.addPlayer(i + 1);
for (const p of g.players.values()) if (chars) p.char = 'ninja';
g.startRound();

function script(i) {
  for (const p of g.players.values()) {
    if (!p.alive) continue;
    let best = null;
    let bd = Infinity;
    for (const t of g.players.values()) {
      if (t === p || !t.alive) continue;
      const d = Math.hypot(t.x - p.x, t.y - p.y);
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    const yaw = best ? Math.atan2(best.y - p.y, best.x - p.x) : p.yaw;
    g.handleInput(p.id, { fwd: bd > 1 ? 1 : 0, strafe: 0, jump: (i + p.id * 7) % 45 === 0, yaw });
    if (bd < 1.7 && (i + p.id) % 6 === 0) g.handleAction(p.id, { name: 'push' });
    if ((i + p.id * 11) % 90 === 0) g.handleAction(p.id, { name: 'skill' });
    if (p.ult >= C.ULT_MAX) g.handleAction(p.id, { name: 'ult' });
  }
}

const times = [];
let rounds = 0;
const deaths = {};
for (let i = 0; i < N; i++) {
  if (g.phase === 'over') {
    rounds++;
    for (const d of g.deaths) deaths[d.cause] = (deaths[d.cause] || 0) + 1;
    g.startRound();
  }
  const t0 = process.hrtime.bigint();
  script(i);
  g.tick(TICK);
  JSON.stringify(g.snapshot()); // 격자 없이 (고도도 격자는 바뀔 때만 따로)
  g.drainEvents();
  times.push(Number(process.hrtime.bigint() - t0) / 1e6);
}
times.sort((a, b) => a - b);
const avg = times.reduce((a, b) => a + b, 0) / N;
console.log(`JS node ${process.version}, ${P}명 각본${chars ? ' 닌자' : ''}: 틱 ${N}번, 판 ${rounds}번 — 평균 ${avg.toFixed(3)}ms (예산 ${((avg / TICK) * 100).toFixed(1)}%), 중앙 ${times[N >> 1].toFixed(3)}ms, 99% ${times[Math.floor(N * 0.99)].toFixed(3)}ms, 최대 ${times[N - 1].toFixed(2)}ms, 사망 ${JSON.stringify(deaths)}`);
