import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setText, setAttr, setClass } from '../client/dom-diff.js';

// 쓴 횟수를 세는 가짜 요소
function fakeEl() {
  const writes = { text: 0, attr: 0, cls: 0 };
  const attrs = new Map(), cls = new Set();
  let text = '';
  return {
    writes,
    get textContent() { return text; },
    set textContent(v) { writes.text++; text = v; },
    getAttribute: (n) => (attrs.has(n) ? attrs.get(n) : null),
    setAttribute: (n, v) => { writes.attr++; attrs.set(n, v); },
    classList: { contains: (c) => cls.has(c), toggle: (c, on) => { writes.cls++; on ? cls.add(c) : cls.delete(c); } },
  };
}

test('setText: 같은 글이면 안 씀, 바뀌면 씀 (숫자도 글자로 비교)', () => {
  const el = fakeEl();
  setText(el, '12'); setText(el, 12); setText(el, '12');
  assert.equal(el.writes.text, 1);
  setText(el, '13');
  assert.equal(el.writes.text, 2);
  setText(el, ''); setText(el, ''); // 빈 글도 한 번만
  assert.equal(el.writes.text, 3);
});

test('setAttr: 같은 값이면 안 씀', () => {
  const el = fakeEl();
  for (let i = 0; i < 5; i++) setAttr(el, 'stroke-dasharray', '10 20');
  assert.equal(el.writes.attr, 1);
  setAttr(el, 'stroke-dasharray', '11 20');
  assert.equal(el.writes.attr, 2);
});

test('setClass: 이미 그 상태면 안 씀', () => {
  const el = fakeEl();
  for (let i = 0; i < 5; i++) setClass(el, 'hidden', false);
  assert.equal(el.writes.cls, 0);
  for (let i = 0; i < 5; i++) setClass(el, 'hidden', true);
  assert.equal(el.writes.cls, 1);
  setClass(el, 'hidden', false);
  assert.equal(el.writes.cls, 2);
});

test('프레임 8번 같은 HUD 값 → 쓰기 1번씩 (8명 판 매 프레임 쓰기 줄이기)', () => {
  const els = Array.from({ length: 8 }, fakeEl);
  for (let f = 0; f < 8; f++) for (const el of els) { setText(el, '0%'); setClass(el, 'dead', false); setAttr(el, 'data-x', 'a'); }
  for (const el of els) assert.deepEqual(el.writes, { text: 1, attr: 1, cls: 0 });
});
