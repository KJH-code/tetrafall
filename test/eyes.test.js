// 눈알·든 물건 재질이 캐릭터마다 따로이고 몸 재질 목록(mats)에 있는지 (감사 C6):
// render.js 는 mats 에만 유령화·무적 반투명 opacity 를 쓰므로, 공유 재질이거나 목록에 없으면 눈알·든 물건만 불투명하게 남음
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';

register('./support/client-loader.mjs', import.meta.url);
globalThis.document ??= { createElement: () => ({ width: 0, height: 0, getContext: () => new Proxy({}, { get: () => () => {}, set: () => true }) }) };

const THREE = await import('three');
const { CONFIG: C } = await import('../shared/config.js');
const { buildCharacter } = await import('../client/character.js');

// 눈알 재질: 흰색 MeshBasicMaterial 이 달린 구
const eyeMats = (ch) => {
  const out = new Set();
  ch.group.traverse((o) => {
    if (o.isMesh && o.material.isMeshBasicMaterial && o.material.color.getHex() === 0xffffff && o.geometry.type === 'SphereGeometry') out.add(o.material);
  });
  return out;
};

for (const char of C.FIGURE_CHARS) {
  test(`${char}: 눈알 재질은 몸마다 따로, 몸 재질 목록에 있음`, () => {
    const a = buildCharacter(0xff0000, null, char), b = buildCharacter(0x00ff00, null, char);
    const ea = eyeMats(a), eb = eyeMats(b);
    assert.ok(ea.size >= 1, '눈 있음');
    for (const m of ea) {
      assert.ok(a.mats.includes(m), '목록에 있음');
      assert.ok(!eb.has(m) && !b.mats.includes(m), '다른 몸과 안 나눔');
    }
    // 한 몸이 반투명이 돼도 다른 몸의 눈은 그대로
    for (const m of a.mats) { m.transparent = true; m.opacity = 0.4; }
    for (const m of eyeMats(b)) assert.equal(m.opacity, 1);
    for (const m of ea) assert.equal(m.opacity, 0.4);
  });
}
