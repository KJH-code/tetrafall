// 시작 지형 (2단계 D). 판 시작 때 격자에 미리 깔아 두는 블록.
// 모든 단차는 1칸이라 기본 점프(1.28칸)로 올라갈 수 있다.

export const MAPS = {
  flat: { name: '평지' },
  pyramid: { name: '피라미드' }, // 가운데가 높은 언덕: 높은 곳 차지하기
  stairs: { name: '계단' }, // 양쪽 가장자리를 따라 올라가는 계단
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
