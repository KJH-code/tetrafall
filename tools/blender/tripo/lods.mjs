// 리깅한 tank_lod0 한 메시 glb → 판 LOD 3개 (같은 뼈·같은 재질·같은 UV) 를 더해 tank.glb 로.
// UV 이음선이 갈라지지 않게 meshopt 로 줄임 (Blender Decimate 는 이음선이 찢어짐).
// 실행: node lods.mjs <입력.glb> <출력.glb>   (npm i @gltf-transform/core @gltf-transform/functions meshoptimizer 가 있는 자리에서, NODE_PATH 로)
import { NodeIO } from '@gltf-transform/core';
import { weld, simplify } from '@gltf-transform/functions';
import { MeshoptSimplifier } from 'meshoptimizer';

const TARGETS = { lod1: 5000, lod2: 4000, lod3: 3000 };
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
const base = root.listNodes().find((n) => n.getName() === 'tank_lod0');
const prim0 = base.getMesh().listPrimitives()[0];
const full = prim0.getIndices().getCount() / 3;
console.log('lod0 tris', full);
// 복사: 문서를 다시 읽어 메시를 줄이고, 원본 문서에 새 메시로 옮김
for (const [name, tris] of Object.entries(TARGETS)) {
  const d = await io.readBinary(await io.writeBinary(doc));
  await d.transform(weld(), simplify({ simplifier: MeshoptSimplifier, ratio: tris / full, error: 0.05, lockBorder: false }));
  const sp = d.getRoot().listNodes().find((n) => n.getName() === 'tank_lod0').getMesh().listPrimitives()[0];
  const m = doc.createMesh('tank_' + name);
  const p = doc.createPrimitive().setMaterial(prim0.getMaterial()).setMode(sp.getMode());
  p.setIndices(doc.createAccessor().setType('SCALAR').setArray(sp.getIndices().getArray()).setBuffer(root.listBuffers()[0]));
  for (const sem of sp.listSemantics()) {
    const a = sp.getAttribute(sem);
    p.setAttribute(sem, doc.createAccessor().setType(a.getType()).setArray(a.getArray()).setNormalized(a.getNormalized()).setBuffer(root.listBuffers()[0]));
  }
  m.addPrimitive(p);
  const n = doc.createNode('tank_' + name).setMesh(m).setSkin(base.getSkin());
  if (base.getParentNode?.()) base.getParentNode().addChild(n); else scene.addChild(n);
  console.log(name, 'tris', sp.getIndices().getCount() / 3);
}
await io.write(dst, doc);
