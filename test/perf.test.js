// 성능 표시 계산 (shared/perf.js): FPS·평균·1% low·구간 평균·기타, 오래된 프레임 버림, 복사 한 줄
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { PerfWindow, worstAvg, perfLine, shortGpu } from '../shared/perf.js';

test('60fps 고른 프레임: FPS 60·평균 16.7·1% low 16.7, 구간 평균과 기타', () => {
  const w = new PerfWindow();
  const ms = 1000 / 60;
  let t = 0;
  for (let i = 0; i < 600; i++) {
    t += ms;
    w.push(t, ms, { ragdoll: 2, bodies: 3, render: 8 });
  }
  const s = w.summary(t);
  assert.ok(Math.abs(s.fps - 60) <= 1, `fps ${s.fps}`);
  assert.ok(Math.abs(s.avg - ms) < 1e-9);
  assert.ok(Math.abs(s.low - ms) < 1e-9);
  assert.equal(s.sections.ragdoll, 2);
  assert.equal(s.sections.grid, 0, '안 잰 구간은 0');
  assert.ok(Math.abs(s.other - (ms - 13)) < 1e-9, '기타 = 일한 시간(안 주면 프레임 시간) - 잰 구간 합');
});

test('기타 JS 는 프레임 간격이 아니라 그 프레임에 JS 가 일한 시간에서 잰 구간을 뺀 것', () => {
  const w = new PerfWindow();
  w.push(16, 16.7, { render: 5, ragdoll: 1 }, 9);
  const s = w.summary(16);
  assert.equal(s.work, 9);
  assert.equal(s.other, 3);
  w.push(32, 16.7, { render: 20 }, 9); // 잰 구간이 일한 시간보다 크면 (재는 오차) 0 아래로 안 감
  assert.ok(w.summary(32).other >= 0);
});

test('1% low 는 가장 느린 1% 평균 (가끔 튀는 프레임이 보임), 평균엔 묻힘', () => {
  const w = new PerfWindow();
  let t = 0;
  for (let i = 0; i < 300; i++) {
    const ms = i % 100 === 0 ? 100 : 10;
    t += ms;
    w.push(t, ms);
  }
  const s = w.summary(t);
  assert.ok(s.low >= 50, `1% low ${s.low}`);
  assert.ok(s.avg < 15);
  assert.equal(worstAvg([5, 1, 9, 3], 0.01), 9, '적어도 1개');
  assert.equal(worstAvg([], 0.01), 0);
  assert.equal(worstAvg([10, 20, 30, 40], 0.5), 35);
});

test('오래된 프레임은 PERF_LOW_MS 밖이면 버림, FPS 는 PERF_FPS_MS 안만', () => {
  const w = new PerfWindow();
  w.push(0, 500);
  w.push(C.PERF_LOW_MS + 100, 10);
  assert.equal(w.frames.length, 1, '5초 지난 느린 프레임은 버림');
  const s = w.summary(C.PERF_LOW_MS + 100);
  assert.equal(s.low, 10);
  assert.equal(s.frames, 1);
  assert.equal(new PerfWindow().summary(0).fps, 0);
});

test('복사 한 줄: 모든 구간 이름·기타·그리기·삼각형·인원·GPU·핑', () => {
  const w = new PerfWindow();
  w.push(10, 16, { ragdoll: 1, bodies: 2, grid: 0.5, hazard: 0.4, render: 9 });
  const line = perfLine(w.summary(10), { draws: 312, tris: 184000, players: 8, rag: 7, low: false, gpu: 'Test GPU', ping: '12ms', size: '1280×720' });
  for (const name of Object.values(C.PERF_SECTIONS)) assert.ok(line.includes(name), name);
  for (const want of ['FPS', '1% low', 'JS ', '기타 JS', '그리기 312', '삼각형 184k', '8명 (래그돌 7)', '그래픽 낮춤 끔', 'GPU Test GPU', '핑 12ms', '화면 1280×720']) assert.ok(line.includes(want), want);
  assert.ok(!line.includes('\n'), '한 줄');
});

test('패널 GPU 이름 줄이기: ANGLE 껍질·장치 번호·API 꼬리 떼기', () => {
  assert.equal(shortGpu('ANGLE (NVIDIA, NVIDIA GeForce RTX 3060 (0x00002504) Direct3D11 vs_5_0 ps_5_0, D3D11)'), 'NVIDIA GeForce RTX 3060');
  assert.equal(shortGpu('ANGLE (Intel, Intel(R) UHD Graphics 620 (0x00005917) Direct3D11 vs_5_0 ps_5_0, D3D11)'), 'Intel(R) UHD Graphics 620');
  assert.equal(shortGpu('ANGLE (Google, Vulkan 1.3.0 (SwiftShader Device (Subzero) (0x0000C0DE)), SwiftShader driver)'), 'Vulkan 1.3.0 (SwiftShader Device (Subzero))');
  assert.equal(shortGpu('Apple M1'), 'Apple M1');
  assert.equal(shortGpu(''), '');
});
