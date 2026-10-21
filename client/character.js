// 플레이어 캐릭터: 폴가이즈풍 콩. 판정 상자(폭 2×PLAYER_HALF, 키 PLAYER_HEIGHT) 안에 들어가게 만든다.
// 로컬 좌표: 발바닥이 z=0, 앞(바라보는 방향)이 +x. 그룹을 플레이어 위치에 두고 rotation.z = yaw 로 돌린다.
// 나중에 외부 모델(GLB)로 바꿀 때는 이 함수만 같은 반환 형태로 바꾸면 된다.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const R = C.PLAYER_HALF; // 몸통 반지름 = 판정 반폭
const H = C.PLAYER_HEIGHT;

const eyeWhiteMat = new THREE.MeshBasicMaterial({ color: 0xffffff }); // 조명 영향 없이 항상 밝게: 어디를 보는지 멀리서도 보이게
const pupilMat = new THREE.MeshBasicMaterial({ color: 0x111111 });

// 반환: { group, bodyMaterial, arms, hammer, held, waitMark, rig, parts, feet }.
// 몸 부분은 rig(몸 가운데가 축) > parts 안에 있어서 애니메이션은 rig 를 기울이고·돌리고·늘리고, parts 를 위아래로 흔든다.
// 이름표·화살표·조종 대기 표시는 group 에 바로 붙어 같이 돌지 않는다. bodyMaterial 의 color/emissive 를 바꾸면 몸통·팔이 같이 바뀐다 (색, 경직 깜빡임)
// arms[0] = 오른팔 (밀치기 휘두르기 애니메이션용). 각 팔의 userData.base = 기본 위치
export function buildCharacter(color) {
  const group = new THREE.Group();
  const bodyMaterial = new THREE.MeshLambertMaterial({ color });
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
  const hammer = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), new THREE.MeshLambertMaterial({ color: 0xff8a10 }));
  hammer.position.set(0, -0.2, 0); // 오른팔 바깥 끝 (팔은 로컬 y 축 방향 캡슐)
  hammer.visible = false;
  arms[0].add(hammer);

  // 왼손에 든 것: 고른 핫바 칸의 물건 하나만 보임 (held[종류].visible). 망치는 오른손이라 같이 보여도 안 겹친다
  const held = {
    block: new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.22, 0.22), new THREE.MeshLambertMaterial({ color: 0x6f8fc8 })),
    brick: new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.17, 0.17), new THREE.MeshLambertMaterial({ color: 0xf0d060 })),
    ball: new THREE.Mesh(new THREE.SphereGeometry(0.14, 14, 10), new THREE.MeshLambertMaterial({ color: 0xe02020 })),
    bomb: new THREE.Mesh(new THREE.SphereGeometry(0.17, 14, 10), new THREE.MeshLambertMaterial({ color: 0x222222 })),
  };
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
  const footMat = new THREE.MeshLambertMaterial({ color: 0x333333 });
  const feet = [];
  for (const side of [-1, 1]) {
    const foot = new THREE.Mesh(new THREE.SphereGeometry(0.09, 12, 8), footMat);
    foot.scale.set(1.4, 1, 0.5);
    foot.position.set(0.05, side * 0.12, 0.045);
    foot.userData.baseX = foot.position.x;
    parts.add(foot);
    feet.push(foot);
  }

  return { group, bodyMaterial, arms, hammer, held, waitMark, rig, parts, feet };
}
