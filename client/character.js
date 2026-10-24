// 플레이어 캐릭터: 폴가이즈풍 콩. 판정 상자(폭 2×PLAYER_HALF, 키 PLAYER_HEIGHT) 안에 들어가게 만든다.
// 로컬 좌표: 발바닥이 z=0, 앞(바라보는 방향)이 +x. 그룹을 플레이어 위치에 두고 rotation.z = yaw 로 돌린다.
// 모델 파일이 있으면 로봇(buildRobot), 없으면 콩. 둘 다 같은 반환 형태라 그리는 쪽은 구분 없이 쓴다.
import * as THREE from 'three';
import { clone as cloneSkinned } from 'three/addons/utils/SkeletonUtils.js';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { itemModel } from '/models.js';
import { buildFigure } from '/figure.js';

const R = C.PLAYER_HALF; // 몸통 반지름 = 판정 반폭
const H = C.PLAYER_HEIGHT;

const eyeWhiteMat = new THREE.MeshBasicMaterial({ color: 0xffffff }); // 조명 영향 없이 항상 밝게: 어디를 보는지 멀리서도 보이게
const pupilMat = new THREE.MeshBasicMaterial({ color: 0x111111 });

// 반환: { group, bodyMaterial, arms, hammer, held, waitMark, rig, parts, feet }.
// 몸 부분은 rig(몸 가운데가 축) > parts 안에 있어서 애니메이션은 rig 를 기울이고·돌리고·늘리고, parts 를 위아래로 흔든다.
// 이름표·화살표·조종 대기 표시는 group 에 바로 붙어 같이 돌지 않는다. bodyMaterial 의 color/emissive 를 바꾸면 몸통·팔이 같이 바뀐다 (색, 경직 깜빡임)
// arms[0] = 오른팔 (밀치기 휘두르기 애니메이션용). 각 팔의 userData.base = 기본 위치
// char 가 FIGURE_CHARS 에 있으면 TABS 식 몸 (figure: 관절이 더 있음)
export function buildCharacter(color, models = null, char = null) {
  if (C.FIGURE_CHARS.includes(char)) return buildFigure(color, char, models);
  return models && models.robot ? buildRobot(color, models) : buildBean(color, models);
}

function buildBean(color, models) {
  const group = new THREE.Group();
  const bodyMaterial = toon({ color });
  const rig = new THREE.Group();
  rig.position.z = H / 2;
  group.add(rig);
  const parts = new THREE.Group();
  parts.position.z = -H / 2;
  rig.add(parts);

  // 몸통: 캡슐. 전체 높이 = 원통 길이 + 2R = H
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(R, H - 2 * R, 8, 20), bodyMaterial);
  body.rotation.x = Math.PI / 2; // 캡슐 축을 y → z 로
  body.position.z = H / 2;
  parts.add(body);

  // 눈 두 개: 앞쪽 표면에 납작한 흰자 + 검은 눈동자. 바라보는 방향이 바로 보인다
  const eyeZ = H * 0.74;
  for (const side of [-1, 1]) {
    const white = new THREE.Mesh(new THREE.SphereGeometry(0.1, 16, 12), eyeWhiteMat);
    white.scale.set(0.45, 1, 1.25);
    white.position.set(R * 0.86, side * 0.11, eyeZ);
    parts.add(white);
    const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.05, 12, 10), pupilMat);
    pupil.scale.set(0.4, 1, 1.2);
    pupil.position.set(R * 0.86 + 0.035, side * 0.11, eyeZ - 0.01);
    parts.add(pupil);
  }

  // 짧은 팔 두 개: 몸통 옆에 반쯤 묻힌 작은 캡슐 (판정 상자 밖으로 1~2cm 만 나온다)
  const arms = [];
  for (const side of [-1, 1]) {
    const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.065, 0.22, 4, 10), bodyMaterial);
    arm.position.set(0.04, side * (R - 0.05), H * 0.45);
    arm.rotation.x = side * 0.35; // 살짝 벌어지게
    arm.userData.base = arm.position.clone();
    arm.userData.baseRot = arm.rotation.clone();
    parts.add(arm);
    arms.push(arm);
  }

  // 망치 머리: 오른팔 끝에 붙임 (망치 아이템 있을 때만 보임)
  const hammer = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), toon({ color: 0xff8a10 }));
  hammer.position.set(0, -0.2, 0); // 오른팔 바깥 끝 (팔은 로컬 y 축 방향 캡슐)
  hammer.visible = false;
  arms[0].add(hammer);

  // 왼손에 든 것: 고른 핫바 칸의 물건 하나만 보임 (held[종류].visible). 망치는 오른손이라 같이 보여도 안 겹친다
  const held = heldItems(models);
  for (const m of Object.values(held)) {
    m.position.set(0, 0.24, 0); // 왼팔 바깥 끝 (+y)
    m.visible = false;
    arms[1].add(m);
  }

  // 조종권을 먹고 차례를 기다리는 중: 머리 위 하늘색 팔면체 (필드의 조종권 아이템과 같은 모양)
  const waitMark = new THREE.Mesh(new THREE.OctahedronGeometry(0.12), new THREE.MeshBasicMaterial({ color: 0x20e0e0 }));
  waitMark.position.z = H + 0.2;
  waitMark.visible = false;
  group.add(waitMark);

  // 발 두 개: 바닥에 납작하게. 몸통 아래 안쪽에 둔다
  const footMat = toon({ color: 0x333333 });
  const feet = [];
  for (const side of [-1, 1]) {
    const foot = new THREE.Mesh(new THREE.SphereGeometry(0.09, 12, 8), footMat);
    foot.scale.set(1.4, 1, 0.5);
    foot.position.set(0.05, side * 0.12, 0.045);
    foot.userData.baseX = foot.position.x;
    parts.add(foot);
    feet.push(foot);
  }

  return { group, bodyMaterial, mats: [bodyMaterial], arms, hammer, held, waitMark, rig, parts, feet, robot: null };
}

// 손에 든 것: 아이템 모델 (없으면 단색 도형)
export function heldItems(models) {
  const fallback = {
    brick: () => new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.17, 0.17), toon({ color: 0xf0d060 })),
    ball: () => new THREE.Mesh(new THREE.SphereGeometry(0.14, 14, 10), toon({ color: 0xe02020 })),
    bomb: () => new THREE.Mesh(new THREE.SphereGeometry(0.17, 14, 10), toon({ color: 0x222222 })),
  };
  const type = { brick: 'brick', ball: 'knockback', bomb: 'bomb' };
  const out = {};
  for (const k of Object.keys(fallback)) out[k] = (type[k] && itemModel(models, type[k], C.HELD_MODEL_SIZE)) || fallback[k]();
  return out;
}

// 로봇 눈알: 원래 눈은 검은 공뿐이라, 그 위에 흰자(조금 작은 흰 공)를 씌우고 앞쪽에 검은 눈동자를 붙인다.
// 검은 재질 부품(Head_4)의 정점을 넷으로 나누면 눈 둘·눈썹 둘 → 아래쪽 둘이 눈. 계산은 모델마다 한 번 (src.userData 에 저장)
function addRobotEyes(model, src, turn) {
  const head = model.getObjectByName('Head_4');
  if (!head) return;
  turn.updateMatrixWorld(true);
  if (!src.userData.eyes) {
    const pos = head.geometry.attributes.position;
    const pts = [];
    for (let i = 0; i < pos.count; i++) pts.push(new THREE.Vector3().fromBufferAttribute(pos, i));
    const box = new THREE.Box3().setFromPoints(pts);
    let centers = [
      [box.min.x, box.min.y],
      [box.max.x, box.min.y],
      [box.min.x, box.max.y],
      [box.max.x, box.max.y],
    ].map(([x, y]) => new THREE.Vector3(x, y, (box.min.z + box.max.z) / 2));
    let groups = [];
    for (let it = 0; it < 20; it++) {
      groups = centers.map(() => []);
      for (const p of pts) {
        let best = 0;
        centers.forEach((c, k) => {
          if (p.distanceToSquared(c) < p.distanceToSquared(centers[best])) best = k;
        });
        groups[best].push(p);
      }
      centers = groups.map((g, k) => (g.length ? g.reduce((a, p) => a.add(p), new THREE.Vector3()).divideScalar(g.length) : centers[k]));
    }
    // 이 게임은 z 가 위, +x 가 앞 (세워 둔 모델 기준)
    const up = (c) => c.clone().applyMatrix4(head.matrixWorld).z;
    const eyes = centers
      .map((c, k) => ({ c, r: Math.max(...groups[k].map((p) => p.distanceTo(c))) }))
      .sort((a, b) => up(a.c) - up(b.c))
      .slice(0, 2);
    const fwd = new THREE.Vector3(1, 0, 0).transformDirection(new THREE.Matrix4().copy(head.matrixWorld).invert()).normalize();
    src.userData.eyes = { eyes, fwd };
  }
  const { eyes, fwd } = src.userData.eyes;
  for (const e of eyes) {
    const white = new THREE.Mesh(new THREE.SphereGeometry(e.r * C.ROBOT_EYE_WHITE, 20, 14), eyeWhiteMat);
    white.position.copy(e.c);
    head.add(white);
    const pupil = new THREE.Mesh(new THREE.SphereGeometry(e.r * C.ROBOT_EYE_PUPIL, 16, 10), pupilMat);
    pupil.position.copy(e.c).addScaledVector(fwd, e.r * (C.ROBOT_EYE_WHITE - C.ROBOT_EYE_PUPIL + 0.1));
    head.add(pupil);
  }
}

// 로봇 (RobotExpressive, CC0). 뼈대가 있어 사람마다 SkeletonUtils 로 복제하고 AnimationMixer 로 동작을 섞는다.
// 반환 형태는 콩과 같고, robot = { mixer, actions, face } 가 더 있다. arms·feet 는 콩 전용 손짓이라 빈 자리만 둔다
function buildRobot(color, models) {
  const group = new THREE.Group();
  const rig = new THREE.Group();
  rig.position.z = H / 2;
  group.add(rig);
  const parts = new THREE.Group();
  parts.position.z = -H / 2;
  rig.add(parts);

  // glTF 는 y 위·+z 앞 → x 축 90도로 세우고 z 축 90도 돌려 앞을 +x 로. 키를 PLAYER_HEIGHT 에 맞추고 발을 z=0 에
  const model = cloneSkinned(models.robot.scene);
  model.rotation.x = Math.PI / 2;
  const turn = new THREE.Group();
  turn.rotation.z = Math.PI / 2;
  turn.add(model);
  turn.updateMatrixWorld(true);
  const box = new THREE.Box3().setFromObject(turn);
  const s = H / (box.max.z - box.min.z);
  turn.scale.setScalar(s);
  turn.position.z = -box.min.z * s;
  parts.add(turn);

  // 재질은 사람마다 복사 (몸 색·깜빡임·유령 반투명). 'Main' 이 몸통 색
  // 같은 원본 재질을 쓰는 부위끼리는 복사본도 하나를 같이 쓴다 (몸통·팔·머리가 모두 'Main' 이라 한 번에 칠해지게)
  const copies = new Map();
  let face = null;
  model.traverse((o) => {
    if (!o.isMesh) return;
    if (!copies.has(o.material)) copies.set(o.material, o.material.clone());
    o.material = copies.get(o.material);
    o.castShadow = true;
    o.frustumCulled = false; // 동작하면 원래 경계 밖으로 나가서
    if (o.morphTargetDictionary && o.morphTargetDictionary.Surprised !== undefined) face = o;
  });
  const mats = [...copies.values()];
  const bodyMaterial = mats.find((m) => m.name === 'Main') || mats[0];
  bodyMaterial.color.setHex(color);

  addRobotEyes(model, models.robot, turn);

  const mixer = new THREE.AnimationMixer(model);
  const actions = {};
  for (const clip of models.robot.animations) actions[clip.name] = mixer.clipAction(clip);
  actions.Idle.play();

  // 손뼈에 망치(오른손)·든 것(왼손). 뼈 공간은 모델 축척이라 크기를 되돌려 준다
  const bone = (name) => {
    let b = null;
    model.traverse((o) => {
      if (!b && o.isBone && o.name === name) b = o;
    });
    return b;
  };
  group.updateMatrixWorld(true);
  const attach = (b, obj) => {
    const ws = b.getWorldScale(new THREE.Vector3()).x;
    obj.scale.multiplyScalar(1 / ws);
    obj.visible = false;
    b.add(obj);
    return obj;
  };
  // GLTFLoader 가 이름에서 '.' 을 빼서 Palm2.R → Palm2R
  const handR = bone('Palm2R') || bone('LowerArmR');
  const handL = bone('Palm2L') || bone('LowerArmL');
  const hammer = attach(handR, itemModel(models, 'weapon', C.HELD_MODEL_SIZE * 1.4) || new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), toon({ color: 0xff8a10 })));
  const held = heldItems(models);
  for (const m of Object.values(held)) attach(handL, m);

  const waitMark = new THREE.Mesh(new THREE.OctahedronGeometry(0.12), new THREE.MeshBasicMaterial({ color: 0x20e0e0 }));
  waitMark.position.z = H + 0.2;
  waitMark.visible = false;
  group.add(waitMark);

  // 콩 전용 손짓 코드가 그대로 돌아도 아무 일 없게 빈 팔
  const dummyArm = () => {
    const a = new THREE.Object3D();
    a.userData.base = a.position.clone();
    a.userData.baseRot = a.rotation.clone();
    return a;
  };
  return { group, bodyMaterial, mats, arms: [dummyArm(), dummyArm()], hammer, held, waitMark, rig, parts, feet: [], robot: { mixer, actions, face, current: 'Idle' } };
}

// 캐릭터 표시: 머리 장식 (탱크 투구 · 닌자 머리띠 · 건축가 안전모 · 갈고리 두건 + 옆구리 갈고리). rig 에 붙임 (rig 원점 = 몸 가운데)
export function charAccessory(char) {
  const g = new THREE.Group();
  const top = H / 2; // rig 기준 머리 꼭대기 근처
  const add = (geo, color, x, y, z, rot = null) => {
    const m = new THREE.Mesh(geo, toon({ color }));
    m.position.set(x, y, z);
    if (rot) m.rotation.set(...rot);
    m.castShadow = true;
    g.add(m);
    return m;
  };
  if (char === 'tank') {
    add(new THREE.SphereGeometry(0.27, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), 0x6a6e78, 0, 0, top - 0.12, [Math.PI / 2, 0, 0]);
    add(new THREE.BoxGeometry(0.06, 0.36, 0.08), 0x4a4e58, 0.22, 0, top - 0.12); // 얼굴 앞 가리개
  } else if (char === 'ninja') {
    add(new THREE.TorusGeometry(0.24, 0.04, 6, 20), 0xc02020, 0, 0, top - 0.2);
    add(new THREE.BoxGeometry(0.04, 0.06, 0.22), 0xc02020, -0.27, 0.06, top - 0.3, [0.4, 0, 0]); // 뒤로 늘어진 끈
    add(new THREE.BoxGeometry(0.04, 0.06, 0.22), 0xc02020, -0.27, -0.06, top - 0.3, [-0.4, 0, 0]);
  } else if (char === 'builder') {
    add(new THREE.SphereGeometry(0.26, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), 0xf2c418, 0, 0, top - 0.1, [Math.PI / 2, 0, 0]);
    add(new THREE.CylinderGeometry(0.33, 0.33, 0.03, 20), 0xf2c418, 0.04, 0, top - 0.1, [Math.PI / 2, 0, 0]); // 챙
  } else if (char === 'hook') {
    add(new THREE.SphereGeometry(0.25, 16, 8, 0, Math.PI * 2, 0, Math.PI / 2), 0x30305a, 0, 0, top - 0.14, [Math.PI / 2, 0, 0]);
    add(new THREE.TorusGeometry(0.11, 0.03, 6, 14, Math.PI * 1.3), 0xb0b4c0, 0.05, -0.36, 0.05, [Math.PI / 2, 0, 0]); // 옆구리 갈고리
  }
  g.traverse((o) => {
    if (o.isMesh) o.userData.charAcc = true;
  });
  return g;
}
