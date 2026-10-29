// three.js 렌더링. 단색 블록, 최소한의 비주얼. 좌표계는 게임과 같은 z-up.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { buildCharacter, charAccessory } from '/character.js';
import { cloneBatched, paintBatched } from '/batch.js';
import { InstancePool } from '/instpool.js';
import { figureAnim, MOVES } from '/figure.js';
import { gaitOf } from '/figure-pose.js';
import { Effects } from '/effects.js';
import { CELL, SHAPE_NAMES } from '/shared/pieces.js';
import { orbitEye, followDist, overviewScale } from '/shared/camera.js';
import { itemModel } from '/models.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { makeTextures } from '/textures.js';
import { OutlineEffect } from 'three/addons/effects/OutlineEffect.js';
import { ViewModel } from '/viewmodel.js';
import { SnapClock, pushTrack, sampleTrack } from '/interp.js';
// 래그돌은 cannon-es 가 없어도 게임이 뜨게 따로 불러옴 (npm install 안 한 상태면 래그돌만 꺼짐)
let RagdollWorld = null;
import('/ragdoll.js')
  .then((m) => (RagdollWorld = m.RagdollWorld))
  .catch((e) => console.warn('래그돌 끔: cannon-es 를 못 불러옴 (npm install 필요)', e));
import { World } from '/world.js';
import { Hazard } from '/hazard.js';
import { MenuScene } from '/menu-scene.js';
import { TitleScene } from '/title-scene.js';
import { labelSizes } from '/shared/hud-layout.js';
import { prof } from '/perf.js';

THREE.Object3D.DEFAULT_UP.set(0, 0, 1);

// P1~P8 색. 블록(파랑 계열)·떨어지는 블록(주황)과 헷갈리지 않는 색 위주
// 아이템 모양·색: 멀리서도 종류를 구분하게
const ITEM_LOOK = {
  control: { color: 0x20e0e0, geo: () => new THREE.OctahedronGeometry(0.3) }, // 하늘색 팔면체
  knockback: { color: 0xe02020, geo: () => new THREE.SphereGeometry(0.24, 14, 10) }, // 빨간 공
  jump: { color: 0x40e040, geo: () => new THREE.ConeGeometry(0.24, 0.45, 12) }, // 초록 원뿔(위로)
  ghost: { color: 0xe8e8ff, geo: () => new THREE.TorusGeometry(0.2, 0.07, 8, 18) }, // 흰 고리
  brick: { color: 0xfff2c0, geo: () => new THREE.BoxGeometry(0.32, 0.32, 0.32) }, // 흰빛 작은 블록 (설치 블록)
  bomb: { color: 0x222222, geo: () => new THREE.SphereGeometry(0.22, 14, 10) }, // 검은 공
  speed: { color: 0xffe020, geo: () => boltGeometry() }, // 노란 번개
};

// 번개 모양 (이속 증가 아이템): 지그재그 판을 조금 두껍게
function boltGeometry() {
  const sh = new THREE.Shape();
  [[0.06, 0.3], [-0.12, 0.02], [0.02, 0.02], [-0.06, -0.3], [0.14, -0.02], [0.0, -0.02]].forEach(([x, y], i) => (i ? sh.lineTo(x, y) : sh.moveTo(x, y)));
  sh.closePath();
  const g = new THREE.ExtrudeGeometry(sh, { depth: 0.08, bevelEnabled: false });
  g.translate(0, 0, -0.04);
  g.rotateX(Math.PI / 2); // 세워서 (z 가 위)
  return g;
}

// 왼손에 든 것: 'brick' | 'ball'(투사체) | 'bomb' | null (망치는 오른손에 따로)
export function heldKind(p) {
  return { brick: 'brick', knockback: 'ball', bomb: 'bomb' }[p.held] || null;
}
const HELD_COLOR = { brick: ITEM_LOOK.brick.color, ball: ITEM_LOOK.knockback.color, bomb: 0x222222 };
const HELD_ITEM = { brick: 'brick', ball: 'knockback', bomb: 'bomb' }; // 손에 든 것 → 아이템 모델

// 피해 % 글자색: 0% 흰색 → 50% 노랑 → 100% 이상 빨강
export function damageColor(d) {
  const t = Math.min(1, d / 100);
  const g = t < 0.5 ? 255 : Math.round(255 - (t - 0.5) * 2 * 215);
  const b = t < 0.5 ? Math.round(255 - t * 2 * 255) : 0;
  return `rgb(255,${g},${b})`;
}

// 머리 위 표시: 위에 이름(플레이어 색), 아래에 피해 %
function drawLabel(canvas, name, color, d) {
  const ctx = canvas.getContext('2d');
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.strokeStyle = 'rgba(0,0,0,.85)';
  ctx.font = 'bold 30px system-ui, sans-serif';
  ctx.lineWidth = 6;
  ctx.strokeText(name, 128, 26);
  ctx.fillStyle = color;
  ctx.fillText(name, 128, 26);
  ctx.font = 'bold 44px system-ui, sans-serif';
  ctx.lineWidth = 7;
  ctx.strokeText(`${d}%`, 128, 80);
  ctx.fillStyle = damageColor(d);
  ctx.fillText(`${d}%`, 128, 80);
}

// 격자 칸 값 → 쌓인 블록 색
function cellColor(v) {
  if (v === CELL.BUILD) return C.BUILD_COLOR;
  if (CELL.GHOST_BASE !== undefined && v >= CELL.GHOST_BASE) return new THREE.Color(PLAYER_COLORS[(v - CELL.GHOST_BASE) % PLAYER_COLORS.length]).multiplyScalar(C.BLOCK_LANDED_SHADE).getHex(); // 유령 투하 블록: 떨어뜨린 사람 색 번호 (나가도 그대로)
  if (v === CELL.THROWN) return C.THROWN_COLOR;
  const shape = SHAPE_NAMES[v - CELL.SHAPE_BASE];
  if (shape) return new THREE.Color(C.SHAPE_COLORS[shape]).multiplyScalar(C.BLOCK_LANDED_SHADE).getHex();
  return C.TERRAIN_COLOR;
}

// 노을 하늘: 안쪽을 그리는 큰 구. 높이에 따라 위·가운데·지평선 색을 섞고, 해 쪽은 밝게 + 해 원반
function skyDome() {
  const mat = new THREE.ShaderMaterial({
    side: THREE.BackSide,
    depthWrite: false,
    fog: false,
    uniforms: {
      top: { value: new THREE.Color(C.SKY_TOP) },
      mid: { value: new THREE.Color(C.SKY_MID) },
      horizon: { value: new THREE.Color(C.SKY_HORIZON) },
      sunDir: { value: new THREE.Vector3(...C.SUN_DIR).normalize() },
      below: { value: new THREE.Color(C.SKY_HORIZON).multiplyScalar(0.55) }, // 지평선 아래 (맵 테마가 바꿈, world.js)
      glow: { value: new THREE.Vector3(1.0, 0.65, 0.35) }, // 해 둘레 번짐 색 (밤 테마는 달빛)
      disc: { value: new THREE.Vector3(1.0, 0.93, 0.75) }, // 해(달) 원반 색
      discSize: { value: 0.0005 }, // 원반 크기 (1 - cos 반지름)
      stars: { value: 0 }, // 별 밝기 (밤 테마)
    },
    vertexShader: `varying vec3 vDir;
      void main() { vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform vec3 top; uniform vec3 mid; uniform vec3 horizon; uniform vec3 sunDir; uniform vec3 below; uniform vec3 glow; uniform vec3 disc; uniform float discSize; uniform float stars; varying vec3 vDir;
      void main() {
        float h = clamp(vDir.z, -1.0, 1.0);
        vec3 c = h < 0.25 ? mix(horizon, mid, smoothstep(0.0, 0.25, h)) : mix(mid, top, smoothstep(0.25, 0.85, h));
        if (h < 0.0) c = mix(horizon, below, smoothstep(0.0, -0.4, h));
        float s = max(dot(normalize(vDir), sunDir), 0.0);
        if (stars > 0.0) {
          vec3 g = floor(normalize(vDir) * 220.0);
          float hs = fract(sin(dot(g, vec3(12.9898, 78.233, 37.719))) * 43758.5453);
          c += vec3(step(0.9972, hs) * stars * smoothstep(0.04, 0.35, h) * (0.5 + 0.5 * fract(hs * 91.0)));
        }
        c += glow * pow(s, 8.0) * 0.45;
        c = mix(c, disc, smoothstep(1.0 - discSize - 0.001, 1.0 - discSize, s));
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  const dome = new THREE.Mesh(new THREE.SphereGeometry(150, 32, 16), mat);
  dome.position.set(C.GRID_W / 2, C.GRID_D / 2, 0);
  dome.renderOrder = -1;
  noOutline(mat);
  return dome;
}

export const PLAYER_COLORS = C.PLAYER_PALETTE; // 사람이 고르는 색 (players[].color = 번호)
// 팀전 몸 색: 팀마다 계열 색, 팀 안에서는 자리 순으로 명암을 달리해 구분
export const TEAM_COLORS = { red: [0xe04040, 0xff8c50, 0xc02868, 0xff6090], blue: [0x3a6ee8, 0x30c0e8, 0x6a50e0, 0x40d8b0] };
export const TEAM_MAIN = { red: 0xe04040, blue: 0x3a6ee8 };
// 몸·이름·킬 로그·이펙트 색은 전부 이것으로: 팀전이면 팀 계열 (팀 안에서 명암), 아니면 고른 색 (예전 서버면 자리 순)
export function playerColor(p, state) {
  if (state && state.teamMode && TEAM_COLORS[p.team]) {
    const mates = state.players.filter((o) => o.team === p.team).sort((a, b) => a.slot - b.slot);
    const list = TEAM_COLORS[p.team];
    return list[Math.max(0, mates.findIndex((o) => o.id === p.id)) % list.length];
  }
  return PLAYER_COLORS[(p.color ?? p.slot) % PLAYER_COLORS.length];
}
const _q = new THREE.Quaternion();
const _lv = new THREE.Vector3(); // 이름표 거리 재기
const [LABEL_W, LABEL_H] = C.LABEL_SIZE; // 머리 위 이름·% 화면 크기 (sizeAttenuation 끔)
const HEAVY_HITS = new Set(['bomb', 'shock', 'projectile', 'slam', 'wall', 'blast', 'bigbomb', 'quake', 'blockslam', 'execute', 'pounce', 'shell', 'bigshell', 'groundshot', 'leapwave', 'spinend']); // 몸이 크게 휘청하는 공격
const MAX_SIDE = Math.max(C.GRID_W, C.GRID_D, ...Object.values(C.FIELD_SIZES));
const MAX_CELLS = MAX_SIDE * MAX_SIDE * Math.max(C.GRID_H, C.SKY_GRID_H || 0); // 가장 큰 판 (인원별 필드 크기 · 하늘 계단 높이)

// 테트리미노 재질이 제 색으로 살짝 빛남 (밤 테마에서도 지형과 구분)
const pieceGlow = (c) => ({ emissive: c, emissiveIntensity: C.PIECE_LOOK.glow });

// 쌓인 테트리미노 (인스턴스 색 = 모양 색): 칸 색 그대로 살짝 빛남 (발광 = 칸 색 × glow)
function landedPieceMat(map) {
  const m = toon({ color: 0xffffff, map });
  m.onBeforeCompile = (sh) => {
    sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>\n totalEmissiveRadiance += diffuseColor.rgb * ${C.PIECE_LOOK.glow.toFixed(3)};`);
  };
  m.customProgramCacheKey = () => `tf-landed-${C.PIECE_LOOK.glow}`;
  return m;
}

export class Renderer {
  // models: loadModels() 결과 (없으면 예전 도형으로 그림)
  constructor(canvasParent, models = null) {
    this.models = models;
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.renderer.shadowMap.enabled = true; // 실제로 그릴지는 setShadows (해가 그림자를 드리울 때만 그림자 패스를 돎)
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap;
    canvasParent.appendChild(this.renderer.domElement);
    this.outline = new OutlineEffect(this.renderer, { defaultThickness: C.OUTLINE_THICKNESS, defaultColor: [0.08, 0.05, 0.1], defaultAlpha: 1 });
    this.outlineOn = true;
    this.canvas = this.renderer.domElement;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(C.SKY_HORIZON);
    this.scene.fog = new THREE.Fog(C.SKY_HORIZON, C.FOG_NEAR, C.FOG_FAR);
    this.dome = skyDome();
    this.scene.add(this.dome);

    this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.05, 200);
    this.camera.up.set(0, 0, 1);
    this.scene.add(this.camera); // 1인칭 팔(뷰모델)을 카메라에 붙이려고
    // 1인칭 팔: 화면 오른쪽 아래에 보이는 내 팔. 밀치기 때 앞으로 뻗는다
    this.viewArm = new THREE.Mesh(new THREE.CapsuleGeometry(0.06, 0.32, 4, 10), toon({ color: 0xffffff }));
    this.viewArm.rotation.x = Math.PI / 2; // 캡슐을 화면 안쪽(-z) 방향으로 눕힘
    this.viewArmBase = new THREE.Vector3(0.26, -0.24, -0.42);
    this.viewArm.position.copy(this.viewArmBase);
    this.viewArm.visible = false;
    this.camera.add(this.viewArm);
    this.vm = new ViewModel(); // 캐릭터 몸(figure)이면 이 팔 대신 캐릭터 팔·무기
    // 1인칭 망치 머리 (망치 있을 때만)
    this.viewHammer = itemModel(models, 'weapon', 0.26) || new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.12, 0.12), toon({ color: 0xff8a10 }));
    // 캡슐 먼 끝에서 손잡이를 쥐고 머리가 위로 (x축 +90도 회전이라 로컬 -y 가 화면 안쪽, 로컬 -z 가 화면 위).
    // 세운 모델은 머리가 +z 끝 → x 축 180도로 뒤집어 머리를 위로, 손잡이 끝이 캡슐 끝에 오게 위로 올림
    this.viewHammer.rotation.x = Math.PI;
    this.viewHammer.position.set(0, -0.26, -0.26 * 0.35);
    this.viewHammer.visible = false;
    this.viewArm.add(this.viewHammer);
    // 1인칭 손에 든 설치 블록 (설치 블록 있을 때만)
    // 손에 든 것 (고른 핫바 칸): 쌓기 블록은 파란 상자, 나머지는 아이템 모델
    this.viewHeld = {};
    for (const [kind, type] of Object.entries(HELD_ITEM)) {
      const o = (type && itemModel(models, type, 0.15)) || new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.13, 0.13), toon({ color: HELD_COLOR[kind] }));
      o.position.set(0, -0.26, 0);
      o.visible = false;
      this.viewArm.add(o);
      this.viewHeld[kind] = o;
    }
    this.W = C.GRID_W; // 지금 판 크기 (snapshot field, 대기실은 기본)
    this.D = C.GRID_D;
    // 하늘 시점: 필드가 화면에 꽉 차는 직교 카메라 (블록과 그림자가 같은 크기로 보인다)
    this.skyCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
    this.skyCamera.up.set(0, 1, 0);
    this.H = C.GRID_H; // 지금 판 높이 (snapshot field.h: 하늘 계단이면 SKY_GRID_H)
    this.skyCamera.position.set(this.W / 2, this.D / 2, this.skyCamH());
    this.skyCamera.lookAt(this.W / 2, this.D / 2, 0);
    this.fitSkyCamera();

    // 노을: 하늘은 따뜻하게, 땅 반사는 푸르스름하게. 해는 낮게 떠서 그림자가 길다
    const hemi = new THREE.HemisphereLight(0xffe2d2, 0x8a90b8, 1.15);
    this.scene.add(hemi);
    this.hemi = hemi;
    this.sunDir = C.SUN_DIR; // 해 방향 (맵 테마가 바꿈)
    const sun = new THREE.DirectionalLight(C.SUN_COLOR, 1.25);
    const center = new THREE.Vector3(this.W / 2, this.D / 2, 0);
    sun.position.copy(center).addScaledVector(new THREE.Vector3(...C.SUN_DIR).normalize(), 30);
    sun.target.position.copy(center);
    this.scene.add(sun, sun.target);
    const reach = Math.hypot(this.W, this.D) / 2 + 4; // 필드 + 여백을 덮는 그림자 상자
    Object.assign(sun.shadow.camera, { left: -reach, right: reach, top: reach + 4, bottom: -reach, near: 5, far: 60 });
    sun.shadow.mapSize.set(C.SHADOW_MAP_SIZE, C.SHADOW_MAP_SIZE);
    sun.shadow.bias = -0.0008;
    sun.shadow.normalBias = 0.03;
    this.sun = sun;

    this.tex = makeTextures([C.GRID_W, C.GRID_D]);
    // 바닥: 칸마다 타일 한 장. 판 크기(인원별)가 바뀌면 setField 가 늘이고 격자선을 다시 만든다
    this.floor = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 0.3), toon({ color: 0xa49aa0, map: this.tex.floor }));
    this.floor.receiveShadow = true;
    this.scene.add(this.floor);
    // 필드 경계 (높이 표시용 세로선)
    this.edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(new THREE.BoxGeometry(1, 1, 1)), // setField 가 판 크기로 늘임
      new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.15 }),
    );
    this.scene.add(this.edges);

    // 쌓인 블록 (인스턴스). 텍스처가 종류마다 달라 종류별로 하나씩: 지형 돌 · 쌓기 나무 · 설치 블록 모래 · 테트리미노
    const blockGeo = new THREE.BoxGeometry(1, 1, 1);
    // 테트리미노 칸: 조금 작고 둥근 장난감 블록 (칸 사이 틈 + 둥근 모서리 + 살짝 빛남 → 이어진 무광 지형과 구분). 떨어질 때·쌓인 뒤 같은 모양
    const P = C.PIECE_LOOK;
    this.pieceBox = new RoundedBoxGeometry(P.size, P.size, P.size, 2, P.bevel);
    this.cubeBox = new THREE.BoxGeometry(1, 1, 1);
    this.blockMeshes = {};
    for (const [kind, map] of Object.entries({ terrain: this.tex.stone, build: this.tex.wood, thrown: this.tex.sand, shape: this.tex.piece })) {
      const mesh = new THREE.InstancedMesh(kind === 'shape' ? this.pieceBox : blockGeo, kind === 'shape' ? landedPieceMat(map) : toon({ color: 0xffffff, map }), MAX_CELLS);
      mesh.count = 0;
      // three.js 는 InstancedMesh 의 경계 구를 처음 한 번만 계산하고 갱신하지 않는다.
      // 블록이 0개일 때 계산된 빈 구가 남으면 원점 모서리가 시야 밖일 때 쌓인 블록 전체가 안 그려진다.
      // 최대 W×D×H 개 한 번의 draw call 이라 시야 판정을 끈다.
      mesh.frustumCulled = false;
      // OutlineEffect 는 인스턴스 위치를 모르고 테두리를 밀어내서 쌓인 블록엔 안 씀 (블록 테두리는 텍스처로)
      noOutline(mesh.material);
      mesh.castShadow = true;
      mesh.receiveShadow = true;
      this.scene.add(mesh);
      this.blockMeshes[kind] = mesh;
    }
    this.gridVersion = -1;

    // 떨어지는 블록 셀 + 그림자 (블록 여러 개 → 필요한 만큼 늘어나는 풀)
    this.pieceMeshes = [];
    this.shadowMeshes = [];
    this.pieceMat = toon({ color: 0xf0a030, map: this.tex.piece, transparent: true, opacity: 1, ...pieceGlow(0xf0a030) }); // 자동 블록
    this.controlledMat = toon({ color: 0xd040d0, emissive: 0x501050, map: this.tex.piece, transparent: true, opacity: 1 }); // 누가 조종 중인 블록 (빛나서 T 모양 보라와 구분)
    this.shapeMats = {}; // 자동 블록: 모양마다 색
    this.thrownMat = toon({ color: 0xffffff, emissive: 0x000000, map: this.tex.sand, transparent: true, opacity: 1 }); // 던진 설치 블록: 흰색 + 노랗게 깜빡임 (O 블록 노랑과 구분)
    this.shadowMat = noOutline(new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45 }));
    this.shadowBox = new THREE.BoxGeometry(0.96, 0.96, 0.06);
    this.piecePool = new InstancePool(this.scene, this.pieceBox, { castShadow: true });
    this.shadowPool = new InstancePool(this.scene, this.shadowBox);
    this.markBox = new THREE.BoxGeometry(0.94, 0.94, 0.04); // 스킬 예고 칸
    this.marks = [];
    // 압사 경고: 나를 깔 블록의 그림자는 빨갛게 + 내 발밑에 빨간 고리
    this.dangerShadowMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xff1010, transparent: true, opacity: 0.6 }));
    this.dangerRing = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.58, 24), noOutline(new THREE.MeshBasicMaterial({ color: 0xff2020, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthTest: false })));
    this.dangerRing.renderOrder = 9;
    this.dangerRing.visible = false;
    this.scene.add(this.dangerRing);

    // 상승하는 위험 (용암 자리): 표면·몸통·빛·입자·화면 경고 (hazard.js). 표면 높이 = state.lava.z
    this.hazard = new Hazard(this);
    this.onHazardRise = null; // 소리 훅: ({ kind: 'start'|'step', z, style }) => …
    this.setField(C.GRID_W, C.GRID_D, true);
    // 맵 테마 (하늘·바닥·섬·먼 배경·위험 모습). 맵 id 로 고름, 표에 없는 맵은 위의 예전 모습 그대로
    this.world = new World(this);

    this.effects = new Effects(this.scene);
    // 조종 중 하늘에서 본 블록의 착지 미리보기 (조종자에게만)
    this.previewMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xf0a030, transparent: true, opacity: 0.35 }));
    // 조준 미리보기 (고른 핫바 칸): 쌓기 = 흰 상자 1칸, 설치 블록 = 노란 상자 2칸, 폭탄 = 부서질 3×3 범위 빨간 판. 못 쓰면 빨강
    this.aimMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.3, depthWrite: false }));
    this.aimEdgeMat = new THREE.LineBasicMaterial({ color: 0xffffff });
    this.aimBoxes = [];
    // 놓인 폭탄: 검은 공, 터질 때가 가까울수록 빨갛게 빨리 깜빡임
    this.bombMeshes = [];
    this.beams = [];
    this.beamMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xd040d0, transparent: true, opacity: 0.5, depthWrite: false }));

    this.playerMeshes = new Map();
    this.hits = new Map(); // 맞은 몸 반응 (id → { id, t0, stop, dir, pow }, hitReact)
    this.finishAt = new Map(); // 콤보 마무리 타를 받은 시각 (comboFinish)
    this.counterAt = new Map(); // 카운터히트를 받은 시각 (counterHit)
    // 건축가 블록: 칸마다 메시 (주인 색·금 간 무늬·깜빡임·솟기), 같은 묶음 이음 띠, 연쇄 폭발 대기 칸
    this.bbMeshes = [];
    this.bbStraps = [];
    this.bbSig = '';
    this.bbSkip = null;
    this.bbBorn = new Map(); // 칸 → 생긴 시각 (솟는 연출)
    this.bbGhosts = []; // 연쇄로 아직 안 터진 칸 { x, y, z, color, at }
    this.bbGeo = new THREE.BoxGeometry(1, 1, 1);
    this.bbStrapMat = toon({ color: 0x3a3a44 });
    this.quakes = []; // 탱크 R 솟는 땅: { cells, t0, sinkAt, meshes }
    this.armorUntil = new Map();
    this.windupUntil = new Map(); // 지상 F 준비 번쩍 (skillWindup) // 탱크 아머 중 (id → 끝 시각): 몸이 금속처럼 번쩍
    this.armorHitAt = new Map(); // 아머로 버틴 시각 (그 타는 안 휘청)
    this.armorBreakAt = new Map(); // 아머가 깨진 시각 (그 타는 크게 휘청)
    this.slides = new Map(); // 닌자 순간 베기 미끄러짐 (id → { from, to, t0, nextGhost })
    this.ghosts = []; // 잔상 { obj, t0 }
    this.acts = new Map(); // 공격 동작 (id → { id, move, t0, windup 초, struck 판정 시각, rec 초, broken 끊긴 시각 })
    this.hitSeq = 0;
    this.itemMeshes = [];
    this.projMeshes = [];
    this.smooth = new Map(); // id -> {x,y,z} 화면에 그리는 위치 (보간됨)
    this.tracks = new Map(); // id -> 최근 스냅샷 위치 [{t,x,y,z}] (client/interp.js)
    this.snapClock = new SnapClock();
    this.snapTime = null;
    this.skyBlend = 0; // 0 = 1인칭, 1 = 하늘 시점. 사이 값은 전환 중
    this.third = false; // 3인칭 (설정·V 키). 살아 있을 때 내 캐릭터 뒤·위에서 봄
    this.tpDist = null; // 3인칭 카메라 실제 거리 (막히면 줄어듦, followDist)
    this.fov = C.FOV_DEFAULT; // 설정의 시야각
    this.skyYaw = Math.PI / 2; // 하늘 시점 화면 위쪽이 가리키는 방향 (조종 시작 때 보던 방향)

    window.addEventListener('resize', () => {
      this.camera.aspect = window.innerWidth / window.innerHeight;
      this.camera.updateProjectionMatrix();
      this.fitSkyCamera();
      this.renderer.setSize(window.innerWidth, window.innerHeight);
    });
  }

  // 판 크기 (snapshot field: 인원별 10·12·14, 대기실 10). 바뀔 때만 바닥·격자선·경계·용암·해 그림자·하늘 시점을 맞춘다
  // 착지 예고: 떨어지는 블록 그림자가 내려앉을 때가 가까울수록 진해짐 (단계별 재질 몇 개를 돌려 씀)
  shadowFor(eta) {
    if (!this.shadowSteps) {
      this.shadowSteps = [0, 1, 2, 3, 4].map((k) => noOutline(new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: C.SHADOW_OPACITY_FAR + ((C.SHADOW_OPACITY_NEAR - C.SHADOW_OPACITY_FAR) * k) / 4 })));
    }
    const near = Number.isFinite(eta) ? 1 - Math.max(0, Math.min(1, eta / C.SHADOW_DARKEN_MS)) : 0;
    return this.shadowSteps[Math.round(near * 4)];
  }

  // 압사 (death crush): 그 자리에 몸이 납작하게 찌그러진 채 잠깐 남음 (병맛, 왜 죽었는지 바로 보임) → 얇아지며 사라짐
  crushFlat(who) {
    const g = this.playerMeshes.get(who);
    const s = this.smooth.get(who);
    if (!g || !s) return;
    const ud = g.userData;
    g.userData = {}; // userData 의 순환 참조를 복사하지 않게
    const flat = cloneBatched(g);
    g.userData = ud;
    flat.traverse((o) => {
      if (o.isSprite) o.visible = false;
      o.castShadow = false;
    });
    flat.visible = true;
    flat.position.set(s.x, s.y, s.z + 0.02);
    flat.scale.set(1.5, 1.5, C.CRUSH_FLAT_Z);
    this.scene.add(flat);
    (this.flats ||= []).push({ m: flat, t0: performance.now() });
  }

  updateFlats() {
    if (!this.flats?.length) return;
    const now = performance.now();
    this.flats = this.flats.filter((f) => {
      const age = now - f.t0;
      if (age > C.CRUSH_FLAT_MS) {
        this.scene.remove(f.m);
        return false;
      }
      // 처음엔 납작하게 퍼졌다가 (살짝 튐) 끝 0.3초에 종잇장처럼 얇아지며 사라짐
      const pop = age < 120 ? 1 + 0.25 * Math.sin((Math.PI * age) / 120) : 1;
      const fade = Math.max(0, (age - (C.CRUSH_FLAT_MS - 300)) / 300);
      f.m.scale.set(1.5 * pop, 1.5 * pop, C.CRUSH_FLAT_Z * (1 - fade * 0.9));
      return true;
    });
  }

  // 카메라(eye) → 캐릭터 가슴 선분에 가까운 블록 칸(떨어지는 블록·하늘 계단 블록)을 반투명 재질로. 들어갈 때·나올 때 거리를 달리해 깜빡이지 않게
  fadeOccluders(eye, subject) {
    const target = subject ? new THREE.Vector3(subject.x, subject.y, subject.z + C.PLAYER_HEIGHT * 0.6) : null;
    const seg = target && eye ? target.clone().sub(eye) : null;
    const len2 = seg ? seg.lengthSq() : 0;
    const q = new THREE.Vector3();
    for (const pm of this.pieceMeshes) {
      let hide = false;
      if (pm.visible && seg && len2 > 0.01) {
        q.copy(pm.position).sub(eye);
        const t = q.dot(seg) / len2;
        if (t > 0 && t < 1) {
          const d = q.sub(seg.clone().multiplyScalar(t)).length();
          hide = d < (pm.userData.faded ? C.OCCLUDE_EXIT : C.OCCLUDE_ENTER);
        }
      }
      pm.userData.faded = hide;
      if (hide) pm.material = this.fadedMat(pm.material);
    }
  }

  fadedMat(base) {
    this.fadedMats ||= new Map();
    let m = this.fadedMats.get(base);
    if (!m) {
      m = base.clone();
      m.transparent = true;
      m.opacity = C.OCCLUDE_OPACITY;
      m.depthWrite = false;
      noOutline(m);
      this.fadedMats.set(base, m);
      this.fadedMats.set(m, m); // 이미 반투명이면 그대로
    }
    return m;
  }

  // 하늘 시점 카메라 높이: 판 높이 + (SKY_CAMERA_HEIGHT - GRID_H) 여백
  skyCamH() {
    return C.SKY_CAMERA_HEIGHT - C.GRID_H + (this.H || C.GRID_H);
  }

  setField(w, d, force = false, h = this.H || C.GRID_H) {
    if (!(w > 0 && d > 0 && h > 0) || (!force && w === this.W && d === this.D && h === this.H)) return;
    this.W = w;
    this.D = d;
    this.H = h;
    this.skyCamera.far = Math.max(100, this.skyCamH() + 20);
    const cx = w / 2;
    const cy = d / 2;
    this.floor.scale.set(w, d, 1);
    this.floor.position.set(cx, cy, -0.15);
    this.tex.floor.repeat.set(w, d);
    if (this.gridLines) {
      this.scene.remove(this.gridLines);
      this.gridLines.geometry.dispose();
      this.gridLines.material.dispose();
    }
    // GridHelper 는 정사각형만 → 긴 변으로 만들고 늘임 (판은 늘 정사각형이지만 혹시 몰라)
    const n = Math.max(w, d);
    this.gridLines = new THREE.GridHelper(n, n, 0x222222, 0x444444);
    this.gridLines.rotation.x = Math.PI / 2;
    this.gridLines.scale.set(w / n, 1, d / n);
    this.gridLines.position.set(cx, cy, 0.002);
    this.scene.add(this.gridLines);
    if (this.world) this.world.layout(); // 테마 섬·장식을 판 크기에 맞춰 (격자선도 테마면 숨김)
    this.edges.scale.set(w, d, this.H);
    this.edges.position.set(cx, cy, this.H / 2);
    this.hazard?.layout();
    this.dome.position.set(cx, cy, 0);
    const center = new THREE.Vector3(cx, cy, 0);
    this.sun.position.copy(center).addScaledVector(new THREE.Vector3(...this.sunDir).normalize(), 30);
    this.sun.target.position.copy(center);
    const reach = Math.hypot(w, d) / 2 + 4; // 필드 + 여백을 덮는 그림자 상자
    Object.assign(this.sun.shadow.camera, { left: -reach, right: reach, top: reach + 4 + (h - C.GRID_H), bottom: -reach, far: 60 + (h - C.GRID_H) * 1.5 }); // 하늘 계단이면 위로 더 (높은 블록도 그림자)
    this.sun.shadow.camera.updateProjectionMatrix();
    this.skyCamera.position.set(cx, cy, this.skyCamH());
    this.skyCamera.lookAt(cx, cy, 0);
    this.fitSkyCamera();
    this.gridVersion = -1; // 격자 배열 길이가 바뀜 → 다시 그림
    this.overviewZ = undefined;
  }

  fitSkyCamera() {
    const aspect = window.innerWidth / window.innerHeight;
    const half = Math.max(this.W, this.D) / 2 + 1; // 필드 + 여백 1칸
    const cam = this.skyCamera;
    if (aspect >= 1) {
      cam.left = -half * aspect;
      cam.right = half * aspect;
      cam.top = half;
      cam.bottom = -half;
    } else {
      cam.left = -half;
      cam.right = half;
      cam.top = half / aspect;
      cam.bottom = -half / aspect;
    }
    cam.updateProjectionMatrix();
  }

  // skip: 그리지 않을 칸 번호 (건축가 블록은 updateBBlocks 가 따로 그림)
  updateGrid(grid, skip = this.bbSkip) {
    const m = new THREE.Matrix4();
    const color = new THREE.Color();
    const count = { terrain: 0, build: 0, thrown: 0, shape: 0 };
    for (let z = 0; z < this.H; z++) {
      for (let y = 0; y < this.D; y++) {
        for (let x = 0; x < this.W; x++) {
          const v = grid[(z * this.D + y) * this.W + x];
          if (!v || (skip && skip.has((z * this.D + y) * this.W + x))) continue;
          const kind = v === CELL.TERRAIN ? 'terrain' : v === CELL.BUILD ? 'build' : v === CELL.THROWN ? 'thrown' : 'shape';
          const mesh = this.blockMeshes[kind];
          const n = count[kind]++;
          m.makeTranslation(x + 0.5, y + 0.5, z + 0.5);
          mesh.setMatrixAt(n, m);
          // 무엇이 남긴 칸인지에 따라 색 (지형 돌·쌓기 나무·설치 블록 모래·테트리미노 모양 색), 인접 칸은 체커보드로 살짝 명암
          color.setHex(v === CELL.TERRAIN && this.terrainColor != null ? this.terrainColor : cellColor(v)); // 테마 지형 블록은 재질 색 그대로
          if ((x + y + z) % 2) color.multiplyScalar(0.94);
          if (kind === 'terrain' && this.terrainColor != null) this.world.cellLook(n, x, y, z, color); // 테마 블록: 칸마다 무늬 변형·색 흔들림
          mesh.setColorAt(n, color);
        }
      }
    }
    for (const [kind, mesh] of Object.entries(this.blockMeshes)) {
      mesh.count = count[kind];
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }
    if (this.world) this.world.gridDone(grid); // 테마 블록 소품 (드러난 옆면의 결정·깨진 돌)
  }

  // 필드에 놓인 아이템 모양: 모델이 있으면 모델, 없으면 예전 도형 (이속 증가는 늘 번개 도형)
  itemShape(type) {
    const model = itemModel(this.models, type, C.ITEM_MODEL_SIZE);
    const look = ITEM_LOOK[type] || ITEM_LOOK.control;
    const o = model || new THREE.Mesh(look.geo(), toon({ color: look.color, emissive: 0x222222 }));
    o.traverse((c) => {
      if (c.isMesh) c.castShadow = true;
    });
    return o;
  }

  shapeMat(shape) {
    if (!this.shapeMats[shape]) {
      const c = C.SHAPE_COLORS[shape] ?? 0xf0a030;
      this.shapeMats[shape] = toon({ color: c, map: this.tex.piece, transparent: true, opacity: 1, ...pieceGlow(c) });
    }
    return this.shapeMats[shape];
  }

  // 하늘 계단 블록 재질 (모양 색을 하얗게 섞어 밝게 + 하늘색 빛, 살짝 비침)
  skyPieceMat(shape) {
    this.skyMats ||= {};
    if (!this.skyMats[shape]) {
      const col = new THREE.Color(C.SHAPE_COLORS[shape] ?? 0xf0a030).lerp(new THREE.Color(0xffffff), C.SKY_PIECE_WHITEN);
      this.skyMats[shape] = toon({ color: col.getHex(), map: this.tex.piece, transparent: true, opacity: C.SKY_PIECE_OPACITY, ...pieceGlow(col.getHex()) });
    }
    return this.skyMats[shape];
  }

  // 유령 투하 블록 (떨어지는 동안): 떨어뜨린 사람 slot 색, 하얗게 섞여 살짝 비침 + 은은한 빛 (유령 느낌). 그림자는 보통 블록과 같음
  ghostPieceMat(color) {
    this.ghostMats ||= {};
    const k = (color ?? 0) % PLAYER_COLORS.length;
    if (!this.ghostMats[k]) {
      const col = new THREE.Color(PLAYER_COLORS[k]);
      this.ghostMats[k] = toon({ color: col.clone().lerp(new THREE.Color(0xffffff), C.GHOST_PIECE_WHITEN).getHex(), emissive: col.clone().multiplyScalar(0.25).getHex(), map: this.tex.piece, transparent: true, opacity: C.GHOST_PIECE_OPACITY });
    }
    return this.ghostMats[k];
  }

  // 관전 중 유령 투하 조준: 화면 점(ndc)에서 나간 시선이 처음 닿는 칸 기둥 → { x, y, z: 기둥 꼭대기 (그 위에 떨어짐) }. 필드 밖이면 null
  pickColumn(state, ndcX, ndcY) {
    const cam = this.camera;
    cam.updateMatrixWorld();
    const o = new THREE.Vector3().setFromMatrixPosition(cam.matrixWorld);
    const d = new THREE.Vector3(ndcX, ndcY, 0.5).unproject(cam).sub(o).normalize();
    for (let t = 0.3; t < C.GHOST_AIM_RANGE; t += 0.05) {
      const x = o.x + d.x * t;
      const y = o.y + d.y * t;
      const z = o.z + d.z * t;
      if (z < -0.5) break; // 바닥 아래 (필드 밖 낭떠러지)
      const gx = Math.floor(x);
      const gy = Math.floor(y);
      if (gx < 0 || gy < 0 || gx >= this.W || gy >= this.D) continue;
      if (z <= 0 || this.solidAt(state, x, y, z)) return { x: gx, y: gy, z: this.columnTopAt(state, gx, gy) };
    }
    return null;
  }

  columnTopAt(state, x, y) {
    if (!state.grid) return 0;
    for (let z = this.H - 1; z >= 0; z--) if (state.grid[(z * this.D + y) * this.W + x]) return z + 1;
    return 0;
  }

  // 조준 표시: 기둥 꼭대기 칸 테두리 + 그 위에 내 색 반투명 큐브 (쿨 중이면 회색). aim = null 이면 숨김
  setGhostAim(aim) {
    if (!this.ghostAim) {
      const g = new THREE.Group();
      const cubeMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: C.GHOST_AIM_OPACITY, depthWrite: false }));
      const cube = new THREE.Mesh(this.cubeBox, cubeMat);
      cube.position.z = 0.5;
      const edgeMat = new THREE.LineBasicMaterial({ color: 0xffffff });
      const edge = new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1.02, 1.02, 0.04)), edgeMat);
      edge.position.z = 0.03;
      const cubeEdge = new THREE.LineSegments(new THREE.EdgesGeometry(this.cubeBox), edgeMat);
      cubeEdge.position.z = 0.5;
      g.add(cube, edge, cubeEdge);
      this.scene.add(g);
      this.ghostAim = { g, cubeMat, edgeMat };
    }
    const a = this.ghostAim;
    a.g.visible = !!aim;
    if (!aim) return;
    a.g.position.set(aim.x + 0.5, aim.y + 0.5, aim.z);
    const col = aim.ready ? aim.color : C.GHOST_AIM_COOLDOWN_COLOR;
    a.cubeMat.color.setHex(col);
    a.edgeMat.color.setHex(aim.ready ? new THREE.Color(aim.color).lerp(new THREE.Color(0xffffff), 0.5).getHex() : C.GHOST_AIM_COOLDOWN_COLOR); // 테두리도 내 색 (밝게)
    a.cubeMat.opacity = C.GHOST_AIM_OPACITY * (aim.ready ? 0.8 + 0.2 * Math.sin(performance.now() / 150) : 0.6);
  }

  // ghostDrop 이벤트: 유령 블록이 생김 — 그 사람 색 연기가 펑 + 하얀 고리 (하늘에서 생김)
  ghostDropFx(e) {
    const pos = { x: e.x + 0.5, y: e.y + 0.5, z: e.z + 0.5 };
    const col = PLAYER_COLORS[(e.color ?? e.slot ?? 0) % PLAYER_COLORS.length];
    this.effects.burst(pos, null, col, 14, 2.5, 0.14, 0.6);
    this.effects.burst(pos, null, 0xffffff, 10, 1.6, 0.1, 0.5);
    this.effects.ring(pos, 0xffffff, 1.4, 0.3, true);
  }

  // 타이틀 화면 (title.js 가 부름): 메뉴 장면 하늘에 블록 로고. instant = 떨어짐 없이 완성 로고
  startTitle(instant = false) {
    if (!this.menu || this.menu.mapId !== C.TITLE_MAP) this.menu = new MenuScene(Math.random, this.lowGfx, C.TITLE_MAP); // 타이틀 섬 = 수정 동굴 고정, 내려온 메뉴도 같은 섬
    this.endTitle();
    this.title = new TitleScene(this, this.menu.camYaw, instant);
    return this.title;
  }

  endTitle() {
    if (!this.title) return;
    this.title.dispose();
    this.title = null;
  }

  // 그래픽 낮춤 (설정): 화면 해상도 1배, 맵 테마 장식·위험 입자 줄임
  setLowGfx(on) {
    if (this.lowGfx === !!on) return;
    this.lowGfx = !!on;
    document.body.classList.toggle('low-gfx', this.lowGfx); // 메뉴 배경 흐림 끔 (index.html)
    this.menu = null; // 메뉴 장면을 새 설정으로 (캐릭터 수)
    this.renderer.setPixelRatio(on ? 1 : Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    this.world.setLow(on);
    this.hazard.setLow(on);
  }

  // 외곽선 켜기·끄기 (설정). 켜면 OutlineEffect 가 장면을 한 번 더 (뒤집힌 테두리로) 그린다
  setOutline(on) {
    this.outlineOn = !!on;
  }

  draw(camera) {
    const t = prof.begin(); // 성능 표시 (F3): 렌더 구간
    if (this.outlineOn) this.outline.render(this.scene, camera);
    else this.renderer.render(this.scene, camera);
    this.hazard.drawOverlay(this.renderer); // 위험이 발 밑에 가까우면 화면 가장자리 색
    prof.end('render', t);
  }

  // 그림자 켜기·끄기 (대기 화면 설정). 꺼지면 그림자 패스 자체를 안 돌아 느린 PC 에서 가벼움
  setShadows(on) {
    this.sun.castShadow = !!on;
  }

  getPlayerMesh(p) {
    let g = this.playerMeshes.get(p.id);
    // 캐릭터마다 몸이 다르면(TABS 식) 캐릭터를 바꿨을 때 다시 만든다
    const look = p.dummy ? 'dummy' : C.FIGURE_CHARS.includes(p.char) ? p.char : 'robot'; // 연습 방 허수아비는 캐릭터 없는 허수아비 모양
    if (g && g.userData.look !== look) {
      this.scene.remove(g);
      this.playerMeshes.delete(p.id);
      g = null;
    }
    if (!g) {
      const color = playerColor(p, this.curState); // 매 프레임 다시 칠함 (색·팀이 바뀌면 바로)
      const ch = buildCharacter(color, this.models, look === 'robot' ? null : look);
      g = ch.group;
      g.userData.look = look;
      g.userData.figure = ch.figure || null;
      g.userData.bodyMat = ch.bodyMaterial;
      g.userData.arms = ch.arms;
      g.userData.hammer = ch.hammer;
      g.userData.held = ch.held;
      g.userData.mats = ch.mats;
      g.userData.robot = ch.robot; // 로봇 모델이면 { mixer, actions, face }
      g.userData.rig = ch.rig;
      g.userData.parts = ch.parts;
      g.userData.feet = ch.feet;
      g.userData.anim = { px: null, py: null, pz: null, hs: 0, vz: 0, walk: 0, spin: 0, land: 0 };
      g.userData.waitMark = ch.waitMark;
      g.userData.color = color;
      g.traverse((o) => {
        if (o.isMesh) o.castShadow = true;
      });
      // 하늘 시점 전용 표시: 바라보는 방향 화살표 (+ 내 캐릭터는 흰 고리)
      const tri = new THREE.Shape();
      tri.moveTo(0.75, 0);
      tri.lineTo(-0.35, 0.38);
      tri.lineTo(-0.15, 0);
      tri.lineTo(-0.35, -0.38);
      tri.closePath();
      const arrow = new THREE.Mesh(
        new THREE.ShapeGeometry(tri),
        noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, depthTest: false })),
      );
      arrow.position.z = C.PLAYER_HEIGHT + 0.05;
      arrow.renderOrder = 10;
      g.add(arrow);
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.6, 0.78, 32),
        noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, depthTest: false })),
      );
      ring.position.z = C.PLAYER_HEIGHT + 0.04;
      ring.renderOrder = 10;
      g.add(ring);
      // 머리 위 피해 % (대난투식)
      const canvas = document.createElement('canvas');
      canvas.width = 256;
      canvas.height = 112;
      const tex = new THREE.CanvasTexture(canvas);
      // 거리와 상관없이 화면에서 같은 크기 (가까이 붙은 상대의 숫자가 화면을 덮지 않게).
      // 블록 뒤에 숨으면 이름표도 가려진다 (기둥 숲에서 숨는 의미가 있게)
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthTest: true, depthWrite: false, transparent: true, sizeAttenuation: false }));
      sprite.scale.set(LABEL_W, LABEL_H, 1);
      // 이름표 높이: 머리(모자·뿔·모히칸 포함) 꼭대기 위로. 들고 있는 무기는 안 셈. 낮아도 예전 높이 아래로는 안 내림
      let labelZ = C.PLAYER_HEIGHT + 0.45;
      if (ch.figure) {
        g.updateMatrixWorld(true);
        const top = new THREE.Box3().setFromObject(ch.figure.neck).max.z;
        if (Number.isFinite(top)) labelZ = Math.max(labelZ, top + C.LABEL_ABOVE_HEAD);
      }
      g.userData.labelZ = labelZ;
      sprite.position.z = labelZ;
      sprite.renderOrder = 11;
      g.add(sprite);
      g.userData.label = { sprite, canvas, tex, shown: null };
      g.userData.arrow = arrow;
      g.userData.ring = ring;
      this.scene.add(g);
      this.playerMeshes.set(p.id, g);
    }
    return g;
  }

  updateAim(aim) {
    const cells = aim ? aim.cells : [];
    while (this.aimBoxes.length < cells.length) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), this.aimMat);
      m.add(new THREE.LineSegments(new THREE.EdgesGeometry(new THREE.BoxGeometry(1.002, 1.002, 1.002)), this.aimEdgeMat));
      this.scene.add(m);
      this.aimBoxes.push(m);
    }
    if (aim) {
      // 쌓기 = 흰 상자, 설치 블록 = 흰 상자 + 노란 테두리 (떨어지는 설치 블록과 같은 모양), 폭탄 = 빨간 판. 못 쓰면 빨강
      const base = aim.kind === 'bomb' ? 0xff5030 : 0xffffff;
      const edge = aim.kind === 'brick' ? 0xf0d060 : base;
      this.aimMat.color.setHex(aim.ok ? base : 0xff2020);
      this.aimEdgeMat.color.setHex(aim.ok ? edge : 0xff2020);
    }
    this.aimBoxes.forEach((m, i) => {
      const c = cells[i];
      m.visible = !!c;
      if (!c) return;
      const flat = aim.kind === 'bomb'; // 폭탄은 범위를 바닥에 얇은 판으로
      m.scale.set(1, 1, flat ? 0.12 : 1);
      m.position.set(c[0] + 0.5, c[1] + 0.5, flat ? c[2] + 0.06 : c[2] + 0.5);
    });
  }

  // 콩 애니메이션: 걸으면 통통 튀며 발을 번갈아 내밀고 앞으로 기울임, 뜨면 위로 늘어남, 내려앉으면 찌그러짐,
  // 경직된 채 날아가면 뒤로 구름. 서버 상태엔 속도가 없어서 부드럽게 따라간 위치의 변화로 속도를 잰다
  animate(g, s, p, dt) {
    const a = g.userData.anim;
    const rig = g.userData.rig;
    const parts = g.userData.parts;
    if (a.px === null || dt <= 0) Object.assign(a, { px: s.x, py: s.y, pz: s.z });
    const vx = (s.x - a.px) / Math.max(dt, 1e-3);
    const vy = (s.y - a.py) / Math.max(dt, 1e-3);
    const vz = (s.z - a.pz) / Math.max(dt, 1e-3);
    Object.assign(a, { px: s.x, py: s.y, pz: s.z });
    const k = 1 - Math.exp(-C.ANIM_SMOOTH * dt);
    a.hs += (Math.hypot(vx, vy) - a.hs) * k;
    const wasFalling = a.vz < -C.ANIM_AIR_VZ;
    a.vz += (vz - a.vz) * k;
    // 공중: 위아래로 빠르거나, 발밑(네 모서리) 바로 아래에 바닥·블록이 없으면 (점프 꼭대기에서 속도가 0 이어도 공중으로)
    const air = Math.abs(a.vz) > C.ANIM_AIR_VZ || (this.curState ? !this.feetOnGround(this.curState, s) : false);
    if (wasFalling && !air) a.land = 1; // 내려앉음
    a.land = Math.max(0, a.land - dt / C.ANIM_LAND_S);
    // 걷기: 발이 땅에 있을 때만 걸음 위상이 돎
    const walking = !air && a.hs > C.ANIM_WALK_MIN_SPEED;
    if (walking) a.walk += dt * a.hs * C.ANIM_WALK_FREQ * (g.userData.figure ? gaitOf(g.userData.figure.char).freq : 1); // 캐릭터별 발 빠르기 (FIGURE_GAIT freq)
    const step = walking ? Math.sin(a.walk) : 0;
    const robot = g.userData.robot; // 로봇은 걷기·춤을 모델 동작이 하므로 통통 튀기·흔들기·빙글은 안 함
    const fig = g.userData.figure; // TABS 식 몸은 관절로 걸음 (통통 튀기·흔들기·늘어나기 안 함, 춤 빙글은 함)
    const jointed = robot || fig;
    parts.position.z = -C.PLAYER_HEIGHT / 2 + (walking && !jointed ? Math.abs(step) * C.ANIM_BOB : 0);
    g.userData.feet.forEach((f, i) => (f.position.x = f.userData.baseX + (i ? -step : step) * C.ANIM_STEP));
    // 경직된 채 빠르게 날아가면 뒤로 구름. 끝나면 가장 가까운 바로 선 자세로 돌아옴
    if (fig) {
      this.figureFlight(a, s, p, air, vx, vy, dt);
      // 몸 기준 가속도 (앞 +, 왼쪽 +): 팔·고개가 늦게 따라오는 힘 (figureAnim follow-through)
      const c = Math.cos(p.yaw);
      const sn = Math.sin(p.yaw);
      const ax = a.pvxs === undefined ? 0 : (a.vxs - a.pvxs) / dt;
      const ay = a.pvys === undefined ? 0 : (a.vys - a.pvys) / dt;
      a.pvxs = a.vxs;
      a.pvys = a.vys;
      a.accF = c * ax + sn * ay;
      a.accS = -sn * ax + c * ay;
      this.figureHabits(a, s, p, air, walking, dt);
      // 안전장치: 구르기·공중제비 각이 깨지면 바로 선 자세로
      if (!Number.isFinite(a.spin)) a.spin = 0;
      if (!Number.isFinite(a.flipAngle)) a.flipAngle = 0;
      if (a.tumbleAxis && ![a.tumbleAxis.x, a.tumbleAxis.y, a.tumbleAxis.z].every(Number.isFinite)) a.tumbleAxis.set(0, 1, 0);
    }
    else if (p.stunned && a.hs > C.ANIM_TUMBLE_MIN_SPEED) a.spin -= dt * C.ANIM_TUMBLE_SPEED;
    else a.spin += (Math.round(a.spin / (Math.PI * 2)) * Math.PI * 2 - a.spin) * (1 - Math.exp(-C.ANIM_SMOOTH * dt));
    const lean = Math.min(1, a.hs / C.MOVE_SPEED) * C.ANIM_LEAN;
    // 바드 기타 꽂기: 떨어지는 동안 몸이 앞으로 확 뒤집혀 거꾸로 (머리·기타가 아래)
    a.diveFlip = (a.diveFlip || 0) + ((fig && this.dives?.has(p.id) ? C.FIGURE_DIVE_FLIP : 0) - (a.diveFlip || 0)) * (1 - Math.exp(-14 * dt));
    rig.rotation.y = lean + (fig ? a.flipAngle + a.diveFlip + C.FIGURE_AIR_DASH.tilt * Math.min(1, ((a.airDashT || 0) / C.FIGURE_AIR_DASH.s) * 4) : a.spin); // 공중 대시: 몸 전체 앞으로 눕힘 (슈퍼맨)
    rig.rotation.x = jointed ? 0 : step * C.ANIM_SWAY; // 걸을 때 좌우로 살짝 흔들
    // 승자 춤·이모트 '춤': 깡충 뛰며 제자리에서 빙글. TABS 식 몸은 승자면 춤 대신 캐릭터별 승리 포즈 (figure.js POSES, a.vicT = 승리 경과 초)
    const emote = p.emote ?? -1;
    const won = this.victoryId === p.id || !!this.winners?.has(p.id);
    a.vicT = won && fig ? (a.vicT >= 0 ? a.vicT : 0) + dt : -1;
    const dancing = (this.victoryId === p.id && !fig) || emote === 1;
    a.dance = dancing ? (a.dance || 0) + dt : 0;
    // 춤이 끝나면 가장 가까운 한 바퀴 각으로 스르륵 (0 으로 뚝 돌아오지 않게)
    if (dancing) a.danceSpin = a.dance * C.VICTORY_SPIN;
    else if (a.danceSpin) {
      const to = Math.round(a.danceSpin / (Math.PI * 2)) * Math.PI * 2;
      a.danceSpin += (to - a.danceSpin) * (1 - Math.exp(-C.FIGURE_SETTLE * dt));
      if (Math.abs(to - a.danceSpin) < 1e-3) a.danceSpin = 0;
    }
    rig.rotation.z = !robot && Number.isFinite(a.danceSpin) ? a.danceSpin : 0;
    if (fig && a.spin) rig.quaternion.premultiply(_q.setFromAxisAngle(a.tumbleAxis, a.spin)); // 날아가는 쪽으로 구름
    if (dancing && !robot) parts.position.z += Math.abs(Math.sin(a.dance * C.VICTORY_HOP_FREQ)) * C.VICTORY_HOP;
    if (robot) this.robotAnim(robot, p, a, air, walking, dancing, emote, dt);
    if (fig) {
      a.emoteT = emote >= 0 && emote !== 1 ? (a.emoteT || 0) + dt : 0;
      a.t = (a.t || 0) + dt;
      const punch = this.effects.punchAmount(p.id);
      const hit = this.hitFor(p);
      figureAnim(fig, {
        air, walking, hs: a.hs, walk: a.walk, stunned: p.stunned || !!a.flipRag, dancing, emote, emoteT: a.emoteT, victory: a.vicT, punch, holding: !!heldKind(p), t: a.t,
        hit, act: this.actFor(p.id), accF: a.accF, accS: a.accS, tumble: a.tumbleAmt, recover: a.recover * a.recoverPow, land: a.figLand * a.landPow, flip: a.flip >= 0 && !a.flipRag ? a.flip / C.FIGURE_FLIP_S : -1, rag: !!a.flipRag,
        sniffAt: fig.sniff ? this.sniffAngle(p) : null,
        vz: a.vz, idle: a.idleT, airDash: (a.airDashT || 0) / C.FIGURE_AIR_DASH.s, bump: a.bump,
        whirl: this.whirlTime(a, p), dizzy: a.dizzy > 0 ? a.dizzy / C.BERSERK_DIZZY_S : 0,
        glide: !!(p.bard && p.bard.glideLeft > 0 && air), amp: !!(p.bard && p.bard.ampLeft > 0),
      }, dt);
      if (a.dizzy > 0) a.dizzy -= dt;
      // 머리 박음: 머리가 확 숙여지고 몸이 살짝 눌렸다 돌아옴 (압사 납작과 다르게 금방 펴짐)
      const bonk = 1 - (performance.now() - (this.bonkAt?.get(p.id) ?? -1e9)) / C.HEAD_BONK_FX_MS;
      if (bonk > 0) {
        const k = Math.sin(Math.PI * Math.min(1, (1 - bonk) * 3)) * bonk; // 확 눌렸다 → 천천히 풀림
        fig.neck.rotation.y += C.HEAD_BONK_NOD * k;
        parts.position.z -= C.HEAD_BONK_SQUASH * k;
      }
    }
    const stretch = a.vz > C.ANIM_AIR_VZ && !fig ? C.ANIM_STRETCH : 0; // 올라가는 중: 위로 늘어나고 옆은 가늘게
    const land = fig ? 0 : a.land; // TABS 식 몸은 찌그러지지 않음
    const wide = 1 - stretch / 2 + land * C.ANIM_LAND_SQUASH * 0.6; // 착지: 납작해지며 옆으로 퍼짐
    rig.scale.set(wide, wide, 1 + stretch - land * C.ANIM_LAND_SQUASH);
  }

  // 머리 위 이름·% 가 많으면 (5명 넘게 보이면) 카메라에서 먼 사람 것은 작고 흐리게 (shared/hud-layout.js labelSizes)
  thinLabels() {
    const vis = [];
    for (const g of this.playerMeshes.values()) {
      const l = g.userData.label;
      if (l && l.sprite.visible) vis.push(l.sprite);
    }
    const cam = this.camera.position;
    const sizes = labelSizes(vis.map((sp) => sp.getWorldPosition(_lv).distanceTo(cam)));
    vis.forEach((sp, i) => {
      const k = sizes[i];
      sp.scale.set(LABEL_W * k.scale, LABEL_H * k.scale, 1);
      sp.material.opacity = k.opacity;
    });
  }

  // 광전사 R 소용돌이 경과 초 (snapshot spinLeft 로 시작 시각을 맞추고 그 뒤는 내 시계로 매끈하게). 안 돌면 -1
  whirlTime(a, p) {
    const bz = p.berserker;
    if (!bz || !(bz.spinLeft > 0) || !p.alive) {
      a.whirlT0 = null;
      return -1;
    }
    const now = performance.now();
    if (a.whirlT0 == null) a.whirlT0 = now - (bz.spinMs - bz.spinLeft);
    const w = (now - a.whirlT0) / 1000;
    return Number.isFinite(w) ? Math.min(w, bz.spinMs / 1000) : -1;
  }

  // 소용돌이 범위 표시 (발밑 빨간 고리 + 도끼 높이에서 빙글 도는 궤적 호) · 뿔 바람 · 어지러울 때 머리 위 별
  updateWhirlFx(g, p, s, dt) {
    const a = g.userData.anim;
    const whirl = a.whirlT0 != null;
    let w = g.userData.whirlFx;
    if (whirl && !w) {
      const r = C.BERSERKER_SPIN_RANGE;
      const mat = noOutline(new THREE.MeshBasicMaterial({ color: C.BERSERK_SPIN_RING_COLOR, transparent: true, opacity: 0.55, side: THREE.DoubleSide, depthWrite: false }));
      const disc = noOutline(new THREE.MeshBasicMaterial({ color: C.BERSERK_SPIN_RING_COLOR, transparent: true, opacity: 0.12, side: THREE.DoubleSide, depthWrite: false }));
      const trailMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.6, side: THREE.DoubleSide, depthWrite: false }));
      const ring = new THREE.Mesh(new THREE.RingGeometry(r - 0.07, r, 40), mat);
      ring.add(new THREE.Mesh(new THREE.CircleGeometry(r - 0.07, 40), disc));
      const trail = new THREE.Mesh(new THREE.RingGeometry(r * 0.55, r * 0.95, 32, 1, 0, Math.PI * 1.2), trailMat);
      for (const m of [ring, trail]) {
        m.renderOrder = 4;
        this.scene.add(m);
      }
      w = g.userData.whirlFx = { ring, trail, mats: [mat, disc, trailMat] };
    }
    if (w) {
      w.ring.visible = w.trail.visible = whirl;
      if (whirl) {
        w.ring.position.set(s.x, s.y, s.z + 0.04);
        w.trail.position.set(s.x, s.y, s.z + 0.9);
        w.trail.rotation.z -= dt * Math.PI * 2 * C.BERSERK_SPIN_TURNS_PER_S;
        // 뿔·몸 둘레 바람 줄: 흰 김이 바깥으로 휙
        if (Math.random() < dt * 30) {
          const ang = Math.random() * Math.PI * 2;
          this.effects.burst({ x: s.x + Math.cos(ang) * 0.5, y: s.y + Math.sin(ang) * 0.5, z: s.z + 1.3 + Math.random() * 0.5 }, { x: Math.cos(ang) * 1.2, y: Math.sin(ang) * 1.2 }, 0xffffff, 1, 2.5, 0.06, 0.25);
        }
      }
    }
    // 어지러움: 머리 위로 노란 별 셋이 빙글
    let st = g.userData.dizzyStars;
    if (a.dizzy > 0 && !st) {
      const mat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffe040 }));
      st = g.userData.dizzyStars = [0, 1, 2].map(() => {
        const m = new THREE.Mesh(new THREE.OctahedronGeometry(0.07), mat);
        this.scene.add(m);
        return m;
      });
    }
    if (st) {
      const on = a.dizzy > 0 && p.alive;
      st.forEach((m, i) => {
        m.visible = on;
        if (!on) return;
        const ang = performance.now() / 180 + (i * Math.PI * 2) / 3;
        m.position.set(s.x + Math.cos(ang) * 0.32, s.y + Math.sin(ang) * 0.32, s.z + C.PLAYER_HEIGHT * C.FIGURE_SCALE + 0.15);
        m.rotation.z = ang * 2;
      });
    }
  }

  // 어지러움 시작 (소용돌이 끝 / 끊김)
  setDizzy(who, sec) {
    const g = this.playerMeshes.get(who);
    if (g && g.userData.figure?.pupils) g.userData.anim.dizzy = sec;
  }

  // 광전사 이벤트 효과
  rushLand(e) {
    const pos = { x: e.x, y: e.y, z: e.z + 0.08 };
    this.effects.ring(pos, 0xffc080, (e.r || 1.5) * 2, 0.35, true);
    this.effects.burst(pos, null, 0x9a8a78, 22, 4.5, 0.14, 0.6);
    if (this.curState) this.blockPulse(this.blockNeighbors([[Math.floor(e.x), Math.floor(e.y), Math.floor(e.z)]]).filter((c) => c[2] < Math.floor(e.z + 0.01)), 0xffffff, { jolt: -C.BLOCK_JOLT, opacity: 0.35 });
    if (this.onBlast) this.onBlast(pos, false);
  }

  spinEnd(e) {
    const pos = { x: e.x, y: e.y, z: e.z + 0.08 };
    this.effects.ring(pos, 0xff7040, (e.r || 2) * 2.2, 0.4, true);
    this.effects.ring({ x: e.x, y: e.y, z: e.z + 0.9 }, 0xffffff, (e.r || 2) * 1.6, 0.3);
    this.effects.burst({ x: e.x, y: e.y, z: e.z + 0.6 }, null, 0xffb060, 26, 7, 0.13, 0.45);
    this.effects.burst(pos, null, 0x9a8a78, 18, 4, 0.14, 0.6);
    if (this.onBlast) this.onBlast(pos, (e.rage || 1) > 1.3);
    this.setDizzy(e.who, C.BERSERK_DIZZY_S);
  }

  // 사냥꾼 대기 킁킁: 내가 표식을 붙인 가장 가까운 상대 쪽 각 (몸 기준, 왼쪽 +). 없으면 null
  sniffAngle(p) {
    let best = null;
    let bd = Infinity;
    for (const t of this.curState?.players || []) {
      if (t.id === p.id || !t.alive || !(t.marks || []).some((m) => m.by === p.id)) continue;
      const d = Math.hypot(t.x - p.x, t.y - p.y);
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    if (!best) return null;
    let ang = Math.atan2(best.y - p.y, best.x - p.x) - p.yaw;
    ang = Math.atan2(Math.sin(ang), Math.cos(ang));
    return Number.isFinite(ang) ? ang : null;
  }

  // 래그돌 목표 자세·모터 세기 입력 (client/ragdoll.js · ragdoll-math.js)
  ragdollCapture(g, p, s, dt) {
    const a = g.userData.anim;
    const now = performance.now();
    const limp = !!p.stunned || !!a.flipRag; // 경직 또는 대포수 공중 반동 (래그돌처럼 뒤로 구름)
    if (a.ragWasStunned && !limp) a.ragStunEnd = now;
    a.ragWasStunned = limp;
    const hit = this.hitFor(p);
    const h = this.hits.get(p.id);
    let hx = -Math.cos(p.yaw);
    let hy = -Math.sin(p.yaw);
    if (h?.dir && Number.isFinite(h.dir.x) && Number.isFinite(h.dir.y)) {
      const l = Math.hypot(h.dir.x, h.dir.y) || 1;
      hx = h.dir.x / l;
      hy = h.dir.y / l;
    }
    const act = this.actFor(p.id);
    this.ragdoll.capture(
      p.id,
      g,
      { stunned: limp, sinceStun: a.ragStunEnd ? (now - a.ragStunEnd) / 1000 : Infinity, hitAge: hit ? hit.age : null, falling: s.z < C.RAGDOLL_FALL_Z, act: act ? act.phase : (p.emote ?? -1) >= 0 || a.vicT >= 0 ? 'pose' : null }, // 이모트·승리 포즈는 모터 세게 (힘 안 빠지게)
      hit ? { id: hit.id, x: hx, y: hy, pow: hit.pow } : null,
      dt,
    );
  }

  // TABS 식 몸의 날아가기·구르기·일어나기·착지·2단 점프 공중제비 상태 (a 에 쌓음, figureAnim 과 rig 회전이 씀)
  figureFlight(a, s, p, air, vx, vy, dt) {
    const k = 1 - Math.exp(-C.ANIM_SMOOTH * dt);
    a.vxs = (a.vxs || 0) + (vx - (a.vxs || 0)) * k;
    a.vys = (a.vys || 0) + (vy - (a.vys || 0)) * k;
    if (!a.tumbleAxis) Object.assign(a, { tumbleAxis: new THREE.Vector3(0, 1, 0), tumbleAmt: 0, recover: 0, recoverPow: 0, figLand: 0, landPow: 0, fallVz: 0, flip: -1, flipAngle: 0, wasStunned: false, tumbled: false });
    // 구르기: 경직 중 빠르게 날아가면 날아가는 쪽으로 머리부터 구름 (한 번 구르기 시작하면 느려져도 경직 끝까지)
    const fast = a.hs > C.FIGURE_TUMBLE_MIN_SPEED;
    a.tumbling = p.stunned && (fast || (a.tumbling && a.hs > C.FIGURE_TUMBLE_MIN_SPEED * 0.4));
    if (a.tumbling) {
      a.tumbled = true;
      // 몸 기준 날아가는 방향 → 그 방향으로 위가 넘어가는 회전축 (위 × 속도)
      const c = Math.cos(p.yaw);
      const sn = Math.sin(p.yaw);
      const lx = c * a.vxs + sn * a.vys;
      const ly = -sn * a.vxs + c * a.vys;
      const len = Math.hypot(lx, ly);
      if (len > 0.5) a.tumbleAxis.set(-ly / len, lx / len, 0);
      a.spin += dt * C.FIGURE_TUMBLE_SPEED;
      a.spinTo = null;
    } else if (a.spin) {
      // 다 구르면 가던 쪽으로 마저 돌아 바로 섬 (조금만 돌았으면 되돌아옴)
      if (a.spinTo == null) a.spinTo = Math.PI * 2 * Math.ceil(a.spin / (Math.PI * 2) - 0.25);
      a.spin += (a.spinTo - a.spin) * (1 - Math.exp(-C.ANIM_SMOOTH * dt));
      if (Math.abs(a.spinTo - a.spin) < 0.01) a.spin = 0;
    }
    a.tumbleAmt += ((a.tumbling ? 1 : 0) - a.tumbleAmt) * k;
    // 경직이 풀리면 (땅에 닿은 뒤) 쪼그렸다 일어남. 굴렀으면 깊게
    if (a.wasStunned && !p.stunned) a.recoverPending = performance.now();
    if (p.stunned) a.recoverPending = 0;
    a.wasStunned = p.stunned;
    if (a.recoverPending && !air) {
      if (performance.now() - a.recoverPending < 1500) {
        a.recover = 1;
        a.recoverPow = a.tumbled ? 1 : 0.5;
      }
      a.recoverPending = 0;
      a.tumbled = false;
    }
    a.recover = Math.max(0, a.recover - dt / C.FIGURE_RECOVER_S);
    // 착지: 떨어진 속도만큼 무릎을 굽힘
    if (air) a.fallVz = Math.min(a.fallVz, a.vz);
    else if (a.fallVz < -C.ANIM_AIR_VZ) {
      a.figLand = 1;
      a.landPow = Math.min(1, -a.fallVz / C.FIGURE_LAND_FALL_VZ);
      a.fallVz = 0;
    } else a.fallVz = 0;
    a.figLand = Math.max(0, a.figLand - dt / C.FIGURE_LAND_S);
    // 2단 점프 공중제비 (airJump 이벤트가 a.flip = 0 으로 시작). 맞으면 끊김
    // 대포수 공중 반동 (cannonFlip): 뒤로 래그돌처럼 여러 바퀴 (a.flipTurns·flipDir·flipS), 팔다리는 허우적 (a.flipRag)
    const flipS = a.flipS || C.FIGURE_FLIP_S;
    if (a.flip >= 0) {
      a.flip += dt;
      if (p.stunned || a.flip >= flipS || (a.flipRag && !air && a.flip > 0.15)) {
        if (a.flip < flipS) a.flipRest = a.flipAngle; // 중간에 끊김: 그 각에서 가장 가까운 바로 선 각으로 스르륵
        a.flip = -1;
        a.flipS = a.flipTurns = 0;
        a.flipDir = 1;
        a.flipRag = false;
      }
    }
    const f = a.flip >= 0 ? a.flip / flipS : 1;
    const turns = a.flipTurns || 1;
    if (a.flip >= 0) a.flipRest = 0;
    else if (a.flipRest) {
      const to = Math.round(a.flipRest / (Math.PI * 2)) * Math.PI * 2;
      a.flipRest += (to - a.flipRest) * (1 - Math.exp(-C.FIGURE_SETTLE * dt));
      if (Math.abs(to - a.flipRest) < 1e-3 || !Number.isFinite(a.flipRest)) a.flipRest = 0;
    }
    a.flipAngle = a.flip >= 0 ? (a.flipDir || 1) * Math.PI * 2 * turns * (a.flipRag ? 1 - (1 - f) * (1 - f) : f * f * (3 - 2 * f)) : a.flipRest || 0; // 공중제비: 웅크리는 동안 천천히 → 가운데서 빨리 → 끝에서 느려짐 / 반동: 처음이 가장 빠름
  }

  // 걸음걸이 밖 버릇 (a 에 쌓음, figureAnim 이 씀): 가만히 있은 시간 (평소 버릇), 공중 대시 슈퍼맨, 벽·몸에 부딪힘 휘청
  figureHabits(a, s, p, air, walking, dt) {
    const busy = walking || air || p.stunned || this.acts.has(p.id) || (p.emote ?? -1) >= 0;
    a.idleT = busy ? 0 : (a.idleT || 0) + dt;
    // 공중 대시: 공중에서 남은 공중 대시가 줄면 (서버 airDashes) 슈퍼맨 자세 잠깐
    if (air && Number.isFinite(a.airDashesPrev) && p.airDashes < a.airDashesPrev) a.airDashT = C.FIGURE_AIR_DASH.s;
    a.airDashesPrev = p.airDashes;
    a.airDashT = p.stunned ? 0 : Math.max(0, (a.airDashT || 0) - dt);
    // 부딪힘: 땅에서 달리다 급히 멈췄고, 가던 쪽 바로 앞에 블록·사람이 있으면 (스스로 멈춘 것과 구별) 작은 휘청. 경직 중엔 안 함
    const B = C.FIGURE_BUMP;
    const hs = Math.hypot(a.vxs, a.vys);
    const prev = a.bumpPrev || { hs: 0, vx: 0, vy: 0 };
    a.bumpPrev = { hs, vx: a.vxs, vy: a.vys };
    a.bumpCd = Math.max(0, (a.bumpCd || 0) - dt);
    if (air || p.stunned || a.bumpCd > 0 || prev.hs < B.minSpeed || (prev.hs - hs) / Math.max(dt, 1e-3) < B.decel) return;
    const ux = prev.vx / prev.hs;
    const uy = prev.vy / prev.hs;
    const ahead = C.PLAYER_HALF + B.reach;
    let blocked = !!this.curState && this.solidAt(this.curState, s.x + ux * ahead, s.y + uy * ahead, s.z + 0.5);
    if (!blocked && this.curState) {
      for (const o of this.curState.players) {
        if (o.id === p.id || !o.alive) continue;
        const dx = o.x - s.x;
        const dy = o.y - s.y;
        if (Math.abs(o.z - s.z) < C.PLAYER_HEIGHT && Math.hypot(dx, dy) < C.PLAYER_HALF * 2 + B.reach && dx * ux + dy * uy > 0) blocked = true;
      }
    }
    if (!blocked) return;
    a.bumpCd = B.cooldown;
    // 몸 기준 방향 (앞 +x, 왼쪽 +y): 가던 쪽 반대로 튕김
    const c = Math.cos(p.yaw);
    const sn = Math.sin(p.yaw);
    a.bump = { id: (a.bump?.id || 0) + 1, dx: -(c * ux + sn * uy), dy: -(-sn * ux + c * uy), pow: prev.hs };
  }

  // 맞은 순간 (main.js 의 hit 이벤트). dir = 밀린 방향 (월드, 없으면 null). 콤보 마무리 타면 더 크게
  hitReact(id, dir, { heavy = false, crit = false, kind = null } = {}) {
    const now = performance.now();
    const finish = now - (this.finishAt.get(id) || -1e9) < 200;
    const counter = now - (this.counterAt.get(id) || -1e9) < 200;
    // 탱크 아머: 버틴 타는 얼굴만 찡그리는 정도, 깨진 타는 크게 (같은 틱에 armor·armorBreak 가 hit 보다 먼저 옴)
    if (now - (this.armorHitAt.get(id) || -1e9) < 200) {
      this.hits.set(id, { id: ++this.hitSeq, t0: now, stop: 0, dir, pow: C.FIGURE_HIT_ARMOR });
      return;
    }
    if (now - (this.armorBreakAt.get(id) || -1e9) < 200) {
      this.hits.set(id, { id: ++this.hitSeq, t0: now, stop: (C.HITSTOP_MS * 1.5) / 1000, dir, pow: C.FIGURE_HIT_ARMOR_BREAK });
      const a = this.acts.get(id);
      if (a && !a.broken) this.acts.delete(id);
      return;
    }
    const pow = Math.min(3, (finish ? C.FIGURE_HIT_FINISH : heavy || crit || HEAVY_HITS.has(kind) ? C.FIGURE_HIT_HEAVY : 1) * (counter ? C.FIGURE_HIT_COUNTER : 1)); // 마무리 + 카운터가 겹쳐도 몸이 뒤집히지 않게
    const stop = (C.HITSTOP_MS * (crit ? C.CRIT_HITSTOP_MULT : 1)) / 1000;
    this.hits.set(id, { id: ++this.hitSeq, t0: now, stop, dir, pow });
    const a = this.acts.get(id);
    if (a && !a.broken) this.acts.delete(id); // 맞으면 하던 공격 동작은 접음 (끊김은 interrupt 가 따로)
  }

  // 콤보 마무리 타 (combo 이벤트가 같은 타의 hit 보다 먼저 옴)
  comboFinish(id) {
    this.finishAt.set(id, performance.now());
  }

  // ---------- 공격 동작 (figure.js MOVES) ----------
  // attack 이벤트: 준비 시작. 동작 이름은 평타 표의 name (갈고리 주먹만 'hook:주먹'), 회복 시간은 평타 표의 rec
  attackStart(e) {
    const set = C.BASIC_ATTACKS?.[e.char];
    const def = set ? (e.air ? set.air : set.chain)[e.n - 1] : null; // 공중 평타도 1타부터 (air 는 배열)
    const move = e.char === 'hook' && e.name === '주먹' ? 'hook:주먹' : e.air && e.name === '표창' ? '공중 표창' : MOVES[e.name] ? e.name : 'punch';
    // 표에서 못 찾거나 이상한 값이면 기본값 (NaN 이 동작에 들어가면 몸이 무너짐)
    const ms = (v, dflt) => (Number.isFinite(v) && v >= 0 ? v : dflt) / 1000;
    this.acts.set(e.who, { id: ++this.hitSeq, move, t0: performance.now(), windup: ms(e.windup, 0), struck: null, rec: ms(def?.rec, 300), broken: 0, air: !!e.air });
  }

  // swing 이벤트: 판정 순간 → 타격 자세. 준비 없이 온 것(캐릭터 없는 밀치기)은 바로 타격
  attackSwing(e) {
    const a = this.acts.get(e.who);
    if (a && !a.struck && !a.broken) {
      a.struck = performance.now();
      if (a.move === '갈고리 스핀') this.spinArc(e.who); // 갈고리 끝이 그리는 원
      return;
    }
    this.acts.set(e.who, { id: ++this.hitSeq, move: 'punch', t0: performance.now(), windup: 0, struck: performance.now(), rec: 0.3, broken: 0 });
  }

  // 스킬·필살기 동작: windupMs 가 있으면 준비 자세로 기다렸다 skillStrike 에서 타격, 없으면 바로 타격
  skillMove(who, move, windupMs = 0) {
    const now = performance.now();
    this.acts.set(who, { id: ++this.hitSeq, move, t0: now, windup: windupMs / 1000, struck: windupMs > 0 ? null : now, rec: MOVES[move].rec || 0.4, broken: 0 });
  }

  // onlyPending: 준비 중인 그 동작이 있을 때만 (wallRise 는 3타 블록에도 와서 평타 회복을 덮으면 안 됨)
  skillStrike(who, move, onlyPending = false) {
    const a = this.acts.get(who);
    if (a && a.move === move && !a.broken) {
      if (!a.struck) a.struck = performance.now();
      return; // 이미 치는 중 (갈고리가 당길 때 한 번 더 오는 것 등)
    }
    if (!onlyPending) this.skillMove(who, move);
  }

  // 끊긴 공격 (interrupt 이벤트): 하던 동작에서 팔이 튕기며 무너짐. 맞은 휘청과 겹쳐 보임
  interrupt(who) {
    const a = this.acts.get(who) || { id: ++this.hitSeq, move: 'punch', t0: performance.now(), windup: 0, struck: null, rec: 0.3 };
    a.id = ++this.hitSeq;
    a.broken = performance.now();
    this.acts.set(who, a);
  }

  // figureAnim 에 넘길 지금 공격 단계. 끝났으면 지움
  actFor(id) {
    const a = this.acts.get(id);
    if (!a) return null;
    const now = performance.now();
    const done = () => {
      this.acts.delete(id);
      return null;
    };
    // 안전장치: 시간 값이 이상하거나 너무 오래 남은 동작은 버림 (끝나지 않는 동작이 자세를 붙잡지 않게)
    if (![a.windup, a.rec].every((v) => Number.isFinite(v) && v >= 0) || a.rec <= 0 || now - a.t0 > C.FIGURE_ACT_MAX_S * 1000) return done();
    if (a.broken) {
      const u = (now - a.broken) / 1000 / C.FIGURE_BROKEN_S;
      return u >= 1 ? done() : { id: a.id, move: a.move, phase: 'broken', u, air: !!a.air };
    }
    if (!a.struck) {
      const age = (now - a.t0) / 1000;
      if (age > a.windup + C.FIGURE_SWING_WAIT_S) return done(); // 판정이 안 옴 (캔슬)
      return { id: a.id, move: a.move, phase: 'wind', u: a.windup > 0 ? Math.min(1, age / a.windup) : 1, air: !!a.air };
    }
    if (a.hold) return { id: a.id, move: a.move, phase: 'strike', u: 1, air: !!a.air }; // 바드 기타 꽂기: 떨어지는 동안 타격 자세 그대로
    const s = (now - a.struck) / 1000;
    if (s < C.FIGURE_STRIKE_S) return { id: a.id, move: a.move, phase: 'strike', u: s / C.FIGURE_STRIKE_S, air: !!a.air };
    const r = (s - C.FIGURE_STRIKE_S) / a.rec;
    return r >= 1 ? done() : { id: a.id, move: a.move, phase: 'rec', u: r, air: !!a.air };
  }

  // ---------- 머리 박음 (headBonk): 떨어지는 블록에 머리를 박고 살아서 아래로 밀려남 ----------
  // 블록 아랫면이 번쩍 들썩 + 흙먼지 + 머리 위로 노란 별이 빙글 (경직 동안) + 머리 끄덕 (animate)
  headBonk(e) {
    const now = performance.now();
    (this.bonkAt ||= new Map()).set(e.who, now);
    const top = e.z + C.PLAYER_HEIGHT;
    const cell = [Math.floor(e.x), Math.floor(e.y), Math.floor(top + 0.05)];
    this.blockPulse([cell], 0xffffff, { jolt: C.BLOCK_JOLT, opacity: 0.6 });
    this.effects.burst({ x: e.x, y: e.y, z: top }, null, 0x9a8a78, 8, 2.5, 0.08, 0.35);
    const mine = this.vm.on && this.playerMeshes.get(e.who) === this.vm.src; // 내 1인칭이면 머리 위 고리는 화면을 덮어서 뺌 (흔들림·소리로)
    if (!mine) this.effects.ring({ x: e.x, y: e.y, z: top + 0.02 }, 0xffe040, 0.45, 0.2, true);
    if (!this.bonkStarMat) {
      this.bonkStarMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffe040 }));
      this.bonkStarGeo = new THREE.OctahedronGeometry(0.06);
    }
    (this.bonks ||= []).push({
      who: e.who,
      t0: now,
      stars: [0, 1, 2, 3].map(() => {
        const m = new THREE.Mesh(this.bonkStarGeo, this.bonkStarMat);
        this.scene.add(m);
        return m;
      }),
    });
  }

  updateBonks() {
    if (!this.bonks?.length) return;
    const now = performance.now();
    this.bonks = this.bonks.filter((b) => {
      const s = this.smooth.get(b.who);
      const u = (now - b.t0) / C.HEAD_BONK_FX_MS;
      if (!s || u >= 1) {
        for (const m of b.stars) this.scene.remove(m);
        return false;
      }
      const g = this.playerMeshes.get(b.who);
      const z = s.z + (g?.userData.labelZ ? g.userData.labelZ - C.LABEL_ABOVE_HEAD : C.PLAYER_HEIGHT) + 0.05;
      b.stars.forEach((m, i) => {
        const ang = now / 110 + (i * Math.PI) / 2;
        const r = 0.22 + 0.1 * u;
        m.position.set(s.x + Math.cos(ang) * r, s.y + Math.sin(ang) * r, z + Math.sin(ang * 2) * 0.03);
        m.rotation.z = ang * 2;
        m.scale.setScalar(u < 0.7 ? 1 : (1 - u) / 0.3);
        m.visible = g ? g.visible : true;
      });
      return true;
    });
  }

  // ---------- 바드 메탈 공중 기타 꽂기 (dive ~ diveEnd) ----------
  diveStart(e) {
    const now = performance.now();
    (this.dives ||= new Map()).set(e.who, { t0: now, acc: 0 });
    const a = this.acts.get(e.who);
    if (a && a.move === '기타 꽂기' && !a.broken) Object.assign(a, { struck: a.struck || now, hold: true });
    else this.acts.set(e.who, { id: ++this.hitSeq, move: '기타 꽂기', t0: now, windup: 0, struck: now, rec: 0.4, broken: 0, air: true, hold: true });
  }

  // what: 'hit' 공중에서 꽂힌 쾅 · 'land' 발밑 충격파 · 'expire' 그냥 끝
  diveEnd(e) {
    this.dives?.delete(e.who);
    const a = this.acts.get(e.who);
    if (a && a.hold) Object.assign(a, { hold: false, struck: performance.now() - C.FIGURE_STRIKE_S * 1000 }); // 바로 회복으로
    const pos = { x: e.x, y: e.y, z: e.z };
    if (e.what === 'hit') {
      this.effects.burst({ x: e.x, y: e.y, z: e.z - 0.2 }, null, 0xffffff, 18, 6, 0.12, 0.5);
      this.effects.burst({ x: e.x, y: e.y, z: e.z - 0.2 }, null, 0xff3040, 14, 5, 0.14, 0.6);
      this.effects.ring({ x: e.x, y: e.y, z: e.z - 0.3 }, 0xff3040, 1.6, 0.3, true);
    } else if (e.what === 'land') {
      this.effects.ring({ x: e.x, y: e.y, z: e.z + 0.08 }, 0xff3040, e.r || 1.5, 0.4, true);
      this.effects.ring({ x: e.x, y: e.y, z: e.z + 0.05 }, 0xc0a880, (e.r || 1.5) * 1.3, 0.5, true);
      this.effects.burst(pos, { x: 0, y: 0 }, 0x9a8a78, 22, 5, 0.14, 0.6);
    }
  }

  // 꽂으며 떨어지는 동안: 몸 둘레로 위로 스치는 속도선 (1인칭이면 화면 둘레로 지나감)
  updateDives(dt) {
    if (!this.dives?.size) return;
    for (const [who, d] of this.dives) {
      const s = this.smooth.get(who);
      if (!s || performance.now() - d.t0 > C.BARD_DIVE_MAX_MS + 500) {
        this.dives.delete(who);
        continue;
      }
      d.acc += dt * C.DIVE_LINE_RATE;
      while (d.acc >= 1) {
        d.acc -= 1;
        const ang = Math.random() * Math.PI * 2;
        const mine = this.vm.on && this.playerMeshes.get(who) === this.vm.src;
        const r = mine ? C.DIVE_LINE_R_MINE + Math.random() * 0.8 : 0.45 + Math.random() * 0.6; // 내 1인칭이면 화면을 안 덮게 멀리
        const z = s.z + Math.random() * 1.8;
        const p = { x: s.x + Math.cos(ang) * r, y: s.y + Math.sin(ang) * r, z };
        this.trail(p, { ...p, z: z + 0.6 + Math.random() * 0.5 }, Math.random() < 0.5 ? 0xffffff : 0xff6070, 110);
      }
    }
  }

  // ---------- 탱크 ----------
  // 아머 구간 (charge: 돌진 동안, slamWarn ~ slam: 떠오르는 동안)
  armorOn(id, ms) {
    this.armorUntil.set(id, performance.now() + ms);
  }

  armorOff(id) {
    this.armorUntil.delete(id);
  }

  // armor 이벤트: 아머로 버팀 → 이 타는 안 휘청, 몸이 순간 하얗게
  armorHit(id) {
    this.armorHitAt.set(id, performance.now());
  }

  // armorBreak 이벤트: 아머 깨짐 → 이 타는 크게 휘청, 금속 빛 끝
  armorBreak(id) {
    this.armorBreakAt.set(id, performance.now());
    this.armorUntil.delete(id);
  }

  // quakeRise: 고리 모양 땅이 솟음 (격자에선 빼고 흙 블록으로 솟는 연출), quakeFall: 가라앉음
  quakeRise(cells, ms = C.TANK_RING_MS, id = null) {
    if (!this.quakeMat) this.quakeMat = toon({ color: C.QUAKE_COLOR, map: this.tex.stone });
    const meshes = cells.map(([x, y, z]) => {
      const m = new THREE.Mesh(this.bbGeo, this.quakeMat);
      m.castShadow = m.receiveShadow = true;
      m.userData.cell = [x, y, z];
      this.scene.add(m);
      return m;
    });
    this.quakes.push({ id, cells, t0: performance.now(), ms, sinkAt: 0, meshes });
    this.blockPulse(cells, 0xffe8c0, { ms: C.QUAKE_RISE_MS + 120, opacity: 0.5 });
  }

  // id 로 맞춰 가라앉힘 (서버가 같은 id 를 줌, gone 이 비어도 그 솟는 땅만). id 가 없으면 (예전 서버) 칸으로 맞추고,
  // 못 맞추면 (층 클리어로 서버 칸이 아래로 밀렸거나 덮여서 빈 목록) 가장 먼저 솟은 것 — 안 그러면 화면에만 남는 유령 블록
  quakeFall(cells, id = null) {
    const now = performance.now();
    if (id !== null && id !== undefined) {
      const q = this.quakes.find((x) => x.id === id);
      if (q && !q.sinkAt) q.sinkAt = now;
      return;
    }
    const key = (c) => c.join(',');
    const gone = new Set(cells.map(key));
    let any = false;
    for (const q of this.quakes) {
      if (!q.sinkAt && q.cells.some((c) => gone.has(key(c)))) {
        q.sinkAt = now;
        any = true;
      }
    }
    if (!any) {
      const q = this.quakes.find((x) => !x.sinkAt);
      if (q) q.sinkAt = now;
    }
  }

  // 판이 바뀌면 (새 판·맵 바꿈) 서버는 솟은 땅을 가라앉힘 이벤트 없이 버림 → 화면 것도 바로 지움
  clearQuakes() {
    for (const q of this.quakes) for (const m of q.meshes) this.scene.remove(m);
    this.quakes = [];
  }

  updateQuakes() {
    if (!this.quakes.length) return;
    const now = performance.now();
    this.quakes = this.quakes.filter((q) => {
      if (!q.sinkAt && q.id == null && now - q.t0 > q.ms + C.QUAKE_FALL_GRACE_MS) q.sinkAt = now; // 안전장치 (id 없는 예전 서버): 가라앉힘 이벤트를 놓쳐도 유령으로 안 남게
      let h; // 땅 위로 나온 높이 비율 (0~1)
      if (q.sinkAt) {
        const u = (now - q.sinkAt) / C.QUAKE_SINK_MS;
        if (u >= 1) {
          for (const m of q.meshes) this.scene.remove(m);
          return false;
        }
        h = 1 - u * u;
      } else {
        const u = Math.min(1, (now - q.t0) / C.QUAKE_RISE_MS);
        h = u < 1 ? 1 + 0.3 * Math.sin(Math.PI * u) - (1 - u) ** 2 : 1;
      }
      const shake = q.sinkAt ? C.QUAKE_SINK_SHAKE : 0;
      for (const m of q.meshes) {
        const [x, y, z] = m.userData.cell;
        m.position.set(x + 0.5 + (Math.random() - 0.5) * shake, y + 0.5 + (Math.random() - 0.5) * shake, z - 0.5 + h);
      }
      return true;
    });
  }

  // 닌자 표창 (star 이벤트, 한 발마다): 첫 발은 오른손·둘째 발은 왼손으로 던지는 자세 + 아주 빠르게 직진하는 표창 (판정은 즉시)
  starShot(e) {
    const now = performance.now();
    if (this.vm.src && this.playerMeshes.get(e.who) === this.vm.src) this.vm.starThrown();
    const a = this.acts.get(e.who);
    if (e.shot === 1 && a && (a.move === '표창' || a.move === '공중 표창') && !a.struck && !a.broken) a.struck = now;
    else {
      const move = e.shot === 1 ? '표창' : '표창2';
      this.acts.set(e.who, { id: ++this.hitSeq, move, t0: now, windup: 0, struck: now, rec: MOVES[move].rec || 0.25, broken: 0, air: !!a?.air });
    }
    if (!this.starGeo) {
      const sh = new THREE.Shape();
      for (let i = 0; i < 8; i++) {
        const r = i % 2 ? 0.05 : 0.17;
        const ang = (i / 8) * Math.PI * 2;
        if (i) sh.lineTo(Math.cos(ang) * r, Math.sin(ang) * r);
        else sh.moveTo(r, 0);
      }
      this.starGeo = new THREE.ShapeGeometry(sh);
      this.starMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xd8e0ea, side: THREE.DoubleSide }));
    }
    const m = new THREE.Mesh(this.starGeo, this.starMat);
    m.position.set(e.from.x, e.from.y, e.from.z);
    this.scene.add(m);
    (this.stars ||= []).push({ m, from: e.from, to: e.to, t0: now });
  }

  // 날아가는 표창: STAR_FLY_MS 동안 직진하며 빙글, 닿으면 사라짐 (빗나간 것은 사거리 끝에서)
  updateStars() {
    if (!this.stars?.length) return;
    const now = performance.now();
    this.stars = this.stars.filter((st) => {
      const u = (now - st.t0) / C.STAR_FLY_MS;
      if (u >= 1) {
        this.scene.remove(st.m);
        return false;
      }
      st.m.position.set(st.from.x + (st.to.x - st.from.x) * u, st.from.y + (st.to.y - st.from.y) * u, st.from.z + (st.to.z - st.from.z) * u);
      st.m.rotation.set(Math.PI / 2, 0, now / 25); // 세워서 빙글
      return true;
    });
  }

  // 세로 잔상 (벽 차기 '슈우욱'): a 에서 위로 len 칸
  streakUp(a, len, color, ms) {
    const m = new THREE.Mesh(new THREE.BoxGeometry(0.1, 0.1, len), noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, depthWrite: false })));
    m.position.set(a.x, a.y, a.z + len / 2);
    this.addMark(m, ms, false);
  }

  // 카운터히트 (counter 이벤트가 같은 타의 hit 보다 먼저 옴)
  counterHit(id) {
    this.counterAt.set(id, performance.now());
  }

  // 대포수 반동 (shellFire): 땅이면 엉덩방아 (동작), 공중이면 뒤로 래그돌 회전 (세기 recoil 만큼 바퀴·빠르기). 대포가 어깨에서 뒤로 툭
  cannonRecoil(e) {
    const g = this.playerMeshes.get(e.who);
    const fig = g?.userData.figure;
    const sm = this.smooth.get(e.who);
    const air = !!(sm && this.curState && !this.feetOnGround(this.curState, sm));
    if (fig) fig.cannonKickAt = performance.now();
    if (air && fig) {
      const a = g.userData.anim;
      a.flip = 0;
      a.flipRag = true;
      a.flipDir = -1; // 뒤로
      a.flipTurns = Math.max(1, Math.round((e.recoil || 5) / C.CANNON_FLIP_PER_TURN));
      a.flipS = a.flipTurns * C.CANNON_FLIP_TURN_S;
    } else this.skillMove(e.who, e.big ? 'cannonBigRecoil' : 'cannonRecoil');
  }

  // 2단 점프 (airJump 이벤트): 앞 공중제비
  airJump(id) {
    const g = this.playerMeshes.get(id);
    if (g && g.userData.figure) g.userData.anim.flip = 0;
  }

  // figureAnim 에 넘길 맞은 것 (몸 기준 밀린 방향). 오래되면 버림
  hitFor(p) {
    const h = this.hits.get(p.id);
    if (!h) return null;
    const age = (performance.now() - h.t0) / 1000;
    if (age > 2) {
      this.hits.delete(p.id);
      return null;
    }
    let dx = -1;
    let dy = 0;
    if (h.dir) {
      const c = Math.cos(p.yaw);
      const sn = Math.sin(p.yaw);
      dx = c * h.dir.x + sn * h.dir.y;
      dy = -sn * h.dir.x + c * h.dir.y;
    }
    if (![dx, dy, h.pow, h.stop].every(Number.isFinite)) {
      this.hits.delete(p.id); // 이상한 방향·세기는 버림
      return null;
    }
    return { id: h.id, age, stop: h.stop, dx, dy, pow: h.pow };
  }

  // 승리 연출: 판이 끝나면 모두의 카메라가 승자 정면으로 날아가고, 승자는 춤, 승자 색 색종이
  // 내 이모트(cam.selfie)도 같은 카메라로 내 앞에서 보여줌 (색종이는 승리 때만)
  victoryCamera(state, cam, dt, eye, look) {
    const id = cam.victory || cam.selfie || null;
    const s = id ? this.smooth.get(id) : null;
    const winner = s && state.players.find((p) => p.id === id);
    if (!winner) {
      this.victoryT = 0;
      return;
    }
    this.victoryT += dt;
    const k = Math.min(1, this.victoryT / C.VICTORY_FLY_S);
    const t = k * k * (3 - 2 * k); // smoothstep
    const yaw = winner.yaw;
    const front = new THREE.Vector3(s.x + Math.cos(yaw) * C.VICTORY_DIST, s.y + Math.sin(yaw) * C.VICTORY_DIST, s.z + C.VICTORY_UP);
    eye.lerp(front, t);
    look.lerp(new THREE.Vector3(s.x, s.y, s.z + C.PLAYER_HEIGHT * 0.55), t);
    if (!cam.victory) return;
    // 색종이: 승자 위에서 몇 번 터짐
    this.confettiAcc = (this.confettiAcc || 0) + dt * C.CONFETTI_RATE;
    const colors = [playerColor(winner, state), 0xffe040, 0x40d0ff, 0xff60c0, 0xffffff];
    for (; this.confettiAcc >= 1; this.confettiAcc--) {
      this.effects.burst({ x: s.x, y: s.y, z: s.z + C.PLAYER_HEIGHT + 0.6 }, null, colors[Math.floor(Math.random() * colors.length)], 6, 6, 0.09, 1.2);
    }
  }

  // 로봇 동작 고르기: 이모트 > 승리 춤 > 밀치기 > 공중 > 달리기 > 걷기 > 가만히. 바뀌면 짧게 섞어 넘어감
  robotAnim(robot, p, a, air, walking, dancing, emote, dt) {
    if (this.effects.punchAmount(p.id) > 0 && !a.punching) a.punchUntil = performance.now() + C.ROBOT_PUNCH_MS;
    a.punching = this.effects.punchAmount(p.id) > 0;
    let want = 'Idle';
    if (emote >= 0) want = C.EMOTE_CLIPS[emote];
    else if (dancing) want = 'Dance';
    else if (performance.now() < (a.punchUntil || 0)) want = 'Punch';
    else if (air) want = 'Jump';
    else if (walking) want = a.hs > C.ROBOT_RUN_SPEED ? 'Running' : 'Walking';
    if (want !== robot.current && robot.actions[want]) {
      const next = robot.actions[want];
      next.reset().play();
      robot.actions[robot.current].crossFadeTo(next, C.ROBOT_FADE_S, false);
      robot.current = want;
    }
    // 표정: 경직이면 놀람, 도발이면 화남
    if (robot.face) {
      const dict = robot.face.morphTargetDictionary;
      const inf = robot.face.morphTargetInfluences;
      const set = (k, v) => dict[k] !== undefined && (inf[dict[k]] += (v - inf[dict[k]]) * Math.min(1, dt * 10));
      set('Surprised', p.stunned ? 1 : 0);
      set('Angry', emote === 3 ? 1 : 0);
    }
    robot.mixer.update(dt);
  }

  // 이모트 동작 (춤은 위 animate 에서): 0 손 흔들기 · 2 웃기 · 3 도발. 팔은 밀치기 애니메이션 뒤에 덮어씀
  emoteAnim(g, emote, a, dt) {
    if (g.userData.robot || g.userData.figure) return; // 로봇은 모델 동작으로 (robotAnim), TABS 식 몸은 figureAnim
    const [right, left] = g.userData.arms;
    const rig = g.userData.rig;
    // 매 프레임 기본 자세로 되돌린 뒤 덮어씀 (이모트가 끝나면 팔이 제자리로). 팔이 짧아서 손 흔들기 땐 오른팔을 키움
    right.rotation.x = right.userData.baseRot.x;
    left.position.copy(left.userData.base);
    left.rotation.copy(left.userData.baseRot);
    right.scale.setScalar(1);
    left.scale.setScalar(1);
    a.emoteT = emote >= 0 && emote !== 1 ? (a.emoteT || 0) + dt : 0;
    if (!a.emoteT) return;
    const t = a.emoteT;
    const big = C.EMOTE_ARM_SCALE;
    if (emote === 0) {
      // 손 흔들기: 오른팔을 머리 옆으로 번쩍 들고 크게 좌우로
      right.scale.setScalar(big);
      right.position.z = right.userData.base.z + 0.42;
      right.rotation.x = -Math.PI / 2 + Math.sin(t * 12) * 0.6;
      rig.rotation.x += Math.sin(t * 12) * 0.08;
    } else if (emote === 2) {
      // 웃기: 배를 잡고(양팔 앞으로) 좌우로 크게 흔들며 들썩들썩
      rig.rotation.y += -0.25;
      rig.rotation.x += Math.sin(t * 22) * 0.22;
      g.userData.parts.position.z += Math.abs(Math.sin(t * 11)) * 0.12;
      right.rotation.z = Math.PI / 3;
      left.rotation.z = -Math.PI / 3;
    } else if (emote === 3) {
      // 도발: 몸을 앞뒤로 까딱이며 왼팔을 크게 앞으로 뻗어 손짓
      rig.rotation.y += 0.15 + Math.sin(t * 8) * 0.2;
      left.rotation.z = -Math.PI / 2 + Math.sin(t * 10) * 0.5; // 왼손엔 든 물건이 있어서 팔은 안 키움
      left.position.x = left.userData.base.x + 0.22;
      left.position.z = left.userData.base.z + 0.15;
    }
  }

  // 조종 중인 블록 ↔ 조종하는 사람 머리를 잇는 보라색 빛줄기 (누가 어느 블록을 모는지)
  // ---- 스킬 예고·잔상 (남에게도 보임). ms 동안 깜빡이다 사라짐 ----
  // grow: 사라지는 동안 커지는 배율 (고리가 퍼짐). parent: 붙일 곳 (캐릭터를 따라다니게)
  addMark(mesh, ms, pulse = true, grow = 0, parent = this.scene) {
    mesh.renderOrder = 8;
    parent.add(mesh);
    this.marks.push({ mesh, until: performance.now() + ms, ms, pulse, grow });
  }

  // 스킬·필살기 빛: 발밑 고리가 퍼지고 몸이 빛남 (스킬은 하얗게 순간, 필살기는 하늘색으로 길게 + 반짝이). 캐릭터를 따라다님
  aura(id, ult) {
    const g = this.playerMeshes.get(id);
    if (!g) return;
    const color = ult ? C.ULT_AURA_COLOR : C.SKILL_AURA_COLOR;
    const ms = ult ? C.ULT_AURA_MS : C.SKILL_AURA_MS;
    const ring = (r0, r1, delay) => {
      const m = new THREE.Mesh(new THREE.RingGeometry(r0, r1, 40), noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false })));
      m.position.z = 0.04;
      setTimeout(() => this.addMark(m, ms * 0.6, false, ult ? 2.6 : 1.8, g), delay);
    };
    ring(0.5, 0.58, 0);
    if (ult) ring(0.5, 0.58, ms * 0.25); // 두 겹
    g.userData.glowUntil = performance.now() + (ult ? ms : C.SKILL_GLOW_MS);
    g.userData.glowColor = color;
    g.userData.sparkUntil = ult ? performance.now() + ms : 0;
  }


  // 칸들 바닥(맨 아래 높이)에 색 판
  markCells(cells, color, ms) {
    const low = new Map();
    for (const [x, y, z] of cells) if (!low.has(x * 100 + y) || z < low.get(x * 100 + y)[2]) low.set(x * 100 + y, [x, y, z]);
    for (const [x, y, z] of low.values()) {
      const m = new THREE.Mesh(this.markBox, noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.6, depthWrite: false })));
      m.position.set(x + 0.5, y + 0.5, z + 0.05);
      this.addMark(m, ms);
    }
  }

  // 바닥에 둥근 범위 (테두리 + 옅은 속)
  markCircle(x, y, z, r, color, ms) {
    const g = new THREE.Group();
    g.add(new THREE.Mesh(new THREE.RingGeometry(r - 0.12, r, 40), noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, side: THREE.DoubleSide, depthWrite: false }))));
    g.add(new THREE.Mesh(new THREE.CircleGeometry(r, 40), noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.22, side: THREE.DoubleSide, depthWrite: false }))));
    g.position.set(x, y, z + 0.06);
    this.addMark(g, ms);
  }

  // 두 점 사이 잔상 (베기·돌진)
  trail(a, b, color, ms) {
    const len = Math.hypot(b.x - a.x, b.y - a.y, b.z - a.z) || 0.01;
    const m = new THREE.Mesh(new THREE.BoxGeometry(len, 0.08, 0.08), noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.85, depthWrite: false })));
    m.position.set((a.x + b.x) / 2, (a.y + b.y) / 2, (a.z + b.z) / 2);
    m.rotation.z = Math.atan2(b.y - a.y, b.x - a.x);
    this.addMark(m, ms, false);
  }

  updateMarks() {
    const now = performance.now();
    for (let i = this.marks.length - 1; i >= 0; i--) {
      const mk = this.marks[i];
      const left = mk.until - now;
      if (left <= 0) {
        mk.mesh.parent?.remove(mk.mesh);
        mk.mesh.traverse((o) => {
          if (o.isMesh) {
            if (o.geometry !== this.markBox) o.geometry.dispose();
            o.material.dispose();
          }
        });
        this.marks.splice(i, 1);
        continue;
      }
      // 예고는 끝이 가까울수록 빨리 깜빡, 잔상은 서서히 사라짐
      const k = mk.pulse ? 0.7 + 0.3 * Math.sin(now / Math.max(40, left / 6)) : left / mk.ms; // 예고는 가장 옅을 때도 40% (끝까지 분명히)
      if (mk.grow) {
        const sc = 1 + mk.grow * (1 - left / mk.ms);
        mk.mesh.scale.set(sc, sc, mk.mesh.scale.z);
      }
      mk.mesh.traverse((o) => {
        if (o.isMesh) o.material.opacity = (o.material.userData.base ??= o.material.opacity) * k;
      });
    }
  }

  // ---------- 블록이 주인공: 블록이 움직이거나 바뀌는 순간 ----------
  // 칸마다 살짝 큰 반투명 상자가 번쩍 → 부풀며 사라짐 (블록 위에 겹쳐서, 바닥 그림자는 안 가림). jolt 면 블록이 들썩하듯 위로 튐
  blockPulse(cells, color = 0xffffff, { ms = C.BLOCK_PULSE_MS, jolt = 0, opacity = 0.75 } = {}) {
    if (!cells?.length) return;
    if (!this.pulseGeo) this.pulseGeo = new THREE.BoxGeometry(1.04, 1.04, 1.04);
    const mat = noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity, depthWrite: false }));
    for (const [x, y, z] of cells) {
      if (![x, y, z].every(Number.isFinite)) continue;
      const m = new THREE.Mesh(this.pulseGeo, mat);
      m.position.set(x + 0.5, y + 0.5, z + 0.5);
      m.renderOrder = 5;
      this.scene.add(m);
      (this.pulses ||= []).push({ m, mat, t0: performance.now(), ms, jolt, base: z + 0.5, opacity });
    }
  }

  // cells 바로 옆(6방향)에 붙은 격자 블록: 터지거나 뽑히거나 박힐 때 옆 블록도 들썩이게
  blockNeighbors(cells) {
    const st = this.curState;
    if (!st?.grid) return [];
    const own = new Set(cells.map((c) => c.join(',')));
    const out = new Map();
    for (const [x, y, z] of cells)
      for (const [dx, dy, dz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
        const c = [x + dx, y + dy, z + dz];
        const k = c.join(',');
        if (c[2] >= 0 && !own.has(k) && this.solidAt(st, c[0] + 0.5, c[1] + 0.5, c[2] + 0.5)) out.set(k, c);
      }
    return [...out.values()];
  }

  updatePulses() {
    if (!this.pulses?.length) return;
    const now = performance.now();
    const gone = new Set();
    this.pulses = this.pulses.filter((p) => {
      const u = (now - p.t0) / p.ms;
      if (u >= 1) {
        this.scene.remove(p.m);
        gone.add(p.mat);
        return false;
      }
      p.m.scale.setScalar(1 + 0.25 * u);
      p.m.position.z = p.base + p.jolt * Math.sin(Math.PI * Math.min(1, u * 2));
      p.mat.opacity = p.opacity * (1 - u) * (1 - u);
      return true;
    });
    for (const mat of gone) if (!this.pulses.some((p) => p.mat === mat)) mat.dispose();
  }

  // ---------- 사냥꾼 ----------
  // 표식: 머리 위 이름표 바로 위에 빨간 마름모 1~3개 (화면 크기 고정 스프라이트). 사라지기 직전 깜빡.
  // 내가 붙인 표식이 있으면 그것을, 없으면 가장 많은 것을 보여줌. 내가 붙인 표식 대상은 블록 뒤에서도 몸이 빨갛게 보임 (사냥꾼의 눈)
  updateHuntMarks(g, p, myId) {
    if (!g.userData.bodyOrder) {
      // 사람 몸은 사냥꾼의 눈 복사본(1) 뒤에 그림 (2) → 복사본은 블록·땅에 가린 곳에만 나옴 (다른 사람 몸에 가린 곳엔 안 나옴)
      g.traverse((o) => {
        if (o.isMesh && o.renderOrder === 0) o.renderOrder = 2;
      });
      g.userData.bodyOrder = true;
    }
    const list = p.marks || [];
    const mine = list.find((m) => m.by === myId);
    const m = mine || list.reduce((a, b) => (!a || b.n > a.n ? b : a), null);
    let hm = g.userData.huntMarks;
    if (m && !hm) {
      const canvas = document.createElement('canvas');
      canvas.width = 96;
      canvas.height = 32;
      const tex = new THREE.CanvasTexture(canvas);
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, depthWrite: false, transparent: true, sizeAttenuation: false }));
      sprite.scale.set(0.09, 0.03, 1);
      sprite.center.set(0.5, -1.4); // 이름표(같은 높이) 위로
      sprite.position.z = g.userData.labelZ ?? C.PLAYER_HEIGHT + 0.45;
      sprite.renderOrder = 12;
      g.add(sprite);
      hm = g.userData.huntMarks = { sprite, canvas, tex, n: 0 };
    }
    if (hm) {
      const n = m && p.alive ? Math.min(C.HUNTER_MARK_MAX, m.n) : 0;
      if (n !== hm.n) {
        const c = hm.canvas.getContext('2d');
        c.clearRect(0, 0, 96, 32);
        for (let i = 0; i < n; i++) {
          const x = 48 + (i - (n - 1) / 2) * 30;
          c.beginPath();
          c.moveTo(x, 3);
          c.lineTo(x + 11, 16);
          c.lineTo(x, 29);
          c.lineTo(x - 11, 16);
          c.closePath();
          c.fillStyle = '#ff3a2a';
          c.fill();
          c.lineWidth = 3;
          c.strokeStyle = '#300';
          c.stroke();
        }
        hm.tex.needsUpdate = true;
        hm.n = n;
      }
      const blink = m && m.left < C.MARK_BLINK_MS && Math.floor(performance.now() / C.MARK_BLINK_PERIOD_MS) % 2 === 1;
      hm.sprite.visible = n > 0 && !blink && !(p.id === myId && !this.third);
      hm.sprite.material.depthTest = !mine; // 내 표식은 블록 뒤에서도 보임
    }
    this.huntEye(g, !!mine && p.alive && p.id !== myId);
  }

  // R 게이지가 찬 상대: 발밑~몸 둘레에 옅은 하늘색 빛 (필살기 빛과 같은 계열, 압사 빨강·치명타 노랑과 다른 색). 은은하게 숨 쉬듯.
  // 나는 안 그림 (HUD 로 앎). 사냥꾼은 ultMax(200) 기준
  updateUltAura(g, p, s, myId, dt) {
    const full = p.alive && !p.master && p.char && p.id !== myId && p.ult >= (p.ultMax || C.ULT_MAX);
    let au = g.userData.ultAura;
    if (!full) {
      if (au) au.grp.visible = false;
      return;
    }
    if (!au) {
      if (!this.ultAuraTex) {
        // 아래가 밝고 위로 사라지는 세로 그라데이션 (빛기둥 옆면) / 가운데가 밝은 원 (바닥)
        const c = document.createElement('canvas');
        c.width = 4;
        c.height = 64;
        const x = c.getContext('2d');
        const gr = x.createLinearGradient(0, 64, 0, 0);
        gr.addColorStop(0, 'rgba(255,255,255,1)');
        gr.addColorStop(0.35, 'rgba(255,255,255,0.45)');
        gr.addColorStop(1, 'rgba(255,255,255,0)');
        x.fillStyle = gr;
        x.fillRect(0, 0, 4, 64);
        this.ultAuraTex = new THREE.CanvasTexture(c);
        const d = document.createElement('canvas');
        d.width = d.height = 64;
        const y = d.getContext('2d');
        const rg = y.createRadialGradient(32, 32, 4, 32, 32, 32);
        rg.addColorStop(0, 'rgba(255,255,255,0.9)');
        rg.addColorStop(0.7, 'rgba(255,255,255,0.35)');
        rg.addColorStop(1, 'rgba(255,255,255,0)');
        y.fillStyle = rg;
        y.fillRect(0, 0, 64, 64);
        this.ultFloorTex = new THREE.CanvasTexture(d);
      }
      const mk = (map) => noOutline(new THREE.MeshBasicMaterial({ color: C.ULT_AURA_COLOR, map, transparent: true, opacity: C.ULT_READY_AURA_OPACITY, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide }));
      const grp = new THREE.Group();
      const wall = new THREE.CylinderGeometry(0.42, 0.5, C.PLAYER_HEIGHT * 1.1, 20, 1, true);
      wall.rotateX(Math.PI / 2);
      wall.translate(0, 0, (C.PLAYER_HEIGHT * 1.1) / 2);
      const wallMat = mk(this.ultAuraTex);
      const floorMat = mk(this.ultFloorTex);
      const wallM = new THREE.Mesh(wall, wallMat);
      const floorM = new THREE.Mesh(new THREE.CircleGeometry(0.75, 24), floorMat);
      floorM.position.z = 0.03;
      for (const m of [wallM, floorM]) {
        m.renderOrder = 6;
        grp.add(m);
      }
      this.scene.add(grp);
      au = g.userData.ultAura = { grp, mats: [wallMat, floorMat] };
    }
    au.grp.visible = true;
    au.grp.position.set(s.x, s.y, s.z);
    const breathe = 0.75 + 0.25 * Math.sin(performance.now() / 420);
    for (const m of au.mats) m.opacity = C.ULT_READY_AURA_OPACITY * breathe;
    // 가끔 반짝이 하나가 몸 둘레에서 위로 (필살기 빛과 같은 느낌, 아주 적게)
    if (Math.random() < dt * C.ULT_READY_SPARKLE_RATE) {
      const a = Math.random() * Math.PI * 2;
      this.effects.burst({ x: s.x + Math.cos(a) * 0.4, y: s.y + Math.sin(a) * 0.4, z: s.z + 0.2 + Math.random() * 0.8 }, { x: 0, y: 0 }, C.ULT_AURA_COLOR, 1, 0.6, 0.05, 0.6);
    }
  }

  // 사냥꾼의 눈: 몸 부품마다 같은 모양의 빨간 복사본을 붙여, 블록에 가려진 부분에만 그림 (GreaterDepth).
  // 복사본은 블록 다음·사람 몸 전에 그려서 (renderOrder 1 → 몸 2) 몸에 가린 곳엔 안 나옴
  huntEye(g, on) {
    let xr = g.userData.xray;
    if (on && !xr) {
      if (!this.xrayMat) this.xrayMat = noOutline(new THREE.MeshBasicMaterial({ color: C.HUNT_EYE_COLOR, depthFunc: THREE.GreaterDepth, depthWrite: false }));
      const parts = [];
      g.traverse((o) => {
        if (o.isMesh && !o.isInstancedMesh && !o.userData.batched && o.material !== this.xrayMat) parts.push(o); // 합친 조각은 합친 메시로 한 번에
      });
      xr = g.userData.xray = [];
      for (const o of parts) {
        let x;
        if (o.userData.pieceBatch) {
          x = new THREE.SkinnedMesh(o.geometry, this.xrayMat);
          x.bind(o.skeleton, o.bindMatrix);
          x.frustumCulled = false;
        } else x = new THREE.Mesh(o.geometry, this.xrayMat);
        x.renderOrder = 1;
        x.castShadow = false;
        o.add(x);
        xr.push(x);
      }
    }
    if (xr) for (const x of xr) x.visible = on;
  }

  // aim 이벤트: 대상마다 빨간 조준점 (화면을 보는 원 + 십자), 0.5초 동안 크게 → 작게 조여 듦. 블록 너머에서도 보임
  aimAt(e) {
    if (!this.aimGeo) {
      this.aimGeo = new THREE.RingGeometry(0.26, 0.33, 24);
      this.aimTick = new THREE.PlaneGeometry(0.06, 0.16);
    }
    const mat = noOutline(new THREE.MeshBasicMaterial({ color: 0xff2a1a, transparent: true, opacity: 0.95, depthTest: false, depthWrite: false, side: THREE.DoubleSide }));
    const now = performance.now();
    for (const id of e.targets || []) {
      const grp = new THREE.Group();
      grp.add(new THREE.Mesh(this.aimGeo, mat));
      for (let k = 0; k < 4; k++) {
        const t = new THREE.Mesh(this.aimTick, mat);
        const a = (k * Math.PI) / 2;
        t.position.set(Math.cos(a) * 0.4, Math.sin(a) * 0.4, 0);
        t.rotation.z = a + Math.PI / 2;
        grp.add(t);
      }
      grp.renderOrder = 13;
      grp.traverse((o) => (o.renderOrder = 13));
      this.scene.add(grp);
      (this.aims ||= []).push({ grp, mat, target: id, who: e.who, t0: now, ms: e.ms || 500 });
    }
  }

  // 쏘거나 끊기면 조준점을 지움 (who 의 것만)
  aimEnd(who) {
    if (!this.aims) return;
    for (const a of this.aims) if (a.who === who) a.t0 = -Infinity;
  }

  updateAims() {
    if (!this.aims?.length) return;
    const now = performance.now();
    this.aims = this.aims.filter((a) => {
      const s = this.smooth.get(a.target);
      const u = (now - a.t0) / (a.ms + C.WARN_TAIL_MS);
      if (u >= 1 || !s) {
        this.scene.remove(a.grp);
        a.mat.dispose();
        return false;
      }
      a.grp.position.set(s.x, s.y, s.z + C.PLAYER_HEIGHT * 0.6);
      a.grp.quaternion.copy(this.camera.quaternion);
      const k = Math.min(1, u * 1.3);
      a.grp.scale.setScalar(1.7 - 0.7 * k * k * (3 - 2 * k)); // 조여 듦
      return true;
    });
  }

  // shot 이벤트: 대상마다 석궁 화살이 아주 빠르게 날아감. 막혔으면 가린 블록 앞면에 박혀 잠깐 남음 (그 블록이 들썩)
  shoot(e) {
    this.aimEnd(e.who);
    if (!e.from) return;
    if (!this.arrowGeo) {
      this.arrowGeo = new THREE.BoxGeometry(0.5, 0.03, 0.03);
      this.arrowHead = new THREE.ConeGeometry(0.045, 0.12, 4).rotateZ(-Math.PI / 2);
      this.arrowMat = toon({ color: 0x8a5a30 });
      this.arrowHeadMat = toon({ color: 0xb8c2cc });
      this.arrowFeather = new THREE.BoxGeometry(0.1, 0.008, 0.07);
      this.arrowFeatherMat = toon({ color: 0xd8352a });
    }
    const now = performance.now();
    for (const sh of e.shots || []) {
      const from = new THREE.Vector3(e.from.x, e.from.y, e.from.z - 0.2);
      let to = new THREE.Vector3(sh.to.x, sh.to.y, sh.to.z);
      let stuck = null;
      if (sh.blocked && this.curState) {
        // 시선을 따라 가며 처음 만나는 블록 칸 앞에서 멈춤
        const dir = to.clone().sub(from);
        const len = dir.length();
        dir.normalize();
        for (let d = 0.3; d < len; d += 0.05) {
          const q = from.clone().addScaledVector(dir, d);
          if (this.solidAt(this.curState, q.x, q.y, q.z)) {
            to = from.clone().addScaledVector(dir, d - 0.15);
            stuck = [Math.floor(q.x), Math.floor(q.y), Math.floor(q.z)];
            break;
          }
        }
      }
      const g = new THREE.Group();
      const shaft = new THREE.Mesh(this.arrowGeo, this.arrowMat);
      shaft.position.x = -0.25;
      g.add(shaft);
      const head = new THREE.Mesh(this.arrowHead, this.arrowHeadMat);
      head.position.x = 0.04;
      g.add(head);
      for (const r of [0, Math.PI / 2]) {
        const f = new THREE.Mesh(this.arrowFeather, this.arrowFeatherMat);
        f.position.x = -0.46;
        f.rotation.x = r;
        g.add(f);
      }
      g.quaternion.setFromUnitVectors(new THREE.Vector3(1, 0, 0), to.clone().sub(from).normalize());
      g.position.copy(from);
      this.scene.add(g);
      (this.arrows ||= []).push({ g, from, to, t0: now, stuck, done: false });
      this.trail(from, to, 0xff5040, C.ARROW_TRAIL_MS);
    }
  }

  updateArrows() {
    if (!this.arrows?.length) return;
    const now = performance.now();
    this.arrows = this.arrows.filter((a) => {
      const u = (now - a.t0) / C.ARROW_FLY_MS;
      if (u < 1) {
        a.g.position.lerpVectors(a.from, a.to, u);
        return true;
      }
      a.g.position.copy(a.to);
      if (!a.done) {
        a.done = true;
        if (a.stuck) {
          // 박힘: 나무 부스러기 + 블록 들썩 + 퍽
          this.effects.burst(a.to, null, 0x9a8a78, 10, 2.5, 0.08, 0.4);
          this.blockPulse([a.stuck], 0xffffff, { jolt: C.BLOCK_JOLT, opacity: 0.6 });
          if (this.onArrowStuck) this.onArrowStuck(a.to);
        }
      }
      if (!a.stuck || u * C.ARROW_FLY_MS > C.ARROW_FLY_MS + C.ARROW_STUCK_MS) {
        this.scene.remove(a.g);
        return false;
      }
      return true;
    });
  }

  // melt 이벤트: 용암에 닿은 블록이 녹음 — 칸마다 주황 번쩍 + 지글 불티 + 검은·회색 연기 기둥
  melt(e) {
    const cells = (e.cells || []).filter((c) => c.every(Number.isFinite));
    if (!cells.length) return;
    this.blockPulse(cells, 0xff7020, { opacity: 0.8, ms: C.BLOCK_PULSE_MS * 1.6 });
    for (const [x, y, z] of cells) {
      const c = { x: x + 0.5, y: y + 0.5, z: z + 0.3 };
      this.effects.burst(c, null, 0xffa030, 6, 3, 0.08, 0.4);
      this.effects.burst({ x: c.x, y: c.y, z: c.z + 0.4 }, { x: 0, y: 0 }, 0x555555, 5, 1.2, 0.18, 1.1);
    }
  }

  // ---------- 바드 ----------
  // 류트 음파 (snapshot notes): 초록·금색으로 빛나는 8분음표가 위아래로 살랑이며 날아감 + 반짝이 꼬리. 30Hz 사이는 날아가는 방향으로 이어 그림
  updateNotes(list, dt) {
    if (!this.noteMeshes) {
      this.noteMeshes = new Map();
      this.noteMat = noOutline(new THREE.MeshBasicMaterial({ color: C.BARD_NOTE_COLOR }));
      const g = new THREE.Group();
      const head = new THREE.Mesh(new THREE.SphereGeometry(0.11, 10, 8), this.noteMat);
      head.scale.set(1.3, 0.6, 0.9);
      g.add(head);
      const stem = new THREE.Mesh(new THREE.BoxGeometry(0.03, 0.03, 0.34), this.noteMat);
      stem.position.set(0.12, 0, 0.17);
      g.add(stem);
      const flag = new THREE.Mesh(new THREE.BoxGeometry(0.14, 0.025, 0.05), this.noteMat);
      flag.position.set(0.18, 0, 0.3);
      flag.rotation.y = 0.6;
      g.add(flag);
      this.noteProto = g;
    }
    const now = performance.now();
    const seen = new Set();
    for (const nt of list) {
      seen.add(nt.id);
      let m = this.noteMeshes.get(nt.id);
      if (!m) {
        const mesh = this.noteProto.clone();
        this.scene.add(mesh);
        m = { mesh, x: nt.x, y: nt.y, z: nt.z, at: now, t0: now, spark: 0 };
        this.noteMeshes.set(nt.id, m);
      }
      if (nt.x !== m.x || nt.y !== m.y || nt.z !== m.z) Object.assign(m, { x: nt.x, y: nt.y, z: nt.z, at: now });
      m.dir = nt.dir;
    }
    for (const [id, m] of this.noteMeshes) {
      if (!seen.has(id)) {
        this.scene.remove(m.mesh);
        this.noteMeshes.delete(id);
        continue;
      }
      const d = m.dir || { x: 0, y: 0, z: 0 };
      const ahead = Math.min(0.1, (now - m.at) / 1000) * C.BARD_NOTE_SPEED;
      const x = m.x + d.x * ahead;
      const y = m.y + d.y * ahead;
      const z = m.z + d.z * ahead + Math.sin((now - m.t0) / 70) * 0.12; // 살랑
      if (![x, y, z].every(Number.isFinite)) continue;
      m.mesh.position.set(x, y, z);
      m.mesh.rotation.z = Math.atan2(d.y, d.x) + Math.PI / 2; // 옆에서 보이게
      m.mesh.rotation.x = Math.sin((now - m.t0) / 120) * 0.4;
      m.spark += dt * 18;
      while (m.spark >= 1) {
        m.spark -= 1;
        this.effects.burst({ x, y, z }, { x: 0, y: 0 }, Math.random() < 0.5 ? C.BARD_NOTE_COLOR : 0xffe070, 1, 0.5, 0.05, 0.35);
      }
    }
  }

  // 머리 위 표시: 취약(vulnLeft) = 분홍 ♫ 가 통통 (넉백 ×1.3, 멀리서도 보이게) / 둔화(slowLeft) = 발밑 옅은 파란 소용돌이 (약하게)
  updateStatusFx(g, p, s, myId) {
    let fx = g.userData.statusFx;
    const vuln = p.alive && p.vulnLeft > 0;
    const slow = p.alive && p.slowLeft > 0;
    if (!fx && (vuln || slow)) {
      const c = document.createElement('canvas');
      c.width = c.height = 64;
      const x = c.getContext('2d');
      x.fillStyle = '#ff6ad5';
      x.strokeStyle = '#3a0030';
      x.lineWidth = 4;
      x.font = 'bold 54px sans-serif';
      x.textAlign = 'center';
      x.textBaseline = 'middle';
      x.strokeText('♫', 32, 34);
      x.fillText('♫', 32, 34);
      const sprite = new THREE.Sprite(new THREE.SpriteMaterial({ map: new THREE.CanvasTexture(c), depthWrite: false, transparent: true, sizeAttenuation: false }));
      sprite.scale.set(0.07, 0.07, 1);
      sprite.center.set(0.5, -1.2); // 이름표 위
      sprite.position.z = g.userData.labelZ ?? C.PLAYER_HEIGHT + 0.45;
      sprite.renderOrder = 12;
      g.add(sprite);
      const ring = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.5, 24, 1, 0, Math.PI * 1.5), noOutline(new THREE.MeshBasicMaterial({ color: 0x6aa8ff, transparent: true, opacity: 0.35, side: THREE.DoubleSide, depthWrite: false })));
      ring.position.z = 0.04;
      g.add(ring);
      fx = g.userData.statusFx = { sprite, ring };
    }
    if (!fx) return;
    fx.sprite.visible = vuln && !(p.id === myId && !this.third);
    if (fx.sprite.visible) fx.sprite.center.y = -1.2 - 0.25 * Math.abs(Math.sin(performance.now() / 160));
    fx.ring.visible = slow;
    if (slow) fx.ring.rotation.z = -performance.now() / 300;
  }

  // 메탈 R 앰프 음파: 뒤에서 한 박자 늦게 따라오는 앰프 (검은 상자 + 스피커 + 빨간 테) + 앞 원뿔로 번쩍이는 전격 음파
  updateAmpFx(g, p, s, dt) {
    const on = !!(p.bard && p.bard.ampLeft > 0 && p.alive);
    let a = g.userData.ampFx;
    if (on && !a) {
      const cab = new THREE.Group();
      cab.add(new THREE.Mesh(new THREE.BoxGeometry(0.45, 0.6, 0.7), toon({ color: 0x1a1a1e })));
      const grille = new THREE.Mesh(new THREE.CircleGeometry(0.2, 16), noOutline(new THREE.MeshBasicMaterial({ color: 0x3a3a44 })));
      grille.rotation.y = Math.PI / 2;
      grille.position.set(0.23, 0, 0.05);
      cab.add(grille);
      const cone = new THREE.Mesh(new THREE.CircleGeometry(0.09, 12), noOutline(new THREE.MeshBasicMaterial({ color: 0x111111 })));
      cone.rotation.y = Math.PI / 2;
      cone.position.set(0.235, 0, 0.05);
      cab.add(cone);
      const edge = new THREE.Mesh(new THREE.BoxGeometry(0.47, 0.62, 0.05), toon({ color: 0xd8202a }));
      edge.position.z = 0.33;
      cab.add(edge);
      cab.traverse((o) => (o.castShadow = true));
      this.scene.add(cab);
      a = g.userData.ampFx = { cab, x: s.x, y: s.y, bolt: 0, waveAcc: 0 };
    }
    if (!a) return;
    a.cab.visible = on;
    if (!on) return;
    const yaw = Number.isFinite(p.bard.ampYaw) ? p.bard.ampYaw : p.yaw; // 연주 방향 (BARD_AMP_LOCK_YAW 면 시작 때 고정, snapshot bard.ampYaw)
    // 앰프: 몸 왼쪽 뒤 비스듬히 1.1칸으로 늦게 따라옴 (바로 뒤면 3인칭 카메라를 가림), 바닥에 놓인 채 통통
    const back = yaw + Math.PI * 0.75;
    const bx = s.x + Math.cos(back) * 1.1;
    const by = s.y + Math.sin(back) * 1.1;
    const k = 1 - Math.exp(-6 * dt);
    a.x += (bx - a.x) * k;
    a.y += (by - a.y) * k;
    const now = performance.now();
    a.cab.position.set(a.x, a.y, s.z + 0.35 + Math.abs(Math.sin(now / 90)) * 0.06);
    a.cab.rotation.z = yaw;
    // 음파: 앞 원뿔 각만큼 벌어진 얇은 호가 몸에서 사거리까지 퍼지며 사라짐 (화면을 덮지 않게 선만)
    a.waveAcc += dt * 1000;
    if (a.waveAcc >= C.BARD_AMP_WAVE_MS) {
      a.waveAcc = 0;
      const half = ((C.BARD_AMP_ANGLE_DEG / 2) * Math.PI) / 180;
      for (const dz of [0.75, 1.3]) {
        const geo = new THREE.RingGeometry(0.86, 1, 20, 1, -half, half * 2);
        const mat = noOutline(new THREE.MeshBasicMaterial({ color: C.BARD_AMP_COLOR, transparent: true, opacity: 0.8, side: THREE.DoubleSide, depthWrite: false }));
        const m = new THREE.Mesh(geo, mat);
        m.position.set(s.x, s.y, s.z + dz);
        m.rotation.z = yaw;
        m.renderOrder = 5;
        this.scene.add(m);
        (this.ampWaves ||= []).push({ m, mat, t0: now });
      }
    }
    // 전격: 원뿔 안에 짧은 번개 줄
    a.bolt += dt * 14;
    while (a.bolt >= 1) {
      a.bolt -= 1;
      const ang = yaw + (Math.random() - 0.5) * ((C.BARD_AMP_ANGLE_DEG * Math.PI) / 180);
      const r1 = 0.6 + Math.random() * (C.BARD_AMP_RANGE - 1.2);
      const r2 = r1 + 0.4 + Math.random() * 0.5;
      const z = s.z + 0.6 + Math.random() * 0.8;
      this.trail({ x: s.x + Math.cos(ang) * r1, y: s.y + Math.sin(ang) * r1, z }, { x: s.x + Math.cos(ang + 0.08) * r2, y: s.y + Math.sin(ang + 0.08) * r2, z: z + (Math.random() - 0.5) * 0.4 }, Math.random() < 0.5 ? 0xffffff : C.BARD_AMP_COLOR, 90);
    }
  }

  updateAmpWaves() {
    if (!this.ampWaves?.length) return;
    const now = performance.now();
    this.ampWaves = this.ampWaves.filter((w) => {
      const u = (now - w.t0) / C.BARD_AMP_WAVE_LIFE_MS;
      if (u >= 1) {
        this.scene.remove(w.m);
        w.m.geometry.dispose();
        w.mat.dispose();
        return false;
      }
      w.m.scale.setScalar(0.4 + u * (C.BARD_AMP_RANGE - 0.4));
      w.mat.opacity = 0.8 * (1 - u);
      return true;
    });
  }

  // glideRing 이벤트: 음유 천천히 낙하 음파 고리 (피해 있음) — 몸 둘레 판정 반경 e.r 까지 퍼지는 두 겹 고리 + 음표 반짝
  bardGlideRing(e) {
    const pos = { x: e.x, y: e.y, z: e.z + 0.9 };
    this.effects.ring(pos, C.BARD_NOTE_COLOR, e.r - 0.2, 0.3, true);
    this.effects.ring(pos, 0xffffff, (e.r - 0.2) * 0.8, 0.22, true);
    this.effects.burst(pos, null, C.BARD_NOTE_COLOR, 10, 3, 0.06, 0.3);
  }

  // form 이벤트: 메탈 = 리프 충격파 (빨간 고리 + 불꽃) + 류트 줄이 팅 끊어져 튐 / 음유 = 초록 치유파 (고리 + 위로 오르는 반짝이)
  bardForm(e) {
    const pos = { x: e.x ?? 0, y: e.y ?? 0, z: (e.z ?? 0) + 0.1 };
    const sm = this.smooth.get(e.who);
    if (e.x === undefined && sm) Object.assign(pos, { x: sm.x, y: sm.y, z: sm.z + 0.1 });
    if (e.form === 'metal') {
      this.effects.ring(pos, 0xff3040, (e.r || 1.8) * 2, 0.35, true);
      this.effects.ring({ x: pos.x, y: pos.y, z: pos.z + 1 }, 0x4060ff, (e.r || 1.8) * 1.6, 0.3);
      this.effects.burst({ x: pos.x, y: pos.y, z: pos.z + 1 }, null, 0xff4050, 22, 6, 0.1, 0.4);
      this.effects.burst({ x: pos.x, y: pos.y, z: pos.z + 1.1 }, null, 0xf0e8d0, 6, 7, 0.04, 0.35); // 끊어진 류트 줄
      if (this.onBlast) this.onBlast(pos, false);
    } else {
      this.effects.ring(pos, 0x60ff90, 4, 0.5, true);
      this.effects.burst({ x: pos.x, y: pos.y, z: pos.z + 0.8 }, { x: 0, y: 0 }, 0x80ffa0, 18, 2.5, 0.08, 0.9);
      for (const h of e.healed || []) {
        const t = this.smooth.get(h.id);
        if (t) this.effects.burst({ x: t.x, y: t.y, z: t.z + 1 }, { x: 0, y: 0 }, 0x80ffa0, 14, 2, 0.08, 1.0);
      }
    }
  }

  // song: 앞 부채꼴로 분홍 음표 물결 + 걸린 사람마다 분홍 번쩍
  bardSong(e) {
    const half = ((C.BARD_SONG_ANGLE_DEG / 2) * Math.PI) / 180;
    for (let k = 0; k < 14; k++) {
      const ang = e.yaw + (Math.random() * 2 - 1) * half;
      const r = 0.8 + Math.random() * 1.2;
      this.effects.burst({ x: e.x + Math.cos(ang) * r, y: e.y + Math.sin(ang) * r, z: e.z + 0.9 + Math.random() * 0.6 }, { x: Math.cos(ang) * 1.5, y: Math.sin(ang) * 1.5 }, 0xff6ad5, 1, 4, 0.08, 0.6);
    }
    this.effects.ring({ x: e.x, y: e.y, z: e.z + 1 }, 0xff6ad5, C.BARD_SONG_RANGE * 0.9, 0.4);
    for (const id of e.targets || []) {
      const t = this.smooth.get(id);
      if (t) this.effects.burst({ x: t.x, y: t.y, z: t.z + 1.4 }, null, 0xff6ad5, 12, 3, 0.08, 0.5);
    }
  }

  // ampEnd: 앞 원뿔 끝까지 큰 전격 쾅
  ampEnd(e) {
    const r = C.BARD_AMP_RANGE * 0.6;
    const pos = { x: e.x + Math.cos(e.yaw) * r, y: e.y + Math.sin(e.yaw) * r, z: e.z + 1 };
    this.effects.ring(pos, C.BARD_AMP_COLOR, 4, 0.35);
    this.effects.burst(pos, { x: Math.cos(e.yaw) * 1.5, y: Math.sin(e.yaw) * 1.5 }, 0xffffff, 26, 8, 0.08, 0.35);
    this.effects.burst(pos, null, C.BARD_AMP_COLOR, 20, 5, 0.1, 0.5);
    if (this.onBlast) this.onBlast(pos, true);
  }

  // ---------- 대포수 ----------
  // 포탄 (snapshot shells): 보통 = 쇠공 + 회색 연기 꼬리, 대형 = 큰 쇠공 + 빨갛게 달아오른 테 + 불·연기 꼬리.
  // 30Hz 사이는 받은 위치에서 날아가는 방향으로 이어서 (끊김 없이). 끝나면 shellEnd 가 효과
  updateShells(list, dt) {
    if (!this.shellMeshes) {
      this.shellMeshes = new Map();
      this.shellGeo = new THREE.IcosahedronGeometry(1, 1);
      this.shellMat = toon({ color: 0x2a2c30 });
      this.bigShellMat = toon({ color: 0x3a2a26, emissive: 0x501000 });
      this.shellBandMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xff6a20 }));
    }
    const now = performance.now();
    const seen = new Set();
    for (const sh of list) {
      seen.add(sh.id);
      let m = this.shellMeshes.get(sh.id);
      if (!m) {
        const big = !!sh.big;
        const mesh = new THREE.Mesh(this.shellGeo, big ? this.bigShellMat : this.shellMat);
        mesh.scale.setScalar(big ? C.SHELL_BIG_SIZE : C.SHELL_SIZE);
        mesh.castShadow = true;
        if (big) {
          const band = new THREE.Mesh(new THREE.TorusGeometry(1.02, 0.12, 4, 16), this.shellBandMat);
          mesh.add(band);
        }
        this.scene.add(mesh);
        m = { mesh, big, x: sh.x, y: sh.y, z: sh.z, at: now, speed: big ? C.CANNON_R_SPEED : C.CANNON_SHELL_SPEED, smoke: 0 };
        this.shellMeshes.set(sh.id, m);
      }
      if (sh.x !== m.x || sh.y !== m.y || sh.z !== m.z) Object.assign(m, { x: sh.x, y: sh.y, z: sh.z, at: now });
      m.dir = sh.dir;
    }
    for (const [id, m] of this.shellMeshes) {
      if (!seen.has(id)) {
        this.scene.remove(m.mesh);
        this.shellMeshes.delete(id);
        continue;
      }
      const ahead = Math.min(0.1, (now - m.at) / 1000) * m.speed; // 다음 위치가 올 때까지 날아가는 쪽으로
      const d = m.dir || { x: 0, y: 0, z: 0 };
      const x = m.x + d.x * ahead;
      const y = m.y + d.y * ahead;
      const z = m.z + d.z * ahead;
      if (![x, y, z].every(Number.isFinite)) continue;
      m.mesh.position.set(x, y, z);
      m.mesh.rotation.x += dt * 9;
      m.mesh.rotation.z += dt * 6;
      // 꼬리: 보통은 회색 연기, 대형은 불꽃 + 진한 연기
      m.smoke += dt * (m.big ? 60 : 30);
      while (m.smoke >= 1) {
        m.smoke -= 1;
        const back = { x: x - d.x * 0.2, y: y - d.y * 0.2, z: z - d.z * 0.2 };
        this.effects.burst(back, { x: 0, y: 0 }, m.big ? (Math.random() < 0.5 ? 0xff7a20 : 0x555555) : 0xaaaaaa, 1, 0.4, m.big ? 0.16 : 0.09, m.big ? 0.5 : 0.45);
      }
    }
  }

  // shellFire: 포구 불꽃 + 연기 뭉치 (쏘는 쪽으로)
  muzzleBlast(e) {
    const d = e.dir || { x: 1, y: 0, z: 0 };
    const pos = { x: e.x, y: e.y, z: e.z };
    this.effects.burst(pos, { x: d.x * 1.2, y: d.y * 1.2 }, 0xffd040, e.big ? 22 : 12, e.big ? 7 : 5, e.big ? 0.15 : 0.1, 0.25);
    this.effects.burst(pos, { x: d.x * 0.6, y: d.y * 0.6 }, 0x888888, e.big ? 26 : 14, e.big ? 3.5 : 2.5, e.big ? 0.2 : 0.14, 0.8);
    this.effects.ring(pos, 0xffe0a0, e.big ? 2.6 : 1.4, 0.2);
  }

  // shellEnd: 닿은 것에 따라 (사람·블록·지형·바닥 = 터짐, expire = 연기만). 대형 포탄은 bigShellBlast 가 크게 따로
  shellImpact(e) {
    const pos = { x: e.x, y: e.y, z: e.z };
    if (e.what === 'expire') {
      this.effects.burst(pos, null, 0x999999, 6, 1.2, 0.12, 0.6);
      return;
    }
    if (e.big) return;
    this.effects.burst(pos, null, 0xffb040, 12, 5, 0.1, 0.3);
    this.effects.burst(pos, null, 0x777777, 12, 3, 0.14, 0.6);
    this.effects.ring(pos, 0xffd080, 2, 0.25);
    if (this.onShellHit) this.onShellHit(pos, false);
  }

  // blockBreak: 부서진 칸마다 번쩍 + 돌 파편이 사방으로 + 옆 블록 들썩 (대형 포탄은 지나간 길 따라)
  blockBreak(e) {
    const cells = (e.cells || []).filter((c) => c.every(Number.isFinite));
    if (!cells.length) return;
    this.blockPulse(cells, 0xffffff, { opacity: 0.85 });
    this.blockPulse(this.blockNeighbors(cells), 0xffffff, { jolt: C.BLOCK_JOLT, opacity: 0.4 });
    for (const [x, y, z] of cells) {
      const c = { x: x + 0.5, y: y + 0.5, z: z + 0.5 };
      this.effects.burst(c, null, 0x8a8078, e.big ? 10 : 16, e.big ? 6 : 5, 0.16, 0.7); // 돌 조각
      this.effects.burst(c, { x: 0, y: 0 }, 0x6e665e, e.big ? 3 : 5, 3, 0.28, 1.1); // 큰 덩어리 (위로 튀었다 떨어짐)
      this.effects.burst(c, null, 0xb0a898, 6, 2, 0.12, 0.8); // 먼지
    }
  }

  // groundShot (F 발밑 포격): 발밑에 쾅 + 바닥 고리 (범위 r) + 흙먼지
  groundShot(e) {
    const pos = { x: e.x, y: e.y, z: e.z + 0.1 };
    this.effects.ring(pos, 0xffc080, (e.r || 1.8) * 2, 0.35, true);
    this.effects.burst(pos, null, 0xffb040, 16, 6, 0.12, 0.3);
    this.effects.burst(pos, null, 0x9a8a78, 20, 4, 0.15, 0.7);
    if (this.onBlast) this.onBlast(pos, false);
  }

  // bigShellBlast (R 끝 폭발): 크게 (범위 r 고리 둘 + 불·연기)
  bigShellBlast(e) {
    const pos = { x: e.x, y: e.y, z: e.z };
    const r = e.r || 2.2;
    this.effects.ring(pos, 0xffa040, r * 2.2, 0.4);
    this.effects.ring({ x: e.x, y: e.y, z: Math.max(0.05, e.z - 0.5) }, 0xffd080, r * 2, 0.45, true);
    this.effects.burst(pos, null, 0xff8020, 40, 9, 0.16, 0.5);
    this.effects.burst(pos, null, 0x666666, 30, 4, 0.22, 1.0);
    if (this.onBlast) this.onBlast(pos, true);
  }

  // ---------- 닌자 순간 베기 ----------
  // blink 이벤트: 몸이 from → to 로 미끄러져 가게 (render 루프가 위치를 덮어씀) + 지나간 길에 바람 줄
  blinkSlide(e) {
    const now = performance.now();
    const from = { x: e.from.x, y: e.from.y, z: Number.isFinite(e.from.z) ? e.from.z : e.to.z }; // 서버 from 에는 z 가 없음
    if (![from.x, from.y, e.to.x, e.to.y].every(Number.isFinite)) return;
    this.slides.set(e.who, { from, to: { ...e.to }, t0: now, ms: C.BLINK_SLIDE_MS, nextGhost: now });
    for (const dz of [0.35, 0.9, 1.4]) {
      this.trail({ x: e.from.x, y: e.from.y, z: e.to.z + dz }, { x: e.to.x, y: e.to.y, z: e.to.z + dz }, 0xffffff, 260 + dz * 60);
    }
  }

  // 잔상: 지금 몸을 통째로 복사해 반투명 한 색으로 남기고 서서히 지움 (이름표·화살표는 뺌)
  spawnGhost(g, color) {
    // clone 은 userData 를 JSON 으로 복사함 → 몸 그룹의 userData(관절·재질 참조)는 잠깐 비우고 복사
    const ud = g.userData;
    g.userData = {};
    let obj;
    try {
      obj = cloneBatched(g); // 합친 몸이 복제본 조각을 따라가게
    } finally {
      g.userData = ud;
    }
    const mat = noOutline(new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.4, depthWrite: false }));
    paintBatched(obj, mat);
    obj.traverse((o) => {
      if (o.isSprite) o.visible = false;
      else if (o.isMesh) o.castShadow = false;
    });
    for (const k of ['arrow', 'ring']) {
      const i = g.children.indexOf(ud[k]);
      if (i >= 0) obj.children[i].visible = false;
    }
    this.scene.add(obj);
    this.ghosts.push({ obj, mat, t0: performance.now() });
  }

  updateGhosts() {
    if (!this.ghosts.length) return;
    const now = performance.now();
    this.ghosts = this.ghosts.filter((gh) => {
      const u = (now - gh.t0) / C.BLINK_GHOST_FADE_MS;
      if (u >= 1) {
        this.scene.remove(gh.obj);
        gh.mat.dispose();
        return false;
      }
      gh.mat.opacity = 0.4 * (1 - u);
      return true;
    });
  }

  // 갈고리 공중 스핀: 갈고리 끝이 그리는 원 (몸 둘레 수평 원호가 도는 만큼 자라며 사라짐) + 끝에 갈고리 머리
  spinArc(who) {
    const s = this.smooth.get(who);
    if (!s) return;
    const geo = new THREE.BufferGeometry();
    const mat = noOutline(new THREE.MeshBasicMaterial({ color: 0xe8ecf4, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthWrite: false }));
    const arc = new THREE.Mesh(geo, mat);
    arc.renderOrder = 6;
    this.hookHeadParts();
    const head = new THREE.Mesh(this.hookHeadGeo, this.hookHeadMat);
    this.scene.add(arc, head);
    (this.spins ||= []).push({ who, arc, head, mat, t0: performance.now(), start: null });
  }

  updateSpinArcs() {
    if (!this.spins?.length) return;
    const now = performance.now();
    const hand = new THREE.Vector3();
    this.spins = this.spins.filter((sp) => {
      const u = (now - sp.t0) / C.SPIN_ARC_MS;
      const s = this.smooth.get(sp.who);
      if (u >= 1 || !s || !this.hookHand(sp.who, hand)) {
        this.scene.remove(sp.arc, sp.head);
        sp.arc.geometry.dispose();
        sp.mat.dispose();
        return false;
      }
      // 손이 가리키는 방향으로 팔 길이보다 멀리 = 갈고리 끝. 처음 각에서 지금 각까지 원호
      const R = C.PUSH_RANGE * 0.9;
      const z = s.z + 1.0;
      const ang = Math.atan2(hand.y - s.y, hand.x - s.x);
      if (sp.start === null) sp.start = ang;
      let sweep = ang - sp.start;
      if (sp.last !== undefined && sweep < sp.lastSweep - Math.PI) sweep += Math.PI * 2; // 한 바퀴 넘어가면 이어서
      if (sp.last !== undefined && sweep > sp.lastSweep + Math.PI) sweep -= Math.PI * 2;
      sp.last = ang;
      sp.lastSweep = sweep;
      const a0 = Math.min(sp.start, sp.start + sweep);
      const len = Math.max(0.05, Math.min(Math.PI * 2, Math.abs(sweep)));
      sp.arc.geometry.dispose();
      sp.arc.geometry = new THREE.RingGeometry(R - 0.06, R + 0.06, 40, 1, a0, len);
      sp.arc.position.set(s.x, s.y, z);
      sp.mat.opacity = 0.85 * (1 - u);
      sp.head.position.set(s.x + Math.cos(ang) * R, s.y + Math.sin(ang) * R, z);
      sp.head.rotation.set(0, 0, ang);
      return true;
    });
  }

  // ---------- 갈고리 ----------
  // 왼손(갈고리 손) 위치 (TABS 식 몸이면 손 관절, 아니면 가슴 높이)
  hookHand(id, out) {
    const g = this.playerMeshes.get(id);
    const fig = g && g.userData.figure;
    if (fig && g.visible) return fig.hands[1].getWorldPosition(out);
    const s = this.smooth.get(id);
    return s ? out.set(s.x, s.y, s.z + 1) : null;
  }

  // 밧줄 하나 (손 → 머리, 꼰 무늬 튜브) + 갈고리 머리. 모양은 매 프레임 setChain 이 다시 만듦
  // 갈고리 머리 모양·재질 (밧줄·스핀이 같이 씀)
  hookHeadParts() {
    if (!this.hookHeadGeo) {
      this.hookHeadGeo = new THREE.TorusGeometry(0.09, 0.025, 4, 8, Math.PI * 1.3);
      this.hookHeadMat = toon({ color: 0xa3adb8 });
    }
  }

  makeChain() {
    this.hookHeadParts();
    const map = this.tex.rope.clone(); // 밧줄마다 길이에 맞춰 무늬 반복
    map.needsUpdate = true;
    const mat = toon({ color: C.ROPE_COLOR, map });
    const mesh = new THREE.Mesh(new THREE.BufferGeometry(), mat);
    mesh.frustumCulled = false;
    mesh.castShadow = true;
    const head = new THREE.Mesh(this.hookHeadGeo, this.hookHeadMat);
    this.scene.add(mesh, head);
    return { mesh, head, mat, map };
  }

  dropChain(c) {
    this.scene.remove(c.mesh, c.head);
    c.mesh.geometry.dispose();
    c.mat.dispose();
    c.map.dispose();
  }

  // a → b 밧줄. sag: 가운데가 아래로 처지는 정도(칸), wave: 옆으로 출렁이는 폭(칸, 시간에 따라 흔들림)
  setChain(c, a, b, t, sag = 0, wave = 0) {
    const len = a.distanceTo(b);
    if (!Number.isFinite(len)) return; // 안전장치
    const dir = b.clone().sub(a).normalize();
    let side = new THREE.Vector3(-dir.y, dir.x, 0);
    if (side.lengthSq() < 1e-6) side = new THREE.Vector3(1, 0, 0);
    side.normalize();
    const pts = [];
    const N = 16;
    for (let i = 0; i <= N; i++) {
      const u = i / N;
      const bow = 4 * u * (1 - u); // 가운데가 가장 큼
      const p = a.clone().lerp(b, u);
      p.z -= sag * bow;
      p.addScaledVector(side, wave * Math.sin(Math.PI * u) * Math.sin(t / 45 + u * 6));
      pts.push(p);
    }
    c.mesh.geometry.dispose();
    c.mesh.geometry = new THREE.TubeGeometry(new THREE.CatmullRomCurve3(pts), 24, C.ROPE_RADIUS, 6, false);
    c.map.repeat.set(Math.max(1, len * C.ROPE_TWISTS), 1);
    c.head.position.copy(b);
    c.head.rotation.set(0, 0, t / 60);
  }

  // F 갈고리. hookThrow (던짐): 갈고리 머리가 HOOK_FLY_MS 동안 던진 방향으로 날아감 →
  // hook (닿는 순간 판정): 상대·블록이면 그쪽에 걸려 잠깐 팽팽 → 감김, 빗나가면 바로 감김. 던짐 없이 hook 만 오면 그 자리에서 날아가는 것부터
  hookThrowRope(e) {
    const s = this.smooth.get(e.who);
    if (!s) return;
    this.dropRope(e.who);
    const miss = new THREE.Vector3(s.x + Math.cos(e.yaw) * C.HOOK_RANGE, s.y + Math.sin(e.yaw) * C.HOOK_RANGE, s.z + C.HOOK_RAY_HEIGHT);
    (this.ropes ||= []).push({ who: e.who, target: null, block: null, miss, t0: performance.now(), flyMs: e.ms || C.HOOK_FLY_MS, landAt: 0, caught: false, chain: this.makeChain() });
  }

  hookRope(e) {
    const now = performance.now();
    let r = this.ropes?.find((x) => x.who === e.who && !x.landAt);
    if (!r) {
      this.hookThrowRope({ who: e.who, yaw: e.yaw, ms: C.HOOK_FLY_MS });
      r = this.ropes?.find((x) => x.who === e.who && !x.landAt);
      if (!r) return;
    }
    const target = e.target ?? null;
    r.block = e.block ? new THREE.Vector3(e.block[0] + 0.5, e.block[1] + 0.5, e.block[2] + 0.5) : null;
    r.target = target;
    r.caught = !!(r.block || target !== null);
    r.landAt = Math.max(now, r.t0 + 1); // 지금 닿음 (날아가던 끝이 그쪽으로 붙음)
    r.landFrom = r.tip ? r.tip.clone() : null;
    if (target !== null && this.smooth.has(target)) {
      // 끌려오는 쪽: 닿은 지금부터 질질 끌려옴 (서버 위치로, 잔상 없음)
      const ts = this.smooth.get(target);
      this.slides.set(target, { from: { x: ts.x, y: ts.y, z: ts.z }, to: null, t0: now, ms: C.HOOK_PULL_SLIDE_MS, nextGhost: Infinity });
    }
  }

  // 던진 갈고리가 닿기 전에 끊김 (interrupt skill): 그 자리에서 감김
  hookCancel(who) {
    const r = this.ropes?.find((x) => x.who === who && !x.landAt);
    if (r) {
      r.landAt = performance.now();
      r.caught = false;
      r.landFrom = r.tip ? r.tip.clone() : null;
    }
  }

  dropRope(who) {
    if (!this.ropes) return;
    this.ropes = this.ropes.filter((r) => {
      if (r.who !== who) return true;
      this.dropChain(r.chain);
      return false;
    });
  }

  updateRopes() {
    if (!this.ropes?.length) return;
    const now = performance.now();
    const a = new THREE.Vector3();
    this.ropes = this.ropes.filter((r) => {
      const age = now - r.t0;
      // 서버 hook 이 늦으면 다 날아간 채로 잠깐 기다림, 너무 오래면 버림
      if (!this.hookHand(r.who, a) || (!r.landAt && age > r.flyMs + 1000)) {
        this.dropChain(r.chain);
        return false;
      }
      const ts = r.target !== null ? this.smooth.get(r.target) : null;
      const len0 = a.distanceTo(r.miss);
      let end;
      let sag;
      let wave;
      if (!r.landAt) {
        // 날아감: 던진 방향으로 늘어지고 살짝 휜 채로 뻗어 나감
        const u = Math.min(1, age / r.flyMs);
        end = a.clone().lerp(r.miss, Math.max(0.02, u));
        sag = len0 * u * C.ROPE_SAG;
        wave = C.ROPE_WOBBLE * 0.6 * (1 - u);
      } else {
        const since = now - r.landAt;
        const hold = r.caught ? C.HOOK_HOLD_MS : 0;
        const goal = ts ? new THREE.Vector3(ts.x, ts.y, ts.z + 1) : r.block || r.landFrom || r.miss;
        if (since > hold + C.HOOK_FLY_MS) {
          this.dropChain(r.chain);
          return false;
        }
        const len = a.distanceTo(goal);
        if (since < hold) {
          // 걸림: 팽팽하게 (걸린 순간 짧게 퉁 떨림)
          end = goal;
          sag = 0;
          wave = C.ROPE_WOBBLE * 0.4 * Math.exp(-since / 60);
        } else {
          // 감김: 느슨해지며 손으로 돌아옴
          const v = (since - hold) / C.HOOK_FLY_MS;
          end = a.clone().lerp(goal, Math.max(0.02, 1 - v));
          sag = len * C.ROPE_SAG * 0.8 * (1 - v);
          wave = C.ROPE_WOBBLE * (1 - v * 0.5);
        }
      }
      r.tip = end.clone();
      this.setChain(r.chain, a, end, now, sag, wave);
      return true;
    });
  }

  // 지상 F 준비 (skillWindup, 닌자·탱크·갈고리): ms 동안 온몸(옷 포함)이 하얗게 번쩍 + 발밑 흰 고리
  skillWindup(e) {
    this.windupUntil.set(e.who, performance.now() + (e.ms || C.SKILL_WINDUP_MS));
    const s = this.smooth.get(e.who);
    if (s) this.effects.ring({ x: s.x, y: s.y, z: s.z + 0.05 }, 0xffffff, 1.8, (e.ms || C.SKILL_WINDUP_MS) / 1000, true);
  }

  // R 1단계 (blockGrab): 덩어리(테트로미노 통째로, 지형은 1칸)가 ms 동안 제자리에서 덜덜 (큰 걸 든다는 예고) →
  // 뽑혀 사슬에 끌려와 머리 위에서 모양 그대로 빙빙 (덩어리가 클수록 크게 돎). 건축가 블록이면 금 간 무늬, 하늘 블록은 밝고 살짝 비침
  blockGrab(e) {
    const now = performance.now();
    const cells = e.cells && e.cells.length ? e.cells : [e.from];
    const kind = e.v === CELL.TERRAIN ? 'stone' : e.v === CELL.BUILD ? 'wood' : e.v === CELL.THROWN ? 'sand' : 'piece';
    const col = new THREE.Color(e.builder ? 0xffb070 : cellColor(e.v));
    if (e.sky) col.lerp(new THREE.Color(0xffffff), C.SKY_PIECE_WHITEN);
    const mat = toon({ color: col.getHex(), map: e.builder ? this.tex.cracked : this.tex[kind], transparent: !!e.sky, opacity: e.sky ? C.SKY_PIECE_OPACITY : 1 });
    // 덩어리 가운데가 원점, 칸은 원래 모양·방향 그대로
    const center = new THREE.Vector3();
    for (const [x, y, z] of cells) center.add(new THREE.Vector3(x + 0.5, y + 0.5, z + 0.5));
    center.divideScalar(cells.length);
    const mesh = new THREE.Group();
    let size = 0;
    for (const [x, y, z] of cells) {
      const cube = new THREE.Mesh(kind === 'piece' && !e.builder ? this.pieceBox : this.bbGeo, mat);
      cube.position.set(x + 0.5 - center.x, y + 0.5 - center.y, z + 0.5 - center.z);
      cube.castShadow = true;
      mesh.add(cube);
      size = Math.max(size, cube.position.length());
    }
    mesh.position.copy(center);
    this.scene.add(mesh);
    (this.grabs ||= new Map()).get(e.who)?.mesh && this.endGrab(e.who);
    this.grabs.set(e.who, { mesh, mat, from: center.clone(), t0: now, ms: e.ms || 300, size, slam: null, chain: this.makeChain() });
    // 잡히는 순간: 덩어리 칸이 번쩍 + 옆 블록 들썩 (뽑혀 나갈 때 돌 조각은 updateGrabs)
    const cs = cells.map((c) => c.map(Math.floor));
    this.blockPulse(cs, 0xffffff, { opacity: 0.6, ms: e.ms || 300 });
    this.blockPulse(this.blockNeighbors(cs), 0xffffff, { jolt: C.BLOCK_JOLT, opacity: 0.35 });
  }

  // R 2단계 (blockSlam): 머리 위에서 앞으로 크게 내려찍음 → 덩어리 모양 그대로 박힘 (빈 cells = 필드 밖으로 떨어져 사라짐)
  blockSlam(e) {
    const g = this.grabs?.get(e.who);
    const s = this.smooth.get(e.who);
    if (!g || !s) return;
    const cells = e.cells && e.cells.length ? e.cells : e.cell ? [e.cell] : [];
    let to;
    if (cells.length) {
      to = new THREE.Vector3();
      for (const [x, y, z] of cells) to.add(new THREE.Vector3(x + 0.5, y + 0.5, z + 0.5));
      to.divideScalar(cells.length);
    } else to = new THREE.Vector3(s.x + e.dir.x * (e.len + 1.5), s.y + e.dir.y * (e.len + 1.5), s.z - 3);
    // 박힌 모양이 뽑은 모양과 다르면 (필드 밖 칸을 버림) 큐브를 박힌 칸에 맞춤
    if (cells.length && cells.length !== g.mesh.children.length) {
      while (g.mesh.children.length > cells.length) g.mesh.remove(g.mesh.children[g.mesh.children.length - 1]);
      cells.forEach(([x, y, z], k) => g.mesh.children[k].position.set(x + 0.5 - to.x, y + 0.5 - to.y, z + 0.5 - to.z));
    }
    g.slam = { t0: performance.now(), from: g.mesh.position.clone(), rot: g.mesh.rotation.z % (Math.PI * 2), to, cells, dir: e.dir, line: { x: s.x, y: s.y, z: s.z } };
  }

  endGrab(who) {
    const g = this.grabs.get(who);
    if (!g) return;
    this.scene.remove(g.mesh);
    g.mat.dispose();
    this.dropChain(g.chain);
    this.grabs.delete(who);
  }

  updateGrabs() {
    if (!this.grabs?.size) return;
    const now = performance.now();
    const hand = new THREE.Vector3();
    for (const [who, g] of this.grabs) {
      const s = this.smooth.get(who);
      if (!s || !this.hookHand(who, hand) || now - g.t0 > 3000) {
        this.endGrab(who);
        continue;
      }
      // 내 1인칭: 덩어리가 화면을 덮지 않게 더 높이 + 반투명
      const mine = this.vm.on && this.playerMeshes.get(who) === this.vm.src;
      g.mat.transparent = mine || g.mat.opacity < 1;
      if (mine) g.mat.opacity = C.HOOK_GRAB_FP_OPACITY;
      const over = new THREE.Vector3(s.x, s.y, s.z + C.PLAYER_HEIGHT + 0.9 + g.size * 0.5 + (mine ? C.HOOK_GRAB_FP_RAISE : 0));
      const swingR = C.HOOK_GRAB_SWING_R + g.size; // 큰 덩어리는 크게 돎 (몸에 안 박히게)
      if (!g.slam) {
        const t = now - g.t0;
        const shakeMs = g.ms * C.HOOK_GRAB_SHAKE_PART; // 서버는 ms 뒤에 내려찍음 → 앞쪽은 덜덜, 뒤쪽은 머리 위로 끌려옴
        if (t < shakeMs) {
          // 예고: 제자리에서 덜덜 (점점 세게)
          const k = (t / shakeMs) * C.HOOK_GRAB_SHAKE;
          g.mesh.position.set(g.from.x + (Math.random() - 0.5) * k, g.from.y + (Math.random() - 0.5) * k, g.from.z + Math.random() * k * 0.5);
        } else {
          if (!g.pulled) {
            // 뽑힘: 빈 자리에서 돌 조각·흙
            g.pulled = true;
            this.effects.burst(g.from, null, 0x8a7a68, 14 + 4 * g.mesh.children.length, 4, 0.12, 0.55);
            this.effects.burst(g.from, { x: 0, y: 0 }, 0x6a5e52, 8, 5, 0.18, 0.6);
          }
          // 끌려옴 → 머리 위에서 빙빙 (모양이 보이게 눕힌 채 z 축으로만 돎)
          const u = Math.min(1, (t - shakeMs) / Math.max(1, g.ms - shakeMs));
          const ang = now / 90;
          const circle = over.clone().add(new THREE.Vector3(Math.cos(ang) * swingR, Math.sin(ang) * swingR, 0));
          g.mesh.position.copy(g.from.clone().lerp(circle, u * u * (3 - 2 * u)));
          g.mesh.rotation.set(0, 0, ang * 0.5 * u);
        }
      } else {
        // 내려찍음: 위로 솟았다 앞으로 떨어지는 호. 도는 각은 박힐 때 0 (격자 모양과 같게)
        const u = Math.min(1, (now - g.slam.t0) / C.HOOK_SLAM_FLY_MS);
        const p = g.slam.from.clone().lerp(g.slam.to, u);
        p.z += Math.sin(Math.PI * u) * 1.2;
        g.mesh.position.copy(p);
        g.mesh.rotation.set(0, 0, g.slam.rot * (1 - u));
        if (u >= 1 && !g.slam.done) {
          g.slam.done = true;
          if (g.slam.cells.length) {
            // 박힘: 칸마다 흙먼지 + 쾅 + 내려찍은 줄을 따라 먼지
            const cs = g.slam.cells.map((c) => c.map(Math.floor));
            for (const [x, y, z] of cs) this.effects.burst({ x: x + 0.5, y: y + 0.5, z: z + 0.5 }, null, 0x8a7a68, Math.ceil(26 / cs.length) + 4, 6, 0.13, 0.7);
            this.effects.ring({ x: g.slam.to.x, y: g.slam.to.y, z: g.slam.to.z - 0.45 }, 0xc0a880, 3.5 + g.size, 0.35, true);
            for (let k = 1; k <= C.HOOK_SLAM_LEN; k++) this.effects.burst({ x: g.slam.line.x + g.slam.dir.x * k, y: g.slam.line.y + g.slam.dir.y * k, z: g.slam.line.z + 0.1 }, null, 0x9a8a78, 4, 2.5, 0.1, 0.5);
            this.blockPulse(cs, 0xffffff, { jolt: -C.BLOCK_JOLT, opacity: 0.85 });
            this.blockPulse(this.blockNeighbors(cs), 0xffffff, { jolt: C.BLOCK_JOLT * 1.5, opacity: 0.4 });
            if (this.onBlast) this.onBlast(g.slam.to, true);
            this.endGrab(who); // 이제 격자에 박힌 블록이 그 자리
            continue;
          }
          g.slam.fallAt = now;
        }
        if (g.slam.fallAt) {
          // 필드 밖: 계속 떨어지며 사라짐
          g.mesh.position.z -= (now - g.slam.fallAt) / 60;
          if (now - g.slam.fallAt > 500) {
            this.endGrab(who);
            continue;
          }
        }
      }
      // R 밧줄: 덜덜·끌어오는 동안 팽팽, 머리 위에서 돌릴 땐 원심력으로 살짝 출렁, 내려찍을 땐 팽팽
      this.setChain(g.chain, hand, g.mesh.position.clone(), now, 0, g.slam || now - g.t0 < g.ms * C.HOOK_GRAB_SHAKE_PART ? 0 : C.ROPE_WOBBLE * 0.4);
    }
  }

  updateBeams(state) {
    const pairs = [];
    for (const pc of state.pieces || []) {
      if (pc.phase !== 'control' || pc.controller === null) continue;
      const s = this.smooth.get(pc.controller);
      const owner = state.players.find((p) => p.id === pc.controller);
      if (!s || !owner || !owner.alive || !pc.cells.length) continue;
      const c = pc.cells.reduce((a, [x, y, z]) => [a[0] + x, a[1] + y, a[2] + z], [0, 0, 0]).map((v) => v / pc.cells.length + 0.5);
      pairs.push([new THREE.Vector3(s.x, s.y, s.z + C.PLAYER_HEIGHT), new THREE.Vector3(...c)]);
    }
    while (this.beams.length < pairs.length) {
      const m = new THREE.Mesh(new THREE.CylinderGeometry(C.BEAM_RADIUS, C.BEAM_RADIUS, 1, 8, 1, true), this.beamMat);
      this.scene.add(m);
      this.beams.push(m);
    }
    const up = new THREE.Vector3(0, 1, 0);
    this.beams.forEach((m, i) => {
      const pr = pairs[i];
      m.visible = !!pr;
      if (!pr) return;
      const [a, b] = pr;
      const dir = b.clone().sub(a);
      m.position.copy(a).addScaledVector(dir, 0.5);
      m.scale.set(1, dir.length(), 1);
      m.quaternion.setFromUnitVectors(up, dir.normalize());
    });
    this.beamMat.opacity = C.BEAM_OPACITY + C.BEAM_PULSE * Math.sin(performance.now() / 150); // 살짝 깜빡임
  }

  // ---------- 건축가 블록 ----------
  // 격자엔 CELL.BUILD 로 있지만 여기서 따로 그림: 주인 색 + 금 간 무늬, 생길 때 솟음, 사라지기 전 깜빡임,
  // 같은 묶음(같은 F 의 벽 등) 이웃 칸은 위를 쇠 띠로 이음 (연쇄가 어디까지 번지는지 보이게), 대폭발 블록은 빨갛게 부풀며 째깍
  updateBBlocks(state) {
    const list = state.bblocks || [];
    const quakeCells = this.quakes.filter((q) => !q.sinkAt).flatMap((q) => q.cells);
    const sig = list.map((b) => `${b.x},${b.y},${b.z},${b.kind}`).join('|') + '#' + quakeCells.join('|');
    if (sig !== this.bbSig) {
      this.bbSig = sig;
      // 건축가 블록·탱크 솟는 땅은 격자에선 빼고 따로 그림
      this.bbSkip = new Set([...list.map((b) => [b.x, b.y, b.z]), ...quakeCells].map(([x, y, z]) => (z * this.D + y) * this.W + x));
      if (state.grid && state.grid.length === this.W * this.D * this.H) this.updateGrid(state.grid);
    }
    const now = performance.now();
    const owners = new Map(state.players.map((p) => [p.id, p]));
    const tint = (id) => {
      const o = owners.get(id);
      return new THREE.Color(o ? playerColor(o, state) : 0xc08040).lerp(new THREE.Color(0xffffff), C.BB_TINT);
    };
    // 연쇄 대기 칸: 차례가 오면 터짐
    const ghosts = [];
    for (const gh of this.bbGhosts) {
      if (now >= gh.at) this.bbPop(gh);
      else ghosts.push(gh);
    }
    this.bbGhosts = ghosts;
    const draw = [...list.map((b) => ({ ...b, color: tint(b.owner) })), ...ghosts.map((g) => ({ ...g, kind: 'ghost', left: Infinity }))];
    while (this.bbMeshes.length < draw.length) {
      const m = new THREE.Mesh(this.bbGeo, toon({ color: 0xffffff, map: this.tex.cracked, transparent: true }));
      m.castShadow = m.receiveShadow = true;
      this.scene.add(m);
      this.bbMeshes.push(m);
    }
    this.bbMeshes.forEach((m, i) => {
      const b = draw[i];
      m.visible = !!b;
      if (!b) return;
      const mat = m.material;
      let sx = 1;
      let sz = 1;
      let emissive = 0x000000;
      let opacity = 1;
      // 솟기: 바닥에서 위로 자라며 살짝 넘쳤다 돌아옴
      const born = this.bbBorn.get(`${b.x},${b.y},${b.z}`);
      if (born !== undefined) {
        const u = (now - born) / C.BB_POP_MS;
        if (u >= 1) this.bbBorn.delete(`${b.x},${b.y},${b.z}`);
        else sz = Math.max(0.05, 1 + 0.25 * Math.sin(Math.PI * u) - (1 - u) ** 3);
      }
      if (b.kind === 'big') {
        // 대폭발: 터질 때가 가까울수록 크게 부풀고 빨리 깜빡
        const k = 1 - Math.min(1, b.left / C.BUILDER_BIG_FUSE_MS);
        sx = 1 + C.BB_BIG_SWELL * k + 0.04 * Math.sin(now / 35);
        sz *= sx;
        mat.color.setHex(0xff4030);
        emissive = Math.floor(now / (50 + b.left / 5)) % 2 ? 0xa01000 : 0x300000;
      } else if (b.kind === 'ghost') {
        mat.color.copy(b.color);
        emissive = 0xffffff; // 곧 터짐: 하얗게
      } else {
        mat.color.copy(b.color);
        if (b.left < C.BB_BLINK_MS && Math.floor(now / (b.left < C.BB_BLINK_MS / 3 ? 70 : 140)) % 2) opacity = 0.35; // 사라지기 직전 깜빡임
      }
      mat.emissive.setHex(emissive);
      mat.opacity = opacity;
      m.scale.set(sx, sx, sz);
      m.position.set(b.x + 0.5, b.y + 0.5, b.z + sz / 2);
    });
    // 같은 묶음 이웃 칸: 윗면 이음매에 쇠 띠
    const at = new Map(list.map((b) => [`${b.x},${b.y},${b.z}`, b]));
    const pairs = [];
    for (const b of list) {
      for (const [dx, dy] of [[1, 0], [0, 1]]) {
        const n = at.get(`${b.x + dx},${b.y + dy},${b.z}`);
        if (n && n.group === b.group) pairs.push([b, dx, dy]);
      }
    }
    while (this.bbStraps.length < pairs.length) {
      const s = new THREE.Mesh(this.bbGeo, this.bbStrapMat);
      this.scene.add(s);
      this.bbStraps.push(s);
    }
    this.bbStraps.forEach((s, i) => {
      const pr = pairs[i];
      s.visible = !!pr;
      if (!pr) return;
      const [b, dx, dy] = pr;
      s.scale.set(dx ? 0.55 : 0.16, dy ? 0.55 : 0.16, 0.06);
      s.position.set(b.x + 0.5 + dx * 0.5, b.y + 0.5 + dy * 0.5, b.z + 1.01);
    });
  }

  // bblock 이벤트: 솟는 연출 시작
  bblockBorn(cells) {
    const now = performance.now();
    for (const [x, y, z] of cells) this.bbBorn.set(`${x},${y},${z}`, now);
  }

  // blast 이벤트: 서버는 한 번에 지웠지만 화면에선 cells 순서대로 차례로 터짐 (치는 방향 dir 로 파편)
  blastChain(e, color) {
    const now = performance.now();
    const c = new THREE.Color(color).lerp(new THREE.Color(0xffffff), C.BB_TINT);
    e.cells.forEach(([x, y, z], i) => this.bbGhosts.push({ x, y, z, color: c, at: now + i * C.BB_CHAIN_STEP_MS, dir: e.dir, hex: color }));
  }

  // 한 칸 터짐: 치는 방향으로 파편 + 회색 먼지 + 작은 고리
  bbPop(gh, big = false) {
    const pos = { x: gh.x + 0.5, y: gh.y + 0.5, z: gh.z + 0.5 };
    const dir = gh.dir ? { x: gh.dir.x * 1.2, y: gh.dir.y * 1.2 } : null;
    this.effects.burst(pos, dir, gh.hex ?? 0xc08040, big ? 30 : 16, big ? 9 : 7, 0.14, 0.55);
    this.effects.burst(pos, null, 0x777777, big ? 18 : 8, 4, 0.12, 0.7);
    this.effects.burst(pos, dir, 0xffc040, 8, 8, 0.1, 0.3);
    this.effects.ring(pos, 0xffd080, big ? 5 : 2.6, 0.3);
    // 터진 칸이 번쩍 + 붙어 있던 블록이 들썩
    this.blockPulse([[gh.x, gh.y, gh.z]], 0xffe0a0, { ms: C.BLOCK_PULSE_MS * 0.8, opacity: 0.9 });
    this.blockPulse(this.blockNeighbors([[gh.x, gh.y, gh.z]]), 0xffd080, { jolt: big ? C.BLOCK_JOLT * 1.5 : C.BLOCK_JOLT, opacity: 0.45 });
    if (this.onBlast) this.onBlast(pos, big);
  }

  updateBombs(bombs) {
    while (this.bombMeshes.length < bombs.length) {
      // 재질을 복사해 폭탄마다 따로 깜빡이게
      const m = itemModel(this.models, 'bomb', C.BOMB_MODEL_SIZE, true) || new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), toon({ color: 0x222222 }));
      m.userData.mats = [];
      m.traverse((o) => {
        if (o.isMesh) {
          o.castShadow = true;
          m.userData.mats.push(o.material);
        }
      });
      this.scene.add(m);
      this.bombMeshes.push(m);
    }
    this.bombMeshes.forEach((m, i) => {
      const b = bombs[i];
      m.visible = !!b;
      if (!b) return;
      m.position.set(b.x + 0.5, b.y + 0.5, b.z + C.BOMB_MODEL_SIZE / 2);
      const period = 80 + Math.min(1, b.left / C.BOMB_FUSE_MS) * 320; // 남은 시간이 짧을수록 빨리
      const on = Math.floor(performance.now() / period) % 2 === 0;
      for (const mat of m.userData.mats) if (mat.emissive) mat.emissive.setHex(on ? 0xff2000 : 0x000000);
    });
  }

  // state: 최신 서버 스냅샷, myId: 내 플레이어 id, dt: 프레임 시간(초), view: 'fps' | 'sky'
  // 관전 카메라 가림 검사: 격자 칸이 차 있거나, 필드 안쪽 바닥(z<0) 아래
  solidAt(state, x, y, z) {
    const gx = Math.floor(x);
    const gy = Math.floor(y);
    const gz = Math.floor(z);
    if (gx < 0 || gy < 0 || gx >= this.W || gy >= this.D) return false;
    if (gz < 0) return true;
    if (gz >= this.H || !state.grid) return false;
    return !!state.grid[(gz * this.D + gy) * this.W + gx]; // 판 크기가 막 바뀌어 배열이 짧아도 빈칸
  }

  // 발이 땅에 닿았나: 바닥(z 0) 또는 발 네 모서리 바로 아래 칸이 단단함
  feetOnGround(state, s) {
    if (s.z <= 0.03 && s.z > -0.3) return true;
    const h = C.PLAYER_HALF;
    for (const [dx, dy] of [[-h, -h], [h, -h], [-h, h], [h, h]]) if (this.solidAt(state, s.x + dx, s.y + dy, s.z - 0.08)) return true;
    return false;
  }

  render(state, myId, dt, view, cam) {
    if (!state) {
      // 메뉴(방 밖): 화면만의 가짜 대기 장면 (menu-scene.js). 방에 들어가면 버림
      this.menu ||= new MenuScene(Math.random, this.lowGfx);
      const f = this.menu.step(dt || 0, !this.title); // 타이틀 동안은 카메라가 안 돎 (내려온 자리 = 메뉴 카메라)
      // 섬이 가운데 메뉴 판에 가리지 않게 화면 왼쪽으로 비킴 (카메라 화면만 옆으로 밀기)
      let shift = C.MENU_VIEW_SHIFT;
      if (this.title) {
        // 타이틀 (title-scene.js): 하늘의 로고를 보다가 누르면 메뉴 카메라 자리로 내려옴
        const look = new THREE.Vector3(this.W / 2, this.D / 2, this.overviewZ ?? 2);
        const e = orbitEye(look, f.cam.yaw, f.cam.pitch, f.cam.overviewDist);
        const ts = this.title.step(dt || 0, { eye: new THREE.Vector3(e.x, e.y, Math.max(0.5, e.z)), look });
        f.cam.pose = ts.pose;
        shift = ts.shift;
      }
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.camera.setViewOffset(w, h, w * shift, 0, w, h);
      return this.render(f.state, null, dt, 'fps', f.cam);
    }
    if (this.menu && !state.menu) {
      this.menu = null; // 진짜 판·대기실이 옴 → 가짜 몸은 아래 players 정리에서 지워짐
      this.endTitle();
      this.camera.clearViewOffset();
    }
    this.curState = state;
    if (state.field) this.setField(state.field.w, state.field.d, false, state.field.h || C.GRID_H);
    const tg = prof.begin(); // 성능 표시: 블록·지형 갱신
    this.world.update(state, dt);
    this.stepView(view, dt);
    if (state.grid && state.grid.length === this.W * this.D * this.H && state.gridVersion !== this.gridVersion) {
      this.updateGrid(state.grid);
      this.gridVersion = state.gridVersion;
    }
    prof.end('grid', tg);

    // 플레이어
    this.victoryId = cam.victory || null;
    // 판 끝 (결과 연출 동안 계속): 이긴 사람(팀전이면 이긴 팀)은 승리 포즈를 유지 (카메라 연출은 WIN_BANNER_MS 뿐)
    const rd = state && state.phase === 'over' && !state.practice ? state.round : null;
    this.winners = rd ? new Set([...(rd.winnerIds || []), ...(rd.winnerTeam ? state.players.filter((q) => q.team === rd.winnerTeam).map((q) => q.id) : [])]) : null;
    const seen = new Set();
    // 위치: 스냅샷을 서버 시각으로 쌓아 두고 조금 늦은 시각의 위치를 두 스냅샷 사이에서 보간 (client/interp.js)
    if (Number.isFinite(state.time) && state.time !== this.snapTime) {
      this.snapTime = state.time;
      this.snapClock.onSnapshot(state.time, state.recvAt ?? performance.now());
      for (const p of state.players) {
        if (!this.tracks.has(p.id)) this.tracks.set(p.id, []);
        pushTrack(this.tracks.get(p.id), state.time, p.x, p.y, p.z);
      }
    }
    const clockT = this.snapClock.advance(performance.now(), dt * 1000);
    const ragKeep = new Set(); // 이번 프레임에 래그돌로 그리는 사람
    const tb = prof.begin(); // 성능 표시: 몸 애니 (보간·figureAnim·이름표 — 래그돌 물리는 따로)
    for (const p of state.players) {
      seen.add(p.id);
      const g = this.getPlayerMesh(p);
      let s = this.smooth.get(p.id);
      if (!s) {
        s = { x: p.x, y: p.y, z: p.z };
        this.smooth.set(p.id, s);
      }
      const slide = this.slides.get(p.id);
      if (slide) {
        // 닌자 순간 베기: 서버는 이미 to 에 있지만 화면에선 from → to 로 아주 빠르게 미끄러져 감 (끝에서 느려짐)
        // (갈고리에 끌려오는 쪽도: 갈고리가 닿을 때까지 제자리, 그 뒤 질질. to 가 없으면 서버 위치까지)
        const u = (performance.now() - slide.t0) / slide.ms;
        const to = slide.to || p;
        if (u >= 1 || !p.alive) this.slides.delete(p.id);
        else {
          const e = u <= 0 ? 0 : 1 - (1 - u) * (1 - u);
          Object.assign(s, { x: slide.from.x + (to.x - slide.from.x) * e, y: slide.from.y + (to.y - slide.from.y) * e, z: slide.from.z + (p.z - slide.from.z) * e });
        }
      } else {
        const track = this.tracks.get(p.id);
        const at = clockT === null ? null : clockT - (p.id === myId ? C.INTERP_DELAY_SELF_MS : C.INTERP_DELAY_MS);
        if (at === null || !track || !sampleTrack(track, at, C.INTERP_EXTRAP_MS, s)) Object.assign(s, { x: p.x, y: p.y, z: p.z });
      }
      if (![s.x, s.y, s.z].every(Number.isFinite)) Object.assign(s, { x: p.x, y: p.y, z: p.z }); // 안전장치
      g.position.set(s.x, s.y, s.z);
      g.rotation.z = p.yaw;
      const firstPerson = view === 'fps' && this.skyBlend === 0 && !cam.victory && !cam.selfie && (!this.third || (this.tpDist ?? C.TP_DIST) < C.TP_HIDE_DIST); // 3인칭은 카메라가 머리 속으로 당겨졌을 때만 숨김
      // 래그돌 (RAGDOLL_CHARS): 1인칭 내 몸은 끔 (viewmodel 이 관절을 베낌). 지난 프레임 물리 회전을 지우고 figureAnim 이 자세를 정하게
      const rag = !!RagdollWorld && !!g.userData.figure && C.RAGDOLL_CHARS.includes(p.char) && p.alive && !p.master && !(p.id === myId && (firstPerson || !this.third));
      if (rag) {
        ragKeep.add(p.id);
        this.ragdoll ||= new RagdollWorld();
        if (this.ragdoll.has(p.id) && this.ragdoll.figOf(p.id) !== g.userData.figure) this.ragdoll.remove(p.id); // 캐릭터가 바뀌어 몸이 새로 생김
        if (!this.ragdoll.has(p.id)) this.ragdoll.create(p.id, g.userData.figure, p.char);
        this.ragdoll.restore(p.id);
      } else if (this.ragdoll?.has(p.id)) this.ragdoll.remove(p.id);
      this.animate(g, s, p, dt);
      if (slide && performance.now() >= slide.nextGhost && this.slides.has(p.id)) {
        slide.nextGhost += C.BLINK_GHOST_MS;
        this.spawnGhost(g, g.userData.color);
      }
      // 이속 증가 중 달리면 발밑에 노란 잔상
      if (p.speedLeft > 0 && g.userData.anim.hs > 1 && Math.random() < dt * C.SPEED_TRAIL_RATE) {
        this.effects.burst({ x: s.x, y: s.y, z: s.z + 0.15 }, null, 0xffe020, 3, 1.2, 0.07, 0.35);
      }
      g.visible = p.alive && !p.master && !(p.id === myId && firstPerson); // 블록 마스터의 마스터는 필드에 없음
      const bodyMat = g.userData.bodyMat;
      // 경직 중엔 흰색으로 빠르게 깜빡임
      g.userData.color = playerColor(p, state); // 팀전이면 팀 색 (판 사이에 팀이 바뀔 수 있어 매 프레임)
      const blinkOn = p.stunned && Math.floor(performance.now() / 70) % 2 === 0;
      bodyMat.color.setHex(blinkOn ? 0xffffff : g.userData.color);
      bodyMat.emissive.setHex(p.stunned ? 0x664400 : p.hasControl ? 0x005566 : 0x000000);
      const skyMarks = this.skyBlend > 0.5;
      g.userData.arrow.visible = skyMarks;
      g.userData.arrow.material.color.setHex(p.id === myId ? 0xffffff : g.userData.color);
      g.userData.ring.visible = skyMarks && p.id === myId;
      // 맞으면 찌그러졌다 펴짐
      // 유령화: 반투명, 점프력 상승: 초록 빛, 망치: 오른팔에 망치 머리
      // 킬 점수전 부활 무적도 반투명 (빠르게 깜빡)
      const opacity = p.ghostLeft > 0 ? 0.35 + 0.1 * Math.sin(performance.now() / 120) : p.shieldLeft > 0 || p.iframeLeft > 0 ? 0.45 + 0.25 * Math.sin(performance.now() / 60) : 1; // 부활·콤보 뒤 무적은 빠르게 깜빡
      for (const m of g.userData.mats) {
        m.transparent = opacity < 1;
        m.opacity = opacity;
      }
      if (p.jumpLeft > 0 && !p.stunned) bodyMat.emissive.setHex(0x1a5a1a);
      if (p.char === 'berserker' && p.alive) {
        // 광전사 분노: 피해 % 따라 몸이 빨갛게 빛나고 (높으면 맥박처럼 출렁) 머리·어깨에서 김
        const k = Math.max(0, Math.min(1, (p.damage || 0) / C.BERSERK_RAGE_PCT));
        // 몸 색(플레이어 색)은 건드리지 않음: 누가 누군지가 우선. 분노는 붙는 효과로 (눈 충혈·눈썹·핏줄·빡침 표시는 figureAnim, 김은 여기)
        const fig = g.userData.figure;
        if (fig?.rage) fig.rage.k = k;
        if (k > 0.2 && Math.random() < dt * C.BERSERK_STEAM_RATE * k) {
          const side = Math.random() < 0.5 ? -1 : 1;
          const ox = Math.random() < 0.4 ? 0 : side * 0.25;
          this.effects.burst({ x: s.x + Math.sin(p.yaw) * ox, y: s.y - Math.cos(p.yaw) * ox, z: s.z + (ox ? 1.25 : 1.6) }, { x: 0, y: 0, z: 1 }, 0xf4f4f4, 1, 0.9, 0.12, 0.8);
        }
      }
      if (p.empower > 0) {
        // 닌자 R 강화: 몸이 보라로 깜빡 + 손에서 보라 불티 (끝 1.5초는 빠르게)
        if (Math.floor(performance.now() / (p.empower < 1500 ? 70 : 160)) % 2) bodyMat.emissive.setHex(C.EMPOWER_GLOW);
        if (Math.random() < dt * 25) this.effects.burst({ x: s.x, y: s.y, z: s.z + 0.9 + Math.random() * 0.6 }, { x: 0, y: 0, z: 1 }, C.EMPOWER_GLOW, 1, 1.2, 0.06, 0.4);
      }
      // 스킬·필살기 빛 (aura): 몸 전체(옷 포함)가 잠깐 빛남. 필살기는 반짝이가 위로
      const now = performance.now();
      const glowing = now < (g.userData.glowUntil || 0);
      for (const m of g.userData.mats) if (m.emissive && m !== bodyMat) m.emissive.setHex(glowing ? g.userData.glowColor : 0x000000);
      if (glowing) bodyMat.emissive.setHex(g.userData.glowColor);
      const wu = (this.windupUntil.get(p.id) || 0) - now;
      if (wu > 0) {
        // 지상 F 준비: 온몸 하얗게 (끝으로 갈수록 더 밝게 → 나가는 순간을 읽게)
        const k = 1 - wu / C.SKILL_WINDUP_MS;
        const v = 0.55 + 0.45 * Math.max(0, Math.min(1, k));
        for (const m of g.userData.mats) if (m.emissive) m.emissive.setRGB(v, v, v);
      }
      if (now < (this.armorUntil.get(p.id) || 0)) {
        // 탱크 아머: 온몸(옷 포함)이 금속처럼 번쩍 (빛이 훑고 지나가듯 밝기가 출렁), 버틴 순간엔 하얗게
        const hitFlash = now - (this.armorHitAt.get(p.id) || -1e9) < 90;
        const c = new THREE.Color(C.ARMOR_SHINE).multiplyScalar(0.5 + 0.5 * Math.abs(Math.sin(now / 70)));
        for (const m of g.userData.mats) if (m.emissive) m.emissive.copy(hitFlash ? new THREE.Color(0xffffff) : c);
      }
      if (now < (g.userData.sparkUntil || 0) && Math.random() < dt * 40) {
        const a = Math.random() * Math.PI * 2;
        this.effects.burst({ x: s.x + Math.cos(a) * 0.45, y: s.y + Math.sin(a) * 0.45, z: s.z + Math.random() * 1.2 }, { x: 0, y: 0, z: 1 }, g.userData.glowColor, 1, 1.5, 0.06, 0.5);
      }
      // 캐릭터 머리 장식 (판 사이에 바뀔 수 있어 바뀔 때만 다시 붙임)
      if (g.userData.char !== p.char) {
        if (g.userData.acc) g.userData.rig.remove(g.userData.acc);
        g.userData.acc = p.char && !g.userData.figure ? charAccessory(p.char) : null; // TABS 식 몸은 옷을 입고 있음
        if (g.userData.acc) g.userData.rig.add(g.userData.acc);
        g.userData.char = p.char;
      }
      g.userData.hammer.visible = p.char === 'builder'; // 건축가 무기 (예전 아이템 망치 모델)
      const gun = g.userData.figure && g.userData.figure.gun;
      if (gun) {
        // 갈고리 장전: 손에 든 권총 부싯돌 자리에 불꽃이 깜빡 / 빈 총이면 허리에서 가끔 연기
        gun.loaded = !!p.loaded;
        gun.spark.visible = !!p.loaded && Math.floor(performance.now() / 90) % 3 !== 0;
        if (!p.loaded && p.alive && gun.holster.visible && Math.random() < dt * 4) {
          const w = gun.holster.getWorldPosition(new THREE.Vector3());
          this.effects.burst({ x: w.x, y: w.y, z: w.z + 0.05 }, { x: 0, y: 0 }, 0x9a9a9a, 1, 0.6, 0.07, 0.7);
        }
      }
      if (g.userData.figure?.setForm) g.userData.figure.setForm(p.bard?.form); // 바드 폼 (snapshot bard.form: 'bard' | 'metal', 없으면 음유시인)
      const balls = g.userData.figure && g.userData.figure.balls;
      if (balls) balls.forEach((b, i) => (b.visible = i < (p.cannon ? p.cannon.ammo : balls.length))); // 대포수 허리 포탄 = 남은 탄
      // 왼손에 고른 칸의 물건, 조종권 대기 중이면 머리 위 하늘색 팔면체
      const kind = heldKind(p);
      for (const [k, m] of Object.entries(g.userData.held)) m.visible = k === kind;
      const wait = g.userData.waitMark;
      wait.visible = p.hasControl && !p.controlling;
      if (wait.visible) wait.rotation.z = performance.now() / 400;
      const sq = this.effects.squashAmount(p.id);
      g.scale.set(1 + 0.28 * sq, 1 + 0.28 * sq, 1 - 0.32 * sq);
      // 밀치기: 오른팔을 앞으로 뻗음
      const pu = this.effects.punchAmount(p.id);
      const arm = g.userData.arms[0];
      // 옆으로 뻗은 오른팔(-y 쪽)을 z축으로 돌려 앞(+x)을 향하게
      arm.position.x = arm.userData.base.x + 0.3 * pu;
      arm.position.z = arm.userData.base.z + 0.2 * pu;
      arm.rotation.z = (Math.PI / 2) * pu;
      this.emoteAnim(g, p.emote ?? -1, g.userData.anim, dt); // 밀치기 뒤에 (팔을 덮어씀)
      // 이름 + 피해 % 표시: 바뀔 때만 다시 그림
      const label = g.userData.label;
      const dmg = p.damage || 0;
      const name = p.nick || p.name;
      const key = `${name}|${dmg}|${g.userData.color}`;
      if (label.shown !== key) {
        drawLabel(label.canvas, name, `#${g.userData.color.toString(16).padStart(6, '0')}`, dmg);
        label.tex.needsUpdate = true;
        label.shown = key;
      }
      label.sprite.visible = p.alive && !state.menu && !(p.id === myId && this.third); // 메뉴 배경 장면은 이름·% 없음 // 3인칭에서 내 % 는 화면 아래에 (머리 위와 둘 다 있으면 겹침)
      this.updateHuntMarks(g, p, myId);
      this.updateUltAura(g, p, s, myId, dt);
      this.updateStatusFx(g, p, s, myId);
      if (p.char === 'bard' || g.userData.ampFx) this.updateAmpFx(g, p, s, dt);
      if (p.char === 'berserker' || g.userData.whirlFx || g.userData.dizzyStars) this.updateWhirlFx(g, p, s, dt);
      if (rag) this.ragdollCapture(g, p, s, dt);
    }
    this.thinLabels();
    prof.end('bodies', tb);
    this.ragCount = this.ragdoll ? ragKeep.size : 0; // 성능 표시: 래그돌 켠 수
    if (this.ragdoll) {
      // 몸 물리: 모은 목표 자세로 한 번에 돌리고 관절 회전으로 되돌려 넣음
      const tr = prof.begin();
      this.ragdoll.prune(ragKeep);
      this.ragdoll.step(dt, (x, y, z) => this.solidAt(state, x, y, z), { w: this.W, d: this.D });
      for (const id of ragKeep) this.ragdoll.apply(id);
      prof.end('ragdoll', tr);
    }
    for (const [id, g] of this.playerMeshes) {
      if (!seen.has(id)) {
        const w = g.userData.whirlFx; // 씬에 따로 붙인 광전사 효과도 치움
        if (w) this.scene.remove(w.ring, w.trail);
        for (const m of g.userData.dizzyStars || []) this.scene.remove(m);
        if (g.userData.ultAura) this.scene.remove(g.userData.ultAura.grp);
        if (g.userData.ampFx) this.scene.remove(g.userData.ampFx.cab);
        this.scene.remove(g);
        this.playerMeshes.delete(id);
        this.smooth.delete(id);
        this.tracks.delete(id);
      }
    }

    // 블록 + 그림자 (여러 개). 칸 수는 블록마다 다르다 (테트리미노 4칸, 설치 블록 1×2 는 2칸)
    const pieces = state.pieces || [];
    const slots = [];
    for (const piece of pieces) for (let i = 0; i < piece.cells.length; i++) slots.push([piece, i]);
    const need = slots.length;
    while (this.pieceMeshes.length < need) {
      // 칸마다 '자리'만 (장면엔 안 넣음): 위치·재질을 정하면 그리기 직전 flushPieces 가 재질마다 InstancedMesh 하나로 그림
      const m = new THREE.Object3D();
      m.material = this.pieceMat;
      this.pieceMeshes.push(m);
      const s = new THREE.Object3D();
      s.material = this.shadowMat;
      this.shadowMeshes.push(s);
    }
    // 압사 경고 중이면 내 몸과 겹치는 그림자 칸을 빨갛게, 발밑에 빨간 고리 (깜빡)
    const meNow = state.players.find((p) => p.id === myId);
    const warned = !!(meNow && meNow.alive && meNow.danger !== null && meNow.danger !== undefined);
    const dangerAt = (x, y) => warned && x < meNow.x + C.PLAYER_HALF && x + 1 > meNow.x - C.PLAYER_HALF && y < meNow.y + C.PLAYER_HALF && y + 1 > meNow.y - C.PLAYER_HALF;
    const ms = warned && this.smooth.get(myId);
    this.dangerRing.visible = !!ms;
    if (ms) {
      this.dangerRing.position.set(ms.x, ms.y, ms.z + 0.04);
      this.dangerRing.scale.setScalar(1 + 0.25 * Math.sin(performance.now() / 60));
    }
    for (let k = 0; k < this.pieceMeshes.length; k++) {
      const pm = this.pieceMeshes[k];
      const sm = this.shadowMeshes[k];
      if (k >= slots.length) {
        pm.visible = false;
        sm.visible = false;
        continue;
      }
      const [piece, i] = slots[k];
      const [x, y, z] = piece.cells[i];
      pm.position.set(x + 0.5, y + 0.5, z + 0.5);
      pm.visible = true;
      pm.material = piece.shape === 'ghost' ? this.ghostPieceMat(piece.ghostColor ?? piece.ghostSlot) : piece.thrown ? this.thrownMat : piece.controller !== null ? this.controlledMat : piece.sky ? this.skyPieceMat(piece.shape) : this.shapeMat(piece.shape);
      const mine = piece.phase === 'control' && piece.controller === myId;
      const showShadow = piece.shadowVisible || mine;
      sm.visible = showShadow;
      if (showShadow) {
        const [sx, sy] = piece.shadow[i];
        sm.position.set(sx + 0.5, sy + 0.5, piece.landZ + 0.03);
        sm.material = mine ? this.previewMat : dangerAt(sx, sy) ? this.dangerShadowMat : this.shadowFor(piece.eta);
        if (mine) this.previewMat.color.setHex(piece.fits ? 0xf0a030 : 0xff2020);
      }
    }

    // 상승하는 위험 (용암 자리)
    const th = prof.begin(); // 성능 표시: 위험 액체
    this.hazard.update(state, dt, myId, state.grid);
    prof.end('hazard', th);

    // 아이템
    while (this.itemMeshes.length < state.items.length) {
      const m = new THREE.Group(); // 종류가 바뀌면 안의 모델을 갈아 끼움
      m.userData.type = null;
      this.scene.add(m);
      this.itemMeshes.push(m);
    }
    for (let i = 0; i < this.itemMeshes.length; i++) {
      const m = this.itemMeshes[i];
      const it = state.items[i];
      if (!it) {
        m.visible = false;
        continue;
      }
      if (m.userData.type !== it.type) {
        m.clear();
        m.add(this.itemShape(it.type));
        m.userData.type = it.type;
      }
      m.visible = true;
      m.position.set(it.x + 0.5, it.y + 0.5, it.z + 0.45 + Math.sin(performance.now() / 300 + i) * 0.06);
      m.rotation.z += dt * 2;
    }

    // 투사체
    while (this.projMeshes.length < state.projectiles.length) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(C.PROJECTILE_RADIUS, 8, 8), new THREE.MeshBasicMaterial({ color: 0xffee40 }));
      this.scene.add(m);
      this.projMeshes.push(m);
    }
    for (let i = 0; i < this.projMeshes.length; i++) {
      const m = this.projMeshes[i];
      const pr = state.projectiles[i];
      m.visible = !!pr;
      if (pr) m.position.set(pr.x, pr.y, pr.z);
    }

    // 카메라
    const me = state.players.find((p) => p.id === myId);
    this.updateAim(me && me.alive && view === 'fps' ? me.aim : null);
    this.updateBombs(state.bombs || []);
    this.updateBBlocks(state);
    this.updateStars();
    this.updateQuakes();
    this.updateRopes();
    this.updateGhosts();
    this.updatePulses();
    this.updateSpinArcs();
    this.updateAims();
    this.updateArrows();
    this.updateShells(state.shells || [], dt);
    this.updateNotes(state.notes || [], dt);
    this.updateAmpWaves();
    this.updateFlats();
    this.updateDives(dt);
    this.updateBonks();
    this.updateGrabs();
    this.updateBeams(state);
    if (me) this.viewArm.material.color.setHex(playerColor(me, state));
    const vp = this.effects.punchAmount(myId);
    this.viewArm.position.set(this.viewArmBase.x - 0.12 * vp, this.viewArmBase.y + 0.08 * vp, this.viewArmBase.z - 0.3 * vp);
    const armView = !!(me && me.alive) && this.skyBlend === 0 && !cam.victory && !cam.selfie && !this.third; // 3인칭은 팔 대신 내 몸
    this.vm.sync(me ? this.playerMeshes.get(me.id) : null);
    this.vm.on = armView && !!this.vm.fig;
    this.vm.update(dt, me ? this.actFor(me.id) : null, !!(me && this.dives?.has(me.id)), !!(me && me.bard && me.bard.ampLeft > 0));
    this.viewArm.visible = armView && !this.vm.on; // 캐릭터 몸이 아니면 (로봇) 예전 팔
    this.viewHammer.visible = !!(me && me.char === 'builder') && !heldKind(me); // 1인칭 건축가 망치 (아이템을 들면 아이템)
    // 손에 든 것: 고른 핫바 칸에 뭐가 있으면 그 색 상자 (망치가 있으면 망치가 우선)
    const kind = me ? heldKind(me) : null;
    for (const [k, o] of Object.entries(this.viewHeld)) o.visible = k === kind; // 든 아이템 (건축가는 아이템을 들면 망치 대신)
    this.effects.update(dt, this.skyBlend >= 1 ? this.skyCamera : this.camera);
    this.updateMarks();
    this.pieceMat.opacity = this.skyBlend > 0.5 ? 0.55 : 1; // 하늘 시점에선 블록 너머로 착지 미리보기가 보이게
    this.controlledMat.opacity = this.pieceMat.opacity;
    this.thrownMat.opacity = this.pieceMat.opacity;
    this.thrownMat.emissive.setHex(Math.floor(performance.now() / C.THROWN_BLINK_MS) % 2 ? 0x806000 : 0x000000);
    for (const m of Object.values(this.shapeMats)) m.opacity = this.pieceMat.opacity;
    // 하늘 계단 블록: 모양 색보다 밝고 하늘색으로 은은히 빛나며 살짝 비침 (떠 있는 느낌). 하늘 시점이면 더 비침
    const skyGlow = 0.55 + 0.45 * Math.sin(performance.now() / 500);
    for (const m of Object.values(this.skyMats || {})) {
      m.opacity = this.pieceMat.opacity < 1 ? 0.45 : C.SKY_PIECE_OPACITY;
      m.emissive.setRGB(0.12 * skyGlow, 0.22 * skyGlow, 0.3 * skyGlow);
    }

    // 1인칭(또는 관전) 자세
    const eye = new THREE.Vector3();
    const look = new THREE.Vector3();
    if (me && me.alive && this.third) {
      // 3인칭: 머리 위 점을 중심으로 시선 뒤·위에 카메라. 블록이 가리면 바로 앞으로 당겼다가 천천히 돌아감
      const s = this.smooth.get(me.id);
      // 중심은 머리 위에서 오른쪽(시선 기준)으로 조금 비킴 → 내 몸이 화면 가운데 왼쪽 아래, 바로 앞 상대가 안 가림
      const pivot = { x: s.x + Math.sin(cam.yaw) * C.TP_SIDE, y: s.y - Math.cos(cam.yaw) * C.TP_SIDE, z: s.z + C.TP_PIVOT_UP };
      const orbit = Math.max(-Math.PI / 2 + 0.05, cam.pitch - C.TP_TILT);
      const want = orbitEye(pivot, cam.yaw, orbit, C.TP_DIST, (x, y, z) => this.solidAt(state, x, y, z), { margin: C.TP_CAM_MARGIN }).dist;
      this.tpDist = followDist(this.tpDist, want, dt, C.TP_EASE_OUT);
      const e = orbitEye(pivot, cam.yaw, orbit, this.tpDist);
      eye.set(e.x, e.y, Math.max(s.z + C.TP_MIN_Z, e.z));
      const cp = Math.cos(cam.pitch);
      look.set(pivot.x + cp * Math.cos(cam.yaw) * C.TP_LOOK_AHEAD, pivot.y + cp * Math.sin(cam.yaw) * C.TP_LOOK_AHEAD, pivot.z + Math.sin(cam.pitch) * C.TP_LOOK_AHEAD);
    } else if (me && me.alive) {
      const s = this.smooth.get(me.id);
      eye.set(s.x, s.y, s.z + C.EYE_HEIGHT);
      const cp = Math.cos(cam.pitch);
      look.set(eye.x + cp * Math.cos(cam.yaw), eye.y + cp * Math.sin(cam.yaw), eye.z + Math.sin(cam.pitch));
    } else if (cam.follow !== null && cam.follow !== undefined && this.smooth.has(cam.follow)) {
      // 관전: 따라가는 사람 둘레를 마우스(yaw·pitch)로 돌고 휠로 거리. 블록이 가리면 앞으로 당김
      const s = this.smooth.get(cam.follow);
      look.set(s.x, s.y, s.z + C.SPECTATE_LOOK_UP);
      const e = orbitEye(look, cam.yaw, cam.pitch, cam.dist ?? C.SPECTATE_DIST, (x, y, z) => this.solidAt(state, x, y, z), { margin: C.SPECTATE_CAM_MARGIN });
      eye.set(e.x, e.y, e.z);
    } else {
      // 죽었거나 아직 없음: 전체 보기. 필드 가운데를 살아 있는 사람들 높이에서 바라보며 마우스로 돌고 휠로 거리
      const alive = state.players.filter((p) => p.alive && this.smooth.has(p.id));
      const want = alive.length ? alive.reduce((a, p) => a + this.smooth.get(p.id).z, 0) / alive.length + C.SPECTATE_LOOK_UP : 2;
      if (this.overviewZ === undefined) this.overviewZ = want;
      this.overviewZ += (want - this.overviewZ) * (1 - Math.exp(-C.SPECTATE_OVERVIEW_FOLLOW * dt));
      look.set(this.W / 2, this.D / 2, this.overviewZ);
      const e = orbitEye(look, cam.yaw, cam.pitch, (cam.overviewDist ?? C.SPECTATE_OVERVIEW_DIST) * overviewScale(Math.max(this.W, this.D), C.GRID_W)); // 큰 판은 멀리
      eye.set(e.x, e.y, Math.max(0.5, e.z));
    }
    if (cam.pose) {
      eye.copy(cam.pose.eye); // 타이틀 카메라 (메뉴 장면)
      look.copy(cam.pose.look);
    }
    if (!(me && me.alive && this.third)) this.tpDist = null; // 다음 3인칭은 처음 거리부터
    this.victoryCamera(state, cam, dt, eye, look);
    // 3인칭·관전 따라가기: 카메라와 캐릭터 사이에 낀 떨어지는 블록·하늘 계단 블록은 반투명 (쌓인 블록은 위에서 카메라를 당김)
    let subject = null;
    if (me && me.alive && this.third && this.smooth.has(me.id)) subject = this.smooth.get(me.id);
    else if (!(me && me.alive) && cam.follow != null && this.smooth.has(cam.follow)) subject = this.smooth.get(cam.follow);
    this.fadeOccluders(subject && !cam.victory ? eye : null, subject);
    this.piecePool.flush(this.pieceMeshes); // 떨어지는 블록 칸·그림자 칸: 재질마다 한 번에 그림
    this.shadowPool.flush(this.shadowMeshes);

    const b = this.skyBlend;
    const skyUp = new THREE.Vector3(Math.cos(this.skyYaw), Math.sin(this.skyYaw), 0);
    if (b >= 1) {
      this.skyCamera.up.copy(skyUp);
      this.skyCamera.lookAt(this.W / 2, this.D / 2, 0);
      this.draw(this.skyCamera);
      return;
    }
    if (b <= 0) {
      this.camera.fov = this.fov;
      this.camera.updateProjectionMatrix();
      this.camera.up.set(0, 0, 1);
      this.camera.position.copy(eye);
      this.camera.lookAt(look);
      const sh = this.effects.shakeOffset();
      if (sh) this.camera.position.add(new THREE.Vector3(sh.x, sh.y, sh.z));
      if (this.camHook) this.camHook(this.camera); // KO 연출 (client/ko.js 마지막 킬 줌·화면 끝 번쩍)
      this.draw(this.camera);
      this.vm.draw(this.renderer, this.outlineOn ? this.outline : null, this.camera.aspect);
      return;
    }
    // 전환 중: 1인칭 자세 → 필드 위 높은 곳에서 내려다보는 자세로 날아오르며 줌인 (끝에서 직교 카메라로 교체)
    const t = b * b * (3 - 2 * b); // smoothstep
    const top = new THREE.Vector3(this.W / 2, this.D / 2, this.skyCamH());
    const center = new THREE.Vector3(this.W / 2, this.D / 2, 0);
    const half = Math.max(this.W, this.D) / 2 + 1;
    const skyFov = (2 * Math.atan(half / this.skyCamH()) * 180) / Math.PI;
    this.camera.fov = this.fov + (skyFov - this.fov) * t;
    this.camera.updateProjectionMatrix();
    this.camera.position.lerpVectors(eye, top, t);
    this.camera.up.set(skyUp.x * t, skyUp.y * t, 1 - t).normalize();
    this.camera.lookAt(new THREE.Vector3().lerpVectors(look, center, t));
    this.draw(this.camera);
  }

  // view 목표로 skyBlend 를 SKY_TRANSITION_MS 동안 옮긴다. 0 = 1인칭, 1 = 하늘 시점
  stepView(view, dt) {
    const target = view === 'sky' ? 1 : 0;
    const step = (dt * 1000) / C.SKY_TRANSITION_MS;
    if (this.skyBlend < target) this.skyBlend = Math.min(target, this.skyBlend + step);
    else if (this.skyBlend > target) this.skyBlend = Math.max(target, this.skyBlend - step);
  }
}
