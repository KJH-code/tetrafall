// 하늘 시점 (블록 마스터·블록 조종) 순수 계산: shared/sky-view.js (비스듬한 카메라·90도 돌리기·착지 미리보기)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { skyPose, turnYaw, easeYaw, landingPreview } from '../shared/sky-view.js';
import { Game } from '../server/game.js';

const sub = (a, b) => a.map((v, i) => v - b[i]);
const dot = (a, b) => a.reduce((s, v, i) => s + v * b[i], 0);
const len = (a) => Math.hypot(...a);
const angle = (a, b) => Math.acos(Math.min(1, dot(a, b) / (len(a) * len(b))));

test('비스듬한 카메라: 판 10~19·화면 비율·네 방향 모두 필드 전체 (바닥 네 모서리) 가 시야 안', () => {
  for (const n of [10, 13, 16, 19]) {
    for (const aspect of [16 / 9, 4 / 3, 21 / 9]) {
      for (const yaw of [0, Math.PI / 2, Math.PI, (3 * Math.PI) / 2]) {
        const P = skyPose(n, n, yaw, aspect);
        const fwd = sub(P.look, P.pos);
        const vHalf = ((P.fov / 2) * Math.PI) / 180;
        const hHalf = Math.atan(Math.tan(vHalf) * aspect);
        for (const c of [[0, 0, 0], [n, 0, 0], [0, n, 0], [n, n, 0]]) {
          assert.ok(angle(sub(c, P.pos), fwd) < Math.min(vHalf, hHalf), `${n}칸 ${aspect.toFixed(2)} yaw ${yaw.toFixed(2)}: 모서리 ${c}`);
        }
      }
    }
  }
});

test('비스듬한 카메라: 위에서 SKY_VIEW.pitch 만큼 내려다보고, 화면 위쪽(yaw) 반대편에 섬', () => {
  const P = skyPose(14, 14, Math.PI / 2, 16 / 9);
  const d = sub(P.look, P.pos);
  const pitch = (Math.atan2(-d[2], Math.hypot(d[0], d[1])) * 180) / Math.PI;
  assert.ok(Math.abs(pitch - C.SKY_VIEW.pitch) < 1e-6);
  assert.ok(P.pos[1] < 7 && Math.abs(P.pos[0] - 7) < 1e-9, 'yaw +y 이면 카메라는 −y 쪽');
  assert.ok(C.SKY_VIEW.pitch > 35 && C.SKY_VIEW.pitch < 80, '수직도 수평도 아닌 3/4');
});

test('90도 돌리기: 네 번이면 제자리, 0..2π, 부드럽게 돌 땐 짧은 쪽으로', () => {
  let y = Math.PI / 2;
  for (let i = 0; i < 4; i++) {
    y = turnYaw(y, 1);
    assert.ok(y >= 0 && y < Math.PI * 2);
  }
  assert.ok(Math.abs(y - Math.PI / 2) < 1e-9);
  assert.ok(Math.abs(turnYaw(0, -1) - (3 * Math.PI) / 2) < 1e-9);
  // 0.1 → 2π-0.1 은 0 을 넘어 짧게 (−0.2)
  const e = easeYaw(0.1, Math.PI * 2 - 0.1, 0.5);
  assert.ok(Math.abs(e - 0) < 1e-9);
});

test('착지 미리보기: 서버가 보낸 착지 높이 그대로 모양을 내림, 칸마다 빛 기둥, 못 놓으면 ok false', () => {
  const piece = { cells: [[3, 3, 9], [4, 3, 9], [5, 3, 9], [4, 4, 9]], landZ: 2, fits: true };
  const { cells, pillars, ok } = landingPreview(piece);
  assert.deepEqual(cells, [[3, 3, 2], [4, 3, 2], [5, 3, 2], [4, 4, 2]]);
  assert.deepEqual(pillars[0], [3, 3, 3, 9], '착지 칸 바로 위부터 지금 칸까지');
  assert.equal(ok, true);
  assert.equal(landingPreview({ ...piece, fits: false }).ok, false);
  assert.equal(landingPreview({ ...piece, cells: piece.cells.map(([x, y]) => [x, y, 2]) }).pillars.length, 0, '이미 착지 높이면 기둥 없음');
});

test('착지 미리보기 = 서버 착지 판정: 실제 게임 블록 (지형 위·마스터 탑 제한)', () => {
  const g = new Game(() => {}, { characters: false });
  g.setMode('master');
  for (const [x, y, h] of [[4, 4, 3], [5, 4, 1]]) for (let z = 0; z < h; z++) (g.grid[g.idx(x, y, z)] = 1);
  const piece = g.makePiece('T', 0, 4, 4, g.H - 2);
  piece.phase = 'control';
  g.updateLanding(piece);
  const world = g.pieceWorldCells(piece);
  const { cells } = landingPreview({ cells: world, landZ: piece.landZ, fits: piece.fits });
  const top = Math.max(...world.map(([x, y]) => g.columnTop(x, y)));
  for (const [, , z] of cells) assert.equal(z, top, '가장 높은 기둥 위');
  // 아무것도 없는 곳 한가운데 높게 쌓인 기둥 위면 탑 제한으로 못 놓음 (빨강)
  for (let z = 0; z < 6; z++) g.grid[g.idx(8, 8, z)] = 1;
  const tall = g.makePiece('O', 0, 8, 8, g.H - 2);
  tall.phase = 'control';
  g.updateLanding(tall);
  assert.equal(landingPreview({ cells: g.pieceWorldCells(tall), landZ: tall.landZ, fits: tall.fits }).ok, false);
});
