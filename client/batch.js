// 그리기 수 줄이기 (2026-10-29, 8명 판 그리기 ~1800 중 캐릭터 몸 조각이 대부분): 몸 조각 Mesh 수십 개를 SkinnedMesh 몇 개로 합친다.
// 조각 Mesh 는 그대로 남겨 '뼈'로 씀 → figureAnim·래그돌·펄럭임·조각 visible 끄기·나중에 붙인 것 모두 예전처럼 조각을 움직이면 됨.
// 조각은 BATCH_HIDE_LAYER 로 옮겨 카메라·그림자에 안 그려지고, 합친 메시가 조각의 matrixWorld 로 그 모양을 그린다 (조각 1개 = 뼈 1개, 가중치 100%).
// 재질: 색·발광만 다른 재질(피부 = 플레이어 색, 옷 색들)은 한 재질 + 정점 색·정점 발광으로 묶음 (그림·종류·테두리가 다르면 따로).
// 매 프레임 (뼈대 update = 그리기 직전): 투명도는 조각이 가장 많은 원래 재질을 따라가고, 원래 재질의 색·발광이 바뀌면 그 조각들 정점 값을 다시 칠함.
// 조각이 안 보이거나(자기·위 관절 visible=false) → 그 뼈는 0 행렬 (안 그려짐). 조각 재질이 바뀌었거나 원래 재질의 투명도가 묶음과 달라지면 그 조각만 다시 혼자 그림.
// 반투명(유령화·무적 깜빡임)이면 묶음 안 조각을 먼 것부터 그리게 삼각형 순서를 매 프레임 정렬 (따로 그릴 때 three 가 하던 정렬과 같은 기준).
// OutlineEffect 테두리도 skinning 을 지원해 같은 모양. 테스트 test/batch.test.js (실제 8명 몸으로)
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const HIDE_MASK = 1 << C.BATCH_HIDE_LAYER; // 합친 조각이 사는 층 (아무 카메라도 이 층을 안 켬)
const SHOW_MASK = 1; // 층 0 = 보통 카메라
const ZERO = new Float32Array(16);

// 합칠 수 있는 조각: 보통 Mesh (InstancedMesh·SkinnedMesh·배열 재질·morph 는 빼고), 위치·법선이 있는 것
export function batchable(o) {
  if (!o.isMesh || o.isInstancedMesh || o.isSkinnedMesh || o.userData.pieceBatch || o.userData.noBatch) return false;
  if (Array.isArray(o.material) || !o.material) return false;
  const g = o.geometry;
  if (!g || !g.attributes.position || !g.attributes.normal) return false;
  if (g.morphAttributes && Object.keys(g.morphAttributes).length) return false;
  return true;
}

// 그리는 중에 바뀌는 값 중 정점으로 못 옮기는 것 (render.js 가 매 프레임 칠함: 투명). 색·발광은 정점 값이라 빠짐
function liveKey(m) {
  return `${m.emissiveIntensity ?? ''}|${m.opacity}|${m.transparent}|${m.visible}|${m.depthWrite}|${m.side}`;
}

// 색·발광 말고 다 같은 재질이면 한 재질로 묶을 수 있음
export function mergeKey(m) {
  const id = (t) => (t ? t.uuid : '');
  const ol = m.userData.outlineParameters ? JSON.stringify(m.userData.outlineParameters) : '';
  return [m.type, id(m.map), id(m.gradientMap), id(m.alphaMap), id(m.emissiveMap), m.blending, m.flatShading, m.vertexColors, m.depthTest, m.alphaTest, m.fog, ol, liveKey(m)].join('|');
}

// 묶은 재질: 정점 색 × 흰색 = 원래 색, 발광은 정점 값 (batchEmis) 으로
function mergedMaterial(src, emis) {
  const mat = src.clone();
  mat.vertexColors = true;
  mat.color.setRGB(1, 1, 1);
  if (emis) {
    mat.onBeforeCompile = (sh) => {
      sh.vertexShader = 'attribute vec3 batchEmis;\nvarying vec3 vBatchEmis;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n\tvBatchEmis = batchEmis;');
      sh.fragmentShader = 'varying vec3 vBatchEmis;\n' + sh.fragmentShader.replace('vec3 totalEmissiveRadiance = emissive;', 'vec3 totalEmissiveRadiance = vBatchEmis;');
    };
    mat.customProgramCacheKey = () => 'batchEmis';
  }
  return mat;
}

// 재질 맞추기는 장면 행렬 갱신 때 (그리기 전 정점 값 올리기보다 먼저 → 색·발광 바뀐 것이 같은 프레임에 보임). 묶음 첫 메시만
function batchMatrixWorld(force) {
  THREE.SkinnedMesh.prototype.updateMatrixWorld.call(this, force);
  const s = this.skeleton;
  if (s instanceof PieceSkeleton && s.groups[0] && s.groups[0].mesh === this && !s.outlinePass()) s.sync();
}

// 반투명 정렬에 쓸 카메라 (그린 카메라를 기억, 다음 프레임 정렬에 씀)
function batchCamera(renderer, scene, camera) {
  if (this.skeleton) this.skeleton.cam = camera;
}

// 조각들의 뼈 행렬을 매 프레임 채우는 뼈대.
// bones[i] = 조각, owner[i] = 그 조각이 들어간 합친 메시, src[i] = 합칠 때 조각 재질, range[i] = [첫 정점, 정점 수]
// groups: 합친 메시마다 { mesh, mat, sources: [{ mat, color, emis, pieces }], base (원래 삼각형 순서), order (조각별 삼각형 자리) }
class PieceSkeleton extends THREE.Skeleton {
  constructor(bones, root, owner, src, range, groups) {
    super(bones, bones.map(() => new THREE.Matrix4()));
    this.root = root;
    this.owner = owner;
    this.src = src;
    this.range = range;
    this.groups = groups;
    this.cam = null;
    this.loose = new Uint8Array(bones.length); // 1 = 혼자 그리는 중
    for (const o of bones) o.layers.mask = HIDE_MASK;
  }

  shown(o) {
    for (let p = o; p && p !== this.root; p = p.parent) if (!p.visible) return false;
    return true;
  }

  // 정점 값 다시 칠하기 (색 3 또는 발광 3)
  paint(attr, pieces, c) {
    for (const i of pieces) {
      const [v0, n] = this.range[i];
      for (let v = v0; v < v0 + n; v++) attr.setXYZ(v, c.r, c.g, c.b);
    }
    attr.needsUpdate = true;
  }

  // 묶은 재질 맞추기: 투명도는 기준 재질(조각이 가장 많은 것)을 따라가고, 다른 원래 재질이 따로 놀면 그 조각들은 혼자 그림.
  // 원래 재질의 색·발광이 바뀌면 그 조각 정점 값을 다시 (맞음 번쩍임·경직 깜빡임·플레이어 색)
  sync() {
    for (const g of this.groups) {
      const ref = g.sources[0].mat;
      g.see = ref.transparent && ref.opacity < 1;
      g.off = null;
      if (g.mat === ref) continue; // 재질 하나 그대로 (정점 값 없음)
      const mat = g.mat;
      if (ref.emissiveIntensity !== undefined) mat.emissiveIntensity = ref.emissiveIntensity;
      mat.opacity = ref.opacity;
      mat.transparent = ref.transparent;
      mat.visible = ref.visible;
      mat.depthWrite = ref.depthWrite;
      const key = liveKey(ref);
      const geo = g.mesh.geometry;
      for (const s of g.sources) {
        if (s.mat !== ref && liveKey(s.mat) !== key) (g.off ||= new Set()).add(s.mat);
        if (s.mat.color && !s.mat.color.equals(s.color)) {
          s.color.copy(s.mat.color);
          this.paint(geo.attributes.color, s.pieces, s.color);
        }
        if (s.emis && s.mat.emissive && !s.mat.emissive.equals(s.emis)) {
          s.emis.copy(s.mat.emissive);
          this.paint(geo.attributes.batchEmis, s.pieces, s.emis);
        }
      }
    }
  }

  // OutlineEffect 의 테두리 패스: 모든 메시 재질을 테두리 재질(ShaderMaterial)로 잠깐 바꿔 그림 → 재질 비교·맞추기는 건너뛰고 앞 패스 상태 그대로
  outlinePass() {
    return this.groups.length > 0 && this.groups[0].mesh.material !== this.groups[0].mat;
  }

  update() {
    const outline = this.outlinePass();
    const { bones, boneMatrices, owner, src, loose } = this;
    for (let i = 0; i < bones.length; i++) {
      const b = bones[i];
      const g = owner[i].userData.group;
      const own = outline ? !loose[i] : b.material === src[i] && !(g && g.off && g.off.has(src[i]));
      if (!outline && !own !== !!loose[i]) {
        loose[i] = own ? 0 : 1;
        b.layers.mask = own ? HIDE_MASK : SHOW_MASK;
      }
      if (own && this.shown(b)) boneMatrices.set(b.matrixWorld.elements, i * 16);
      else boneMatrices.set(ZERO, i * 16);
    }
    if (this.boneTexture) this.boneTexture.needsUpdate = true;
    if (!outline) for (const g of this.groups) this.order(g);
  }

  // 반투명이면 조각을 카메라에서 먼 것부터 (three 의 반투명 정렬과 같은 기준: 조각 도형 경계 구 가운데의 화면 깊이, 같으면 만든 순서). 불투명이 되면 원래 순서로
  order(g) {
    const index = g.mesh.geometry.index;
    if (!g.see || !this.cam) {
      if (g.sorted) {
        index.array.set(g.base);
        index.needsUpdate = true;
        g.sorted = false;
      }
      return;
    }
    const e = this.cam.matrixWorld.elements;
    const list = g.order;
    for (const it of list) {
      const m = this.bones[it.i].matrixWorld.elements;
      const [x, y, z] = it.c; // 조각 도형 경계 구 가운데 (three 가 반투명 정렬에 쓰는 점)
      const wx = m[0] * x + m[4] * y + m[8] * z + m[12];
      const wy = m[1] * x + m[5] * y + m[9] * z + m[13];
      const wz = m[2] * x + m[6] * y + m[10] * z + m[14];
      it.z = (wx - e[12]) * -e[8] + (wy - e[13]) * -e[9] + (wz - e[14]) * -e[10];
    }
    list.sort((a, b) => b.z - a.z || a.id - b.id);
    const out = index.array;
    let k = 0;
    for (const it of list) {
      out.set(g.base.subarray(it.i0, it.i0 + it.n), k);
      k += it.n;
    }
    index.needsUpdate = true;
    g.sorted = true;
  }
}

// root 아래 합칠 수 있는 조각을 묶음. solo: 따로 묶을 재질. minPieces 보다 적은 묶음은 안 만듦 (그 조각은 예전처럼 혼자 그림).
// 합친 메시는 root 의 맨 앞 자식 (조각보다 먼저 지나가서 혼자 그릴 조각을 같은 프레임에 보이게). 반환: 합친 메시 목록
export function batchPieces(root, { solo = [], minPieces = C.BATCH_MIN_PIECES } = {}) {
  root.updateMatrixWorld(true);
  const soloSet = new Set(solo);
  const byKey = new Map();
  root.traverse((o) => {
    if (!batchable(o)) return;
    const k = soloSet.has(o.material) ? `solo:${o.material.uuid}` : mergeKey(o.material);
    if (!byKey.has(k)) byKey.set(k, []);
    byKey.get(k).push(o);
  });
  const bones = [];
  const plans = [];
  for (const list of byKey.values()) {
    if (list.length < minPieces) continue;
    plans.push({ list, first: bones.length });
    for (const o of list) bones.push(o);
  }
  if (!plans.length) return [];
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const rel = new THREE.Matrix4();
  const mirrored = (o) => rel.multiplyMatrices(inv, o.matrixWorld).determinant() < 0;
  const owner = [];
  const src = [];
  const range = [];
  const groups = [];
  const batches = [];
  for (const plan of plans) {
    const mats = [...new Set(plan.list.map((o) => o.material))];
    const sources = mats.map((sm) => ({ mat: sm, color: sm.color ? sm.color.clone() : null, emis: sm.emissive ? sm.emissive.clone() : null, pieces: [] }));
    plan.list.forEach((o, k) => sources.find((s) => s.mat === o.material).pieces.push(plan.first + k));
    sources.sort((a, b) => b.pieces.length - a.pieces.length); // 투명도 기준 = 조각이 가장 많은 재질 (소품 하나가 따로 놀아도 나머지는 묶인 채)
    const multi = mats.length > 1;
    const emis = multi && !!mats[0].emissive;
    const irange = [];
    const geo = mergePieces(plan.list, plan.first, mirrored, multi, emis, range, irange);
    const mat = multi ? mergedMaterial(sources[0].mat, emis) : mats[0];
    const m = new THREE.SkinnedMesh(geo, mat);
    m.frustumCulled = false; // 경계 구가 뼈를 안 따라감
    m.castShadow = plan.list.some((o) => o.castShadow);
    m.receiveShadow = plan.list.some((o) => o.receiveShadow);
    m.renderOrder = plan.list[0].renderOrder;
    m.userData.pieceBatch = true;
    m.onBeforeRender = batchCamera;
    m.updateMatrixWorld = batchMatrixWorld;
    const group = {
      mesh: m,
      mat, // 합친 메시 재질 (테두리 패스에선 잠깐 다른 재질)
      sources,
      off: null,
      see: false,
      base: geo.index.array.slice(), // 원래 삼각형 순서 (반투명 정렬 뒤 되돌릴 때)
      order: plan.list.map((o, k) => {
        if (!o.geometry.boundingSphere) o.geometry.computeBoundingSphere();
        const c = o.geometry.boundingSphere.center;
        return { i: plan.first + k, id: o.id, c: [c.x, c.y, c.z], i0: irange[plan.first + k][0], n: irange[plan.first + k][1], z: 0 };
      }),
      sorted: false,
    };
    Object.defineProperty(m.userData, 'group', { value: group, enumerable: false, writable: true }); // clone 이 JSON 으로 베끼지 않게
    groups.push(group);
    batches.push(m);
    for (const o of plan.list) {
      owner.push(m);
      src.push(o.material);
    }
  }
  const skeleton = new PieceSkeleton(bones, root, owner, src, range, groups);
  for (const m of batches) m.bind(skeleton, new THREE.Matrix4()); // 묶음 행렬 = 단위: 조각 좌표 그대로가 정점
  for (const o of bones) o.userData.batched = true;
  for (let i = batches.length - 1; i >= 0; i--) {
    batches[i].parent = root;
    root.children.unshift(batches[i]);
  }
  return batches;
}

// 조각 도형을 조각 좌표 그대로 이어 붙임 (position·normal·uv [+ color·batchEmis] + skinIndex = 뼈 번호, skinWeight = 1).
// range 에 조각마다 [첫 정점, 수], irange 에 [첫 삼각형 자리, 수]
function mergePieces(list, first, mirrored, withColor, withEmis, range, irange) {
  let nv = 0;
  let ni = 0;
  for (const o of list) {
    const g = o.geometry;
    nv += g.attributes.position.count;
    ni += g.index ? g.index.count : g.attributes.position.count;
  }
  const pos = new Float32Array(nv * 3);
  const nor = new Float32Array(nv * 3);
  const uv = new Float32Array(nv * 2);
  const col = withColor ? new Float32Array(nv * 3) : null;
  const emi = withEmis ? new Float32Array(nv * 3) : null;
  const si = new Uint16Array(nv * 4);
  const sw = new Float32Array(nv * 4);
  const idx = nv > 65535 ? new Uint32Array(ni) : new Uint16Array(ni);
  let v0 = 0;
  let i0 = 0;
  list.forEach((o, k) => {
    const g = o.geometry;
    const p = g.attributes.position;
    const n = g.attributes.normal;
    const t = g.attributes.uv;
    const c = o.material.color;
    const e = o.material.emissive;
    const count = g.index ? g.index.count : p.count;
    range[first + k] = [v0, p.count];
    irange[first + k] = [i0, count];
    for (let v = 0; v < p.count; v++) {
      const a = v0 + v;
      pos[a * 3] = p.getX(v);
      pos[a * 3 + 1] = p.getY(v);
      pos[a * 3 + 2] = p.getZ(v);
      nor[a * 3] = n.getX(v);
      nor[a * 3 + 1] = n.getY(v);
      nor[a * 3 + 2] = n.getZ(v);
      if (t) {
        uv[a * 2] = t.getX(v);
        uv[a * 2 + 1] = t.getY(v);
      }
      if (col) {
        col[a * 3] = c ? c.r : 1;
        col[a * 3 + 1] = c ? c.g : 1;
        col[a * 3 + 2] = c ? c.b : 1;
      }
      if (emi && e) {
        emi[a * 3] = e.r;
        emi[a * 3 + 1] = e.g;
        emi[a * 3 + 2] = e.b;
      }
      si[a * 4] = first + k;
      sw[a * 4] = 1;
    }
    const flip = mirrored(o); // 거울상 조각 (음수 크기): 보통 Mesh 는 three 가 앞면 방향을 뒤집어 주지만 합치면 못 해서 삼각형 순서를 뒤집음
    for (let j = 0; j < count; j += 3) {
      const a = g.index ? g.index.getX(j) : j;
      const b = g.index ? g.index.getX(j + 1) : j + 1;
      const cc = g.index ? g.index.getX(j + 2) : j + 2;
      idx[i0 + j] = v0 + a;
      idx[i0 + j + 1] = v0 + (flip ? cc : b);
      idx[i0 + j + 2] = v0 + (flip ? b : cc);
    }
    v0 += p.count;
    i0 += count;
  });
  const geo = new THREE.BufferGeometry();
  geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  geo.setAttribute('normal', new THREE.BufferAttribute(nor, 3));
  geo.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  if (col) geo.setAttribute('color', new THREE.BufferAttribute(col, 3));
  if (emi) geo.setAttribute('batchEmis', new THREE.BufferAttribute(emi, 3));
  geo.setAttribute('skinIndex', new THREE.BufferAttribute(si, 4));
  geo.setAttribute('skinWeight', new THREE.BufferAttribute(sw, 4));
  geo.setIndex(new THREE.BufferAttribute(idx, 1));
  return geo;
}

// 합친 몸을 복제 (압사 납작 몸·잔상): three 의 clone 은 SkinnedMesh 가 원본 뼈대를 그대로 가리켜서, 복제본 조각으로 다시 묶음.
// 도형 정점은 같이 쓰고 삼각형 순서(반투명 정렬)·색·발광 값만 따로
export function cloneBatched(src) {
  const copy = src.clone(true);
  const a = [];
  const b = [];
  src.traverse((o) => a.push(o));
  copy.traverse((o) => b.push(o));
  if (a.length !== b.length) return copy;
  const twin = new Map(a.map((o, i) => [o, b[i]]));
  const done = new Map();
  for (let i = 0; i < a.length; i++) {
    const o = a[i];
    if (!o.isSkinnedMesh || !(o.skeleton instanceof PieceSkeleton)) continue;
    const s = o.skeleton;
    if (!done.has(s)) {
      const groups = s.groups.map((g) => {
        const m = twin.get(g.mesh);
        const old = g.mesh.geometry;
        const geo = new THREE.BufferGeometry();
        for (const [k, at] of Object.entries(old.attributes)) geo.setAttribute(k, k === 'color' || k === 'batchEmis' ? at.clone() : at);
        geo.setIndex(new THREE.BufferAttribute(g.base.slice(), 1));
        m.geometry = geo;
        const ng = {
          mesh: m,
          mat: g.mat,
          sources: g.sources.map((x) => ({ mat: x.mat, color: x.color && x.color.clone(), emis: x.emis && x.emis.clone(), pieces: x.pieces })),
          off: null,
          see: false,
          base: g.base,
          order: g.order.map((x) => ({ ...x, id: twin.get(s.bones[x.i]).id })),
          sorted: false,
        };
        Object.defineProperty(m.userData, 'group', { value: ng, enumerable: false, writable: true });
        return ng;
      });
      done.set(s, new PieceSkeleton(s.bones.map((x) => twin.get(x)), twin.get(s.root) || copy, s.owner.map((x) => twin.get(x)), s.src.slice(), s.range, groups));
    }
    b[i].bind(done.get(s), b[i].bindMatrix);
    b[i].onBeforeRender = batchCamera;
    b[i].updateMatrixWorld = batchMatrixWorld;
  }
  return copy;
}

// 몸 전체를 한 재질로 (잔상): 조각·합친 메시 모두 mat 으로, 묶음은 그대로 (정점 색·발광은 안 씀)
export function paintBatched(root, mat) {
  root.traverse((o) => {
    if (!o.isMesh) return;
    o.material = mat;
    if (o.isSkinnedMesh && o.skeleton instanceof PieceSkeleton) {
      const s = o.skeleton;
      s.src.fill(mat);
      for (const g of s.groups) {
        g.mat = mat;
        g.sources = [{ mat, color: null, emis: null, pieces: [] }];
      }
    }
  });
}
