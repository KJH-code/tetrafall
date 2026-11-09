// 떨어져 나온 작은 조각 (삼각형으로 이어진 덩어리가 아닌 부스러기) 지우기 (W34): .glb 안 지정한 메시 노드들에서 꼭짓점을 위치로 합쳐 이어진 덩어리를 세고,
// 가장 큰 덩어리 말고 삼각형이 MAX_TRIS (기본 150) 이하인 덩어리를 뺀다. 갈고리는 원본 코트-주먹 한 덩어리에서 떨어진 부스러기가 손가락 뼈 (RightHandIndex3 등) 에 매여
// 팔을 크게 움직이면 허공에서 찢어진 조각으로 따라다녔음 (stage 85+3+1, 판 LOD 33·26·20 개…). 안 쓰는 꼭짓점은 남겨 둠 (색인만 줄임).
// 두 번째 일 (BRIDGE_JSON = {노드 이름: [삼각형 번호…]}, hook_bridge.py 가 만듦): 쉬는 자세에선 작은데 팔을 움직이면 늘어나는 '이음' 삼각형 (주먹과 코트를 잇던) 도 번호로 뺌.
// 실행 (@gltf-transform/core 가 있는 폴더에서): [BRIDGE_JSON=<파일>] node drop_shards.mjs <입력.glb> <출력.glb> <메시 노드 이름,이름…> [MAX_TRIS]
import { NodeIO } from '@gltf-transform/core';
import fs from 'fs';

const [src, dst, names, maxArg] = process.argv.slice(2);
const MAX = Number(maxArg || 150);
const want = new Set(names.split(','));
const bridge = process.env.BRIDGE_JSON ? JSON.parse(fs.readFileSync(process.env.BRIDGE_JSON, 'utf8')) : {};
const io = new NodeIO();
const doc = await io.read(src);
for (const n of doc.getRoot().listNodes()) {
  if (!want.has(n.getName()) || !n.getMesh()) continue;
  for (const p of n.getMesh().listPrimitives()) {
    const P = p.getAttribute('POSITION').getArray();
    const idxAcc = p.getIndices();
    const idx = idxAcc.getArray();
    const nv = P.length / 3;
    const key = new Map();
    const rep = new Int32Array(nv);
    for (let i = 0; i < nv; i++) {
      const k = [0, 1, 2].map((a) => Math.round(P[i * 3 + a] * 1e4)).join(',');
      if (!key.has(k)) key.set(k, i);
      rep[i] = key.get(k);
    }
    const par = new Int32Array(nv).map((_, i) => i);
    const f = (x) => { while (par[x] !== x) { par[x] = par[par[x]]; x = par[x]; } return x; };
    for (let t = 0; t < idx.length; t += 3) {
      const a = f(rep[idx[t]]);
      for (let k = 1; k < 3; k++) par[f(rep[idx[t + k]])] = a;
    }
    const cnt = new Map();
    for (let t = 0; t < idx.length; t += 3) { const r = f(rep[idx[t]]); cnt.set(r, (cnt.get(r) || 0) + 1); }
    let big = -1, bn = 0;
    for (const [r, c] of cnt) if (c > bn) { bn = c; big = r; }
    const keep = [];
    let dropped = 0;
    const br = new Set(bridge[n.getName()] || []);
    let bridged = 0;
    for (let t = 0; t < idx.length; t += 3) {
      const r = f(rep[idx[t]]);
      if (r !== big && cnt.get(r) <= MAX) { dropped++; continue; }
      if (br.has(t / 3)) { bridged++; continue; }
      keep.push(idx[t], idx[t + 1], idx[t + 2]);
    }
    console.log(n.getName(), '삼각형', idx.length / 3, '→', keep.length / 3, '(뺌', dropped + ', 이음', bridged + ', 덩어리', cnt.size + ')');
    idxAcc.setArray(idx instanceof Uint32Array ? new Uint32Array(keep) : new Uint16Array(keep));
  }
}
await io.write(dst, doc);
