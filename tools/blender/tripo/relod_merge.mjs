// relod.py 가 만든 <이름>_relod.glb 들 (새 UV·알베도로 다시 구운 판 LOD) 을 원래 ext/<이름>.glb 에 판 LOD 로 합침 (W31).
// 원래 글의 stage (<이름>_lod0)·1인칭 팔 (<이름>_vm)·뼈대·재질은 그대로 두고, <이름>_lod1..N 메시 (옛 LOD) 를 지우고 새 것을 같은 이름으로 넣음.
// 새 메시의 뼈 번호 (JOINTS_0) 는 뼈 이름으로 원래 스킨의 번호로 바꿈. 재질 = 알베도 하나 (이름 <이름>_lodN, 텍스처 이름 <이름>_atlas_lodN — 고도가 <이름>_<이름>_atlas_lodN.jpg 로 꺼냄).
// 실행: node relod_merge.mjs <원래.glb> <이름> <출력.glb> <lod1.glb> [lod2.glb …]    (NODE_PATH = @gltf-transform/core 가 있는 node_modules)
import { NodeIO } from '@gltf-transform/core';
import { prune } from '@gltf-transform/functions';

const [orig, NAME, dst, ...news] = process.argv.slice(2);
const io = new NodeIO();
const doc = await io.read(orig);
const root = doc.getRoot();
const scene = root.listScenes()[0];
const base = root.listNodes().find((n) => n.getName() === NAME + '_lod0');
const skin = base.getSkin();
const joints = skin.listJoints();
const jointIdx = new Map(joints.map((j, i) => [j.getName(), i]));
const buffer = root.listBuffers()[0];
const parent = base.getParentNode?.() ?? null;
for (const n of root.listNodes()) {
  if (new RegExp('^' + NAME + '_lod[1-9]$').test(n.getName())) {
    n.getMesh()?.dispose();
    n.dispose();
  }
}
const stageMat = base.getMesh().listPrimitives()[0].getMaterial();
for (let i = 0; i < news.length; i++) {
  const lod = NAME + '_lod' + (i + 1);
  const B = await io.read(news[i]);
  const nb = B.getRoot().listNodes().find((n) => n.getMesh());
  const pb = nb.getMesh().listPrimitives()[0];
  const namesB = nb.getSkin().listJoints().map((j) => j.getName());
  const remap = namesB.map((nm) => {
    if (!jointIdx.has(nm)) throw new Error('뼈 이름이 원래 스킨에 없음: ' + nm);
    return jointIdx.get(nm);
  });
  const texB = pb.getMaterial().getBaseColorTexture();
  const tex = doc.createTexture(NAME + '_atlas_lod' + (i + 1)).setImage(texB.getImage()).setMimeType(texB.getMimeType());
  const mat = doc.createMaterial(NAME + '_lod' + (i + 1)).setBaseColorTexture(tex).setMetallicFactor(stageMat.getMetallicFactor()).setRoughnessFactor(stageMat.getRoughnessFactor()).setDoubleSided(stageMat.getDoubleSided());
  const p = doc.createPrimitive().setMaterial(mat).setMode(pb.getMode());
  p.setIndices(doc.createAccessor().setType('SCALAR').setArray(pb.getIndices().getArray()).setBuffer(buffer));
  for (const sem of pb.listSemantics()) {
    const a = pb.getAttribute(sem);
    let arr = a.getArray();
    if (sem.startsWith('JOINTS_')) {
      arr = arr.slice();
      const w = pb.getAttribute(sem.replace('JOINTS_', 'WEIGHTS_')).getArray();
      for (let k = 0; k < arr.length; k++) arr[k] = w[k] > 0 ? remap[arr[k]] : 0;
    }
    p.setAttribute(sem, doc.createAccessor().setType(a.getType()).setArray(arr).setNormalized(a.getNormalized()).setBuffer(buffer));
  }
  const m = doc.createMesh(lod).addPrimitive(p);
  const n = doc.createNode(lod).setMesh(m).setSkin(skin);
  if (parent) parent.addChild(n); else scene.addChild(n);
  console.log(lod, 'tris', pb.getIndices().getCount() / 3, 'verts', pb.getAttribute('POSITION').getCount(), 'tex', texB.getImage().length, 'bytes');
}
await doc.transform(prune({ keepAttributes: true, keepLeaves: true })); // 안 쓰는 TEXCOORD_1 (몸 색 칸) 을 지우면 안 됨
await io.write(dst, doc);
console.log('wrote', dst);
