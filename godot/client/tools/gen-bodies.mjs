// client/figure.js buildFigure 를 node 에서 실제로 돌려 8명 몸 (맨몸 + 옷·무기·소품) 을 그대로 뽑음 → chars/data/bodies.bin (만든 파일, 손으로 고치지 않음)
// 파일 = [u32 풀린 크기] + gzip( [u32 표 길이] [표 JSON, 4바이트 맞춤] [float32 정점 덩어리] ) — 예전 bodies.json (base64) 2.5MB → 약 0.27MB, 고도는 PackedByteArray.decompress 로 품
// 표: 노드 나무 (부모·위치·회전 쿼터니언·크기·보이기) + 메시 정점 (위치·법선·uv = 덩어리 안 [float 시작, 개수]) + 재질 (색·발광·투명·양면·외곽선·피부 여부·체크 무늬) +
// figure 의 특별 노드 표 (hips·waist…·flaps·shields·gun·bow·horns·rage·forms… → 노드 번호). 좌표는 몸 안 게임 좌표 그대로 (chars/body.gd 의 frame 이 고도로 돌림)
// 실행 (레포 뿌리): node godot/client/tools/gen-bodies.mjs
import { register } from 'node:module';
import fs from 'node:fs';
import zlib from 'node:zlib';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

register('../../../test/support/client-loader.mjs', import.meta.url);
// 체크 무늬 천 텍스처가 캔버스에 그림 → 가짜 캔버스가 칠한 색을 기억 (고도에서 같은 무늬를 다시 그림)
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
const { CONFIG: C } = await import('../../../shared/config.js');
const { buildFigure } = await import('../../../client/figure.js');
const { buildCharacter } = await import('../../../client/character.js');

const blob = []; // float32 덩어리 조각들
let blobN = 0;
const put = (arr) => {
  const f = new Float32Array(arr);
  blob.push(Buffer.from(f.buffer));
  blobN += f.length;
  return [blobN - f.length, f.length];
};
const b64 = (arr) => Buffer.from(new Float32Array(arr).buffer).toString('base64'); // 같은 모양 찾기 열쇠
const geos = []; // 정점 묶음 (같은 BufferGeometry 는 한 번만)
const geoIdx = new Map();
const geoKey = new Map();
function geoOf(g) {
  if (geoIdx.has(g)) return geoIdx.get(g);
  const ng = g.index ? g.toNonIndexed() : g;
  const a = ng.attributes;
  const key = `${b64(a.position.array)}|${a.normal ? b64(a.normal.array) : ''}|${a.uv ? b64(a.uv.array) : ''}`; // 모양이 같은 조각 (왼팔·오른팔 등) 은 한 번만
  if (!geoKey.has(key)) {
    geos.push({ pos: put(a.position.array), nor: a.normal ? put(a.normal.array) : null, uv: a.uv ? put(a.uv.array) : null, n: a.position.count });
    geoKey.set(key, geos.length - 1);
  }
  geoIdx.set(g, geoKey.get(key));
  return geoKey.get(key);
}

const out = { scale: C.FIGURE_SCALE, chars: {} };
// 8명 + 연습 방 허수아비 'dummy' (client/character.js buildDummy — figure 관절 없음, 묶음 SkinnedMesh 는 뺌)
for (const ch of [...C.FIGURE_CHARS, 'dummy']) {
  const r = ch === 'dummy' ? buildCharacter(0xffffff, null, 'dummy') : buildFigure(0xffffff, ch, null);
  const skin = r.bodyMaterial;
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
      o.plaid = m.map.image.fills; // [색, 투명도, x, y, w, h] (32×32 캔버스에 차례로)
      o.repeat = [m.map.repeat.x, m.map.repeat.y];
    }
    mats.push(o);
    matIdx.set(m, mats.length - 1);
    return mats.length - 1;
  }
  const skip = new Set(); // character.js 가 붙인 묶음 SkinnedMesh (고도는 G3 batch 로 다시 묶음)
  r.group.traverse((o) => {
    if (o.isSkinnedMesh || o.isBone || (o.parent && skip.has(o.parent))) {
      skip.add(o);
      return;
    }
    const e = {
      parent: o.parent && nodeIdx.has(o.parent) ? nodeIdx.get(o.parent) : -1,
      p: o.position.toArray(),
      q: o.quaternion.toArray(),
      s: o.scale.toArray(),
    };
    if (!o.visible) e.hidden = true;
    if (o.userData.dagger) e.dagger = true; // 닌자 왼손 단검 (1인칭은 표창으로 바꿈)
    if (o.isMesh) {
      e.geo = geoOf(o.geometry);
      e.mat = Array.isArray(o.material) ? matOf(o.material[0]) : matOf(o.material);
      if (!o.castShadow) e.noShadow = true;
    }
    nodes.push(e);
    nodeIdx.set(o, nodes.length - 1);
  });
  // figure 의 특별 노드·값 (노드는 번호, 재질은 {mat}, 함수는 뺌)
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
    // 바드 두 폼: 폼마다 부위 묶음 (보이기를 바꿈) + 몸통 재질 (setForm 이 바꿈)
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
  out.chars[ch] = { nodes, mats, refs };
}
out.geos = geos;
const file = path.join(path.dirname(fileURLToPath(import.meta.url)), '../chars/data/bodies.bin');
fs.mkdirSync(path.dirname(file), { recursive: true });
let json = Buffer.from(JSON.stringify(out), 'utf8');
json = Buffer.concat([json, Buffer.alloc((4 - (json.length % 4)) % 4, 0x20)]); // 덩어리가 4바이트 맞춤에서 시작
const head = Buffer.alloc(4);
head.writeUInt32LE(json.length);
const raw = Buffer.concat([head, json, ...blob]);
const size = Buffer.alloc(4);
size.writeUInt32LE(raw.length);
fs.writeFileSync(file, Buffer.concat([size, zlib.gzipSync(raw, { level: 9 })]));
const nodesN = Object.values(out.chars).reduce((a, c) => a + c.nodes.length, 0);
console.log(`bodies.bin: ${Object.keys(out.chars).length}명, 노드 ${nodesN}, 정점 묶음 ${geos.length}, ${(fs.statSync(file).size / 1024).toFixed(0)}KB`);
