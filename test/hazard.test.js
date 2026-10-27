// 상승하는 위험 화면 계산 (client/hazard-field.js): 닿는 곳 거리·깊이·차오름 단계·화면 경고 세기. 모습 값은 config WORLD_THEMES.*.hazard
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { CONFIG as C } from '../shared/config.js';
import { columnAt, hazardField, riseStep, vignetteStrength, HAZARD_MARGIN } from '../client/hazard-field.js';

// W×D×H 빈 격자 + 칸 채우기
function grid(W, D, H, cells) {
  const g = new Uint8Array(W * D * H);
  for (const [x, y, z] of cells) g[(z * D + y) * W + x] = 1;
  return g;
}

test('위험 화면: 표면이 바닥 아래면 필드 안은 모두 닿음, 위면 표면 높이에 걸친 칸만 닿음', () => {
  const g = grid(4, 4, 6, [[1, 1, 0], [1, 1, 1], [2, 2, 0]]);
  assert.deepEqual(columnAt(g, 4, 4, 6, 0, 0, -0.5), { pierce: true, ground: 0 });
  assert.equal(columnAt(g, 4, 4, 6, -1, 0, -0.5).pierce, false, '필드 밖은 안 닿음');
  assert.equal(columnAt(g, 4, 4, 6, 1, 1, 1.4).pierce, true, '2층 기둥이 1.4 표면을 뚫음');
  assert.deepEqual(columnAt(g, 4, 4, 6, 2, 2, 1.4), { pierce: false, ground: 1 }, '1층 블록은 잠김 (깊이 0.4)');
  assert.deepEqual(columnAt(g, 4, 4, 6, 0, 0, 1.4), { pierce: false, ground: 0 }, '빈 칸은 바닥까지');
});

test('위험 화면: 닿는 곳 거리 표 — 뚫린 칸 0, 멀어질수록 커지고 최대에서 자름, 맞닿는 변마다 입자 자리', () => {
  const W = 4;
  const g = grid(W, W, 6, [[1, 1, 0], [1, 1, 1]]);
  const f = hazardField(g, W, W, 6, 1.5, 2, 3);
  assert.equal(f.nx, (W + 2 * HAZARD_MARGIN) * 2);
  const at = (x, y) => f.dist[Math.floor((y - f.y0) * f.res) * f.nx + Math.floor((x - f.x0) * f.res)];
  assert.equal(at(1.5, 1.5), 0);
  assert.ok(at(2.75, 1.5) > 0 && at(2.75, 1.5) < at(3.75, 1.5), '멀수록 큼');
  assert.equal(at(-5, -5), 3, '최대에서 자름');
  assert.equal(f.contacts.length, 4, '기둥 하나 = 네 변');
  const low = hazardField(g, W, W, 6, -0.5, 2, 3);
  assert.equal(low.contacts.length, 4 * W, '바닥 아래면 필드 둘레가 닿는 곳');
});

test('위험 화면: 차오름 단계는 HAZARD_RISE_STEP 마다 1씩, 화면 경고는 발이 가까울수록 세고 최대를 안 넘음', () => {
  const s = C.HAZARD_RISE_STEP;
  assert.equal(riseStep(0), 0);
  assert.equal(riseStep(s - 0.01), 0);
  assert.equal(riseStep(s), 1);
  assert.equal(riseStep(-0.01), -1);
  assert.ok(vignetteStrength(C.HAZARD_VIGNETTE_DIST + 1) < 0.01, '멀면 없음');
  assert.ok(vignetteStrength(0.2) > vignetteStrength(1.5));
  assert.ok(vignetteStrength(-1, 1) <= C.HAZARD_VIGNETTE_MAX);
});

test('위험 모습: 테마 7개 모두 값이 있고 종류 5가지를 다 씀', () => {
  const styles = new Set();
  for (const [id, t] of Object.entries(C.WORLD_THEMES)) {
    const h = t.hazard;
    styles.add(h.style);
    for (const k of ['deep', 'mid', 'shallow', 'foam', 'tint', 'contact', 'vignette']) assert.equal(typeof h[k], 'number', `${id}.hazard.${k}`);
    assert.ok(h.alpha.length === 2 && h.alpha.every((a) => a > 0 && a <= 1), `${id} alpha`);
    assert.ok(h.wave[0] > 0 && h.wave[0] < 0.2, `${id} 파도는 가볍게`);
    assert.equal(h.band.length, 3);
    assert.equal(h.splash.length, 2);
    assert.equal(h.particles.length, 2);
  }
  assert.deepEqual([...styles].sort(), ['energy', 'lava', 'storm', 'swamp', 'water']);
  assert.ok(C.WORLD_THEMES[C.HAZARD_FALLBACK]);
  assert.ok(C.HAZARD_SEG[1] < C.HAZARD_SEG[0], '그래픽 낮춤이면 표면 격자 적게');
});
