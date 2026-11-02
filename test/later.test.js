import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createLater } from '../shared/later.js';

// 가짜 시계: 예약만 쌓고 tick(ms) 로 앞으로 감
function fakeClock() {
  let now = 0, next = 1;
  const q = new Map();
  return {
    set: (fn, ms) => (q.set(next, { fn, at: now + ms }), next++),
    clear: (id) => q.delete(id),
    tick(ms) {
      now += ms;
      for (const [id, t] of [...q]) if (t.at <= now && q.has(id)) (q.delete(id), t.fn());
    },
  };
}

test('later: 시간 되면 한 번 실행하고 목록에서 빠짐', () => {
  const c = fakeClock(), L = createLater(c.set, c.clear);
  let n = 0;
  L.later(() => n++, 100);
  assert.equal(L.size, 1);
  c.tick(99); assert.equal(n, 0);
  c.tick(1); assert.equal(n, 1);
  assert.equal(L.size, 0);
});

test('cancelAll: 방 나가면 남은 예약이 전부 안 돎', () => {
  const c = fakeClock(), L = createLater(c.set, c.clear);
  let n = 0;
  for (let i = 0; i < 5; i++) L.later(() => n++, 50 * (i + 1));
  c.tick(60); assert.equal(n, 1);
  L.cancelAll();
  assert.equal(L.size, 0);
  c.tick(1000); assert.equal(n, 1);
  L.later(() => n++, 10); // 취소 뒤 새 예약은 정상
  c.tick(10); assert.equal(n, 2);
});
