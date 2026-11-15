import { test } from 'node:test';
import assert from 'node:assert/strict';
import { ScreenClock } from '../shared/screen-clock.js';

test('화면 시계: 프레임 dt(배율 곱한 값)만큼만 감 — 슬로모션이면 느리게, 멈추면 멈춤', () => {
  const c = new ScreenClock(1000);
  c.advance(0.1); // 정상 0.1초
  assert.equal(c.now(), 1100);
  for (let i = 0; i < 10; i++) c.advance(0.1 * 0.2); // 20% 속도로 실제 1초
  assert.ok(Math.abs(c.now() - 1300) < 1e-9);
  c.advance(0); // 히트스톱
  c.advance(-1); // 이상한 값은 무시
  assert.ok(Math.abs(c.now() - 1300) < 1e-9);
});

test('연출 경과 = 시계 차이: 같은 실제 시간에 슬로모션이면 덜 진행 (대포 반동 CANNON_KICK_MS 식)', () => {
  const kickMs = 200;
  const run = (scale) => {
    const c = new ScreenClock(0);
    const at = c.now(); // 쐈을 때
    for (let i = 0; i < 6; i++) c.advance((1 / 60) * scale * 5); // 실제 ≈ 83ms
    return Math.max(0, 1 - (c.now() - at) / kickMs);
  };
  assert.ok(run(0.2) > run(1), '슬로모션이면 반동이 더 오래 남음');
});
