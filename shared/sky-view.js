// 하늘 시점 (블록 마스터·블록 조종) 순수 계산 — 2026-10-30 재혁: 위에서 수직으로 보면 겹친 게 안 보임 → 비스듬한 3D + 착지 미리보기.
// three.js 없음 (client/render.js·client/sky-aids.js 가 씀 + 테스트). 수치는 config SKY_VIEW
import { CONFIG as C } from './config.js';

// 카메라 자리: 필드 가운데를 비스듬히 (화면 위쪽 = yaw 방향). 판 크기·화면 비율에 맞춰 필드 전체가 들어오게 거리 자동
// 반환 { pos: [x, y, z], look: [x, y, z], fov (세로, 도) }
export function skyPose(W, D, yaw, aspect = 16 / 9, V = C.SKY_VIEW) {
  const look = [W / 2, D / 2, V.lookZ];
  const R = Math.hypot(W, D) / 2 + V.margin; // 필드 반 대각선 + 여백 (어느 쪽으로 돌려도 들어옴)
  const vf = (V.fov * Math.PI) / 180;
  const hf = 2 * Math.atan(Math.tan(vf / 2) * aspect);
  const dist = (R / Math.sin(Math.min(vf, hf) / 2)) * V.fit;
  const el = (V.pitch * Math.PI) / 180;
  const ux = Math.cos(yaw);
  const uy = Math.sin(yaw);
  const pos = [look[0] - ux * dist * Math.cos(el), look[1] - uy * dist * Math.cos(el), look[2] + dist * Math.sin(el)];
  return { pos, look, fov: V.fov, dist };
}

// 회전 키: 90도씩 (dir +1 왼쪽으로 돎 = 반시계, -1 오른쪽). 0..2π 안으로
export function turnYaw(yaw, dir) {
  const t = yaw + (dir * Math.PI) / 2;
  const full = Math.PI * 2;
  return ((t % full) + full) % full;
}

// 보이는 yaw 를 목표로 짧은 쪽으로 부드럽게 (k = 0..1 이번 프레임 비율)
export function easeYaw(shown, target, k) {
  let d = target - shown;
  d = Math.atan2(Math.sin(d), Math.cos(d));
  return shown + d * k;
}

// 착지 미리보기 칸: 지금 블록 칸들을 서버가 계산한 착지 높이 landZ 로 내림 (블록 모양 그대로, 가장 낮은 칸이 landZ)
// 기둥: 칸마다 지금 높이에서 착지 칸 위까지 [x, y, 아래 z, 위 z]
export function landingPreview(piece) {
  const minZ = Math.min(...piece.cells.map((c) => c[2]));
  const cells = piece.cells.map(([x, y, z]) => [x, y, piece.landZ + (z - minZ)]);
  const pillars = piece.cells.map(([x, y, z], i) => [x, y, cells[i][2] + 1, z]).filter((p) => p[3] > p[2]);
  return { cells, pillars, ok: !!piece.fits };
}
