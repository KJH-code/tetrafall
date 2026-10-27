// 액티브 래그돌 순수 계산 (client/ragdoll-math.js): 모터 세기, 관절 모터 방향, 골반 끌어당김
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ragdollMotor, quatDiffVec, pdAngular, rootPull, limbPull } from '../client/ragdoll-math.js';
import { CONFIG as C } from '../shared/config.js';

const calm = { stunned: false, sinceStun: Infinity, hitAge: null, falling: false, act: null };
const zq = (a) => ({ x: 0, y: 0, z: Math.sin(a / 2), w: Math.cos(a / 2) }); // z 축으로 a 라디안
const close = (a, b, eps = 1e-6) => Math.abs(a - b) < eps;

test('평소는 모터 1, 공격 준비·타격은 세게 + 목표 자세로 섞음 (예고가 읽히게)', () => {
  assert.deepEqual(ragdollMotor(calm), { motor: 1, snap: 0 });
  for (const act of ['wind', 'strike']) {
    const m = ragdollMotor({ ...calm, act });
    assert.equal(m.motor, C.RAGDOLL_MOTOR_ATTACK);
    assert.equal(m.snap, C.RAGDOLL_ATTACK_SNAP);
  }
  assert.equal(ragdollMotor({ ...calm, act: 'rec' }).snap, 0);
});

test('맞은 순간 힘이 빠졌다가 RAGDOLL_HIT_RECOVER_S 동안 돌아옴, 공격 중에 맞아도 흐물', () => {
  assert.ok(close(ragdollMotor({ ...calm, hitAge: 0 }).motor, C.RAGDOLL_HIT_MOTOR));
  const mid = ragdollMotor({ ...calm, hitAge: C.RAGDOLL_HIT_RECOVER_S / 2 }).motor;
  assert.ok(mid > C.RAGDOLL_HIT_MOTOR && mid < 1);
  assert.equal(ragdollMotor({ ...calm, hitAge: C.RAGDOLL_HIT_RECOVER_S }).motor, 1);
  const m = ragdollMotor({ ...calm, hitAge: 0, act: 'strike' });
  assert.ok(close(m.motor, C.RAGDOLL_HIT_MOTOR));
  assert.equal(m.snap, 0);
});

test('경직·낙사 중엔 가장 약하고, 경직이 풀리면 서서히 세짐 (일어나기)', () => {
  assert.equal(ragdollMotor({ ...calm, stunned: true, act: 'wind' }).motor, C.RAGDOLL_STUN_MOTOR);
  assert.equal(ragdollMotor({ ...calm, falling: true }).motor, C.RAGDOLL_FALL_MOTOR);
  assert.ok(close(ragdollMotor({ ...calm, sinceStun: 0 }).motor, C.RAGDOLL_STUN_MOTOR));
  const half = ragdollMotor({ ...calm, sinceStun: C.RAGDOLL_STUN_RECOVER_S / 2 }).motor;
  assert.ok(half > C.RAGDOLL_STUN_MOTOR && half < 1);
});

test('쿼터니언 차이 = 짧은 쪽 회전 벡터', () => {
  const v = quatDiffVec(zq(0.5), zq(0.2));
  assert.ok(close(v.z, 0.3) && close(v.x, 0) && close(v.y, 0));
  const w = quatDiffVec(zq(-3), zq(3)); // 3 → -3 은 짧은 쪽으로 +0.28
  assert.ok(close(w.z, Math.PI * 2 - 6, 1e-9));
  assert.ok(close(quatDiffVec(zq(1), zq(1)).z, 0));
});

test('관절 모터: 목표 쪽으로 돌리고 목표 각속도로 맞춤, 세기 0 이면 힘 없음', () => {
  const Z = { x: 0, y: 0, z: 0 };
  const a = pdAngular(zq(0), zq(0.1), Z, Z, 1);
  assert.ok(close(a.z, C.RAGDOLL_KP * 0.1, 1e-6));
  const b = pdAngular(zq(0), zq(0), { x: 0, y: 0, z: 2 }, Z, 1);
  assert.ok(b.z < 0);
  // 목표가 같은 빠르기로 돌고 있으면 줄이지 않음 (feed-forward)
  assert.ok(close(pdAngular(zq(0), zq(0), { x: 0, y: 0, z: 2 }, { x: 0, y: 0, z: 2 }, 1).z, 0));
  const c = pdAngular(zq(0), zq(1), { x: 1, y: 1, z: 1 }, { x: 3, y: 0, z: 0 }, 0);
  assert.deepEqual([c.x, c.y, c.z], [0, 0, 0]);
});

test('골반: 판정 위치로 끌어당기고 (중력 보정), 너무 멀면 순간 맞춤', () => {
  const o = { x: 0, y: 0, z: 0 };
  const r = rootPull(o, o, { x: 0.1, y: 0, z: 0 }, o);
  assert.equal(r.snap, false);
  assert.ok(close(r.x, C.RAGDOLL_ROOT_KP * 0.1));
  assert.ok(close(r.z, C.RAGDOLL_GRAVITY));
  assert.equal(rootPull(o, o, { x: C.RAGDOLL_MAX_DRIFT + 0.01, y: 0, z: 0 }, o).snap, true);
  // 정지 상태에서 중력 보정과 스프링만으로 처지는 거리 = g / kp (작아야 판정에서 안 멀어짐)
  assert.ok(C.RAGDOLL_GRAVITY / C.RAGDOLL_ROOT_KP < 0.02);
});

test('팔다리 조각: 세기 1 이면 목표 위치로 + 중력 보정, 세기 0 이면 아무 힘 없음 (중력에 맡김)', () => {
  const o = { x: 0, y: 0, z: 0 };
  const a = limbPull(o, o, { x: 0, y: 0.1, z: 0 }, o, 1);
  assert.ok(close(a.y, C.RAGDOLL_LIN_KP * 0.1));
  assert.ok(close(a.z, C.RAGDOLL_GRAVITY));
  const b = limbPull(o, { x: 1, y: 0, z: 0 }, { x: 0, y: 1, z: 0 }, { x: 0, y: 3, z: 0 }, 0);
  assert.deepEqual([b.x, b.y, b.z], [0, 0, 0]);
});
