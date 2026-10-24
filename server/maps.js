// 시작 지형 (2단계 D, 2026-10-20 4개 추가). 판 시작 때 격자에 미리 깔아 두는 블록.
// 오르는 길의 단차는 1칸이라 기본 점프(1.28칸)로 맨 위까지 걸어서 갈 수 있다 (안쪽 절벽은 있음).

export const MAPS = {
  flat: { name: '평지' },
  pyramid: { name: '피라미드' }, // 가운데가 높은 언덕: 높은 곳 차지하기
  stairs: { name: '계단' }, // 양쪽 가장자리를 따라 올라가는 계단
  bowl: { name: '그릇' }, // 가운데가 낮고 가장자리로 갈수록 높아짐
  spiral: { name: '나선 계단' }, // 바깥 두 줄을 따라 한 바퀴 돌며 0→5층
  pillars: { name: '기둥 숲' }, // 2층 기둥 9개(가운데만 3층), 기둥마다 1층 발판
  fortress: { name: '요새' }, // 네 모서리 3층 탑, 탑을 잇는 2층 성벽, 성벽 가운데 안쪽에 1층 발판
};

export const MAP_IDS = Object.keys(MAPS);

// 기둥 높이 목록 [x, y, h] 를 돌려준다 (h 칸만큼 z=0 부터 쌓음)
export function mapColumns(id, W, D) {
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
    // 링 거리 0.5·1.5 는 평지, 2.5 → 1층, 3.5 → 2층, 4.5(맨 바깥) → 3층
    const cx = (W - 1) / 2;
    const cy = (D - 1) / 2;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        const h = Math.floor(Math.max(Math.abs(x - cx), Math.abs(y - cy))) - 1;
        if (h > 0) out.push([x, y, h]);
      }
    }
  } else if (id === 'spiral') {
    // 바깥 두 줄(링 거리 3.5 이상)을 중심 둘레 각도로 6등분해 0~5층. 한 바퀴 끝(5층)과 시작(0층) 사이는 절벽
    const cx = W / 2;
    const cy = D / 2;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        if (Math.max(Math.abs(x + 0.5 - cx), Math.abs(y + 0.5 - cy)) < 3.5) continue;
        const a = (Math.atan2(y + 0.5 - cy, x + 0.5 - cx) + 2 * Math.PI) % (2 * Math.PI);
        const h = Math.floor((a / (2 * Math.PI)) * 6);
        if (h > 0) out.push([x, y, h]);
      }
    }
  } else if (id === 'pillars') {
    // x, y 가 3 으로 나눠 1 남는 칸에 2층 기둥 (가운데 (4,4) 는 3층), 오른쪽 옆에 한 칸 낮은 발판
    const mid = [Math.floor(W / 2) - 1, Math.floor(D / 2) - 1];
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
    // 아래쪽 두 줄은 x 가 커질수록, 위쪽 두 줄은 x 가 작아질수록 높아짐 (0~4층)
    for (let x = 0; x < W; x++) {
      const up = Math.floor(x / 2);
      const down = Math.floor((W - 1 - x) / 2);
      for (const y of [0, 1]) if (up > 0) out.push([x, y, up]);
      for (const y of [D - 2, D - 1]) if (down > 0) out.push([x, y, down]);
    }
  }
  return out;
}
