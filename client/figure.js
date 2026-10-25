// TABS 식 캐릭터: 각진 저폴리 몸 + 왕눈알. 피부 = 플레이어(팀) 색, 옷·소품 = 캐릭터마다 고정 색.
// 모델 파일 없이 기본 도형으로 만들고, 관절(엉덩이·허리·목·어깨·팔꿈치·무릎)을 코드로 움직인다 (figureAnim).
// 로컬 좌표는 콩·로봇과 같다: 발바닥 z=0, 앞 +x, 왼쪽 +y. 키는 PLAYER_HEIGHT 안팎.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { heldItems } from '/character.js';
import { itemModel } from '/models.js';

// 눈알은 외곽선을 안 그림 (흰자 둘레에 검은 테가 생겨 부자연스러움)
const eyeWhiteMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff }));
const pupilMat = noOutline(new THREE.MeshBasicMaterial({ color: 0x111111 }));

const flat = (color) => toon({ color }); // (MeshToonMaterial 엔 flatShading 이 없음. 각진 느낌은 저폴리 도형으로)

// 체형 (칸). foot 발 두께, shin·thigh 다리 마디, torso 몸통 높이, chestR·waistR 가슴·허리 반지름, depth 앞뒤 납작함,
// barrel 이면 몸통이 둥근 통, head·headW 머리 높이·폭, sink 머리가 어깨에 묻히는 깊이, upper·lower 팔 마디, armR·foreR 팔 굵기,
// legR 다리 굵기, hand 손 크기, shoulderY 어깨 관절 옆 거리, hipY 다리 사이, hunch 구부정한 각, spread 팔 벌린 각
const BODIES = {
  // 보통 마네킹
  lean: { foot: 0.06, shin: 0.36, thigh: 0.36, torso: 0.48, chestR: 0.15, waistR: 0.12, depth: 0.72, head: 0.28, headW: 0.17, sink: -0.05, upper: 0.3, lower: 0.27, armR: 0.045, foreR: 0.04, legR: 0.065, hand: 0.048, shoulderY: 0.18, hipY: 0.075, hunch: 0, spread: 0.22 },
  // 마른 몸 (닌자): 가늘고 다리 김
  slim: { foot: 0.06, shin: 0.37, thigh: 0.37, torso: 0.47, chestR: 0.14, waistR: 0.11, depth: 0.72, head: 0.27, headW: 0.165, sink: -0.05, upper: 0.3, lower: 0.27, armR: 0.042, foreR: 0.038, legR: 0.058, hand: 0.045, shoulderY: 0.17, hipY: 0.07, hunch: 0.05, spread: 0.24 },
  // 다부진 보통 몸 (건축가)
  sturdy: { foot: 0.065, shin: 0.3, thigh: 0.3, torso: 0.55, chestR: 0.19, waistR: 0.15, depth: 0.8, head: 0.28, headW: 0.19, sink: 0, upper: 0.28, lower: 0.26, armR: 0.055, foreR: 0.052, legR: 0.075, hand: 0.055, shoulderY: 0.22, hipY: 0.085, hunch: 0, spread: 0.3 },
  // 팔 긴 보통 몸 (갈고리)
  reach: { foot: 0.06, shin: 0.34, thigh: 0.34, torso: 0.5, chestR: 0.16, waistR: 0.13, depth: 0.74, head: 0.28, headW: 0.175, sink: -0.04, upper: 0.34, lower: 0.32, armR: 0.05, foreR: 0.046, legR: 0.066, hand: 0.05, shoulderY: 0.19, hipY: 0.075, hunch: 0.06, spread: 0.26 },
  // 드럼통 (탱크): 둥근 통 몸통, 팔다리 짧고 뭉툭
  drum: { foot: 0.07, shin: 0.22, thigh: 0.22, torso: 0.74, chestR: 0.31, waistR: 0.31, depth: 0.86, barrel: true, head: 0.27, headW: 0.2, sink: 0.05, upper: 0.27, lower: 0.25, armR: 0.08, foreR: 0.08, legR: 0.09, hand: 0.07, shoulderY: 0.31, hipY: 0.12, hunch: 0.04, spread: 0.45 },
};

// 각진 원기둥: 위 끝이 원점, -z 쪽으로 len (팔·다리 마디·그 위 갑옷). 옆면 seg 개라 저폴리로 보임
function limbGeo(len, rTop, rBottom, seg = 6) {
  const geo = new THREE.CylinderGeometry(rTop, rBottom, len, seg);
  geo.rotateX(Math.PI / 2); // 원기둥 축 y → z
  geo.translate(0, 0, -len / 2);
  return geo;
}

// z 축 원기둥 (가운데가 원점). scaleX 로 앞뒤를 납작하게
function ringGeo(rTop, rBottom, h, seg = 8, scaleX = 1) {
  const geo = new THREE.CylinderGeometry(rTop, rBottom, h, seg);
  geo.rotateX(Math.PI / 2);
  geo.scale(scaleX, 1, 1);
  return geo;
}

// 위쪽 반구 (z 위)
function domeGeo(r, seg = 8) {
  const geo = new THREE.SphereGeometry(r, seg, 3, 0, Math.PI * 2, 0, Math.PI * 0.5);
  geo.rotateX(Math.PI / 2);
  return geo;
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

// 캐릭터별 체형 (FIGURE_BODY 에 없으면 보통)
const bodyOf = (char) => BODIES[(C.FIGURE_BODY && C.FIGURE_BODY[char]) || 'lean'] || BODIES.lean;

// 반환 형태는 buildCharacter 와 같다 (+ figure: 관절·자세 상태). arms·feet 는 콩 전용이라 빈 자리만 둔다
export function buildFigure(color, char, models) {
  const d = bodyOf(char);
  const group = new THREE.Group();
  const rig = new THREE.Group();
  rig.position.z = C.PLAYER_HEIGHT / 2;
  group.add(rig);
  const parts = new THREE.Group();
  parts.position.z = -C.PLAYER_HEIGHT / 2;
  rig.add(parts);
  // 몸 전체 크기 (먼 거리에서 로봇보다 작아 보여서 키움). 판정 상자는 그대로
  const body = new THREE.Group();
  body.scale.setScalar(C.FIGURE_SCALE);
  parts.add(body);

  const skin = flat(color); // 몸 = 플레이어 색 (render.js 가 매 프레임 칠함)
  const mats = [skin];
  const costume = (c) => {
    const m = flat(c);
    mats.push(m);
    return m;
  };

  // 엉덩이 → 허리(몸통) → 목(머리)
  const hipZ = d.foot + d.shin + d.thigh;
  const hips = joint(body, 0, 0, hipZ);
  hips.add(mesh(new THREE.BoxGeometry(d.waistR * 1.2, d.hipY * 2 + d.legR * 2, 0.14), skin, 0, 0, 0.02));
  const waist = joint(hips, 0, 0, 0.04);
  if (d.barrel) {
    const geo = new THREE.IcosahedronGeometry(1, 1);
    geo.scale(d.chestR * d.depth, d.chestR, d.torso / 2);
    waist.add(mesh(geo, skin, 0, 0, d.torso / 2));
  } else {
    waist.add(mesh(ringGeo(d.chestR, d.waistR, d.torso, 8, d.depth), skin, 0, 0, d.torso / 2));
  }
  const neck = joint(waist, 0, 0, d.torso - d.sink);
  const headGeo = new THREE.IcosahedronGeometry(0.5, 1);
  headGeo.scale(d.headW, d.headW * 0.97, d.head);
  neck.add(mesh(headGeo, skin, 0, 0, d.head / 2));

  // 팔: 어깨 → 팔꿈치 → 손. 0 = 오른팔(-y), 1 = 왼팔(+y) (콩과 같은 순서)
  const shoulders = [];
  const elbows = [];
  const hands = [];
  for (const side of [-1, 1]) {
    const sh = joint(waist, 0, side * d.shoulderY, d.torso - d.armR * 1.6);
    sh.add(mesh(limbGeo(d.upper, d.armR, d.armR * 0.85), skin));
    const el = joint(sh, 0, 0, -d.upper);
    el.add(mesh(limbGeo(d.lower, d.foreR, d.foreR * 0.8), skin));
    const hand = joint(el, 0, 0, -d.lower);
    hand.add(mesh(new THREE.IcosahedronGeometry(d.hand, 0), skin));
    shoulders.push(sh);
    elbows.push(el);
    hands.push(hand);
  }

  // 다리: 엉덩이 관절 → 무릎 → 발
  const thighs = [];
  const knees = [];
  const feet = [];
  for (const side of [-1, 1]) {
    const th = joint(hips, 0, side * d.hipY, 0);
    th.add(mesh(limbGeo(d.thigh, d.legR, d.legR * 0.8), skin));
    const kn = joint(th, 0, 0, -d.thigh);
    kn.add(mesh(limbGeo(d.shin, d.legR * 0.8, d.legR * 0.65), skin));
    const foot = joint(kn, 0, 0, -d.shin);
    foot.add(mesh(new THREE.BoxGeometry(d.legR * 3, d.legR * 1.5, d.foot), skin, d.legR * 0.6, 0, -d.foot / 2));
    thighs.push(th);
    knees.push(kn);
    feet.push(foot);
  }

  const fig = { d, hips, waist, neck, shoulders, elbows, hands, thighs, knees, feet, flaps: [], pose: null };
  dressUp(char, fig, costume, skin);

  // 망치는 오른손 (건축가 무기, render.js 가 건축가만 보임): 손잡이를 쥐고 머리가 주먹 앞쪽으로 (모델은 손잡이가 z 축, 머리가 +z 끝)
  const hammer = itemModel(models, 'weapon', C.HELD_MODEL_SIZE * 1.4);
  if (hammer) {
    hammer.rotation.y = Math.PI / 2; // 머리(+z) → 앞(+x)
    hammer.position.x = C.HELD_MODEL_SIZE * 1.4 * 0.35; // 손잡이 아래쪽을 쥠
  }
  const hammerObj = hammer || mesh(new THREE.BoxGeometry(0.26, 0.2, 0.2), toon({ color: 0xff8a10 }));
  hammerObj.visible = false;
  hands[0].add(hammerObj);
  const held = heldItems(models);
  for (const m of Object.values(held)) {
    m.position.set(0, 0, -d.hand * 1.5);
    m.scale.multiplyScalar(C.FIGURE_HELD_SCALE); // 로봇보다 작게
    m.visible = false;
    hands[1].add(m);
  }

  const waitMark = new THREE.Mesh(new THREE.OctahedronGeometry(0.12), new THREE.MeshBasicMaterial({ color: 0x20e0e0 }));
  waitMark.position.z = C.PLAYER_HEIGHT + 0.2;
  waitMark.visible = false;
  group.add(waitMark);

  const dummyArm = () => {
    const a = new THREE.Object3D();
    a.userData.base = a.position.clone();
    a.userData.baseRot = a.rotation.clone();
    return a;
  };
  return { group, bodyMaterial: skin, mats, arms: [dummyArm(), dummyArm()], hammer: hammerObj, held, waitMark, rig, parts, feet: [], robot: null, figure: fig };
}

// 왕눈알: 크게 튀어나온 흰자 + 앞을 보는 검은 눈동자. x 는 머리(또는 투구) 앞면에 맞춰 줌
// sides: 그릴 눈 (-1 오른쪽, 1 왼쪽). 안대 찬 해적은 [1]
function addEyes(neck, x, y, z, r, sides = [-1, 1]) {
  for (const side of sides) {
    const white = mesh(new THREE.SphereGeometry(r, 12, 8), eyeWhiteMat, x, side * y, z);
    white.castShadow = false;
    neck.add(white);
    const pupil = mesh(new THREE.SphereGeometry(r * 0.45, 10, 6), pupilMat, r * 0.88, 0, 0);
    pupil.castShadow = false;
    white.add(pupil);
  }
}

// 옷·소품 (캐릭터마다 고정 색). cloth = 피부 재질 (플레이어·팀 색): 옷 사이로 보이게 하거나 천 부분에 씀
function dressUp(char, fig, costume, cloth) {
  const dress = { tank: dressTank, ninja: dressNinja, builder: dressBuilder, hook: dressHook }[char];
  if (dress) return dress(fig, costume, cloth);
  addEyes(fig.neck, fig.d.headW * 0.42, 0.045, fig.d.head * 0.56, C.FIGURE_EYE);
}

// 탱크: 드럼통 몸 + 조각 난 판금 + 둥근 투구 + 등 방패.
// 갑옷이 피부를 거의 덮어서 천 부분(겉옷·볏·방패 판·배 띠 한 겹·윗팔 소매)은 피부 재질 = 플레이어(팀) 색
function dressTank(fig, costume, cloth) {
  const d = fig.d;
  const steel = costume(0xa3adb8);
  const dark = costume(0x5d6672);
  const leather = costume(0x6a4428);
  const gold = costume(0xd8a838);

  // ---- 투구: 둥근 돔 + 이마 띠 + 돔을 가로지르는 쇠 띠 둘 + 눈 사이로 내려오는 코 가드 + 꼭대기 장식 ----
  const r = d.headW * 0.62;
  const browZ = d.head * 0.66;
  fig.neck.add(mesh(ringGeo(r, r, d.head * 0.22, 8), steel, 0, 0, browZ + d.head * 0.11)); // 옆·뒤통수
  const dome = mesh(domeGeo(r * 1.02), steel, 0, 0, browZ + d.head * 0.22);
  dome.scale.z = 0.75; // 덜 뾰족하게, 납작한 돔
  fig.neck.add(dome);
  for (const turn of [0, Math.PI / 2]) {
    const band = new THREE.TorusGeometry(r * 1.04, 0.014, 3, 8, Math.PI);
    band.rotateX(Math.PI / 2); // 반원이 위로
    band.rotateZ(turn); // 앞뒤 띠 / 좌우 띠
    band.scale(1, 1, 0.75);
    fig.neck.add(mesh(band, dark, 0, 0, browZ + d.head * 0.22));
  }
  fig.neck.add(mesh(ringGeo(r * 1.06, r * 1.06, 0.045, 8), dark, 0, 0, browZ)); // 이마 띠
  fig.neck.add(mesh(new THREE.BoxGeometry(0.03, 0.032, d.head * 0.42), dark, r * 1.02, 0, browZ - d.head * 0.18)); // 코 가드
  fig.neck.add(mesh(new THREE.IcosahedronGeometry(0.035, 0), cloth, 0, 0, browZ + d.head * 0.22 + r * 0.8)); // 꼭대기 장식
  addEyes(fig.neck, r * 0.82, 0.07, browZ - d.head * 0.14, C.FIGURE_EYE);

  // ---- 몸통 갑옷 (드럼통 몸 기준): 가슴판(가운데 능선) + 배를 덮는 겹친 띠 + 목 칼라 + 허리띠·버클 + 겉옷 + 허리 치마판 ----
  const cR = d.chestR * 1.08;
  // 높이 z 에서 둥근 몸통 표면까지 거리 (갑옷 조각을 표면에 붙이려고)
  const surf = (z, grow) => d.chestR * grow * Math.sqrt(Math.max(0, 1 - ((z - d.torso / 2) / (d.torso / 2)) ** 2));
  const chest = new THREE.IcosahedronGeometry(1, 1);
  chest.scale(cR * d.depth, cR, d.torso * 0.5 * 0.62);
  fig.waist.add(mesh(chest, steel, 0, 0, d.torso * 0.66)); // 가슴판 (윗부분)
  const ridge = new THREE.BoxGeometry(0.04, 0.04, d.torso * 0.42);
  ridge.rotateZ(Math.PI / 4); // 단면이 마름모 → 능선
  fig.waist.add(mesh(ridge, steel, surf(d.torso * 0.7, 1.08) * d.depth + 0.005, 0, d.torso * 0.7));
  // 배 띠 3겹 (아래로 갈수록 살짝 작게, 색 번갈아)
  for (let i = 0; i < 3; i++) {
    const z = d.torso * (0.4 - i * 0.11);
    const r = surf(z, 1.07) + 0.01;
    fig.waist.add(mesh(ringGeo(r, r * 0.96, d.torso * 0.1, 8, d.depth), i % 2 ? cloth : steel, 0, 0, z));
  }
  fig.waist.add(mesh(ringGeo(d.headW * 0.62, d.headW * 0.8, 0.07, 8), dark, 0, 0, d.torso - d.sink + 0.01)); // 목 칼라
  const beltR = d.chestR * 0.82;
  fig.waist.add(mesh(ringGeo(beltR, beltR, 0.06, 8, d.depth), leather, 0, 0, 0.03));
  fig.waist.add(mesh(new THREE.BoxGeometry(0.03, 0.08, 0.07), gold, beltR * d.depth + 0.01, 0, 0.03)); // 버클
  const tabard = new THREE.BoxGeometry(0.025, beltR * 0.75, 0.3);
  tabard.translate(0, 0, -0.15);
  const tab = mesh(tabard, cloth, beltR * d.depth + 0.005, 0, 0.01);
  tab.rotation.y = -0.12; // 아래가 살짝 앞으로
  fig.waist.add(tab);
  // 허리 치마판: 옆·앞 비스듬히 4장 (엉덩이에 붙어 몸통과 같이 안 숙여짐)
  for (const [ang, w] of [[0.75, 0.13], [-0.75, 0.13], [1.6, 0.12], [-1.6, 0.12]]) {
    const plate = new THREE.BoxGeometry(0.025, w, 0.17);
    plate.translate(0, 0, -0.085);
    const m = mesh(plate, steel, Math.cos(ang) * beltR * d.depth, Math.sin(ang) * beltR, 0.04);
    m.rotation.order = 'ZYX';
    m.rotation.z = ang;
    m.rotation.y = -0.22; // 아래가 바깥으로 벌어짐
    fig.hips.add(m);
  }

  // ---- 어깨: 3단으로 겹친 판 (큰 돔 + 아래로 작아지는 두 겹) ----
  for (const sh of fig.shoulders) {
    const side = Math.sign(sh.position.y);
    const r = d.armR * 2.3;
    const pad = new THREE.Group();
    pad.add(mesh(domeGeo(r), steel));
    const l1 = mesh(domeGeo(r * 0.92), dark, 0, side * 0.02, -0.05);
    l1.scale.z = 0.6;
    pad.add(l1);
    const l2 = mesh(domeGeo(r * 0.82), steel, 0, side * 0.035, -0.09);
    l2.scale.z = 0.5;
    pad.add(l2);
    pad.add(mesh(new THREE.IcosahedronGeometry(0.018, 0), gold, 0, side * r * 0.2, r * 0.95)); // 리벳
    pad.position.set(0, side * 0.01, d.armR * 0.6);
    pad.rotation.x = side * 0.3; // 바깥으로 기울어짐
    sh.add(pad);
  }
  // ---- 팔: 윗팔 판 + 팔꿈치 보호대 + 아래팔 판(손 쪽이 벌어짐) + 큰 장갑 ----
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(limbGeo(d.upper * 0.55, d.armR * 1.15, d.armR * 1.05, 8), cloth, 0, 0, -d.upper * 0.35)); // 소매
    fig.elbows[i].add(mesh(new THREE.IcosahedronGeometry(d.foreR * 1.25, 0), steel));
    fig.elbows[i].add(mesh(limbGeo(d.lower * 0.7, d.foreR * 1.1, d.foreR * 1.35, 8), steel, 0, 0, -d.lower * 0.22));
    const fist = new THREE.IcosahedronGeometry(d.hand * 1.15, 0);
    fist.scale(1.1, 0.9, 1);
    fig.hands[i].add(mesh(fist, dark));
  }
  // ---- 다리: 허벅지 앞 판 + 무릎 보호대(+ 날개) + 정강이 판 + 겹친 쇠 장화 ----
  for (let i = 0; i < 2; i++) {
    fig.thighs[i].add(mesh(new THREE.BoxGeometry(0.03, d.legR * 2.1, d.thigh * 0.55), steel, d.legR * 1.05, 0, -d.thigh * 0.38));
    const kn = fig.knees[i];
    kn.add(mesh(new THREE.IcosahedronGeometry(d.legR * 1.15, 0), steel, d.legR * 0.35, 0, 0));
    kn.add(mesh(new THREE.BoxGeometry(0.02, d.legR * 2.6, d.legR * 1.1), dark, d.legR * 0.9, 0, 0)); // 무릎 날개
    kn.add(mesh(limbGeo(d.shin * 0.75, d.legR * 1.05, d.legR * 0.95, 8), steel, 0, 0, -d.shin * 0.12));
    const ft = fig.feet[i];
    ft.add(mesh(new THREE.BoxGeometry(d.legR * 3.3, d.legR * 1.8, d.foot * 1.15), dark, d.legR * 0.65, 0, -d.foot / 2));
    for (let k = 0; k < 2; k++) ft.add(mesh(new THREE.BoxGeometry(d.legR * 0.9, d.legR * 1.7, 0.03), steel, d.legR * (1.2 + k * 0.75), 0, 0.01 - k * 0.015)); // 발등 겹판
  }

  // ---- 등에 둥근 방패: 플레이어 색 판 + 쇠 테두리 + 가로 띠 + 가운데 돌기 ----
  const shield = new THREE.Group();
  const sr = Math.max(0.28, d.chestR * 1.15);
  const disk = new THREE.CylinderGeometry(sr, sr, 0.045, 10);
  disk.rotateZ(Math.PI / 2); // 원판 면이 앞뒤(x)를 보게
  shield.add(mesh(disk, cloth));
  const rim = new THREE.TorusGeometry(sr, 0.03, 4, 10);
  rim.rotateY(Math.PI / 2);
  shield.add(mesh(rim, steel));
  shield.add(mesh(new THREE.BoxGeometry(0.05, sr * 1.9, 0.06), steel, -0.005, 0, 0));
  shield.add(mesh(new THREE.IcosahedronGeometry(0.07, 0), gold, -0.04, 0, 0));
  shield.position.set(-cR * d.depth - 0.04, 0, d.torso * 0.58);
  shield.rotation.y = 0.15; // 위가 살짝 뒤로
  fig.waist.add(shield);
  // 앞 방패: 방패 동작(돌진·올려치기·내려치기) 동안만 등 대신 가슴 앞에 (figureAnim 이 바꿔 보임)
  const front = shield.clone();
  front.position.set(cR * d.depth + 0.12, 0, d.torso * 0.5);
  front.rotation.y = -0.1;
  front.visible = false;
  fig.waist.add(front);
  fig.shields = { back: shield, front };
}

// 천 자락 (목도리 끝·머리띠 끝·코트 자락): 붙는 점이 축, -z 로 매달림. 움직이면 뒤로 날리고 살랑임 (figureAnim)
// base 가만히 있을 때 뒤로 젖힌 각, lift 최고 속도일 때 더 젖히는 각, flutter 살랑이는 폭
function flap(fig, parent, geo, mat, x, y, z, base, lift, flutter) {
  const pivot = joint(parent, x, y, z);
  geo.translate(0, 0, -geo.parameters.depth / 2);
  pivot.add(mesh(geo, mat));
  pivot.rotation.y = base;
  fig.flaps.push({ obj: pivot, base, lift, flutter });
  return pivot;
}

// 닌자: 마른 몸 + 두건(눈 둘레만 피부 띠) + 머리띠 끝 둘 + 긴 목도리 + 허리띠 + 팔·다리 감은 천 + 등에 칼
function dressNinja(fig, costume, cloth) {
  const d = fig.d;
  const black = costume(0x26262e);
  const red = costume(0xa01c24);
  const steel = costume(0xa3adb8);
  const gold = costume(0xd8a838);
  const eyeZ = d.head * 0.58;
  // 두건: 머리보다 조금 큰 각진 공 + 눈 높이에 피부 띠 (그 사이로 왕눈알)
  const hood = new THREE.IcosahedronGeometry(0.5, 1);
  hood.scale(d.headW * 1.14, d.headW * 1.12, d.head * 1.1);
  fig.neck.add(mesh(hood, black, 0, 0, d.head / 2 + 0.005));
  fig.neck.add(mesh(ringGeo(d.headW * 0.58, d.headW * 0.58, 0.06, 8), cloth, 0, 0, eyeZ));
  fig.neck.add(mesh(ringGeo(d.headW * 0.6, d.headW * 0.6, 0.035, 8), red, 0, 0, eyeZ + 0.06)); // 머리띠
  for (const side of [-1, 1]) flap(fig, fig.neck, new THREE.BoxGeometry(0.012, 0.035, 0.2), red, -d.headW * 0.55, side * 0.02, eyeZ + 0.06, 0.6, 0.8, 0.25);
  addEyes(fig.neck, d.headW * 0.6, 0.042, eyeZ, C.FIGURE_EYE * 0.9);
  // 목도리: 목 둘레 고리 + 등 뒤로 길게 늘어진 두 자락
  const scarf = new THREE.TorusGeometry(d.chestR * 0.62, 0.035, 4, 8);
  fig.waist.add(mesh(scarf, red, 0, 0, d.torso - 0.02));
  for (const side of [-1, 1]) flap(fig, fig.waist, new THREE.BoxGeometry(0.015, 0.07, 0.5), red, -d.chestR * 0.6, side * 0.04, d.torso - 0.03, 0.25, 1.05, 0.2);
  // 몸통 옷: 검은 조끼 (앞 V 로 피부가 보이게 앞쪽을 비움)
  const vest = new THREE.CylinderGeometry(d.chestR * 1.06, d.waistR * 1.1, d.torso * 0.85, 8, 1, true, Math.PI / 2 + 0.35, Math.PI * 2 - 0.7);
  vest.rotateX(Math.PI / 2);
  vest.scale(d.depth, 1, 1);
  const vm = mesh(vest, black, 0, 0, d.torso * 0.5);
  vm.material.side = THREE.DoubleSide;
  fig.waist.add(vm);
  fig.waist.add(mesh(ringGeo(d.waistR * 1.18, d.waistR * 1.18, 0.07, 8, d.depth), red, 0, 0, 0.06)); // 허리띠
  for (const side of [-1, 1]) flap(fig, fig.waist, new THREE.BoxGeometry(0.012, 0.04, 0.16), red, -d.waistR * d.depth, side * 0.03, 0.05, 0.3, 0.6, 0.2);
  // 팔·다리 감은 천 (아래팔·정강이) + 검은 신발
  for (let i = 0; i < 2; i++) {
    fig.elbows[i].add(mesh(limbGeo(d.lower * 0.6, d.foreR * 1.2, d.foreR * 1.05, 6), black, 0, 0, -d.lower * 0.3));
    fig.knees[i].add(mesh(limbGeo(d.shin * 0.55, d.legR * 0.95, d.legR * 0.85, 6), black, 0, 0, -d.shin * 0.42));
    fig.feet[i].add(mesh(new THREE.BoxGeometry(d.legR * 3.1, d.legR * 1.6, d.foot * 1.1), black, d.legR * 0.6, 0, -d.foot / 2));
  }
  // 등에 칼: 비스듬한 칼집 + 금색 코등이 + 손잡이 (오른 어깨 위로 손잡이)
  const sword = new THREE.Group();
  sword.add(mesh(new THREE.BoxGeometry(0.035, 0.05, 0.62), black, 0, 0, -0.1));
  sword.add(mesh(ringGeo(0.05, 0.05, 0.015, 8), gold, 0, 0, 0.22));
  sword.add(mesh(new THREE.BoxGeometry(0.03, 0.03, 0.16), steel, 0, 0, 0.31));
  sword.position.set(-d.chestR * d.depth - 0.03, 0, d.torso * 0.55);
  sword.rotation.x = 0.7; // 손잡이가 오른 어깨 쪽(-y)으로
  fig.waist.add(sword);
  // 두 손에 단검: 주먹 끝에서 팔이 뻗는 쪽(-z)으로 짧은 날 + 검은 손잡이 → 찌르면 날이 앞으로
  for (const hand of fig.hands) {
    hand.add(mesh(new THREE.BoxGeometry(0.022, 0.05, 0.05), black, 0, 0, -d.hand * 0.6));
    const blade = new THREE.ConeGeometry(0.028, 0.2, 4);
    blade.rotateX(-Math.PI / 2); // 끝이 -z
    blade.scale(1, 0.35, 1); // 납작한 날
    hand.add(mesh(blade, steel, 0, 0, -d.hand * 0.6 - 0.12));
  }
}

// 건축가: 다부진 보통 몸 + 노란 안전모 + 주황 작업 조끼(반사 띠, 앞이 열려 셔츠(피부)가 보임) + 공구 벨트 + 장갑·작업화 + 등에 테트리미노 가방
function dressBuilder(fig, costume, cloth) {
  const d = fig.d;
  const yellow = costume(0xf2c418);
  const orange = costume(0xff7a1a);
  const reflect = costume(0xe6edf2);
  const brown = costume(0x6a4428);
  const tan = costume(0xc9a06a);
  const steel = costume(0xa3adb8);
  const piece = costume(0x30c8e8); // 테트리미노 (하늘색: 조끼 주황·모자 노랑과 안 겹침)
  // 안전모: 돔 + 앞으로 긴 챙 + 가운데 능선
  const browZ = d.head * 0.7;
  const hat = mesh(domeGeo(d.headW * 0.66), yellow, 0, 0, browZ);
  hat.scale.z = 0.85;
  fig.neck.add(hat);
  const brim = mesh(ringGeo(d.headW * 0.72, d.headW * 0.72, 0.025, 10), yellow, 0.025, 0, browZ);
  brim.scale.x = 1.25;
  fig.neck.add(brim);
  fig.neck.add(mesh(new THREE.BoxGeometry(d.headW * 1.2, 0.03, 0.04), yellow, 0, 0, browZ + d.headW * 0.55));
  addEyes(fig.neck, d.headW * 0.44, 0.05, d.head * 0.5, C.FIGURE_EYE);
  // 조끼: 앞이 열린 원통 + 반사 띠 둘
  const open = 0.9; // 앞에 비우는 각
  const vestGeo = (r1, r2, h) => {
    const g = new THREE.CylinderGeometry(r1, r2, h, 10, 1, true, Math.PI / 2 + open / 2, Math.PI * 2 - open);
    g.rotateX(Math.PI / 2);
    g.scale(d.depth, 1, 1);
    return g;
  };
  const vest = mesh(vestGeo(d.chestR * 1.08, d.waistR * 1.12, d.torso * 0.78), orange, 0, 0, d.torso * 0.55);
  vest.material.side = THREE.DoubleSide;
  fig.waist.add(vest);
  for (const z of [0.42, 0.62]) {
    const r = d.waistR + (d.chestR - d.waistR) * ((z - 0.16) / 0.78);
    const s = mesh(vestGeo(r * 1.13, r * 1.13, 0.035), reflect, 0, 0, d.torso * z);
    s.material.side = THREE.DoubleSide;
    fig.waist.add(s);
  }
  // 공구 벨트 + 주머니 + 옆에 매단 작은 망치
  fig.waist.add(mesh(ringGeo(d.waistR * 1.2, d.waistR * 1.2, 0.06, 8, d.depth), brown, 0, 0, 0.05));
  for (const ang of [0.9, -0.9, 2.2]) fig.waist.add(mesh(new THREE.BoxGeometry(0.06, 0.08, 0.09), tan, Math.cos(ang) * d.waistR * 1.2 * d.depth, Math.sin(ang) * d.waistR * 1.2, 0.0));
  const tool = new THREE.Group();
  tool.add(mesh(new THREE.BoxGeometry(0.025, 0.025, 0.16), brown, 0, 0, -0.06));
  tool.add(mesh(new THREE.BoxGeometry(0.07, 0.04, 0.04), steel, 0, 0, 0.03));
  tool.position.set(0, -d.waistR * 1.25, 0.0);
  fig.waist.add(tool);
  // 장갑·작업화
  for (let i = 0; i < 2; i++) {
    fig.hands[i].add(mesh(new THREE.IcosahedronGeometry(d.hand * 1.2, 0), tan));
    fig.feet[i].add(mesh(new THREE.BoxGeometry(d.legR * 3.3, d.legR * 1.8, d.foot * 1.4), brown, d.legR * 0.65, 0, -d.foot / 2));
  }
  // 등 가방: 어깨끈 둘 + 테트리미노 T (작은 상자 4개)
  for (const side of [-1, 1]) fig.waist.add(mesh(new THREE.BoxGeometry(d.chestR * 2 * d.depth + 0.02, 0.035, 0.035), brown, 0, side * d.chestR * 0.5, d.torso * 0.86));
  const c = 0.13;
  const back = -d.chestR * d.depth - c / 2 - 0.01;
  for (const [y, z] of [[-c, 0], [0, 0], [c, 0], [0, -c]]) {
    const cube = mesh(new THREE.BoxGeometry(c * 0.94, c * 0.94, c * 0.94), piece, back, y, d.torso * 0.68 + z);
    fig.waist.add(cube);
  }
}

// 갈고리: 팔 긴 보통 몸 + 해적 삼각모 + 안대 (눈알 하나) + 앞이 열린 긴 코트(자락 날림) + 허리에 감은 밧줄 + 왼손 갈고리 + 장화
function dressHook(fig, costume, cloth) {
  const d = fig.d;
  const black = costume(0x222228);
  const coat = costume(0x4a2e1f);
  const gold = costume(0xd8a838);
  const rope = costume(0xc8a36a);
  const steel = costume(0xa3adb8);
  const eyeZ = d.head * 0.55;
  // 삼각모: 세모난 챙 (모서리 하나가 앞) + 금색 테 + 낮은 머리 부분
  const browZ = d.head * 0.8;
  const brim = new THREE.CylinderGeometry(d.headW * 1.05, d.headW * 1.05, 0.035, 3);
  brim.rotateX(Math.PI / 2);
  fig.neck.add(mesh(brim, black, 0, 0, browZ));
  // 챙 세 변을 위로 접어 올림 (삼각모 모양): 변마다 바깥으로 기운 판 + 금색 테
  const R = d.headW * 1.05;
  for (let k = 0; k < 3; k++) {
    const ang = Math.PI / 3 + (k * 2 * Math.PI) / 3; // 변 가운데 방향 (모서리 하나가 앞 = 0)
    const wall = new THREE.Group();
    wall.position.set(Math.cos(ang) * R * 0.5, Math.sin(ang) * R * 0.5, browZ);
    wall.rotation.z = ang;
    const side = mesh(new THREE.BoxGeometry(0.018, R * 1.6, 0.075), black, 0, 0, 0.035);
    side.rotation.y = -0.45; // 위가 바깥으로
    wall.add(side);
    const edge = mesh(new THREE.BoxGeometry(0.02, R * 1.6, 0.014), gold, 0.03, 0, 0.07);
    edge.rotation.y = -0.45;
    wall.add(edge);
    fig.neck.add(wall);
  }
  fig.neck.add(mesh(ringGeo(d.headW * 0.5, d.headW * 0.56, d.head * 0.25, 8), black, 0, 0, browZ + d.head * 0.12));
  // 안대: 오른눈(-y) 자리에 검은 판 + 머리를 비스듬히 두른 끈. 왼눈만 왕눈알
  fig.neck.add(mesh(new THREE.CylinderGeometry(0.045, 0.045, 0.02, 8).rotateZ(Math.PI / 2), black, d.headW * 0.5, -0.045, eyeZ));
  const strap = mesh(ringGeo(d.headW * 0.52, d.headW * 0.52, 0.012, 10), black, 0, 0, eyeZ + 0.02);
  strap.rotation.x = 0.35;
  fig.neck.add(strap);
  addEyes(fig.neck, d.headW * 0.44, 0.045, eyeZ, C.FIGURE_EYE, [1]);
  // 긴 코트: 앞이 열린 원통 (안쪽 셔츠 = 피부) + 금단추 + 뒤로 늘어진 자락 셋
  const open = 0.8;
  const coatGeo = new THREE.CylinderGeometry(d.chestR * 1.1, d.waistR * 1.25, d.torso * 0.95, 10, 1, true, Math.PI / 2 + open / 2, Math.PI * 2 - open);
  coatGeo.rotateX(Math.PI / 2);
  coatGeo.scale(d.depth, 1, 1);
  const cm = mesh(coatGeo, coat, 0, 0, d.torso * 0.5);
  cm.material.side = THREE.DoubleSide;
  fig.waist.add(cm);
  for (const side of [-1, 1]) for (let k = 0; k < 3; k++) {
    const ang = side * (open / 2 + 0.12);
    const r = d.waistR * 1.25 + (d.chestR * 1.1 - d.waistR * 1.25) * (0.3 + k * 0.22);
    fig.waist.add(mesh(new THREE.IcosahedronGeometry(0.018, 0), gold, Math.cos(ang) * r * d.depth + 0.005, Math.sin(ang) * r, d.torso * (0.3 + k * 0.22)));
  }
  for (const [y, w] of [[0, 0.16], [-0.13, 0.11], [0.13, 0.11]]) flap(fig, fig.hips, new THREE.BoxGeometry(0.02, w, 0.42), coat, -d.waistR * d.depth - 0.02, y, 0.04, 0.08, 0.7, 0.1);
  // 큰 소매 끝동 (금 테) + 밧줄 감은 허리 + 넓은 허리띠·버클
  for (const el of fig.elbows) el.add(mesh(limbGeo(0.08, d.foreR * 1.5, d.foreR * 1.7, 8), coat, 0, 0, -d.lower * 0.55));
  fig.waist.add(mesh(ringGeo(d.waistR * 1.15, d.waistR * 1.15, 0.06, 8, d.depth), black, 0, 0, 0.06));
  fig.waist.add(mesh(new THREE.BoxGeometry(0.03, 0.07, 0.06), gold, d.waistR * 1.15 * d.depth + 0.01, 0, 0.06));
  const coil = new THREE.TorusGeometry(0.07, 0.022, 4, 10);
  coil.rotateX(Math.PI / 2);
  fig.waist.add(mesh(coil, rope, 0, d.waistR * 1.3, 0.02));
  fig.waist.add(mesh(coil.clone(), rope, 0, d.waistR * 1.3, 0.06));
  // 왼손 = 갈고리: 피부 손을 빼고 쇠 손목 + 굽은 갈고리
  const hand = fig.hands[1];
  hand.clear();
  hand.add(mesh(limbGeo(0.06, d.foreR * 1.1, d.foreR * 1.1, 8), steel, 0, 0, 0.03));
  const hook = new THREE.TorusGeometry(0.08, 0.02, 4, 10, Math.PI * 1.3);
  hook.rotateX(Math.PI / 2); // 갈고리가 앞뒤(x-z) 면에서 굽음
  fig.hands[1].add(mesh(hook, steel, 0.04, 0, -0.11));
  fig.hands[1].add(mesh(limbGeo(0.06, 0.02, 0.02, 4), steel, 0, 0, -0.03));
  // 장화: 정강이 덮는 검은 통 + 접힌 윗단
  for (let i = 0; i < 2; i++) {
    fig.knees[i].add(mesh(limbGeo(d.shin * 0.75, d.legR * 1.15, d.legR * 1.0, 8), black, 0, 0, -d.shin * 0.25));
    fig.knees[i].add(mesh(ringGeo(d.legR * 1.4, d.legR * 1.25, 0.05, 8), black, 0, 0, -d.shin * 0.22));
    fig.feet[i].add(mesh(new THREE.BoxGeometry(d.legR * 3.2, d.legR * 1.7, d.foot * 1.2), black, d.legR * 0.6, 0, -d.foot / 2));
  }
  // 플린트록 권총: 평소엔 오른쪽 허리에 꽂힘 (장전이면 부싯돌 자리에 불꽃, render.js 가 켬), 탕 동작 동안만 오른손에
  const wood = costume(0x6a3e22);
  const pistol = () => {
    const g = new THREE.Group(); // 총열이 -z, 손잡이가 +z 쪽 (손 기준: 팔이 뻗는 쪽으로 총열)
    g.add(mesh(new THREE.BoxGeometry(0.035, 0.035, 0.26), steel, 0, 0, -0.13)); // 총열
    g.add(mesh(new THREE.BoxGeometry(0.05, 0.045, 0.12), wood, 0, 0, -0.03)); // 몸통 (나무)
    g.add(mesh(new THREE.BoxGeometry(0.06, 0.04, 0.03), gold, 0, 0, -0.27)); // 총구 테
    g.add(mesh(new THREE.BoxGeometry(0.03, 0.04, 0.03), black, 0.03, 0, 0.0)); // 부싯돌 공이
    return g;
  };
  const holster = pistol();
  holster.position.set(d.waistR * 0.3 * d.depth, -d.waistR * 1.25, 0.05);
  holster.rotation.y = -0.4; // 총열이 아래·조금 뒤로
  fig.waist.add(holster);
  const spark = new THREE.Mesh(new THREE.IcosahedronGeometry(0.03, 0), noOutline(new THREE.MeshBasicMaterial({ color: 0xffd040 })));
  spark.position.set(0.05, 0, 0.0);
  holster.add(spark);
  const inHand = pistol();
  inHand.position.set(0, 0, -d.hand * 0.6);
  inHand.visible = false;
  fig.hands[0].add(inHand);
  fig.gun = { holster, inHand, spark };
}

// ---------- 동작 ----------
// 관절마다 목표 각도를 정하고 FIGURE_FOLLOW 빠르기로 따라감 → 살짝 늦게 따라와 흐느적거림 (TABS 느낌)
// 각도 이름: fwd = 앞으로 드는 각 (어깨·허벅지), out = 옆으로 벌리는 각 (어깨), bend = 굽힘 (팔꿈치 앞, 무릎 뒤)
// waistSide = 허리를 왼쪽(+y)으로 기울인 각, waistRoll = 허리 비틂 (위에서 봐서 왼쪽으로 돎)
function restPose(d) {
  return {
    waistPitch: d.hunch,
    waistRoll: 0,
    waistSide: 0,
    neckPitch: -d.hunch,
    hipsZ: 0,
    shFwd: [0, 0],
    shOut: [d.spread, d.spread],
    elbow: [0.15, 0.15],
    thFwd: [0, 0],
    thOut: [0, 0],
    knee: [0, 0],
  };
}

// 맞은 순간 자세 (히트스톱 동안 이대로 멈칫): 팔다리가 맞은 쪽 반대로 남고 (몸통만 먼저 밀림), 무릎이 꺾임.
// dx·dy = 밀려나는 방향 (몸 기준, 앞 +x 왼쪽 +y), pow = 세기
function hitPose(T, dx, dy, pow) {
  const fling = Math.min(1.6, 0.9 * pow);
  T.shFwd = [-dx * fling + 0.3, -dx * fling + 0.3];
  T.shOut = [0.9 + 0.4 * pow + dy * 0.5, 0.9 + 0.4 * pow - dy * 0.5];
  T.elbow = [0.5, 0.5];
  T.thFwd = [-dx * 0.4 * pow + 0.2, -dx * 0.2 * pow];
  T.thOut = [Math.max(0, -dy) * 0.4, Math.max(0, dy) * 0.4];
  T.knee = [0.6, 0.3];
  T.neckPitch = -dx * 0.35 * pow;
  T.waistRoll = dy * 0.3;
}

// 휘청 스프링 (허리 앞뒤·좌우 각). 맞으면 밀린 방향으로 꺾인 채 시작해 그 방향으로 한 번 더 튕긴 뒤 흔들리며 섬
function stepSway(sw, dt) {
  const n = Math.max(1, Math.ceil(dt / 0.01));
  const h = dt / n;
  for (let i = 0; i < n; i++) {
    for (const [x, v] of [['x', 'vx'], ['y', 'vy']]) {
      sw[v] += (-C.FIGURE_HIT_SPRING_K * sw[x] - C.FIGURE_HIT_SPRING_DAMP * sw[v]) * h;
      sw[x] += sw[v] * h;
    }
  }
}

// ---------- 공격 동작 (평타·스킬·필살기) ----------
// 동작마다 준비 자세 W 와 타격 자세 S. 준비(크게, 상대가 읽는 예고) → 타격(아주 짧게 S 로 튐) → 회복(S 에서 천천히 풀림).
// 공격 자세는 FIGURE_FOLLOW 를 건너뛰고 바로 그 자세 (속은 격투), 끝나면 평소처럼 흐물흐물 돌아옴 (겉은 병맛).
// 자세 칸: 허리 waistPitch(앞 숙임)·waistRoll(왼쪽으로 비틂 = 오른 어깨 앞)·waistSide, 고개 neckPitch,
// 팔다리 [오른쪽, 왼쪽] (null = 그대로): shFwd(앞으로 듦)·shOut(옆으로 벌림)·elbow·thFwd·knee, crouch(0~1 두 무릎 굽힘)
// spin: 타격~회복 동안 몸 전체를 도는 각 (라디안, +면 왼쪽으로). rec: 스킬처럼 서버 표에 회복 시간이 없을 때 (초)
// shield: 그 동작 동안 탱크 방패를 등에서 몸 앞으로. turn: 타격 동안 몸을 그 각만큼 돌렸다가 회복 끝에 돌아옴. float: 다리를 앞으로 뻗어도 엉덩이를 바닥으로 안 내림 (날아가는 자세)
const R = (v) => [v, null]; // 오른팔(다리)만
const L = (v) => [null, v]; // 왼팔(다리)만
export const MOVES = {
  // 아무 표에도 없을 때 (캐릭터 없는 밀치기)
  punch: { W: { shFwd: R(-0.4), elbow: R(1.6), waistRoll: -0.3 }, S: { shFwd: R(1.55), shOut: R(0.1), elbow: R(0.05), waistRoll: 0.3 } },

  // 탱크: 묵직하게. 주먹 → 어깨 박치기 → 방패 밀기(두 팔)
  '주먹': { W: { shFwd: R(-0.3), elbow: R(2.1), shOut: R(1.0), waistRoll: -0.6, waistSide: 0.15, crouch: 0.3 }, S: { shFwd: R(1.55), elbow: R(0.05), shOut: R(0.05), waistRoll: 0.4, waistPitch: 0.2 } },
  '어깨 박치기': {
    W: { waistRoll: -0.9, waistPitch: 0.1, shFwd: [0.3, -0.4], elbow: [1.6, 1.4], crouch: 0.5 },
    S: { waistRoll: 0.5, waistPitch: 0.55, waistSide: -0.2, shFwd: [-0.3, 0.6], elbow: [1.3, 1.5], thFwd: [0.5, -0.4] },
  },
  // 3타 방패 올려치기: 방패를 앞에 들고 웅크렸다가 위로 퍼 올림 (띄움, 마무리 아님)
  '방패 올려치기': {
    W: { crouch: 0.8, waistPitch: 0.55, shFwd: [0.8, 0.8], shOut: [0.15, 0.15], elbow: [1.7, 1.7], neckPitch: -0.3 },
    S: { waistPitch: -0.55, shFwd: [2.5, 2.5], shOut: [0.2, 0.2], elbow: [0.5, 0.5], thFwd: [0.5, -0.3], neckPitch: -0.2 },
    shield: true,
  },
  // 공중 방패 내려치기 (마무리): 방패를 머리 위로 → 아래로 쾅
  '방패 내려치기': { W: { shFwd: [2.9, 2.9], elbow: [0.5, 0.5], waistPitch: -0.3 }, S: { shFwd: [0.7, 0.7], elbow: [0.1, 0.1], waistPitch: 0.7 }, shield: true },

  // 닌자: 단검·발 섞인 빠른 연타. 찌르기 → 반대 찌르기 → 앞차기 → 올려 차기(크게, 띄움) / 공중 베기 → 내려 차기
  '찌르기': { W: { shFwd: R(0.0), shOut: R(0.8), elbow: R(2.1), waistRoll: -0.45, waistSide: 0.12, crouch: 0.35 }, S: { shFwd: R(1.6), elbow: R(0), waistRoll: 0.35, waistPitch: 0.25 } },
  '반대 찌르기': { W: { shFwd: L(0.0), shOut: L(0.8), elbow: L(2.1), waistRoll: 0.45, waistSide: -0.12, crouch: 0.35 }, S: { shFwd: L(1.6), elbow: L(0), waistRoll: -0.35, waistPitch: 0.25 } },
  '앞차기': {
    W: { thFwd: [1.3, -0.1], knee: [1.8, 0.2], waistPitch: -0.15, shFwd: [0.6, 0.6], shOut: [0.5, 0.5], elbow: [1.6, 1.6] },
    S: { thFwd: [1.6, -0.2], knee: [0.05, 0.1], waistPitch: -0.35, shFwd: [-0.3, -0.3], shOut: [0.7, 0.7], elbow: [0.6, 0.6] },
  },
  '올려 차기': {
    W: { crouch: 0.7, waistPitch: 0.45, shFwd: [-0.6, -0.6], shOut: [0.4, 0.4], elbow: [0.4, 0.4], neckPitch: -0.3 },
    S: { thFwd: [2.7, -0.3], knee: [0, 0.2], waistPitch: -0.6, shOut: [1.5, 1.5], shFwd: [0, 0], elbow: [0.2, 0.2], neckPitch: 0.2 },
  },
  '표창': { W: { shFwd: R(2.6), shOut: R(0.4), elbow: R(1.7), waistRoll: -0.6, waistPitch: -0.25, thFwd: [-0.3, 0.4] }, S: { shFwd: R(1.2), shOut: R(0.1), elbow: R(0), waistRoll: 0.5, waistPitch: 0.35 } },
  // 표창 둘째 발: 왼손
  '표창2': { S: { shFwd: L(1.2), shOut: L(0.1), elbow: L(0), waistRoll: -0.5, waistPitch: 0.35 }, rec: 0.25 },
  '공중 베기': { W: { shFwd: [2.7, 0.5], elbow: [0.4, 0.8] }, S: { shFwd: [0.4, 0.2], elbow: [0.1, 0.8], waistPitch: 0.6 } },
  '내려 차기': {
    W: { thFwd: [2.3, -0.2], knee: [0.3, 0.6], waistPitch: -0.45, shFwd: [2.2, 2.2], shOut: [0.6, 0.6], elbow: [0.3, 0.3] },
    S: { thFwd: [0.2, -0.3], knee: [0, 0.6], waistPitch: 0.65, shFwd: [-0.4, -0.4], shOut: [0.9, 0.9], elbow: [0.2, 0.2] },
  },

  // 건축가: 오른손 망치질. 옆치기 → 반대로 치기 → 두 팔 내려찍기
  '옆치기': { W: { shOut: R(1.5), shFwd: R(-0.5), elbow: R(0.4), waistRoll: -0.8, crouch: 0.3 }, S: { shOut: R(0.3), shFwd: R(1.4), elbow: R(0.1), waistRoll: 0.6 } },
  '반대 치기': { W: { shOut: R(-0.4), shFwd: R(1.2), elbow: R(1.4), waistRoll: 0.8, crouch: 0.3 }, S: { shOut: R(1.4), shFwd: R(0.5), elbow: R(0.1), waistRoll: -0.6 } },
  '내려찍기': {
    W: { shFwd: [3.0, 3.0], shOut: [0.15, 0.15], elbow: [0.6, 0.6], waistPitch: -0.4, neckPitch: -0.3 },
    S: { shFwd: [0.6, 0.6], shOut: [0.1, 0.1], elbow: [0.05, 0.05], waistPitch: 0.8, neckPitch: 0.2, crouch: 0.8 },
  },
  '망치 내려찍기': { W: { shFwd: [3.0, 3.0], elbow: [0.6, 0.6], waistPitch: -0.4, crouch: 0.5 }, S: { shFwd: [0.5, 0.5], elbow: [0.05, 0.05], waistPitch: 0.8 } },

  // 갈고리: 왼손 갈고리를 크게 휘두르고 → 오른 주먹 한 방
  '갈고리 휘두르기': { W: { shOut: L(2.0), shFwd: L(-0.2), elbow: L(0.9), waistRoll: 0.5, waistSide: -0.15, crouch: 0.3 }, S: { shOut: L(0.3), shFwd: L(1.4), elbow: L(0.2), waistRoll: -0.6, waistPitch: 0.2 } },
  // 큰 주먹: 갈고리 주먹은 탱크 주먹보다 더 크게 뒤로 젖힘 (같은 이름이라 캐릭터로 구분: hook:주먹)
  'hook:주먹': { W: { shFwd: R(-0.6), shOut: R(1.2), elbow: R(2.0), waistRoll: -0.8, waistPitch: -0.25, crouch: 0.4 }, S: { shFwd: R(1.6), shOut: R(0.05), elbow: R(0), waistRoll: 0.55, waistPitch: 0.4, thFwd: [0.5, -0.4] } },
  // 3타 (장전): 탕 — 오른손 권총을 앞으로 겨눴다가 반동으로 팔이 휙 올라감 (gun: 그동안 권총이 손에)
  '탕': {
    W: { shFwd: R(1.5), shOut: R(0.1), elbow: R(0.1), waistRoll: 0.35, neckPitch: 0.05 },
    S: { shFwd: R(2.5), shOut: R(0.3), elbow: R(0.7), waistRoll: 0.2, waistPitch: -0.3, neckPitch: -0.25, thFwd: [-0.2, 0.3] },
    gun: true,
  },
  // 3타 (빈 총): 갈고리 내려치기 — 약한 마무리
  '갈고리 내려치기': { W: { shFwd: L(2.8), shOut: L(0.3), elbow: L(0.6), waistPitch: -0.25 }, S: { shFwd: L(0.6), elbow: L(0.1), waistPitch: 0.5, crouch: 0.3 } },
  // 공중 갈고리 스핀: 갈고리 팔을 쭉 뻗어 채찍처럼 수평으로 한 바퀴
  '갈고리 스핀': { W: { shOut: L(1.5), shFwd: L(-0.3), elbow: L(0.8), waistRoll: 0.6, crouch: 0.3 }, S: { shOut: L(1.6), shFwd: L(0.1), elbow: L(0), waistRoll: 0 }, spin: -Math.PI * 2 },

  // ---- 스킬·필살기 ----
  // 탱크 돌진: 어깨를 앞으로 숙이고 돌진 (판정이 바로라 준비 없음)
  // 탱크 F 방패 돌진: 방패를 앞세우고 몸을 숙여 돌진 (두 팔로 방패를 받침)
  tankCharge: { S: { waistPitch: 0.55, shFwd: [1.1, 1.1], shOut: [0.1, 0.1], elbow: [1.6, 1.6], thFwd: [0.8, -0.5], knee: [0.7, 0.3], neckPitch: -0.4 }, rec: 0.5, shield: true },
  // 탱크 내려찍기: 두 팔 번쩍 들고 떠올랐다가 (slamWarn) → 쾅 (slam)
  tankSlam: {
    W: { shFwd: [3.0, 3.0], shOut: [0.3, 0.3], elbow: [0.4, 0.4], waistPitch: -0.35, thFwd: [0.9, 0.9], knee: [1.4, 1.4] },
    S: { shFwd: [0.5, 0.5], shOut: [0.6, 0.6], elbow: [0, 0], waistPitch: 0.9, crouch: 1 },
    rec: 0.6,
  },
  // 닌자 순간 베기: 손발 싹 다 앞으로 쭉 뻗고 날아가는 자세 (TABS 병맛, 순간이동이라 원래 모션이 없음)
  ninjaDash: { S: { shFwd: [1.6, 1.6], shOut: [0.15, 0.15], elbow: [0, 0], thFwd: [1.5, 1.5], knee: [0, 0], waistPitch: -0.15, neckPitch: -0.3 }, rec: 0.45, float: true },
  // 닌자 벽 차기: 몸을 오른쪽으로 90도 돌려 (블록이 왼쪽 옆) 왼다리로 옆차기, 몸은 반대로 젖히고 팔 벌려 균형 → 튀어 오름
  ninjaWallKick: { S: { thOut: [0.1, 1.5], thFwd: [0.2, 0.1], knee: [0.5, 0], waistSide: -0.45, shOut: [1.4, 1.2], shFwd: [0.2, -0.2], elbow: [0.3, 0.3], neckPitch: -0.2 }, rec: 0.45, turn: -Math.PI / 2 },
  // 건축가 솟는 벽: 두 손을 바닥 쪽으로 모았다가 (wallWarn) → 위로 확 올림 (wallRise)
  builderWall: { W: { shFwd: [0.7, 0.7], shOut: [0.3, 0.3], elbow: [0.3, 0.3], waistPitch: 0.6, crouch: 0.8 }, S: { shFwd: [2.9, 2.9], shOut: [0.4, 0.4], elbow: [0.1, 0.1], waistPitch: -0.3 }, rec: 0.5 },
  // 건축가 대폭발: 망치를 두 손으로 머리 위로 → 바닥을 쾅 (그 앞에 3×3 이 솟음)
  builderBig: { S: { shFwd: [0.5, 0.5], shOut: [0.1, 0.1], elbow: [0.05, 0.05], waistPitch: 0.85, neckPitch: 0.2, crouch: 0.9 }, rec: 0.6 },
  // 건축가 공중 F 발판: 발밑 블록이 엉덩이를 차올림 → 놀라서 팔다리 쫙, 엉덩이부터 튀어 오름 (병맛)
  builderPad: { S: { shFwd: [2.4, 2.4], shOut: [1.4, 1.4], elbow: [0.2, 0.2], thFwd: [1.4, 1.4], knee: [0.3, 0.3], waistPitch: -0.6, neckPitch: -0.5 }, rec: 0.55 },
  // 갈고리 던지기: 왼팔 쭉 → 당기며 몸을 뒤로
  hookThrow: { S: { shFwd: L(1.6), shOut: L(0.05), elbow: L(0), waistRoll: -0.5, waistPitch: 0.25 }, rec: 0.5, pull: true },
  // 갈고리에 끌려오는 쪽: TABS 처럼 몸이 질질 (힘 빠진 팔다리가 뒤로 처지고 고개가 젖혀짐). 경직 중에도 보임 (stunOk)
  hookDragged: { S: { shFwd: [-0.7, -0.5], shOut: [0.9, 1.1], elbow: [0.4, 0.6], thFwd: [-0.6, -0.3], knee: [1.1, 0.6], waistPitch: 0.45, neckPitch: -0.6 }, rec: 0.45, stunOk: true },
  // 갈고리로 블록에 걸어 내가 끌려감: 갈고리 팔을 앞으로 쭉, 다리는 뒤로 날림
  hookZip: { S: { shFwd: [-0.4, 2.0], shOut: [0.8, 0.1], elbow: [0.6, 0], thFwd: [-0.5, -0.2], knee: [0.9, 0.5], waistPitch: 0.35, neckPitch: -0.3 }, rec: 0.45, float: true },
  // R 블록 내려찍기: 뽑은 블록을 사슬로 머리 위에서 돌림 (blockGrab ~ blockSlam) → 앞으로 쾅
  hookSlam: {
    W: { shFwd: [2.9, 2.9], shOut: [0.3, 0.3], elbow: [0.5, 0.5], waistPitch: -0.3, neckPitch: -0.4 },
    S: { shFwd: [0.8, 0.8], shOut: [0.1, 0.1], elbow: [0.05, 0.05], waistPitch: 0.8, neckPitch: 0.2, crouch: 0.6 },
    rec: 0.5,
  },
};
// 끊긴 공격: 팔이 튕겨 나가며 자세가 무너짐 (뒤로 젖히고 무릎이 꺾임)
const BROKEN = { shFwd: [2.3, 1.9], shOut: [1.3, 1.5], elbow: [0.2, 0.5], waistPitch: -0.25, neckPitch: -0.45, waistRoll: 0.3, crouch: 0.6 };

// 공격 자세를 P 에 바로 덮어씀 (w = 0~1 섞는 정도). 값은 절대 각 (매 프레임 쌓이지 않게).
// crouch 는 이번 프레임 목표 자세 T 의 다리에서 두 무릎을 더 굽힌 각 (다리 각을 직접 준 동작은 그쪽이 이김)
function overlay(P, T, pose, w) {
  if (!pose || w <= 0) return;
  if (pose.crouch) {
    for (let i = 0; i < 2; i++) {
      P.thFwd[i] += (T.thFwd[i] + 0.9 * pose.crouch - P.thFwd[i]) * w;
      P.knee[i] += (T.knee[i] + 1.6 * pose.crouch - P.knee[i]) * w;
    }
  }
  for (const [key, val] of Object.entries(pose)) {
    if (val === null || val === undefined || !(key in P)) continue;
    if (Array.isArray(val)) {
      val.forEach((v, i) => {
        if (v !== null) P[key][i] += (v - P[key][i]) * w;
      });
    } else P[key] += (val - P[key]) * w;
  }
}

// 자세 값이 다 정상인지 (NaN·무한대 없음)
function poseOk(P) {
  for (const v of Object.values(P)) {
    if (Array.isArray(v) ? !v.every(Number.isFinite) : !Number.isFinite(v)) return false;
  }
  return true;
}

// 0~1 → 부드럽게
const ease = (u) => {
  const x = Math.max(0, Math.min(1, u));
  return x * x * (3 - 2 * x);
};

// st: { air, walking, hs, walk(위상), stunned, dancing, emote, emoteT, punch(0~1), holding(왼손에 든 것 있음), t,
//       hit(맞은 것: { id, age 초, stop 히트스톱 초, dx, dy 밀린 방향(몸 기준), pow 세기 } 또는 null),
//       tumble(0~1 구르는 중), recover(0~1 일어나는 중), land(0~1 착지 무릎), flip(0~1 2단 점프 공중제비 중, 아니면 -1),
//       act(공격 동작: { id, move(MOVES 이름), phase 'wind'|'strike'|'rec'|'broken', u 0~1 } 또는 null) }
export function figureAnim(fig, st, dt, retry = false) {
  const d = fig.d;
  const T = restPose(d);
  // 안전장치: 이상한 값(NaN·무한대)이 들어온 맞음·공격은 버림 (한 번 들어가면 자세에 영영 남아 몸이 무너짐)
  const finite = (...v) => v.every(Number.isFinite);
  st = { ...st };
  for (const k of ['hs', 'walk', 't', 'tumble', 'recover', 'land', 'punch', 'emoteT']) if (!finite(st[k] ?? 0)) st[k] = 0;
  if (!finite(st.flip ?? -1)) st.flip = -1;
  const t = st.t;
  const hit = st.hit && finite(st.hit.dx, st.hit.dy, st.hit.pow, st.hit.age, st.hit.stop) ? st.hit : null;
  if (st.act && !(finite(st.act.u) && MOVES[st.act.move] !== undefined)) st.act = null;
  if (!finite(dt) || dt < 0) dt = 0;
  const sw = fig.sway || (fig.sway = { x: 0, y: 0, vx: 0, vy: 0, id: null });
  if (!finite(sw.x, sw.y, sw.vx, sw.vy)) Object.assign(sw, { x: 0, y: 0, vx: 0, vy: 0 });
  if (fig.pose && !poseOk(fig.pose)) fig.pose = null; // 깨진 자세는 버리고 기본 자세부터
  if (hit && hit.id !== sw.id) {
    // 새로 맞음: 밀린 쪽으로 꺾인 채 시작 (멈칫 뒤 그쪽으로 튕김)
    sw.id = hit.id;
    sw.x = hit.dx * C.FIGURE_HIT_LEAN * hit.pow;
    sw.y = hit.dy * C.FIGURE_HIT_LEAN * hit.pow;
    sw.vx = hit.dx * C.FIGURE_HIT_KICK * hit.pow;
    sw.vy = hit.dy * C.FIGURE_HIT_KICK * hit.pow;
  }
  const frozen = !!hit && hit.age < hit.stop; // 히트스톱: 맞은 자세로 멈춤
  if (!frozen) stepSway(sw, dt);

  if (st.walking) {
    const amp = Math.min(1, st.hs / C.MOVE_SPEED);
    for (let i = 0; i < 2; i++) {
      const ph = st.walk + (i ? Math.PI : 0);
      T.thFwd[i] = Math.sin(ph) * C.FIGURE_WALK_LEG * amp;
      // 뒤로 차 올리는 무릎 (빠를수록 높이)
      T.knee[i] = Math.max(0, -Math.cos(ph)) * C.FIGURE_WALK_KNEE * amp + Math.max(0, -Math.sin(ph)) * 0.4 * amp;
      T.shFwd[i] = -Math.sin(ph) * C.FIGURE_WALK_ARM * amp + 0.15 * amp;
      T.elbow[i] = 0.3 + C.FIGURE_RUN_ELBOW * amp + Math.max(0, -Math.sin(ph)) * 0.3 * amp; // 앞으로 올 때 더 굽혀 펌프
      T.shOut[i] = d.spread * (1 - 0.5 * amp);
    }
    T.waistPitch = d.hunch + C.FIGURE_RUN_LEAN * amp;
    T.waistRoll = -Math.sin(st.walk) * C.FIGURE_RUN_TWIST * amp; // 어깨가 다리 반대로 비틂
    T.waistSide = Math.sin(st.walk) * 0.05 * amp; // 디딘 다리 쪽으로 살짝
    T.neckPitch = -d.hunch - C.FIGURE_RUN_LEAN * amp * 0.6 + Math.cos(st.walk * 2) * 0.05 * amp; // 고개는 앞을 봄
  } else {
    T.waistPitch = d.hunch + Math.sin(t * 2) * 0.02; // 숨쉬기
    T.shOut = T.shOut.map((o, i) => o + Math.sin(t * 1.7 + i) * 0.03);
  }
  if (st.air) {
    // 공중: 팔을 벌려 허우적, 한쪽 무릎을 올림
    T.shOut = [1.1 + Math.sin(t * 14) * 0.25, 1.1 + Math.sin(t * 14 + 1) * 0.25];
    T.shFwd = [0.2, 0.2];
    T.elbow = [0.4, 0.4];
    T.thFwd = [0.7, -0.15];
    T.knee = [1.0, 0.3];
    T.waistRoll = 0;
    T.waistSide = 0;
  }
  if (st.flip >= 0) {
    // 2단 점프 공중제비: 무릎을 가슴으로 당겨 웅크림 (돌기는 render.js 가 몸 전체를)
    const tuck = Math.min(1, st.flip * 5, (1 - st.flip) * 3); // 시작하자마자 웅크리고 끝에서 폄
    T.thFwd = [1.9 * tuck, 1.9 * tuck];
    T.knee = [2.2 * tuck, 2.2 * tuck];
    T.shFwd = [1.2 * tuck, 1.2 * tuck];
    T.shOut = [0.3, 0.3];
    T.elbow = [1.6 * tuck, 1.6 * tuck];
    T.waistPitch = 0.5 * tuck;
    T.neckPitch = 0.3 * tuck;
  }
  if (st.stunned) {
    // 맞고 날아가는 중: 팔다리를 크게 벌리고 버둥
    T.shOut = [1.5 + Math.sin(t * 20) * 0.3, 1.5 + Math.cos(t * 18) * 0.3];
    T.shFwd = [Math.sin(t * 16) * 0.5, Math.cos(t * 15) * 0.5];
    T.thOut = [0.35, 0.35];
    T.thFwd = [Math.sin(t * 17) * 0.5, -Math.sin(t * 17) * 0.5];
    T.knee = [0.5, 0.5];
    T.neckPitch = -0.3;
    T.waistRoll = 0;
    T.waistSide = 0;
    if (st.tumble > 0) {
      // 크게 날아가며 구르는 중: 몸을 공처럼 말아 굴러가는 게 보이게
      const c = st.tumble;
      T.thFwd = T.thFwd.map((v) => v * (1 - c) + 1.6 * c);
      T.knee = T.knee.map((v) => v * (1 - c) + 2.0 * c);
      T.shFwd = T.shFwd.map((v) => v * (1 - c) + 1.0 * c);
      T.shOut = T.shOut.map((v) => v * (1 - c) + 0.6 * c);
      T.elbow = [1.2, 1.2];
      T.waistPitch = 0.6 * c;
      T.neckPitch = 0.4 * c;
    }
  } else if (st.recover > 0) {
    // 경직이 풀림: 쪼그려 앉았다가 손으로 균형 잡으며 일어남
    const r = st.recover * st.recover * (3 - 2 * st.recover);
    T.thFwd = T.thFwd.map((v) => v + 1.1 * r);
    T.knee = T.knee.map((v) => v + 1.9 * r);
    T.waistPitch += 0.55 * r;
    T.neckPitch -= 0.45 * r;
    T.shFwd = T.shFwd.map((v) => v + 0.7 * r);
    T.shOut = T.shOut.map((v) => v + 0.6 * r);
    T.elbow = T.elbow.map((v) => v + 0.3 * r);
  }
  if (st.land > 0 && !st.air && !st.stunned) {
    // 착지: 무릎을 굽혀 받음 (떨어진 속도만큼)
    const l = st.land;
    T.thFwd = T.thFwd.map((v) => v + 0.6 * C.FIGURE_LAND_KNEE * l);
    T.knee = T.knee.map((v) => v + 1.1 * C.FIGURE_LAND_KNEE * l);
    T.waistPitch += 0.3 * C.FIGURE_LAND_KNEE * l;
    T.neckPitch -= 0.2 * C.FIGURE_LAND_KNEE * l;
    T.shOut = T.shOut.map((v) => v + 0.5 * l);
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
    T.shFwd[0] = (Math.PI / 2) * st.punch;
    T.shOut[0] = 0.1;
    T.elbow[0] = 0.05;
    T.waistRoll = 0.25 * st.punch;
  }
  if (frozen) hitPose(T, hit.dx, hit.dy, hit.pow);

  // 따라가기 (처음엔 바로 그 자세, 히트스톱도 바로 그 자세로 멈칫)
  const k = fig.pose && !frozen ? 1 - Math.exp(-C.FIGURE_FOLLOW * (st.flip >= 0 ? 2.5 : 1) * dt) : 1; // 공중제비는 빨리 웅크려야 보임
  const P = fig.pose || (fig.pose = restPose(d));
  const lerp = (a, b) => a + (b - a) * k;
  for (const key of Object.keys(T)) {
    if (Array.isArray(T[key])) P[key] = P[key].map((v, i) => lerp(v, T[key][i]));
    else P[key] = lerp(P[key], T[key]);
  }
  if (st.punch > 0 && !frozen && !st.act) {
    // 밀치기 팔은 늦게 따라오면 안 보임 (0.22초짜리) → 바로 그 자세
    P.shFwd[0] = T.shFwd[0];
    P.shOut[0] = T.shOut[0];
    P.elbow[0] = T.elbow[0];
  }
  // 공격 동작: 따라가기를 건너뛰고 바로 덮어씀. 끝나면 덮어쓴 자세에서 평소처럼 흐물흐물 돌아옴
  let spin = 0;
  const act = st.act && (st.act.phase === 'broken' || (!frozen && (!st.stunned || MOVES[st.act.move].stunOk))) ? st.act : null; // 끊김·끌려옴은 맞은 휘청 위에 겹침
  if (act) {
    const m = MOVES[act.move] || MOVES.punch;
    if (act.phase === 'wind') overlay(P, T, m.W, ease(act.u * 1.4)); // 준비 시간의 앞쪽에서 이미 크게
    else if (act.phase === 'strike') {
      overlay(P, T, m.W, 1 - act.u);
      overlay(P, T, m.S, ease(act.u * 2));
    } else if (act.phase === 'rec') {
      overlay(P, T, m.S, 1 - ease(act.u));
      if (m.pull) overlay(P, T, { shFwd: L(0.4), elbow: L(2.0), waistPitch: -0.3 }, Math.sin(Math.PI * Math.min(1, act.u * 1.5))); // 갈고리 당김
    } else if (act.phase === 'broken') {
      if (sw.brokenId !== act.id) {
        sw.brokenId = act.id;
        sw.vx -= C.FIGURE_HIT_KICK * 0.3; // 뒤로 조금 더 휘청 (맞은 휘청에 얹힘)
      }
      overlay(P, T, BROKEN, act.u < 0.25 ? 1 : 1 - ease((act.u - 0.25) / 0.75));
    }
    if (m.spin && (act.phase === 'strike' || act.phase === 'rec')) spin = m.spin * ease(act.phase === 'strike' ? act.u * 0.2 : 0.2 + act.u * 0.8);
    if (m.turn && (act.phase === 'strike' || act.phase === 'rec')) spin = m.turn * (act.phase === 'strike' ? ease(act.u) : 1 - ease((act.u - 0.6) / 0.4)); // 옆으로 돌았다가 회복 끝에 돌아옴
  }
  fig.hips.rotation.z = spin;
  if (fig.gun) {
    const inHand = !!act && !!MOVES[act.move].gun && act.phase !== 'broken';
    fig.gun.inHand.visible = inHand;
    fig.gun.holster.visible = !inHand;
  }
  if (fig.shields) {
    const front = !!act && !!MOVES[act.move].shield && act.phase !== 'broken';
    fig.shields.front.visible = front;
    fig.shields.back.visible = !front;
  }

  // 땅에 있으면 더 뻗은 다리의 발이 바닥에 닿게 엉덩이를 내림 (무릎 굽히면 주저앉음, 걸으면 자연히 오르내림)
  let drop = 0;
  const floating = act && MOVES[act.move]?.float && act.phase !== 'wind';
  if (!st.air && st.flip < 0 && !(st.tumble > 0) && !floating) {
    let reach = 0;
    for (let i = 0; i < 2; i++) {
      reach = Math.max(reach, (d.thigh * Math.cos(P.thFwd[i]) + d.shin * Math.cos(P.thFwd[i] - P.knee[i])) * Math.cos(P.thOut[i]));
    }
    drop = Math.max(0, d.thigh + d.shin - reach);
  }
  if (!poseOk(P) || !Number.isFinite(drop) || !Number.isFinite(spin)) {
    // 그래도 깨졌으면 이번 프레임은 기본 자세로 (다음 프레임은 깨끗한 자세부터)
    fig.pose = restPose(d);
    Object.assign(sw, { x: 0, y: 0, vx: 0, vy: 0 });
    if (!retry) return figureAnim(fig, { ...st, act: null, hit: null, walking: false, air: false }, 0, true);
    return;
  }
  fig.hips.position.z = d.foot + d.shin + d.thigh + P.hipsZ - drop;
  fig.waist.rotation.y = P.waistPitch + sw.x;
  fig.waist.rotation.x = -(P.waistSide + sw.y);
  fig.waist.rotation.z = P.waistRoll;
  fig.neck.rotation.y = P.neckPitch - sw.x * 0.5; // 머리는 늦게 따라옴
  fig.neck.rotation.x = sw.y * 0.5;
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
  // 천 자락: 빨리 움직이거나 날아가면 뒤로 날리고 살랑임 (히트스톱 동안은 멈춤)
  if (frozen) return;
  const sp = st.stunned ? 1 : st.walking || st.air ? Math.min(1, st.hs / C.MOVE_SPEED) : 0;
  fig.flaps.forEach((f, i) => {
    f.obj.rotation.y = f.base + sp * f.lift + Math.sin(t * 9 + i * 1.7) * f.flutter * (0.3 + sp);
  });
}
