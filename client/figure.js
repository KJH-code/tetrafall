// TABS 식 캐릭터: 각진 저폴리 마네킹 + 왕눈알. 피부 = 플레이어(팀) 색, 옷·소품 = 캐릭터마다 고정 색.
// 모델 파일 없이 기본 도형으로 만들고, 관절(엉덩이·허리·목·어깨·팔꿈치·무릎)을 코드로 움직인다 (figureAnim).
// 로컬 좌표는 콩·로봇과 같다: 발바닥 z=0, 앞 +x, 왼쪽 +y. 판정 상자(폭 2×PLAYER_HALF, 키 PLAYER_HEIGHT) 안에 들어가게.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon } from '/toon.js';
import { heldItems } from '/character.js';
import { itemModel } from '/models.js';

const H = C.PLAYER_HEIGHT;

// 뼈대 길이 (칸). 머리 꼭대기 = H
const FOOT_H = 0.06;
const SHIN = 0.36;
const THIGH = 0.36;
const HIP_Z = FOOT_H + SHIN + THIGH; // 엉덩이 관절 높이
const TORSO = 0.48;
const NECK = 0.05;
const HEAD = H - HIP_Z - TORSO - NECK; // 머리 높이 (나머지)
const UPPER_ARM = 0.3;
const LOWER_ARM = 0.27;

const eyeWhiteMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
const pupilMat = new THREE.MeshBasicMaterial({ color: 0x111111 });

const flat = (color) => toon({ color, flatShading: true });

// 각진 원기둥: 아래 끝이 원점, -z 쪽으로 len 만큼 (팔·다리 마디). 옆면 6개라 저폴리로 보임
function limb(len, rTop, rBottom, mat) {
  const geo = new THREE.CylinderGeometry(rTop, rBottom, len, 6);
  geo.rotateX(Math.PI / 2); // 원기둥 축 y → z
  geo.translate(0, 0, -len / 2);
  const m = new THREE.Mesh(geo, mat);
  m.castShadow = true;
  return m;
}

function mesh(geo, mat, x = 0, y = 0, z = 0) {
  const m = new THREE.Mesh(geo, mat);
  m.position.set(x, y, z);
  m.castShadow = true;
  return m;
}

// 관절 하나 = Group. 자식은 이 관절 기준으로 매달린다
function joint(parent, x, y, z) {
  const j = new THREE.Group();
  j.position.set(x, y, z);
  parent.add(j);
  return j;
}

// 캐릭터별 체형: 탱크는 넓고 두껍게
const BUILD = {
  tank: { torso: 1.25, limb: 1.3 },
};

// 반환 형태는 buildCharacter 와 같다 (+ figure: 관절·자세 상태). arms·feet 는 콩 전용이라 빈 자리만 둔다
export function buildFigure(color, char, models) {
  const build = BUILD[char] || { torso: 1, limb: 1 };
  const group = new THREE.Group();
  const rig = new THREE.Group();
  rig.position.z = H / 2;
  group.add(rig);
  const parts = new THREE.Group();
  parts.position.z = -H / 2;
  rig.add(parts);

  const skin = flat(color); // 몸 = 플레이어 색 (render.js 가 매 프레임 칠함)
  const mats = [skin];
  const costume = (c) => {
    const m = flat(c);
    mats.push(m);
    return m;
  };

  // 엉덩이 → 허리(몸통) → 목(머리)
  const hips = joint(parts, 0, 0, HIP_Z);
  hips.add(mesh(new THREE.BoxGeometry(0.17, 0.26 * build.torso, 0.14), skin, 0, 0, 0.02));
  const waist = joint(hips, 0, 0, 0.05);
  const torsoR = 0.15 * build.torso;
  const torsoGeo = new THREE.CylinderGeometry(torsoR, torsoR * 0.78, TORSO - 0.05, 6);
  torsoGeo.rotateX(Math.PI / 2);
  torsoGeo.scale(0.72, 1, 1); // 앞뒤로 납작하게
  waist.add(mesh(torsoGeo, skin, 0, 0, (TORSO - 0.05) / 2));
  const neck = joint(waist, 0, 0, TORSO - 0.05 + NECK);
  const headGeo = new THREE.IcosahedronGeometry(0.5, 1);
  headGeo.scale(0.17, 0.165, HEAD * 0.95);
  const head = mesh(headGeo, skin, 0, 0, HEAD / 2);
  neck.add(head);
  // 왕눈알: 크게 튀어나온 흰자 + 앞을 보는 검은 눈동자
  const eyes = [];
  for (const side of [-1, 1]) {
    const white = mesh(new THREE.SphereGeometry(0.05, 12, 8), eyeWhiteMat, 0.07, side * 0.045, HEAD * 0.56);
    neck.add(white);
    const pupil = mesh(new THREE.SphereGeometry(0.022, 10, 6), pupilMat, 0.045, 0, 0);
    white.add(pupil);
    eyes.push(pupil);
  }

  // 팔: 어깨 → 팔꿈치 → 손. arms[0] = 오른팔(-y), [1] = 왼팔(+y) (콩과 같은 순서)
  const shoulderY = torsoR * 0.95 + 0.04 * build.limb;
  const shoulders = [];
  const elbows = [];
  const hands = [];
  for (const side of [-1, 1]) {
    const sh = joint(waist, 0, side * shoulderY, TORSO - 0.1);
    sh.rotation.order = 'XYZ';
    sh.add(limb(UPPER_ARM, 0.045 * build.limb, 0.04 * build.limb, skin));
    const el = joint(sh, 0, 0, -UPPER_ARM);
    el.add(limb(LOWER_ARM, 0.04 * build.limb, 0.034 * build.limb, skin));
    const hand = joint(el, 0, 0, -LOWER_ARM);
    hand.add(mesh(new THREE.IcosahedronGeometry(0.048 * build.limb, 0), skin));
    shoulders.push(sh);
    elbows.push(el);
    hands.push(hand);
  }

  // 다리: 엉덩이 관절 → 무릎 → 발
  const thighs = [];
  const knees = [];
  for (const side of [-1, 1]) {
    const th = joint(hips, 0, side * 0.075 * build.torso, 0);
    th.add(limb(THIGH, 0.065 * build.limb, 0.05 * build.limb, skin));
    const kn = joint(th, 0, 0, -THIGH);
    kn.add(limb(SHIN, 0.05 * build.limb, 0.04 * build.limb, skin));
    const foot = mesh(new THREE.BoxGeometry(0.19, 0.09 * build.limb, FOOT_H), skin, 0.04, 0, -SHIN - FOOT_H / 2);
    kn.add(foot);
    thighs.push(th);
    knees.push(kn);
  }

  const fig = { hips, waist, neck, shoulders, elbows, hands, thighs, knees, eyes, pose: null };
  dressUp(char, fig, costume, build);

  // 망치는 오른손, 든 것은 왼손
  const hammer = itemModel(models, 'weapon', C.HELD_MODEL_SIZE * 1.4) || mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), toon({ color: 0xff8a10 }));
  hammer.position.set(0, 0, -0.06);
  hammer.visible = false;
  hands[0].add(hammer);
  const held = heldItems(models);
  for (const m of Object.values(held)) {
    m.position.set(0, 0, -0.08);
    m.scale.multiplyScalar(C.FIGURE_HELD_SCALE); // 팔이 가늘어서 로봇보다 작게
    m.visible = false;
    hands[1].add(m);
  }

  const waitMark = new THREE.Mesh(new THREE.OctahedronGeometry(0.12), new THREE.MeshBasicMaterial({ color: 0x20e0e0 }));
  waitMark.position.z = H + 0.2;
  waitMark.visible = false;
  group.add(waitMark);

  const dummyArm = () => {
    const a = new THREE.Object3D();
    a.userData.base = a.position.clone();
    a.userData.baseRot = a.rotation.clone();
    return a;
  };
  return { group, bodyMaterial: skin, mats, arms: [dummyArm(), dummyArm()], hammer, held, waitMark, rig, parts, feet: [], robot: null, figure: fig };
}

// 옷·소품 (캐릭터마다 고정 색). 지금은 탱크만 (시안)
function dressUp(char, fig, costume, build) {
  if (char !== 'tank') return;
  const steel = costume(0x9aa4b0);
  const dark = costume(0x5a6270);
  const blue = costume(0x2f5fc8);
  const leather = costume(0x6a4428);
  const torsoR = 0.15 * build.torso;

  // 투구: 머리 윗부분을 덮는 반구 + 이마 띠 + 파란 깃털. 눈은 가리지 않음
  const helmZ = HEAD * 0.76; // 눈 바로 위
  const helm = new THREE.SphereGeometry(0.11, 8, 4, 0, Math.PI * 2, 0, Math.PI * 0.5);
  helm.rotateX(Math.PI / 2);
  fig.neck.add(mesh(helm, steel, -0.005, 0, helmZ));
  const brim = new THREE.CylinderGeometry(0.115, 0.115, 0.04, 8);
  brim.rotateX(Math.PI / 2);
  fig.neck.add(mesh(brim, dark, -0.005, 0, helmZ));
  // 투구 위 파란 볏 (앞뒤로 긴 판)
  fig.neck.add(mesh(new THREE.BoxGeometry(0.22, 0.035, 0.08), blue, -0.02, 0, helmZ + 0.11));

  // 가슴 갑옷: 몸통보다 조금 큰 껍데기 + 파란 겉옷 띠 + 가죽 허리띠
  const chest = new THREE.CylinderGeometry(torsoR * 1.12, torsoR * 0.9, TORSO * 0.62, 6);
  chest.rotateX(Math.PI / 2);
  chest.scale(0.78, 1, 1);
  fig.waist.add(mesh(chest, steel, 0, 0, TORSO * 0.6));
  const tabard = new THREE.BoxGeometry(0.03, torsoR * 0.8, TORSO * 0.55);
  fig.waist.add(mesh(tabard, blue, torsoR * 0.82, 0, TORSO * 0.45));
  const belt = new THREE.CylinderGeometry(torsoR * 0.92, torsoR * 0.92, 0.06, 6);
  belt.rotateX(Math.PI / 2);
  belt.scale(0.78, 1, 1);
  fig.waist.add(mesh(belt, leather, 0, 0, 0.04));

  // 어깨 보호대: 큰 반구 (넓은 실루엣)
  for (const sh of fig.shoulders) {
    const pad = new THREE.SphereGeometry(0.1, 6, 3, 0, Math.PI * 2, 0, Math.PI * 0.5);
    pad.rotateX(Math.PI / 2);
    sh.add(mesh(pad, steel, 0, Math.sign(sh.position.y) * 0.02, 0.0));
  }
  // 장갑·정강이 보호대·쇠 장화
  for (const h of fig.hands) h.add(mesh(new THREE.IcosahedronGeometry(0.068, 0), steel));
  for (const kn of fig.knees) {
    kn.add(mesh(new THREE.BoxGeometry(0.11, 0.1, 0.22), steel, 0.02, 0, -0.14));
    kn.add(mesh(new THREE.BoxGeometry(0.21, 0.12, 0.08), dark, 0.045, 0, -SHIN - 0.02));
  }

  // 등에 둥근 방패: 파란 판 + 쇠 테두리 + 가운데 쇠 돌기
  const shield = new THREE.Group();
  const disk = new THREE.CylinderGeometry(0.25, 0.25, 0.04, 10);
  disk.rotateZ(Math.PI / 2); // 원판 면이 앞뒤(x)를 보게
  shield.add(mesh(disk, blue));
  const rim = new THREE.TorusGeometry(0.25, 0.025, 4, 10);
  rim.rotateY(Math.PI / 2);
  shield.add(mesh(rim, steel));
  shield.add(mesh(new THREE.IcosahedronGeometry(0.06, 0), steel, -0.03, 0, 0));
  shield.position.set(-torsoR * 0.85 - 0.03, 0, TORSO * 0.55);
  shield.rotation.y = 0.12; // 위가 살짝 뒤로
  fig.waist.add(shield);
}

// ---------- 동작 ----------
// 관절마다 목표 각도를 정하고 FIGURE_FOLLOW 빠르기로 따라감 → 살짝 늦게 따라와 흐느적거림 (TABS 느낌)
// 각도 이름: fwd = 앞으로 드는 각 (어깨·허벅지), out = 옆으로 벌리는 각 (어깨), bend = 굽힘 (팔꿈치 앞, 무릎 뒤)
function restPose() {
  return {
    waistPitch: 0,
    waistRoll: 0,
    neckPitch: 0,
    hipsZ: 0,
    shFwd: [0, 0],
    shOut: [C.FIGURE_ARM_SPREAD, C.FIGURE_ARM_SPREAD],
    elbow: [0.15, 0.15],
    thFwd: [0, 0],
    thOut: [0, 0],
    knee: [0, 0],
  };
}

// st: { air, walking, hs, walk(위상), stunned, dancing, emote, emoteT, punch(0~1), holding(왼손에 든 것 있음), t }
export function figureAnim(fig, st, dt) {
  const T = restPose();
  const t = st.t;
  if (st.walking) {
    const amp = Math.min(1, st.hs / C.MOVE_SPEED);
    for (let i = 0; i < 2; i++) {
      const ph = st.walk + (i ? Math.PI : 0);
      T.thFwd[i] = Math.sin(ph) * C.FIGURE_WALK_LEG * amp;
      T.knee[i] = Math.max(0, -Math.cos(ph)) * C.FIGURE_WALK_KNEE * amp;
      T.shFwd[i] = -Math.sin(ph) * C.FIGURE_WALK_ARM * amp;
      T.elbow[i] = 0.3 + 0.4 * amp;
    }
    T.waistPitch = C.FIGURE_RUN_LEAN * amp;
    T.hipsZ = Math.abs(Math.sin(st.walk)) * 0.04 * amp;
  } else {
    T.waistPitch = Math.sin(t * 2) * 0.02; // 숨쉬기
    T.shOut = T.shOut.map((o, i) => o + Math.sin(t * 1.7 + i) * 0.03);
  }
  if (st.air) {
    // 공중: 팔을 벌려 허우적, 한쪽 무릎을 올림
    T.shOut = [1.1 + Math.sin(t * 14) * 0.25, 1.1 + Math.sin(t * 14 + 1) * 0.25];
    T.shFwd = [0.2, 0.2];
    T.elbow = [0.4, 0.4];
    T.thFwd = [0.7, -0.15];
    T.knee = [1.0, 0.3];
  }
  if (st.stunned) {
    // 맞고 날아가는 중: 팔다리를 크게 벌리고 버둥
    T.shOut = [1.5 + Math.sin(t * 20) * 0.3, 1.5 + Math.cos(t * 18) * 0.3];
    T.shFwd = [Math.sin(t * 16) * 0.5, Math.cos(t * 15) * 0.5];
    T.thOut = [0.35, 0.35];
    T.thFwd = [Math.sin(t * 17) * 0.5, -Math.sin(t * 17) * 0.5];
    T.knee = [0.5, 0.5];
    T.neckPitch = -0.3;
  }
  if (st.holding && !st.stunned && st.emote < 0) {
    // 왼손에 든 것을 앞으로 내밀어 보이게
    T.shFwd[1] = 0.55;
    T.elbow[1] = 0.7;
  }
  if (st.dancing) {
    // 춤: 양팔을 번갈아 위로 펌프
    T.shOut = [2.3 + Math.sin(t * 12) * 0.5, 2.3 - Math.sin(t * 12) * 0.5];
    T.elbow = [0.6, 0.6];
    T.thFwd = [0.2 * Math.sin(t * 12), -0.2 * Math.sin(t * 12)];
  } else if (st.emote === 0) {
    // 손 흔들기: 오른팔 번쩍, 팔꿈치로 좌우
    T.shOut[0] = 2.7;
    T.elbow[0] = 0.5 + Math.sin(st.emoteT * 12) * 0.5;
  } else if (st.emote === 2) {
    // 웃기: 배를 잡고 들썩
    T.shFwd = [0.5, 0.5];
    T.shOut = [0.1, 0.1];
    T.elbow = [1.7, 1.7];
    T.waistPitch = -0.25 + Math.sin(st.emoteT * 22) * 0.18;
    T.neckPitch = -0.3;
  } else if (st.emote === 3) {
    // 도발: 왼팔을 앞으로 뻗어 손짓
    T.shFwd[1] = 1.4;
    T.shOut[1] = 0.1;
    T.elbow[1] = 0.6 + Math.sin(st.emoteT * 10) * 0.6;
    T.waistPitch = 0.1 + Math.sin(st.emoteT * 8) * 0.12;
  }
  if (st.punch > 0) {
    // 밀치기: 오른팔을 앞으로 쭉, 몸을 살짝 비틂
    T.shFwd[0] = Math.PI / 2 * st.punch;
    T.shOut[0] = 0.1;
    T.elbow[0] = 0.05;
    T.waistRoll = 0.25 * st.punch;
  }

  // 따라가기 (처음엔 바로 그 자세)
  const k = fig.pose ? 1 - Math.exp(-C.FIGURE_FOLLOW * dt) : 1;
  const P = fig.pose || (fig.pose = restPose());
  const lerp = (a, b) => a + (b - a) * k;
  for (const key of Object.keys(T)) {
    if (Array.isArray(T[key])) P[key] = P[key].map((v, i) => lerp(v, T[key][i]));
    else P[key] = lerp(P[key], T[key]);
  }
  if (st.punch > 0) {
    // 밀치기 팔은 늦게 따라오면 안 보임 (0.22초짜리) → 바로 그 자세
    P.shFwd[0] = T.shFwd[0];
    P.shOut[0] = T.shOut[0];
    P.elbow[0] = T.elbow[0];
  }

  fig.hips.position.z = HIP_Z + P.hipsZ;
  fig.waist.rotation.y = P.waistPitch;
  fig.waist.rotation.z = P.waistRoll;
  fig.neck.rotation.y = P.neckPitch;
  for (let i = 0; i < 2; i++) {
    const side = i ? 1 : -1; // 0 = 오른쪽(-y)
    // 어깨: x 축으로 벌리고(out), y 축으로 앞으로(fwd). 아래(-z)를 보던 팔이 앞(+x)으로 가려면 y 축 음의 회전
    fig.shoulders[i].rotation.x = side * P.shOut[i];
    fig.shoulders[i].rotation.y = -P.shFwd[i];
    fig.elbows[i].rotation.y = -P.elbow[i];
    fig.thighs[i].rotation.x = side * P.thOut[i];
    fig.thighs[i].rotation.y = -P.thFwd[i];
    fig.knees[i].rotation.y = P.knee[i];
  }
}
