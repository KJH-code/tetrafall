// client/dispose.js — 장면에서 뗀 몸의 GPU 자원 풀어 주기 (감사 C3), 공유 자원은 안 풀음
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';

register('./support/client-loader.mjs', import.meta.url);
const THREE = await import('three');
const { disposeObject, collectResources, protectSet } = await import('../client/dispose.js');

// 풀린 자원 수를 세는 도움: dispose 이벤트
function watch(res, log) {
  res.addEventListener('dispose', () => log.add(res));
  return res;
}
// 사람 몸 흉내: 몸 조각(공유 지오메트리·공유 그림 + 자기 재질) + 이름표(자기 그림·스프라이트 재질) 
function body(shared, log) {
  const g = new THREE.Group();
  const mat = watch(new THREE.MeshBasicMaterial({ map: shared.tex }), log);
  g.add(new THREE.Mesh(shared.geo, mat));
  g.add(new THREE.Mesh(watch(new THREE.BoxGeometry(1, 1, 1), log), watch(new THREE.MeshBasicMaterial({ color: 0xff0000 }), log)));
  const label = watch(new THREE.Texture(), log);
  g.add(new THREE.Sprite(watch(new THREE.SpriteMaterial({ map: label }), log)));
  return g;
}

test('disposeObject: 자기 자원은 풀고 protect 에 든 공유 지오메트리·그림은 놔둠', () => {
  const log = new Set();
  const shared = { geo: watch(new THREE.SphereGeometry(1), log), tex: watch(new THREE.Texture(), log) };
  const g = body(shared, log);
  const n = disposeObject(g, protectSet([], [shared.geo, shared.tex]));
  assert.deepEqual(n, { geometries: 1, materials: 3, textures: 1 });
  assert.equal(log.has(shared.geo), false);
  assert.equal(log.has(shared.tex), false);
  assert.equal(log.size, 5);
});

test('남은 다른 사람 몸이 쓰는 자원은 protectSet(남은 몸들) 로 지켜짐', () => {
  const log = new Set();
  const shared = { geo: watch(new THREE.SphereGeometry(1), log), tex: watch(new THREE.Texture(), log) };
  const a = body(shared, log), b = body(shared, log);
  disposeObject(a, protectSet([b])); // b 가 남아 있음 → 공유 것은 놔둠
  assert.equal(log.has(shared.geo) || log.has(shared.tex), false);
  const n = disposeObject(b, protectSet([])); // 마지막 몸 → 공유 것도 풀림
  assert.equal(n.geometries, 2);
  assert.equal(log.has(shared.geo), true);
});

test('같은 자원이 두 번 나와도 한 번만 풀고, 배열 재질·없는 root 도 안전', () => {
  const geo = new THREE.BoxGeometry(1, 1, 1);
  const m1 = new THREE.MeshBasicMaterial(), m2 = new THREE.MeshBasicMaterial();
  const g = new THREE.Group();
  g.add(new THREE.Mesh(geo, [m1, m2]), new THREE.Mesh(geo, m1));
  assert.deepEqual(disposeObject(g), { geometries: 1, materials: 2, textures: 0 });
  assert.deepEqual(disposeObject(null), { geometries: 0, materials: 0, textures: 0 });
  assert.equal(collectResources(g).size, 3);
});
