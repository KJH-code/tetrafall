// 방 나가기 확인 (shared/leave.js): 판 중에만 한 번 더 묻고, 연습·대기실·판 끝·관전은 바로
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { leaveNeedsConfirm } from '../shared/leave.js';
import { wipeKind } from '../shared/wipe.js';

test('판 중(살아 있음)만 한 번 더 묻기', () => {
  assert.equal(leaveNeedsConfirm({ phase: 'playing', practice: false, alive: true }), true);
  assert.equal(leaveNeedsConfirm({ phase: 'countdown', practice: false, alive: true }), true);
  assert.equal(leaveNeedsConfirm({ phase: 'playing', practice: true, alive: true }), false, '연습은 안 물음');
  assert.equal(leaveNeedsConfirm({ phase: 'lobby', practice: false, alive: true }), false);
  assert.equal(leaveNeedsConfirm({ phase: 'over', practice: false, alive: true }), false);
  assert.equal(leaveNeedsConfirm({ phase: 'playing', practice: false, alive: false }), false, '이미 죽어 관전 중이면 바로');
  assert.ok(C.LEAVE_CONFIRM_MS >= 1000 && C.LEAVE_CONFIRM_MS <= 6000);
});

test('방에서 나가면 메뉴로 짧은 화면 전환', () => {
  for (const from of ['lobby', 'game', 'results']) assert.equal(wipeKind(from, 'menu'), 'short', from);
});
