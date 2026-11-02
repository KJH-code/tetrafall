import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createErrorReporter, runEach } from '../shared/err-report.js';

test('같은 에러는 한 번만, 글이 바뀌면 다시 찍음', () => {
  const out = [];
  const r = createErrorReporter((...a) => out.push(a));
  assert.equal(r.report('프레임', new Error('A')), true);
  assert.equal(r.report('프레임', new Error('A')), false);
  assert.equal(r.report('프레임', new Error('B')), true);
  assert.equal(r.report('프레임', new Error('A')), true); // B 다음 A 는 새 에러
  assert.equal(out.length, 3);
});

test('runEach: 이벤트 하나가 터져도 같은 묶음의 나머지는 처리', () => {
  const seen = [], errs = [];
  const failed = runEach([1, 2, 3, 4], (e) => { if (e === 2) throw new Error('x'); seen.push(e); }, (e) => errs.push(e));
  assert.deepEqual(seen, [1, 3, 4]);
  assert.deepEqual(errs, [2]);
  assert.equal(failed, 1);
  assert.equal(runEach(undefined, () => {}, () => {}), 0);
});
