// JS 몸 (client/figure.js buildFigure — 맨몸 + 옷·무기·소품) 을 node 에서 실제로 돌려 .glb 로 구움 → 고도 chars/body.gd 가 파일로 불러옴 (W7, 2026-11-02 재혁 '몸을 파일로')
// 실행 (레포 뿌리): node tools/bake-bodies.mjs [캐릭터 id …]   (기본: tank) → godot/client/assets/models/<id>.glb + <id>.json (작은 manifest)
// 그 뒤 고도 import 한 번 (godot --headless --path godot/client --import) — .glb.import 설정 (LOD·그림자 메시·접선 끔) 은 커밋돼 있음
//
// .glb 안 (몸 안 좌표 = 게임 좌표: 앞 +x, 왼쪽 +y, 위 +z — 맨 위 'frame' 노드 하나가 glTF/고도 Y 위로 돌림, core/coords.gd 와 같은 돌림):
//   frame ─ body (JS group) ─ … 관절 나무 (이름 = 고도 body.gd 의 관절 이름: hips·waist·neck·torso·shoulder_R/L·elbow_R/L·hand_R/L·thigh_R/L·knee_R/L·foot_R/L·flaps_0_obj …)
//         │    관절마다 그 아래 같이 움직이는 조각은 재질마다 메시 하나로 합친 잎 노드 '<주인>__m<재질>' (조각 모드: 1인칭 팔·확인용)
//         ├─ B_<번호> … 뼈 나무 (번호 = manifest nodes 번호, 고도 import 가 Skeleton3D 로 바꿈)
//         └─ batch  툰 조각 전부를 정점 색 SkinnedMesh 하나로 (뼈 = 관절) — 판·대기실·초상 몸 (G3 batch.gd 를 미리 구운 것: 피부 정점은 UV2.x = 1, 색은 툰 skin_tint)
// 조각 표 (gen-bodies.mjs 와 같은 뽑기) 중 refs 가 가리키는 노드·처음에 숨긴 노드·닌자 단검·그 조상은 노드 그대로 (자세·보이기·재질 바꾸기를 코드가 함), 나머지 조각만 합침
// manifest: nodes (이름·부모·숨김·그림자·단검·재질·batch = 묶음에 들어간 조각) · mats (gen-bodies 와 같은 재질 표) · refs (노드 번호) · bones (뼈 → 노드 번호) · 수치
import { register } from 'node:module';
import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { fileURLToPath } from 'node:url';

register('../test/support/client-loader.mjs', import.meta.url);
// 체크 무늬 천 텍스처가 캔버스에 그림 → 가짜 캔버스가 칠한 색을 기억 (고도에서 같은 무늬를 다시 그림, gen-bodies.mjs 와 같음)
globalThis.document ??= {
  createElement: () => {
    const fills = [];
    let style = null;
    let alpha = 1;
    const ctx = new Proxy({}, {
      get: (_, k) => (k === 'fillRect' ? (...a) => fills.push([style, alpha, ...a]) : () => {}),
      set: (_, k, v) => {
        if (k === 'fillStyle') style = v;
        if (k === 'globalAlpha') alpha = v;
        return true;
      },
    });
    return { width: 0, height: 0, fills, getContext: () => ctx };
  },
};
const THREE = await import('three');
const { CONFIG: C } = await import('../shared/config.js');
const { buildFigure } = await import('../client/figure.js');

const ROOT = path.join(path.dirname(fileURLToPath(import.meta.url)), '..');
const OUT = path.join(ROOT, 'godot/client/assets/models');
// 관절 배열 이름 (refs 키 → 노드 이름, [0] = 오른쪽 R, [1] = 왼쪽 L — ragdoll.gd upperR = shoulders[0])
const JOINT_NAMES = { shoulders: 'shoulder', elbows: 'elbow', hands: 'hand', thighs: 'thigh', knees: 'knee', feet: 'foot' };
const SIDE = ['R', 'L'];

// ---------- JS 몸 → 조각 표 (gen-bodies.mjs 와 같은 뽑기: 노드 나무·재질·refs) ----------
function extract(ch) {
  const r = buildFigure(0xffffff, ch, null);
  const skin = r.bodyMaterial;
  const objs = [];
  const nodes = [];
  const nodeIdx = new Map();
  const mats = [];
  const matIdx = new Map();
  function matOf(m) {
    if (matIdx.has(m)) return matIdx.get(m);
    const o = {
      kind: m.isMeshBasicMaterial ? 'basic' : 'toon',
      color: m.color ? m.color.getHex() : 0xffffff,
      emissive: m.emissive ? m.emissive.getHex() : 0,
      opacity: m.opacity,
      transparent: !!m.transparent,
      double: m.side === THREE.DoubleSide,
      outline: !(m.userData.outlineParameters && m.userData.outlineParameters.visible === false) && !m.isMeshBasicMaterial,
      skin: m === skin,
      shade: !!(r.figure?.shade && r.figure.shade.mat === m),
    };
    if (m.map && m.map.image && m.map.image.fills) {
      o.plaid = m.map.image.fills;
      o.repeat = [m.map.repeat.x, m.map.repeat.y];
    }
    mats.push(o);
    matIdx.set(m, mats.length - 1);
    return mats.length - 1;
  }
  const skip = new Set();
  r.group.traverse((o) => {
    if (o.isSkinnedMesh || o.isBone || (o.parent && skip.has(o.parent))) {
      skip.add(o);
      return;
    }
    const e = { parent: o.parent && nodeIdx.has(o.parent) ? nodeIdx.get(o.parent) : -1 };
    if (!o.visible) e.hidden = true;
    if (o.userData.dagger) e.dagger = true;
    if (o.isMesh) {
      e.geo = o.geometry;
      e.mat = Array.isArray(o.material) ? matOf(o.material[0]) : matOf(o.material);
      if (!o.castShadow) e.noShadow = true;
    }
    objs.push(o);
    nodes.push(e);
    nodeIdx.set(o, nodes.length - 1);
  });
  const seen = new Set();
  const ref = (v) => {
    if (v === null || v === undefined) return null;
    if (v.isObject3D) return nodeIdx.has(v) ? { node: nodeIdx.get(v) } : null;
    if (v.isMaterial) return matIdx.has(v) ? { mat: matIdx.get(v) } : null;
    if (typeof v === 'function') return undefined;
    if (typeof v !== 'object') return v;
    if (seen.has(v)) return null;
    seen.add(v);
    if (Array.isArray(v)) return v.map(ref);
    const o = {};
    for (const [k, x] of Object.entries(v)) {
      const y = ref(x);
      if (y !== undefined) o[k] = y;
    }
    return o;
  };
  const f = r.figure || {};
  const refs = {};
  for (const [k, v] of Object.entries(f)) if (!['d', 'char', 'pose'].includes(k)) {
    const y = ref(v);
    if (y !== undefined) refs[k] = y;
  }
  if (f.forms) {
    refs.formParts = {};
    refs.torsoMat = {};
    for (const k of Object.keys(f.forms)) {
      seen.clear();
      refs.formParts[k] = f.forms[k].userData.parts.map(ref);
      f.setForm(k);
      matOf(f.torso.material);
      refs.torsoMat[k] = matIdx.get(f.torso.material);
    }
    f.setForm('bard');
    delete refs.forms;
  }
  refs.rig = ref(r.rig);
  refs.parts = ref(r.parts);
  refs.hammer = ref(r.hammer);
  refs.held = ref(r.held);
  refs.waitMark = ref(r.waitMark);
  return { objs, nodes, mats, refs };
}

// refs 안의 {node: i} → [i, 경로]
function refPaths(v, at, out) {
  if (Array.isArray(v)) v.forEach((x, i) => refPaths(x, [...at, i], out));
  else if (v && typeof v === 'object') {
    if (typeof v.node === 'number' && Object.keys(v).length === 1) out.push([v.node, at]);
    else for (const [k, x] of Object.entries(v)) refPaths(x, [...at, k], out);
  }
}
function remapRefs(v, map) {
  if (Array.isArray(v)) return v.map((x) => remapRefs(x, map));
  if (v && typeof v === 'object') {
    if (typeof v.node === 'number' && Object.keys(v).length === 1) return map.has(v.node) ? { node: map.get(v.node) } : null;
    const o = {};
    for (const [k, x] of Object.entries(v)) o[k] = remapRefs(x, map);
    return o;
  }
  return v;
}
function nameOf(at) {
  if (at.length === 2 && JOINT_NAMES[at[0]] && typeof at[1] === 'number') return `${JOINT_NAMES[at[0]]}_${SIDE[at[1]] ?? at[1]}`;
  return at.join('_');
}

// 묶음 (SkinnedMesh) 에 넣는 재질: 불투명 툰, 그림·발광 없음, 외곽선 있음, 한 면 (G3 batch.gd _batchable + JS batch.js 처럼 양면·외곽선 없는 건 따로), 근육 홈 (피부 × 어둡게 — 사람마다 색) 빼고
function batchable(m) {
  return m.kind === 'toon' && !m.transparent && !m.plaid && !m.emissive && m.outline && !m.double && !m.shade;
}

// 정점 묶음 → {pos, nor, uv, idx} (색인 그대로 — 고도 import 가 정점을 다시 나누지 않게)
function geoArrays(g) {
  const a = g.attributes;
  const n = a.position.count;
  const idx = g.index ? Array.from(g.index.array) : Array.from({ length: n }, (_, i) => i);
  return { pos: Array.from(a.position.array), nor: a.normal ? Array.from(a.normal.array) : null, uv: a.uv ? Array.from(a.uv.array) : null, idx, n };
}
// m 으로 옮긴 정점 묶음 (법선은 역전치, 거울이면 삼각형 뒤집음)
function transformed(ga, m) {
  const out = { pos: [], nor: [], uv: [], idx: [], n: ga.n };
  const nm = new THREE.Matrix3().getNormalMatrix(m);
  const v = new THREE.Vector3();
  for (let i = 0; i < ga.n; i++) {
    v.fromArray(ga.pos, i * 3).applyMatrix4(m);
    out.pos.push(v.x, v.y, v.z);
    if (ga.nor) v.fromArray(ga.nor, i * 3).applyMatrix3(nm).normalize();
    else v.set(0, 0, 1);
    out.nor.push(v.x, v.y, v.z);
    out.uv.push(ga.uv ? ga.uv[i * 2] : 0, ga.uv ? ga.uv[i * 2 + 1] : 0);
  }
  const flip = m.determinant() < 0;
  for (let t = 0; t < ga.idx.length; t += 3) {
    if (flip) out.idx.push(ga.idx[t], ga.idx[t + 2], ga.idx[t + 1]);
    else out.idx.push(ga.idx[t], ga.idx[t + 1], ga.idx[t + 2]);
  }
  return out;
}
function append(dst, src, extra) {
  const base = dst.n;
  dst.pos.push(...src.pos);
  dst.nor.push(...src.nor);
  dst.uv.push(...src.uv);
  for (const i of src.idx) dst.idx.push(base + i);
  if (extra) extra(src.n);
  dst.n += src.n;
}
const emptyGeo = () => ({ pos: [], nor: [], uv: [], idx: [], n: 0 });

// ---------- 굽기 ----------
function bake(ch) {
  const src = extract(ch);
  const { objs, nodes, mats, refs } = src;
  const N = nodes.length;
  const children = Array.from({ length: N }, () => []);
  nodes.forEach((e, i) => e.parent >= 0 && children[e.parent].push(i));
  // 남길 노드: refs 가 가리킴·숨김·단검·맨 위 + 그 조상
  const paths = [];
  refPaths(refs, [], paths);
  const keep = new Set();
  const names = new Map();
  for (const [i, at] of paths) {
    keep.add(i);
    if (!names.has(i)) names.set(i, nameOf(at));
  }
  nodes.forEach((e, i) => (e.hidden || e.dagger || e.parent < 0) && keep.add(i));
  for (const i of [...keep]) for (let p = nodes[i].parent; p >= 0; p = nodes[p].parent) keep.add(p);
  // 바드 몸통: 폼마다 재질을 통째로 바꿈 → 묶음 밖 (body.gd _batch 와 같음). 광전사 눈 흰자: 분노 때 색이 바뀜 → 묶음 밖 (body.gd _merge 와 같음)
  const torsoNode = refs.formParts && refs.torso ? refs.torso.node : -1;
  const rageEye = refs.rage && refs.rage.eyeMat ? refs.rage.eyeMat.mat : -1;
  const inBatch = (i) => nodes[i].geo !== undefined && i !== torsoNode && nodes[i].mat !== rageEye && batchable(mats[nodes[i].mat]);
  // 노드 → 몸 안 (frame 기준) 자리 = group 부터 곱함
  const local = objs.map((o) => new THREE.Matrix4().compose(o.position, o.quaternion, o.scale));
  const world = [];
  nodes.forEach((e, i) => (world[i] = e.parent >= 0 ? world[e.parent].clone().multiply(local[i]) : local[i].clone()));
  // 남긴 노드 번호 (나무 순서 그대로 → 부모 번호 < 자식 번호)
  const kept = [...keep].sort((a, b) => a - b);
  const newIdx = new Map(kept.map((i, k) => [i, k]));
  const used = new Set();
  const uniq = (s) => {
    let n = s.replace(/[^A-Za-z0-9_]/g, '_');
    if (n === 'frame' || n === 'batch' || /^B_\d+$/.test(n)) n = `n_${n}`;
    let k = n;
    for (let j = 2; used.has(k); j++) k = `${n}${j}`;
    used.add(k);
    return k;
  };
  const out = []; // manifest nodes
  const trs = new Map(); // 남긴 노드 → JS 자리 (잎은 단위)
  const meshes = []; // [노드 번호 (out), 정점 묶음, 재질]
  for (const i of kept) {
    const e = nodes[i];
    const o = { name: uniq(i === 0 ? 'body' : (names.get(i) ?? `n${i}`)), parent: e.parent >= 0 ? newIdx.get(e.parent) : -1 };
    trs.set(out.length, { t: objs[i].position.toArray(), q: objs[i].quaternion.toArray(), s: objs[i].scale.toArray() });
    if (e.hidden) o.hidden = true;
    if (e.dagger) o.dagger = true;
    if (e.geo !== undefined) {
      o.mat = e.mat;
      if (e.noShadow) o.noShadow = true;
      if (inBatch(i)) o.batch = true;
      meshes.push([out.length, geoArrays(e.geo), e.mat]);
    }
    out.push(o);
  }
  // 나머지 조각: 가장 가까운 남긴 조상 (주인) 아래 재질·그림자마다 하나로
  const groups = new Map();
  for (let i = 0; i < N; i++) {
    if (keep.has(i) || nodes[i].geo === undefined) continue;
    let owner = nodes[i].parent;
    while (!keep.has(owner)) owner = nodes[owner].parent;
    const rel = world[owner].clone().invert().multiply(world[i]);
    const key = `${owner}|${nodes[i].mat}|${!!nodes[i].noShadow}|${inBatch(i)}`;
    if (!groups.has(key)) groups.set(key, { owner, mat: nodes[i].mat, noShadow: !!nodes[i].noShadow, batch: inBatch(i), geo: emptyGeo() });
    append(groups.get(key).geo, transformed(geoArrays(nodes[i].geo), rel));
  }
  // 잎 순서: 묶음 밖 조각 먼저, 묶음 조각은 맨 끝 (묶음 모드는 그 앞까지만 노드 표로 씀)
  const leafs = [...groups.values()].sort((a, b) => a.batch - b.batch);
  const leafStart = out.length;
  for (const g of leafs) {
    const o = { name: uniq(`${out[newIdx.get(g.owner)].name}__m${g.mat}${g.noShadow ? '_ns' : ''}`), parent: newIdx.get(g.owner), mat: g.mat };
    if (g.noShadow) o.noShadow = true;
    if (g.batch) o.batch = true;
    meshes.push([out.length, g.geo, g.mat]);
    out.push(o);
  }
  const batchStart = out.findIndex((o, k) => k >= leafStart && o.batch);
  // 묶음 (SkinnedMesh): 뼈 = 묶음 조각의 주인 노드 (남긴 메시 노드는 자기, 잎은 부모)
  const boneOf = (k) => (k >= leafStart ? out[k].parent : k);
  const boneSet = new Set();
  for (const [k] of meshes) if (out[k].batch) boneSet.add(boneOf(k));
  const bones = [...boneSet].sort((a, b) => a - b); // 부모 < 자식
  const boneIdx = new Map(bones.map((b, j) => [b, j]));
  const oldOf = new Map(kept.map((i, k) => [k, i]));
  const boneParent = bones.map((b) => {
    for (let p = out[b].parent; p >= 0; p = out[p].parent) if (boneIdx.has(p)) return boneIdx.get(p);
    return -1;
  });
  // 뼈 자리 (부모 뼈 기준) = 고도 sync 와 같은 자리·돌림·크기로 나눔 (비뚤림이 있으면 경고)
  const boneLocal = bones.map((b, j) => {
    const par = boneParent[j];
    const m = par >= 0 ? world[oldOf.get(bones[par])].clone().invert().multiply(world[oldOf.get(b)]) : world[oldOf.get(b)].clone();
    const t = new THREE.Vector3();
    const q = new THREE.Quaternion();
    const s = new THREE.Vector3();
    m.decompose(t, q, s);
    const back = new THREE.Matrix4().compose(t, q, s);
    const err = Math.max(...back.elements.map((x, k) => Math.abs(x - m.elements[k])));
    if (err > 1e-5) console.warn(`  ${ch} 뼈 ${out[b].name} 비뚤림 ${err.toExponential(2)}`);
    return { t, q, s, m: back };
  });
  const boneGlobal = [];
  bones.forEach((_, j) => (boneGlobal[j] = boneParent[j] >= 0 ? boneGlobal[boneParent[j]].clone().multiply(boneLocal[j].m) : boneLocal[j].m.clone()));
  const batch = { ...emptyGeo(), col: [], skin: [], joint: [] };
  for (const [k, ga, mat] of meshes) {
    if (!out[k].batch) continue;
    const j = boneIdx.get(boneOf(k));
    // 조각 정점 → 몸 안 (bind 자세 = 뼈 전역)
    const g = transformed(ga, boneGlobal[j]); // 남긴 메시 노드 = 자기 기준, 잎 = 주인 기준 → 둘 다 뼈 기준
    const m = mats[mat];
    const c = new THREE.Color(m.skin ? 0xffffff : m.color);
    append(batch, g, (n) => {
      for (let v = 0; v < n; v++) {
        batch.col.push(c.r, c.g, c.b);
        batch.skin.push(m.skin ? 1 : 0);
        batch.joint.push(j);
      }
    });
  }
  // glTF 재질은 보기용 (블렌더 등) — 고도는 manifest mats 로 G3 툰을 만듦
  const gltf = writeGlb(ch, out, trs, meshes, mats, bones, boneParent, boneLocal, boneGlobal, batch);
  const refsOut = remapRefs(refs, newIdx);
  const verts = { pieces: meshes.reduce((a, [, g]) => a + g.n, 0), batch: batch.n };
  const tris = { pieces: meshes.reduce((a, [, g]) => a + g.idx.length / 3, 0), batch: batch.idx.length / 3 };
  const manifest = {
    char: ch,
    source: sourceHash(),
    glb: `${ch}.glb`,
    leafStart,
    batchStart: batchStart < 0 ? out.length : batchStart,
    nodes: out,
    mats,
    refs: refsOut,
    bones: bones.map((b, j) => ({ node: b, parent: boneParent[j] })),
    stats: { jsNodes: N, jsMeshes: nodes.filter((e) => e.geo !== undefined).length, nodes: out.length, meshes: meshes.length, bones: bones.length, verts, tris },
  };
  return { gltf, manifest };
}

// JS 몸을 만드는 파일들의 해시 (바뀌었는데 안 다시 구웠는지 테스트가 봄)
function sourceHash() {
  const h = crypto.createHash('sha1');
  for (const f of ['client/figure.js', 'client/toon.js', 'client/character.js', 'client/models.js', 'shared/config.js', 'tools/bake-bodies.mjs']) h.update(fs.readFileSync(path.join(ROOT, f)));
  return h.digest('hex').slice(0, 12);
}

// ---------- glTF 2.0 바이너리 (.glb) 쓰기 (three GLTFExporter 는 DOM·FileReader 가 있어야 해서 직접) ----------
function writeGlb(ch, out, trs, meshes, mats, bones, boneParent, boneLocal, boneGlobal, batch) {
  const bin = [];
  let binLen = 0;
  const bufferViews = [];
  const accessors = [];
  const view = (buf, target) => {
    const pad = (4 - (binLen % 4)) % 4;
    if (pad) bin.push(Buffer.alloc(pad)), (binLen += pad);
    bufferViews.push({ buffer: 0, byteOffset: binLen, byteLength: buf.length, ...(target ? { target } : {}) });
    bin.push(buf);
    binLen += buf.length;
    return bufferViews.length - 1;
  };
  const acc = (arr, type, comp, opts = {}) => {
    const per = { SCALAR: 1, VEC2: 2, VEC3: 3, VEC4: 4, MAT4: 16 }[type];
    const T = { 5126: Float32Array, 5125: Uint32Array, 5123: Uint16Array, 5121: Uint8Array }[comp];
    const ta = T.from(arr);
    const a = { bufferView: view(Buffer.from(ta.buffer), opts.target), componentType: comp, count: arr.length / per, type };
    if (opts.normalized) a.normalized = true;
    if (opts.minmax) {
      a.min = [];
      a.max = [];
      for (let c = 0; c < per; c++) {
        let lo = Infinity;
        let hi = -Infinity;
        for (let i = c; i < arr.length; i += per) (lo = Math.min(lo, ta[i])), (hi = Math.max(hi, ta[i]));
        a.min.push(lo);
        a.max.push(hi);
      }
    }
    accessors.push(a);
    return accessors.length - 1;
  };
  const ARRAY = 34962;
  const ELEMENT = 34963;
  const idxAcc = (idx, n) => acc(idx, 'SCALAR', n < 65536 ? 5123 : 5125, { target: ELEMENT });
  // three uv (v 위) → glTF uv (v 아래)
  const flipV = (uv) => uv.map((x, i) => (i % 2 ? 1 - x : x));
  const lin = (hex) => {
    const c = new THREE.Color(hex);
    return [c.r, c.g, c.b].map((x) => (x <= 0.04045 ? x / 12.92 : ((x + 0.055) / 1.055) ** 2.4));
  };
  const materials = mats.map((m, i) => ({
    name: `m${i}`,
    pbrMetallicRoughness: { baseColorFactor: [...lin(m.color), m.transparent ? m.opacity : 1], metallicFactor: 0, roughnessFactor: 1 },
    ...(m.emissive ? { emissiveFactor: lin(m.emissive) } : {}),
    ...(m.transparent ? { alphaMode: 'BLEND' } : {}),
    ...(m.double ? { doubleSided: true } : {}),
    ...(m.kind === 'basic' ? { extensions: { KHR_materials_unlit: {} } } : {}),
  }));
  materials.push({ name: 'batch', pbrMetallicRoughness: { baseColorFactor: [1, 1, 1, 1], metallicFactor: 0, roughnessFactor: 1 } });
  const gMeshes = [];
  const meshOf = new Map();
  for (const [k, g, mat] of meshes) {
    const attributes = { POSITION: acc(g.pos, 'VEC3', 5126, { target: ARRAY, minmax: true }), NORMAL: acc(g.nor, 'VEC3', 5126, { target: ARRAY }) };
    if (g.uv.length) attributes.TEXCOORD_0 = acc(flipV(g.uv), 'VEC2', 5126, { target: ARRAY });
    gMeshes.push({ name: `${ch}_${out[k].name}`, primitives: [{ attributes, indices: idxAcc(g.idx, g.n), material: mat }] });
    meshOf.set(k, gMeshes.length - 1);
  }
  const gNodes = [];
  // frame: 게임 (x 앞, y 왼쪽, z 위) → glTF·고도 (x, z, -y) = x 축 −90° (chars/body.gd frame 과 같음)
  gNodes.push({ name: 'frame', rotation: [-Math.SQRT1_2, 0, 0, Math.SQRT1_2], children: [] });
  const nodeOf = new Map();
  out.forEach((o, k) => {
    const n = { name: o.name };
    const t = trs.get(k); // 남긴 노드 = JS 노드 자리 그대로, 잎 = 주인 기준이라 단위
    if (t) Object.assign(n, { translation: t.t, rotation: t.q, scale: t.s });
    if (meshOf.has(k)) n.mesh = meshOf.get(k);
    gNodes.push(n);
    nodeOf.set(k, gNodes.length - 1);
    const par = o.parent >= 0 ? gNodes[nodeOf.get(o.parent)] : gNodes[0];
    (par.children ??= []).push(gNodes.length - 1);
  });
  // 뼈 나무
  const jointNode = [];
  bones.forEach((b, j) => {
    const L = boneLocal[j];
    gNodes.push({ name: `B_${b}`, translation: L.t.toArray(), rotation: L.q.toArray(), scale: L.s.toArray() });
    jointNode.push(gNodes.length - 1);
    const par = boneParent[j] >= 0 ? gNodes[jointNode[boneParent[j]]] : gNodes[0];
    (par.children ??= []).push(gNodes.length - 1);
  });
  let skin = null;
  if (batch.n) {
    // 정점 색 = 재질 sRGB 값 그대로 (G3 batch.gd 처럼, 툰이 COLOR 를 sRGB 로 보고 선형으로 바꿈). 고도 glTF import 는 COLOR_0 를 선형으로 보고
    // sRGB → 선형으로 한 번 바꿔 넣음 → 그 반대 (선형 → sRGB) 로 미리 바꿔 씀 (16비트라 어두운 색도 그대로). 그래서 블렌더 등 보기 도구에선 색이 밝게 보임
    const enc = (x) => (x <= 0.0031308 ? x * 12.92 : 1.055 * x ** (1 / 2.4) - 0.055);
    const col = [];
    for (let v = 0; v < batch.n; v++) col.push(...[0, 1, 2].map((c) => Math.round(enc(batch.col[v * 3 + c]) * 65535)), 65535);
    const joints = [];
    const weights = [];
    for (let v = 0; v < batch.n; v++) joints.push(batch.joint[v], 0, 0, 0), weights.push(255, 0, 0, 0);
    const uv2 = [];
    for (let v = 0; v < batch.n; v++) uv2.push(batch.skin[v], 0);
    const attributes = {
      POSITION: acc(batch.pos, 'VEC3', 5126, { target: ARRAY, minmax: true }),
      NORMAL: acc(batch.nor, 'VEC3', 5126, { target: ARRAY }),
      COLOR_0: acc(col, 'VEC4', 5123, { target: ARRAY, normalized: true }),
      TEXCOORD_0: acc(new Array(batch.n * 2).fill(0), 'VEC2', 5126, { target: ARRAY }),
      TEXCOORD_1: acc(uv2, 'VEC2', 5126, { target: ARRAY }),
      JOINTS_0: acc(joints, 'VEC4', bones.length < 256 ? 5121 : 5123, { target: ARRAY }),
      WEIGHTS_0: acc(weights, 'VEC4', 5121, { target: ARRAY, normalized: true }),
    };
    gMeshes.push({ name: `${ch}_batch`, primitives: [{ attributes, indices: idxAcc(batch.idx, batch.n), material: materials.length - 1 }] });
    const ibm = [];
    for (const g of boneGlobal) ibm.push(...g.clone().invert().elements);
    skin = { name: `${ch}_skin`, joints: jointNode, inverseBindMatrices: acc(ibm, 'MAT4', 5126) };
    gNodes.push({ name: 'batch', mesh: gMeshes.length - 1, skin: 0 });
    gNodes[0].children.push(gNodes.length - 1);
  }
  const json = {
    asset: { version: '2.0', generator: 'Tetrafall tools/bake-bodies.mjs' },
    extensionsUsed: mats.some((m) => m.kind === 'basic') ? ['KHR_materials_unlit'] : undefined,
    scene: 0,
    scenes: [{ name: ch, nodes: [0] }],
    nodes: gNodes,
    meshes: gMeshes,
    materials,
    ...(skin ? { skins: [skin] } : {}),
    accessors,
    bufferViews,
    buffers: [{ byteLength: binLen }],
  };
  return glb(json, Buffer.concat(bin));
}

function glb(json, bin) {
  let js = Buffer.from(JSON.stringify(json), 'utf8');
  js = Buffer.concat([js, Buffer.alloc((4 - (js.length % 4)) % 4, 0x20)]);
  const binPad = Buffer.concat([bin, Buffer.alloc((4 - (bin.length % 4)) % 4, 0)]);
  const head = Buffer.alloc(12);
  head.writeUInt32LE(0x46546c67, 0);
  head.writeUInt32LE(2, 4);
  head.writeUInt32LE(12 + 8 + js.length + 8 + binPad.length, 8);
  const c0 = Buffer.alloc(8);
  c0.writeUInt32LE(js.length, 0);
  c0.writeUInt32LE(0x4e4f534a, 4);
  const c1 = Buffer.alloc(8);
  c1.writeUInt32LE(binPad.length, 0);
  c1.writeUInt32LE(0x004e4942, 4);
  return Buffer.concat([head, c0, js, c1, binPad]);
}

// ---------- 실행 ----------
const list = process.argv.slice(2).length ? process.argv.slice(2) : ['tank'];
fs.mkdirSync(OUT, { recursive: true });
for (const ch of list) {
  if (!C.FIGURE_CHARS.includes(ch)) throw new Error(`캐릭터 없음: ${ch}`);
  const { gltf, manifest } = bake(ch);
  fs.writeFileSync(path.join(OUT, `${ch}.glb`), gltf);
  fs.writeFileSync(path.join(OUT, `${ch}.json`), JSON.stringify(manifest) + '\n');
  const s = manifest.stats;
  console.log(`${ch}.glb ${(gltf.length / 1024).toFixed(0)}KB + ${ch}.json ${(fs.statSync(path.join(OUT, `${ch}.json`)).size / 1024).toFixed(1)}KB: JS 노드 ${s.jsNodes} (메시 ${s.jsMeshes}) → 노드 ${s.nodes} (메시 ${s.meshes}), 뼈 ${s.bones}, 정점 조각 ${s.verts.pieces}·묶음 ${s.verts.batch}, 삼각형 ${s.tris.batch}`);
}
