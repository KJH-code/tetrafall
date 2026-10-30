// 건축가 블록 모습 (2026-10-30 재혁 시안 A '공사장 나무 상자'): 칸 하나를 이루는 부품과 연출 곡선. DOM·three.js 없는 순수 계산.
// client/bblocks.js 가 부품마다 InstancedMesh 하나로 그림 (그리기 수가 칸 수에 안 늘게). 테스트 test/bblock-look.test.js
import { CONFIG as C } from './config.js';

export const BB_KINDS = ['wall', 'pad', 'third', 'big'];

// 칸 한 개의 부품. at = 칸 바닥 가운데에서 부품 가운데까지 (x, y, z), size = (x, y, z) 크기, part = 그릴 묶음
// base: 판자 상자 (재질 mat), corner: 쇠 모서리, band: 공사 줄무늬 띠 (주인 색), plate: R 위 빛 판
export function bblockParts(kind) {
  const L = C.BB_LOOK;
  const s = L.box[kind] ?? L.box.wall;
  const out = [{ part: 'base', mat: kind === 'pad' ? 'woodPad' : kind === 'big' ? 'woodBig' : 'wood', at: [0, 0, s / 2], size: [s, s, s] }];
  const c = L.corner;
  const big = kind === 'big';
  for (const [sx, sy] of [[1, 1], [-1, 1], [1, -1], [-1, -1]]) {
    const o = big ? 0.44 : s / 2 - 0.04;
    out.push({ part: 'corner', at: [sx * o, sy * o, s / 2], size: [c, c, s + 0.02] });
  }
  const b = L.band[kind] || L.band.wall;
  if (kind === 'third') out.push({ part: 'band', at: [0, 0, s / 2], size: [s + 0.03, b.w, s + 0.03] });
  else out.push({ part: 'band', at: [0, 0, s * b.z], size: [s + 0.03, s + 0.03, b.h] });
  if (big) out.push({ part: 'plate', at: [0, 0, s + L.plate.h / 2 - 0.01], size: [L.plate.size, L.plate.size, L.plate.h] });
  return out;
}

// 솟기: 바닥에서 위로 자라며 살짝 넘쳤다 돌아옴 (u = 0~1, 높이 비율)
export function riseScale(u) {
  if (u >= 1) return 1;
  return Math.max(0.05, 1 + 0.25 * Math.sin(Math.PI * u) - (1 - u) ** 3);
}

// 금: 사라지기 BB_CRACK_MS 전부터 0 → 1 (left = 남은 ms)
export function crackOf(left) {
  if (!Number.isFinite(left) || left >= C.BB_CRACK_MS) return 0;
  return Math.min(1, Math.max(0, 1 - left / C.BB_CRACK_MS));
}

// 하얗게 깜빡임 (0 / 1): 사라지기 BB_BLINK_MS 전부터, 끝 1/3 은 빠르게
export function flashOf(left, now) {
  if (!Number.isFinite(left) || left >= C.BB_BLINK_MS) return 0;
  const period = left < C.BB_BLINK_MS / 3 ? 70 : 140;
  return Math.floor(now / period) % 2 ? 0.45 : 0;
}

// R 대폭발 준비 (left = 터질 때까지 ms): k 0 → 1, 부풂, 빛 판 세기 (0 평소 ~ 1 하얗게), 맥동 빨라짐
export function bigPrep(left, now) {
  const k = 1 - Math.min(1, Math.max(0, left / C.BUILDER_BIG_FUSE_MS));
  const pulse = 0.5 + 0.5 * Math.sin(now / (60 - 40 * k));
  return { k, swell: 1 + C.BB_BIG_SWELL * k * k + 0.03 * k * Math.sin(now / 30), glow: Math.min(1, 0.25 + 0.75 * k * (0.7 + 0.3 * pulse)) };
}

// 수명 끝 무너짐 (u = 0~1): 납작해지며 가라앉고 살짝 기욺. sz = 높이 비율, sink = 내려간 칸, tilt = 라디안
export function collapseAt(u) {
  const t = Math.min(1, Math.max(0, u));
  return { sz: Math.max(0.08, 1 - 0.92 * t * t), sink: 0.15 * t, tilt: 0.35 * t * (1 - 0.4 * t) };
}

// R 준비 째깍 시각 (ms, 앞에서부터 점점 촘촘히)
export function bigTicks(ms = C.BUILDER_BIG_FUSE_MS) {
  return C.BB_BIG_TICKS.map((f) => Math.round(f * ms));
}

// 터질 때·무너질 때 판자 조각 수 (그래픽 낮춤이면 줄임, 0 이상 정수)
export function shardCount(kind, low = false) {
  const n = C.BB_SHARDS[kind] ?? C.BB_SHARDS.wall;
  return Math.max(low ? 1 : 0, Math.round(n * (low ? C.BB_LOW_FX : 1)));
}
