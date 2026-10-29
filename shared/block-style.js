// 테마 지형 블록 모습 계산 (three.js 없음, client/blocks.js 셰이더가 씀 + 테스트)
import { CONFIG as C } from './config.js';
import { CELL } from './pieces.js';

// 셰이더에 넘길 값: 테마 terrain (색·결) + 공통 스타일 (WORLD_BLOCK_STYLES) + 테마 덮어쓰기 (terrain.block)
// 없는 결 값은 0 (끔). 스타일 이름이 표에 없으면 null → 예전 텍스처 블록
export function blockStyle(terrain, styleName = C.WORLD_BLOCK_STYLE) {
  const style = C.WORLD_BLOCK_STYLES[styleName];
  if (!style || !terrain) return null;
  const s = { lip: 0, strata: [0, 0], brick: null, grid: [0, 0], sheen: 0, ...style, ...terrain, ...(terrain.block || {}) };
  delete s.block;
  const tints = (s.tints && s.tints.length ? s.tints : [s.side]).slice(0, 3);
  while (tints.length < 3) tints.push(tints[tints.length - 1]);
  s.tints = tints;
  if (s.glow == null) s.veins = 0; // 빛 금은 빛 색이 있는 테마만
  return s;
}

// 칸마다 이웃이 빈 방향 비트 (1 +x · 2 −x · 4 +y · 8 −y · 16 +z · 32 −z, 바닥 z=0 아래는 막힘).
// 같은 지형 칸만 '막힘' (다른 블록이 옆에 와도 지형 모서리는 깎인 채). skip: 그리지 않는 칸 (건축가 블록, 빈 칸처럼)
// 순서는 render.updateGrid 와 같게 (z → y → x, 지형 칸만) → n 번째 값 = n 번째 지형 인스턴스
export function openBits(grid, W, D, H, skip, out = []) {
  const at = (x, y, z) => x >= 0 && y >= 0 && z >= 0 && x < W && y < D && z < H && grid[(z * D + y) * W + x] === CELL.TERRAIN && !(skip && skip.has((z * D + y) * W + x));
  let n = 0;
  for (let z = 0; z < H; z++) {
    for (let y = 0; y < D; y++) {
      for (let x = 0; x < W; x++) {
        const i = (z * D + y) * W + x;
        if (grid[i] !== CELL.TERRAIN || (skip && skip.has(i))) continue;
        let m = 0;
        if (!at(x + 1, y, z)) m |= 1;
        if (!at(x - 1, y, z)) m |= 2;
        if (!at(x, y + 1, z)) m |= 4;
        if (!at(x, y - 1, z)) m |= 8;
        if (!at(x, y, z + 1)) m |= 16;
        if (z > 0 && !at(x, y, z - 1)) m |= 32;
        out[n++] = m;
      }
    }
  }
  out.length = n;
  return out;
}

