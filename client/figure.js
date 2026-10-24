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

const flat = (color) => toon({ color, flatShading: true });

// 체형 (칸). foot 발 두께, shin·thigh 다리 마디, torso 몸통 높이, chestR·waistR 가슴·허리 반지름, depth 앞뒤 납작함,
// barrel 이면 몸통이 둥근 통, head·headW 머리 높이·폭, sink 머리가 어깨에 묻히는 깊이, upper·lower 팔 마디, armR·foreR 팔 굵기,
// legR 다리 굵기, hand 손 크기, shoulderY 어깨 관절 옆 거리, hipY 다리 사이, hunch 구부정한 각, spread 팔 벌린 각
const BODIES = {
  // 보통 마네킹
  lean: { foot: 0.06, shin: 0.36, thigh: 0.36, torso: 0.48, chestR: 0.15, waistR: 0.12, depth: 0.72, head: 0.28, headW: 0.17, sink: -0.05, upper: 0.3, lower: 0.27, armR: 0.045, foreR: 0.04, legR: 0.065, hand: 0.048, shoulderY: 0.18, hipY: 0.075, hunch: 0, spread: 0.22 },
  // 거대 상체: 어깨·가슴이 아주 크고 팔이 굵고 김, 다리는 짧고 굵음, 목 없음, 머리 작음
  brute: { foot: 0.07, shin: 0.27, thigh: 0.27, torso: 0.7, chestR: 0.27, waistR: 0.15, depth: 0.74, head: 0.25, headW: 0.17, sink: 0.07, upper: 0.36, lower: 0.36, armR: 0.085, foreR: 0.095, legR: 0.09, hand: 0.075, shoulderY: 0.31, hipY: 0.1, hunch: 0.14, spread: 0.32 },
  // 드럼통: 둥근 통 몸통, 팔다리 짧고 뭉툭
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

  const skin = flat(color); // 몸 = 플레이어 색 (render.js 가 매 프레임 칠함)
  const mats = [skin];
  const costume = (c) => {
    const m = flat(c);
    mats.push(m);
    return m;
  };

  // 엉덩이 → 허리(몸통) → 목(머리)
  const hipZ = d.foot + d.shin + d.thigh;
  const hips = joint(parts, 0, 0, hipZ);
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

  const fig = { d, hips, waist, neck, shoulders, elbows, hands, thighs, knees, feet, pose: null };
  dressUp(char, fig, costume, skin);

  // 망치는 오른손: 손잡이를 쥐고 머리가 주먹 앞쪽으로 (모델은 손잡이가 z 축, 머리가 +z 끝)
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
function addEyes(neck, x, y, z, r) {
  for (const side of [-1, 1]) {
    const white = mesh(new THREE.SphereGeometry(r, 12, 8), eyeWhiteMat, x, side * y, z);
    white.castShadow = false;
    neck.add(white);
    const pupil = mesh(new THREE.SphereGeometry(r * 0.45, 10, 6), pupilMat, r * 0.88, 0, 0);
    pupil.castShadow = false;
    white.add(pupil);
  }
}

// 옷·소품 (캐릭터마다 고정 색). 지금은 탱크만 (시안). 탱크 외엔 맨몸 + 눈
// 갑옷이 피부를 거의 덮어서 천 부분(겉옷·볏·방패 판·배 띠 한 겹·윗팔 소매)은 피부 재질 = 플레이어(팀) 색
function dressUp(char, fig, costume, cloth) {
  const d = fig.d;
  if (char !== 'tank') {
    addEyes(fig.neck, d.headW * 0.42, 0.045, d.head * 0.56, 0.05);
    return;
  }
  const steel = costume(0xa3adb8);
  const dark = costume(0x5d6672);
  const leather = costume(0x6a4428);
  const gold = costume(0xd8a838);
  const barrel = !!d.barrel;

  // ---- 투구 ----
  if (barrel) {
    // 원뿔 투구 + 이마 띠 + 눈 사이로 내려오는 코 가드 (노르만 식)
    const r = d.headW * 0.62;
    const browZ = d.head * 0.66;
    fig.neck.add(mesh(ringGeo(r, r, d.head * 0.38, 8), steel, 0, 0, browZ + d.head * 0.17)); // 뒤통수·옆을 덮는 통
    const cone = new THREE.ConeGeometry(r * 1.02, d.head * 0.55, 8);
    cone.rotateX(Math.PI / 2);
    fig.neck.add(mesh(cone, steel, 0, 0, browZ + d.head * 0.36 + d.head * 0.27));
    fig.neck.add(mesh(ringGeo(r * 1.06, r * 1.06, 0.045, 8), dark, 0, 0, browZ));
    fig.neck.add(mesh(new THREE.BoxGeometry(0.03, 0.032, d.head * 0.42), dark, r * 1.02, 0, browZ - d.head * 0.18)); // 코 가드
    fig.neck.add(mesh(new THREE.IcosahedronGeometry(0.04, 0), cloth, 0, 0, browZ + d.head * 0.66)); // 꼭대기 장식
    addEyes(fig.neck, r * 0.82, 0.062, browZ - d.head * 0.13, 0.05);
  } else {
    // 통투구: 얼굴 전체를 덮는 원통 + 눈 높이 가로 틈(왕눈알이 틈으로 튀어나옴) + 가운데 세로 보강대 + 숨구멍
    const r = d.headW * 0.68;
    const h = d.head * 1.05;
    const eyeZ = d.head * 0.6;
    fig.neck.add(mesh(ringGeo(r, r * 1.04, h, 8), steel, 0, 0, h / 2 - 0.01));
    fig.neck.add(mesh(ringGeo(r * 0.75, r, 0.05, 8), steel, 0, 0, h + 0.015)); // 윗면 경사
    fig.neck.add(mesh(new THREE.BoxGeometry(0.03, r * 1.7, 0.035), dark, r * 0.95, 0, eyeZ)); // 눈 틈
    fig.neck.add(mesh(new THREE.BoxGeometry(0.035, 0.035, h * 0.62), gold, r * 1.0, 0, eyeZ - h * 0.08)); // 세로 보강대 (눈 사이)
    fig.neck.add(mesh(ringGeo(r * 1.05, r * 1.05, 0.04, 8), dark, 0, 0, h * 0.9)); // 윗 테
    for (let i = 0; i < 3; i++) fig.neck.add(mesh(new THREE.BoxGeometry(0.02, 0.025, 0.012), dark, r * 0.96, -0.06 - i * 0.03, eyeZ - 0.08 - i * 0.012)); // 숨구멍
    fig.neck.add(mesh(new THREE.BoxGeometry(r * 2.1, 0.04, 0.1), cloth, -0.01, 0, h + 0.08)); // 볏 (앞뒤로 긴 판)
    addEyes(fig.neck, r * 0.98, 0.055, eyeZ, 0.052);
  }

  // ---- 몸통 갑옷: 가슴판(가운데 능선) + 배를 덮는 겹친 띠 + 목 칼라 + 허리띠·버클 + 파란 겉옷 + 허리 치마판 ----
  const cR = d.chestR * 1.08;
  const wR = d.waistR * 1.1;
  // 높이 z 에서 몸통 앞면까지 거리 (갑옷 조각을 표면에 붙이려고)
  const surf = (z, grow) => (barrel ? d.chestR * grow * Math.sqrt(Math.max(0, 1 - ((z - d.torso / 2) / (d.torso / 2)) ** 2)) : (wR + (cR - wR) * (z / d.torso)) * grow);
  if (barrel) {
    const geo = new THREE.IcosahedronGeometry(1, 1);
    geo.scale(cR * d.depth, cR, d.torso * 0.5 * 0.62);
    fig.waist.add(mesh(geo, steel, 0, 0, d.torso * 0.66)); // 가슴판 (윗부분)
  } else {
    fig.waist.add(mesh(ringGeo(cR, wR * 1.15, d.torso * 0.55, 8, d.depth), steel, 0, 0, d.torso * 0.7));
  }
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
  const beltR = barrel ? d.chestR * 0.82 : wR * 1.08;
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
}

// ---------- 동작 ----------
// 관절마다 목표 각도를 정하고 FIGURE_FOLLOW 빠르기로 따라감 → 살짝 늦게 따라와 흐느적거림 (TABS 느낌)
// 각도 이름: fwd = 앞으로 드는 각 (어깨·허벅지), out = 옆으로 벌리는 각 (어깨), bend = 굽힘 (팔꿈치 앞, 무릎 뒤)
function restPose(d) {
  return {
    waistPitch: d.hunch,
    waistRoll: 0,
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

// st: { air, walking, hs, walk(위상), stunned, dancing, emote, emoteT, punch(0~1), holding(왼손에 든 것 있음), t }
export function figureAnim(fig, st, dt) {
  const d = fig.d;
  const T = restPose(d);
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
    T.waistPitch = d.hunch + C.FIGURE_RUN_LEAN * amp;
    T.hipsZ = Math.abs(Math.sin(st.walk)) * 0.04 * amp;
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
    T.shFwd[0] = (Math.PI / 2) * st.punch;
    T.shOut[0] = 0.1;
    T.elbow[0] = 0.05;
    T.waistRoll = 0.25 * st.punch;
  }

  // 따라가기 (처음엔 바로 그 자세)
  const k = fig.pose ? 1 - Math.exp(-C.FIGURE_FOLLOW * dt) : 1;
  const P = fig.pose || (fig.pose = restPose(d));
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

  fig.hips.position.z = d.foot + d.shin + d.thigh + P.hipsZ;
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
