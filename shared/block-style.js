// 테마 지형 블록 모습 계산 (three.js 없음, client/blocks.js 셰이더가 씀 + 테스트)
import { CONFIG as C } from './config.js';
import { CELL } from './pieces.js';

// 셰이더에 넘길 값: 테마 terrain (색·결) + 공통 스타일 (WORLD_BLOCK_STYLES) + 테마 덮어쓰기 (terrain.block)
// 없는 결 값은 0 (끔). 스타일 이름이 표에 없으면 null → 예전 텍스처 블록
export function blockStyle(terrain, styleName = C.WORLD_BLOCK_STYLE) {
  const style = C.WORLD_BLOCK_STYLES[styleName];
  if (!style || !terrain) return null;
  const s = { lip: 0, strata: [0, 0], brick: null, grid: [0, 0], sheen: 0, sideShade: 1, ao: 0, hi: 0, sprout: null, ...style, ...terrain, ...(terrain.block || {}) };
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


// 칸 자리로 정하는 0..1 난수 (k: 쓰임마다 다른 값). 셰이더 대신 여기서 정해 인스턴스 속성으로 넘김 → 튀어나온 조각과 같은 값
export function cellRand(x, y, z, k = 0) {
  let h = Math.imul(x + 1013, 73856093) ^ Math.imul(y + 2029, 19349663) ^ Math.imul(z + 4051, 83492791) ^ Math.imul(k + 7, 2654435761);
  h = Math.imul(h ^ (h >>> 15), 2246822507);
  h = Math.imul(h ^ (h >>> 13), 3266489909);
  return ((h ^ (h >>> 16)) >>> 0) / 4294967296;
}

// 칸마다 셰이더 값 세 개 (render.updateGrid 와 같은 순서, 지형 칸만):
// open = 이웃이 빈 방향 (openBits), ao = 그늘 비트 (1·2·4·8 윗면 +x·−x·+y·−y 쪽 위 칸에 블록 → 그 가장자리 어둡게,
// 16·32·64·128 옆면 +x·−x·+y·−y 의 바깥 아래 칸이 막힘(바닥 포함) → 그 옆면 아래쪽 어둡게), lift = 드러난 윗면 높낮이 (−0.5..0.5, × step)
export function cellLooks(grid, W, D, H, skip) {
  const open = openBits(grid, W, D, H, skip);
  const solid = (x, y, z) => z < 0 || (x >= 0 && y >= 0 && x < W && y < D && z < H && grid[(z * D + y) * W + x] !== 0);
  const ao = [];
  const lift = [];
  let n = 0;
  const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
  for (let z = 0; z < H; z++) {
    for (let y = 0; y < D; y++) {
      for (let x = 0; x < W; x++) {
        const i = (z * D + y) * W + x;
        if (grid[i] !== CELL.TERRAIN || (skip && skip.has(i))) continue;
        let a = 0;
        dirs.forEach(([dx, dy], k) => {
          if (solid(x + dx, y + dy, z + 1)) a |= 1 << k;
          if (solid(x + dx, y + dy, z - 1)) a |= 16 << k;
        });
        ao[n] = a;
        lift[n] = cellRand(x, y, z, 1) - 0.5;
        n++;
      }
    }
  }
  return { open, ao, lift };
}

// 블록에서 튀어나온 조각 자리 (테마 sprout: { kind, side, top, size }). 드러난 옆면 (+x·−x·+y·−y) 과 윗면 (발에 안 걸리게 가장자리, 작게)
// 결과: { x, y, z (칸), face: 0 +x · 1 −x · 2 +y · 3 −y · 4 윗면, u, v (면 위 자리 −0.5..0.5), s (크기), spin (0..1) }. max 개까지
export function sproutSpots(grid, W, D, H, skip, sp, max) {
  const out = [];
  if (!sp) return out;
  const looks = openBits(grid, W, D, H, skip);
  let n = 0;
  for (let z = 0; z < H && out.length < max; z++) {
    for (let y = 0; y < D && out.length < max; y++) {
      for (let x = 0; x < W && out.length < max; x++) {
        const i = (z * D + y) * W + x;
        if (grid[i] !== CELL.TERRAIN || (skip && skip.has(i))) continue;
        const m = looks[n++];
        const size = (k) => sp.size[0] + cellRand(x, y, z, k) * (sp.size[1] - sp.size[0]);
        for (let f = 0; f < 4 && out.length < max; f++) {
          if (!(m & (1 << f)) || cellRand(x, y, z, 10 + f) >= sp.side) continue;
          out.push({ x, y, z, face: f, u: (cellRand(x, y, z, 20 + f) - 0.5) * 0.6, v: (cellRand(x, y, z, 30 + f) - 0.5) * 0.5, s: size(40 + f), spin: cellRand(x, y, z, 50 + f) });
        }
        if (m & 16 && sp.top && cellRand(x, y, z, 14) < sp.top && out.length < max) {
          // 윗면은 드러난 옆 가장자리 쪽 (없으면 모서리), 작게
          const edges = [0, 1, 2, 3].filter((f) => m & (1 << f));
          const f = edges.length ? edges[Math.floor(cellRand(x, y, z, 15) * edges.length)] : Math.floor(cellRand(x, y, z, 15) * 4);
          const along = (cellRand(x, y, z, 16) - 0.5) * 0.7;
          const sgn = f % 2 ? -1 : 1;
          const [u, v] = f < 2 ? [sgn * 0.38, along] : [along, sgn * 0.38];
          out.push({ x, y, z, face: 4, u, v, s: size(44) * C.BLOCK_SPROUT_TOP_SCALE, spin: cellRand(x, y, z, 54), edge: f });
        }
      }
    }
  }
  return out;
}
