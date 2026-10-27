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
