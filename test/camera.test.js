// 관전 궤도 카메라 (shared/camera.js): 마우스 방향대로 둘레에 서고, 블록이 막으면 앞으로 당긴다
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { orbitEye, followDist } from '../shared/camera.js';

const near = (a, b, msg) => assert.ok(Math.abs(a - b) < 1e-9, `${msg}: ${a} ≈ ${b}`);
const c = { x: 5, y: 5, z: 2 };

test('궤도 카메라: yaw 쪽을 보도록 반대편 뒤에, 내려다보면 위에', () => {
  const e = orbitEye(c, 0, 0, 4); // +x 를 봄 → 카메라는 -x 쪽
  near(e.x, 1, 'x');
  near(e.y, 5, 'y');
  near(e.z, 2, 'z');
  const down = orbitEye(c, Math.PI / 2, -Math.PI / 4, 4); // +y 를 보며 45도 내려다봄
  near(down.y, 5 - 4 * Math.SQRT1_2, 'y');
  near(down.z, 2 + 4 * Math.SQRT1_2, '위로');
  near(Math.hypot(down.x - c.x, down.y - c.y, down.z - c.z), 4, '거리');
});

test('궤도 카메라: 사이를 막는 칸이 있으면 그 앞으로 당기고, 없으면 원래 거리', () => {
  // x 가 2 이하인 칸은 벽
  const wall = (x) => x < 2;
  const e = orbitEye(c, 0, 0, 6, wall, { step: 0.05, margin: 0.3 });
  assert.ok(e.x > 2, `벽 앞 (x=${e.x})`);
  assert.ok(e.dist < 3 - 0.25 && e.dist > 2.5, `당긴 거리 ${e.dist}`);
  const free = orbitEye(c, Math.PI, 0, 6, wall); // 벽 반대쪽에 카메라
  near(free.dist, 6, '안 막힘');
  // 중심이 블록 속(유령)이어도 카메라는 최소 거리만큼 뒤
  const inside = orbitEye(c, 0, 0, 6, () => true, { minDist: 0.6 });
  near(inside.dist, 0.6, '최소 거리');
});

test('3인칭 거리: 가까워질 때는 바로, 멀어질 때는 천천히 (넘치지 않음)', () => {
  near(followDist(4, 1.5, 1 / 60, 4), 1.5, '막히면 바로 당김');
  near(followDist(null, 4, 1 / 60, 4), 4, '처음은 바로');
  const back = followDist(1.5, 4, 1 / 60, 4);
  assert.ok(back > 1.5 && back < 1.7, `한 프레임엔 조금만 (${back})`);
  let d = 1.5;
  for (let i = 0; i < 120; i++) d = followDist(d, 4, 1 / 60, 4);
  assert.ok(d > 3.9 && d <= 4, `2초 뒤엔 거의 다 (${d})`);
});
