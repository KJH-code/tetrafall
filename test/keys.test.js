// 조작 키 설정 (client/keys.js): 키 이름, 겹침, 저장값 읽기
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ACTIONS, DEFAULT_BINDS, keyLabel, normCode, conflicts, groupLabel, loadBinds } from '../client/keys.js';

test('키 설정: 기본값은 겹치지 않고, 행동마다 하나씩', () => {
  assert.deepEqual(conflicts(DEFAULT_BINDS), {});
  assert.equal(new Set(ACTIONS.map((a) => a.id)).size, ACTIONS.length);
  assert.equal(DEFAULT_BINDS.skill, 'KeyF');
  assert.equal(DEFAULT_BINDS.attack, 'Mouse0');
});

test('키 설정: 화면 이름 (키보드·마우스·묶음)', () => {
  assert.equal(keyLabel('KeyF'), 'F');
  assert.equal(keyLabel('Digit3'), '3');
  assert.equal(keyLabel('Mouse0'), '좌클릭');
  assert.equal(keyLabel('Mouse3'), '마우스 뒤');
  assert.equal(keyLabel(normCode('ShiftRight')), 'Shift');
  assert.equal(groupLabel(DEFAULT_BINDS, ['fwd', 'left', 'back', 'right']), 'WASD');
  assert.equal(groupLabel({ ...DEFAULT_BINDS, fwd: 'ArrowUp' }, ['fwd', 'left', 'back', 'right']), '↑/A/S/D');
  assert.equal(groupLabel(DEFAULT_BINDS, ['rotL', 'rotR']), 'Q/E');
});

test('키 설정: 겹치면 그 키와 행동들을 알려 줌', () => {
  const b = { ...DEFAULT_BINDS, skill: 'Mouse4', ult: 'Mouse4' };
  assert.deepEqual(conflicts(b), { Mouse4: ['skill', 'ult'] });
});

test('키 설정: 저장소가 없거나 깨졌으면 기본값, 일부만 있으면 나머지는 기본값', () => {
  assert.deepEqual(loadBinds(), DEFAULT_BINDS); // node 엔 localStorage 가 없음 → 기본값
  const store = { 'tf-keys': JSON.stringify({ skill: 'Mouse3', bogus: 'KeyZ', ult: 5 }) };
  globalThis.localStorage = { getItem: (k) => store[k] ?? null };
  try {
    const b = loadBinds();
    assert.equal(b.skill, 'Mouse3');
    assert.equal(b.ult, 'KeyR'); // 문자열이 아니면 무시
    assert.equal(b.bogus, undefined);
    store['tf-keys'] = '{깨짐';
    assert.deepEqual(loadBinds(), DEFAULT_BINDS);
  } finally {
    delete globalThis.localStorage;
  }
});
