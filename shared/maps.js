// 시작 지형. 판 시작 때 격자에 미리 깔아 두는 블록. 2026-10-29 재혁: 맵마다 확실한 특징 하나 + 테마(world.js WORLD_MAP_THEME)에 맞는 모양으로 다시.
// 공정성: 모든 맵이 필드 가운데를 축으로 90° 돌려도 같은 바람개비 대칭 (거울 대칭은 아님 → 덜 반듯함). 시작 자리 8곳(모서리 4·변 가운데 4)도
// 90° 돌리면 서로 겹쳐서, 같은 종류 자리끼리는 주변 지형이 똑같다. 시작 칸과 그 둘레 한 칸은 늘 바닥(0)으로 비운다 (MAP_SPAWN_CLEAR).
// 크기: 필드 10~19칸(FIELD_SIZES) 모두에서 같은 모양이 커지고(위치·넓이는 판 크기에 비례), 높이는 판 크기와 상관없이 맵마다 같은 상한.
// 오르는 길: 어느 블록 윗면이든 이웃 칸끼리 2칸 이하(2단 점프) 차이로 바닥에서 올라갈 수 있다 (테스트).

import { CONFIG as C } from './config.js';

export const MAPS = {
  flat: { name: '평지' }, // 초원: 블록 없는 트인 들판 (기본 맵). 숨을 곳·높은 곳이 없어 밀기 실력만 — 다른 맵과 비교 기준
  pyramid: { name: '피라미드' }, // 사막: 가운데 3층 피라미드(왕 자리) + 바깥 모래 언덕 4개가 바람을 막는 오아시스 고리
  stairs: { name: '계단' }, // 수정 동굴: 수정 탑 4개, 탑마다 바깥으로 내려가는 계단, 탑끼리는 가운데로 가는 좁은 수정 다리
  bowl: { name: '그릇' }, // 화산: 가운데 분화구(낮음 = 용암이 먼저 차는 위험한 곳)를 두른 칼데라 벽, 벽에 고개 4곳
  spiral: { name: '나선 계단' }, // 하늘 성: 가운데 5층 탑을 도는 나선 길, 길 중간이 한 칸씩 끊겨 2단 점프로 건넘
  pillars: { name: '기둥 숲' }, // 버섯 숲: 높이 다른(1~4층) 버섯 기둥 징검다리, 높은 버섯일수록 가운데 가까움
  fortress: { name: '요새' }, // 중세 성: 가운데 성채(2층 성벽 + 3층 망루, 성문 4곳) 둘레를 해자(바닥)가 돌고 판 가장자리는 1층 바깥 성벽
};

export const MAP_IDS = Object.keys(MAPS);

// 기둥 높이 목록 [x, y, h] 를 돌려준다 (h 칸만큼 z=0 부터 쌓음). W·D 는 판 크기 (인원별 10~19, FIELD_SIZES)
export function mapColumns(id, W, D) {
  const f = SHAPES[id];
  const out = [];
  if (!f) return out;
  const clear = spawnClear(W, D);
  const c = (W - 1) / 2;
  const s = W / 10; // 10×10 기준 배율
  for (let x = 0; x < W; x++) {
    for (let y = 0; y < D; y++) {
      if (clear.has(x * 100 + y)) continue;
      const [u, v] = canon(x - c, y - c);
      const h = Math.min(C.MAP_MAX_H, Math.max(0, Math.round(f(u, v, s, W))));
      if (h > 0) out.push([x, y, h]);
    }
  }
  return out;
}

// 90° 바람개비 대칭: 가운데 기준 좌표 (dx, dy) 를 (−dy, dx) 로 돌려도 같은 값이 나오게, 늘 첫 사분면(u > 0, v ≥ 0)으로 돌려서 모양 함수에 넘긴다
function canon(dx, dy) {
  let u = dx;
  let v = dy;
  for (let k = 0; k < 4 && !(u > 0 && v >= 0) && (u !== 0 || v !== 0); k++) [u, v] = [v, -u];
  return [u, v];
}

// 시작 칸 둘레 (체비쇼프 MAP_SPAWN_CLEAR 칸 안). 모서리 4곳은 늘, 변 가운데 4곳은 그 판 크기를 5명 이상이 쓸 때만 (작은 판을 다 비우지 않게).
// 모서리끼리·변 가운데끼리 90° 돌리면 겹쳐서 바람개비 대칭은 그대로
function spawnClear(W, D) {
  const out = new Set();
  const r = C.MAP_SPAWN_CLEAR;
  const most = Math.max(0, ...Object.entries(C.FIELD_SIZES).filter(([, w]) => w === W).map(([n]) => Number(n)));
  const used = most === 0 || most >= 5 ? 8 : 4; // 표에 없는 크기는 8곳 다
  for (const p of C.spawnPointsFor(W, D).slice(0, used)) {
    for (const px of new Set([Math.floor(p.x - 1e-9), Math.floor(p.x)])) {
      for (const py of new Set([Math.floor(p.y - 1e-9), Math.floor(p.y)])) {
        for (let dx = -r; dx <= r; dx++) for (let dy = -r; dy <= r; dy++) out.add((px + dx) * 100 + (py + dy));
      }
    }
  }
  return out;
}

// 첫 사분면 극좌표 (r, 각도 0~90°)
const polar = (u, v) => [Math.hypot(u, v), (Math.atan2(v, u) * 180) / Math.PI];
// 점 (pu, pv) 까지 거리
const dist = (u, v, pu, pv) => Math.hypot(u - pu, v - pv);
// 극좌표 점 (반지름 r, 각도 deg)
const at = (r, deg) => [r * Math.cos((deg * Math.PI) / 180), r * Math.sin((deg * Math.PI) / 180)];

// 첫 사분면 칸 가운데 좌표 목록 (판 크기가 짝수면 가운데가 칸 경계라 반 칸 어긋남)
function quadrantCells(W) {
  const c = (W - 1) / 2;
  const out = [];
  for (let x = 0; x < W; x++) for (let y = 0; y < W; y++) if (x - c > 0 && y - c >= 0) out.push([x - c, y - c]);
  return out;
}

// 버섯 숲: 바깥(반지름 0.42W, 각도 0°)에서 가운데 쪽(0.1W, 85°)으로 휘어 들어가는 나선을 따라, 앞 버섯과 한 칸 틈이 되는 자리마다 1칸 버섯.
// 높이는 줄 순서로 1→4층, 3층 이상 버섯엔 앞 버섯 쪽에 2층 낮은 발판 버섯이 붙음 (2단 점프로 한 번에 2층씩).
// 남은 자리엔 1층 작은 버섯을 드문드문. 시작 자리에 걸리는 칸은 뺌. [u, v, 높이]
const mushroomCache = new Map();
function mushrooms(W) {
  if (mushroomCache.has(W)) return mushroomCache.get(W);
  const off = W % 2 === 0 ? 0.5 : 0;
  const snap = (q) => Math.round(q - off) + off;
  const c = (W - 1) / 2;
  const clear = spawnClear(W, W);
  const ok = ([a, b]) => a > 0 && b >= 0 && a <= W / 2 && b <= W / 2 && !clear.has((a + c) * 100 + (b + c));
  const cheb = (p, q) => Math.max(Math.abs(p[0] - q[0]), Math.abs(p[1] - q[1]));
  const chain = [];
  for (let i = 0; i <= 400; i++) {
    const t = i / 400;
    const [x, y] = at((0.42 - 0.32 * t * t) * W, 85 * t); // 바깥에서 먼저 돌고 끝에서 안으로
    const m = [snap(x), snap(y)];
    if (chain.some((o) => cheb(m, o) < 2) || !ok(m)) continue;
    chain.push(m);
  }
  const out = chain.map(([u, v], i) => [u, v, 1 + Math.floor((i * 4) / chain.length)]);
  for (let i = 0; i < out.length; i++) {
    const m = out[i];
    if (m[2] < 3) continue;
    const prev = out[i - 1] ?? [0, 0];
    const steps = [[1, 0], [-1, 0], [0, 1], [0, -1]]
      .map(([dx, dy]) => [m[0] + dx, m[1] + dy])
      .filter((q) => ok(q) && !out.some((o) => o[0] === q[0] && o[1] === q[1]))
      .sort((p, q) => Math.hypot(p[0] - prev[0], p[1] - prev[1]) - Math.hypot(q[0] - prev[0], q[1] - prev[1]));
    if (steps.length) out.push([steps[0][0], steps[0][1], m[2] - 2]);
    else m[2] = 2; // 발판 놓을 데가 없으면 바닥에서 바로 오를 수 있게
  }
  for (let u = off || 1; u <= W / 2; u++) {
    for (let v = off; v <= W / 2; v++) {
      const r = Math.hypot(u, v);
      if (r < 0.15 * W || r > 0.45 * W) continue;
      if (Math.round(u * 7 + v * 13 + W * 3) % 10 >= 4) continue; // 자리마다 정해진 해시로 약 40%
      if (out.some((o) => cheb([u, v], o) < 2) || !ok([u, v])) continue;
      out.push([u, v, 1]);
    }
  }
  mushroomCache.set(W, out);
  return out;
}

// 수정 탑: 가운데 (칸에 맞춤)·반 너비, 둘레 계단 칸 (탑 가운데에서 본 각도 순, 바깥쪽 입구에서 시작해 3/4 바퀴)
const towerCache = new Map();
function crystalTower(W) {
  if (towerCache.has(W)) return towerCache.get(W);
  const off = W % 2 === 0 ? 0.5 : 0;
  const size = W >= 14 ? 2 : 1;
  const [x, y] = at(0.25 * W, 15);
  // 2×2 탑이면 가운데가 칸 경계 (반 칸 어긋남)
  const g = size === 2 ? 0.5 - off : off;
  const snap = (q) => Math.round(q - g) + g;
  const tu = snap(x);
  const tv = snap(y);
  const half = (size - 1) / 2 + 0.01;
  const out = Math.atan2(tv, tu); // 바깥 방향
  const clear = spawnClear(W, W);
  const c = (W - 1) / 2;
  const ring = quadrantCells(W)
    .filter(([pu, pv]) => !clear.has((pu + c) * 100 + (pv + c))) // 시작 자리에 지워지는 칸은 빼고 셈 (작은 판)
    .filter(([pu, pv]) => Math.max(Math.abs(pu - tu), Math.abs(pv - tv)) <= half + 1 && Math.max(Math.abs(pu - tu), Math.abs(pv - tv)) > half)
    .map(([pu, pv]) => [pu, pv, (Math.atan2(pv - tv, pu - tu) - out + 4 * Math.PI) % (2 * Math.PI)])
    .filter(([, , a]) => a < 1.5 * Math.PI + 0.01)
    .sort((p, q) => p[2] - q[2]);
  const t = { u: tu, v: tv, half, ring };
  towerCache.set(W, t);
  return t;
}

// 맵마다 첫 사분면 (u, v) 칸의 높이. s = W / 10
const SHAPES = {
  // 초원: 아무것도 없는 트인 들판 (기본 맵, 숨을 곳 없이 실력으로만). 테스트도 이 맵에서 빈 판을 씀
  flat() {
    return 0;
  },
  // 사막: 가운데 계단 피라미드 (위에서 보면 마름모, 3·2·1층, 한 층 너비는 판 크기에 비례) + 각도 10~40° 초승달 모래 언덕 (1층, 이웃 칸 단차가 늘 1칸 이하)
  pyramid(u, v, s, W) {
    const m = Math.abs(u) + Math.abs(v) - (W % 2 === 0 ? 1 : 0); // 마름모 (네모면 작은 판에서 모서리가 시작 자리에 깎여 절벽이 됨)
    const step = Math.max(1, 0.9 * s);
    if (m < step * 3) return 3 - Math.floor(m / step);
    const [r, a] = polar(u, v);
    const R = 0.4 * W;
    if (a >= 10 && a <= 40 && Math.abs(r - R) < 0.7 * s) return 1;
    return 0;
  },
  // 수정 동굴: 수정 탑(4층, 판이 크면 2×2) 4개, 탑 둘레를 한 바퀴 3/4 감아 오르는 1·2·3층 계단 (입구는 바깥쪽),
  // 탑에서 가운데로 3층 좁은 수정 다리 → 가운데 받침(3층)에서 네 다리가 만남
  stairs(u, v, s, W) {
    const t = crystalTower(W);
    const d = Math.max(Math.abs(u - t.u), Math.abs(v - t.v)); // 탑 가운데에서 체비쇼프 거리
    if (d <= t.half) return 4;
    if (d <= t.half + 1) {
      const i = t.ring.findIndex(([pu, pv]) => Math.abs(pu - u) < 0.01 && Math.abs(pv - v) < 0.01);
      if (i >= 0) return t.ring.length >= 3 ? 1 + Math.floor((i * 3) / t.ring.length) : 2; // 칸이 모자라면 (작은 판) 2층 발판 하나로 2단 점프
    }
    // 다리: 탑 → 가운데 (폭 1칸, 이웃 칸끼리 이어지게 조금 넉넉히)
    const len = Math.hypot(t.u, t.v);
    const along = (u * t.u + v * t.v) / len;
    const side = Math.abs(u * t.v - v * t.u) / len;
    if (along > 0 && along < len && side < 0.75) return 3;
    return Math.hypot(u, v) < Math.max(1, 0.6 * s) ? 3 : 0; // 다리가 만나는 가운데 받침
  },
  // 화산: 칼데라 벽 (반지름 0.22W~0.32W, 3층, 안쪽 사면 2층), 고개(각도 35~55°, 1층) — 분화구 안은 바닥
  bowl(u, v, s, W) {
    const [r, a] = polar(u, v);
    const r0 = 0.2 * W;
    const r1 = 0.3 * W;
    if (r < r0 - 0.6 * s || r > r1 + 0.8 * s) return 0;
    const pass = a >= 33 && a <= 52;
    if (r < r0) return pass ? 0 : 2; // 안쪽 사면
    if (r <= r1) return pass ? 1 : 3; // 벽
    return pass ? 0 : 1; // 바깥 사면
  },
  // 하늘 성: 가운데 탑 5층, 그 둘레 나선 길 (폭 2칸쯤) — 사분면마다 각도 순서대로 1층부터 4층까지 고르게 올라감 (탑까지 1층 차이),
  // 끝(각도 80° 넘음)은 끊김(빈칸) → 다음 사분면 길 시작(1층)과 떨어져 있음
  spiral(u, v, s, W) {
    const ring = (pu, pv) => {
      const [r, a] = polar(pu, pv);
      return r >= rt && r <= rt + 1.6 * s && a <= 80;
    };
    const rt = Math.max(1.1, 0.12 * W);
    if (Math.hypot(u, v) < rt) return 5;
    if (!ring(u, v)) return 0;
    // 길 칸들을 각도 순으로 세워 몇 번째인지로 층을 정함 (작은 판에서도 1·2·3·4 가 다 나오게)
    const cells = quadrantCells(W).filter(([pu, pv]) => ring(pu, pv));
    const ang = (pu, pv) => Math.atan2(pv, pu);
    const rank = cells.filter(([pu, pv]) => ang(pu, pv) < ang(u, v) - 1e-9).length;
    return 1 + Math.floor((rank * 4) / cells.length);
  },
  // 버섯 숲: 1칸 버섯 기둥 줄 (mushrooms) — 바깥에서 가운데로 휘어 들어가며 높아져 가운데 가까운 끝 버섯이 4층
  pillars(u, v, s, W) {
    for (const [px, py, h] of mushrooms(W)) if (Math.abs(u - px) < 0.01 && Math.abs(v - py) < 0.01) return h;
    return 0;
  },
  // 중세 성: 성채 성벽 (체비쇼프 0.17W~0.23W, 2층) + 모서리 망루 (3층) + 성문 (각 변 가운데 근처, 바람개비라 조금 비낌), 해자 (바닥) 고리 뒤로 판 가장자리 한 줄 바깥 성벽 1층
  fortress(u, v, s, W) {
    const m = Math.max(Math.abs(u), Math.abs(v));
    const n = Math.min(Math.abs(u), Math.abs(v));
    const w0 = 0.17 * W;
    const w1 = 0.23 * W + 0.4;
    if (m >= w0 && m <= w1) {
      if (n >= w0 - 0.2) return 3; // 모서리 망루
      if (m === u && Math.abs(v - 0.07 * W) < Math.max(0.6, 0.05 * W)) return 0; // 성문: 변마다 가운데에서 조금 비낀 자리 (바람개비)
      return 2;
    }
    if (m > W / 2 - 1) return 1; // 판 가장자리 한 줄 = 바깥 성벽 1층 (떨어지기 전에 한 번 걸림)
    return 0;
  },
};
