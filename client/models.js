// 모델 파일 불러오기 (client/assets, 출처·라이선스는 assets/CREDITS.md).
// 불러오지 못하면 null 을 돌려주고, 그리는 쪽은 예전 도형(콩·단색 아이템)으로 그린다.
import * as THREE from 'three';
import { GLTFLoader } from 'three/addons/loaders/GLTFLoader.js';

// 아이템 종류 → 모델 파일 (이속 증가는 모델 없이 번개 도형)
const ITEM_FILES = {
  control: 'kenney-platformer/button-round.glb',
  knockback: 'kenney-blaster/blaster-b.glb',
  weapon: 'kenney-survival/tool-hammer.glb',
  jump: 'kenney-platformer/spring.glb',
  ghost: 'kenney-graveyard/character-ghost.glb',
  brick: 'kenney-platformer/crate-item.glb',
  bomb: 'kenney-platformer/bomb.glb',
};
const ROBOT_FILE = 'robot/RobotExpressive.glb';

export async function loadModels() {
  const loader = new GLTFLoader();
  const items = {};
  const [robot] = await Promise.all([
    loader.loadAsync(`/assets/${ROBOT_FILE}`),
    ...Object.entries(ITEM_FILES).map(async ([type, file]) => {
      items[type] = (await loader.loadAsync(`/assets/${file}`)).scene;
    }),
  ]);
  return { items, robot };
}

// glTF 는 y 가 위, 이 게임은 z 가 위 → x 축으로 90도 세운다. 가장 긴 변이 size 가 되게 줄이고 가운데를 원점에.
// 돌려주는 것은 바깥 Group (위치·회전은 이 Group 에 준다)
export function standUp(obj, size) {
  const inner = new THREE.Group();
  obj.rotation.x = Math.PI / 2;
  inner.add(obj);
  inner.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(inner);
  const dims = box.getSize(new THREE.Vector3());
  const s = size / Math.max(dims.x, dims.y, dims.z);
  inner.scale.setScalar(s);
  inner.position.copy(box.getCenter(new THREE.Vector3()).multiplyScalar(-s));
  const outer = new THREE.Group();
  outer.add(inner);
  return outer;
}

// 아이템 모델 하나 (모양·재질은 원본과 공유, ownMaterials 면 재질을 복사해 따로 바꿀 수 있게)
export function itemModel(models, type, size, ownMaterials = false) {
  const src = models && models.items[type];
  if (!src) return null;
  const obj = src.clone(true);
  if (ownMaterials) {
    obj.traverse((o) => {
      if (o.isMesh) o.material = o.material.clone();
    });
  }
  return standUp(obj, size);
}
