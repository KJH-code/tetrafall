// 사냥꾼 1인칭 소총 떼어 내기 (W34): ext/hunter.glb 의 stage 메시 (hunter_lod0) 에서 소총만 뽑아 따로 .glb (hunter_rifle.glb) 로.
// 원본 소총은 몸 메시에 붙어 있고 가중치가 전부 오른손 반지 손가락 뼈 (RightHandRing3) 에 몰려 있음 → 그 뼈가 가장 센 삼각형 중 오른손 뼈 머리에서 RIFLE_MIN 이상 떨어진 것
// (손가락·쥔 부분은 1인칭 팔 hunter_vm 이 따로 가짐). 꼭짓점은 오른손 뼈 지역 좌표 (역바인드 행렬) 로 바꿔서 → external.gd attach 가 그 뼈에 붙이면 3인칭 몸의 소총과 같은 자리·방향.
// 알베도는 삼각형마다 색을 뽑은 작은 팔레트 그림. 실행 (@gltf-transform/core + sharp 가 있는 폴더에서):
//   node hunter_rifle.mjs <ext/hunter.glb> <출력 hunter_rifle.glb>
import { NodeIO } from '@gltf-transform/core';
import sharp from 'sharp';

const [src, dst] = process.argv.slice(2);
const RIFLE_MIN = Number(process.env.RIFLE_MIN || 0.07); // 오른손 뼈 머리에서 이만큼 (모델 키 1.0 기준 m) 안은 쥔 손이라 뺌
const io = new NodeIO();
const doc = await io.read(src);
const root = doc.getRoot();
const node = root.listNodes().find((n) => n.getName() === 'hunter_lod0');
const skin = node.getSkin();
const joints = skin.listJoints().map((j) => j.getName());
const ibm = skin.getInverseBindMatrices().getArray();
const prim = node.getMesh().listPrimitives()[0];
const P = prim.getAttribute('POSITION').getArray();
const N = prim.getAttribute('NORMAL').getArray();
const UV = prim.getAttribute('TEXCOORD_0').getArray();
const J = prim.getAttribute('JOINTS_0').getArray();
const W = prim.getAttribute('WEIGHTS_0').getArray();
const idx = prim.getIndices().getArray();
const ring = joints.findIndex((n) => n.endsWith('RightHandRing3'));
const hand = joints.findIndex((n) => n.endsWith(':RightHand'));
const M = ibm.slice(hand * 16, hand * 16 + 16); // 열 우선: 메시 → 손뼈 지역
const head = [0, 1, 2].map((r) => -(M[r * 4] * M[12] + M[r * 4 + 1] * M[13] + M[r * 4 + 2] * M[14])); // 손뼈 머리 (메시 좌표)
const nv = P.length / 3;
const dom = new Int16Array(nv);
for (let v = 0; v < nv; v++) {
  let b = 0;
  for (let k = 1; k < 4; k++) if (W[v * 4 + k] > W[v * 4 + b]) b = k;
  dom[v] = J[v * 4 + b];
}
const far = (v) => Math.hypot(P[v * 3] - head[0], P[v * 3 + 1] - head[1], P[v * 3 + 2] - head[2]) >= RIFLE_MIN;
const ok = (v) => dom[v] === ring && far(v);
const map = new Map();
const tris = [];
for (let t = 0; t < idx.length; t += 3) {
  const a = idx[t], b = idx[t + 1], c = idx[t + 2];
  if (!(ok(a) && ok(b) && ok(c))) continue;
  tris.push(a, b, c);
  for (const v of [a, b, c]) if (!map.has(v)) map.set(v, map.size);
}
console.log('소총 삼각형', tris.length / 3, '꼭짓점', map.size, '손뼈 머리', head.map((x) => +x.toFixed(3)));
// 알베도: 소총 UV 가 원본 아틀라스 전체에 흩어져 있어서 자르지 않고, 삼각형마다 UV 무게중심의 색을 뽑아 작은 팔레트 그림 (칸 하나 = 삼각형 하나) 으로 — 저폴리 툰 모양에 맞고 그림이 아주 작음.
const tex = prim.getMaterial().getBaseColorTexture();
const raw = await sharp(Buffer.from(tex.getImage())).removeAlpha().raw().toBuffer({ resolveWithObject: true });
const tw = raw.info.width, th = raw.info.height;
const nt = tris.length / 3;
const side = Math.ceil(Math.sqrt(nt));
const pal = Buffer.alloc(side * side * 3, 128);
for (let t = 0; t < nt; t++) {
  let u = 0, w = 0;
  for (let k = 0; k < 3; k++) { u += UV[tris[t * 3 + k] * 2]; w += UV[tris[t * 3 + k] * 2 + 1]; }
  const x = Math.min(tw - 1, Math.max(0, Math.floor((u / 3) * tw))), y = Math.min(th - 1, Math.max(0, Math.floor((w / 3) * th)));
  for (let c = 0; c < 3; c++) pal[t * 3 + c] = raw.data[(y * tw + x) * 3 + c];
}
const palpng = await sharp(pal, { raw: { width: side, height: side, channels: 3 } }).png().toBuffer();
console.log('팔레트', side + 'x' + side, nt, '칸');
// 새 문서 (삼각형마다 꼭짓점 따로 — 칸 가운데 UV)
const out = new (doc.constructor)();
const buf = out.createBuffer();
const np = new Float32Array(nt * 9), nn = new Float32Array(nt * 9), nu = new Float32Array(nt * 6);
for (let t = 0; t < nt; t++) {
  const cu = ((t % side) + 0.5) / side, cv = (Math.floor(t / side) + 0.5) / side;
  for (let k = 0; k < 3; k++) {
    const v = tris[t * 3 + k], o = (t * 3 + k);
    const x = P[v * 3], y = P[v * 3 + 1], z = P[v * 3 + 2];
    for (let r = 0; r < 3; r++) np[o * 3 + r] = M[r] * x + M[4 + r] * y + M[8 + r] * z + M[12 + r];
    const nx = N[v * 3], ny = N[v * 3 + 1], nz = N[v * 3 + 2];
    for (let r = 0; r < 3; r++) nn[o * 3 + r] = M[r] * nx + M[4 + r] * ny + M[8 + r] * nz;
    nu[o * 2] = cu;
    nu[o * 2 + 1] = cv;
  }
}
const ni = new Uint16Array(nt * 3).map((_, i) => i);
const acc = (type, arr) => out.createAccessor().setType(type).setArray(arr).setBuffer(buf);
const t2 = out.createTexture('hunter_rifle_palette').setImage(palpng).setMimeType('image/png');
const mat = out.createMaterial('hunter_rifle').setBaseColorTexture(t2).setMetallicFactor(0).setRoughnessFactor(1).setDoubleSided(true);
const p = out.createPrimitive().setMaterial(mat).setIndices(acc('SCALAR', ni)).setAttribute('POSITION', acc('VEC3', np)).setAttribute('NORMAL', acc('VEC3', nn)).setAttribute('TEXCOORD_0', acc('VEC2', nu));
const mesh = out.createMesh('hunter_rifle').addPrimitive(p);
const nd = out.createNode('hunter_rifle').setMesh(mesh);
out.createScene('s').addChild(nd);
await io.write(dst, out);
console.log('wrote', dst);
