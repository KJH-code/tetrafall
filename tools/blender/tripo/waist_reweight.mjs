// W46 허리 장갑·벨트 스킨 늘어남 수리: 이미 리깅해 둔 ext/<이름>.glb 의 stage·판 LOD (<이름>_lod0~N) 가중치만 고쳐 다시 씀 (뼈·UV·텍스처·마스크·뼈 번호·애니메이션 그대로, Blender·relod 를 다시 안 돌림 — cloth_bones.mjs 와 같은 방식).
// 원인 (tools/motion_qa 삼각형 늘어남 ×12~18): 자동 가중치가 골반 높이 (벨트·허리 장갑·엉덩이 옆 천 판) 에서 이웃 꼭짓점끼리 가중치가 크게 다름 (허벅지 뼈 0.48 ↔ 천 뼈·척추 0.25 …) →
// 다리를 들고 윗몸을 숙이면 (공격 동작) 이웃 두 꼭짓점이 서로 다른 변환을 받아 0.02m 짜리 변이 0.26m 로 늘어남.
// 고침 = 골반 둘레 (높이 yMin..yMax) 꼭짓점 가중치를 이웃끼리 부드럽게 (라플라스 평활: 위치가 같은 꼭짓점은 한 점으로 묶어 UV 이음선이 갈라지지 않게, 가중치 합 1·꼭짓점당 뼈 4 개 유지)
// + 선택적으로 (--hips) 엉덩이 관절보다 위 꼭짓점의 허벅지 가중치를 골반 (Hips) 으로, 아래 꼭짓점의 척추 가중치를 허벅지 (천 꼭짓점은 Hips) 로 옮김.
// 실행: node waist_reweight.mjs <입력.glb> <출력.glb> <이름> [--ymin 0.05 --ymax 0.62 --iters 20 --lam 0.5 --arms --hips --lo --hi --hi2]   (@gltf-transform/core 가 있는 node_modules 안에서)
import { NodeIO } from '@gltf-transform/core';

const [src, dst, CH, ...rest] = process.argv.slice(2);
const opt = (k, d) => (rest.includes(k) ? parseFloat(rest[rest.indexOf(k) + 1]) : d);
const YMIN = opt('--ymin', 0.05), YMAX = opt('--ymax', 0.62), ITERS = opt('--iters', 20), LAM = opt('--lam', 0.5);
const DO_HIPS = rest.includes('--hips');
const ARMS = rest.includes('--arms'); // 어깨 장갑 (어깨뼈·위팔) 둘레도 같이 평활
const LO = opt('--lo', 0.1), HI = opt('--hi', 0.1), HI2 = opt('--hi2', 0.12), CLOTH = opt('--cloth', 0.15);
const CLEAN0 = opt('--clean', 0.08); // ⓪ 시작 (엉덩이 관절 위 m), 아주 크게 주면 끔
const P = 'mixamorig:';
const sstep = (a, b, x) => { const t = Math.min(1, Math.max(0, (x - a) / (b - a))); return t * t * (3 - 2 * t); };

const io = new NodeIO();
const doc = await io.read(src);
const root = doc.getRoot();
const stage = root.listNodes().find((n) => n.getName() === CH + '_lod0');
const joints = stage.getSkin().listJoints();
const idx = new Map(joints.map((j, i) => [j.getName(), i]));
const J = (n) => idx.get(P + n);
const hips = J('Hips'), lUp = J('LeftUpLeg'), rUp = J('RightUpLeg');
const spineSet = new Set([J('Spine'), J('Spine1'), J('Spine2')]);
const clothSet = new Set([...idx.entries()].filter(([n]) => n.startsWith(P + 'Tabard')).map(([, i]) => i));
const yh = joints[lUp].getWorldMatrix()[13];
const zL = joints[lUp].getWorldMatrix()[14];
console.log('WR 엉덩이 관절 y', yh.toFixed(3), '왼 z', zL.toFixed(3));

const meshNodes = root.listNodes().filter((n) => new RegExp('^' + CH + '_lod\\d+$').test(n.getName()));
for (const n of meshNodes) {
  const prim = n.getMesh().listPrimitives()[0];
  const pos = prim.getAttribute('POSITION').getArray();
  const Ja = prim.getAttribute('JOINTS_0'), Wa = prim.getAttribute('WEIGHTS_0');
  const ja = Ja.getArray(), wa = Wa.getArray();
  const idxArr = prim.getIndices().getArray();
  const cnt = pos.length / 3;
  // 위치가 같은 꼭짓점 묶기
  const key = (i) => Math.round(pos[i * 3] * 1e4) + ',' + Math.round(pos[i * 3 + 1] * 1e4) + ',' + Math.round(pos[i * 3 + 2] * 1e4);
  const gid = new Int32Array(cnt);
  const gmap = new Map();
  const members = [];
  for (let i = 0; i < cnt; i++) {
    const k = key(i);
    let g = gmap.get(k);
    if (g === undefined) { g = members.length; gmap.set(k, g); members.push([]); }
    gid[i] = g; members[g].push(i);
  }
  const G = members.length;
  // 묶음 가중치 (첫 꼭짓점 것 — 같은 자리 꼭짓점은 원래 같은 가중치) 와 이웃
  let W = new Array(G);
  const gy = new Float32Array(G), gz = new Float32Array(G);
  for (let g = 0; g < G; g++) {
    const i = members[g][0];
    const m = new Map();
    for (let q = 0; q < 4; q++) if (wa[i * 4 + q] > 0) m.set(ja[i * 4 + q], (m.get(ja[i * 4 + q]) || 0) + wa[i * 4 + q]);
    W[g] = m; gy[g] = pos[i * 3 + 1]; gz[g] = pos[i * 3 + 2];
  }
  const nb = Array.from({ length: G }, () => new Set());
  for (let t = 0; t < idxArr.length; t += 3) {
    for (let a = 0; a < 3; a++) {
      const g1 = gid[idxArr[t + a]], g2 = gid[idxArr[t + (a + 1) % 3]];
      if (g1 !== g2) { nb[g1].add(g2); nb[g2].add(g1); }
    }
  }
  // 팔·손 가중치가 센 꼭짓점은 건드리지 않음 (어깨·팔 은 이 작업 대상이 아님)
  const BODY = new Set([hips, lUp, rUp, J('LeftLeg'), J('RightLeg'), ...spineSet, ...clothSet]);
  if (ARMS) for (const nm of ['LeftShoulder', 'LeftArm', 'RightShoulder', 'RightArm', 'Neck']) BODY.add(J(nm));
  const active = new Uint8Array(G);
  let nAct = 0;
  for (let g = 0; g < G; g++) {
    let body = 0;
    for (const [j, v] of W[g]) if (BODY.has(j)) body += v;
    active[g] = gy[g] >= YMIN && gy[g] <= (ARMS ? Math.max(YMAX, 0.85) : YMAX) && body > 0.9 ? 1 : 0;
    nAct += active[g];
  }
  const touched = new Uint8Array(G);
  const clean = () => {
    for (let g = 0; g < G; g++) {
      const y = gy[g];
      if (y < yh + CLEAN0) continue;
      const a = sstep(yh + CLEAN0, yh + CLEAN0 + 0.06, y);
      const w = W[g];
      for (const up of [lUp, rUp]) { const v = w.get(up) || 0; if (v > 0 && a > 0) { const mv = v * a; w.set(up, v - mv); w.set(J('Spine1'), (w.get(J('Spine1')) || 0) + mv); touched[g] = 1; } }
    }
  };
  // ⓪ 허벅지 가중치가 엉덩이 관절보다 한참 위 (겨드랑이·가슴 높이) 에 번져 있는 자동 가중치 오류 → 가슴 (Spine1) 으로 (엉덩이 관절 + 0.08 .. + 0.14 에서 점점). 평활이 다시 퍼뜨리지 않게 평활 뒤에도 한 번 더
  clean();
  // ① (--hips) 엉덩이 관절 위쪽 허벅지 → 골반, 아래쪽 척추 → 허벅지·골반
  if (DO_HIPS) {
    for (let g = 0; g < G; g++) {
      if (!active[g]) continue;
      const y = gy[g], w = W[g];
      let cloth = 0;
      for (const [j, v] of w) if (clothSet.has(j)) cloth += v;
      const a1 = sstep(yh - LO, yh + HI, y), a2 = 1 - sstep(yh, yh + HI2, y);
      const add = (j, v) => w.set(j, (w.get(j) || 0) + v);
      for (const up of [lUp, rUp]) { const v = w.get(up) || 0; if (v > 0) { const mv = v * a1; w.set(up, v - mv); add(hips, mv); } }
      for (const sp of spineSet) { const v = w.get(sp) || 0; if (v > 0) { const mv = v * a2; w.set(sp, v - mv); add(cloth >= CLOTH ? hips : (gz[g] < 0 === zL < 0 ? lUp : rUp), mv); } }
    }
  }
  // ② 라플라스 평활 (활성 꼭짓점끼리, 이웃은 활성·비활성 모두 평균에 넣어 경계에서 부드럽게 이어짐)
  for (let it = 0; it < ITERS; it++) {
    const NW = new Array(G);
    for (let g = 0; g < G; g++) {
      if (!active[g] || nb[g].size === 0) { NW[g] = W[g]; continue; }
      const acc = new Map();
      for (const h of nb[g]) for (const [j, v] of W[h]) acc.set(j, (acc.get(j) || 0) + v / nb[g].size);
      const out = new Map();
      for (const [j, v] of W[g]) out.set(j, v * (1 - LAM));
      for (const [j, v] of acc) out.set(j, (out.get(j) || 0) + v * LAM);
      NW[g] = out;
    }
    W = NW;
    clean();
  }
  clean();
  // 되쓰기: 상위 4 개, 정규화
  let changed = 0;
  for (let g = 0; g < G; g++) {
    if (!active[g] && !touched[g]) continue;
    const top = [...W[g].entries()].filter(([, v]) => v > 0.002).sort((a, b) => b[1] - a[1]).slice(0, 4);
    const sum = top.reduce((t, e) => t + e[1], 0) || 1;
    for (const i of members[g]) {
      for (let q = 0; q < 4; q++) {
        if (q < top.length) { ja[i * 4 + q] = top[q][0]; wa[i * 4 + q] = top[q][1] / sum; } else { ja[i * 4 + q] = 0; wa[i * 4 + q] = 0; }
      }
    }
    changed++;
  }
  Ja.setArray(ja); Wa.setArray(wa);
  console.log('WR', n.getName(), '꼭짓점', cnt, '묶음', G, '활성', nAct, '바꿈', changed);
}
await io.write(dst, doc);
console.log('WR wrote', dst);
