// W40 천·망토·코트 2차 모션 뼈: 이미 리깅해 둔 ext/<이름>.glb 에 뼈 사슬 (mixamorig:<Prefix><n><i>) 을 더하고 stage·판 LOD (<이름>_lod0~N) 에 같은 규칙으로 가중치를 옮김.
// 닌자 목도리 (ninja_scarf.py, Blender) 를 일반화하되 Blender 를 다시 돌리지 않음 — stage·1인칭 팔·마스크·재질·텍스처는 글자 그대로 두고 (relod·maskbake 결과와 호환),
// 새 뼈는 스킨 마지막에 붙여 기존 뼈 번호가 안 바뀜 (애니메이션 클립 .glb·JOINTS_0 호환). 선택은 꼭짓점 단위 규칙이라 LOD 마다 따로 셈해도 같은 천을 가리킴.
// 실행: node cloth_bones.mjs <입력.glb> <출력.glb> <hunter|hook|tank> [--debug <폴더>]   (NODE_PATH 대신 @gltf-transform/core·sharp 가 있는 node_modules 안에서)
import { NodeIO } from '@gltf-transform/core';
import sharp from 'sharp';
import fs from 'fs';

const [src, dst, CH, ...rest] = process.argv.slice(2);
const dbgDir = rest.includes('--debug') ? rest[rest.indexOf('--debug') + 1] : null;
const P = 'mixamorig:';

const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

// ---------- 캐릭터별 규칙 ----------
// sel(ctx) → {m: 0~1 천인 정도, u: 가로 좌표 (사슬 가르기)}.  ctx = {p: [x,y,z], rgb, mask (UV2.x), bone (이름→[x,y,z])}
// ytop·ybot 은 사슬 세로 범위, N = 사슬 뼈 수, prefix = 뼈 이름, a0·a1 = 가중치 섞임 (위쪽 몸통 가중치 → 천 가중치) 구간 (세로 0~1 비율)
const CHARS = {
  // 사냥꾼 초록 망토: 올리브 색 칸, 목깃 (크림) 아래, 몸 뒤쪽 (앞 가장자리는 서서히 빠짐)
  hunter: {
    parent: 'Spine2', prefix: 'Cape', chains: 3, N: 3, ytop: 0.70, ybot: 0.10, a0: 0.0, a1: 0.55, axisU: 2,
    sel: ({ p, rgb, bone }) => {
      const [r, g, b] = rgb;
      const olive = r < g * 1.1 && g > b * 1.02 && !(r > 170 && g > 150 && b > 120); // 가죽 (붉은 갈색)·크림 털 뺌, 그늘진 짙은 올리브 포함
      if (!olive) return { m: 0, u: p[2] };
      const xs = bone.Spine[0];
      const back = sstep(xs + 0.07, xs - 0.05, p[0]);
      const below = sstep(0.74, 0.62, p[1]) ; // 목깃·어깨 위는 안 움직임
      return { m: back * below, u: p[2] };
    },
  },
  // 탱크 붉은 천 (몸 색 칸 UV2.x): 등 뒤로 늘어진 긴 천 (몸 뒤 x < xs) + 목도리 꼬리
  tank: {
    parent: 'Spine2', prefix: 'Tabard', chains: 2, N: 3, ytop: 0.66, ybot: 0.08, a0: 0.0, a1: 0.5, axisU: 2,
    sel: ({ p, mask, bone }) => {
      if (mask < 0.5) return { m: 0, u: p[2] };
      const xs = bone.Spine1[0];
      const back = sstep(xs - 0.0, xs - 0.05, p[0]); // 뒤쪽
      const lowish = sstep(0.72, 0.62, p[1]);
      return { m: back * lowish, u: p[2] };
    },
  },
  // 갈고리 코트 자락: 엉덩이 아래 코트 (다리 축에서 먼 것), 부츠 위
  hook: {
    parent: 'Hips', prefix: 'Skirt', chains: 3, N: 3, ytop: 0.46, ybot: 0.17, a0: 0.0, a1: 0.5, axisU: -1,
    sel: ({ p, bone }) => {
      const dleg = Math.min(segDist(p, bone.LeftUpLeg, bone.LeftLeg), segDist(p, bone.LeftLeg, bone.LeftFoot), segDist(p, bone.RightUpLeg, bone.RightLeg), segDist(p, bone.RightLeg, bone.RightFoot));
      const out = sstep(0.075, 0.11, dleg);
      const y = sstep(0.47, 0.40, p[1]) * sstep(0.18, 0.21, p[1]);
      const hx = bone.Hips[0], hz = bone.Hips[2];
      const ang = Math.atan2(p[2] - hz, p[0] - hx); // 앞 +x 가 0, 뒤 ±π, 왼 -z (-π/2)
      return { m: out * y, u: ang };
    },
  },
};

function segDist(p, a, b) {
  const ab = [b[0] - a[0], b[1] - a[1], b[2] - a[2]], ap = [p[0] - a[0], p[1] - a[1], p[2] - a[2]];
  const l2 = ab[0] ** 2 + ab[1] ** 2 + ab[2] ** 2 || 1e-9;
  const t = Math.min(1, Math.max(0, (ap[0] * ab[0] + ap[1] * ab[1] + ap[2] * ab[2]) / l2));
  const q = [a[0] + ab[0] * t - p[0], a[1] + ab[1] * t - p[1], a[2] + ab[2] * t - p[2]];
  return Math.hypot(q[0], q[1], q[2]);
}

// 4x4 (열 우선) 곱·역행렬
function mul(a, b) { const o = new Array(16).fill(0); for (let c = 0; c < 4; c++) for (let r = 0; r < 4; r++) for (let k = 0; k < 4; k++) o[c * 4 + r] += a[k * 4 + r] * b[c * 4 + k]; return o; }
function inv(m) {
  const i = new Array(16), [a00, a01, a02, a03, a10, a11, a12, a13, a20, a21, a22, a23, a30, a31, a32, a33] = m;
  const b00 = a00 * a11 - a01 * a10, b01 = a00 * a12 - a02 * a10, b02 = a00 * a13 - a03 * a10, b03 = a01 * a12 - a02 * a11, b04 = a01 * a13 - a03 * a11, b05 = a02 * a13 - a03 * a12;
  const b06 = a20 * a31 - a21 * a30, b07 = a20 * a32 - a22 * a30, b08 = a20 * a33 - a23 * a30, b09 = a21 * a32 - a22 * a31, b10 = a21 * a33 - a23 * a31, b11 = a22 * a33 - a23 * a32;
  let d = b00 * b11 - b01 * b10 + b02 * b09 + b03 * b08 - b04 * b07 + b05 * b06; d = 1 / d;
  i[0] = (a11 * b11 - a12 * b10 + a13 * b09) * d; i[1] = (a02 * b10 - a01 * b11 - a03 * b09) * d; i[2] = (a31 * b05 - a32 * b04 + a33 * b03) * d; i[3] = (a22 * b04 - a21 * b05 - a23 * b03) * d;
  i[4] = (a12 * b08 - a10 * b11 - a13 * b07) * d; i[5] = (a00 * b11 - a02 * b08 + a03 * b07) * d; i[6] = (a32 * b02 - a30 * b05 - a33 * b01) * d; i[7] = (a20 * b05 - a22 * b02 + a23 * b01) * d;
  i[8] = (a10 * b10 - a11 * b08 + a13 * b06) * d; i[9] = (a01 * b08 - a00 * b10 - a03 * b06) * d; i[10] = (a30 * b04 - a31 * b02 + a33 * b00) * d; i[11] = (a21 * b02 - a20 * b04 - a23 * b00) * d;
  i[12] = (a11 * b07 - a10 * b09 - a12 * b06) * d; i[13] = (a00 * b09 - a01 * b07 + a02 * b06) * d; i[14] = (a31 * b01 - a30 * b03 - a32 * b00) * d; i[15] = (a20 * b03 - a21 * b01 + a22 * b00) * d;
  return i;
}
const trans = (x, y, z) => [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, x, y, z, 1];

const cfg = CHARS[CH];
if (!cfg) throw new Error('모르는 캐릭터 ' + CH);
const io = new NodeIO();
const doc = await io.read(src);
const root = doc.getRoot();
const stage = root.listNodes().find((n) => n.getName() === CH + '_lod0');
const skin = stage.getSkin();
const joints = skin.listJoints();
if (joints.some((j) => j.getName().startsWith(P + cfg.prefix))) throw new Error('이미 천 뼈가 있음');
const jIdx = new Map(joints.map((j, i) => [j.getName(), i]));
const bone = {};
for (const j of joints) { const m = j.getWorldMatrix(); bone[j.getName().slice(P.length)] = [m[12], m[13], m[14]]; }
const parentNode = joints[jIdx.get(P + cfg.parent)];

// 메시 (lod0~N, vm 은 팔뿐이라 뺌) 마다 꼭짓점 정보
const meshNodes = root.listNodes().filter((n) => new RegExp('^' + CH + '_lod\\d+$').test(n.getName()));
async function texSampler(prim) {
  const tex = prim.getMaterial()?.getBaseColorTexture();
  if (!tex) return () => [128, 128, 128];
  const { data, info } = await sharp(Buffer.from(tex.getImage())).removeAlpha().raw().toBuffer({ resolveWithObject: true });
  return (u, v) => {
    const x = Math.min(info.width - 1, Math.max(0, Math.floor(u * info.width))), y = Math.min(info.height - 1, Math.max(0, Math.floor(v * info.height)));
    const o = (y * info.width + x) * 3;
    return [data[o], data[o + 1], data[o + 2]];
  };
}
const infoByNode = new Map();
for (const n of meshNodes) {
  const prim = n.getMesh().listPrimitives()[0];
  const pos = prim.getAttribute('POSITION').getArray(), uv = prim.getAttribute('TEXCOORD_0').getArray();
  const uv2 = prim.getAttribute('TEXCOORD_1')?.getArray();
  const samp = await texSampler(prim);
  const cnt = pos.length / 3;
  const m = new Float32Array(cnt), u = new Float32Array(cnt);
  for (let i = 0; i < cnt; i++) {
    const p = [pos[i * 3], pos[i * 3 + 1], pos[i * 3 + 2]];
    const r = cfg.sel({ p, rgb: samp(uv[i * 2], uv[i * 2 + 1]), mask: uv2 ? uv2[i * 2] : 0, bone });
    m[i] = r.m; u[i] = r.u;
  }
  infoByNode.set(n, { prim, m, u, pos, cnt });
}

// 사슬 가르기: stage 의 천 꼭짓점 u 분위수 → 가운데 u (chains 개)
const st = infoByNode.get(stage);
const us = [];
for (let i = 0; i < st.cnt; i++) if (st.m[i] > 0.5) us.push(st.u[i]);
us.sort((a, b) => a - b);
if (us.length < 100) throw new Error('천 꼭짓점이 너무 적음 ' + us.length);
let centers;
if (cfg.axisU === -1) { // 둘레 각: 뒤 (±π) 를 가운데로 접어 연속으로 (각 → 뒤 기준 -π..π 로 돌려 분위수)
  centers = [];
  const f = us.map((a) => (a >= 0 ? a - Math.PI : a + Math.PI)).sort((a, b) => a - b); // 뒤 = 0
  for (let k = 0; k < cfg.chains; k++) centers.push(f[Math.floor(f.length * (k + 0.5) / cfg.chains)]);
} else {
  centers = [];
  for (let k = 0; k < cfg.chains; k++) centers.push(us[Math.floor(us.length * (k + 0.5) / cfg.chains)]);
}
const toU = (u) => (cfg.axisU === -1 ? (u >= 0 ? u - Math.PI : u + Math.PI) : u);
console.log('TF 천', CH, '꼭짓점', us.length, '사슬 가운데', centers.map((c) => +c.toFixed(3)));

// 사슬 k 의 세로 단계 y_i (N+1 개): ytop → ybot 균등
const N = cfg.N;
const ys = []; for (let i = 0; i <= N; i++) ys.push(cfg.ytop - (cfg.ytop - cfg.ybot) * i / N);
// 사슬 가로 위치 (x,z): stage 의 가까운 높이대 천 꼭짓점 평균 (가로 가중 hat)
const latW = (u, k) => { // 사슬 k 에 대한 가로 hat (가까운 둘 사이 선형 보간)
  const uu = toU(u);
  const c = centers;
  if (uu <= c[0]) return k === 0 ? 1 : 0;
  if (uu >= c[c.length - 1]) return k === c.length - 1 ? 1 : 0;
  for (let q = 0; q < c.length - 1; q++) if (uu >= c[q] && uu <= c[q + 1]) {
    const t = (uu - c[q]) / Math.max(1e-6, c[q + 1] - c[q]);
    return k === q ? 1 - t : k === q + 1 ? t : 0;
  }
  return 0;
};
const heads = []; // [k][i] = [x,y,z]
for (let k = 0; k < cfg.chains; k++) {
  const row = [];
  for (let i = 0; i <= N; i++) {
    let sx = 0, sz = 0, sw = 0;
    const band = (cfg.ytop - cfg.ybot) / N * 0.6;
    for (let q = 0; q < st.cnt; q++) {
      if (st.m[q] < 0.5) continue;
      const y = st.pos[q * 3 + 1];
      if (Math.abs(y - ys[i]) > band) continue;
      const w = latW(st.u[q], k) * st.m[q];
      if (w <= 0) continue;
      sx += st.pos[q * 3] * w; sz += st.pos[q * 3 + 2] * w; sw += w;
    }
    if (sw < 1e-6) { // 비면 위 단계 연장
      const prev = row[row.length - 1] || [bone[cfg.parent][0], ys[i], bone[cfg.parent][2]];
      row.push([prev[0], ys[i], prev[2]]);
    } else row.push([sx / sw, ys[i], sz / sw]);
  }
  // 머리는 몸 가까이: 첫 단계는 부모 뼈 x (등) 쪽으로 당김
  heads.push(row);
}

// 뼈 노드 만들기 (부모 = 부모 뼈, 세계 회전 항등)
const names = [], newNodes = [];
const pw = parentNode.getWorldMatrix();
for (let k = 0; k < cfg.chains; k++) {
  let prev = parentNode, prevW = pw;
  for (let i = 0; i < N; i++) {
    const nm = P + cfg.prefix + (k + 1) + '_' + (i + 1);
    const nd = doc.createNode(nm);
    const h = heads[k][i];
    const wm = trans(h[0], h[1], h[2]);
    const loc = mul(inv(prevW), wm); // 부모 세계 → 지역 (세계 회전 항등이 되게)
    nd.setMatrix(loc);
    prev.addChild(nd);
    prev = nd; prevW = wm;
    names.push(nm); newNodes.push({ nd, wm, k, i });
  }
}
// 스킨: 관절 추가 + 역바인드
const oldIbm = skin.getInverseBindMatrices();
const total = joints.length + newNodes.length;
const arr = new Float32Array(total * 16);
arr.set(oldIbm.getArray());
newNodes.forEach((e, q) => {
  skin.addJoint(e.nd);
  arr.set(inv(e.wm), (joints.length + q) * 16); // 메시·뼈대 노드 세계 변환이 항등이라 역바인드 = 뼈 세계의 역
});
const ibmAcc = doc.createAccessor().setType('MAT4').setArray(arr).setBuffer(oldIbm.getBuffer());
skin.setInverseBindMatrices(ibmAcc);
oldIbm.dispose();

// 가중치
const newIdx = (k, i) => joints.length + k * N + i;
const dbg = {};
for (const n of meshNodes) {
  const { prim, m, u, pos, cnt } = infoByNode.get(n);
  const J = prim.getAttribute('JOINTS_0'), W = prim.getAttribute('WEIGHTS_0');
  const ja = J.getArray(), wa = W.getArray();
  const need16 = total > 255;
  if (need16 && ja.BYTES_PER_ELEMENT === 1) throw new Error('뼈 수 255 초과');
  const ymax = cfg.ytop, ymin = cfg.ybot, span = ymax - ymin;
  const d = new Float32Array(cnt);
  let moved = 0;
  for (let i = 0; i < cnt; i++) {
    if (m[i] < 0.02) continue;
    const y = pos[i * 3 + 1];
    const s = Math.min(1, Math.max(0, (ymax - y) / span)); // 0 (위) ~ 1 (아래)
    const a = sstep(cfg.a0, cfg.a1, s) * m[i];
    d[i] = a;
    if (a < 0.01) continue;
    const sN = s * N; // 0~N
    const nw = new Map();
    for (let k = 0; k < cfg.chains; k++) {
      const lw = latW(u[i], k);
      if (lw <= 0) continue;
      for (let b = 0; b < N; b++) {
        let hat = Math.max(0, 1 - Math.abs(sN - (b + 0.5)));
        if (sN < 0.5 && b === 0) hat = 1;
        if (sN > N - 0.5 && b === N - 1) hat = 1;
        if (hat > 0) nw.set(newIdx(k, b), (nw.get(newIdx(k, b)) || 0) + lw * hat);
      }
    }
    let tot = 0; for (const v of nw.values()) tot += v;
    if (tot <= 0) continue;
    const all = new Map();
    for (let q = 0; q < 4; q++) { const w = wa[i * 4 + q]; if (w > 0) all.set(ja[i * 4 + q], (all.get(ja[i * 4 + q]) || 0) + w * (1 - a)); }
    for (const [j, v] of nw) all.set(j, (all.get(j) || 0) + a * v / tot);
    const top = [...all.entries()].filter(([, w]) => w > 0.002).sort((x, y2) => y2[1] - x[1]).slice(0, 4);
    const sum = top.reduce((t, e) => t + e[1], 0) || 1;
    for (let q = 0; q < 4; q++) {
      if (q < top.length) { ja[i * 4 + q] = top[q][0]; wa[i * 4 + q] = top[q][1] / sum; } else { ja[i * 4 + q] = 0; wa[i * 4 + q] = 0; }
    }
    moved++;
  }
  J.setArray(ja); W.setArray(wa);
  console.log('TF', n.getName(), '꼭짓점', cnt, '천 가중치', moved);
  dbg[n.getName()] = Array.from(d);
}
if (dbgDir) { fs.mkdirSync(dbgDir, { recursive: true }); fs.writeFileSync(dbgDir + '/' + CH + '_a.json', JSON.stringify(dbg[CH + '_lod0'])); fs.writeFileSync(dbgDir + '/' + CH + '_heads.json', JSON.stringify(heads)); }
await io.write(dst, doc);
console.log('TF 천 뼈', names.join(' '));
