// 사냥꾼 표식 알아보기 (shared/hunt-marks.js): 칸 수·꽉 참·붙는 순간 커짐·맞은 사람 화면 가장자리
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { pickMark, markPips, pipText, popScale, edgeLevel, markBlink } from '../shared/hunt-marks.js';

test('표식 고르기: 내 것이 먼저, 없으면 가장 많은 것', () => {
  const marks = [{ by: 1, n: 1, left: 5000 }, { by: 2, n: 3, left: 5000 }];
  assert.equal(pickMark(marks, 1).by, 1);
  assert.equal(pickMark(marks, 1).mine, true);
  assert.equal(pickMark(marks, 9).by, 2);
  assert.equal(pickMark(marks, 9).mine, false);
  assert.equal(pickMark([], 1), null);
  assert.equal(pickMark(undefined, 1), null);
});

test('칸: 최대치만큼 자리를 보이고 찬 칸 수, 최대면 full', () => {
  assert.equal(C.HUNTER_MARK_MAX, 3);
  assert.deepEqual(markPips(1).pips, [true, false, false]);
  assert.equal(markPips(2).full, false);
  assert.equal(markPips(3).full, true);
  assert.equal(markPips(5).n, 3, '최대치에서 자름');
  assert.equal(pipText(2), '◆◆◇');
  assert.equal(pipText(0), '◇◇◇');
});

test('붙는 순간 커졌다 줄어듦: 처음·끝은 1, 가운데는 크고, popMs 뒤는 1', () => {
  const U = C.HUNT_MARK_UI;
  assert.equal(popScale(0), 1);
  assert.ok(popScale(U.popMs * 0.3) > 1.2);
  assert.ok(popScale(U.popMs * 0.3) > popScale(U.popMs * 0.8));
  assert.equal(popScale(U.popMs), 1);
  assert.equal(popScale(-5), 1);
});

test('맞은 사람 화면 가장자리: 표식이 많을수록 진하고, 붙은 순간 더 진하고, 깜빡이면 0', () => {
  const U = C.HUNT_MARK_UI;
  assert.equal(edgeLevel(0), 0);
  assert.ok(Math.abs(edgeLevel(1) - U.edge[0]) < 1e-9);
  assert.ok(Math.abs(edgeLevel(3) - U.edge[1]) < 1e-9);
  assert.ok(edgeLevel(2) > edgeLevel(1) && edgeLevel(2) < edgeLevel(3));
  assert.ok(edgeLevel(1, 3, 0) > edgeLevel(1, 3, U.edgePulse[1] - 1));
  assert.equal(edgeLevel(2, 3, Infinity, true), 0);
  assert.ok(edgeLevel(3, 3, 0) <= 1);
});

test('사라지기 직전 깜빡: 남은 시간이 MARK_BLINK_MS 보다 길면 안 깜빡', () => {
  assert.equal(markBlink(C.MARK_BLINK_MS + 1, C.MARK_BLINK_PERIOD_MS * 3), false);
  assert.equal(markBlink(10, C.MARK_BLINK_PERIOD_MS * 3), true);
  assert.equal(markBlink(10, C.MARK_BLINK_PERIOD_MS * 2), false);
});
