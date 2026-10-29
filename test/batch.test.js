// 그리기 수 줄이기 (client/batch.js · instpool.js · effects.js 파편): 실제 8명 몸을 합쳐서
// 조각 수·뼈 번호가 몸과 맞는지, 어떤 자세에서도 합친 정점이 원래 조각 자리 그대로인지, 안 보임·재질 바뀜·색·발광·반투명 정렬·복제가 예전처럼 되는지
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { register } from 'node:module';
import { readFileSync } from 'node:fs';

register('./support/client-loader.mjs', import.meta.url); // client/ 의 '/shared/…' 주소를 파일로
// 체크 무늬 천 텍스처가 캔버스를 만듦 → 그리지 않는 가짜 캔버스
globalThis.document ??= { createElement: () => ({ width: 0, height: 0, getContext: () => new Proxy({}, { get: () => () => {}, set: () => true }) }) };

const THREE = await import('three');
const { CONFIG: C } = await import('../shared/config.js');
const { buildCharacter } = await import('../client/character.js');
const { figureAnim } = await import('../client/figure.js');
const { batchPieces, cloneBatched, paintBatched } = await import('../client/batch.js');
const { InstancePool, outlineInstancing } = await import('../client/instpool.js');
const { Effects } = await import('../client/effects.js');

const HIDE = 1 << C.BATCH_HIDE_LAYER;
const batchesOf = (root) => root.children.filter((o) => o.userData.pieceBatch);
const pieceInfo = (root) => {
  const b = batchesOf(root)[0];
  return { sk: b.skeleton, batches: batchesOf(root) };
};

// 조각 i 의 정점 v 를 합친 메시로 그렸을 때 세계 좌표 (셰이더 계산과 같음: 메시 행렬 × 묶음 역행렬 × 뼈 행렬 × 정점)
function skinnedWorld(batch, v) {
  const geo = batch.geometry;
  const bi = geo.attributes.skinIndex.getX(v);
  const bm = new THREE.Matrix4().fromArray(batch.skeleton.boneMatrices, bi * 16);
  const p = new THREE.Vector3().fromBufferAttribute(geo.attributes.position, v);
  return p.applyMatrix4(bm).applyMatrix4(batch.bindMatrixInverse).applyMatrix4(batch.matrixWorld);
}

function pose(ch, t, walking) {
  for (let k = 0; k < 5; k++) figureAnim(ch.figure, { air: false, walking, hs: walking ? 4 : 0, walk: t, t, flip: -1, emote: -1, emoteT: 0, punch: 0, dizzy: 0, whirl: -1, sniffAt: null }, 0.016);
}

// 모든 합친 정점이 원래 조각의 같은 정점 자리와 같은지 (조각마다 몇 개씩)
function assertSameShape(root, label) {
  root.updateMatrixWorld(true);
  for (const b of batchesOf(root)) {
    b.skeleton.update();
    const sk = b.skeleton;
    const geo = b.geometry;
    for (let i = 0; i < sk.bones.length; i++) {
      if (sk.owner[i] !== b || sk.loose[i]) continue;
      const piece = sk.bones[i];
      if (!sk.shown(piece)) continue;
      const [v0, n] = sk.range[i];
      for (const k of [0, Math.floor(n / 2), n - 1]) {
        const want = new THREE.Vector3().fromBufferAttribute(piece.geometry.attributes.position, k).applyMatrix4(piece.matrixWorld);
        const got = skinnedWorld(b, v0 + k);
        assert.ok(got.distanceTo(want) < 1e-5, `${label}: 조각 ${i} 정점 ${k} ${got.toArray()} ≠ ${want.toArray()}`);
        assert.equal(geo.attributes.skinIndex.getX(v0 + k), i, '뼈 번호 = 조각 번호');
      }
    }
  }
}

test('8명 몸: 조각 Mesh 수십 개 → 합친 메시 3개 이하, 합칠 수 있는 조각은 모두 정확히 한 뼈', () => {
  for (const [i, char] of C.FIGURE_CHARS.entries()) {
    const ch = buildCharacter(C.PLAYER_PALETTE[i], null, char);
    const { sk, batches } = pieceInfo(ch.group);
    assert.ok(batches.length >= 1 && batches.length <= 3, `${char}: 합친 메시 ${batches.length}개`);
    assert.deepEqual(ch.batches, batches);
    let pieces = 0;
    let verts = 0;
    ch.rig.traverse((o) => {
      // 몸(rig) 아래 조각 전부 (머리 위 조종 대기 표시처럼 혼자인 재질은 group 에 따로)
      if (o.isMesh && !o.userData.pieceBatch) {
        pieces++;
        assert.ok(o.userData.batched, `${char}: 안 합친 조각 (${o.geometry.type})`);
        assert.equal(o.layers.mask, HIDE, '합친 조각은 숨은 층');
        verts += o.geometry.attributes.position.count;
      }
    });
    assert.ok(pieces >= 70, `${char}: 조각 ${pieces}`);
    assert.equal(sk.bones.length, pieces, '조각 1개 = 뼈 1개');
    assert.equal(new Set(sk.bones).size, pieces);
    assert.equal(batches.reduce((a, b) => a + b.geometry.attributes.position.count, 0), verts, '정점 수 그대로');
    let single = 0;
    ch.group.traverse((o) => {
      if (o.isMesh && !o.userData.pieceBatch && !o.userData.batched) single++;
    });
    assert.ok(single <= 1, `${char}: 몸 밖 혼자 그리는 것 ${single} (조종 대기 표시)`);
    assert.deepEqual(ch.group.children.slice(0, batches.length), batches, '합친 메시가 맨 앞 자식');
    for (const b of batches) assert.equal(b.skeleton, sk, '한 몸은 뼈대 하나');
  }
});

test('어떤 자세든 합친 정점 = 원래 조각 정점 자리 (가만히·걷기·몸 돌림·래그돌처럼 관절 꺾기)', () => {
  for (const [i, char] of C.FIGURE_CHARS.entries()) {
    const ch = buildCharacter(C.PLAYER_PALETTE[i], null, char);
    pose(ch, 0.8, false);
    assertSameShape(ch.group, `${char} 가만히`);
    pose(ch, 0.37, true);
    ch.group.position.set(3, -2, 1.5);
    ch.group.rotation.z = 1.1;
    assertSameShape(ch.group, `${char} 걷기`);
    const f = ch.figure;
    f.waist.rotation.set(0.4, -0.3, 0.9); // 래그돌이 관절을 직접 돌리는 것처럼
    f.elbows[0].rotation.x = 1.7;
    f.knees[1].rotation.y = -1.2;
    f.neck.scale.set(1.2, 0.8, 1); // 찌그러짐
    assertSameShape(ch.group, `${char} 꺾기`);
  }
});

test('안 보이는 조각(자기·위 관절 visible=false)은 0 행렬, 다시 보이면 제자리', () => {
  const ch = buildCharacter(0x3080ff, null, 'tank');
  const { sk } = pieceInfo(ch.group);
  const hand = ch.figure.hands[0];
  const under = sk.bones.map((o, i) => [o, i]).filter(([o]) => { for (let p = o; p; p = p.parent) if (p === hand) return true; return false; });
  assert.ok(under.length > 0);
  hand.visible = false;
  ch.group.updateMatrixWorld(true);
  sk.update();
  for (const [, i] of under) assert.ok(sk.boneMatrices.slice(i * 16, i * 16 + 16).every((v) => v === 0), '손 아래 조각은 0');
  const other = sk.bones.findIndex((o) => !under.some(([u]) => u === o) && sk.shown(o));
  assert.ok(sk.boneMatrices.slice(other * 16, other * 16 + 16).some((v) => v !== 0), '다른 조각은 그대로');
  hand.visible = true;
  assertSameShape(ch.group, '다시 보임');
});

test('플레이어 색·맞음 번쩍임·경직 발광: 원래 재질 값이 바뀌면 그 조각들 정점 색·발광만 바뀜', () => {
  const ch = buildCharacter(0x3080ff, null, 'ninja');
  const { sk, batches } = pieceInfo(ch.group);
  const main = batches.find((b) => b.userData.group.sources.some((s) => s.mat === ch.bodyMaterial));
  const g = main.userData.group;
  assert.ok(g.sources.length >= 2, '피부·옷이 한 묶음');
  const skin = g.sources.find((s) => s.mat === ch.bodyMaterial);
  const cloth = g.sources.find((s) => s !== skin && s.mat.emissive);
  ch.bodyMaterial.color.setHex(0xffffff); // 경직 깜빡임
  ch.bodyMaterial.emissive.setHex(0x664400);
  ch.group.updateMatrixWorld(true); // 재질 맞추기는 행렬 갱신 때
  const col = main.geometry.attributes.color;
  const emi = main.geometry.attributes.batchEmis;
  const at = (attr, i) => new THREE.Color(attr.getX(sk.range[i][0]), attr.getY(sk.range[i][0]), attr.getZ(sk.range[i][0]));
  const near = (a, b) => Math.abs(a.r - b.r) + Math.abs(a.g - b.g) + Math.abs(a.b - b.b) < 1e-6; // 정점 값은 float32
  for (const i of skin.pieces) {
    assert.ok(near(at(col, i), ch.bodyMaterial.color), '피부 조각 = 흰색');
    assert.ok(near(at(emi, i), ch.bodyMaterial.emissive), '피부 조각 발광');
  }
  for (const i of cloth.pieces) {
    assert.ok(near(at(col, i), cloth.mat.color), '옷 조각 색 그대로');
    assert.ok(near(at(emi, i), new THREE.Color(0, 0, 0)), '옷 조각은 발광 없음');
  }
  for (const m of ch.mats) if (m.emissive) m.emissive.setHex(0xffffff); // 맞음 번쩍임 (온몸)
  ch.group.updateMatrixWorld(true);
  for (const s of g.sources) if (ch.mats.includes(s.mat)) for (const i of s.pieces) assert.ok(near(at(emi, i), new THREE.Color(1, 1, 1)));
  sk.update();
  assert.equal(sk.loose.reduce((a, v) => a + v, 0), 0, '색·발광은 정점 값이라 혼자 그리는 조각 없음');
});

test('조각 재질이 바뀌면(바드 폼 몸통) 그 조각만 혼자 그림, 돌아오면 다시 합침 · 테두리 패스(재질을 잠깐 바꿈)는 무시', () => {
  const ch = buildCharacter(0x3080ff, null, 'bard');
  const { sk, batches } = pieceInfo(ch.group);
  const torso = ch.figure.torso;
  const i = sk.bones.indexOf(torso);
  assert.ok(i >= 0);
  ch.figure.setForm('metal');
  ch.group.updateMatrixWorld(true);
  sk.update();
  assert.equal(sk.loose[i], 1);
  assert.equal(torso.layers.mask, 1, '혼자 그림 (층 0)');
  assert.ok(sk.boneMatrices.slice(i * 16, i * 16 + 16).every((v) => v === 0), '합친 메시에선 안 그림');
  assert.equal(sk.loose.reduce((a, v) => a + v, 0), 1, '다른 조각은 그대로 합침');
  // 테두리 패스: OutlineEffect 가 모든 메시 재질을 ShaderMaterial 로 바꿈 → 상태 그대로
  const outline = new THREE.ShaderMaterial();
  const saved = new Map();
  ch.group.traverse((o) => {
    if (o.isMesh) {
      saved.set(o, o.material);
      o.material = outline;
    }
  });
  ch.group.updateMatrixWorld(true);
  sk.update();
  assert.equal(sk.loose.reduce((a, v) => a + v, 0), 1, '테두리 패스에선 안 바뀜');
  for (const [o, m] of saved) o.material = m;
  ch.figure.setForm('bard');
  ch.group.updateMatrixWorld(true);
  sk.update();
  assert.equal(sk.loose[i], 0);
  assert.equal(torso.layers.mask, HIDE);
  assert.ok(batches.every((b) => b.material === b.userData.group.mat));
});

test('반투명(유령화·무적): 묶음 안 조각을 카메라에서 먼 것부터 그리게 삼각형 순서 정렬, 불투명이면 원래 순서', () => {
  const ch = buildCharacter(0x3080ff, null, 'tank');
  const { sk, batches } = pieceInfo(ch.group);
  const main = batches.reduce((a, b) => (b.userData.group.order.length > a.userData.group.order.length ? b : a));
  const g = main.userData.group;
  const cam = new THREE.PerspectiveCamera(50, 1, 0.1, 100);
  cam.up.set(0, 0, 1);
  cam.position.set(6, -2, 2);
  cam.lookAt(0, 0, 0.8);
  cam.updateMatrixWorld(true);
  sk.cam = cam;
  for (const m of ch.mats) {
    m.transparent = true;
    m.opacity = 0.4;
  }
  ch.group.updateMatrixWorld(true);
  sk.update();
  assert.ok(g.see && g.sorted);
  const idx = main.geometry.index.array;
  // 정렬된 첫 조각 삼각형 = 가장 먼 조각
  const far = g.order[0];
  assert.deepEqual([...idx.slice(0, far.n)], [...g.base.slice(far.i0, far.i0 + far.n)]);
  for (let k = 1; k < g.order.length; k++) assert.ok(g.order[k - 1].z >= g.order[k].z, '먼 것부터');
  assert.equal([...idx].sort((a, b) => a - b).join(), [...g.base].sort((a, b) => a - b).join(), '삼각형은 그대로 (순서만)');
  // 반투명은 render.js 가 몸 재질(mats)에만 줌 → 그 조각은 합친 채 정렬, 같은 묶음의 다른 재질(손에 든 것 등)은 불투명 그대로라 혼자 그림 (예전처럼)
  // (묶음 기준 재질과 투명도가 다른 조각만 혼자)
  sk.bones.forEach((o, i) => {
    const ref = sk.owner[i].userData.group.sources[0].mat;
    assert.equal(sk.loose[i], ch.mats.includes(sk.src[i]) === ch.mats.includes(ref) ? 0 : 1, `조각 ${i}`);
  });
  assert.ok(sk.loose.reduce((a, v) => a + v, 0) <= 6, '혼자 그리는 건 몇 개뿐');
  for (const m of ch.mats) {
    m.transparent = false;
    m.opacity = 1;
  }
  ch.group.updateMatrixWorld(true);
  sk.update();
  assert.ok(!g.sorted);
  assert.deepEqual([...main.geometry.index.array], [...g.base], '원래 순서');
});

test('복제(압사 납작 몸·잔상): 복제본 조각을 따라감, 원본·삼각형 순서·정점 색과 따로 · 잔상 한 색으로 칠해도 합친 채', () => {
  const ch = buildCharacter(0x3080ff, null, 'hook');
  pose(ch, 0.5, true);
  const copy = cloneBatched(ch.group);
  const cb = batchesOf(copy);
  assert.equal(cb.length, ch.batches.length);
  for (const b of cb) {
    for (const o of b.skeleton.bones) {
      let inCopy = false;
      for (let p = o; p; p = p.parent) if (p === copy) inCopy = true;
      assert.ok(inCopy, '복제본 뼈는 복제본 조각');
    }
    assert.notEqual(b.geometry.index, ch.batches[cb.indexOf(b)].geometry.index, '삼각형 순서는 따로');
  }
  copy.position.set(5, 5, 0);
  copy.scale.set(1.5, 1.5, 0.2);
  assertSameShape(copy, '복제본 납작');
  assertSameShape(ch.group, '원본 그대로');
  const mat = new THREE.MeshBasicMaterial({ color: 0xff00ff, transparent: true, opacity: 0.4, depthWrite: false });
  paintBatched(copy, mat);
  copy.updateMatrixWorld(true);
  const sk = cb[0].skeleton;
  sk.update();
  assert.equal(sk.loose.reduce((a, v) => a + v, 0), 0, '잔상도 합쳐 그림');
  assert.ok(cb.every((b) => b.material === mat));
  assert.ok(ch.batches.every((b) => b.material !== mat), '원본 재질 그대로');
});

test('거울상 조각(음수 크기)은 삼각형 감김을 뒤집어 앞면 그대로', () => {
  const root = new THREE.Group();
  const mat = new THREE.MeshToonMaterial({ color: 0xff0000 });
  const a = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), mat);
  const b = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), mat);
  b.scale.set(-1, 1, 1);
  root.add(a, b);
  const [batch] = batchPieces(root);
  const n = a.geometry.index.count;
  const idx = batch.geometry.index.array;
  const off = a.geometry.attributes.position.count;
  for (let j = 0; j < n; j += 3) {
    assert.deepEqual([idx[j], idx[j + 1], idx[j + 2]], [a.geometry.index.getX(j), a.geometry.index.getX(j + 1), a.geometry.index.getX(j + 2)]);
    assert.deepEqual([idx[n + j], idx[n + j + 1], idx[n + j + 2]], [off + b.geometry.index.getX(j), off + b.geometry.index.getX(j + 2), off + b.geometry.index.getX(j + 1)]);
  }
});

test('떨어지는 블록 칸·그림자 칸: 재질마다 InstancedMesh 하나, 모자라면 늘림, 안 쓰는 재질은 숨김', () => {
  const scene = new THREE.Scene();
  const pool = new InstancePool(scene, new THREE.BoxGeometry(1, 1, 1));
  const m1 = new THREE.MeshToonMaterial();
  const m2 = new THREE.MeshToonMaterial();
  const slot = (mat, x, vis = true) => {
    const o = new THREE.Object3D();
    o.material = mat;
    o.position.set(x, 0, 0);
    o.visible = vis;
    return o;
  };
  const slots = [slot(m1, 0), slot(m1, 1), slot(m2, 2), slot(m1, 3, false)];
  pool.flush(slots);
  assert.equal(scene.children.length, 2, '재질 2개 = 메시 2개');
  assert.equal(pool.meshes.get(m1).count, 2, '안 보이는 칸은 빼고');
  assert.equal(pool.meshes.get(m2).count, 1);
  const mtx = new THREE.Matrix4();
  pool.meshes.get(m1).getMatrixAt(1, mtx);
  assert.equal(new THREE.Vector3().setFromMatrixPosition(mtx).x, 1);
  const many = Array.from({ length: C.INSTANCE_POOL_MIN * 3 }, (_, i) => slot(m1, i));
  pool.flush(many);
  assert.equal(pool.meshes.get(m1).count, many.length, '늘림');
  assert.equal(pool.meshes.get(m2).visible, false, '안 쓰는 재질은 숨김');
  assert.equal(scene.children.filter((o) => o.isInstancedMesh).length, 2, '옛 메시는 치움');
});

test('OutlineEffect 테두리 셰이더 고치기: three 원본 줄이 그대로 있어야 인스턴스 위치를 씀 (three 를 올리면 확인)', () => {
  const src = readFileSync(new URL('../node_modules/three/examples/jsm/effects/OutlineEffect.js', import.meta.url), 'utf8');
  assert.ok(src.includes("vec4 pos2 = projectionMatrix * modelViewMatrix * vec4( skinned.xyz + normal, 1.0 );"));
  const mat = new THREE.ShaderMaterial({ vertexShader: 'void main(){ vec4 pos2 = projectionMatrix * modelViewMatrix * vec4( skinned.xyz + normal, 1.0 ); }' });
  outlineInstancing(null, null, null, null, mat);
  assert.ok(mat.vertexShader.includes('instanceMatrix * p2') && mat.vertexShader.includes('#ifdef USE_INSTANCING'));
  const v = mat.version;
  outlineInstancing(null, null, null, null, mat);
  assert.equal(mat.version, v, '한 번만');
  const toon = new THREE.MeshToonMaterial();
  outlineInstancing(null, null, null, null, toon);
  assert.ok(!toon.userData.instOutline, '보통 재질은 안 건드림');
});

test('타격 파편: InstancedMesh 하나에 보이는 파편만 (색·투명도 칸마다)', () => {
  const scene = new THREE.Scene();
  const fx = new Effects(scene);
  fx.burst({ x: 1, y: 2, z: 3 }, null, 0xff0000, 5, 4, 0.1, 0.5);
  fx.burst({ x: 1, y: 2, z: 3 }, null, 0x00ff00, 3, 4, 0.1, 0.5);
  fx.update(0.016, null);
  assert.equal(scene.children.filter((o) => o.isMesh && !o.isInstancedMesh && o.visible).length, 0, '파편 Mesh 따로 없음');
  assert.equal(fx.pmesh.count, 8);
  const c = new THREE.Color();
  fx.pmesh.getColorAt(7, c);
  assert.ok(c.equals(new THREE.Color(0x00ff00)));
  assert.ok(fx.opacity.array[0] > 0 && fx.opacity.array[0] <= 1);
  for (let k = 0; k < 120; k++) fx.update(0.05, null);
  assert.equal(fx.pmesh.count, 0, '다 사라지면 0');
  assert.equal(fx.pmesh.visible, false);
});
