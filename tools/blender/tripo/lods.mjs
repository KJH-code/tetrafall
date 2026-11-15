// 리깅한 tank_lod0 한 메시 glb → 판 LOD 3개 (같은 뼈·같은 재질·같은 UV) 를 더해 tank.glb 로.
// UV 이음선이 갈라지지 않게 meshopt 로 줄임 (Blender Decimate 는 이음선이 찢어짐).
// LOD_LOCK=1 = 가장자리 잠금 (닌자: 안 잠그면 줄인 몸에 구멍), LOD_ERR = 허용 오차 (기본 0.05)
// 실행: node lods.mjs <입력.glb> <출력.glb> [이름 = tank] [lod1,lod2,lod3 삼각형 수] [stage 삼각형 수 — 있으면 lod0 도 줄임]   (npm i @gltf-transform/core @gltf-transform/functions meshoptimizer 가 있는 자리에서, NODE_PATH 로)
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';

const NAME = process.argv[4] && !process.argv[4].includes(',') ? process.argv[4] : 'tank';
const tl = (process.argv[5] || '5000,4000,3000').split(',').map(Number); // 값이 하나면 LOD 하나 (닌자: UV 이음선 때문에 약 8500 아래로 안 내려감 → 하나만 만들어 판 화질 셋이 같이 씀)
const STAGE = +(process.argv[6] || 0);
const TARGETS = Object.fromEntries(tl.map((t, i) => ['lod' + (i + 1), t]));
await MeshoptSimplifier.ready;
const io = new NodeIO();
// 소품 모드: node lods.mjs prop <입력.glb> <출력.glb> <삼각형 수>  (방패·망치 한 메시를 줄임)
if (process.argv[2] === 'prop') {
  const [, , , pin, pout, ptris] = process.argv;
  const d = await io.read(pin);
  const pr = d.getRoot().listMeshes()[0].listPrimitives()[0];
  const n0 = pr.getIndices().getCount() / 3;
  await d.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: +ptris / n0, error: 0.08, lockBorder: false }));
  await io.write(pout, d);
  console.log('prop tris', d.getRoot().listMeshes()[0].listPrimitives()[0].getIndices().getCount() / 3);
  process.exit(0);
}
const [src, dst] = process.argv.slice(2);
const doc = await io.read(src);
const root = doc.getRoot();
const scene = root.listScenes()[0];
const base = root.listNodes().find((n) => n.getName() === NAME + '_lod0');
const prim0 = base.getMesh().listPrimitives()[0];
const full = prim0.getIndices().getCount() / 3;
console.log('lod0 tris', full);
// 복사: 문서를 다시 읽어 메시를 줄이고, 원본 문서에 새 메시로 옮김
for (const [name, tris] of Object.entries(TARGETS)) {
  const d = await io.readBinary(await io.writeBinary(doc));
  await d.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: tris / full, error: +(process.env.LOD_ERR || 0.05), lockBorder: !!process.env.LOD_LOCK }));
  const sp = d.getRoot().listNodes().find((n) => n.getName() === NAME + '_lod0').getMesh().listPrimitives()[0];
  const m = doc.createMesh(NAME + '_' + name);
  const p = doc.createPrimitive().setMaterial(prim0.getMaterial()).setMode(sp.getMode());
  p.setIndices(doc.createAccessor().setType('SCALAR').setArray(sp.getIndices().getArray()).setBuffer(root.listBuffers()[0]));
  for (const sem of sp.listSemantics()) {
    const a = sp.getAttribute(sem);
    p.setAttribute(sem, doc.createAccessor().setType(a.getType()).setArray(a.getArray()).setNormalized(a.getNormalized()).setBuffer(root.listBuffers()[0]));
  }
  m.addPrimitive(p);
  const n = doc.createNode(NAME + '_' + name).setMesh(m).setSkin(base.getSkin());
  if (base.getParentNode?.()) base.getParentNode().addChild(n); else scene.addChild(n);
  console.log(name, 'tris', sp.getIndices().getCount() / 3);
}
if (STAGE > 0 && STAGE < full) {
  const d = await io.readBinary(await io.writeBinary(doc));
  await d.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: STAGE / full, error: 0.03, lockBorder: false }));
  const sp = d.getRoot().listNodes().find((n) => n.getName() === NAME + '_lod0').getMesh().listPrimitives()[0];
  prim0.setIndices(doc.createAccessor().setType('SCALAR').setArray(sp.getIndices().getArray()).setBuffer(root.listBuffers()[0]));
  for (const sem of sp.listSemantics()) {
    const a = sp.getAttribute(sem);
    prim0.setAttribute(sem, doc.createAccessor().setType(a.getType()).setArray(a.getArray()).setNormalized(a.getNormalized()).setBuffer(root.listBuffers()[0]));
  }
  console.log('lod0 -> stage tris', sp.getIndices().getCount() / 3);
}
await io.write(dst, doc);
