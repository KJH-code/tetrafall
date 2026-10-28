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

test('전용 도발 칸 이름이 8명 + 메탈 폼 다 있고, 포즈 시간 수치가 이모트 길이 안에 들어감', () => {
  for (const ch of [...C.FIGURE_CHARS, 'metal']) assert.ok(C.EMOTE_CHAR_NAMES[ch], ch);
  assert.ok(C.POSE_IN_S > 0 && C.POSE_SNAP_S > 0 && C.POSE_OUT_S > 0);
  assert.ok(C.POSE_IN_S + C.POSE_SNAP_S + C.POSE_OUT_S < C.EMOTE_MS / 1000 - 0.5, '결정 포즈로 멈춰 있는 시간이 0.5초 넘게');
  assert.equal(C.EMOTE_CLIPS.length, C.EMOTE_NAMES.length, '로봇도 칸마다 동작');
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

// 체형 표 (FIGURE_BODIES): 캐릭터마다 실루엣이 달라야 함 (2026-10-28 재혁: "다 똑같은 막대기 몸")
const B = C.FIGURE_BODIES;
const legs = (b) => b.foot + b.shin + b.thigh;
const height = (b) => legs(b) + b.torso - b.sink + b.head; // 몸 비율 전, 숙임 무시
const KEYS = ['foot', 'shin', 'thigh', 'torso', 'chestR', 'waistR', 'depth', 'head', 'headW', 'sink', 'upper', 'lower', 'armR', 'foreR', 'legR', 'hand', 'shoulderY', 'hipY', 'hunch', 'spread'];

test('체형 표: FIGURE_BODY 가 가리키는 체형이 다 있고 값이 다 숫자', () => {
  for (const [ch, body] of Object.entries(C.FIGURE_BODY)) {
    assert.ok(B[body], `${ch} → ${body}`);
    for (const k of KEYS) assert.ok(Number.isFinite(B[body][k]), `${body}.${k}`);
    assert.ok(C.RAGDOLL_WEIGHT[body] > 0, `${body} 래그돌 무게`);
  }
});

test('건축가 (땅딸막 노동자): 보통 몸보다 키 작고 다리 짧고, 어깨 넓고 팔뚝 굵고, 배가 가슴만큼 (막대 몸 아님)', () => {
  const b = B[C.FIGURE_BODY.builder];
  const lean = B.lean;
  assert.ok(height(b) < height(lean) * 0.92, '키 작음');
  assert.ok(legs(b) < legs(lean) * 0.75, '다리 짧음');
  assert.ok(b.shoulderY > lean.shoulderY * 1.4, '어깨 넓음');
  assert.ok(b.foreR > lean.foreR * 1.7 && b.foreR >= b.armR, '팔뚝 굵음 (위팔 이상)');
  assert.ok(b.waistR > b.chestR * 0.9, '배 살짝');
  assert.ok(height(b) > height(B[C.FIGURE_BODY.cannon]), '대포수보다는 큼');
  assert.ok(C.RAGDOLL_WEIGHT[C.FIGURE_BODY.builder] > C.RAGDOLL_WEIGHT.lean, '무거움');
});

test('바드 (호리호리 음유시인): 보통 몸보다 다리 길고 가늘고 어깨 좁고, 가벼움', () => {
  const b = B[C.FIGURE_BODY.bard];
  const lean = B.lean;
  assert.ok(legs(b) > legs(lean) * 1.05, '다리 김');
  assert.ok(b.legR < lean.legR && b.armR < lean.armR, '가는 팔다리');
  assert.ok(b.shoulderY < lean.shoulderY, '좁은 어깨');
  assert.ok(height(b) > height(B[C.FIGURE_BODY.builder]) * 1.2, '건축가와 실루엣이 확 다름');
  assert.ok(C.RAGDOLL_WEIGHT[C.FIGURE_BODY.bard] < C.RAGDOLL_WEIGHT.lean, '가벼움');
  assert.ok(C.BARD_CAPE_LEN > 0 && C.BARD_HOOD_H > 0, '플레이어 색 망토·두건');
});

test('사냥꾼 (웅크린 추적자): 크게 굽은 등·늘 굽힌 무릎·앞으로 뺀 목, 긴 팔, 망토 안감', () => {
  const b = B[C.FIGURE_BODY.hunter];
  const lean = B.lean;
  assert.ok(b.hunch >= 0.5 && b.bend >= 0.5, '굽은 등·무릎');
  assert.ok(b.sink < lean.sink, '목을 앞으로 뺌');
  assert.ok(b.upper + b.lower > lean.upper + lean.lower, '긴 팔');
  assert.ok(b.hunch > B[C.FIGURE_BODY.bard].hunch + 0.4, '꼿꼿한 바드와 반대');
  assert.ok(C.HUNTER_CAPE_LEN > 0);
});

test('갈고리 (덩치 큰 선장): 위가 크고 아래가 가는 몸 — 가슴이 다리보다 훨씬 굵고, 긴 팔, 넓은 어깨', () => {
  const b = B[C.FIGURE_BODY.hook];
  const lean = B.lean;
  assert.ok(b.chestR > b.legR * 4, '큰 상체 · 가는 다리');
  assert.ok(b.chestR > lean.chestR * 1.5 && b.shoulderY > lean.shoulderY * 1.4, '술통 가슴·넓은 어깨');
  assert.ok(b.legR < lean.legR, '가는 다리');
  assert.ok(b.upper + b.lower > lean.upper + lean.lower, '긴 팔');
  assert.ok(C.HOOK_COAT_LEN > 0);
});

test('닌자 (재빠른 그림자): 가늘고 날렵, 머리는 보통 비율, 키는 예전처럼 큰 편 (치비 아님)', () => {
  const b = B[C.FIGURE_BODY.ninja];
  const lean = B.lean;
  assert.ok(Math.abs(b.headW - lean.headW) < 0.02 && b.head / b.torso < 0.7, '보통 머리');
  assert.ok(height(b) > height(lean) * 0.97, '키 큰 편');
  assert.ok(b.legR < lean.legR && b.armR < lean.armR && b.chestR < lean.chestR, '가는 몸');
  assert.ok(b.hunch > 0 && b.bend > 0, '살짝 숙인 날렵한 자세');
  assert.ok(C.NINJA_SCARF_LEN > 0);
});

test('대포수 (통통 포수 꼬마): 가장 작고, 공 같은 몸통 (배 = 가슴), 짧고 굵은 팔다리', () => {
  const b = B[C.FIGURE_BODY.cannon];
  assert.ok(b.barrel && b.waistR >= b.chestR, '공 같은 배');
  for (const [ch, body] of Object.entries(C.FIGURE_BODY)) if (ch !== 'cannon') assert.ok(height(b) < height(B[body]), `${ch} 보다 작음`);
  assert.ok(b.legR > B[C.FIGURE_BODY.builder].legR && legs(b) < legs(B[C.FIGURE_BODY.builder]), '건축가보다 다리 굵고 짧음');
  assert.ok(b.foreR > B.lean.foreR * 1.4, '굵은 팔');
  assert.ok(C.CANNON_SHORTS_GROW < 0.8, '배가 반바지 위로 튀어나옴');
});
