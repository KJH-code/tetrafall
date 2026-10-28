// 관전 궤도 카메라: 중심(따라가는 사람)을 바라보며 yaw·pitch 로 둘레를 돈다.
// 블록이 중심과 카메라 사이를 막으면 막힌 칸 앞으로 당긴다 (3인칭 게임 카메라 흔한 방식).
// three.js 없는 순수 계산 — client/render.js 가 쓰고 test/camera.test.js 가 검증한다.

// center {x,y,z}: 바라볼 점. yaw·pitch: 1인칭 시선과 같은 뜻 (pitch 가 음수 = 내려다봄 → 카메라는 위로)
// dist: 원하는 거리. solidAt(x,y,z) → 단단한가 (없으면 가림 검사 안 함)
// 돌려주는 것: { x, y, z, dist } (dist = 실제 거리, 막혔으면 줄어듦)
export function orbitEye(center, yaw, pitch, dist, solidAt = null, { step = 0.1, margin = 0.3, minDist = 0.6 } = {}) {
  const cp = Math.cos(pitch);
  const dx = -cp * Math.cos(yaw);
  const dy = -cp * Math.sin(yaw);
  const dz = -Math.sin(pitch);
  let d = dist;
  if (solidAt) {
    // 중심에서 카메라 쪽으로 걸으며 처음 단단한 칸을 찾음. 중심 바로 옆(minDist 안)은 안 봄 (유령이 블록 속에 있어도 카메라는 뒤에)
    for (let t = minDist; t <= dist; t += step) {
      if (solidAt(center.x + dx * t, center.y + dy * t, center.z + dz * t)) {
        d = Math.max(minDist, t - margin);
        break;
      }
    }
  }
  return { x: center.x + dx * d, y: center.y + dy * d, z: center.z + dz * d, dist: d };
}

// 3인칭 카메라 거리 따라가기: 막혀서 가까워져야 하면 바로 (벽 속이 안 보이게), 멀어질 때는 천천히 (덜컥거리지 않게)
// cur: 지금 거리 (없으면 want), want: 이번 프레임 거리, rate: 멀어지는 빠르기 (/초)
export function followDist(cur, want, dt, rate) {
  if (cur == null || want <= cur) return want;
  return cur + (want - cur) * (1 - Math.exp(-rate * dt));
}

// 전체 보기 거리 배율: 판이 기본(GRID_W)보다 크면 그만큼 멀리 (2026-10-28 8인 19×19 — 휠 줌은 이 배율에 곱해짐)
export function overviewScale(side, base) {
  return Math.max(1, side / base);
}
