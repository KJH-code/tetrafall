// 상승하는 위험(용암 자리) 화면 계산 — three.js 없는 순수 계산 (hazard.js 가 씀, test/hazard.test.js 가 검사).
// 판정은 서버 (state.lava.z). 여기는 모습에 쓸 값만: 표면이 블록·바닥에 닿는 곳까지의 거리, 바닥 높이(깊이), 차오름 단계, 화면 경고 세기.
import { CONFIG as C } from '../shared/config.js';

// 위험 판이 덮는 넓이: 필드 + 둘레 margin 칸씩
export const HAZARD_MARGIN = 6;

// 격자에서 칸 (x, y) 기둥의 표면 근처 상태.
// pierce: 표면 높이 zs 에 걸친 칸이 차 있음 (블록이 표면을 뚫고 나옴 → 둘레에 거품·불꽃 테). zs < 0 이면 필드 안은 바닥이 뚫고 나옴
// ground: 표면 아래에서 가장 높은 단단한 윗면 높이 (깊이 = zs - ground, 얕을수록 밝고 투명)
export function columnAt(grid, W, D, H, x, y, zs) {
  if (x < 0 || y < 0 || x >= W || y >= D) return { pierce: false, ground: -C.HAZARD_DEEP };
  if (zs < 0) return { pierce: true, ground: 0 };
  const iz = Math.floor(zs);
  const solid = (z) => z >= 0 && z < H && !!grid[(z * D + y) * W + x];
  if (solid(iz)) return { pierce: true, ground: zs };
  for (let z = Math.min(iz - 1, H - 1); z >= 0; z--) if (solid(z)) return { pierce: false, ground: z + 1 };
  return { pierce: false, ground: 0 };
}

// 위험 판 전체를 칸마다 res 개로 나눈 표: dist (가장 가까운 뚫린 칸까지 칸 단위 거리, max 에서 자름) · ground.
// 거리는 두 번 훑는 근사 거리 (chamfer). contacts: 뚫린 칸과 안 뚫린 칸이 맞닿는 변 가운데 점 (거품·증기 입자 자리)
export function hazardField(grid, W, D, H, zs, res = C.HAZARD_FIELD_RES, max = C.HAZARD_FOAM_DIST) {
  const M = HAZARD_MARGIN;
  const cw = W + 2 * M;
  const cd = D + 2 * M;
  const nx = cw * res;
  const ny = cd * res;
  const cols = [];
  for (let cy = 0; cy < cd; cy++) for (let cx = 0; cx < cw; cx++) cols.push(columnAt(grid, W, D, H, cx - M, cy - M, zs));
  const col = (cx, cy) => (cx < 0 || cy < 0 || cx >= cw || cy >= cd ? { pierce: false, ground: -C.HAZARD_DEEP } : cols[cy * cw + cx]);
  const INF = 1e9;
  const dist = new Float32Array(nx * ny);
  const ground = new Float32Array(nx * ny);
  for (let j = 0; j < ny; j++) {
    for (let i = 0; i < nx; i++) {
      const c = col(Math.floor(i / res), Math.floor(j / res));
      dist[j * nx + i] = c.pierce ? 0 : INF;
      ground[j * nx + i] = c.ground;
    }
  }
  const a = 1 / res;
  const b = Math.SQRT2 / res;
  const relax = (k, v) => {
    if (v < dist[k]) dist[k] = v;
  };
  for (let j = 0; j < ny; j++) {
    for (let i = 0; i < nx; i++) {
      const k = j * nx + i;
      if (i > 0) relax(k, dist[k - 1] + a);
      if (j > 0) {
        relax(k, dist[k - nx] + a);
        if (i > 0) relax(k, dist[k - nx - 1] + b);
        if (i < nx - 1) relax(k, dist[k - nx + 1] + b);
      }
    }
  }
  for (let j = ny - 1; j >= 0; j--) {
    for (let i = nx - 1; i >= 0; i--) {
      const k = j * nx + i;
      if (i < nx - 1) relax(k, dist[k + 1] + a);
      if (j < ny - 1) {
        relax(k, dist[k + nx] + a);
        if (i < nx - 1) relax(k, dist[k + nx + 1] + b);
        if (i > 0) relax(k, dist[k + nx - 1] + b);
      }
    }
  }
  for (let k = 0; k < dist.length; k++) dist[k] = Math.min(max, dist[k]);
  const contacts = [];
  for (let cy = 0; cy < cd; cy++) {
    for (let cx = 0; cx < cw; cx++) {
      if (!col(cx, cy).pierce) continue;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        if (col(cx + dx, cy + dy).pierce) continue;
        contacts.push({ x: cx - M + 0.5 + dx * 0.5, y: cy - M + 0.5 + dy * 0.5, nx: dx, ny: dy });
      }
    }
  }
  return { nx, ny, res, x0: -M, y0: -M, w: cw, d: cd, dist, ground, contacts };
}

// 차오름 단계: 표면이 HAZARD_RISE_STEP 칸 오를 때마다 1 (화면 번쩍·흔들림·소리 훅)
export function riseStep(z) {
  return Math.floor(z / C.HAZARD_RISE_STEP + 1e-6);
}

// 화면 가장자리 경고 세기 (0~HAZARD_VIGNETTE_MAX): 내 발이 표면에 가까울수록 세게. gap = 내 z - 표면 z
export function vignetteStrength(gap, pulse = 0) {
  if (!(gap < C.HAZARD_VIGNETTE_DIST)) return Math.min(C.HAZARD_VIGNETTE_MAX, pulse * 0.15);
  const k = 1 - Math.max(0, gap) / C.HAZARD_VIGNETTE_DIST;
  return Math.min(C.HAZARD_VIGNETTE_MAX, C.HAZARD_VIGNETTE_MAX * k * k + pulse * 0.2);
}
