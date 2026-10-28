// TABS 식 캐릭터: 각진 저폴리 몸 + 왕눈알. 피부 = 플레이어(팀) 색, 옷·소품 = 캐릭터마다 고정 색.
// 모델 파일 없이 기본 도형으로 만들고, 관절(엉덩이·허리·목·어깨·팔꿈치·무릎)을 코드로 움직인다 (figureAnim).
// 로컬 좌표는 콩·로봇과 같다: 발바닥 z=0, 앞 +x, 왼쪽 +y. 키는 PLAYER_HEIGHT 안팎.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { heldItems } from '/character.js';
import { itemModel } from '/models.js';
import { gaitOf, gaitPose, airPose, accLean, idlePose, overlayT, SUPERMAN } from '/figure-pose.js';

// 눈알은 외곽선을 안 그림 (흰자 둘레에 검은 테가 생겨 부자연스러움)
const eyeWhiteMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff }));
const pupilMat = noOutline(new THREE.MeshBasicMaterial({ color: 0x111111 }));

const flat = (color) => toon({ color }); // (MeshToonMaterial 엔 flatShading 이 없음. 각진 느낌은 저폴리 도형으로)
const _white = new THREE.Color(0xffffff);

const BODIES = C.FIGURE_BODIES; // 체형 표는 shared/config.js (테스트 test/figure.test.js)

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

// 골반 (엉덩이 관절 기준 가운데가 원점): 몸통 아래(허리 반지름·앞뒤 납작함, 같은 8각)에 맞춘 둥근 통, 아래가 조금 넓음 (엉덩이).
// 상자였을 땐 몸통 8각 통보다 앞뒤가 얇아 허리를 숙이거나 비틀면 몸통 바닥 모서리가 삐져나와 윗몸이 따로 얹힌 것처럼 보였음.
// grow = 옷(바지) 두께 배율, h = 높이
function pelvisGeo(d, grow = 1, h = 0.14) {
  const geo = new THREE.CylinderGeometry(1, 1.08, h, 8);
  geo.rotateX(Math.PI / 2);
  geo.scale(d.waistR * (d.depth || 0.75) * grow, Math.max(d.waistR, d.hipY + d.legR) * grow, 1);
  return geo;
}

// 체크 무늬 천 텍스처 (작업 셔츠): colors = [바탕, 굵은 줄, 가는 줄]. 같은 무늬는 한 번만 만듦
const _plaid = new Map();
function plaidTexture(colors) {
  const key = colors.join(',');
  if (_plaid.has(key)) return _plaid.get(key);
  const n = 32;
  const cv = document.createElement('canvas');
  cv.width = cv.height = n;
  const g = cv.getContext('2d');
  const hex = (c) => '#' + c.toString(16).padStart(6, '0');
  g.fillStyle = hex(colors[0]);
  g.fillRect(0, 0, n, n);
  g.globalAlpha = 0.55;
  g.fillStyle = hex(colors[1]);
  g.fillRect(0, 10, n, 6);
  g.fillRect(10, 0, 6, n);
  g.globalAlpha = 0.9;
  g.fillStyle = hex(colors[2]);
  g.fillRect(0, 26, n, 2);
  g.fillRect(26, 0, 2, n);
  const tex = new THREE.CanvasTexture(cv);
  tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  tex.repeat.set(C.FIGURE_PLAID_REPEAT, C.FIGURE_PLAID_REPEAT);
  tex.magFilter = THREE.NearestFilter;
  tex.colorSpace = THREE.SRGBColorSpace;
  _plaid.set(key, tex);
  return tex;
}

// 굴곡 있는 팔다리 (근육선): profile = [[t, r], ...] (t 0 = 위 끝 ~ 1 = 아래 끝, r 반지름). 관절에서 -z 로 len, 매끈하게 한 덩어리.
// top 을 주면 위 끝을 그만큼 위로 둥글게 덮음 (어깨처럼 공을 따로 안 붙여도 됨)
function latheLimb(len, profile, seg = 10, top = 0) {
  const pts = [];
  if (top > 0) for (let k = 0; k <= 3; k++) pts.push(new THREE.Vector2(profile[0][1] * Math.sin((k / 3) * Math.PI * 0.5), top * Math.cos((k / 3) * Math.PI * 0.5)));
  for (const [t, r] of profile) pts.push(new THREE.Vector2(r, -t * len));
  const geo = new THREE.LatheGeometry(pts.reverse(), seg); // 아래 → 위 순서라야 면이 바깥을 봄
  geo.rotateX(Math.PI / 2); // 축 y → z (위 끝이 원점, 아래로 -z)
  return geo;
}

// 저폴리 덩어리 (근육·배·털 뭉치): 정이십면체를 sx·sy·sz 로 늘려 parent 에 붙임. detail 1 이면 더 둥긂
function lump(parent, sx, sy, sz, mat, x, y, z, rx = 0, ry = 0, detail = 0) {
  const g = new THREE.IcosahedronGeometry(1, detail);
  g.scale(sx, sy, sz);
  const m = mesh(g, mat, x, y, z);
  m.rotation.set(rx, ry, 0);
  parent.add(m);
  return m;
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
  hips.add(mesh(pelvisGeo(d), skin, 0, 0, 0.02));
  const waist = joint(hips, 0, 0, 0.04);
  waist.add(mesh(ringGeo(d.waistR * 0.97, d.waistR * 0.9, 0.09, 8, d.depth), skin, 0, 0, -0.035)); // 허리 아래 마개: 숙이거나 비틀어도 골반과 사이가 안 뜸
  let torso;
  if (d.barrel) {
    const geo = new THREE.IcosahedronGeometry(1, 1);
    geo.scale(d.chestR * d.depth, d.chestR, d.torso / 2);
    torso = mesh(geo, skin, 0, 0, d.torso / 2);
  } else {
    torso = mesh(ringGeo(d.chestR, d.waistR, d.torso, 8, d.depth), skin, 0, 0, d.torso / 2);
  }
  waist.add(torso);
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

  const fig = { d, char, hips, waist, torso, neck, shoulders, elbows, hands, thighs, knees, feet, flaps: [], pose: null };
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
// sides: 그릴 눈 (-1 오른쪽, 1 왼쪽). 안대 찬 해적은 [1]. whiteMat: 흰자 재질 (광전사는 분노로 충혈되게 따로)
function addEyes(neck, x, y, z, r, sides = [-1, 1], whiteMat = eyeWhiteMat) {
  const pupils = [];
  for (const side of sides) {
    const white = mesh(new THREE.SphereGeometry(r, 12, 8), whiteMat, x, side * y, z);
    white.castShadow = false;
    neck.add(white);
    const pupil = mesh(new THREE.SphereGeometry(r * 0.45, 10, 6), pupilMat, r * 0.88, 0, 0);
    pupil.castShadow = false;
    white.add(pupil);
    pupils.push(pupil);
  }
  return pupils; // 어지러울 때 빙글 돌리려고 (광전사)
}

// 옷·소품 (캐릭터마다 고정 색). cloth = 피부 재질 (플레이어·팀 색): 옷 사이로 보이게 하거나 천 부분에 씀
function dressUp(char, fig, costume, cloth) {
  const dress = { tank: dressTank, ninja: dressNinja, builder: dressBuilder, hook: dressHook, hunter: dressHunter, cannon: dressCannon, berserker: dressBerserker, bard: dressBard }[char];
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

// 닌자 (재빠른 그림자): 가늘고 날렵한 몸 + 두건(눈 둘레만 피부 띠) + 검은 도복 (닫힌 몸통, 겹친 깃) + 헐렁한 바지 (발목 붕대로 조임)
// + 팔뚝·정강이 붕대 + 등에 칼. 플레이어 색 큰 면 = 길게 날리는 목도리 + 허리띠(오비) + 머리띠 (2026-10-28)
function dressNinja(fig, costume, cloth) {
  const d = fig.d;
  const T = d.torso;
  const black = costume(0x26262e);
  const charcoal = costume(0x3c3c46);
  const wrap = costume(0xd8d2c4);
  const steel = costume(0xa3adb8);
  const gold = costume(0xd8a838);
  const eyeZ = d.head * 0.58;
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T;
  // 두건: 머리보다 조금 큰 둥근 공 + 눈 높이에 피부 띠 (그 사이로 왕눈알) + 플레이어 색 머리띠·끝 둘
  const hood = new THREE.IcosahedronGeometry(0.5, 2);
  hood.scale(d.headW * 1.12, d.headW * 1.1, d.head * 1.08);
  fig.neck.add(mesh(hood, black, 0, 0, d.head / 2 + 0.005));
  fig.neck.add(mesh(ringGeo(d.headW * 0.57, d.headW * 0.57, 0.07, 12), cloth, 0, 0, eyeZ));
  fig.neck.add(mesh(ringGeo(d.headW * 0.59, d.headW * 0.59, 0.035, 12), cloth, 0, 0, eyeZ + 0.07)); // 머리띠
  for (const side of [-1, 1]) flap(fig, fig.neck, new THREE.BoxGeometry(0.012, 0.04, 0.26), cloth, -d.headW * 0.55, side * 0.025, eyeZ + 0.07, 0.6, 0.8, 0.25);
  addEyes(fig.neck, d.headW * 0.6, 0.05, eyeZ, C.FIGURE_EYE);
  // 도복: 몸통 = 검정 (몸통 재질) + 왼쪽 위로 겹친 깃 (짙은 회색 띠) + 허리 아래 짧은 자락
  fig.torso.material = black;
  for (const side of [-1, 1]) {
    const lapel = mesh(new THREE.BoxGeometry(0.012, 0.035, T * 0.6), charcoal, rz(T * 0.65) * d.depth * 0.95, side * 0.03, T * 0.68);
    lapel.rotation.x = side * 0.55;
    fig.waist.add(lapel);
  }
  fig.waist.add(mesh(ringGeo(d.waistR * 1.12, d.waistR * 1.4, 0.1, 10, d.depth), black, 0, 0, -0.02)); // 자락 (골반 위끝을 덮음)
  // 목도리 (플레이어 색): 목 둘레 고리 + 등 뒤로 길게 날리는 두 자락
  fig.waist.add(mesh(new THREE.TorusGeometry(d.headW * 0.5, 0.06, 6, 12).scale(d.depth * 1.1, 1, 0.9), cloth, 0, 0, T + 0.01));
  for (const side of [-1, 1]) flap(fig, fig.waist, new THREE.BoxGeometry(0.015, 0.1, C.NINJA_SCARF_LEN), cloth, -rz(T) * 0.6, side * 0.055, T - 0.02, 0.25, 1.05, 0.2);
  // 허리띠 (오비, 플레이어 색) + 뒤 매듭 자락
  fig.waist.add(mesh(ringGeo(d.waistR * 1.18, d.waistR * 1.18, 0.08, 10, d.depth), cloth, 0, 0, 0.06));
  for (const side of [-1, 1]) flap(fig, fig.waist, new THREE.BoxGeometry(0.012, 0.045, 0.17), cloth, -d.waistR * d.depth * 1.1, side * 0.03, 0.05, 0.3, 0.6, 0.2);
  // 팔: 어깨부터 매끈한 검은 소매 → 팔꿈치 아래 붕대 감은 팔뚝 (띠 여러 줄). 다리: 헐렁한 바지 (허벅지·무릎이 부풀고 정강이에서 좁아짐) → 붕대로 조인 발목 + 둥근 버선 신발
  const A = d.armR;
  const sleeve = latheLimb(d.upper, [[0, A * 1.45], [0.5, A * 1.55], [1, A * 1.35]], 10, A * 1.1);
  const fore = latheLimb(d.lower, [[0, A * 1.3], [0.3, A * 1.3], [1, d.foreR * 1.05]], 10, A * 1.0);
  const L = d.legR;
  const thigh = latheLimb(d.thigh, [[0, L * 1.55], [0.5, L * 1.75], [1, L * 1.6]], 10, L * 0.9);
  const shin = latheLimb(d.shin * 0.55, [[0, L * 1.6], [0.4, L * 1.55], [1, L * 1.05]], 10, L * 1.0);
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(sleeve, black));
    fig.elbows[i].add(mesh(new THREE.IcosahedronGeometry(A * 1.35, 1), black));
    fig.elbows[i].add(mesh(fore, black));
    for (let k = 0; k < 4; k++) {
      const band = mesh(ringGeo(d.foreR * 1.25 + (3 - k) * 0.002, d.foreR * 1.2 + (3 - k) * 0.002, 0.02, 10), wrap, 0, 0, -d.lower * (0.45 + k * 0.13));
      band.rotation.y = (k % 2 ? 1 : -1) * 0.12; // 비스듬히 감김
      fig.elbows[i].add(band);
    }
    fig.thighs[i].add(mesh(thigh, black));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(L * 1.6, 1), black));
    fig.knees[i].add(mesh(shin, black));
    for (let k = 0; k < 4; k++) {
      const band = mesh(ringGeo(L * 1.15, L * 1.1, 0.022, 10), wrap, 0, 0, -d.shin * (0.58 + k * 0.11));
      band.rotation.y = (k % 2 ? 1 : -1) * 0.12;
      fig.knees[i].add(band);
    }
    fig.feet[i].children[0].visible = false;
    lump(fig.feet[i], L * 1.7, L * 1.05, d.foot * 0.95, black, L * 0.6, 0, -d.foot * 0.45, 0, 0, 1);
  }
  fig.hips.add(mesh(pelvisGeo(d, 1.2, 0.18), black, 0, 0, 0));
  // 등에 칼: 비스듬한 칼집 + 금색 코등이 + 손잡이 (오른 어깨 위로 손잡이)
  const sword = new THREE.Group();
  sword.add(mesh(new THREE.BoxGeometry(0.035, 0.05, 0.62), black, 0, 0, -0.1));
  sword.add(mesh(ringGeo(0.05, 0.05, 0.015, 8), gold, 0, 0, 0.22));
  sword.add(mesh(new THREE.BoxGeometry(0.03, 0.03, 0.16), steel, 0, 0, 0.31));
  sword.position.set(-rz(T * 0.55) * d.depth - 0.04, 0, T * 0.55);
  sword.rotation.x = 0.7; // 손잡이가 오른 어깨 쪽(-y)으로
  fig.waist.add(sword);
  // 두 손에 단검: 주먹 끝에서 팔이 뻗는 쪽(-z)으로 짧은 날 + 검은 손잡이 → 찌르면 날이 앞으로
  for (const hand of fig.hands) {
    const grip = mesh(new THREE.BoxGeometry(0.022, 0.05, 0.05), black, 0, 0, -d.hand * 0.6);
    const blade = new THREE.ConeGeometry(0.028, 0.2, 4);
    blade.rotateX(-Math.PI / 2); // 끝이 -z
    blade.scale(1, 0.35, 1); // 납작한 날
    const edge = mesh(blade, steel, 0, 0, -d.hand * 0.6 - 0.12);
    grip.userData.dagger = edge.userData.dagger = true; // 1인칭은 왼손 단검 대신 표창 (viewmodel.js)
    hand.add(grip, edge);
  }
}

// 건축가: 다부진 보통 몸 + 노란 안전모 + 주황 작업 조끼(반사 띠, 앞이 열려 셔츠(피부)가 보임) + 공구 벨트 + 장갑·작업화 + 등에 테트리미노 가방
function dressBuilder(fig, costume, cloth) {
  const d = fig.d;
  const T = d.torso;
  const orange = costume(0xff7a1a);
  const darkOrange = costume(0xc85a10);
  const reflect = costume(0xe6edf2);
  const brown = costume(0x6a4428);
  const tan = costume(0xc9a06a);
  const steel = costume(0xa3adb8);
  const gold = costume(0xe0b030);
  const stache = costume(0x4a2c18);
  const piece = costume(0x30c8e8); // 테트리미노 (하늘색: 작업복 주황·모자 노랑과 안 겹침)
  const cream = costume(C.FIGURE_BUILDER_SHIRT[1]);
  // 작업 셔츠 (체크 무늬 천): 피부(플레이어 색)와 어떤 팔레트·팀 색에서도 갈리게 무늬로. 몸통 맨살 통도 셔츠로 덮음
  const shirt = costume(0xffffff);
  shirt.map = plaidTexture(C.FIGURE_BUILDER_SHIRT);
  fig.torso.material = shirt;
  // 안전모 (플레이어 색: 건축가끼리 멀리서 갈리게, 2026-10-28 재혁): 돔 + 앞으로 긴 챙 + 가운데 능선·챙 테는 대비 색 (어두운 모자면 밝게, figureAnim 이 칠함)
  const trim = costume(0x000000);
  fig.shade = { mat: trim, src: cloth, k: C.FIGURE_HAT_TRIM, contrast: true };
  const browZ = d.head * 0.7;
  const hat = mesh(domeGeo(d.headW * 0.66), cloth, 0, 0, browZ);
  hat.scale.z = 0.85;
  fig.neck.add(hat);
  const brim = mesh(ringGeo(d.headW * 0.72, d.headW * 0.72, 0.025, 10), cloth, 0.025, 0, browZ);
  brim.scale.x = 1.25;
  fig.neck.add(brim);
  const brimEdge = mesh(ringGeo(d.headW * 0.74, d.headW * 0.74, 0.012, 10), trim, 0.025, 0, browZ - 0.008);
  brimEdge.scale.x = 1.25;
  fig.neck.add(brimEdge);
  fig.neck.add(mesh(ringGeo(0.016, 0.016, d.headW * 1.25, 6).rotateY(Math.PI / 2), trim, 0, 0, browZ + d.headW * 0.58));
  fig.neck.add(mesh(ringGeo(d.headW * 0.67, d.headW * 0.67, 0.02, 10), trim, 0, 0, browZ + 0.012)); // 모자 띠
  addEyes(fig.neck, d.headW * 0.44, 0.05, d.head * 0.5, C.FIGURE_EYE);
  fig.waist.add(mesh(ringGeo(d.headW * 0.6, d.headW * 0.78, 0.06, 10), cream, 0, 0, T - d.sink + 0.01)); // 셔츠 깃
  // 덥수룩한 콧수염 (양쪽으로 처짐) + 둥근 코
  for (const side of [-1, 1]) lump(fig.neck, 0.035, 0.06, 0.03, stache, d.headW * 0.47, side * 0.045, d.head * 0.3, side * 0.35, 0, 1);
  lump(fig.neck, 0.035, 0.035, 0.035, cloth, d.headW * 0.52, 0, d.head * 0.38, 0, 0, 1);
  // 작업복 멜빵바지 (주황 + 반사 띠): 둥근 배 통 + 가슴판 + 멜빵 + 금 단추. 골반 쪽 바지 위끝을 배 통이 덮음 (이음매 안 보임)
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T;
  fig.waist.add(mesh(ringGeo(rz(T * 0.5) * 1.07, d.waistR * 1.1, T * 0.56, 10, d.depth), orange, 0, 0, T * 0.22));
  lump(fig.waist, d.waistR * d.depth * 1.08, d.waistR * 1.02, T * 0.27, orange, 0.03, 0, T * 0.26, 0, 0, 1); // 배 (살짝 나옴)
  fig.waist.add(mesh(ringGeo(rz(T * 0.36) * 1.12, rz(T * 0.36) * 1.12, 0.035, 10, d.depth), reflect, 0, 0, T * 0.36)); // 반사 띠
  const bibX = rz(T * 0.66) * d.depth * 0.93;
  lump(fig.waist, 0.03, d.chestR * 0.62, T * 0.2, orange, bibX, 0, T * 0.64, 0, 0.08, 1); // 가슴판
  // 가슴 주머니: 가슴판 위에 살짝 튀어나온 납작한 천 조각 (같은 주황) + 위쪽 덮개 선 (어두운 주황)
  const pocket = mesh(new THREE.BoxGeometry(0.012, d.chestR * 0.5, T * 0.13), orange, bibX + 0.03, 0, T * 0.6);
  pocket.rotation.y = 0.08;
  fig.waist.add(pocket);
  const flap = mesh(new THREE.BoxGeometry(0.016, d.chestR * 0.54, 0.014), darkOrange, bibX + 0.034, 0, T * 0.66);
  flap.rotation.y = 0.08;
  fig.waist.add(flap);
  for (const side of [-1, 1]) {
    // 멜빵: 가슴판 위끝 → 어깨 위로 넘어 → 등으로 X
    const front = mesh(ringGeo(0.018, 0.018, T * 0.36, 6), orange, bibX - 0.01, side * d.chestR * 0.42, T * 0.86);
    front.scale.y = 1.8;
    front.rotation.y = -0.35;
    fig.waist.add(front);
    const over = mesh(ringGeo(0.018, 0.018, rz(T) * d.depth * 1.9, 6).rotateY(Math.PI / 2), orange, -0.01, side * d.chestR * 0.45, T + 0.005);
    over.scale.y = 1.8;
    fig.waist.add(over);
    const back = mesh(ringGeo(0.018, 0.018, T * 0.62, 6), orange, -rz(T * 0.7) * d.depth * 0.95, side * d.chestR * 0.2, T * 0.7);
    back.scale.y = 1.8;
    back.rotation.x = side * 0.45;
    fig.waist.add(back);
    const btn = new THREE.CylinderGeometry(0.022, 0.022, 0.014, 8);
    btn.rotateZ(Math.PI / 2);
    fig.waist.add(mesh(btn, gold, bibX + 0.03, side * d.chestR * 0.42, T * 0.72));
  }
  fig.hips.add(mesh(pelvisGeo(d, 1.12, 0.2), orange, 0, 0, 0));
  // 공구 벨트 (배 아래) + 주머니 + 옆에 매단 작은 망치
  fig.waist.add(mesh(ringGeo(d.waistR * 1.16, d.waistR * 1.16, 0.06, 10, d.depth), brown, 0, 0, 0.03));
  for (const ang of [0.9, -0.9, 2.3]) lump(fig.waist, 0.04, 0.05, 0.055, tan, Math.cos(ang) * d.waistR * 1.18 * d.depth, Math.sin(ang) * d.waistR * 1.18, -0.01, 0, 0, 1);
  const tool = new THREE.Group();
  tool.add(mesh(ringGeo(0.013, 0.013, 0.16, 6), brown, 0, 0, -0.06));
  tool.add(mesh(ringGeo(0.022, 0.022, 0.07, 6).rotateY(Math.PI / 2), steel, 0, 0, 0.03));
  tool.position.set(0, -d.waistR * 1.22, -0.01);
  fig.waist.add(tool);
  // 팔: 어깨부터 매끈한 셔츠 소매 (둥근 어깨 + 위팔) → 팔꿈치에 걷어 올린 소매 테 → 맨살 팔뚝이 손목 쪽으로 굵어짐 (뽀빠이) → 장갑.
  // 소매 테가 팔꿈치 관절을 감싸 굽혀도 이음이 안 벌어짐. 다리: 작업복 바지 + 접은 단 + 둥근 작업화
  const rU = d.armR * 1.3;
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(domeGeo(rU, 10), shirt, 0, 0, d.armR * 0.35)); // 어깨 둥근 끝 (소매와 같은 굵기·천)
    fig.shoulders[i].add(mesh(limbGeo(d.upper + d.armR * 0.35, rU, rU * 0.95, 10), shirt, 0, 0, d.armR * 0.35));
    fig.elbows[i].add(mesh(ringGeo(rU * 1.12, rU * 1.12, d.armR * 1.1, 10), cream, 0, 0, -d.armR * 0.15)); // 걷은 소매 테
    fig.elbows[i].add(mesh(limbGeo(d.lower + d.foreR * 0.4, d.foreR * 1.0, d.foreR * 1.3, 10), cloth, 0, 0, d.foreR * 0.4)); // 팔뚝 (손목 쪽이 굵음)
    fig.hands[i].add(mesh(ringGeo(d.foreR * 1.35, d.foreR * 1.4, 0.035, 10), tan, 0, 0, d.hand * 0.6)); // 장갑 목
    fig.hands[i].add(mesh(new THREE.IcosahedronGeometry(d.hand * 1.4, 1), tan));
    fig.thighs[i].add(mesh(limbGeo(d.thigh * 1.04, d.legR * 1.25, d.legR * 1.15, 8), orange));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(d.legR * 1.18, 1), orange));
    fig.knees[i].add(mesh(limbGeo(d.shin, d.legR * 1.12, d.legR * 1.22, 8), orange));
    fig.knees[i].add(mesh(ringGeo(d.legR * 1.3, d.legR * 1.3, 0.045, 8), darkOrange, 0, 0, -d.shin * 0.82)); // 접은 단
    fig.feet[i].children[0].visible = false; // 맨발 상자 대신
    lump(fig.feet[i], d.legR * 1.75, d.legR * 1.05, d.foot * 1.0, brown, d.legR * 0.6, 0, -d.foot * 0.4, 0, 0, 1); // 둥근 작업화
  }
  // 등: 테트리미노 T (작은 상자 4개, 블록이라 각진 게 맞음)
  const c = 0.13;
  const backX = -rz(T * 0.68) * d.depth - c / 2 - 0.01;
  for (const [y, z] of [[-c, 0], [0, 0], [c, 0], [0, -c]]) fig.waist.add(mesh(new THREE.BoxGeometry(c * 0.94, c * 0.94, c * 0.94), piece, backX, y, T * 0.68 + z));
}

// 갈고리: 덩치 큰 해적 선장 (위가 크고 아래가 가는 몸, 긴 팔) + 삼각모 + 안대 (눈알 하나) + 수염 + 앞이 열린 긴 코트 (자락 안감 플레이어 색) + 플레이어 색 조끼·장식띠·끝동 + 밧줄 + 왼손 갈고리 + 큰 장화
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
  // 덩치 큰 선장 옷. 플레이어 색 큰 면 = 몸통 조끼 (몸통 재질 그대로 = 피부색, 금단추·흰 목장식으로 옷으로 읽힘) + 허리 장식띠 + 소매 끝동 + 코트 자락 안감
  const T = d.torso;
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T;
  const white = costume(0xf0ece0);
  const breech = costume(0xb89a6a);
  for (let k = 0; k < 4; k++) {
    const z = T * (0.18 + k * 0.17);
    fig.waist.add(mesh(new THREE.CylinderGeometry(0.018, 0.018, 0.012, 8).rotateZ(Math.PI / 2), gold, rz(z) * d.depth + 0.004, 0, z)); // 조끼 금단추
  }
  for (let k = 0; k < 3; k++) lump(fig.waist, 0.03, 0.05 - k * 0.008, 0.03, white, rz(T) * d.depth * 0.9 + 0.01, 0, T * (0.9 - k * 0.07), 0, 0, 1); // 흰 목장식 (주름)
  // 코트: 앞이 열린 상체 통 + 세운 큰 깃 (금 테) + 허리부터 무릎까지 퍼지는 자락 (겉 갈색 · 안감 플레이어 색, 앞이 트여 다리가 안 걸림)
  const open = 1.1;
  const coatGeo = new THREE.CylinderGeometry(rz(T) * 1.08, d.waistR * 1.12, T * 0.95, 12, 1, true, Math.PI / 2 + open / 2, Math.PI * 2 - open);
  coatGeo.rotateX(Math.PI / 2);
  coatGeo.scale(d.depth, 1, 1);
  const cm = mesh(coatGeo, coat, 0, 0, T * 0.5);
  cm.material.side = THREE.DoubleSide;
  fig.waist.add(cm);
  const collar = new THREE.CylinderGeometry(rz(T) * 1.0, rz(T) * 0.88, 0.08, 12, 1, true, Math.PI / 2 + 0.9, Math.PI * 2 - 1.8);
  collar.rotateX(Math.PI / 2);
  collar.scale(d.depth, 1, 1);
  const colM = mesh(collar, coat, -0.01, 0, T + 0.02);
  colM.material.side = THREE.DoubleSide;
  fig.waist.add(colM);
  fig.waist.add(mesh(new THREE.TorusGeometry(rz(T) * 1.0, 0.01, 4, 16, Math.PI * 2 - 1.8).rotateZ(0.9).scale(d.depth, 1, 1), gold, -0.01, 0, T + 0.06));
  const skirtLen = C.HOOK_COAT_LEN;
  const skirt = (r0, r1, flip) => {
    const g = new THREE.CylinderGeometry(r0, r1, skirtLen, 12, 1, true, Math.PI / 2 + open / 2, Math.PI * 2 - open);
    g.rotateX(Math.PI / 2);
    g.scale(d.depth, flip ? -1 : 1, 1); // 안감은 y 를 뒤집어 면이 안쪽을 봄 (좌우 대칭이라 모양은 같음)
    g.translate(0, 0, -skirtLen / 2);
    return g;
  };
  const sk = joint(fig.waist, 0, 0, 0.03);
  sk.add(mesh(skirt(d.waistR * 1.14, d.waistR * 2.1, false), coat));
  sk.add(mesh(skirt(d.waistR * 1.11, d.waistR * 2.06, true), cloth));
  sk.add(mesh(new THREE.TorusGeometry(d.waistR * 2.1, 0.012, 4, 16, Math.PI * 2 - open).rotateZ(open / 2).scale(d.depth, 1, 1), gold, 0, 0, -skirtLen));
  fig.flaps.push({ obj: sk, base: 0, lift: 0.3, flutter: 0.05 });
  // 허리: 넓은 검정 허리띠·금 버클 + 그 위 플레이어 색 장식띠 (옆에 매듭, 늘어진 두 자락) + 밧줄 감은 것
  fig.waist.add(mesh(ringGeo(d.waistR * 1.16, d.waistR * 1.16, 0.08, 10, d.depth), cloth, 0, 0, 0.11)); // 장식띠
  fig.waist.add(mesh(ringGeo(d.waistR * 1.18, d.waistR * 1.18, 0.05, 10, d.depth), black, 0, 0, 0.04));
  fig.waist.add(mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.016, 4).rotateZ(Math.PI / 2).rotateX(Math.PI / 4), gold, d.waistR * 1.18 * d.depth + 0.008, 0, 0.04));
  lump(fig.waist, 0.035, 0.04, 0.035, cloth, d.waistR * 0.4 * d.depth, d.waistR * 1.15, 0.11, 0, 0, 1); // 매듭
  for (const dz of [0, 0.04]) flap(fig, fig.waist, new THREE.BoxGeometry(0.015, 0.035, 0.16), cloth, d.waistR * 0.4 * d.depth + dz * 0.5, d.waistR * 1.18, 0.09, 0.1 + dz * 3, 0.5, 0.15);
  const coil = new THREE.TorusGeometry(0.07, 0.022, 4, 10);
  coil.rotateX(Math.PI / 2);
  fig.waist.add(mesh(coil, rope, -0.02, -d.waistR * 1.3, 0.0));
  fig.waist.add(mesh(coil.clone(), rope, -0.02, -d.waistR * 1.3, 0.04));
  // 수염: 턱 끝 작은 염소수염 + 콧수염 (얼굴·입 쪽 피부가 보이게, 2026-10-28 재혁)
  lump(fig.neck, 0.035, d.headW * 0.2, d.head * 0.14, black, d.headW * 0.4, 0, d.head * 0.02, 0, 0.3, 1);
  for (const side of [-1, 1]) lump(fig.neck, 0.03, 0.05, 0.022, black, d.headW * 0.5, side * 0.04, d.head * 0.34, side * 0.4, 0, 1);
  // 팔: 어깨부터 매끈한 코트 소매 (굵고 긴 팔) → 플레이어 색 큰 끝동 (금 테). 다리: 가는 바지 + 큰 장화 (넓게 접은 윗단)
  const A = d.armR;
  const sleeve = latheLimb(d.upper, [[0, A * 1.3], [0.35, A * 1.38], [1, A * 1.15]], 10, A * 1.1);
  const fore = latheLimb(d.lower * 0.7, [[0, A * 1.15], [1, d.foreR * 1.3]], 10, A * 1.0);
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(sleeve, coat));
    fig.elbows[i].add(mesh(fore, coat));
    fig.elbows[i].add(mesh(latheLimb(0.1, [[0, d.foreR * 1.75], [1, d.foreR * 1.95]], 10), cloth, 0, 0, -d.lower * 0.55)); // 끝동
    fig.elbows[i].add(mesh(ringGeo(d.foreR * 1.98, d.foreR * 1.98, 0.012, 10), gold, 0, 0, -d.lower * 0.55 - 0.1));
  }
  const L = d.legR;
  for (let i = 0; i < 2; i++) {
    fig.thighs[i].add(mesh(latheLimb(d.thigh, [[0, L * 1.35], [0.5, L * 1.25], [1, L * 1.05]], 10, L * 0.8), breech));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(L * 1.05, 1), breech));
    fig.knees[i].add(mesh(latheLimb(d.shin, [[0, L * 1.55], [0.12, L * 1.45], [1, L * 1.25]], 10), black, 0, 0, 0.03)); // 장화
    fig.knees[i].add(mesh(ringGeo(L * 1.95, L * 1.6, 0.08, 10), black, 0, 0, 0.0)); // 넓게 접은 윗단
    fig.feet[i].children[0].visible = false;
    lump(fig.feet[i], L * 2.0, L * 1.25, d.foot * 1.0, black, L * 0.75, 0, -d.foot * 0.4, 0, 0, 1);
  }
  fig.hips.add(mesh(pelvisGeo(d, 1.1, 0.18), breech, 0, 0, 0));
  // 왼손 = 갈고리: 피부 손을 빼고 쇠 손목 + 굽은 갈고리
  const hand = fig.hands[1];
  hand.clear();
  hand.add(mesh(limbGeo(0.06, d.foreR * 1.1, d.foreR * 1.1, 8), steel, 0, 0, 0.03));
  const hook = new THREE.TorusGeometry(0.08, 0.02, 4, 10, Math.PI * 1.3);
  hook.rotateX(Math.PI / 2); // 갈고리가 앞뒤(x-z) 면에서 굽음
  fig.hands[1].add(mesh(hook, steel, 0.04, 0, -0.11));
  fig.hands[1].add(mesh(limbGeo(0.06, 0.02, 0.02, 4), steel, 0, 0, -0.03));
  // 플린트록 권총: 장전이면 오른손에 들고 앞으로 겨눈 채 (부싯돌 자리에 불꽃, render.js 가 켬), 빈 총이면 오른쪽 허리에 꽂힘 (총구에서 연기).
  // 탕 동작 동안은 늘 손에. 모양: 쇠 총열 + 놋쇠 나팔 총구 + 나무 몸통 + 아래로 휜 손잡이(놋쇠 뒤꽁무니) + 공이 (장전이면 젖혀짐)
  const wood = costume(0x6a3e22);
  const sparkMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffd040 }));
  const pistol = () => {
    const g = new THREE.Group(); // 총열이 -z, 손잡이가 +z 쪽 (손 기준: 팔이 뻗는 쪽으로 총열)
    g.add(mesh(limbGeo(0.28, 0.022, 0.024, 6), steel)); // 총열
    const flare = new THREE.CylinderGeometry(0.045, 0.028, 0.05, 8);
    flare.rotateX(Math.PI / 2);
    g.add(mesh(flare, gold, 0, 0, -0.27)); // 나팔 총구
    g.add(mesh(new THREE.BoxGeometry(0.05, 0.045, 0.14), wood, 0, 0, -0.02)); // 몸통
    const grip = mesh(new THREE.BoxGeometry(0.045, 0.04, 0.11), wood, 0.045, 0, 0.07);
    grip.rotation.y = -0.7; // 아래(+x 쪽 = 손바닥 쪽)로 휨
    g.add(grip);
    g.add(mesh(new THREE.IcosahedronGeometry(0.03, 0), gold, 0.08, 0, 0.11)); // 손잡이 끝 놋쇠
    const hammer = mesh(new THREE.BoxGeometry(0.02, 0.02, 0.06), black, -0.04, 0, 0.01); // 공이
    g.add(hammer);
    const spark = new THREE.Mesh(new THREE.IcosahedronGeometry(0.035, 0), sparkMat);
    spark.position.set(-0.05, 0, -0.03);
    spark.visible = false;
    g.add(spark);
    g.userData = { hammer, spark };
    return g;
  };
  const holster = pistol();
  holster.position.set(d.waistR * 0.3 * d.depth, -d.waistR * 1.25, 0.05);
  holster.rotation.y = -0.4; // 총열이 아래·조금 뒤로
  fig.waist.add(holster);
  const inHand = pistol();
  inHand.position.set(0, 0, -d.hand * 0.6);
  inHand.visible = false;
  fig.hands[0].add(inHand);
  fig.gun = { holster, inHand, spark: inHand.userData.spark, loaded: false };
}

// 사냥꾼: 확 숙인 몸(무릎도 굽힘) + 넓은 챙 사냥 모자 + 큰 코 + 무릎까지 오는 짙은 초록 망토 + 갈색 조끼·바지·장화 + 오른손 사냥칼 + 등에 석궁.
// 옷은 고정색, 플레이어(팀) 색은 셔츠(조끼 앞 틈·소매)·모자 띠·깃털 (갈고리가 코트 안 셔츠로 보이는 것과 같은 식)
// 석궁은 R 동작(bow) 동안만 손에 (figureAnim 이 켬). 가만히 있으면 킁킁 (fig.sniff)
function dressHunter(fig, costume, cloth) {
  const d = fig.d;
  const green = costume(0x2e4a26);
  const hatMat = costume(0x5a3c22);
  const leather = costume(0x7a4a26);
  const pants = costume(0x5e3d22);
  const dark = costume(0x33220f);
  const steel = costume(0xb8c2cc);
  const wood = costume(0x8a5a30);
  const eyeZ = d.head * 0.55;
  // 사냥 모자: 아주 넓은 챙 (앞이 내려옴) + 둥근 머리 + 플레이어 색 띠 + 띠에 꽂은 플레이어 색 깃털
  const browZ = d.head * 0.78;
  const brim = mesh(ringGeo(d.headW * 1.6, d.headW * 1.6, 0.03, 12), hatMat, 0.02, 0, browZ);
  brim.rotation.y = 0.14; // 앞이 내려옴
  fig.neck.add(brim);
  fig.neck.add(mesh(ringGeo(d.headW * 0.6, d.headW * 0.68, d.head * 0.4, 8), hatMat, 0, 0, browZ + d.head * 0.19));
  fig.neck.add(mesh(ringGeo(d.headW * 0.7, d.headW * 0.7, 0.045, 8), cloth, 0, 0, browZ + 0.04)); // 띠
  const plume = mesh(new THREE.BoxGeometry(0.02, 0.05, 0.3), cloth, -0.03, d.headW * 0.68, browZ + 0.14);
  plume.rotation.x = -0.45;
  plume.rotation.y = -0.7; // 뒤로 젖힘
  fig.neck.add(plume);
  addEyes(fig.neck, d.headW * 0.44, 0.048, eyeZ, C.FIGURE_EYE);
  // 큰 코 (킁킁): 앞으로 길게 튀어나온 각진 원뿔 + 콧망울
  const nose = new THREE.ConeGeometry(0.055, 0.16, 6);
  nose.rotateZ(-Math.PI / 2); // 끝이 앞(+x)
  fig.nose = mesh(nose, cloth, d.headW * 0.5 + 0.06, 0, eyeZ - 0.075);
  fig.neck.add(fig.nose);
  fig.neck.add(mesh(new THREE.IcosahedronGeometry(0.04, 0), cloth, d.headW * 0.5 + 0.13, 0, eyeZ - 0.085));
  // 웅크린 추적자 옷: 몸통 = 닫힌 가죽 저킨 (몸통 재질, 맨살 안 보임) + 앞 여밈 끈. 플레이어 색 큰 면 = 목도리 + 망토 안감 (앞·옆에서 보임)
  const T = d.torso;
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T;
  const fur = costume(0x8a7a66);
  fig.torso.material = leather;
  for (let k = 0; k < 4; k++) fig.waist.add(mesh(ringGeo(0.006, 0.006, 0.05, 4).rotateY(Math.PI / 2), dark, rz(T * (0.25 + k * 0.15)) * d.depth + 0.004, 0, T * (0.25 + k * 0.15))); // 여밈 끈
  fig.waist.add(mesh(ringGeo(d.waistR * 1.18, d.waistR * 1.18, 0.06, 10, d.depth), dark, 0, 0, 0.05));
  fig.waist.add(mesh(new THREE.CylinderGeometry(0.026, 0.026, 0.014, 8).rotateZ(Math.PI / 2), steel, d.waistR * 1.18 * d.depth + 0.007, 0, 0.05));
  fig.waist.add(mesh(ringGeo(d.waistR * 1.15, d.waistR * 1.45, 0.12, 10, d.depth), leather, 0, 0, -0.03)); // 저킨 자락 (골반 위끝을 덮음)
  // 칼집 (오른 허리) + 화살통 (왼 허리 뒤, 석궁 화살)
  const sheath = mesh(latheLimb(0.2, [[0, 0.028], [0.8, 0.024], [1, 0.012]], 6), dark, 0.02, -d.waistR * 1.3, 0.04);
  sheath.rotation.x = -0.25;
  fig.waist.add(sheath);
  const quiver = new THREE.Group();
  quiver.add(mesh(latheLimb(0.24, [[0, 0.045], [1, 0.04]], 8, 0), leather));
  quiver.add(mesh(ringGeo(0.048, 0.048, 0.02, 8), dark, 0, 0, -0.005));
  for (const [y, x] of [[-0.015, 0.01], [0.015, -0.01], [0, 0.02]]) quiver.add(mesh(ringGeo(0.006, 0.006, 0.08, 4), steel, x, y, 0.03));
  quiver.position.set(-d.waistR * 0.6 * d.depth, d.waistR * 1.25, 0.16);
  quiver.rotation.x = 0.35;
  quiver.rotation.y = 0.25;
  fig.waist.add(quiver);
  // 털 어깨 망토: 어깨를 덮는 털 덧댐 (덩어리 여럿이 겹친 둥근 깃) + 등 뒤 짧고 넓은 자락 (겉 초록 · 안감 플레이어 색, 엉덩이까지)
  for (let k = 0; k < 9; k++) {
    const ang = Math.PI * (0.5 + (k * 1.0) / 8);
    lump(fig.waist, 0.07, 0.075, 0.055, fur, Math.cos(ang) * rz(T) * d.depth * 1.05, Math.sin(ang) * rz(T) * 1.08, T - 0.015, 0.3 * k, 0.5 * k, 1);
  }
  for (const side of [-1, 1]) lump(fig.waist, 0.09, 0.08, 0.06, fur, 0.01, side * d.shoulderY, T + 0.005, side * 0.3, 0, 1);
  const capeLen = C.HUNTER_CAPE_LEN;
  const arc = (r0, r1, flip) => {
    const g = new THREE.CylinderGeometry(r0, r1, capeLen, 12, 1, true, Math.PI * 1.1, Math.PI * 0.8);
    g.rotateX(Math.PI / 2);
    g.scale(d.depth, flip ? -1 : 1, 1); // 안감은 y 를 뒤집어 면이 안쪽을 봄 (자락이 좌우 대칭이라 모양은 같음)
    g.translate(0, 0, -capeLen / 2);
    return g;
  };
  const pivot = joint(fig.waist, 0, 0, T - 0.02);
  pivot.add(mesh(arc(rz(T) * 1.15, rz(T) * 1.95, false), green));
  pivot.add(mesh(arc(rz(T) * 1.12, rz(T) * 1.91, true), cloth)); // 안감 (플레이어 색)
  pivot.rotation.y = 0.12;
  fig.flaps.push({ obj: pivot, base: 0.12, lift: 0.55, flutter: 0.12 });
  // 목도리 (플레이어 색): 목에 감은 둥근 띠 + 앞으로 늘어진 두 자락
  fig.waist.add(mesh(new THREE.TorusGeometry(d.headW * 0.55, 0.035, 6, 12).scale(d.depth * 1.1, 1, 0.9), cloth, 0.01, 0, T + 0.01));
  for (const side of [-1, 1]) flap(fig, fig.waist, new THREE.BoxGeometry(0.02, 0.05, 0.16), cloth, rz(T) * d.depth * 0.85, side * 0.035, T - 0.01, -0.15, 0.4, 0.15);
  // 팔: 가죽 소매가 어깨부터 매끈하게 (긴 팔) → 팔꿈치 아래 가죽 장갑 (손목 쪽 넓은 덧댐). 다리: 바지 + 무릎까지 오는 장화 (둥근 모양)
  const A = d.armR;
  const sleeve = latheLimb(d.upper, [[0, A * 1.35], [0.4, A * 1.4], [1, A * 1.15]], 10, A * 1.0);
  const glove = latheLimb(d.lower, [[0, A * 1.2], [0.25, A * 1.3], [0.7, d.foreR * 1.35], [1, d.foreR * 1.6]], 10, A * 1.0);
  const L = d.legR;
  const thighGeo = latheLimb(d.thigh, [[0, L * 1.3], [0.4, L * 1.3], [1, L * 1.08]], 10, L * 0.8);
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(sleeve, green));
    fig.elbows[i].add(mesh(glove, leather));
    fig.hands[i].add(mesh(new THREE.IcosahedronGeometry(d.hand * 1.2, 1), leather));
    fig.thighs[i].add(mesh(thighGeo, pants));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(L * 1.1, 1), pants));
    fig.knees[i].add(mesh(latheLimb(d.shin, [[0, L * 1.3], [0.15, L * 1.4], [1, L * 1.2]], 10, 0), dark, 0, 0, -0.01)); // 무릎까지 장화
    fig.knees[i].add(mesh(ringGeo(L * 1.5, L * 1.45, 0.05, 10), leather, 0, 0, -0.02)); // 장화 접은 단
    fig.feet[i].children[0].visible = false;
    lump(fig.feet[i], L * 1.85, L * 1.15, d.foot * 1.0, dark, L * 0.7, 0, -d.foot * 0.4, 0, 0, 1);
  }
  fig.hips.add(mesh(pelvisGeo(d, 1.12, 0.18), pants, 0, 0, 0));
  // 오른손 사냥칼: 손잡이 + 넓적한 날 (팔이 뻗는 쪽 -z 로)
  const hand = fig.hands[0];
  hand.add(mesh(new THREE.BoxGeometry(0.03, 0.035, 0.07), dark, 0, 0, -d.hand * 0.5));
  hand.add(mesh(new THREE.BoxGeometry(0.02, 0.08, 0.02), steel, 0, 0, -d.hand * 0.5 - 0.045)); // 코등이
  const blade = new THREE.ConeGeometry(0.04, 0.26, 4);
  blade.rotateX(-Math.PI / 2);
  blade.scale(1, 0.3, 1);
  hand.add(mesh(blade, steel, 0, 0, -d.hand * 0.5 - 0.18));
  // 석궁: 개머리(나무) + 활 (양쪽으로 휜 팔) + 시위 + 걸린 화살. 개머리가 +z, 화살 나가는 쪽 -z
  const crossbow = () => {
    const g = new THREE.Group();
    g.add(mesh(new THREE.BoxGeometry(0.04, 0.04, 0.36), wood, 0, 0, -0.06));
    for (const side of [-1, 1]) {
      const arm = mesh(new THREE.BoxGeometry(0.025, 0.2, 0.025), dark, 0, side * 0.1, -0.22);
      arm.rotation.x = side * -0.35; // 끝이 뒤로 휨
      g.add(arm);
    }
    g.add(mesh(new THREE.BoxGeometry(0.008, 0.36, 0.008), costume(0xe8e0c8), 0, 0, -0.17)); // 시위
    g.add(mesh(new THREE.BoxGeometry(0.012, 0.012, 0.24), steel, 0.025, 0, -0.16)); // 걸린 화살
    return g;
  };
  const back = crossbow();
  back.scale.setScalar(1.2);
  back.position.set(-rz(T * 0.62) * d.depth * 1.75 - 0.04, 0, T * 0.55); // 망토 위
  back.rotation.x = -0.8; // 비스듬히 등에 (망토 위)
  back.rotation.y = Math.PI; // 활이 아래쪽
  fig.waist.add(back);
  const inHand = crossbow();
  inHand.scale.setScalar(1.3);
  inHand.position.set(0, 0, -d.hand * 0.6);
  inHand.visible = false;
  fig.hands[1].add(inHand); // 왼손이 받치고 오른손 (칼 든 채) 이 방아쇠 쪽
  fig.bow = { back, inHand };
  fig.sniff = true;
}

// 대포수 (통통 포수 꼬마): 갈고리 해적단의 포수. 공처럼 둥근 배 + 짧고 굵은 팔다리 + 몸보다 큰 대포를 오른 어깨에 멤 + 두건(반다나, 매듭 자락) + 줄무늬 셔츠 + 가죽 띠·포탄 주머니 + 반바지·장화 + 금 귀걸이.
// 플레이어(팀) 색 = 셔츠 줄무늬·소매 줄 + 맨팔. 대포는 쇠 몸통 + 놋쇠 테 + 둥근 꽁무니, 허리 뒤에 포탄 3개 (fig.balls, 탄 수 표시용)
function dressCannon(fig, costume, cloth) {
  const d = fig.d;
  const black = costume(0x222228);
  const white = costume(0xf0ece0);
  const iron = costume(0x3a3c42);
  const brass = costume(0xd0a040);
  const brown = costume(0x6a4428);
  const eyeZ = d.head * 0.5;
  // 두건: 머리를 크게 덮는 검은 반구 (뒤로 처짐) + 이마 띠 + 뒤통수 큰 매듭 + 길게 늘어진 자락 둘 + 흰 물방울 (머리(피부)와 구분되게 검정)
  const capZ = d.head * 0.68;
  const cap = mesh(domeGeo(d.headW * 0.66, 12), black, -0.02, 0, capZ);
  cap.scale.set(1.15, 1.06, 1.0);
  fig.neck.add(cap);
  fig.neck.add(mesh(ringGeo(d.headW * 0.67, d.headW * 0.67, 0.06, 12), black, 0, 0, capZ));
  for (const [x, y, z] of [[0.3, 0.06, 0.08], [0.3, -0.07, 0.05], [0.2, 0.0, 0.12], [0.0, 0.1, 0.1], [0.0, -0.1, 0.09], [-0.25, 0.04, 0.1]]) {
    const r = d.headW * 0.66;
    const v = new THREE.Vector3(x * 2, y * 4, z * 6).normalize().multiplyScalar(r * 1.02);
    fig.neck.add(mesh(new THREE.IcosahedronGeometry(0.016, 1), white, v.x * 1.15 - 0.02, v.y * 1.06, capZ + v.z)); // 흰 물방울 무늬
  }
  lump(fig.neck, 0.05, 0.065, 0.05, black, -d.headW * 0.68, 0, capZ + 0.01, 0, 0, 1); // 큰 매듭
  for (const side of [-1, 1]) flap(fig, fig.neck, new THREE.BoxGeometry(0.015, 0.06, 0.24), black, -d.headW * 0.7, side * 0.035, capZ - 0.01, 0.35 + side * 0.12, 0.7, 0.25);
  // 얼굴 개성: 덥수룩한 검은 구레나룻이 턱선을 따라 이어지는 턱수염 (입 쪽은 비움)
  for (const side of [-1, 1]) lump(fig.neck, 0.035, 0.022, d.head * 0.18, black, d.headW * 0.12, side * d.headW * 0.49, d.head * 0.36, side * 0.15, 0, 1);
  const chin = new THREE.TorusGeometry(d.headW * 0.44, 0.016, 5, 12, Math.PI);
  chin.rotateZ(-Math.PI / 2); // 반원이 앞(+x)으로
  chin.scale(0.9, 1, 1);
  fig.neck.add(mesh(chin, black, d.headW * 0.03, 0, d.head * 0.1));
  addEyes(fig.neck, d.headW * 0.46, 0.05, eyeZ, C.FIGURE_EYE);
  fig.neck.add(mesh(new THREE.TorusGeometry(0.02, 0.006, 4, 8), brass, 0, -d.headW * 0.5, eyeZ - 0.05)); // 금 귀걸이
  // 줄무늬 셔츠: 공 같은 배 (몸통 = 흰 셔츠 재질) 위에 플레이어 색 가로 줄 (맨살 없이 흰·플레이어 색 번갈아)
  fig.torso.material = white;
  fig.waist.children[0].material = white; // 허리 아래 마개도 셔츠 (배 아래로 맨살이 안 보이게)
  fig.hips.children[0].visible = false; // 맨살 골반 대신 좁은 반바지만
  const n = 4;
  for (let k = 0; k < n; k++) {
    const z = d.torso * (0.2 + (k * 0.6) / (n - 1));
    const r = d.chestR * Math.sqrt(Math.max(0.05, 1 - ((z - d.torso / 2) / (d.torso / 2)) ** 2)) * 1.03 + 0.006;
    fig.waist.add(mesh(ringGeo(r, r, 0.055, 14, d.depth), cloth, 0, 0, z));
  }
  // 가죽 띠 (왼 어깨 → 오른 허리, 배를 감고 비스듬히) + 포탄 주머니 둘
  const strap = new THREE.TorusGeometry(d.chestR * 1.05, 0.018, 4, 16);
  strap.scale(d.depth * 1.02, 1, 1.25);
  const sm = mesh(strap, brown, 0, 0, d.torso * 0.52);
  sm.rotation.x = 0.75;
  fig.waist.add(sm);
  for (const [y, z] of [[-0.09, 0.32], [0.04, 0.6]]) lump(fig.waist, 0.035, 0.045, 0.045, brown, d.chestR * d.depth * 0.98, y, d.torso * z, 0, 0, 1);
  // 팔: 어깨부터 팔꿈치 아래까지 긴 줄무늬 소매 (흰 바탕 + 플레이어 색 줄, 한 덩어리) → 플레이어 색 굵게 접은 소매 끝 → 짧은 맨팔뚝 → 큰 가죽 장갑 (건축가 체크 소매와 다르게)
  const A = d.armR;
  const sleeve = latheLimb(d.upper, [[0, A * 1.55], [0.5, A * 1.6], [1, A * 1.5]], 10, A * 1.2);
  const fore = latheLimb(d.lower * 0.55, [[0, A * 1.5], [1, A * 1.45]], 10, A * 1.25);
  for (let i = 0; i < 2; i++) {
    fig.shoulders[i].add(mesh(sleeve, white));
    for (const t of [0.25, 0.6]) fig.shoulders[i].add(mesh(ringGeo(A * 1.63, A * 1.63, 0.035, 10), cloth, 0, 0, -d.upper * t));
    fig.elbows[i].add(mesh(fore, white));
    fig.elbows[i].add(mesh(ringGeo(A * 1.53, A * 1.53, 0.03, 10), cloth, 0, 0, -d.lower * 0.2));
    fig.elbows[i].add(mesh(ringGeo(A * 1.7, A * 1.7, 0.05, 10), cloth, 0, 0, -d.lower * 0.55)); // 접은 소매 끝
    fig.elbows[i].add(mesh(latheLimb(d.lower * 0.45, [[0, A * 1.15], [1, d.foreR * 1.05]], 10), cloth, 0, 0, -d.lower * 0.55));
    fig.hands[i].add(mesh(ringGeo(d.foreR * 1.5, d.foreR * 1.6, 0.04, 10), brown, 0, 0, d.hand * 0.7)); // 장갑 목
    fig.hands[i].add(mesh(new THREE.IcosahedronGeometry(d.hand * 1.45, 1), brown));
  }
  // 넓은 갈색 허리띠·둥근 금 버클 + 짧고 헐렁한 검은 반바지 + 굵은 장화 (둥근, 접은 단)
  fig.waist.add(mesh(ringGeo(d.waistR * 1.0, d.waistR * 1.0, 0.07, 14, d.depth), brown, 0, 0, d.torso * 0.12));
  fig.waist.add(mesh(new THREE.CylinderGeometry(0.04, 0.04, 0.018, 10).rotateZ(Math.PI / 2), brass, d.waistR * d.depth + 0.008, 0, d.torso * 0.12));
  fig.hips.add(mesh(pelvisGeo(d, C.CANNON_SHORTS_GROW, 0.18), black, 0, 0, -0.02)); // 반바지는 배 아래로 좁게 (배가 앞·옆으로 튀어나옴)
  const L = d.legR;
  for (let i = 0; i < 2; i++) {
    fig.thighs[i].add(mesh(latheLimb(d.thigh * 1.02, [[0, L * 1.45], [0.5, L * 1.55], [1, L * 1.35]], 10, L * 0.9), black));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(L * 1.3, 1), black));
    fig.knees[i].add(mesh(latheLimb(d.shin, [[0, L * 1.45], [0.2, L * 1.4], [1, L * 1.35]], 10), brown, 0, 0, -0.01)); // 장화
    fig.knees[i].add(mesh(ringGeo(L * 1.65, L * 1.5, 0.05, 10), brown, 0, 0, -0.02));
    fig.feet[i].children[0].visible = false;
    lump(fig.feet[i], L * 1.75, L * 1.2, d.foot * 1.0, brown, L * 0.6, 0, -d.foot * 0.4, 0, 0, 1);
  }
  // 허리 뒤 포탄 3개 (탄 수만큼 보임, render 가 끔)
  fig.balls = [-1, 0, 1].map((k) => {
    const b = mesh(new THREE.IcosahedronGeometry(0.055, 1), iron, -d.waistR * d.depth - 0.03, k * 0.09, d.torso * 0.1);
    fig.waist.add(b);
    return b;
  });
  // 대포: 오른 어깨 위에 앞뒤로 길게 (포구가 앞 +x). 몸 길이보다 김
  const cannon = new THREE.Group();
  const len = 0.95;
  const body = new THREE.CylinderGeometry(0.1, 0.13, len, 12);
  body.rotateZ(-Math.PI / 2); // 축 y → x, 굵은 쪽(아래 = 뒤)이 -x
  cannon.add(mesh(body, iron));
  for (const [x, r] of [[0.46, 0.12], [0.36, 0.115], [-0.05, 0.125], [-0.4, 0.14]]) {
    const ring = new THREE.CylinderGeometry(r, r, 0.035, 12);
    ring.rotateZ(Math.PI / 2);
    cannon.add(mesh(ring, brass, x, 0, 0));
  }
  const muzzle = new THREE.CylinderGeometry(0.125, 0.1, 0.07, 12);
  muzzle.rotateZ(-Math.PI / 2);
  cannon.add(mesh(muzzle, iron, len / 2 + 0.02, 0, 0));
  const bore = new THREE.CircleGeometry(0.075, 12);
  bore.rotateY(Math.PI / 2);
  cannon.add(mesh(bore, costume(0x0a0a0a), len / 2 + 0.056, 0, 0)); // 포구 구멍
  cannon.add(mesh(new THREE.IcosahedronGeometry(0.07, 1), iron, -len / 2 - 0.05, 0, 0)); // 둥근 꽁무니
  cannon.add(mesh(new THREE.BoxGeometry(0.02, 0.02, 0.06), brass, -0.38, 0, 0.14)); // 심지 구멍
  cannon.position.set(-0.05, -d.shoulderY - 0.02, d.torso + 0.1);
  cannon.rotation.y = -0.12; // 포구가 살짝 위로
  fig.waist.add(cannon);
  fig.cannon = cannon;
}

// 광전사: 바이킹. 우락부락한 몸 + 쇠 투구(코 가리개) + 흐물거리는 두 마디 뿔 (fig.horns) + 덥수룩한 주황 수염·땋은 갈래 둘 +
// 어깨 털 망토 + 맨가슴(피부 = 플레이어 색)에 가죽 띠 X + 둥근 금 버클 허리띠 + 가죽 바지·털 장화 + 팔목 보호대 + 오른손 큰 도끼 (가만히 있으면 어깨에 걸침)
// 분노(피해 % 따라 몸이 빨갛게 빛나고 김)는 render.js 가 칠함
function dressBerserker(fig, costume, cloth) {
  const d = fig.d;
  const iron = costume(0x8a9098);
  const bone = costume(0xeee2c4);
  const ginger = costume(0xd0702a);
  const fur = costume(0x9a8468);
  const darkFur = costume(0x5a4430);
  const leather = costume(0x6a4428);
  const dark = costume(0x3a2a1c);
  const gold = costume(0xd8a838);
  const steel = costume(0xc4ccd4);
  const wood = costume(0x7a5030);
  // 투구: 쇠 반구 + 테 + 코 가리개 + 가운데 능선
  const browZ = d.head * 0.62;
  const helm = mesh(domeGeo(d.headW * 0.62, 10), iron, 0, 0, browZ);
  helm.scale.z = 1.05;
  fig.neck.add(helm);
  fig.neck.add(mesh(ringGeo(d.headW * 0.64, d.headW * 0.64, 0.05, 10), iron, 0, 0, browZ));
  fig.neck.add(mesh(new THREE.BoxGeometry(0.02, 0.035, 0.12), iron, d.headW * 0.62, 0, browZ - 0.05)); // 코 가리개
  fig.neck.add(mesh(new THREE.BoxGeometry(d.headW * 1.2, 0.02, 0.03), iron, 0, 0, browZ + d.headW * 0.6));
  // 뿔: 바이킹 소뿔. 마디 HORN_SEGS 개를 이어 붙인 휜 호 (투구 옆에서 바깥으로 나갔다 위로 C 자로 휨), 끝으로 갈수록 가늘고 뾰족.
  // 색은 뿌리 상아색 → 끝 짙은 갈색 (마디마다 조금씩), 뿌리에 쇠 고리. 휜 각은 figureAnim 이 마디마다 줌
  const N = C.FIGURE_HORN_SEGS;
  const ivory = new THREE.Color(0xf2e8cc);
  const brown = new THREE.Color(0x4e3018);
  fig.horns = [];
  for (const side of [-1, 1]) {
    const root = joint(fig.neck, 0, side * d.headW * 0.6, browZ + 0.04);
    const ring = new THREE.TorusGeometry(0.058, 0.014, 5, 10);
    ring.rotateX(Math.PI / 2); // 고리 면이 뿔 축(±y)에 수직
    root.add(mesh(ring, iron, 0, side * 0.012, 0));
    const segs = [];
    let parent = root;
    for (let k = 0; k < N; k++) {
      const u0 = k / N;
      const u1 = (k + 1) / N;
      const r0 = 0.058 * (1 - u0 * 0.9);
      const r1 = k === N - 1 ? 0.002 : 0.058 * (1 - u1 * 0.9); // 끝 마디는 뾰족
      const len = C.FIGURE_HORN_LEN / N;
      const geo = new THREE.CylinderGeometry(r1, r0 * 1.04, len * 1.12, 8); // 조금 길게 → 이음새가 겹쳐 안 보임
      geo.translate(0, len / 2, 0); // 뿌리가 원점, +y 로 뻗음
      if (side < 0) geo.rotateZ(Math.PI); // -y 로
      const j2 = k === 0 ? root : joint(parent, 0, side * len, 0);
      j2.add(mesh(geo, costume(ivory.clone().lerp(brown, (u0 + u1) / 2).getHex())));
      j2.rotation.x = side * (k === 0 ? 0.15 : C.FIGURE_HORN_CURL / (N - 1)); // 처음부터 휜 채로 (figureAnim 도 같은 각)
      segs.push(j2);
      parent = j2;
    }
    fig.horns.push({ segs, side });
  }
  // 분노 (render.js 가 피해 % 로 움직임): 충혈되는 흰자 (따로 재질) · 찌푸리는 굵은 눈썹 · 팔·이마에 솟는 핏줄. 피부(플레이어 색)는 그대로 둠
  const eyeMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff }));
  fig.pupils = addEyes(fig.neck, d.headW * 0.46, 0.05, d.head * 0.5, C.FIGURE_EYE, [-1, 1], eyeMat);
  const brows = [-1, 1].map((side) => {
    const b = mesh(new THREE.BoxGeometry(0.03, 0.075, 0.025), ginger, d.headW * 0.5 + C.FIGURE_EYE * 0.6, side * 0.05, d.head * 0.5 + C.FIGURE_EYE + 0.012);
    fig.neck.add(b);
    return { mesh: b, side };
  });
  const veinMat = costume(0xc0101a);
  const veins = [];
  const vein = (parent, x, y, z, len, rot) => {
    const v = mesh(new THREE.BoxGeometry(0.012, 0.012, len), veinMat, x, y, z);
    v.rotation.x = rot;
    v.visible = false;
    parent.add(v);
    veins.push(v);
  };
  for (let i = 0; i < 2; i++) {
    vein(fig.shoulders[i], d.armR * 0.95, 0.005, -d.upper * 0.45, d.upper * 0.5, 0.25);
    vein(fig.shoulders[i], d.armR * 0.7, -0.03, -d.upper * 0.55, d.upper * 0.3, -0.4);
  }
  vein(fig.neck, d.headW * 0.47, 0.02, d.head * 0.66, 0.05, 0.5); // 이마 (투구 아래)
  vein(fig.neck, d.headW * 0.47, -0.02, d.head * 0.66, 0.05, -0.5);
  // 만화 '빡침' 표시: 투구 옆에 빨간 네 갈래 (분노 절반 넘으면 벌떡벌떡)
  const anger = new THREE.Group();
  const angerMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xe0201a }));
  for (let k = 0; k < 4; k++) {
    const a = (k * Math.PI) / 2 + Math.PI / 4;
    const arm = new THREE.Mesh(new THREE.BoxGeometry(0.012, 0.02, 0.05), angerMat);
    arm.position.set(0, Math.cos(a) * 0.035, Math.sin(a) * 0.035);
    arm.rotation.x = -a;
    anger.add(arm);
  }
  anger.position.set(d.headW * 0.25, -d.headW * 0.75, d.head * 1.05);
  anger.visible = false;
  fig.neck.add(anger);
  fig.rage = { eyeMat, brows, veins, anger, k: 0 };
  // 수염: 턱 아래 덥수룩한 덩어리 + 콧수염 + 땋은 갈래 둘 (흔들림)
  const beard = new THREE.IcosahedronGeometry(0.5, 1);
  beard.scale(d.headW * 0.55, d.headW * 1.0, d.head * 0.85);
  fig.neck.add(mesh(beard, ginger, d.headW * 0.62, 0, d.head * 0.14)); // 입 아래부터 털 망토 앞까지
  fig.neck.add(mesh(new THREE.BoxGeometry(0.04, d.headW * 0.9, 0.04), ginger, d.headW * 0.6, 0, d.head * 0.33)); // 콧수염
  for (const side of [-1, 1]) flap(fig, fig.neck, new THREE.BoxGeometry(0.04, 0.04, 0.2), ginger, d.headW * 0.62, side * 0.055, -d.head * 0.08, -0.12, -0.4, 0.2);
  // 구레나룻: 투구 옆에서 수염까지 이어지는 덥수룩한 털 (성질 있는 얼굴)
  for (const side of [-1, 1]) {
    const burn = new THREE.IcosahedronGeometry(1, 0);
    burn.scale(0.07, 0.04, d.head * 0.3);
    fig.neck.add(mesh(burn, ginger, d.headW * 0.22, side * d.headW * 0.46, d.head * 0.36));
  }
  // 근육 몸통 (맨살 = 플레이어 색): 기본 8각 통 위에 가슴·배·등 근육 덩어리를 저폴리로 얹고, 사이 홈은 피부보다 어두운 색 (fig.shade, figureAnim 이 피부색을 따라 칠함)
  const T = d.torso;
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T; // 높이 z 의 몸통 반지름
  const surfX = (z, y) => d.depth * (rz(z) - 0.414 * Math.abs(y)); // 8각 통 앞면 x (앞 가운데가 모서리)
  const shade = costume(0x000000);
  fig.shade = { mat: shade, src: cloth };
  for (const side of [-1, 1]) {
    const py = side * d.chestR * 0.4;
    lump(fig.waist, 0.06, d.chestR * 0.4, T * 0.14, cloth, surfX(T * 0.74, py) + 0.01, py, T * 0.74, side * 0.15, -0.25); // 가슴 (아래 모서리가 앞으로)
    lump(fig.waist, 0.11, d.chestR * 0.36, 0.08, cloth, -0.03, side * d.chestR * 0.45, T * 0.96); // 승모근 (목이 거의 없게)
    const by = side * d.chestR * 0.42;
    lump(fig.waist, 0.05, d.chestR * 0.42, T * 0.26, cloth, -surfX(T * 0.62, by) - 0.008, by, T * 0.62, side * -0.12, 0.15); // 등 (광배근)
  }
  fig.waist.add(mesh(new THREE.BoxGeometry(0.03, 0.022, T * 0.24), shade, surfX(T * 0.72, 0) + 0.004, 0, T * 0.72)); // 가슴 사이 홈
  fig.waist.add(mesh(new THREE.BoxGeometry(0.03, 0.022, T * 0.5), shade, -surfX(T * 0.6, 0) - 0.004, 0, T * 0.58)); // 척추 홈
  // 배: 어두운 판 위에 복근 2×3 (사이 틈이 홈으로 보임)
  const absX = surfX(T * 0.3, 0) + 0.004;
  fig.waist.add(mesh(new THREE.BoxGeometry(0.03, 0.17, T * 0.42), shade, absX, 0, T * 0.32));
  for (const z of [0.17, 0.31, 0.45]) for (const side of [-1, 1]) fig.waist.add(mesh(new THREE.BoxGeometry(0.035, 0.074, T * 0.12), cloth, absX + 0.012, side * 0.041, T * z));
  lump(fig.waist, 0.025, 0.06, 0.05, ginger, surfX(T * 0.86, 0) + 0.015, 0, T * 0.86); // 가슴 털
  // 어깨 털 망토 (크게) + 어깨 위 털 뭉치 + 등 뒤 짧은 털 자락
  const mantle = new THREE.TorusGeometry(d.chestR * 0.95, 0.12, 6, 14, Math.PI * 1.35); // 앞이 트임 (수염·가슴이 보이게)
  mantle.rotateZ(Math.PI - Math.PI * 0.675); // 트인 쪽이 앞(+x)
  mantle.scale(d.depth, 1, 0.85);
  fig.waist.add(mesh(mantle, fur, 0, 0, T - 0.01));
  for (let k = 0; k < 9; k++) {
    const a = Math.PI * (0.45 + (k * 1.1) / 8); // 뒤쪽·어깨에 털 뭉치
    lump(fig.waist, 0.085, 0.085, 0.07, fur, Math.cos(a) * d.chestR * d.depth, Math.sin(a) * d.chestR * 0.98, T - 0.07 - 0.02 * (k % 2), 0.4 * k, 0.7 * k);
  }
  for (const side of [-1, 1]) lump(fig.waist, 0.13, 0.12, 0.08, fur, -0.01, side * d.chestR * 0.98, T + 0.02, side * 0.3, 0.2); // 어깨 위
  for (const [y, w, len] of [[0, 0.17, 0.42], [-0.15, 0.13, 0.32], [0.15, 0.13, 0.32]]) {
    flap(fig, fig.waist, new THREE.BoxGeometry(0.035, w, T * len), fur, -d.chestR * d.depth * (y ? 0.85 : 1) - 0.02, y, T - 0.05, 0.15, 0.7, 0.1); // 등 털 자락 (가운데 길게, 끝이 들쭉날쭉)
  }
  // 가죽 띠 하나 (왼 어깨 → 오른 옆구리) + 쇠고리
  const strap = mesh(new THREE.BoxGeometry(0.02, 0.055, T * 1.08), leather, surfX(T * 0.56, 0) + 0.018, 0, T * 0.56);
  strap.rotation.x = 0.6;
  fig.waist.add(strap);
  const ringGeo2 = new THREE.TorusGeometry(0.03, 0.009, 4, 8);
  ringGeo2.rotateY(Math.PI / 2);
  fig.waist.add(mesh(ringGeo2, iron, surfX(T * 0.62, 0) + 0.03, -0.045, T * 0.64));
  // 허리: 넓은 허리띠(몸통 쪽) 가 골반 쪽 가죽 바지 위끝을 덮음 → 숙이거나 비틀어도 이음매가 안 보임. 앞뒤 털 자락 (골반 쪽)
  fig.waist.add(mesh(ringGeo(d.waistR * 1.14, d.waistR * 1.12, 0.1, 10, d.depth), dark, 0, 0, 0.035));
  const buckle = new THREE.CylinderGeometry(0.06, 0.06, 0.025, 10);
  buckle.rotateZ(Math.PI / 2);
  fig.waist.add(mesh(buckle, gold, d.waistR * 1.14 * d.depth + 0.01, 0, 0.035));
  fig.hips.add(mesh(pelvisGeo(d, 1.12, 0.2), leather, 0, 0, 0));
  flap(fig, fig.hips, new THREE.BoxGeometry(0.03, d.waistR * 0.7, 0.17), darkFur, d.waistR * d.depth * 1.15, 0, 0.04, -0.06, -0.5, 0.08);
  flap(fig, fig.hips, new THREE.BoxGeometry(0.03, d.waistR * 1.3, 0.2), darkFur, -d.waistR * d.depth * 1.15, 0, 0.04, 0.06, 0.6, 0.08);
  // 가죽 바지 + 털 장화 (끈 감김) + 팔: 어깨 덩어리·알통·굵은 팔뚝 (맨살) + 팔목 보호대
  for (let i = 0; i < 2; i++) {
    const side = i ? 1 : -1;
    fig.thighs[i].add(mesh(limbGeo(d.thigh * 1.05, d.legR * 1.22, d.legR * 1.08, 7), leather));
    fig.knees[i].add(mesh(new THREE.IcosahedronGeometry(d.legR * 1.3, 0), leather));
    fig.knees[i].add(mesh(limbGeo(d.shin * 0.75, d.legR * 1.12, d.legR * 1.02, 7), leather));
    fig.knees[i].add(mesh(limbGeo(d.shin * 0.75, d.legR * 1.32, d.legR * 1.2, 8), fur, 0, 0, -d.shin * 0.28));
    for (const z of [0.45, 0.7]) fig.knees[i].add(mesh(ringGeo(d.legR * 1.35, d.legR * 1.35, 0.02, 8), dark, 0, 0, -d.shin * z));
    fig.feet[i].add(mesh(new THREE.BoxGeometry(d.legR * 3.3, d.legR * 1.9, d.foot * 1.3), fur, d.legR * 0.6, 0, -d.foot / 2));
    lump(fig.shoulders[i], d.armR * 1.45, d.armR * 1.5, d.armR * 1.35, cloth, 0, side * d.armR * 0.25, -d.armR * 0.2); // 어깨
    lump(fig.shoulders[i], d.armR * 1.15, d.armR * 1.0, d.upper * 0.28, cloth, d.armR * 0.35, 0, -d.upper * 0.55); // 알통
    lump(fig.elbows[i], d.foreR * 1.3, d.foreR * 1.25, d.lower * 0.26, cloth, 0, 0, -d.lower * 0.22); // 팔뚝
    fig.elbows[i].add(mesh(limbGeo(d.lower * 0.42, d.foreR * 1.25, d.foreR * 1.15, 8), leather, 0, 0, -d.lower * 0.52));
  }
  // 큰 도끼: 오른손에. 자루가 손에서 팔 뻗는 쪽(-z)으로 길게, 끝에 넓은 초승달 날 (한쪽 = 손등 쪽 +x) + 반대쪽 뾰족
  const axe = new THREE.Group();
  axe.add(mesh(new THREE.CylinderGeometry(0.022, 0.026, 0.82, 6).rotateX(Math.PI / 2), wood, 0, 0, -0.3));
  const bladeGeo = new THREE.CylinderGeometry(0.2, 0.2, 0.025, 14, 1, false, -Math.PI * 0.32, Math.PI * 0.64);
  bladeGeo.rotateZ(Math.PI / 2); // 판이 x-z 면 → 돌려서 x-z 면에 납작하게
  bladeGeo.rotateX(Math.PI / 2);
  const blade = mesh(bladeGeo, steel, 0.02, 0, -0.62);
  axe.add(blade);
  axe.add(mesh(new THREE.BoxGeometry(0.1, 0.035, 0.09), iron, 0.02, 0, -0.63)); // 날 목
  axe.add(mesh(new THREE.ConeGeometry(0.035, 0.1, 4).rotateZ(Math.PI / 2), iron, -0.07, 0, -0.63)); // 반대쪽 뾰족
  for (const z of [-0.08, 0.04]) axe.add(mesh(ringGeo(0.03, 0.03, 0.025, 6), leather, 0, 0, z)); // 손잡이 감은 가죽
  axe.position.set(0, 0, -d.hand * 0.3);
  fig.hands[0].add(axe);
  fig.axe = axe;
}

// 바드: 두 폼을 다 만들어 두고 fig.setForm('bard' | 'metal') 로 바꿔 보임 (render 가 snapshot form 으로 부름). 몸은 같은 호리호리 체형 (lithe)
// 음유시인 (로빈후드) = 초록 뾰족 모자·깃털 + 플레이어 색 망토(어깨 두건 + 무릎까지 자락) + 헐렁한 리넨 소매 튜닉 + 갈색 조끼 + 초록 바지 + 접은 긴 장화 + 류트
// 메탈 = 빨강·검정 모히칸 + 검정 티 + 징 박힌 검정 민소매 재킷 + 맨팔 (플레이어 색) + 찢어진 청바지 + 가시 팔찌 + V 일렉기타
// 플레이어 색이 멀리서 보이는 큰 면: 음유 = 망토·깃털, 메탈 = 맨팔·손목 띠 (2026-10-28 재혁: 얼굴만으로는 부족)
function dressBard(fig, costume, cloth) {
  const d = fig.d;
  const T = d.torso;
  const forms = { bard: new THREE.Group(), metal: new THREE.Group() };
  // 몸 부위마다 폼별 묶음 (부위가 따로 움직여서 부위마다 Group 을 붙이고 폼에 등록). 폼마다 처음 등록한 것 = 머리 (폼 바뀜 연출)
  const part = (parent, form) => {
    const g = new THREE.Group();
    parent.add(g);
    (forms[form].userData.parts ||= []).push(g);
    return g;
  };
  const eyeZ = d.head * 0.55;
  addEyes(fig.neck, d.headW * 0.44, 0.046, eyeZ, C.FIGURE_EYE);
  const brown = costume(0x7a4e2a);
  const darkBrown = costume(0x4a301a);
  const wood = costume(0xb07838);
  const string = costume(0xf0e8d0);
  const gold = costume(0xd8a838);
  fig.feet.forEach((f) => (f.children[0].visible = false)); // 맨발 상자 대신 장화 (두 폼)
  const rz = (z) => d.waistR + ((d.chestR - d.waistR) * z) / T;
  const torsoMat = {};
  // 둥근 장화: 발 덩어리 + 정강이를 감싸는 통 (+ 접은 단)
  const boot = (i, form, mat, cuffMat) => {
    const f = part(fig.feet[i], form);
    lump(f, d.legR * 1.9, d.legR * 1.15, d.foot * 1.05, mat, d.legR * 0.7, 0, -d.foot * 0.4, 0, 0, 1);
    const k = part(fig.knees[i], form);
    k.add(mesh(limbGeo(d.shin * 0.62, d.legR * 1.35, d.legR * 1.25, 10), mat, 0, 0, -d.shin * 0.38));
    if (cuffMat) k.add(mesh(ringGeo(d.legR * 1.55, d.legR * 1.45, 0.06, 10), cuffMat, 0, 0, -d.shin * 0.38));
  };
  // 다리: 허벅지 → 무릎 → 정강이 위까지 한 굵기로 이어지는 바지 (무릎은 같은 굵기 공이라 굽혀도 이음이 안 벌어짐)
  const pants = (i, form, mat, kneeMat) => {
    part(fig.thighs[i], form).add(mesh(limbGeo(d.thigh * 1.04, d.legR * 1.25, d.legR * 1.12, 10), mat));
    const k = part(fig.knees[i], form);
    k.add(mesh(new THREE.IcosahedronGeometry(d.legR * 1.12, 1), kneeMat || mat));
    k.add(mesh(limbGeo(d.shin * 0.5, d.legR * 1.12, d.legR * 1.05, 10), mat));
  };
  // ---- 음유시인 ----
  {
    // 숲색 (거의 검은 초록) + 금 테: 초록 플레이어여도 모자·바지가 망토(플레이어 색)와 갈려 보이게
    const green = costume(0x1f3d1e);
    const darkGreen = costume(0x142a14);
    const linen = costume(0xe6dcc4);
    torsoMat.bard = linen;
    const head = part(fig.neck, 'bard');
    // 뾰족 모자: 앞뒤로 긴 납작 원뿔 (뒤로 꺾인 끝) + 금 테 + 플레이어 색 깃털
    const capZ = d.head * 0.72;
    const cap = new THREE.ConeGeometry(d.headW * 0.68, d.head * 0.75, 8);
    cap.rotateX(Math.PI / 2);
    cap.scale(1.25, 0.95, 1);
    const capM = mesh(cap, green, -0.03, 0, capZ + d.head * 0.3);
    capM.rotation.y = -0.45; // 끝이 뒤로
    head.add(capM);
    head.add(mesh(ringGeo(d.headW * 0.64, d.headW * 0.64, 0.045, 10), gold, 0, 0, capZ)); // 금 테
    const plume = lump(head, 0.02, 0.035, 0.16, cloth, -0.02, d.headW * 0.58, capZ + 0.1, -0.35, -0.85, 1);
    plume.rotation.order = 'YXZ';
    // 튜닉: 몸통은 리넨 (setForm 이 몸통 재질을 바꿈) + 갈색 조끼 (닫힌 통, 앞 끈 X) + 허리띠·금 버클·주머니 + 허리 아래로 퍼지는 튜닉 자락
    const body = part(fig.waist, 'bard');
    body.add(mesh(ringGeo(rz(T * 0.8) * 1.07, d.waistR * 1.1, T * 0.72, 10, d.depth), brown, 0, 0, T * 0.44));
    for (let k = 0; k < 3; k++) {
      const z = T * (0.3 + k * 0.17);
      const x = rz(z) * d.depth * 1.08 + 0.004;
      for (const side of [-1, 1]) {
        const lace = mesh(ringGeo(0.006, 0.006, 0.07, 4).rotateX(Math.PI / 2), linen, x, 0, z);
        lace.rotation.x = side * 0.7;
        body.add(lace);
      }
    }
    body.add(mesh(ringGeo(d.waistR * 1.2, d.waistR * 1.2, 0.05, 10, d.depth), darkBrown, 0, 0, 0.06));
    body.add(mesh(new THREE.CylinderGeometry(0.03, 0.03, 0.015, 8).rotateZ(Math.PI / 2), gold, d.waistR * 1.2 * d.depth + 0.008, 0, 0.06));
    lump(body, 0.03, 0.04, 0.045, darkBrown, d.waistR * 0.5 * d.depth, -d.waistR * 1.15, 0.01, 0, 0, 1); // 주머니
    body.add(mesh(ringGeo(d.waistR * 1.2, d.waistR * 1.5, 0.14, 10, d.depth), linen, 0, 0, -0.02)); // 튜닉 자락 (골반 위끝을 덮음)
    // 망토 (플레이어 색): 어깨 두건 + 등 뒤 둥근 자락 (아래로 넓어짐, 금 테). 빨리 움직이면 뒤로 날림
    const hood = new THREE.CylinderGeometry(d.headW * 0.62, rz(T) * 1.75, C.BARD_HOOD_H, 12); // 어깨 덮는 두건 깃 (앞에서도 플레이어 색이 크게 보이게)
    hood.rotateX(Math.PI / 2);
    hood.scale(d.depth * 1.08, 1, 1);
    body.add(mesh(hood, cloth, 0, 0, T + 0.03 - C.BARD_HOOD_H / 2));
    body.add(mesh(ringGeo(rz(T) * 1.76, rz(T) * 1.76, 0.02, 12, d.depth * 1.08), gold, 0, 0, T + 0.02 - C.BARD_HOOD_H)); // 두건 끝 금 테
    const capeLen = C.BARD_CAPE_LEN;
    const capeGeo = new THREE.CylinderGeometry(rz(T) * 1.12, rz(T) * 1.6, capeLen, 12, 1, true, Math.PI * 1.15, Math.PI * 0.7);
    capeGeo.rotateX(Math.PI / 2);
    capeGeo.scale(d.depth, 1, 1);
    capeGeo.translate(0, 0, -capeLen / 2);
    const pivot = joint(body, 0, 0, T - 0.02);
    const capeM = mesh(capeGeo, cloth);
    capeM.material = cloth;
    pivot.add(capeM);
    const hemGeo = new THREE.CylinderGeometry(rz(T) * 1.62, rz(T) * 1.62, 0.025, 12, 1, true, Math.PI * 1.15, Math.PI * 0.7);
    hemGeo.rotateX(Math.PI / 2);
    hemGeo.scale(d.depth, 1, 1);
    pivot.add(mesh(hemGeo, gold, 0, 0, -capeLen + 0.012));
    pivot.rotation.y = 0.1;
    fig.flaps.push({ obj: pivot, base: 0.1, lift: 0.6, flutter: 0.1 });
    fig.cape = capeM;
    // 팔: 어깨부터 리넨 소매가 매끈하게 → 팔꿈치 아래로 넓게 퍼지는 헐렁한 소매 (팔꿈치에서 겹침) → 손목은 갈색 소매 끝
    const rU = d.armR * 1.45;
    for (let i = 0; i < 2; i++) {
      const sh = part(fig.shoulders[i], 'bard');
      sh.add(mesh(domeGeo(rU, 10), linen, 0, 0, d.armR * 0.4));
      sh.add(mesh(limbGeo(d.upper + d.armR * 0.4, rU, rU * 1.15, 10), linen, 0, 0, d.armR * 0.4));
      const el = part(fig.elbows[i], 'bard');
      el.add(mesh(new THREE.IcosahedronGeometry(rU * 1.15, 1), linen)); // 팔꿈치 (위·아래 소매와 같은 굵기)
      el.add(mesh(limbGeo(d.lower * 0.82, rU * 1.15, rU * 1.75, 10), linen)); // 헐렁하게 퍼지는 소매
      el.add(mesh(ringGeo(rU * 1.78, rU * 1.78, 0.025, 10), brown, 0, 0, -d.lower * 0.82)); // 소매 끝 테
    }
    for (let i = 0; i < 2; i++) {
      pants(i, 'bard', green);
      boot(i, 'bard', darkBrown, brown);
    }
    part(fig.hips, 'bard').add(mesh(pelvisGeo(d, 1.12, 0.18), green, 0, 0, 0));
    // 류트: 배 모양 몸통 (반쪽 공) + 울림 구멍 + 목 (뒤로 꺾인 머리) + 줄. 가슴 앞에 비스듬히 (목이 왼쪽 위로)
    const lute = new THREE.Group();
    const bowl = new THREE.SphereGeometry(0.13, 10, 8, 0, Math.PI * 2, 0, Math.PI / 2);
    bowl.scale(1, 0.75, 1.35);
    bowl.rotateY(-Math.PI / 2); // 둥근 등이 몸 쪽(-x), 판이 앞(+x)
    lute.add(mesh(bowl, wood));
    lute.add(mesh(new THREE.CylinderGeometry(0.035, 0.035, 0.005, 10).rotateZ(Math.PI / 2), darkBrown, 0.005, 0, 0.03));
    lute.add(mesh(new THREE.BoxGeometry(0.02, 0.045, 0.3), darkBrown, 0.0, 0, 0.3));
    const pegbox = mesh(new THREE.BoxGeometry(0.02, 0.05, 0.09), darkBrown, -0.03, 0, 0.47);
    pegbox.rotation.y = 0.9;
    lute.add(pegbox);
    const strings = new THREE.Group();
    for (const y of [-0.012, 0, 0.012]) strings.add(mesh(new THREE.BoxGeometry(0.004, 0.003, 0.5), string, 0.012, y, 0.2));
    lute.add(strings);
    lute.scale.setScalar(C.BARD_LUTE_SCALE);
    lute.position.set(rz(T * 0.42) * d.depth * 1.1 + 0.08, 0.02, T * 0.42);
    lute.rotation.x = -0.9; // 목이 왼쪽(+y) 위로
    body.add(lute);
    fig.lute = { lute, strings };
  }
  // ---- 메탈 ----
  {
    const black = costume(0x1c1c22);
    const tee = costume(0x2c2c34);
    const red = costume(0xd8202a);
    const blue = costume(0x2a4cc8);
    const stud = costume(0xd8dce4);
    torsoMat.metal = tee;
    const head = part(fig.neck, 'metal');
    // 모히칸: 머리 가운데 앞에서 뒤로 뾰족 가시 줄 (플레이어 색·검정 번갈아). fig.mohawk 를 키워 솟는 연출
    const mohawk = new THREE.Group();
    const n = 8;
    for (let k = 0; k < n; k++) {
      const a = Math.PI * (0.2 + (k * 0.75) / (n - 1)); // 이마 위(앞)에서 뒤통수 쪽으로 머리 위 호
      const h = 0.12 + 0.09 * Math.sin((Math.PI * k) / (n - 1)); // 가운데가 가장 높음
      const geo = new THREE.ConeGeometry(0.045, h, 5);
      geo.rotateX(Math.PI / 2); // 축 +z
      geo.scale(1, 0.4, 1); // 옆으로 납작 (지느러미처럼 한 줄)
      const spike = mesh(geo, k % 2 ? black : cloth, Math.cos(a) * d.headW * 0.5, 0, d.head * 0.5 + Math.sin(a) * d.head * 0.5); // 플레이어 색·검정 번갈아
      spike.rotation.y = Math.PI / 2 - a; // 머리 표면에서 바깥(반지름 방향)으로
      spike.position.addScaledVector(new THREE.Vector3(Math.cos(a), 0, Math.sin(a)), h / 2 - 0.01);
      mohawk.add(spike);
    }
    head.add(mohawk);
    fig.mohawk = mohawk;
    head.add(mesh(new THREE.TorusGeometry(0.018, 0.005, 4, 8), stud, 0, -d.headW * 0.5, eyeZ - 0.05)); // 귀 피어싱
    // 검정 티 (몸통) 위에 징 박힌 민소매 재킷: 앞이 조금 열린 통 (안쪽은 티라 어두운 구멍처럼 안 보임) + 어깨 가시 + 천 조각
    const body = part(fig.waist, 'metal');
    const open = 0.55;
    const jacket = new THREE.CylinderGeometry(rz(T) * 1.1, d.waistR * 1.15, T * 0.9, 10, 1, true, Math.PI / 2 + open / 2, Math.PI * 2 - open);
    jacket.rotateX(Math.PI / 2);
    jacket.scale(d.depth, 1, 1);
    const jm = mesh(jacket, black, 0, 0, T * 0.52);
    jm.material.side = THREE.DoubleSide;
    body.add(jm);
    const collar = new THREE.CylinderGeometry(d.headW * 0.85, d.headW * 0.62, C.METAL_COLLAR, 10, 1, true, Math.PI * 0.62, Math.PI * 1.76); // 세운 재킷 깃 (앞이 트임)
    collar.rotateX(Math.PI / 2);
    const collarM = mesh(collar, black, -0.01, 0, T + C.METAL_COLLAR / 2 - 0.02);
    collarM.material.side = THREE.DoubleSide;
    body.add(collarM);
    for (const side of [-1, 1]) {
      // 어깨 패드: 검정 가죽 반구 + 징 테 + 큰 가시 셋 (가는 몸이라도 어깨 실루엣이 넓게)
      const pad = mesh(domeGeo(C.METAL_PAD_R, 10), black, 0, side * d.shoulderY, T - 0.02);
      pad.scale.set(1.1, 1, 0.75);
      pad.rotation.x = side * -0.45;
      body.add(pad);
      const padRim = mesh(new THREE.TorusGeometry(C.METAL_PAD_R * 1.0, 0.009, 4, 12), stud, 0, side * d.shoulderY, T - 0.02);
      padRim.scale.set(1.1, 1, 1);
      padRim.rotation.x = side * -0.45;
      body.add(padRim);
      for (let k = 0; k < 3; k++) {
        const sp = mesh(new THREE.ConeGeometry(0.022, 0.11 - Math.abs(k - 1) * 0.025, 5), stud, -0.04 + k * 0.04, side * (d.shoulderY + C.METAL_PAD_R * 0.35), T + C.METAL_PAD_R * 0.55);
        sp.rotation.x = side * -0.6;
        body.add(sp);
      }
      for (let k = 0; k < 3; k++) {
        const ang = side * (open / 2 + 0.15);
        const z = T * (0.3 + k * 0.2);
        const r = rz(z) * 1.12;
        body.add(mesh(new THREE.IcosahedronGeometry(0.013, 0), stud, Math.cos(ang) * r * d.depth + 0.005, Math.sin(ang) * r, z));
      }
    }
    for (const [y, z, w, h, mat, rot] of [[0.04, T * 0.6, 0.12, 0.1, red, 0.2], [-0.06, T * 0.36, 0.08, 0.07, blue, -0.3]]) {
      const m = mesh(new THREE.BoxGeometry(0.01, w, h), mat, -rz(z) * d.depth * 1.12 - 0.006, y, z); // 등 천 조각
      m.rotation.x = rot;
      body.add(m);
    }
    body.add(mesh(ringGeo(d.waistR * 1.2, d.waistR * 1.2, 0.05, 10, d.depth), black, 0, 0, 0.06));
    for (let k = 0; k < 6; k++) {
      const a = (k / 6) * Math.PI * 2;
      body.add(mesh(new THREE.IcosahedronGeometry(0.013, 0), stud, Math.cos(a) * d.waistR * 1.2 * d.depth, Math.sin(a) * d.waistR * 1.2, 0.06));
    }
    // 맨팔 (플레이어 색): 근육선 있는 한 덩어리 (둥근 어깨 → 알통이 부푼 위팔 → 가는 팔꿈치 / 팔꿈치 아래 부푼 팔뚝 → 가는 손목). 팔꿈치는 위아래가 겹침
    const A = d.armR;
    const upperGeo = latheLimb(d.upper, [[0, A * 1.5], [0.15, A * 1.75], [0.45, A * 1.85], [0.78, A * 1.3], [1, A * 1.1]], 10, A * 1.1);
    const foreGeo = latheLimb(d.lower, [[0, A * 1.2], [0.2, A * 1.65], [0.5, A * 1.35], [0.85, d.foreR * 1.15], [1, d.foreR * 1.05]], 10, A * 1.0);
    for (let i = 0; i < 2; i++) {
      part(fig.shoulders[i], 'metal').add(mesh(upperGeo, cloth));
      const wrist = part(fig.elbows[i], 'metal');
      wrist.add(mesh(foreGeo, cloth));
      wrist.add(mesh(limbGeo(0.06, d.foreR * 1.6, d.foreR * 1.6, 10), black, 0, 0, -d.lower * 0.72));
      wrist.add(mesh(limbGeo(0.02, d.foreR * 1.65, d.foreR * 1.65, 10), cloth, 0, 0, -d.lower * 0.7)); // 플레이어 색 띠
      for (let k = 0; k < 5; k++) {
        const a = (k / 5) * Math.PI * 2;
        const sp = mesh(new THREE.ConeGeometry(0.012, 0.04, 4), stud, Math.cos(a) * d.foreR * 1.65, Math.sin(a) * d.foreR * 1.65, -d.lower * 0.78);
        sp.lookAt(new THREE.Vector3(Math.cos(a) * 2, Math.sin(a) * 2, -d.lower * 0.78));
        sp.rotateX(Math.PI / 2);
        wrist.add(sp);
      }
    }
    // 찢어진 청바지 (무릎에 빨간 패치) + 검정 장화 빨간 끈
    // 찢어진 스키니 청바지: 허벅지가 무릎으로 가늘어지는 굴곡 (무릎에 찢어진 틈 = 검정 + 실밥 흰 줄) + 두꺼운 밑창 검정 부츠 (빨간 끈) + 허리 체인
    const L = d.legR;
    const thighGeo = latheLimb(d.thigh, [[0, L * 1.35], [0.3, L * 1.3], [0.8, L * 1.08], [1, L * 1.05]], 10, L * 0.8);
    const shinGeo = latheLimb(d.shin * 0.55, [[0, L * 1.08], [0.35, L * 1.15], [1, L * 1.0]], 10, L * 0.9);
    for (let i = 0; i < 2; i++) {
      part(fig.thighs[i], 'metal').add(mesh(thighGeo, blue));
      const kn = part(fig.knees[i], 'metal');
      kn.add(mesh(shinGeo, blue));
      const rip = mesh(new THREE.SphereGeometry(L * 1.0, 10, 6, -0.7, 1.4, 0.9, 1.3), black, 0.006, 0, 0); // 무릎 찢어진 틈 (앞쪽만)
      rip.rotation.x = Math.PI / 2;
      rip.rotation.z = -Math.PI / 2;
      kn.add(rip);
      for (const z of [-0.025, 0.025]) kn.add(mesh(ringGeo(0.004, 0.004, L * 1.4, 4).rotateX(Math.PI / 2), stud, L * 1.06, 0, z)); // 실밥
      const f = part(fig.feet[i], 'metal');
      lump(f, L * 2.3, L * 1.6, d.foot * 1.0, black, L * 0.8, 0, -d.foot * 0.2, 0, 0, 1);
      const sole = mesh(new THREE.CylinderGeometry(1, 1, C.METAL_SOLE, 10).rotateX(Math.PI / 2), black, L * 0.8, 0, -d.foot + C.METAL_SOLE / 2);
      sole.scale.set(L * 2.4, L * 1.7, 1);
      f.add(sole);
      const welt = mesh(new THREE.CylinderGeometry(1, 1, 0.012, 10).rotateX(Math.PI / 2), red, L * 0.8, 0, -d.foot + C.METAL_SOLE + 0.004); // 밑창 위 빨간 줄
      welt.scale.set(L * 2.42, L * 1.72, 1);
      f.add(welt);
      kn.add(mesh(limbGeo(d.shin * 0.62, L * 1.75, L * 1.85, 10), black, 0, 0, -d.shin * 0.4)); // 큰 부츠 목 (가는 다리와 대비)
      for (const z of [0.52, 0.68, 0.84]) kn.add(mesh(ringGeo(L * 1.8 + z * L * 0.12, L * 1.8 + z * L * 0.12, 0.016, 10), stud, 0, 0, -d.shin * z)); // 은색 버클 띠
    }
    for (let k = 0; k < 6; k++) {
      const link = mesh(new THREE.TorusGeometry(0.016, 0.005, 4, 8), stud, -d.waistR * 0.5 * d.depth + k * 0.02, -d.waistR * 1.15, 0.03 - Math.sin((k / 5) * Math.PI) * 0.09);
      link.rotation.x = Math.PI / 2;
      link.rotation.y = k % 2 ? Math.PI / 2 : 0;
      body.add(link); // 허리 체인 (오른쪽 옆구리로 늘어짐)
    }
    part(fig.hips, 'metal').add(mesh(pelvisGeo(d, 1.12, 0.18), blue, 0, 0, 0));
    // 일렉기타: 뾰족한 V 몸통 (빨강 + 검정 테) + 긴 목 + 뾰족 머리 + 줄. 가슴 앞에 비스듬히 (목이 왼쪽 위로)
    const guitar = new THREE.Group();
    for (const side of [-1, 1]) {
      const wing = mesh(new THREE.BoxGeometry(0.03, 0.07, 0.3), red, 0, side * 0.055, -0.1);
      wing.rotation.x = side * 0.45;
      guitar.add(wing);
      const edge = mesh(new THREE.BoxGeometry(0.032, 0.02, 0.3), black, 0, side * 0.09, -0.1);
      edge.rotation.x = side * 0.45;
      guitar.add(edge);
    }
    guitar.add(mesh(new THREE.BoxGeometry(0.032, 0.09, 0.1), red, 0, 0, 0.02));
    guitar.add(mesh(new THREE.BoxGeometry(0.022, 0.04, 0.36), black, 0.005, 0, 0.26));
    const headstock = mesh(new THREE.BoxGeometry(0.022, 0.06, 0.1), red, 0.005, 0.015, 0.47);
    headstock.rotation.x = -0.4;
    guitar.add(headstock);
    for (const y of [-0.012, 0, 0.012]) guitar.add(mesh(new THREE.BoxGeometry(0.004, 0.003, 0.5), stud, 0.02, y, 0.18));
    guitar.position.set(rz(T * 0.4) * d.depth * 1.12 + 0.06, 0.02, T * 0.4);
    guitar.rotation.x = -0.95;
    body.add(guitar);
    fig.guitar = guitar;
  }
  fig.forms = forms;
  fig.form = null;
  fig.formAt = -1e9;
  fig.setForm = (form) => {
    if (form !== 'metal') form = 'bard';
    if (fig.form === form) return;
    const first = fig.form === null;
    fig.form = form;
    fig.formAt = first ? -1e9 : performance.now(); // 처음엔 연출 없이
    for (const [k, grp] of Object.entries(forms)) for (const g of grp.userData.parts) g.visible = k === form;
    fig.torso.material = torsoMat[form]; // 몸통 = 튜닉 리넨 / 검정 티 (맨살 몸통이 옷 틈으로 안 보이게)
  };
  fig.setForm('bard');
}

// ---------- 동작 ----------
// 관절마다 목표 각도를 정하고 스프링(FIGURE_SPRING)으로 따라감 → 살짝 늦게, 살짝 넘치며 따라와 흐느적거림 (TABS 느낌)
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
    shTwist: [0, 0],
    elbow: [0.15, 0.15],
    thFwd: [(d.bend || 0) * 0.5, (d.bend || 0) * 0.5],
    thOut: [0, 0],
    knee: [d.bend || 0, d.bend || 0],
  };
}

// 관절 무리별 스프링 (FIGURE_SPRING: w 빠르기 /초, damp 감쇠비 — 1 이면 안 넘침, 작을수록 출렁)
const SPRING_GROUP = { waistPitch: 'body', waistRoll: 'body', waistSide: 'body', hipsZ: 'body', neckPitch: 'neck', shFwd: 'arm', shOut: 'arm', shTwist: 'arm', elbow: 'arm', thFwd: 'leg', thOut: 'leg', knee: 'leg' };
function zeroPose(P) {
  const V = {};
  for (const [k, v] of Object.entries(P)) V[k] = Array.isArray(v) ? v.map(() => 0) : 0;
  return V;
}
// P 를 T 쪽으로 스프링으로 (속도 V). 작은 걸음으로 나눠 안정하게
function springPose(P, V, T, dt, fast = 1) {
  const n = Math.max(1, Math.ceil(dt / C.FIGURE_SPRING_STEP));
  const h = dt / n;
  for (const key of Object.keys(T)) {
    if (!(key in V)) V[key] = Array.isArray(T[key]) ? T[key].map(() => 0) : 0;
    const sp = C.FIGURE_SPRING[SPRING_GROUP[key] || 'body'];
    const w = sp.w * fast;
    const kk = w * w;
    const c = 2 * sp.damp * w;
    const one = (x, v, tg) => {
      for (let j = 0; j < n; j++) {
        v += (kk * (tg - x) - c * v) * h;
        x += v * h;
      }
      return [x, v];
    };
    if (Array.isArray(T[key])) {
      for (let i = 0; i < T[key].length; i++) [P[key][i], V[key][i]] = one(P[key][i], V[key][i], T[key][i]);
    } else [P[key], V[key]] = one(P[key], V[key], T[key]);
  }
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
// 공격 자세는 스프링을 건너뛰고 바로 그 자세 (속은 격투), 끝나면 평소처럼 흐물흐물 돌아옴 (겉은 병맛).
// 자세 칸: 허리 waistPitch(앞 숙임)·waistRoll(왼쪽으로 비틂 = 오른 어깨 앞)·waistSide, 고개 neckPitch,
// 팔다리 [오른쪽, 왼쪽] (null = 그대로): shFwd(앞으로 듦)·shOut(옆으로 벌림)·shTwist(팔 비틂, + 면 굽힌 팔이 안쪽으로)·elbow·thFwd·knee, crouch(0~1 두 무릎 굽힘)
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
  // 공중 베기: 웅크린 채 오른손 단검을 머리 위로 → 몸을 비틀며 앞아래로 사선 베기
  '공중 베기': {
    W: { shFwd: [2.8, 0.3], shOut: [0.5, 1.0], elbow: [0.6, 0.6], waistRoll: -0.45, waistPitch: -0.15, thFwd: [1.1, 0.6], knee: [1.7, 1.2] },
    S: { shFwd: [0.5, 0.6], shOut: [0.7, 1.1], elbow: [0, 0.6], waistRoll: 0.55, waistPitch: 0.35, thFwd: [0.7, 1.1], knee: [1.3, 1.6] },
  },
  // 내려 차기 (마무리, 도끼 차기): 오른다리를 머리 위까지 번쩍 + 두 팔 위로 → 다리를 앞아래로 내리찍으며 몸을 접음, 왼무릎은 접은 채
  '내려 차기': {
    W: { thFwd: [2.7, 0.3], knee: [0, 1.4], waistPitch: -0.5, neckPitch: -0.2, shFwd: [2.4, 2.4], shOut: [0.8, 0.8], elbow: [0.3, 0.3] },
    S: { thFwd: [0.5, 0.6], knee: [0, 1.5], waistPitch: 0.55, neckPitch: 0.25, shFwd: [-0.5, -0.5], shOut: [1.1, 1.1], elbow: [0.2, 0.2] },
  },
  // 공중 표창 (R 강화): 두 손을 반대 어깨로 모아 웅크렸다가 앞아래로 뿌림 (둘째 발은 표창2 왼손)
  '공중 표창': {
    W: { shFwd: [1.0, 1.0], shOut: [-0.25, -0.25], elbow: [2.2, 2.2], waistPitch: 0.2, thFwd: [1.2, 0.8], knee: [1.8, 1.4] },
    S: { shFwd: R(1.0), shOut: R(0.5), elbow: R(0), waistRoll: 0.45, waistPitch: 0.35, thFwd: [0.8, 1.1], knee: [1.2, 1.6] },
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

  // 사냥꾼: 사냥칼 베기 → 반대 베기 → 찔러 넣기 (마무리, 표식). 공중 내려 베기
  '베기': { W: { shOut: R(1.4), shFwd: R(0.2), elbow: R(1.0), waistRoll: -0.6, crouch: 0.3 }, S: { shOut: R(0.15), shFwd: R(1.5), elbow: R(0.1), waistRoll: 0.5, waistPitch: 0.2 } },
  '반대 베기': { W: { shOut: R(-0.3), shFwd: R(1.3), elbow: R(1.7), waistRoll: 0.6, crouch: 0.3 }, S: { shOut: R(1.5), shFwd: R(0.7), elbow: R(0.1), waistRoll: -0.55, waistPitch: 0.2 } },
  // 찔러 넣기: 칼을 허리로 당기고 왼손을 앞에 겨눴다가 → 왼발 내딛으며 쭉 찌름 (후딜 김)
  '찔러 넣기': {
    W: { shFwd: [0.1, 1.1], shOut: [0.7, 0.2], elbow: [2.3, 0.3], waistRoll: -0.75, waistPitch: -0.1, crouch: 0.5, neckPitch: 0.1 },
    S: { shFwd: [1.6, -0.4], shOut: [0.05, 0.6], elbow: [0, 0.6], waistRoll: 0.45, waistPitch: 0.45, thFwd: [-0.35, 1.0], knee: [0.2, 0.9] },
  },
  '내려 베기': {
    W: { shFwd: R(2.9), shOut: R(0.3), elbow: R(0.8), waistPitch: -0.3, thFwd: [1.0, 0.6], knee: [1.6, 1.2] },
    S: { shFwd: R(0.5), shOut: R(0.2), elbow: R(0.05), waistPitch: 0.6, thFwd: [0.7, 1.0], knee: [1.2, 1.5] },
  },

  // 대포수: 탄이 있으면 포탄 (어깨 대포를 겨누듯 몸을 낮추고 → 쾅, 쏜 뒤는 반동 동작 cannonRecoil 이 이어받음), 없으면 대포째 후려치기 (허리를 크게 틀어 어깨 대포로)
  '포탄': { W: { crouch: 0.35, waistPitch: 0.15, neckPitch: -0.1, shOut: [1.75, 0.6], shFwd: [0.25, 0.9], elbow: [1.7, 1.2] }, S: { crouch: 0.2, waistPitch: -0.2, shOut: [1.75, 0.8], shFwd: [0.25, 0.6], elbow: [1.7, 0.9] } },
  '후려치기': {
    W: { waistRoll: 1.0, waistSide: 0.15, crouch: 0.4, shOut: [1.75, 1.0], shFwd: [0.25, -0.4], elbow: [1.7, 0.8] },
    S: { waistRoll: -0.9, waistPitch: 0.35, waistSide: -0.2, shOut: [1.75, 1.2], shFwd: [0.25, 0.6], elbow: [1.7, 0.4], thFwd: [-0.3, 0.6] },
  },

  // 광전사: 큰 도끼. 가로 베기 (오른쪽 뒤로 크게 젖혔다 120° 휩쓸기) → 내려찍기 (건축가 것과 같은 두 손 내려찍기) / 공중 회전 베기 (팔 뻗고 한 바퀴)
  '가로 베기': {
    W: { shOut: [1.6, 0.6], shFwd: [-0.3, 0.9], elbow: [0.4, 1.0], waistRoll: -1.1, waistSide: 0.15, crouch: 0.4 },
    S: { shOut: [0.3, 0.9], shFwd: [1.5, 0.3], elbow: [0.1, 0.6], waistRoll: 1.0, waistPitch: 0.25, thFwd: [-0.2, 0.5] },
  },
  '회전 베기': { W: { shOut: [1.5, 1.3], shFwd: [0.2, 0.2], elbow: [0.2, 0.3], waistRoll: 0.7, thFwd: [1.0, 0.7], knee: [1.4, 1.1] }, S: { shOut: [1.55, 1.4], shFwd: [0.3, 0.2], elbow: [0.05, 0.3], waistRoll: 0, thFwd: [0.8, 0.9], knee: [1.2, 1.3] }, spin: -Math.PI * 2 },

  // 바드 음유시인: 류트 음파 (오른손을 높이 들었다 줄을 확 긁어내림) / 공중 천천히 낙하 (팔 벌리고 빙글: glide 상태가 따로 돌림)
  '류트 음파': { W: { shFwd: [1.6, 0.75], shOut: [0.6, 0.05], elbow: [1.2, 1.45], waistRoll: -0.25, neckPitch: -0.15 }, S: { shFwd: [0.35, 0.75], shOut: [0.2, 0.05], elbow: [1.7, 1.45], waistRoll: 0.2, waistPitch: 0.15, neckPitch: 0.1 } },
  '천천히 낙하': { W: { shOut: [1.2, 1.2], shFwd: [0.4, 0.4], elbow: [0.3, 0.3] }, S: { shOut: [1.45, 1.45], shFwd: [0.2, 0.2], elbow: [0.2, 0.2], thFwd: [0.3, 0.3], knee: [0.5, 0.5] }, rec: 0.3 },
  // 바드 메탈: 가슴의 기타째 몸을 크게 틀어 후려치기 → 두 손 머리 위로 들어 내려치기 / 공중: 거꾸로 곤두박질치며 아래로 꽂기
  '기타 후려치기': {
    W: { waistRoll: -1.0, waistSide: 0.15, crouch: 0.35, shFwd: [0.4, 1.0], shOut: [0.9, 0.2], elbow: [1.4, 1.3] },
    S: { waistRoll: 0.9, waistPitch: 0.3, shFwd: [1.2, 0.8], shOut: [0.3, 0.5], elbow: [0.6, 0.9], thFwd: [-0.2, 0.5] },
  },
  '기타 내려치기': {
    W: { shFwd: [3.0, 3.0], shOut: [0.15, 0.15], elbow: [0.6, 0.6], waistPitch: -0.45, neckPitch: -0.3 },
    S: { shFwd: [0.6, 0.6], shOut: [0.1, 0.1], elbow: [0.05, 0.05], waistPitch: 0.85, neckPitch: 0.25, crouch: 0.8 },
  },
  '기타 꽂기': {
    W: { shFwd: [2.8, 2.8], elbow: [0.5, 0.5], waistPitch: -0.4, thFwd: [1.3, 1.3], knee: [1.6, 1.6] },
    S: { shFwd: [1.4, 1.4], shOut: [0.1, 0.1], elbow: [0.1, 0.1], waistPitch: 1.35, neckPitch: 0.4, thFwd: [-0.7, -0.5], knee: [0.3, 0.5] },
  },

  // ---- 스킬·필살기 ----
  // 바드 폼 전환: 메탈 = 기타를 머리 위로 치켜들고 리프 (충격파) / 음유 = 류트를 가슴에 안고 두 팔 벌려 치유
  bardRiff: { S: { shFwd: [2.6, 2.4], shOut: [0.5, 0.5], elbow: [0.4, 0.5], waistPitch: -0.4, neckPitch: -0.5, thOut: [0.35, 0.35], crouch: 0.3 }, rec: 0.6 },
  bardHeal: { S: { shOut: [1.7, 1.7], shFwd: [0.6, 0.6], elbow: [0.2, 0.2], waistPitch: -0.2, neckPitch: -0.35 }, rec: 0.6 },
  // 음유 R 취약의 노래: 류트를 앞으로 내밀며 크게 한 번 긁음
  bardSong: { S: { shFwd: [0.6, 1.4], shOut: [0.3, 0.0], elbow: [1.4, 0.6], waistPitch: 0.2, waistRoll: 0.3, neckPitch: -0.2 }, rec: 0.7 },
  // 광전사 F 광폭 도약: 도끼를 두 손으로 머리 위로 치켜들고 무릎 접어 날아감 (rush) → 착지하며 쾅 내려찍기 (rushLand)
  berserkerLeap: { S: { shFwd: [2.9, 2.9], shOut: [0.25, 0.25], elbow: [0.5, 0.5], waistPitch: -0.35, neckPitch: -0.3, thFwd: [1.3, 0.6], knee: [1.6, 1.0] }, rec: 0.6, float: true },
  berserkerSlam: { S: { shFwd: [0.5, 0.5], shOut: [0.15, 0.15], elbow: [0.05, 0.05], waistPitch: 0.85, neckPitch: 0.2, crouch: 0.9 }, rec: 0.55 },
  // 대포수 반동 (땅): 엉덩방아 — 다리가 앞으로 쭉 뻗으며 엉덩이부터 털썩, 몸은 뒤로 젖히고 왼팔 허우적 (대포는 어깨에 그대로)
  cannonRecoil: { S: { thFwd: [1.45, 1.35], knee: [0.15, 0.3], waistPitch: -0.55, neckPitch: 0.35, shOut: [1.75, 1.6], shFwd: [0.25, 1.2], elbow: [1.7, 0.4] }, rec: 0.6 },
  // R 대형 포탄 반동: 더 크게 — 뒤로 벌러덩 (다리가 하늘로)
  cannonBigRecoil: { S: { thFwd: [2.0, 1.8], knee: [0.1, 0.5], waistPitch: -1.0, neckPitch: 0.5, shOut: [1.75, 2.2], shFwd: [0.25, 1.6], elbow: [1.7, 0.2] }, rec: 0.9 },
  // F 발밑 포격: 대포를 발밑으로 쾅 쏴서 튀어 오름 — 웅크렸다가 다리를 쫙 펴고 만세
  cannonJump: { S: { thFwd: [0.2, 0.2], thOut: [0.5, 0.5], knee: [0.1, 0.1], waistPitch: -0.2, neckPitch: -0.3, shOut: [1.75, 2.4], shFwd: [0.25, 0.3], elbow: [1.7, 0.2] }, rec: 0.6, float: true },
  // 사냥꾼 추적 도약: 네 발로 엎드려 웅크렸다가 (leapWarn) → 두 팔을 앞으로 뻗고 다리는 뒤로, 짐승처럼 덮침 (leap)
  hunterLeap: {
    W: { waistPitch: 1.15, shFwd: [1.25, 1.25], shOut: [0.3, 0.3], elbow: [0.2, 0.2], crouch: 1, neckPitch: -0.95 },
    S: { waistPitch: 0.35, shFwd: [2.3, 2.3], shOut: [0.45, 0.45], elbow: [0.6, 0.6], thFwd: [-0.7, -0.4], knee: [0.9, 1.1], neckPitch: -0.45 },
    rec: 0.5,
    float: true,
  },
  // 사냥꾼 처형 사격: 등의 석궁을 꺼내 어깨에 대고 겨눔 (aim, 0.5초) → 쏘는 반동으로 몸이 젖혀짐 (shot)
  hunterAim: {
    W: { shFwd: [1.4, 1.55], shOut: [-0.15, 0.05], elbow: [1.0, 0.35], waistRoll: 0.15, neckPitch: 0.1 },
    S: { shFwd: [1.7, 1.85], shOut: [-0.1, 0.1], elbow: [1.15, 0.55], waistPitch: -0.35, neckPitch: -0.15, thFwd: [-0.25, 0.35] },
    rec: 0.5,
    bow: true,
  },

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

// ---------- 도발·승리 포즈 (스매시식) ----------
// 캐릭터(바드는 폼)마다 taunt = 이모트 바퀴 전용 칸(C.EMOTE_CHAR), victory = 판 끝 승자. 준비 W 로 모였다가 → 결정 포즈 S 에 딱 멈추고
// → loop(초) 가 S 위에 작은 반복을 얹음 (끝나지 않는 승리 포즈도 살아 있게). 도발은 이모트 끝나기 전에 풀려 돌아옴. 자세 칸은 MOVES 와 같음
// shield: 그동안 탱크 방패를 몸 앞에
const wob = (t, hz, a) => Math.sin(t * hz * Math.PI * 2) * a;
export const POSES = {
  tank: {
    taunt: { W: { shFwd: [1.2, 1.3], elbow: [1.6, 1.5], crouch: 0.5, waistPitch: 0.25 }, S: { shFwd: [1.0, 1.25], shOut: [0.1, 0.05], elbow: [1.9, 1.45], crouch: 0.4, waistPitch: 0.15, neckPitch: -0.1 }, loop: (t) => ({ shFwd: R(0.9 + Math.max(0, wob(t, 2.2, 0.6))), elbow: R(1.9 - Math.max(0, wob(t, 2.2, 0.7))) }), shield: true },
    victory: { W: { crouch: 0.4, waistPitch: 0.2, shFwd: [0.6, 0.6] }, S: { shFwd: [1.1, 1.1], shOut: [0.15, 0.15], shTwist: [1.4, 1.4], elbow: [1.75, 1.75], waistPitch: -0.2, neckPitch: -0.5, thOut: [0.18, 0.18] }, loop: (t) => ({ neckPitch: -0.5 + Math.max(0, wob(t, 0.9, 0.2)) }) }, // 팔짱 (방패는 등에), 턱 높이 들고 끄덕
  },
  ninja: {
    taunt: { W: { crouch: 0.6, shFwd: [0.4, 0.4], shOut: [0.6, 0.6], elbow: [1.2, 1.2] }, S: { shFwd: [1.15, 1.15], shOut: [-0.4, -0.4], elbow: [1.95, 1.95], thFwd: [1.2, 0], knee: [1.9, 0.15], neckPitch: 0.15, waistPitch: 0.1 }, loop: (t) => ({ elbow: [1.95 + wob(t, 3, 0.08), 1.95 - wob(t, 3, 0.08)] }) },
    victory: { W: { crouch: 0.7, shFwd: [-0.4, -0.4], shOut: [0.5, 0.5] }, S: { thFwd: [-0.05, 1.55], knee: [1.65, 1.7], shFwd: [0.9, 0.9], shOut: [0.1, 0.1], shTwist: [1.2, 1.2], elbow: [1.9, 1.9], waistPitch: 0.12, neckPitch: 0.3 }, loop: (t) => ({ neckPitch: 0.3 + wob(t, 0.5, 0.05) }) }, // 오른 무릎을 땅에 꿇고 왼발 앞, 두 단검 가슴 앞 X자
  },
  builder: {
    taunt: { W: { shFwd: [1.5, -0.2], elbow: [1.2, 1.4], crouch: 0.3 }, S: { shFwd: [0.3, -0.35], shOut: [0.5, 0.8], elbow: [2.45, 2.0], waistSide: -0.12, neckPitch: -0.1 }, loop: (t) => ({ neckPitch: -0.1 + Math.max(0, wob(t, 1.6, 0.25)) }) },
    victory: { W: { crouch: 0.5, shFwd: [0.5, 0.5], elbow: [1.5, 1.5] }, S: { shFwd: [3.0, 1.05], shOut: [0.3, 0.1], elbow: [0.2, 1.7], waistPitch: -0.15, neckPitch: -0.3, thOut: [0.12, 0.12] }, loop: (t) => ({ shFwd: R(2.85 + wob(t, 1.4, 0.18)), elbow: R(0.25 - wob(t, 1.4, 0.15)) }) },
  },
  hook: {
    taunt: { W: { shFwd: [0.2, 0.8], elbow: [1.2, 1.4], waistRoll: 0.1 }, S: { shFwd: [-0.35, 1.35], shOut: [0.75, 0.05], elbow: [2.0, 0.9], waistRoll: 0.25, waistPitch: -0.12, neckPitch: -0.2 }, loop: (t) => ({ elbow: L(1.0 + Math.max(0, wob(t, 2.4, 0.75))) }) },
    victory: { W: { crouch: 0.4, shFwd: [0.4, 0.2] }, S: { shFwd: [2.95, -0.35], shOut: [0.25, 0.75], elbow: [0.15, 2.0], thFwd: [0, 1.15], knee: [0, 1.25], waistPitch: -0.12, neckPitch: -0.3 }, loop: (t) => ({ shFwd: R(2.95 + wob(t, 0.8, 0.12)) }) },
  },
  hunter: {
    taunt: { W: { crouch: 0.45, waistPitch: 0.45, neckPitch: 0.35, shFwd: [0.3, 0.3] }, S: { shFwd: [1.6, 0.2], shOut: [0.05, 0.4], elbow: [0, 0.5], waistRoll: 0.35, waistPitch: 0.15, thFwd: [0.5, -0.2], neckPitch: -0.1 }, loop: (t) => ({ shFwd: R(1.6 + wob(t, 3, 0.05)) }) },
    victory: { W: { crouch: 0.5, waistPitch: 0.3 }, S: { shFwd: [2.5, 0.4], shOut: [0, 0.25], shTwist: [0.6, 0], elbow: [1.6, 1.2], crouch: 0.35, waistPitch: 0.45, neckPitch: -0.55, thFwd: [0.75, -0.15] }, loop: (t) => ({ waistRoll: wob(t, 0.35, 0.35) }) }, // 손바닥을 이마에 대고 몸을 앞으로 내밀어 먼 곳을 살핌
  },
  cannon: {
    taunt: { W: { crouch: 0.5, waistPitch: 0.25, shFwd: [0.25, 0.6], elbow: [1.7, 1.6] }, S: { waistPitch: -0.45, neckPitch: 0.2, shFwd: [0.25, 0.2], shOut: [1.75, 2.5], elbow: [1.7, 0.4], thFwd: [0.35, -0.15] }, loop: (t) => ({ shOut: [1.75, 2.5 + Math.max(0, wob(t, 2.5, 0.35))] }) },
    victory: { W: { crouch: 0.3, waistPitch: 0.2 }, S: { waistPitch: -0.35, neckPitch: -0.3, shFwd: [0.25, 0.55], shOut: [1.75, -0.1], elbow: [1.7, 1.75], thOut: [0.2, 0.2] }, loop: (t) => ({ waistPitch: -0.35 + Math.abs(wob(t, 2.2, 0.12)), neckPitch: -0.3 - Math.abs(wob(t, 2.2, 0.12)) }) },
  },
  berserker: {
    taunt: { W: { crouch: 0.6, waistPitch: 0.45, shFwd: [0.5, 0.5], shOut: [0.6, 0.6], elbow: [1.6, 1.6] }, S: { shOut: [1.3, 1.3], shFwd: [0.45, 0.45], elbow: [1.6, 1.6], thOut: [0.32, 0.32], crouch: 0.45, waistPitch: -0.25, neckPitch: -0.55 }, loop: (t) => ({ elbow: [1.6 + wob(t, 9, 0.07), 1.6 - wob(t, 9, 0.07)], neckPitch: -0.55 + wob(t, 7, 0.04) }) },
    victory: { W: { crouch: 0.6, waistPitch: 0.4, shFwd: [0.6, 0.6], elbow: [1.5, 1.5] }, S: { shFwd: [3.0, 0.35], shOut: [0.25, 1.35], elbow: [0.25, 1.9], thOut: [0.3, 0.3], crouch: 0.35, waistPitch: -0.25, neckPitch: -0.5 }, loop: (t) => ({ shFwd: R(2.9 + Math.max(0, wob(t, 1.2, 0.2))), elbow: L(1.9 + wob(t, 8, 0.06)), neckPitch: -0.5 + wob(t, 6, 0.04) }) },
  },
  bard: {
    taunt: { W: { shFwd: [2.7, 0.75], shOut: [0.35, 0.05], elbow: [2.1, 1.45], waistPitch: -0.15, neckPitch: -0.1 }, S: { shFwd: [0.75, -0.55], shOut: [1.35, 0.75], elbow: [0.2, 0.25], waistPitch: 1.0, neckPitch: 0.1, thFwd: [-0.8, 0.45], knee: [0.35, 0.55] }, loop: (t) => ({ elbow: R(0.2 + Math.max(0, wob(t, 1.5, 0.35))) }) }, // 모자 벗듯 손을 머리에 → 한 발 뒤로 빼고 깊이 숙이며 팔을 옆으로 크게 쓸어 인사
    victory: { W: { shFwd: [0.45, 0.75], shOut: [0.3, 0.05], elbow: [1.6, 1.45], crouch: 0.4 }, S: { shFwd: [0.55, 1.3], shOut: [0.5, 0.1], elbow: [1.5, 0.8], waistPitch: -0.7, waistRoll: 0.3, neckPitch: -0.4, thFwd: [-0.35, 0.6], knee: [0.15, 0.55] }, loop: (t) => ({ shFwd: R(0.55 + wob(t, 4, 0.35)), elbow: R(1.5 + wob(t, 4, 0.6)), waistPitch: -0.7 + Math.abs(wob(t, 1, 0.15)), neckPitch: -0.4 - Math.abs(wob(t, 1, 0.25)), waistSide: wob(t, 0.5, 0.12) }) }, // 뒤로 젖혀 류트를 치켜들고 독주: 한 발 앞, 긁는 손 크게
  },
  metal: {
    taunt: { W: { shFwd: [0.45, 0.75], elbow: [1.6, 1.45], crouch: 0.3 }, S: { shFwd: [2.9, 0.75], shOut: [0.25, 0.05], elbow: [0.25, 1.45], thOut: [0.3, 0.3], crouch: 0.3, waistPitch: -0.2, neckPitch: -0.3 }, loop: (t) => ({ neckPitch: -0.3 + Math.max(0, wob(t, 2.5, 0.7)), waistPitch: -0.2 + Math.max(0, wob(t, 2.5, 0.2)) }) },
    victory: { W: { crouch: 0.6, shFwd: [0.45, 0.75], elbow: [1.6, 1.45] }, S: { thFwd: [1.3, -0.45], knee: [1.5, 2.1], shFwd: [0.45, 0.75], shOut: [0.3, 0.05], elbow: [1.6, 1.45], waistPitch: -0.45, neckPitch: -0.5 }, loop: (t) => ({ elbow: R(1.6 + wob(t, 7, 0.3)), neckPitch: -0.5 + Math.max(0, wob(t, 2.2, 0.75)) }) },
  },
};

// 도발·승리 포즈 시간 축: t = 시작부터 초, end = 끝나는 초 (승리는 Infinity = 결정 포즈 유지)
function poseAt(P, T, V, set, t, end) {
  const tin = C.POSE_IN_S;
  const tsnap = tin + C.POSE_SNAP_S;
  if (t < tin) return overlay(P, T, set.W, ease(t / tin), V);
  const S = set.loop && t >= tsnap ? { ...set.S, ...mergeSides(set.S, set.loop(t - tsnap)) } : set.S;
  const out = Number.isFinite(end) ? 1 - ease((t - (end - C.POSE_OUT_S)) / C.POSE_OUT_S) : 1;
  if (t < tsnap) {
    const u = (t - tin) / C.POSE_SNAP_S;
    overlay(P, T, set.W, 1 - u, V);
    overlay(P, T, S, ease(u), V);
  } else overlay(P, T, S, Math.min(1, out), V);
}
// loop 의 [값, null] (한쪽만) 이 S 의 다른 쪽을 지우지 않게
function mergeSides(S, add) {
  const out = {};
  for (const [k, v] of Object.entries(add)) out[k] = Array.isArray(v) && Array.isArray(S[k]) ? v.map((x, i) => (x === null ? S[k][i] : x)) : v;
  return out;
}

// 공격 자세를 P 에 바로 덮어씀 (w = 0~1 섞는 정도). 값은 절대 각 (매 프레임 쌓이지 않게).
// crouch 는 이번 프레임 목표 자세 T 의 다리에서 두 무릎을 더 굽힌 각 (다리 각을 직접 준 동작은 그쪽이 이김)
// V = 관절 스프링 속도: 덮어쓴 만큼 줄임 (자세를 붙잡는 동안 스프링 속도가 쌓였다가 끝날 때 팔이 튕겨 나가지 않게)
function overlay(P, T, pose, w, V) {
  if (!pose || w <= 0) return;
  const keep = 1 - Math.min(1, w);
  if (pose.crouch) {
    for (let i = 0; i < 2; i++) {
      P.thFwd[i] += (T.thFwd[i] + 0.9 * pose.crouch - P.thFwd[i]) * w;
      P.knee[i] += (T.knee[i] + 1.6 * pose.crouch - P.knee[i]) * w;
      if (V) {
        V.thFwd[i] *= keep;
        V.knee[i] *= keep;
      }
    }
  }
  for (const [key, val] of Object.entries(pose)) {
    if (val === null || val === undefined || !(key in P)) continue;
    if (Array.isArray(val)) {
      val.forEach((v, i) => {
        if (v === null) return;
        P[key][i] += (v - P[key][i]) * w;
        if (V) V[key][i] *= keep;
      });
    } else {
      P[key] += (val - P[key]) * w;
      if (V) V[key] *= keep;
    }
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
  if (st.bump && st.bump.id !== sw.bumpId && finite(st.bump.dx, st.bump.dy, st.bump.pow)) {
    // 벽·몸에 부딪힘: 휘청 스프링에 튕김만 얹음 (맞음보다 작게, 멈칫 없음)
    sw.bumpId = st.bump.id;
    if (!st.stunned) {
      sw.vx += st.bump.dx * C.FIGURE_BUMP.kick * Math.min(st.bump.pow, C.MOVE_SPEED * 1.5);
      sw.vy += st.bump.dy * C.FIGURE_BUMP.kick * Math.min(st.bump.pow, C.MOVE_SPEED * 1.5);
    }
  }
  const frozen = !!hit && hit.age < hit.stop; // 히트스톱: 맞은 자세로 멈춤
  if (!frozen) stepSway(sw, dt);

  if (st.walking) {
    gaitPose(T, d, st, gaitOf(fig.char));
  } else {
    T.waistPitch = d.hunch + Math.sin(t * 2) * 0.02; // 숨쉬기
    T.shOut = T.shOut.map((o, i) => o + Math.sin(t * 1.7 + i) * 0.03);
    if (fig.sniff && !st.act) {
      // 사냥꾼 킁킁: 몇 초마다 고개를 내밀고 빠르게 까딱 (냄새 맡기). 표식 대상이 있으면 더 자주, 그쪽으로 몸을 틀어 (사냥개 흉내)
      const target = Number.isFinite(st.sniffAt);
      const every = target ? C.FIGURE_SNIFF_EVERY / 2 : C.FIGURE_SNIFF_EVERY;
      const ph = t % every;
      const on = ph < C.FIGURE_SNIFF_LEN ? Math.sin((Math.PI * ph) / C.FIGURE_SNIFF_LEN) : 0;
      T.neckPitch += on * (0.25 + Math.sin(t * 38) * 0.12);
      T.waistPitch += on * 0.12;
      if (target) T.waistRoll += Math.max(-1, Math.min(1, st.sniffAt)) * 0.7;
    }
  }
  if (st.air) airPose(T, d, st, t, !!st.act && st.act.phase !== 'broken');
  if (st.airDash > 0 && !st.stunned) overlayT(T, SUPERMAN, Math.min(1, st.airDash * 4)); // 공중 대시: 한 팔 앞으로 쭉, 다리 뒤로 (끝에서 풀림)
  if (!st.stunned && !(st.flip >= 0)) accLean(T, st);
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
  if (fig.axe && !st.stunned && !st.act && st.emote < 0 && !st.air && !(st.whirl >= 0) && !(st.dizzy > 0)) {
    // 도끼를 어깨에 걸침: 오른팔꿈치를 접어 자루가 어깨 위로 넘어감
    T.shFwd[0] = 0.35;
    T.shOut[0] = 0.55;
    T.elbow[0] = 1.95;
  }
  if (fig.forms && !st.stunned && !st.act && st.emote < 0 && (!st.air || st.amp) && !st.glide) {
    // 바드: 악기를 가슴 앞에 들고 (왼손 목, 오른손 줄). 메탈은 대기 중 헤드뱅잉
    T.shFwd = [0.45, 0.75];
    T.shOut = [0.3, 0.05];
    T.elbow = [1.6, 1.45];
    if (st.amp) {
      // 앰프 연주: 다리 벌리고 버팀 + 미친 듯이 줄 긁기 + 크게 헤드뱅잉
      const bang = Math.max(0, Math.sin(t * C.BARD_HEADBANG_HZ * 1.6 * Math.PI * 2));
      T.neckPitch += bang * 0.8 - 0.2;
      T.waistPitch += bang * 0.2 + 0.1;
      T.elbow[0] += Math.sin(t * 30) * 0.35;
      T.thOut = [0.35, 0.35];
      T.knee = T.knee.map((v) => v + 0.35);
      T.thFwd = T.thFwd.map((v) => v + 0.2);
    } else if (fig.form === 'metal' && !st.walking) {
      const bang = Math.max(0, Math.sin(t * C.BARD_HEADBANG_HZ * Math.PI * 2));
      T.neckPitch += bang * 0.55 - 0.1;
      T.waistPitch += bang * 0.12;
      T.elbow[0] += Math.sin(t * C.BARD_HEADBANG_HZ * Math.PI * 4) * 0.25; // 줄 긁기
    }
  }
  if (st.dizzy > 0 && !st.stunned) {
    // 소용돌이 끝: 어지러워 비틀 — 허리·고개가 느리게 휘청, 무릎 풀리고 팔은 허우적
    const z = Math.min(1, st.dizzy * 1.5);
    T.waistSide += Math.sin(t * 4.5) * 0.35 * z;
    T.waistRoll += Math.sin(t * 2.9) * 0.4 * z;
    T.neckPitch += Math.sin(t * 3.7) * 0.3 * z - 0.15 * z;
    T.knee = T.knee.map((v, i) => v + (0.45 + Math.sin(t * 4.5 + i * 2) * 0.25) * z);
    T.thFwd = T.thFwd.map((v) => v + 0.25 * z);
    T.shOut = T.shOut.map((v, i) => v + (0.7 + Math.sin(t * 6 + i * 1.7) * 0.4) * z);
    T.elbow = T.elbow.map((v) => v + 0.4 * z);
  }
  if (fig.cannon) {
    // 쏜 순간 대포가 어깨 위에서 뒤로 툭 밀렸다 돌아옴
    const k = fig.cannonKickAt ? Math.max(0, 1 - (performance.now() - fig.cannonKickAt) / (C.CANNON_KICK_MS || 1)) : 0;
    fig.cannon.position.x = (fig.cannonBaseX ??= fig.cannon.position.x) - C.CANNON_KICK * k * k;
  }
  if (fig.cannon && !st.stunned && st.emote < 0) {
    // 대포를 어깨에 멘 자세: 오른손은 어깨 위 대포를 받치고, 왼손은 허리에 척 (걸으면 왼팔만 흔들림)
    T.shFwd[0] = 0.25;
    T.shOut[0] = 1.75;
    T.elbow[0] = 1.7;
    if (!st.walking) {
      T.shFwd[1] = -0.35;
      T.shOut[1] = 0.75;
      T.elbow[1] = 2.0;
    }
  }
  if (fig.gun?.loaded && !st.stunned && !st.air && st.emote < 0) {
    // 장전된 권총을 든 오른손: 팔꿈치를 굽혀 총을 앞으로 (걸을 땐 흔들림 반만)
    T.elbow[0] = 1.5;
    T.shFwd[0] = st.walking ? 0.2 + T.shFwd[0] * 0.3 : 0.25;
    T.shOut[0] = 0.15;
  }
  if (st.idle > C.FIGURE_IDLE_AFTER && !st.walking && !st.air && !st.stunned && !st.act && !st.dancing && st.emote < 0 && !(st.victory >= 0) && !st.holding && !(st.dizzy > 0) && !st.amp) {
    // 평소 버릇: 가만히 있으면 몇 초마다 캐릭터별 짧은 동작
    const hb = C.FIGURE_IDLE[fig.char];
    const ph = hb ? (st.idle - C.FIGURE_IDLE_AFTER) % hb.every : -1;
    if (hb && ph < hb.len) idlePose(T, hb.kind, ph / hb.len, ph, fig.form);
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

  // 따라가기: 관절마다 스프링 (살짝 넘쳤다 돌아옴). 팔·고개는 느슨해서 몸보다 늦게 따라옴 (follow-through)
  // 처음엔 바로 그 자세, 히트스톱도 바로 그 자세로 멈칫
  const P = fig.pose || (fig.pose = restPose(d));
  if (!fig.poseV || !poseOk(fig.poseV)) fig.poseV = zeroPose(P);
  const V = fig.poseV;
  if (frozen) {
    for (const key of Object.keys(T)) {
      P[key] = Array.isArray(T[key]) ? [...T[key]] : T[key];
      V[key] = Array.isArray(T[key]) ? T[key].map(() => 0) : 0;
    }
  } else {
    // 몸이 빨라지면 팔·고개가 뒤로 처지고 멈추면 앞으로 쏠림, 옆으로 꺾으면 반대쪽으로 (몸 기준 가속도, render.js 가 줌)
    const af = finite(st.accF ?? 0) ? st.accF ?? 0 : 0;
    const as = finite(st.accS ?? 0) ? st.accS ?? 0 : 0;
    const lim = C.FIGURE_LAG_ACC_MAX;
    const f = Math.max(-lim, Math.min(lim, af)) * dt;
    const sd = Math.max(-lim, Math.min(lim, as)) * dt;
    for (let i = 0; i < 2; i++) {
      V.shFwd[i] -= f * C.FIGURE_LAG_ARM;
      V.shOut[i] += (i ? -sd : sd) * C.FIGURE_LAG_ARM;
    }
    V.neckPitch -= f * C.FIGURE_LAG_NECK;
    const fast = st.flip >= 0 ? C.FIGURE_SPRING_FLIP : 1; // 공중제비는 빨리 웅크려야 보임
    springPose(P, V, T, dt, fast);
  }
  if (st.punch > 0 && !frozen && !st.act) {
    // 밀치기 팔은 늦게 따라오면 안 보임 (0.22초짜리) → 바로 그 자세
    P.shFwd[0] = T.shFwd[0];
    P.shOut[0] = T.shOut[0];
    P.elbow[0] = T.elbow[0];
    V.shFwd[0] = V.shOut[0] = V.elbow[0] = 0;
  }
  // 공격 동작: 따라가기를 건너뛰고 바로 덮어씀. 끝나면 덮어쓴 자세에서 평소처럼 흐물흐물 돌아옴
  let spin = 0;
  const act = st.act && (st.act.phase === 'broken' || (!frozen && (!st.stunned || MOVES[st.act.move].stunOk))) ? st.act : null; // 끊김·끌려옴은 맞은 휘청 위에 겹침
  if (act) {
    const m = MOVES[act.move] || MOVES.punch;
    if (act.phase === 'wind') overlay(P, T, m.W, ease(act.u * 1.4), V); // 준비 시간의 앞쪽에서 이미 크게
    else if (act.phase === 'strike') {
      overlay(P, T, m.W, 1 - act.u, V);
      overlay(P, T, m.S, ease(act.u * 2), V);
    } else if (act.phase === 'rec') {
      // 공중 공격은 타격 자세를 빨리 풀어 떨어지는 동안 굳은 자세로 남지 않게 (지상은 느리게)
      overlay(P, T, m.S, 1 - ease(act.air ? act.u * 2.2 : act.u), V);
      if (m.pull) overlay(P, T, { shFwd: L(0.4), elbow: L(2.0), waistPitch: -0.3 }, Math.sin(Math.PI * Math.min(1, act.u * 1.5)), V); // 갈고리 당김
    } else if (act.phase === 'broken') {
      if (sw.brokenId !== act.id) {
        sw.brokenId = act.id;
        sw.vx -= C.FIGURE_HIT_KICK * 0.3; // 뒤로 조금 더 휘청 (맞은 휘청에 얹힘)
      }
      overlay(P, T, BROKEN, act.u < 0.25 ? 1 : 1 - ease((act.u - 0.25) / 0.75), V);
    }
    if (m.spin && (act.phase === 'strike' || act.phase === 'rec')) spin = m.spin * ease(act.phase === 'strike' ? act.u * 0.2 : 0.2 + act.u * 0.8);
    if (m.turn && (act.phase === 'strike' || act.phase === 'rec')) spin = m.turn * (act.phase === 'strike' ? ease(act.u) : 1 - ease((act.u - 0.6) / 0.4)); // 옆으로 돌았다가 회복 끝에 돌아옴
  }
  // 도발 (이모트 전용 칸) · 승리 포즈: 공격 중·맞음·경직이면 안 함
  const poseSet = !act && !frozen && !st.stunned ? POSES[fig.form === 'metal' ? 'metal' : fig.char]?.[st.victory >= 0 ? 'victory' : st.emote === C.EMOTE_CHAR ? 'taunt' : ''] : null;
  if (poseSet) poseAt(P, T, V, poseSet, st.victory >= 0 ? st.victory : st.emoteT, st.victory >= 0 ? Infinity : C.EMOTE_MS / 1000);
  if (st.whirl >= 0 && !frozen) {
    // 광전사 R 분노 소용돌이: 도끼 든 팔을 쭉 뻗고 팽이처럼 (처음 0.25초에 빨라짐). 원심력에 끌려가듯 도끼 쪽으로 기울고 고개는 뒤로 젖혀짐
    const w = st.whirl;
    const ramp = Math.min(1, w / 0.25);
    spin = -Math.PI * 2 * C.BERSERK_SPIN_TURNS_PER_S * (w < 0.25 ? (w * w) / 0.5 : w - 0.125); // 빠르기가 0.25초 동안 0 → 최대 (돈 각 = 빠르기의 적분)
    overlay(P, T, { shOut: [1.55, 1.45], shFwd: [0.35, 0.15], elbow: [0.05, 0.35], waistSide: -0.4, waistPitch: -0.1, neckPitch: -0.45, thOut: [0.2, 0.3], knee: [0.35, 0.2] }, ramp, V);
  }
  if (st.glide && !frozen) {
    // 음유 천천히 낙하: 팔 벌리고 단풍 씨앗처럼 빙글빙글
    spin = (t * Math.PI * 2 * C.BARD_GLIDE_TURNS_PER_S) % (Math.PI * 2);
    overlay(P, T, { shOut: [1.45, 1.45], shFwd: [0.25, 0.25], elbow: [0.15, 0.15], thFwd: [0.25, 0.25], knee: [0.4, 0.4], neckPitch: -0.25 }, 1, V);
  }
  // 도는 동작(소용돌이·글라이드·춤 등)이 끝나면 가장 가까운 한 바퀴 각으로 스르륵 (안 그러면 0 으로 뚝 돌아옴). 도는 동안은 그대로
  const spinning = spin !== 0;
  if (spinning || !Number.isFinite(fig.spinS)) fig.spinS = spin;
  else {
    const to = Math.round(fig.spinS / (Math.PI * 2)) * Math.PI * 2;
    fig.spinS += (to - fig.spinS) * (1 - Math.exp(-C.FIGURE_SETTLE * dt));
    if (Math.abs(to - fig.spinS) < 1e-3) fig.spinS = 0;
  }
  if (fig.gun) {
    // 장전이면 늘 손에 (빈 총이면 허리), 탕 동작 동안은 늘 손에. 장전이면 공이가 젖혀짐
    const inHand = (!!act && !!MOVES[act.move].gun && act.phase !== 'broken') || !!fig.gun.loaded;
    fig.gun.inHand.visible = inHand;
    fig.gun.holster.visible = !inHand;
    for (const g of [fig.gun.inHand, fig.gun.holster]) g.userData.hammer.rotation.y = fig.gun.loaded ? -0.9 : 0;
  }
  if (fig.bow) {
    const inHand = !!act && !!MOVES[act.move].bow && act.phase !== 'broken';
    fig.bow.inHand.visible = inHand;
    fig.bow.back.visible = !inHand;
  }
  if (fig.shields) {
    const front = (!!act && !!MOVES[act.move].shield && act.phase !== 'broken') || !!poseSet?.shield;
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
  // 엉덩이 높이: 땅↔공중·구르기 사이에서 뚝 바뀌지 않게 빠르게 따라감 (처음·히트스톱은 바로)
  if (!Number.isFinite(fig.dropS) || frozen) fig.dropS = drop;
  else fig.dropS += (drop - fig.dropS) * (1 - Math.exp(-C.FIGURE_DROP_FOLLOW * dt));
  drop = fig.dropS;
  if (!poseOk(P) || !Number.isFinite(drop) || !Number.isFinite(spin)) {
    // 그래도 깨졌으면 이번 프레임은 기본 자세로 (다음 프레임은 깨끗한 자세부터)
    fig.pose = restPose(d);
    fig.poseV = null;
    Object.assign(sw, { x: 0, y: 0, vx: 0, vy: 0 });
    if (!retry) return figureAnim(fig, { ...st, act: null, hit: null, walking: false, air: false }, 0, true);
    return;
  }
  fig.hips.position.z = d.foot + d.shin + d.thigh + P.hipsZ - drop;
  // 공격 중 허리 비틂의 일부는 골반이 (다리째) 받음 → 휘두를 때 몸 전체가 돌고 허리 이음매가 덜 비틀림. 걷기 비틂(어깨 ↔ 다리 반대)은 허리만
  fig.twistK = Number.isFinite(fig.twistK) ? fig.twistK : 0;
  fig.twistK += ((act && act.phase !== 'broken' ? 1 : 0) - fig.twistK) * (1 - Math.exp(-C.FIGURE_HIP_TWIST_FOLLOW * dt));
  fig.hipTwist = P.waistRoll * C.FIGURE_HIP_TWIST * fig.twistK;
  fig.hips.rotation.z = fig.spinS + fig.hipTwist;
  fig.waist.rotation.y = P.waistPitch + sw.x;
  fig.waist.rotation.x = -(P.waistSide + sw.y);
  fig.waist.rotation.z = P.waistRoll - fig.hipTwist;
  fig.neck.rotation.y = P.neckPitch - sw.x * 0.5; // 머리는 늦게 따라옴
  fig.neck.rotation.x = sw.y * 0.5;
  for (let i = 0; i < 2; i++) {
    const side = i ? 1 : -1; // 0 = 오른쪽(-y)
    // 어깨: x 축으로 벌리고(out), y 축으로 앞으로(fwd). 아래(-z)를 보던 팔이 앞(+x)으로 가려면 y 축 음의 회전
    fig.shoulders[i].rotation.x = side * P.shOut[i];
    fig.shoulders[i].rotation.y = -P.shFwd[i];
    fig.shoulders[i].rotation.z = -side * P.shTwist[i]; // 팔을 제 축으로 비틂 (+ = 팔꿈치 굽힘이 몸 안쪽으로: 팔짱·X자)
    fig.elbows[i].rotation.y = -P.elbow[i];
    fig.thighs[i].rotation.x = side * P.thOut[i];
    fig.thighs[i].rotation.y = -P.thFwd[i];
    fig.knees[i].rotation.y = P.knee[i];
  }
  if (fig.shade) {
    // 근육 사이 홈·모자 테: 피부(플레이어 색, render.js 가 매 프레임 칠함)보다 어둡게 따라감. contrast 면 어두운 피부일 땐 밝게
    const sc = fig.shade.mat.color.copy(fig.shade.src.color);
    if (fig.shade.contrast && sc.r * 0.3 + sc.g * 0.59 + sc.b * 0.11 < C.FIGURE_TRIM_DARK) sc.lerp(_white, C.FIGURE_TRIM_LIGHTEN);
    else sc.multiplyScalar(fig.shade.k ?? C.FIGURE_MUSCLE_SHADE);
    fig.shade.mat.emissive.copy(fig.shade.src.emissive);
  }
  // 천 자락: 빨리 움직이거나 날아가면 뒤로 날리고 살랑임 (히트스톱 동안은 멈춤)
  if (frozen) return;
  const sp = st.whirl >= 0 ? C.BERSERK_SPIN_FLAP : st.stunned ? 1 : st.walking || st.air ? Math.min(1, st.hs / C.MOVE_SPEED) : 0; // 소용돌이 중엔 수염·갈래·털 망토가 바깥으로 날림
  // 자락은 스프링으로 늦게: 멈추면 앞으로 한 번 넘어갔다가 내려옴
  const fl = fig.flapS && Number.isFinite(fig.flapS.x + fig.flapS.v) ? fig.flapS : (fig.flapS = { x: sp, v: 0 });
  const fw = C.FIGURE_FLAP_SPRING.w;
  for (let j = 0, n = Math.max(1, Math.ceil(dt / C.FIGURE_SPRING_STEP)); j < n; j++) {
    fl.v += (fw * fw * (sp - fl.x) - 2 * C.FIGURE_FLAP_SPRING.damp * fw * fl.v) * (dt / n);
    fl.x += fl.v * (dt / n);
  }
  fig.flaps.forEach((f, i) => {
    f.obj.rotation.y = f.base + fl.x * f.lift + Math.sin(t * 9 + i * 1.7) * f.flutter * (0.3 + Math.max(0, fl.x));
  });
  if (fig.rage) {
    // 광전사 분노 (k 0~1, render.js 가 정함): 눈썹이 안쪽 아래로 찌푸려지고, 흰자가 충혈, 0.35 넘으면 핏줄이 섬 (높으면 벌떡벌떡)
    const k = fig.rage.k;
    for (const b of fig.rage.brows) b.mesh.rotation.x = b.side * (0.15 + 0.6 * k);
    fig.rage.eyeMat.color.setRGB(1, 1 - 0.55 * k, 1 - 0.6 * k);
    const beat = 1 + 0.25 * Math.max(0, Math.sin(t * 9)) * k;
    for (const v of fig.rage.veins) {
      v.visible = k > 0.35;
      v.scale.set(beat, beat, 1);
    }
    fig.rage.anger.visible = k > 0.5;
    fig.rage.anger.scale.setScalar(0.8 + 0.5 * Math.max(0, Math.sin(t * 9)));
  }
  if (fig.forms) {
    // 폼 전환: 메탈은 모히칸이 머리에서 확 솟아오름 (넘쳤다 돌아옴), 음유시인은 모자가 툭 얹힘
    const u = Math.min(1, (performance.now() - fig.formAt) / C.BARD_FORM_POP_MS);
    const pop = u < 1 ? Math.sin(u * Math.PI * 0.5) * (1 + 0.35 * Math.sin(u * Math.PI)) : 1;
    if (fig.form === 'metal') fig.mohawk.scale.set(1, 1, Math.max(0.01, pop));
    else fig.forms.bard.userData.parts[0].position.z = (1 - pop) * 0.15;
  }
  if (fig.pupils) {
    // 어지러움: 눈동자가 흰자 안에서 빙글빙글 (두 눈이 반대로)
    fig.pupils.forEach((pu, i) => {
      const r = C.FIGURE_EYE * 0.45;
      const on = st.dizzy > 0 ? Math.min(1, st.dizzy * 2) : 0;
      const a = t * 14 * (i ? -1 : 1);
      pu.position.set(C.FIGURE_EYE * 0.88 * (1 - on * 0.15), Math.cos(a) * r * on, Math.sin(a) * r * on);
    });
  }
  // 광전사 뿔: 마디마다 같은 각으로 위로 꺾여 매끈한 C 자 (뿌리는 바깥으로, 끝은 위로). 흐물거리지 않음 (2026-10-26 재혁: 그냥 위로 휘게)
  if (fig.horns) {
    const bend = C.FIGURE_HORN_CURL / (C.FIGURE_HORN_SEGS - 1);
    for (const h of fig.horns) h.segs.forEach((j, k) => (j.rotation.x = h.side * (k === 0 ? 0.15 : bend)));
  }
}
