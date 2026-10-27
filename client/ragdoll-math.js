// 액티브 래그돌 순수 계산 (three.js·cannon-es 없음, client/ragdoll.js 가 씀, 테스트 test/ragdoll.test.js)
// 쿼터니언은 {x, y, z, w}, 벡터는 {x, y, z}
import { CONFIG as C } from '../shared/config.js';

const clamp01 = (u) => Math.max(0, Math.min(1, u));
const ease = (u) => {
  const x = clamp01(u);
  return x * x * (3 - 2 * x);
};

// 모터 세기 (0~): 평소 1, 공격 중 세게, 맞은 직후·경직·낙사 중엔 힘이 빠짐. snap = 화면 자세를 목표 자세로 섞는 비율 (공격 예고·타격)
// st: { stunned, sinceStun(경직이 풀린 지 초, 없으면 Infinity), hitAge(맞은 지 초, 없으면 null), falling, act(phase 또는 null) }
export function ragdollMotor(st) {
  let motor = 1;
  let snap = 0;
  if (st.act === 'wind' || st.act === 'strike') {
    motor = C.RAGDOLL_MOTOR_ATTACK;
    snap = C.RAGDOLL_ATTACK_SNAP;
  } else if (st.act === 'rec') motor = C.RAGDOLL_MOTOR_ATTACK;
  if (st.hitAge !== null && st.hitAge !== undefined && st.hitAge < C.RAGDOLL_HIT_RECOVER_S) {
    motor = Math.min(motor, C.RAGDOLL_HIT_MOTOR + (1 - C.RAGDOLL_HIT_MOTOR) * ease(st.hitAge / C.RAGDOLL_HIT_RECOVER_S));
    snap = 0;
  }
  if (Number.isFinite(st.sinceStun) && st.sinceStun < C.RAGDOLL_STUN_RECOVER_S) {
    motor = Math.min(motor, C.RAGDOLL_STUN_MOTOR + (1 - C.RAGDOLL_STUN_MOTOR) * ease(st.sinceStun / C.RAGDOLL_STUN_RECOVER_S));
  }
  if (st.stunned) {
    motor = Math.min(motor, C.RAGDOLL_STUN_MOTOR);
    snap = 0;
  }
  if (st.falling) {
    motor = Math.min(motor, C.RAGDOLL_FALL_MOTOR);
    snap = 0;
  }
  return { motor, snap };
}

// 쿼터니언 차이 q·conj(b) 를 회전 벡터(축 × 각, 짧은 쪽)로
export function quatDiffVec(q, b, out = {}) {
  // d = q * conj(b)
  const bx = -b.x, by = -b.y, bz = -b.z, bw = b.w;
  let x = q.w * bx + q.x * bw + q.y * bz - q.z * by;
  let y = q.w * by - q.x * bz + q.y * bw + q.z * bx;
  let z = q.w * bz + q.x * by - q.y * bx + q.z * bw;
  let w = q.w * bw - q.x * bx - q.y * by - q.z * bz;
  if (w < 0) (x = -x), (y = -y), (z = -z), (w = -w); // 짧은 쪽으로
  const s = Math.hypot(x, y, z);
  if (s < 1e-9) return Object.assign(out, { x: 2 * x, y: 2 * y, z: 2 * z });
  const ang = 2 * Math.atan2(s, w);
  return Object.assign(out, { x: (x / s) * ang, y: (y / s) * ang, z: (z / s) * ang });
}

// 관절 모터: 지금 자세 q·각속도 w 에서 목표 자세 t (목표 각속도 tw) 로 가는 각가속도 (월드 기준). motor = 세기 배율
// 목표 각속도를 같이 따라가야 (feed-forward) 걷기·공격처럼 계속 움직이는 자세에 늦지 않음
const _e = {};
export function pdAngular(q, t, w, tw, motor, out = {}) {
  const e = quatDiffVec(t, q, _e);
  const kp = C.RAGDOLL_KP * motor;
  const kd = C.RAGDOLL_KD * Math.sqrt(Math.max(0, motor)); // 감쇠는 세기의 제곱근 (약해도 너무 출렁이지 않게)
  const f = Math.min(1, motor); // 힘이 빠지면 목표 움직임도 덜 따라감
  return Object.assign(out, { x: kp * e.x + kd * (tw.x * f - w.x), y: kp * e.y + kd * (tw.y * f - w.y), z: kp * e.z + kd * (tw.z * f - w.z) });
}

// 골반 끌어당기기: 판정(보간) 위치 t 에서 멀면 순간 맞춤 (snap), 아니면 스프링 가속도 (중력 보정 포함)
export function rootPull(p, v, t, tv, out = {}) {
  const dx = t.x - p.x, dy = t.y - p.y, dz = t.z - p.z;
  if (Math.hypot(dx, dy, dz) > C.RAGDOLL_MAX_DRIFT) return Object.assign(out, { snap: true, x: 0, y: 0, z: 0 });
  const kp = C.RAGDOLL_ROOT_KP, kd = C.RAGDOLL_ROOT_KD;
  return Object.assign(out, {
    snap: false,
    x: kp * dx + kd * (tv.x - v.x),
    y: kp * dy + kd * (tv.y - v.y),
    z: kp * dz + kd * (tv.z - v.z) + C.RAGDOLL_GRAVITY,
  });
}

// 팔다리·몸통 조각: 자기 목표 위치로 끌어당김 (모터 세기만큼, 중력 보정도 세기만큼). 세면 자세가 그대로 읽히고, 빠지면 관절에 매달려 휘날림
export function limbPull(p, v, t, tv, motor, out = {}) {
  const kp = C.RAGDOLL_LIN_KP * motor;
  const kd = C.RAGDOLL_LIN_KD * Math.sqrt(Math.max(0, motor));
  const f = Math.min(1, motor);
  return Object.assign(out, {
    x: kp * (t.x - p.x) + kd * (tv.x * f - v.x),
    y: kp * (t.y - p.y) + kd * (tv.y * f - v.y),
    z: kp * (t.z - p.z) + kd * (tv.z * f - v.z) + C.RAGDOLL_GRAVITY * f,
  });
}
