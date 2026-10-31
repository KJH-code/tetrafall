// 자동 블록 자리 고르기 한 번 시간 (JS 쪽, tests/bench_placement.gd 와 같은 격자). 실행: node godot/prototype/tools/js_placement_bench.mjs
import fs from 'node:fs';
import { Game } from '../../../server/game.js';

const cases = JSON.parse(fs.readFileSync(new URL('../tests/js_placement.json', import.meta.url)));
function make(size, tops) {
  const g = new Game();
  g.setFieldSize(size);
  tops.forEach((h, i) => {
    for (let z = 0; z < h; z++) g.grid[g.idx(i % size, Math.floor(i / size), z)] = 1;
  });
  return g;
}
function timed(g) {
  for (let k = 0; k < 20; k++) g.chooseAutoPlacement('I'); // JIT 데우기 (서버도 warmUpPlacement 로 데움)
  const n = 20;
  const t0 = process.hrtime.bigint();
  for (let k = 0; k < n; k++) g.chooseAutoPlacement('I');
  return `한 번 ${(Number(process.hrtime.bigint() - t0) / 1e6 / n).toFixed(2)}ms`;
}
for (const size of [10, 14, 19]) console.log(`${size}×${size} 평지: ${timed(make(size, []))}`);
for (const cs of cases) console.log(`${cs.size}×${cs.size} 울퉁불퉁: ${timed(make(cs.size, cs.tops))}`);
