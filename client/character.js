// 플레이어 캐릭터: 폴가이즈풍 콩. 판정 상자(폭 2×PLAYER_HALF, 키 PLAYER_HEIGHT) 안에 들어가게 만든다.
// 로컬 좌표: 발바닥이 z=0, 앞(바라보는 방향)이 +x. 그룹을 플레이어 위치에 두고 rotation.z = yaw 로 돌린다.
// 나중에 외부 모델(GLB)로 바꿀 때는 이 함수만 같은 반환 형태로 바꾸면 된다.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const R = C.PLAYER_HALF; // 몸통 반지름 = 판정 반폭
const H = C.PLAYER_HEIGHT;

const eyeWhiteMat = new THREE.MeshBasicMaterial({ color: 0xffffff }); // 조명 영향 없이 항상 밝게: 어디를 보는지 멀리서도 보이게
const pupilMat = new THREE.MeshBasicMaterial({ color: 0x111111 });

// 반환: { group, bodyMaterial, arms }. bodyMaterial 의 color/emissive 를 바꾸면 몸통·팔이 같이 바뀐다 (색, 경직 깜빡임)
// arms[0] = 오른팔 (밀치기 휘두르기 애니메이션용). 각 팔의 userData.base = 기본 위치
export function buildCharacter(color) {
  const group = new THREE.Group();
  const bodyMaterial = new THREE.MeshLambertMaterial({ color });

  // 몸통: 캡슐. 전체 높이 = 원통 길이 + 2R = H
  const body = new THREE.Mesh(new THREE.CapsuleGeometry(R, H - 2 * R, 8, 20), bodyMaterial);
  body.rotation.x = Math.PI / 2; // 캡슐 축을 y → z 로
  body.position.z = H / 2;
  group.add(body);

  // 눈 두 개: 앞쪽 표면에 납작한 흰자 + 검은 눈동자. 바라보는 방향이 바로 보인다
  const eyeZ = H * 0.74;
  for (const side of [-1, 1]) {
    const white = new THREE.Mesh(new THREE.SphereGeometry(0.1, 16, 12), eyeWhiteMat);
    white.scale.set(0.45, 1, 1.25);
    white.position.set(R * 0.86, side * 0.11, eyeZ);
    group.add(white);
    const pupil = new THREE.Mesh(new THREE.SphereGeometry(0.05, 12, 10), pupilMat);
    pupil.scale.set(0.4, 1, 1.2);
    pupil.position.set(R * 0.86 + 0.035, side * 0.11, eyeZ - 0.01);
    group.add(pupil);
  }

  // 짧은 팔 두 개: 몸통 옆에 반쯤 묻힌 작은 캡슐 (판정 상자 밖으로 1~2cm 만 나온다)
  const arms = [];
  for (const side of [-1, 1]) {
    const arm = new THREE.Mesh(new THREE.CapsuleGeometry(0.065, 0.22, 4, 10), bodyMaterial);
    arm.position.set(0.04, side * (R - 0.05), H * 0.45);
    arm.rotation.x = side * 0.35; // 살짝 벌어지게
    arm.userData.base = arm.position.clone();
    arm.userData.baseRot = arm.rotation.clone();
    group.add(arm);
    arms.push(arm);
  }

  // 망치 머리: 오른팔 끝에 붙임 (망치 아이템 있을 때만 보임)
  const hammer = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), new THREE.MeshLambertMaterial({ color: 0xff8a10 }));
  hammer.position.set(0, -0.2, 0); // 오른팔 바깥 끝 (팔은 로컬 y 축 방향 캡슐)
  hammer.visible = false;
  arms[0].add(hammer);

  // 발 두 개: 바닥에 납작하게. 몸통 아래 안쪽에 둔다
  const footMat = new THREE.MeshLambertMaterial({ color: 0x333333 });
  for (const side of [-1, 1]) {
    const foot = new THREE.Mesh(new THREE.SphereGeometry(0.09, 12, 8), footMat);
    foot.scale.set(1.4, 1, 0.5);
    foot.position.set(0.05, side * 0.12, 0.045);
    group.add(foot);
  }

  return { group, bodyMaterial, arms, hammer };
}
