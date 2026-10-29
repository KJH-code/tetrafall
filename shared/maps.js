// 시작 지형 (2단계 D, 2026-10-20 4개 추가). 판 시작 때 격자에 미리 깔아 두는 블록.
// 오르는 길의 단차는 1칸이라 기본 점프(1.28칸)로 맨 위까지 걸어서 갈 수 있다 (안쪽 절벽은 있음).
// 2026-10-29 재혁: 예전 배치(높은 곳이 가장자리·판 전체)는 그대로, 테마(config WORLD_MAP_THEME)에 맞는 포인트만 조금 (ACCENTS).
// 포인트는 1층씩만 높이거나(오르는 길 단차 1칸 그대로) 벽에 틈을 낸다. 높이 상한 MAP_MAX_H
import { CONFIG as C } from './config.js';

export const MAPS = {
  flat: { name: '평지' }, // 초원
  pyramid: { name: '피라미드' }, // 사막. 가운데가 높은 언덕: 높은 곳 차지하기. 꼭대기에 4층 머릿돌
  stairs: { name: '계단' }, // 수정 동굴. 양쪽 가장자리를 따라 올라가는 계단, 계단 꼭대기에 5층 수정 기둥
  bowl: { name: '그릇' }, // 화산. 가운데가 낮고 가장자리로 갈수록 높아짐, 벽마다 바닥까지 갈라진 틈 하나 (바람개비로 비낌)
  spiral: { name: '나선 계단' }, // 하늘 성. 바깥 두 줄을 따라 한 바퀴 돌며 0→5층, 5층 바깥 줄에 성가퀴 (한 칸 걸러 6층)
  pillars: { name: '기둥 숲' }, // 버섯 숲. 2층 기둥(가운데만 3층), 기둥마다 낮은 발판. 네 모서리 기둥은 3층 큰 버섯
  fortress: { name: '요새' }, // 중세 성. 네 모서리 3층 탑(바깥 모서리 한 칸은 4층 망루), 탑을 잇는 2층 성벽(변마다 성문 틈), 성벽 가운데 안쪽에 1층 발판
};

export const MAP_IDS = Object.keys(MAPS);

// 기둥 높이 목록 [x, y, h] 를 돌려준다 (h 칸만큼 z=0 부터 쌓음). W·D 는 판 크기 (인원별 10~19, FIELD_SIZES. 가운데 기준으로 늘어나고 높이는 10×10 과 같게)
export function mapColumns(id, W, D) {
  const h = new Map();
  for (const [x, y, z] of baseColumns(id, W, D)) h.set(x * 100 + y, z);
  ACCENTS[id]?.(W, D, (x, y) => h.get(x * 100 + y) ?? 0, (x, y, z) => (z > 0 ? h.set(x * 100 + y, z) : h.delete(x * 100 + y)));
  return [...h].map(([k, z]) => [Math.floor(k / 100), k % 100, Math.min(z, C.MAP_MAX_H)]).sort((a, b) => a[0] - b[0] || a[1] - b[1]);
}

// 테마 포인트: (W, D, get(x, y), set(x, y, h)). 예전 배치 위에 덧붙이기만
const ACCENTS = {
  // 사막: 피라미드 꼭대기 머릿돌 (가운데 1칸·짝수 판 2×2 는 5층, 그 둘레 4층. 10×10 은 가운데 4층만) + 네 모서리 3층 오벨리스크 (2·1층 단) + 변마다 무너진 돌 1층
  pyramid(W, D, get, set) {
    const raise = (x, y, h) => get(x, y) < h && set(x, y, h);
    const mx = mid(W);
    const my = mid(D);
    // 이웃 칸이 모두 나보다 낮지 않을 때만 한 층 (이웃 단차 1칸 유지. 10×10 은 꼭대기가 좁아 가운데만 4층)
    const flatTop = (x, y) => [[1, 0], [-1, 0], [0, 1], [0, -1]].every(([dx, dy]) => get(x + dx, y + dy) >= get(x, y));
    const ring = [];
    for (let x = mx[0] - 1; x <= mx[mx.length - 1] + 1; x++) for (let y = my[0] - 1; y <= my[my.length - 1] + 1; y++) if (flatTop(x, y)) ring.push([x, y]);
    for (const [x, y] of ring) set(x, y, get(x, y) + 1);
    for (const x of mx) for (const y of my) if (flatTop(x, y)) set(x, y, get(x, y) + 1);
    // 오벨리스크: 모서리 칸 3층, 양옆으로 2·1층 (피라미드처럼 이웃 단차 1칸)
    for (const [dx, dy, h] of [[0, 0, 3], [1, 0, 2], [0, 1, 2], [2, 0, 1], [0, 2, 1]]) for (const [x, y] of turns(W, D, dx, dy)) raise(x, y, h);
    const k = Math.floor(W / 2) + 1;
    for (const kk of W >= 14 ? [k, k + 2] : [k]) for (const [x, y] of turns(W, D, kk, 0)) raise(x, y, 1);
  },
  // 수정 동굴: 계단 맨 위 안쪽 줄 끝 6층 수정 첨탑 (안쪽으로 한 칸씩 내려옴) + 양옆 가장자리에 수정 무리 (3층 하나 + 둘레 2·1층, 판 가운데 기준 180° 돌린 짝, 큰 판은 두 쌍)
  stairs(W, D, get, set) {
    for (const [x, y, dx] of [[W - 1, 1, -1], [0, D - 2, 1]]) {
      // 계단 끝 칸을 2층 더 올리고 안쪽으로 한 칸에 1층씩 내려오게 (계단 방향 단차 1칸 그대로)
      const top = get(x, y) + 2;
      for (let i = 0; top - i > get(x + i * dx, y); i++) set(x + i * dx, y, top - i);
    }
    // 계단 없는 양옆 가장자리에 수정 무리 (바깥 칸 3층, 안쪽으로 2·1층. 가운데 바닥은 비워 둠 — 바닥에 두면 압사가 줄어듦)
    const ys = W >= 16 ? [0.35, 0.65] : [0.5];
    for (const fy of ys) {
      const y = Math.round(fy * (D - 1));
      for (const [dx, dy, h] of [[0, 0, 3], [0, 1, 2], [0, -1, 2], [1, 0, 2], [1, 1, 1], [1, -1, 1], [2, 0, 1]]) {
        for (const [x, yy] of [[dx, y + dy], [W - 1 - dx, D - 1 - y - dy]]) if (get(x, yy) < h) set(x, yy, h);
      }
    }
  },
  // 화산: 벽마다 바닥까지 갈라진 틈 (1칸 폭, 가운데에서 한 칸 비껴 바람개비) — 분화구로 들어가는 길 + 용암이 먼저 차는 낮은 홈.
  // 틈 양옆 바깥 벽은 4층 굴뚝
  bowl(W, D, get, set) {
    const k = Math.floor(W / 2) + 1;
    for (let d = 0; d < Math.floor(W / 2); d++) {
      if (get(k, d) === 0) break; // 벽 두께만큼 (안쪽 평지에 닿으면 멈춤)
      for (const [x, y] of turns(W, D, k, d)) set(x, y, 0);
    }
    // 틈 옆 바깥 벽 두 칸은 4층 화산 굴뚝 (분화구 바닥은 비워 둠 — 바닥에 바위를 두면 압사가 줄어듦)
    for (const [x, y] of turns(W, D, k - 2, 0)) set(x, y, get(x, y) + 1);
    for (const [x, y] of turns(W, D, k + 2, 0)) set(x, y, get(x, y) + 1);
  },
  // 하늘 성: 4·5층 바깥 줄을 한 칸 걸러 한 층 더 (성가퀴), 나선 끝(5층 → 절벽) 칸은 7층 뾰족탑 (옆 칸 6층)
  spiral(W, D, get, set) {
    const base = (x, y) => get(x, y);
    const outer = (x, y) => x === 0 || y === 0 || x === W - 1 || y === D - 1;
    let tip = null;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        if (!outer(x, y) || base(x, y) !== 5) continue;
        if ([[1, 0], [-1, 0], [0, 1], [0, -1]].some(([dx, dy]) => outer(x + dx, y + dy) && x + dx >= 0 && x + dx < W && y + dy >= 0 && y + dy < D && base(x + dx, y + dy) === 0)) tip = [x, y];
      }
    }
    const merlon = [];
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) if (outer(x, y) && base(x, y) >= 4 && (x + y) % 2 === 0) merlon.push([x, y]);
    }
    for (const [x, y] of merlon) set(x, y, base(x, y) + 1);
    if (tip) {
      const [x, y] = tip;
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx;
        const ny = y + dy;
        if (nx >= 0 && ny >= 0 && nx < W && ny < D && get(nx, ny) >= 5) set(nx, ny, 6);
      }
      set(x, y, 7);
    }
  },
  // 버섯 숲: 네 모서리 기둥은 3층 큰 버섯 (발판 2·1층), 가운데 버섯은 4층 (발판 3·2층)
  pillars(W, D, get, set) {
    const xs = [];
    for (let x = 1; x < W; x += 3) xs.push(x);
    const ys = [];
    for (let y = 1; y < D; y += 3) ys.push(y);
    const grow = (x, y, top) => {
      set(x, y, top);
      const dir = x + 2 < W ? 1 : -1; // 발판은 오른쪽, 판 끝이면 왼쪽
      for (let s = 1; s < top - 1; s++) if (get(x + dir * s, y) < top - s) set(x + dir * s, y, top - s);
    };
    xs.forEach((x, i) => ys.forEach((y, j) => {
      const end = (k, n) => k === 0 || k === n - 1;
      if (get(x, y) === 3) grow(x, y, 4); // 예전부터 3층인 가운데 기둥
      else if (end(i, xs.length) && end(j, ys.length)) grow(x, y, 3);
    }));
  },
  // 중세 성: 탑 바깥 모서리 한 칸 4층 망루, 성벽마다 2칸 성문 틈 (가운데에서 비껴 바람개비, 안쪽 1층 발판은 그대로)
  fortress(W, D, get, set) {
    for (const [x, y] of [[0, 0], [W - 1, 0], [0, D - 1], [W - 1, D - 1]]) set(x, y, 4);
    const k = Math.floor(W / 2) + 1;
    for (const kk of [k, k + 1]) for (const [x, y] of turns(W, D, kk, 0)) set(x, y, 0);
  },
};

// 가운데 칸 (홀수 판 1칸, 짝수 판 2칸)
function mid(n) {
  return n % 2 ? [(n - 1) / 2] : [n / 2 - 1, n / 2];
}
// (x, y) 를 판 가운데 기준 90° 씩 돌린 네 칸 (바람개비)
function turns(W, D, x, y) {
  return [[x, y], [W - 1 - y, x], [W - 1 - x, D - 1 - y], [y, D - 1 - x]];
}

// 예전 배치 (포인트 없이). 테스트가 "예전 그대로 + 조금" 인지 비교할 때도 씀
export function baseColumns(id, W, D) {
  const out = [];
  if (id === 'pyramid') {
    // 바깥에서 2칸 들어간 정사각형부터 한 칸씩 안으로 갈수록 1층씩 높아짐
    const cx = (W - 1) / 2;
    const cy = (D - 1) / 2;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        const ring = Math.max(Math.abs(x - cx), Math.abs(y - cy)); // 중심에서의 링 거리 (0.5, 1.5, ...)
        const h = Math.max(0, Math.floor((W / 2 - 1.5 - ring) + 1));
        if (h > 0) out.push([x, y, Math.min(h, 3)]);
      }
    }
  } else if (id === 'bowl') {
    // 10×10: 링 거리 0.5·1.5 는 평지, 2.5 → 1층, 3.5 → 2층, 4.5(맨 바깥) → 3층. 큰 판은 바깥 세 줄만 1·2·3층 (평지가 넓어짐, 2026-10-28 8인: 예전엔 19×19 바깥이 8층)
    const cx = (W - 1) / 2;
    const cy = (D - 1) / 2;
    const flat = Math.min(W, D) / 2 - 5; // 10×10 보다 늘어난 링 수
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        const h = Math.floor(Math.max(Math.abs(x - cx), Math.abs(y - cy)) - flat) - 1;
        if (h > 0) out.push([x, y, h]);
      }
    }
  } else if (id === 'spiral') {
    // 바깥 두 줄(링 거리 3.5 이상)을 중심 둘레 각도로 6등분해 0~5층. 한 바퀴 끝(5층)과 시작(0층) 사이는 절벽
    const cx = W / 2;
    const cy = D / 2;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        if (Math.max(Math.abs(x + 0.5 - cx), Math.abs(y + 0.5 - cy)) < W / 2 - 1.5) continue; // 바깥 두 줄 (10×10 이면 3.5)
        const a = (Math.atan2(y + 0.5 - cy, x + 0.5 - cx) + 2 * Math.PI) % (2 * Math.PI);
        const h = Math.floor((a / (2 * Math.PI)) * 6);
        if (h > 0) out.push([x, y, h]);
      }
    }
  } else if (id === 'pillars') {
    // x, y 가 3 으로 나눠 1 남는 칸에 2층 기둥 (가운데에 가장 가까운 기둥은 3층), 오른쪽 옆에 한 칸 낮은 발판
    const near = (n) => 1 + 3 * Math.round((n / 2 - 1 - 1) / 3); // 10 이면 4
    const mid = [near(W), near(D)];
    for (let x = 1; x < W; x += 3) {
      for (let y = 1; y < D; y += 3) {
        const top = x === mid[0] && y === mid[1] ? 3 : 2;
        out.push([x, y, top]);
        for (let s = 1; s < top && x + s < W; s++) out.push([x + s, y, top - s]);
      }
    }
  } else if (id === 'fortress') {
    // 모서리 2×2 탑 3층, 가장자리 한 줄 성벽 2층, 성벽 가운데 두 칸 안쪽에 1층 발판
    const tower = (x, y) => (x < 2 || x >= W - 2) && (y < 2 || y >= D - 2);
    const midX = [Math.floor(W / 2) - 1, Math.floor(W / 2)];
    const midY = [Math.floor(D / 2) - 1, Math.floor(D / 2)];
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        const edge = x === 0 || y === 0 || x === W - 1 || y === D - 1;
        if (tower(x, y)) out.push([x, y, 3]);
        else if (edge) out.push([x, y, 2]);
        else if ((midX.includes(x) && (y === 1 || y === D - 2)) || (midY.includes(y) && (x === 1 || x === W - 2))) out.push([x, y, 1]);
      }
    }
  } else if (id === 'stairs') {
    // 아래쪽 두 줄은 x 가 커질수록, 위쪽 두 줄은 x 가 작아질수록 높아짐 (0~4층). 한 층 너비 = W / 5 칸 (10×10 은 2칸, 큰 판은 넓은 계단 — 2026-10-28 예전엔 19×19 가 9층)
    const run = W / 5;
    for (let x = 0; x < W; x++) {
      const up = Math.floor(x / run);
      const down = Math.floor((W - 1 - x) / run);
      for (const y of [0, 1]) if (up > 0) out.push([x, y, up]);
      for (const y of [D - 2, D - 1]) if (down > 0) out.push([x, y, down]);
    }
  }
  return out;
}
