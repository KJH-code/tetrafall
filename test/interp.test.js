// 위치 보간 (client/interp.js): 스냅샷 사이 선형 보간, 화면 시계, 순간이동
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { SnapClock, pushTrack, sampleTrack } from '../client/interp.js';
import { CONFIG as C } from '../shared/config.js';

test('두 스냅샷 사이는 선형 보간, 앞은 첫 값', () => {
  const tr = [];
  pushTrack(tr, 0, 0, 0, 0);
  pushTrack(tr, 100, 2, 0, 1);
  assert.deepEqual(sampleTrack(tr, 50, 0), { x: 1, y: 0, z: 0.5 });
  assert.deepEqual(sampleTrack(tr, -20, 0), { x: 0, y: 0, z: 0 });
  assert.equal(sampleTrack([], 0, 0), null);
});

test('다음 스냅샷이 늦으면 마지막 속도로 extrapMs 까지만 내다봄', () => {
  const tr = [];
  pushTrack(tr, 0, 0, 0, 0);
  pushTrack(tr, 100, 1, 0, 0);
  assert.ok(Math.abs(sampleTrack(tr, 120, 40).x - 1.2) < 1e-9);
  assert.ok(Math.abs(sampleTrack(tr, 500, 40).x - 1.4) < 1e-9); // 40ms 에서 멈춤
});

test('순간이동·시각이 뒤로 가면 기록을 새로 시작 (이어 그리지 않음)', () => {
  const tr = [];
  pushTrack(tr, 0, 0, 0, 0);
  pushTrack(tr, 33, C.INTERP_TELEPORT + 1, 0, 0);
  assert.equal(tr.length, 1);
  pushTrack(tr, 10, 0, 0, 0);
  assert.equal(tr.length, 1);
  assert.equal(tr[0].t, 10);
  for (let i = 1; i < 50; i++) pushTrack(tr, 10 + i * 33, 0, 0, 0);
  assert.equal(tr.length, C.INTERP_TRACK_LEN);
});

// 30Hz 스냅샷이 들쭉날쭉 도착 (0~12ms 늦음, 가끔 두 틱 묶음), 60fps 로 그림 → 일정한 속도로 달리는 몸의 프레임마다 화면 속도
function simulate(seed) {
  let s = seed;
  const rnd = () => ((s = (s * 1664525 + 1013904223) >>> 0) / 4294967296);
  const snaps = [];
  for (let k = 0; k < 120; k++) {
    if (rnd() < 0.1) continue; // 이 틱은 다음 틱과 묶여 감
    snaps.push({ time: k * 33.3, arrive: k * 33.3 + 20 + rnd() * 12 });
  }
  snaps.sort((a, b) => a.arrive - b.arrive);
  const clock = new SnapClock();
  const tr = [];
  let i = 0;
  const xs = [];
  for (let now = 300; now < 3800; now += 1000 / 60) {
    while (i < snaps.length && snaps[i].arrive <= now) {
      clock.onSnapshot(snaps[i].time, snaps[i].arrive);
      pushTrack(tr, snaps[i].time, snaps[i].time * 0.0045, 0, 0); // 4.5칸/초
      i++;
    }
    xs.push(sampleTrack(tr, clock.advance(now, 1000 / 60) - C.INTERP_DELAY_MS, C.INTERP_EXTRAP_MS).x);
  }
  const v = xs.slice(1).map((x, j) => (x - xs[j]) * 60);
  return v.slice(10);
}

test('들쭉날쭉 도착해도 화면 속도가 고름 (프레임마다 차이 평균 10% 미만)', () => {
  for (const seed of [1, 2, 3]) {
    const v = simulate(seed);
    const mean = v.reduce((a, b) => a + b, 0) / v.length;
    assert.ok(Math.abs(mean - 4.5) < 0.2, `평균 속도 ${mean}`);
    let jerk = 0;
    for (let j = 1; j < v.length; j++) jerk += Math.abs(v[j] - v[j - 1]);
    assert.ok(jerk / (v.length - 1) / mean < 0.1, `끊김 ${((jerk / (v.length - 1) / mean) * 100).toFixed(1)}%`);
    assert.ok(Math.min(...v) > 0, '멈추는 프레임 없음');
  }
});

test('화면 시계: 서버 시각이 크게 뒤로 가면 (새 방) 다시 맞춤', () => {
  const clock = new SnapClock();
  clock.onSnapshot(50000, 1000);
  assert.equal(clock.advance(1000, 16), 50000);
  clock.onSnapshot(0, 1100);
  assert.equal(clock.advance(1100, 16), 0);
});
