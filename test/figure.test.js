// 몸 모양 수치 (client/figure.js 는 three.js 라 여기선 config 만): 공격 비틂 골반 나눔·광전사 근육 홈 색·1인칭 크기
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';

test('공격 비틂은 골반이 일부만 나눠 받음 (허리도 돌아야 휘두름이 읽힘)', () => {
  assert.ok(C.FIGURE_HIP_TWIST > 0 && C.FIGURE_HIP_TWIST < 0.5);
  assert.ok(C.FIGURE_HIP_TWIST_FOLLOW > 0);
});

test('광전사 근육 사이 홈은 피부색보다 어둡지만 검지 않음', () => {
  assert.ok(C.FIGURE_MUSCLE_SHADE > 0.3 && C.FIGURE_MUSCLE_SHADE < 1);
});

test('광전사 체형·1인칭 크기 설정이 있음', () => {
  assert.equal(C.FIGURE_BODY.berserker, 'brute');
  assert.ok(C.VM_SIZE.berserker > 0 && C.VM_SIZE.berserker < 1);
});

// 걸음걸이·공중·평소 버릇 (client/figure-pose.js, 순수 계산)
import { gaitOf, gaitPose, airPose, accLean, idlePose, overlayT, SUPERMAN } from '../client/figure-pose.js';
const D = { hunch: 0.1, spread: 0.22 };
const rest = () => ({ waistPitch: 0, waistRoll: 0, waistSide: 0, neckPitch: 0, hipsZ: 0, shFwd: [0, 0], shOut: [0.2, 0.2], elbow: [0.15, 0.15], thFwd: [0, 0], thOut: [0, 0], knee: [0, 0] });
const run = (char, walk = 1, hs = C.MOVE_SPEED) => {
  const T = rest();
  gaitPose(T, D, { hs, walk }, gaitOf(char));
  return T;
};

test('걸음걸이: 8명 모두 표가 있고 칸 이름은 기본값에 있는 것만', () => {
  for (const ch of C.FIGURE_CHARS) assert.ok(C.FIGURE_GAIT[ch], ch);
  for (const [ch, g] of Object.entries(C.FIGURE_GAIT)) for (const k of Object.keys(g)) assert.ok(k in C.FIGURE_GAIT_DEFAULT, `${ch}.${k}`);
  const G = (ch) => gaitOf(ch);
  assert.ok(G('tank').freq < 1 && G('tank').stride < 1 && G('tank').bounce > G('ninja').bounce, '탱크 쿵쿵');
  assert.ok(G('cannon').freq > G('tank').freq && G('cannon').stride < G('ninja').stride, '대포수 종종');
  assert.ok(G('hook').sway > G('ninja').sway && G('hook').wide > 0, '갈고리 뒤뚱');
  assert.ok(G('berserker').shrug > 0 && G('hunter').crouch > 0, '광전사 들썩·사냥꾼 웅크림');
});

test('걸음걸이 자세: 닌자는 팔을 뒤로·숙임, 사냥꾼은 무릎 굽힘, 디딜 때 엉덩이가 가장 낮음', () => {
  const nj = run('ninja');
  assert.ok(nj.shFwd[0] < 0 && nj.shFwd[1] < 0, '닌자 팔 뒤로');
  assert.ok(nj.waistPitch > run('tank').waistPitch, '닌자가 더 숙임');
  assert.ok(Math.min(...run('hunter', 0).knee) > 0.4, '사냥꾼 웅크림');
  const tankStep = run('tank', 0).hipsZ; // 디딤
  const tankMid = run('tank', Math.PI / 2).hipsZ; // 다리 벌어짐
  assert.ok(tankStep < 0 && tankMid > 0, '쿵: 디딜 때 낮게');
  // 멈추면 (hs 0) 걸음 흔들림 없음
  const still = run('bard', 1, 0);
  assert.ok(Math.abs(still.hipsZ) < 1e-12 && Math.abs(still.waistRoll) < 1e-12);
});

test('공중 자세: 오름은 무릎 접고 팔 위, 내려옴은 다리 뻗음, 공격 중엔 팔 가만히', () => {
  const at = (vz, attacking = false) => {
    const T = rest();
    airPose(T, D, { vz }, 0, attacking);
    return T;
  };
  const up = at(C.FIGURE_AIR_VZ * 2), peak = at(0), down = at(-C.FIGURE_AIR_VZ * 2);
  assert.ok(up.knee[0] > peak.knee[0] && peak.knee[0] > down.knee[0], '무릎: 오름 > 정점 > 내려옴');
  assert.ok(up.shOut[0] > peak.shOut[0], '오름: 팔 위');
  assert.ok(peak.thOut[0] > up.thOut[0], '정점: 다리 벌림');
  assert.deepEqual(at(-5, true).shOut, [0.5, 0.5]);
  const T = rest();
  overlayT(T, SUPERMAN, 1);
  assert.ok(T.shFwd[0] > 2.5 && T.thFwd[0] < 0, '슈퍼맨: 팔 앞으로 쭉, 다리 뒤로');
  assert.ok(C.FIGURE_AIR_DASH.s > 0.1 && C.FIGURE_AIR_DASH.s <= 0.3);
});

test('가속 기울임은 상한이 있고, 꺾는 쪽으로 기움', () => {
  const T = rest();
  accLean(T, { accF: 1e6, accS: -1e6 });
  assert.equal(T.waistPitch, C.FIGURE_ACC_LEAN.max);
  assert.equal(T.waistSide, -C.FIGURE_ACC_LEAN.max);
  const S = rest();
  accLean(S, { accF: NaN, accS: undefined });
  assert.equal(S.waistPitch, 0);
});

test('평소 버릇: 사냥꾼(킁킁) 빼고 7명, 동작마다 자세가 바뀌고 처음·끝은 원래 자세', () => {
  const chars = Object.keys(C.FIGURE_IDLE);
  assert.equal(chars.length, 7);
  assert.ok(!chars.includes('hunter') && chars.every((c) => C.FIGURE_CHARS.includes(c)));
  assert.ok(C.FIGURE_IDLE_AFTER > 1);
  for (const [ch, h] of Object.entries(C.FIGURE_IDLE)) {
    assert.ok(h.len < h.every, ch);
    const mid = rest();
    idlePose(mid, h.kind, 0.3, h.len * 0.3);
    assert.notDeepEqual(mid, rest(), `${ch} ${h.kind} 움직임`);
    for (const u of [0, 1]) {
      const T = rest();
      idlePose(T, h.kind, u, h.len * u);
      for (const [k, v] of Object.entries(rest())) {
        if (Array.isArray(v)) v.forEach((x, i) => assert.ok(Math.abs(T[k][i] - x) < 1e-9, `${ch} ${k}`));
        else assert.ok(Math.abs(T[k] - v) < 1e-9, `${ch} ${k}`);
      }
    }
  }
});

test('부딪힘 휘청 설정', () => {
  const B = C.FIGURE_BUMP;
  assert.ok(B.decel > 0 && B.minSpeed > 0 && B.kick > 0 && B.cooldown > 0 && B.reach > 0 && B.reach < 1);
});
