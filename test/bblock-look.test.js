// 건축가 블록 모습 (2026-10-30 시안 A 공사장 나무 상자): 칸 부품·연출 곡선 (shared/bblock-look.js) + 부품마다 InstancedMesh 하나라 칸이 늘어도 그리기 수 그대로 (client/bblocks.js)
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { CONFIG as C } from '../shared/config.js';
import { BB_KINDS, bblockParts, riseScale, crackOf, flashOf, bigPrep, collapseAt, bigTicks, shardCount } from '../shared/bblock-look.js';

register('./support/client-loader.mjs', import.meta.url);
globalThis.document ??= { createElement: () => ({ width: 0, height: 0, getContext: () => new Proxy({}, { get: () => () => {}, set: () => true }) }) };

test('4종 부품: 판자 상자 + 쇠 모서리 4 + 주인 색 띠, R 만 빛 판. 종류마다 다른 판자·띠, 칸 안에 들어감', () => {
  const mats = new Set();
  for (const k of BB_KINDS) {
    const parts = bblockParts(k);
    const count = (p) => parts.filter((x) => x.part === p).length;
    assert.equal(count('base'), 1, k);
    assert.equal(count('corner'), 4, k);
    assert.equal(count('band'), 1, `${k} 띠 (주인 색)`);
    assert.equal(count('plate'), k === 'big' ? 1 : 0, `${k} 빛 판`);
    mats.add(parts[0].mat);
    for (const p of parts) {
      for (let a = 0; a < 2; a++) assert.ok(Math.abs(p.at[a]) + p.size[a] / 2 <= 0.53, `${k} ${p.part} 칸 밖으로 안 나감`);
      assert.ok(p.at[2] - p.size[2] / 2 >= -0.02 && p.at[2] + p.size[2] / 2 <= 1.04, `${k} ${p.part} 높이`);
    }
  }
  assert.equal(mats.size, 3, '판자 3가지 (가로·세로·어두운 R)');
  assert.ok(C.BB_LOOK.box.third < C.BB_LOOK.box.wall, '3타 블록은 작은 상자');
  assert.ok(bblockParts('third').find((p) => p.part === 'band').size[1] < 0.3, '3타는 세로 띠');
});

test('솟기: 0 에서 자라 살짝 넘쳤다(오버슛) 1 로', () => {
  assert.ok(riseScale(0) <= 0.06);
  const peak = Math.max(...Array.from({ length: 50 }, (_, i) => riseScale(i / 50)));
  assert.ok(peak > 1.05 && peak < 1.3, `넘침 ${peak}`);
  assert.equal(riseScale(1), 1);
});

test('수명 끝: 금은 BB_CRACK_MS 전부터 0→1, 깜빡임은 BB_BLINK_MS 전부터 (끝 1/3 빠르게), 그 전엔 둘 다 없음', () => {
  assert.equal(crackOf(C.BUILDER_BLOCK_MS), 0);
  assert.equal(crackOf(C.BB_CRACK_MS + 1), 0);
  assert.ok(crackOf(C.BB_CRACK_MS / 2) > 0.4 && crackOf(C.BB_CRACK_MS / 2) < 0.6);
  assert.equal(crackOf(0), 1);
  assert.ok(C.BB_BLINK_MS < C.BB_CRACK_MS, '금이 먼저, 깜빡임은 끝 무렵');
  assert.equal(flashOf(C.BB_BLINK_MS + 1, 1000), 0);
  const on = (left) => Array.from({ length: 2000 }, (_, t) => flashOf(left, t)).filter((v) => v > 0).length;
  assert.ok(on(C.BB_BLINK_MS - 10) > 0, '깜빡임');
  const flips = (left) => Array.from({ length: 1400 }, (_, t) => flashOf(left, t)).reduce((n, v, i, a) => n + (i && v !== a[i - 1] ? 1 : 0), 0);
  assert.ok(flips(100) > flips(C.BB_BLINK_MS - 10), '끝 무렵 더 빠르게');
});

test('R 준비 (BUILDER_BIG_FUSE_MS 0.8초): 빛 판이 점점 세지고 부풂, 째깍은 점점 촘촘히, 마지막은 터지기 직전', () => {
  assert.equal(C.BUILDER_BIG_FUSE_MS, 800);
  const a = bigPrep(C.BUILDER_BIG_FUSE_MS, 0);
  const b = bigPrep(50, 0);
  assert.ok(a.k === 0 && b.k > 0.9);
  assert.ok(b.glow > a.glow + 0.4, '빛 판 세짐');
  assert.ok(b.swell > a.swell, '부풂');
  const t = bigTicks(800);
  assert.equal(t[0], 0);
  for (let i = 2; i < t.length; i++) assert.ok(t[i] - t[i - 1] <= t[i - 1] - t[i - 2], '간격이 줄어듦');
  assert.ok(t.at(-1) < 800 && t.at(-1) > 700, '마지막은 터지기 직전');
});

test('무너짐: 납작해지며 가라앉고 기울다 끝에 거의 없어짐', () => {
  const s = collapseAt(0);
  const e = collapseAt(1);
  assert.equal(s.sz, 1);
  assert.equal(s.tilt, 0);
  assert.ok(e.sz < 0.15 && e.sink > 0.1 && e.tilt > 0.1);
  assert.equal(collapseAt(2).sz, e.sz, '끝 뒤엔 그대로');
});

test('판자 조각 수: R 이 가장 많음, 그래픽 낮춤이면 BB_LOW_FX 만큼 (적어도 1)', () => {
  assert.ok(shardCount('big') > shardCount('wall') && shardCount('wall') >= shardCount('third'));
  for (const k of [...BB_KINDS, 'collapse']) {
    assert.ok(shardCount(k, true) <= shardCount(k) && shardCount(k, true) >= 1, k);
    assert.ok(Math.abs(shardCount(k, true) - shardCount(k) * C.BB_LOW_FX) <= 1, k);
  }
});

test('부품마다 InstancedMesh 하나: 칸 50개를 그려도 장면 메시 수는 그대로 (최대 7), 칸 수만큼 인스턴스, 띠는 주인 색', async () => {
  const THREE = await import('three');
  const { BuilderBlocks } = await import('../client/bblocks.js');
  const { Shards } = await import('../client/shards.js');
  const scene = new THREE.Scene();
  const bb = new BuilderBlocks(scene);
  const red = new THREE.Color(1, 0, 0);
  const blue = new THREE.Color(0, 0, 1);
  const items = [];
  for (let i = 0; i < 50; i++) items.push({ x: i % 10, y: Math.floor(i / 10), z: 0, kind: BB_KINDS[i % 4], color: i % 2 ? red : blue, sx: 1, sz: 1, crack: i / 50, flash: 0, glow: 0.5 });
  bb.draw(items, [{ x: 1, y: 0.5, z: 1, dx: 1, dy: 0 }]);
  const meshes = scene.children.filter((o) => o.isInstancedMesh && o.visible);
  assert.ok(meshes.length <= 7, `메시 ${meshes.length}개`);
  const total = (part) => bb.pools[part].im.count;
  assert.equal(total('wood') + total('woodPad') + total('woodBig'), 50, '상자 = 칸 수');
  assert.equal(total('corner'), 200);
  assert.equal(total('band'), 50);
  assert.equal(total('plate'), items.filter((b) => b.kind === 'big').length);
  assert.equal(total('strap'), 1);
  const c = new THREE.Color();
  bb.pools.band.im.getColorAt(1, c);
  assert.ok(c.equals(red), '띠 = 주인 색');
  assert.ok(bb.pools.wood.im.geometry.attributes.aCrack.array.some((v) => v > 0), '칸마다 금 값');
  // 칸이 줄면 남는 인스턴스는 안 그림, 더 늘어도 메시 수 그대로
  bb.draw(items.slice(0, 3));
  assert.equal(total('band'), 3);
  bb.draw([...items, ...items, ...items], [{ x: 1, y: 0.5, z: 1, dx: 1, dy: 0 }]);
  assert.equal(scene.children.filter((o) => o.isInstancedMesh && o.visible).length, meshes.length, '150칸도 같은 메시 수');
  // 판자 조각: InstancedMesh 하나, 최대 수를 안 넘음, 시간이 지나면 사라짐
  const sh = new Shards(scene, bb.textures.wood, (x, y, z) => z < 0);
  sh.spawn({ x: 1, y: 1, z: 1 }, null, C.BB_SHARDS.max + 50, [0xffffff]);
  sh.update(0.016);
  assert.equal(sh.im.count, C.BB_SHARDS.max);
  for (let k = 0; k < 120; k++) sh.update(0.05);
  assert.equal(sh.im.count, 0);
});
