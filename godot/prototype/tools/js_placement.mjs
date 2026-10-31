// 자동 블록 자리 점수 비교 (JS 쪽): 여러 격자(기둥 높이)마다 모든 후보의 점수와 무작위 값별 고른 자리를 뽑음.
// 고도 tests/test_compare.gd 가 같은 격자로 auto_candidates·pick_candidate 를 돌려 같은지 봄.
// 실행: node godot/prototype/tools/js_placement.mjs > godot/prototype/tests/js_placement.json
import { Game } from '../../../server/game.js';
import { CONFIG as C } from '../../../shared/config.js';
import { SHAPE_NAMES, rotatedCells, footprint } from '../../../shared/pieces.js';

let s = 777;
const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 2 ** 32);
// [판 크기, 가장 낮은 층, 그 위로 솟은 기둥 비율]
const specs = [[10, 0, 0.3], [10, 1, 0.6], [10, 0, 0.05], [12, 2, 0.4], [14, 0, 0.2], [16, 1, 0.5], [19, 0, 0.15], [10, 3, 0.9]];
const cases = [];
for (const [size, base, q] of specs) {
  const g = new Game();
  g.setFieldSize(size);
  const tops = [];
  for (let y = 0; y < size; y++) {
    for (let x = 0; x < size; x++) {
      const h = base + (rnd() < q ? 1 + Math.floor(rnd() * 3) : 0);
      tops.push(h);
      for (let z = 0; z < h; z++) g.grid[g.idx(x, y, z)] = 1;
    }
  }
  const sc = g.placementScorer();
  const scores = [];
  for (const shape of SHAPE_NAMES) {
    for (let r = 0; r < 4; r++) {
      const cells = rotatedCells(shape, r);
      const { w, d } = footprint(cells);
      for (let px = 0; px <= size - w; px++) {
        for (let py = 0; py <= size - d; py++) {
          let landZ = 0;
          for (const [dx, dy] of cells) landZ = Math.max(landZ, sc.tops[(py + dy) * size + px + dx]);
          if (landZ + 1 > g.H || landZ > C.PIECE_SPAWN_Z) continue;
          scores.push(sc.score(cells, px, py, landZ));
        }
      }
    }
  }
  const picks = [];
  for (const u of [0.01, 0.25, 0.5, 0.75, 0.99]) {
    g.rng = () => u;
    const pc = g.chooseAutoPlacement('I');
    picks.push([u, pc.shape, pc.rot, pc.px, pc.py]);
  }
  cases.push({ size, tops, scores, picks });
}
console.log(JSON.stringify(cases));
