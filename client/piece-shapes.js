// 테마별 테트리미노 칸 모양 (piece-look.js 가 씀). 칸 하나 = 지오메트리 하나 (InstancedMesh 라 그리기 수 그대로), 부품을 합쳐 만듦.
// 모든 부품은 position·normal·uv·aAcc (0 조각 색 · 1 accent[0] · 2 accent[1] — 버섯 흰 점·대·금 테·잎) 를 가짐. 칸 크기 size 안 (가운데 원점)
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { ConvexGeometry } from 'three/addons/geometries/ConvexGeometry.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

export const PIECE_SHAPES = ['round', 'gem', 'bricks', 'cap', 'crate', 'framed'];

// 부품 하나: 인덱스 없이, 행렬 적용, uv 없으면 (또는 proj) 칸 기준 상자 투영으로 (벽돌 여러 장에 무늬 하나가 이어짐), aAcc 채움
function part(geo, m, acc = 0, proj = false) {
  const g = geo.index ? geo.toNonIndexed() : geo;
  if (m) g.applyMatrix4(m);
  if (!g.attributes.normal) g.computeVertexNormals();
  if (!g.attributes.uv || proj) {
    const p = g.attributes.position;
    const n = g.attributes.normal;
    const uv = new Float32Array(p.count * 2);
    for (let i = 0; i < p.count; i++) {
      const ax = Math.abs(n.getX(i)), ay = Math.abs(n.getY(i)), az = Math.abs(n.getZ(i));
      const [u, v] = az >= ax && az >= ay ? [p.getX(i), p.getY(i)] : ax >= ay ? [p.getY(i), p.getZ(i)] : [p.getX(i), p.getZ(i)];
      uv[i * 2] = u + 0.5;
      uv[i * 2 + 1] = v + 0.5;
    }
    g.setAttribute('uv', new THREE.BufferAttribute(uv, 2));
  }
  for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
  g.setAttribute('aAcc', new THREE.BufferAttribute(new Float32Array(g.attributes.position.count).fill(acc), 1));
  return g;
}
const T = (x, y, z) => new THREE.Matrix4().makeTranslation(x, y, z);
const S = (x, y, z) => new THREE.Matrix4().makeScale(x, y, z);
const zUp = () => new THREE.Matrix4().makeRotationX(Math.PI / 2); // +Y → +Z

// 깎인 보석: 모서리 잘린 정육면체 + 면마다 낮은 피라미드 (여러 면이 각진 모양)
function gem(s) {
  const h = s / 2 - 0.05;
  const c = h * 0.42;
  const pts = [];
  for (const sx of [-1, 1]) for (const sy of [-1, 1]) for (const sz of [-1, 1]) {
    pts.push(new THREE.Vector3(sx * h, sy * h, sz * (h - c)), new THREE.Vector3(sx * h, sy * (h - c), sz * h), new THREE.Vector3(sx * (h - c), sy * h, sz * h));
  }
  const p = 0.05;
  for (const a of [0, 1, 2]) for (const sg of [-1, 1]) {
    const v = new THREE.Vector3();
    v.setComponent(a, sg * (h + p));
    pts.push(v);
  }
  return [part(new ConvexGeometry(pts))];
}

// 벽돌 층: rows 줄, 줄마다 반으로 나눔 (x·y 번갈아 → 네 옆면 모두 어긋난 쌓기), 줄 사이·벽돌 사이 줄눈. 벽돌마다 조금 들쭉날쭉
function bricks(s, rows, gap, bevel) {
  const out = [];
  const rh = (s - gap * (rows - 1)) / rows;
  let seed = 7;
  const rnd = () => ((seed = (seed * 1103515245 + 12345) & 0x7fffffff) / 0x7fffffff);
  for (let r = 0; r < rows; r++) {
    const z = -s / 2 + rh / 2 + r * (rh + gap);
    const alongX = r % 2 === 0;
    const split = 0.38 + rnd() * 0.24; // 나누는 자리 (가운데 근처)
    const a0 = -s / 2;
    const cut = a0 + s * split;
    for (const [lo, hi] of [[a0, cut - gap / 2], [cut + gap / 2, s / 2]]) {
      const len = hi - lo;
      const inset = rnd() * 0.025;
      const w = s - inset * 2;
      const sx = alongX ? len : w;
      const sy = alongX ? w : len;
      const g = new RoundedBoxGeometry(sx, sy, rh, 1, Math.min(bevel, rh / 3));
      out.push(part(g, alongX ? T((lo + hi) / 2, 0, z) : T(0, (lo + hi) / 2, z), 0, true));
    }
  }
  return out;
}

// 버섯 갓: 크림색 밑동 + 위가 볼록한 갓 (조각 색) + 큰 흰 점
function cap(s) {
  const base = s * 0.5;
  const out = [part(new RoundedBoxGeometry(s * 0.8, s * 0.8, base, 1, 0.06), T(0, 0, -s / 2 + base / 2), 2)];
  const r = s * 0.5;
  const dz = s * 0.5; // 갓 높이
  const z0 = -s / 2 + base * 0.7;
  out.push(part(new THREE.SphereGeometry(1, 12, 5, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.Matrix4().multiplyMatrices(T(0, 0, z0), new THREE.Matrix4().multiplyMatrices(S(r, r, dz), zUp()))));
  // 갓 아래 받침 (갓 둘레가 떠 보이지 않게)
  out.push(part(new THREE.CylinderGeometry(r, r * 0.92, s * 0.08, 12), new THREE.Matrix4().multiplyMatrices(T(0, 0, z0 - s * 0.04), zUp())));
  const spots = [[0, 0, 1], [0.62, 0.15, 0.55], [-0.45, 0.5, 0.6], [-0.3, -0.6, 0.55], [0.35, -0.5, 0.62]];
  for (const [x, y, k] of spots) {
    const n = new THREE.Vector3(x, y, k).normalize();
    const p = new THREE.Vector3(n.x * r, n.y * r, n.z * dz + z0);
    const q = new THREE.Quaternion().setFromUnitVectors(new THREE.Vector3(0, 0, 1), new THREE.Vector3(n.x / r, n.y / r, n.z / dz).normalize());
    const m = new THREE.Matrix4().compose(p, q, new THREE.Vector3(s * 0.11, s * 0.11, s * 0.035));
    out.push(part(new THREE.IcosahedronGeometry(1, 0), m, 1));
  }
  return out;
}

// 나무 상자 (판자 결은 텍스처) + 윗면 한쪽 잎 덤불 (accent[0])
function crate(s, bevel) {
  const out = [part(new RoundedBoxGeometry(s, s, s, 1, bevel))];
  const h = s / 2;
  for (const [x, y, z, r] of [[h * 0.45, h * 0.45, h + 0.02, 0.17], [h * 0.1, h * 0.62, h + 0.0, 0.12], [h * 0.65, h * 0.05, h - 0.01, 0.11]]) {
    out.push(part(new THREE.IcosahedronGeometry(r, 0), new THREE.Matrix4().multiplyMatrices(T(x, y, z - 0.03), S(1, 1, 0.75)), 1));
  }
  return out;
}

// 대리석 몸 + 굵은 금 테 (모서리 12개 + 면 가운데 마름모, accent[0])
function framed(s) {
  const t = s * 0.12;
  const h = s / 2 - t / 2;
  const out = [part(new THREE.BoxGeometry(s - t * 0.6, s - t * 0.6, s - t * 0.6))];
  for (let a = 0; a < 3; a++) {
    for (const u of [-1, 1]) for (const v of [-1, 1]) {
      const size = [t, t, t];
      size[a] = s;
      const pos = [0, 0, 0];
      pos[(a + 1) % 3] = u * h;
      pos[(a + 2) % 3] = v * h;
      out.push(part(new THREE.BoxGeometry(...size), T(...pos), 1));
    }
  }
  for (let a = 0; a < 3; a++) for (const sg of [-1, 1]) {
    const pos = [0, 0, 0];
    pos[a] = sg * (s / 2 - t * 0.3);
    const rot = new THREE.Matrix4();
    if (a === 0) rot.makeRotationY(Math.PI / 2);
    else if (a === 1) rot.makeRotationX(Math.PI / 2);
    const dia = new THREE.Matrix4().multiplyMatrices(rot, new THREE.Matrix4().makeRotationZ(Math.PI / 4));
    out.push(part(new THREE.BoxGeometry(s * 0.22, s * 0.22, t * 0.5), new THREE.Matrix4().multiplyMatrices(T(...pos), dia), 1));
  }
  return out;
}

// spec = pieceSpec 결과. low = 그래픽 낮춤 → 둥근 상자 하나 (모서리 한 단)
export function pieceGeometry(spec, low) {
  const s = spec.size;
  const shape = low ? 'round' : spec.shape || 'round';
  let parts;
  if (shape === 'gem') parts = gem(s);
  else if (shape === 'bricks') parts = bricks(s, spec.rows || 3, spec.gap || 0.04, spec.bevel);
  else if (shape === 'cap') parts = cap(s);
  else if (shape === 'crate') parts = crate(s, spec.bevel);
  else if (shape === 'framed') parts = framed(s);
  else parts = [part(new RoundedBoxGeometry(s, s, s, low ? 1 : spec.segs, spec.bevel))];
  const g = parts.length === 1 ? parts[0] : mergeGeometries(parts);
  g.computeBoundingBox();
  g.computeBoundingSphere();
  return g;
}
