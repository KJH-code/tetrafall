// 걸음걸이·공중·평소 버릇 자세 (2026-10-28, three.js 없는 순수 계산, figure.js figureAnim 이 씀, 테스트 test/figure.test.js)
// 모두 목표 자세 T 만 바꿈 → 관절 스프링·래그돌 모터가 그 자세를 따라감
// T: { waistPitch, waistRoll, waistSide, neckPitch, hipsZ, shFwd[2], shOut[2], elbow[2], thFwd[2], thOut[2], knee[2] } ([오른쪽, 왼쪽])
import { CONFIG as C } from '../shared/config.js';

const ease = (u) => {
  const x = Math.max(0, Math.min(1, u));
  return x * x * (3 - 2 * x);
};

export function gaitOf(char) {
  return { ...C.FIGURE_GAIT_DEFAULT, ...(C.FIGURE_GAIT[char] || {}) };
}

// 걷기·달리기: 캐릭터별 보폭·숙임·팔·무릎·통통·뒤뚱·들썩 (G = gaitOf)
export function gaitPose(T, d, st, G) {
  const amp = Math.min(1, st.hs / C.MOVE_SPEED);
  const w = st.walk;
  for (let i = 0; i < 2; i++) {
    const ph = w + (i ? Math.PI : 0);
    T.thFwd[i] = Math.sin(ph) * C.FIGURE_WALK_LEG * amp * G.stride + G.crouch * 0.6;
    // 뒤로 차 올리는 무릎 (빠를수록 높이) + 웅크림
    T.knee[i] = (Math.max(0, -Math.cos(ph)) * C.FIGURE_WALK_KNEE + Math.max(0, -Math.sin(ph)) * 0.4) * amp * G.knee + G.crouch * 1.1;
    T.thOut[i] = G.wide;
    T.shFwd[i] = (-Math.sin(ph) * C.FIGURE_WALK_ARM * G.arm + 0.15 - G.armBack) * amp;
    T.elbow[i] = Math.max(0.05, 0.3 + (C.FIGURE_RUN_ELBOW + G.elbow) * amp + Math.max(0, -Math.sin(ph)) * 0.3 * amp * G.arm); // 앞으로 올 때 더 굽혀 펌프
    T.shOut[i] = d.spread * (1 - 0.5 * amp) + G.shrug * amp * (0.6 + 0.6 * Math.abs(Math.sin(w)));
  }
  const step = Math.abs(Math.sin(w)); // 0 = 디딤, 1 = 다리가 가장 벌어짐
  T.waistPitch = d.hunch + (C.FIGURE_RUN_LEAN + G.lean) * amp + G.shrug * amp * 0.5 * (1 - step); // 들썩: 디딜 때마다 윗몸이 앞으로 툭
  T.waistRoll = -Math.sin(w) * C.FIGURE_RUN_TWIST * amp * G.twist; // 어깨가 다리 반대로 비틂
  T.waistSide = Math.sin(w) * (0.05 + G.sway) * amp; // 디딘 다리 쪽으로 (뒤뚱이면 크게)
  T.neckPitch = -d.hunch - (C.FIGURE_RUN_LEAN + G.lean) * amp * 0.6 + G.neck * amp + Math.cos(w * 2) * 0.05 * amp; // 고개는 앞을 봄
  T.hipsZ = G.bounce * amp * (step - 0.5) * 2; // 디딜 때 가장 낮고 (쿵) 다리가 벌어질 때 높음 (통통)
}

// 공중: 오름 (무릎 접고 팔 위) → 정점 (팔다리 펼침) → 내려옴 (팔 허우적, 다리 뻗어 착지 준비). 공격 중엔 팔을 가만히
const AIR_RISE = { shFwd: [0.7, 0.7], shOut: [1.9, 1.9], elbow: [0.5, 0.5], thFwd: [1.1, 0.55], knee: [1.6, 1.1], thOut: [0.05, 0.05], waistPitch: 0.12, neckPitch: -0.2 };
const AIR_PEAK = { shFwd: [0.15, 0.15], shOut: [1.45, 1.45], elbow: [0.2, 0.2], thFwd: [0.35, 0.05], knee: [0.4, 0.3], thOut: [0.22, 0.22], waistPitch: 0, neckPitch: -0.1 };
const AIR_FALL = { shFwd: [0.5, 0.5], shOut: [1.25, 1.25], elbow: [0.4, 0.4], thFwd: [0.45, 0.3], knee: [0.2, 0.25], thOut: [0.1, 0.1], waistPitch: -0.08, neckPitch: 0.15 };
export function airPose(T, d, st, t, attacking) {
  const vz = Number.isFinite(st.vz) ? st.vz : 0;
  const r = ease(vz / C.FIGURE_AIR_VZ);
  const f = ease(-vz / C.FIGURE_AIR_VZ);
  const p = 1 - r - f;
  for (const key of Object.keys(AIR_PEAK)) {
    const mix = (k) => AIR_RISE[key][k] * r + AIR_PEAK[key][k] * p + AIR_FALL[key][k] * f;
    T[key] = Array.isArray(AIR_PEAK[key]) ? [mix(0), mix(1)] : AIR_RISE[key] * r + AIR_PEAK[key] * p + AIR_FALL[key] * f;
  }
  T.waistPitch += d.hunch;
  // 내려오는 동안 팔 허우적 (두 팔 엇갈려)
  for (let i = 0; i < 2; i++) {
    T.shOut[i] += Math.sin(t * 14 + i * 2.1) * 0.35 * f;
    T.shFwd[i] += Math.sin(t * 11 + i * Math.PI) * 0.45 * f;
  }
  if (attacking) {
    T.shOut = [0.5, 0.5];
    T.shFwd = [0.2, 0.2];
    T.elbow = [0.4, 0.4];
  }
  T.waistRoll = 0;
  T.waistSide = 0;
  T.hipsZ = 0;
}

// 공중 대시 슈퍼맨: 오른팔 앞으로 쭉, 왼팔 몸 옆, 다리 뒤로 모음, 고개 들어 앞을 봄 (몸 전체 눕힘은 render.js)
export const SUPERMAN = { shFwd: [2.9, -0.2], shOut: [0.1, 0.25], elbow: [0.05, 0.2], thFwd: [-0.3, -0.15], knee: [0.15, 0.45], thOut: [0.05, 0.05], waistPitch: -0.15, neckPitch: -0.7 };
export function overlayT(T, pose, w) {
  for (const [key, val] of Object.entries(pose)) {
    if (Array.isArray(val)) val.forEach((v, i) => (T[key][i] += (v - T[key][i]) * w));
    else T[key] += (val - T[key]) * w;
  }
}

// 가속·멈춤·방향 전환: 몸 기준 가속도만큼 기울임 (출발은 앞으로, 멈추면 관성으로 앞으로 쏠림, 꺾으면 안쪽으로)
export function accLean(T, st) {
  const L = C.FIGURE_ACC_LEAN;
  const af = Number.isFinite(st.accF) ? st.accF : 0;
  const as = Number.isFinite(st.accS) ? st.accS : 0;
  const clip = (v) => Math.max(-L.max, Math.min(L.max, v));
  T.waistPitch += clip(Math.abs(af) * L.fwd);
  T.waistSide += clip(as * L.side);
}

// 평소 버릇 (kind = FIGURE_IDLE[char].kind, u = 0~1 진행, s = 시작부터 초)
export function idlePose(T, kind, u, s, form) {
  const env = Math.sin(Math.PI * Math.min(1, u)); // 스르륵 들어갔다 나옴
  const k = Math.min(1, env * 2.5);
  const P = {};
  if (kind === 'tap') {
    // 탱크: 오른손을 넘겨 등 방패를 툭툭 (두 번)
    Object.assign(P, { shFwd: [1.6, null], shOut: [0.9, null], elbow: [2.3 + Math.max(0, Math.sin(s * 16)) * 0.35, null], neckPitch: 0.15 });
  } else if (kind === 'twirl') {
    // 닌자: 오른손 앞에서 손목째 빙글빙글 (단검 돌리기), 고개는 손을 봄
    Object.assign(P, { shFwd: [0.75 + Math.sin(s * 18) * 0.18, null], shOut: [0.35 + Math.cos(s * 18) * 0.18, null], elbow: [1.5, null], neckPitch: 0.3 });
  } else if (kind === 'shoulder') {
    // 건축가: 망치를 어깨에 척 올리고 한 번 툭 (튕김)
    Object.assign(P, { shFwd: [0.4, null], shOut: [0.6, null], elbow: [1.95 + Math.max(0, Math.sin(s * 9)) * 0.2 * (u > 0.4 ? 1 : 0), null], waistSide: -0.06 });
  } else if (kind === 'polish') {
    // 갈고리: 갈고리 든 팔을 앞으로, 다른 손으로 문질러 닦음, 고개 숙여 봄
    Object.assign(P, { shFwd: [0.85, 0.75], shOut: [0.05 + Math.sin(s * 14) * 0.18, 0.1], elbow: [1.5, 1.55], neckPitch: 0.4, waistPitch: 0.1 });
  } else if (kind === 'fiddle') {
    // 대포수: 왼손으로 어깨 위 포탄을 만지작 (오른손은 대포를 받친 채)
    Object.assign(P, { shFwd: [null, 1.2], shOut: [null, 0.6 + Math.sin(s * 11) * 0.12], elbow: [null, 2.0 + Math.sin(s * 13) * 0.2], neckPitch: 0.2, waistSide: 0.08 });
  } else if (kind === 'flex') {
    // 광전사: 앞 절반은 두 팔 힘주며 씩씩 (어깨 들썩), 뒤 절반은 목을 좌우로 꺾음
    const breath = Math.max(0, Math.sin(s * 9));
    if (u < 0.55) Object.assign(P, { shFwd: [0.3, 0.3], shOut: [1.15, 1.15], elbow: [1.9, 1.9], waistPitch: 0.15 + breath * 0.12, neckPitch: -0.1 });
    else Object.assign(P, { waistSide: (u < 0.75 ? 1 : -1) * 0.28, neckPitch: 0.1 });
  } else if (kind === 'pluck') {
    // 바드: 오른손으로 줄을 툭 튕기고 고개를 까딱 (악기 든 자세 위)
    Object.assign(P, { elbow: [1.5 + Math.max(0, Math.sin(s * 20)) * 0.7, null], shOut: [0.3 + Math.max(0, Math.sin(s * 20)) * 0.25, null], neckPitch: Math.sin(s * 10) * 0.3 + (form === 'metal' ? 0.15 : 0) });
  }
  for (const [key, val] of Object.entries(P)) {
    if (Array.isArray(val)) val.forEach((v, i) => v !== null && (T[key][i] += (v - T[key][i]) * k));
    else T[key] += (val - T[key]) * k;
  }
}
