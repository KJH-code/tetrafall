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
