// three.js 렌더링. 단색 블록, 최소한의 비주얼. 좌표계는 게임과 같은 z-up.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { buildCharacter, charAccessory } from '/character.js';
import { figureAnim, MOVES } from '/figure.js';
import { Effects } from '/effects.js';
import { CELL, SHAPE_NAMES } from '/shared/pieces.js';
import { orbitEye, followDist } from '/shared/camera.js';
import { itemModel } from '/models.js';
import { makeTextures } from '/textures.js';
import { OutlineEffect } from 'three/addons/effects/OutlineEffect.js';

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
  if (v === CELL.THROWN) return C.THROWN_COLOR;
  const shape = SHAPE_NAMES[v - CELL.SHAPE_BASE];
  if (shape) return new THREE.Color(C.SHAPE_COLORS[shape]).multiplyScalar(C.BLOCK_LANDED_SHADE).getHex();
  return C.TERRAIN_COLOR;
}

// 용암 표면: 꼭짓점을 천천히 출렁이고, 겹친 사인 무늬로 어두운 빨강 ~ 밝은 노랑이 흐름 (빛 계산 없이 스스로 빛남)
function lavaSurfaceMaterial() {
  return noOutline(new THREE.ShaderMaterial({
    uniforms: { time: { value: 0 } },
    vertexShader: `uniform float time; varying vec2 vXY;
      void main() {
        vec3 p = position;
        p.z += sin(p.x * 1.3 + time * 1.1) * 0.06 + sin(p.y * 1.7 - time * 0.9) * 0.05;
        vXY = p.xy;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }`,
    fragmentShader: `uniform float time; varying vec2 vXY;
      void main() {
        float n = sin(vXY.x * 0.9 + time * 0.5) + sin(vXY.y * 1.1 - time * 0.4) + sin((vXY.x + vXY.y) * 0.7 + time * 0.3) + sin(length(vXY) * 1.6 - time * 0.8);
        float b = smoothstep(0.6, 2.4, n);
        vec3 c = mix(vec3(0.55, 0.08, 0.02), vec3(1.0, 0.38, 0.05), smoothstep(-1.5, 1.2, n));
        c = mix(c, vec3(1.0, 0.85, 0.35), b);
        gl_FragColor = vec4(c, 1.0);
      }`,
  }));
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
    },
    vertexShader: `varying vec3 vDir;
      void main() { vDir = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform vec3 top; uniform vec3 mid; uniform vec3 horizon; uniform vec3 sunDir; varying vec3 vDir;
      void main() {
        float h = clamp(vDir.z, -1.0, 1.0);
        vec3 c = h < 0.25 ? mix(horizon, mid, smoothstep(0.0, 0.25, h)) : mix(mid, top, smoothstep(0.25, 0.85, h));
        if (h < 0.0) c = mix(horizon, horizon * 0.55, smoothstep(0.0, -0.4, h));
        float s = max(dot(normalize(vDir), sunDir), 0.0);
        c += vec3(1.0, 0.65, 0.35) * pow(s, 8.0) * 0.45;
        c = mix(c, vec3(1.0, 0.93, 0.75), smoothstep(0.9985, 0.9995, s));
        gl_FragColor = vec4(c, 1.0);
      }`,
  });
  const dome = new THREE.Mesh(new THREE.SphereGeometry(150, 32, 16), mat);
  dome.position.set(C.GRID_W / 2, C.GRID_D / 2, 0);
  dome.renderOrder = -1;
  noOutline(mat);
  return dome;
}

export const PLAYER_COLORS = [0xe05050, 0x50c050, 0xb060e0, 0xe0c050, 0xf0f0f0, 0x40d0c0, 0xff80b0, 0x8a5a30];
// 팀전 몸 색: 팀마다 계열 색, 팀 안에서는 자리 순으로 명암을 달리해 구분
export const TEAM_COLORS = { red: [0xe04040, 0xff8c50, 0xc02868, 0xff6090], blue: [0x3a6ee8, 0x30c0e8, 0x6a50e0, 0x40d8b0] };
export const TEAM_MAIN = { red: 0xe04040, blue: 0x3a6ee8 };
export function playerColor(p, state) {
  if (state && state.teamMode && TEAM_COLORS[p.team]) {
    const mates = state.players.filter((o) => o.team === p.team).sort((a, b) => a.slot - b.slot);
    const list = TEAM_COLORS[p.team];
    return list[Math.max(0, mates.findIndex((o) => o.id === p.id)) % list.length];
  }
  return PLAYER_COLORS[p.slot % PLAYER_COLORS.length];
}
const _q = new THREE.Quaternion();
const HEAVY_HITS = new Set(['bomb', 'shock', 'projectile', 'slam', 'whirl', 'wall', 'blast', 'bigbomb']); // 몸이 크게 휘청하는 공격
const MAX_CELLS = C.GRID_W * C.GRID_D * C.GRID_H;

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
    this.scene.add(skyDome());

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
    // 1인칭 망치 머리 (망치 있을 때만)
    this.viewHammer = itemModel(models, 'weapon', 0.26) || new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.12, 0.12), toon({ color: 0xff8a10 }));
    this.viewHammer.position.set(0, -0.26, 0); // 캡슐 먼 끝 (x축 +90도 회전이라 로컬 -y 가 화면 안쪽)
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
    // 하늘 시점: 필드가 화면에 꽉 차는 직교 카메라 (블록과 그림자가 같은 크기로 보인다)
    this.skyCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
    this.skyCamera.up.set(0, 1, 0);
    this.skyCamera.position.set(C.GRID_W / 2, C.GRID_D / 2, C.SKY_CAMERA_HEIGHT);
    this.skyCamera.lookAt(C.GRID_W / 2, C.GRID_D / 2, 0);
    this.fitSkyCamera();

    // 노을: 하늘은 따뜻하게, 땅 반사는 푸르스름하게. 해는 낮게 떠서 그림자가 길다
    const hemi = new THREE.HemisphereLight(0xffe2d2, 0x8a90b8, 1.15);
    this.scene.add(hemi);
    const sun = new THREE.DirectionalLight(C.SUN_COLOR, 1.25);
    const center = new THREE.Vector3(C.GRID_W / 2, C.GRID_D / 2, 0);
    sun.position.copy(center).addScaledVector(new THREE.Vector3(...C.SUN_DIR).normalize(), 30);
    sun.target.position.copy(center);
    this.scene.add(sun, sun.target);
    const reach = Math.hypot(C.GRID_W, C.GRID_D) / 2 + 4; // 필드 + 여백을 덮는 그림자 상자
    Object.assign(sun.shadow.camera, { left: -reach, right: reach, top: reach + 4, bottom: -reach, near: 5, far: 60 });
    sun.shadow.mapSize.set(C.SHADOW_MAP_SIZE, C.SHADOW_MAP_SIZE);
    sun.shadow.bias = -0.0008;
    sun.shadow.normalBias = 0.03;
    this.sun = sun;

    this.tex = makeTextures([C.GRID_W, C.GRID_D]);
    // 바닥: 칸마다 타일 한 장
    const floor = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W, C.GRID_D, 0.3),
      toon({ color: 0xa49aa0, map: this.tex.floor }),
    );
    floor.position.set(C.GRID_W / 2, C.GRID_D / 2, -0.15);
    floor.receiveShadow = true;
    this.scene.add(floor);
    const gridHelper = new THREE.GridHelper(C.GRID_W, C.GRID_W, 0x222222, 0x444444);
    gridHelper.rotation.x = Math.PI / 2;
    gridHelper.position.set(C.GRID_W / 2, C.GRID_D / 2, 0.002);
    this.scene.add(gridHelper);
    // 필드 경계 (높이 표시용 세로선)
    const edges = new THREE.LineSegments(
      new THREE.EdgesGeometry(new THREE.BoxGeometry(C.GRID_W, C.GRID_D, C.GRID_H)),
      new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.15 }),
    );
    edges.position.set(C.GRID_W / 2, C.GRID_D / 2, C.GRID_H / 2);
    this.scene.add(edges);

    // 쌓인 블록 (인스턴스). 텍스처가 종류마다 달라 종류별로 하나씩: 지형 돌 · 쌓기 나무 · 설치 블록 모래 · 테트리미노
    const blockGeo = new THREE.BoxGeometry(1, 1, 1);
    this.blockMeshes = {};
    for (const [kind, map] of Object.entries({ terrain: this.tex.stone, build: this.tex.wood, thrown: this.tex.sand, shape: this.tex.tetris })) {
      const mesh = new THREE.InstancedMesh(blockGeo, toon({ color: 0xffffff, map }), MAX_CELLS);
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
    this.pieceMat = toon({ color: 0xf0a030, map: this.tex.tetris, transparent: true, opacity: 1 }); // 자동 블록
    this.controlledMat = toon({ color: 0xd040d0, emissive: 0x501050, map: this.tex.tetris, transparent: true, opacity: 1 }); // 누가 조종 중인 블록 (빛나서 T 모양 보라와 구분)
    this.shapeMats = {}; // 자동 블록: 모양마다 색
    this.thrownMat = toon({ color: 0xffffff, emissive: 0x000000, map: this.tex.sand, transparent: true, opacity: 1 }); // 던진 설치 블록: 흰색 + 노랗게 깜빡임 (O 블록 노랑과 구분)
    this.shadowMat = noOutline(new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45 }));
    this.pieceBox = new THREE.BoxGeometry(1, 1, 1);
    this.shadowBox = new THREE.BoxGeometry(0.96, 0.96, 0.06);
    this.markBox = new THREE.BoxGeometry(0.94, 0.94, 0.04); // 스킬 예고 칸
    this.marks = [];
    // 압사 경고: 나를 깔 블록의 그림자는 빨갛게 + 내 발밑에 빨간 고리
    this.dangerShadowMat = noOutline(new THREE.MeshBasicMaterial({ color: 0xff1010, transparent: true, opacity: 0.6 }));
    this.dangerRing = new THREE.Mesh(new THREE.RingGeometry(0.42, 0.58, 24), noOutline(new THREE.MeshBasicMaterial({ color: 0xff2020, transparent: true, opacity: 0.85, side: THREE.DoubleSide, depthTest: false })));
    this.dangerRing.renderOrder = 9;
    this.dangerRing.visible = false;
    this.scene.add(this.dangerRing);

    // 용암: 필드보다 넓은 판. 표면 높이 = state.lava.z
    this.lavaBottom = -6;
    this.lava = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W + 12, C.GRID_D + 12, 1),
      noOutline(new THREE.MeshBasicMaterial({ color: 0x9a2408 })),
    );
    this.lava.visible = false;
    this.scene.add(this.lava);
    // 표면: 천천히 출렁이고 밝은 무늬가 흐르는 판 (몸통 위에 얹음)
    this.lavaTop = new THREE.Mesh(new THREE.PlaneGeometry(C.GRID_W + 12, C.GRID_D + 12, 48, 48), lavaSurfaceMaterial());
    this.lavaTop.visible = false;
    this.scene.add(this.lavaTop);
    // 용암 빛: 가까운 블록 옆면을 주황으로 비춤 (늘 씬에 두고 세기만 바꿈 — 빛 개수가 바뀌면 셰이더를 다시 만듦)
    this.lavaLight = new THREE.PointLight(0xff6a20, 0, C.LAVA_LIGHT_RANGE, 1.4);
    this.scene.add(this.lavaLight);
    this.emberAcc = 0;

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
    this.acts = new Map(); // 공격 동작 (id → { id, move, t0, windup 초, struck 판정 시각, rec 초, broken 끊긴 시각 })
    this.hitSeq = 0;
    this.itemMeshes = [];
    this.projMeshes = [];
    this.smooth = new Map(); // id -> {x,y,z}
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

  fitSkyCamera() {
    const aspect = window.innerWidth / window.innerHeight;
    const half = Math.max(C.GRID_W, C.GRID_D) / 2 + 1; // 필드 + 여백 1칸
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
    for (let z = 0; z < C.GRID_H; z++) {
      for (let y = 0; y < C.GRID_D; y++) {
        for (let x = 0; x < C.GRID_W; x++) {
          const v = grid[(z * C.GRID_D + y) * C.GRID_W + x];
          if (!v || (skip && skip.has((z * C.GRID_D + y) * C.GRID_W + x))) continue;
          const kind = v === CELL.TERRAIN ? 'terrain' : v === CELL.BUILD ? 'build' : v === CELL.THROWN ? 'thrown' : 'shape';
          const mesh = this.blockMeshes[kind];
          const n = count[kind]++;
          m.makeTranslation(x + 0.5, y + 0.5, z + 0.5);
          mesh.setMatrixAt(n, m);
          // 무엇이 남긴 칸인지에 따라 색 (지형 돌·쌓기 나무·설치 블록 모래·테트리미노 모양 색), 인접 칸은 체커보드로 살짝 명암
          color.setHex(cellColor(v));
          if ((x + y + z) % 2) color.multiplyScalar(0.94);
          mesh.setColorAt(n, color);
        }
      }
    }
    for (const [kind, mesh] of Object.entries(this.blockMeshes)) {
      mesh.count = count[kind];
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }
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
      this.shapeMats[shape] = toon({ color: C.SHAPE_COLORS[shape] ?? 0xf0a030, map: this.tex.tetris, transparent: true, opacity: 1 });
    }
    return this.shapeMats[shape];
  }

  // 외곽선 켜기·끄기 (설정). 켜면 OutlineEffect 가 장면을 한 번 더 (뒤집힌 테두리로) 그린다
  setOutline(on) {
    this.outlineOn = !!on;
  }

  draw(camera) {
    if (this.outlineOn) this.outline.render(this.scene, camera);
    else this.renderer.render(this.scene, camera);
  }

  // 그림자 켜기·끄기 (대기 화면 설정). 꺼지면 그림자 패스 자체를 안 돌아 느린 PC 에서 가벼움
  setShadows(on) {
    this.sun.castShadow = !!on;
  }

  getPlayerMesh(p) {
    let g = this.playerMeshes.get(p.id);
    // 캐릭터마다 몸이 다르면(TABS 식) 캐릭터를 바꿨을 때 다시 만든다
    const look = C.FIGURE_CHARS.includes(p.char) ? p.char : 'robot';
    if (g && g.userData.look !== look) {
      this.scene.remove(g);
      this.playerMeshes.delete(p.id);
      g = null;
    }
    if (!g) {
      const color = PLAYER_COLORS[p.slot % PLAYER_COLORS.length];
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
      sprite.scale.set(0.3, 0.13, 1);
      sprite.position.z = C.PLAYER_HEIGHT + 0.45;
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
    const air = Math.abs(a.vz) > C.ANIM_AIR_VZ;
    if (wasFalling && !air) a.land = 1; // 내려앉음
    a.land = Math.max(0, a.land - dt / C.ANIM_LAND_S);
    // 걷기: 발이 땅에 있을 때만 걸음 위상이 돎
    const walking = !air && a.hs > C.ANIM_WALK_MIN_SPEED;
    if (walking) a.walk += dt * a.hs * C.ANIM_WALK_FREQ;
    const step = walking ? Math.sin(a.walk) : 0;
    const robot = g.userData.robot; // 로봇은 걷기·춤을 모델 동작이 하므로 통통 튀기·흔들기·빙글은 안 함
    const fig = g.userData.figure; // TABS 식 몸은 관절로 걸음 (통통 튀기·흔들기·늘어나기 안 함, 춤 빙글은 함)
    const jointed = robot || fig;
    parts.position.z = -C.PLAYER_HEIGHT / 2 + (walking && !jointed ? Math.abs(step) * C.ANIM_BOB : 0);
    g.userData.feet.forEach((f, i) => (f.position.x = f.userData.baseX + (i ? -step : step) * C.ANIM_STEP));
    // 경직된 채 빠르게 날아가면 뒤로 구름. 끝나면 가장 가까운 바로 선 자세로 돌아옴
    if (fig) {
      this.figureFlight(a, s, p, air, vx, vy, dt);
      // 안전장치: 구르기·공중제비 각이 깨지면 바로 선 자세로
      if (!Number.isFinite(a.spin)) a.spin = 0;
      if (!Number.isFinite(a.flipAngle)) a.flipAngle = 0;
      if (a.tumbleAxis && ![a.tumbleAxis.x, a.tumbleAxis.y, a.tumbleAxis.z].every(Number.isFinite)) a.tumbleAxis.set(0, 1, 0);
    }
    else if (p.stunned && a.hs > C.ANIM_TUMBLE_MIN_SPEED) a.spin -= dt * C.ANIM_TUMBLE_SPEED;
    else a.spin += (Math.round(a.spin / (Math.PI * 2)) * Math.PI * 2 - a.spin) * (1 - Math.exp(-C.ANIM_SMOOTH * dt));
    const lean = Math.min(1, a.hs / C.MOVE_SPEED) * C.ANIM_LEAN;
    rig.rotation.y = lean + (fig ? a.flipAngle : a.spin);
    rig.rotation.x = jointed ? 0 : step * C.ANIM_SWAY; // 걸을 때 좌우로 살짝 흔들
    // 승자 춤·이모트 '춤': 깡충 뛰며 제자리에서 빙글
    const emote = p.emote ?? -1;
    const dancing = this.victoryId === p.id || emote === 1;
    a.dance = dancing ? (a.dance || 0) + dt : 0;
    rig.rotation.z = dancing && !robot ? a.dance * C.VICTORY_SPIN : 0;
    if (fig && a.spin) rig.quaternion.premultiply(_q.setFromAxisAngle(a.tumbleAxis, a.spin)); // 날아가는 쪽으로 구름
    if (dancing && !robot) parts.position.z += Math.abs(Math.sin(a.dance * C.VICTORY_HOP_FREQ)) * C.VICTORY_HOP;
    if (robot) this.robotAnim(robot, p, a, air, walking, dancing, emote, dt);
    if (fig) {
      a.emoteT = emote >= 0 && emote !== 1 ? (a.emoteT || 0) + dt : 0;
      a.t = (a.t || 0) + dt;
      const punch = this.effects.punchAmount(p.id);
      const hit = this.hitFor(p);
      figureAnim(fig, {
        air, walking, hs: a.hs, walk: a.walk, stunned: p.stunned, dancing, emote, emoteT: a.emoteT, punch, holding: !!heldKind(p), t: a.t,
        hit, act: this.actFor(p.id), tumble: a.tumbleAmt, recover: a.recover * a.recoverPow, land: a.figLand * a.landPow, flip: a.flip >= 0 ? a.flip / C.FIGURE_FLIP_S : -1,
      }, dt);
    }
    const stretch = a.vz > C.ANIM_AIR_VZ && !fig ? C.ANIM_STRETCH : 0; // 올라가는 중: 위로 늘어나고 옆은 가늘게
    const land = fig ? 0 : a.land; // TABS 식 몸은 찌그러지지 않음
    const wide = 1 - stretch / 2 + land * C.ANIM_LAND_SQUASH * 0.6; // 착지: 납작해지며 옆으로 퍼짐
    rig.scale.set(wide, wide, 1 + stretch - land * C.ANIM_LAND_SQUASH);
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
    if (a.flip >= 0) {
      a.flip += dt;
      if (p.stunned || a.flip >= C.FIGURE_FLIP_S) a.flip = -1;
    }
    const f = a.flip >= 0 ? a.flip / C.FIGURE_FLIP_S : 1;
    a.flipAngle = a.flip >= 0 ? Math.PI * 2 * f * f * (3 - 2 * f) : 0; // 웅크리는 동안 천천히 → 가운데서 빨리 → 끝에서 느려짐
  }

  // 맞은 순간 (main.js 의 hit 이벤트). dir = 밀린 방향 (월드, 없으면 null). 콤보 마무리 타면 더 크게
  hitReact(id, dir, { heavy = false, crit = false, kind = null } = {}) {
    const now = performance.now();
    const finish = now - (this.finishAt.get(id) || -1e9) < 200;
    const counter = now - (this.counterAt.get(id) || -1e9) < 200;
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
    const move = e.char === 'hook' && e.name === '주먹' ? 'hook:주먹' : MOVES[e.name] ? e.name : 'punch';
    // 표에서 못 찾거나 이상한 값이면 기본값 (NaN 이 동작에 들어가면 몸이 무너짐)
    const ms = (v, dflt) => (Number.isFinite(v) && v >= 0 ? v : dflt) / 1000;
    this.acts.set(e.who, { id: ++this.hitSeq, move, t0: performance.now(), windup: ms(e.windup, 0), struck: null, rec: ms(def?.rec, 300), broken: 0 });
  }

  // swing 이벤트: 판정 순간 → 타격 자세. 준비 없이 온 것(캐릭터 없는 밀치기)은 바로 타격
  attackSwing(e) {
    const a = this.acts.get(e.who);
    if (a && !a.struck && !a.broken) {
      a.struck = performance.now();
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
      return u >= 1 ? done() : { id: a.id, move: a.move, phase: 'broken', u };
    }
    if (!a.struck) {
      const age = (now - a.t0) / 1000;
      if (age > a.windup + C.FIGURE_SWING_WAIT_S) return done(); // 판정이 안 옴 (캔슬)
      return { id: a.id, move: a.move, phase: 'wind', u: a.windup > 0 ? Math.min(1, age / a.windup) : 1 };
    }
    const s = (now - a.struck) / 1000;
    if (s < C.FIGURE_STRIKE_S) return { id: a.id, move: a.move, phase: 'strike', u: s / C.FIGURE_STRIKE_S };
    const r = (s - C.FIGURE_STRIKE_S) / a.rec;
    return r >= 1 ? done() : { id: a.id, move: a.move, phase: 'rec', u: r };
  }

  // 닌자 표창 (star 이벤트, 한 발마다): 첫 발은 오른손·둘째 발은 왼손으로 던지는 자세 + 아주 빠르게 직진하는 표창 (판정은 즉시)
  starShot(e) {
    const now = performance.now();
    const a = this.acts.get(e.who);
    if (e.shot === 1 && a && a.move === '표창' && !a.struck && !a.broken) a.struck = now;
    else {
      const move = e.shot === 1 ? '표창' : '표창2';
      this.acts.set(e.who, { id: ++this.hitSeq, move, t0: now, windup: 0, struck: now, rec: MOVES[move].rec || 0.25, broken: 0 });
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
      const k = mk.pulse ? 0.55 + 0.45 * Math.sin(now / Math.max(40, left / 6)) : left / mk.ms;
      if (mk.grow) {
        const sc = 1 + mk.grow * (1 - left / mk.ms);
        mk.mesh.scale.set(sc, sc, mk.mesh.scale.z);
      }
      mk.mesh.traverse((o) => {
        if (o.isMesh) o.material.opacity = (o.material.userData.base ??= o.material.opacity) * k;
      });
    }
  }

  // 갈고리 줄: 던진 사람에서 끌려온 사람(빗나가면 보는 방향 끝)까지 잠깐
  showHook(whoId, targetId, yaw) {
    const a = this.smooth.get(whoId);
    if (!a) return;
    const b = targetId !== null && targetId !== undefined ? this.smooth.get(targetId) : null;
    const to = b ? new THREE.Vector3(b.x, b.y, b.z + 0.9) : new THREE.Vector3(a.x + Math.cos(yaw) * C.HOOK_RANGE, a.y + Math.sin(yaw) * C.HOOK_RANGE, a.z + 0.9);
    const geo = new THREE.BufferGeometry().setFromPoints([new THREE.Vector3(a.x, a.y, a.z + 0.9), to]);
    const line = new THREE.Line(geo, noOutline(new THREE.LineBasicMaterial({ color: 0xd8dce8, transparent: true, opacity: 0.9 })));
    this.scene.add(line);
    setTimeout(() => {
      this.scene.remove(line);
      geo.dispose();
      line.material.dispose();
    }, 260);
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
    const sig = list.map((b) => `${b.x},${b.y},${b.z},${b.kind}`).join('|');
    if (sig !== this.bbSig) {
      this.bbSig = sig;
      this.bbSkip = new Set(list.map((b) => (b.z * C.GRID_D + b.y) * C.GRID_W + b.x));
      if (state.grid) this.updateGrid(state.grid);
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
    if (gx < 0 || gy < 0 || gx >= C.GRID_W || gy >= C.GRID_D) return false;
    if (gz < 0) return true;
    if (gz >= C.GRID_H || !state.grid) return false;
    return state.grid[(gz * C.GRID_D + gy) * C.GRID_W + gx] !== 0;
  }

  render(state, myId, dt, view, cam) {
    if (!state) return;
    this.stepView(view, dt);
    if (state.grid && state.gridVersion !== this.gridVersion) {
      this.updateGrid(state.grid);
      this.gridVersion = state.gridVersion;
    }

    // 플레이어
    this.victoryId = cam.victory || null;
    const seen = new Set();
    const k = 1 - Math.exp(-25 * dt);
    for (const p of state.players) {
      seen.add(p.id);
      const g = this.getPlayerMesh(p);
      let s = this.smooth.get(p.id);
      if (!s) {
        s = { x: p.x, y: p.y, z: p.z };
        this.smooth.set(p.id, s);
      }
      if (Math.hypot(p.x - s.x, p.y - s.y, p.z - s.z) > 3) Object.assign(s, { x: p.x, y: p.y, z: p.z });
      s.x += (p.x - s.x) * k;
      s.y += (p.y - s.y) * k;
      s.z += (p.z - s.z) * k;
      g.position.set(s.x, s.y, s.z);
      g.rotation.z = p.yaw;
      this.animate(g, s, p, dt);
      // 이속 증가 중 달리면 발밑에 노란 잔상
      if (p.speedLeft > 0 && g.userData.anim.hs > 1 && Math.random() < dt * C.SPEED_TRAIL_RATE) {
        this.effects.burst({ x: s.x, y: s.y, z: s.z + 0.15 }, null, 0xffe020, 3, 1.2, 0.07, 0.35);
      }
      const firstPerson = view === 'fps' && this.skyBlend === 0 && !cam.victory && !cam.selfie && (!this.third || (this.tpDist ?? C.TP_DIST) < C.TP_HIDE_DIST); // 3인칭은 카메라가 머리 속으로 당겨졌을 때만 숨김
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
      label.sprite.visible = p.alive && !(p.id === myId && this.third); // 3인칭에서 내 % 는 화면 아래에 (머리 위와 둘 다 있으면 겹침)
    }
    for (const [id, g] of this.playerMeshes) {
      if (!seen.has(id)) {
        this.scene.remove(g);
        this.playerMeshes.delete(id);
        this.smooth.delete(id);
      }
    }

    // 블록 + 그림자 (여러 개). 칸 수는 블록마다 다르다 (테트리미노 4칸, 설치 블록 1×2 는 2칸)
    const pieces = state.pieces || [];
    const slots = [];
    for (const piece of pieces) for (let i = 0; i < piece.cells.length; i++) slots.push([piece, i]);
    const need = slots.length;
    while (this.pieceMeshes.length < need) {
      const m = new THREE.Mesh(this.pieceBox, this.pieceMat);
      m.castShadow = true;
      this.scene.add(m);
      this.pieceMeshes.push(m);
      const s = new THREE.Mesh(this.shadowBox, this.shadowMat);
      this.scene.add(s);
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
      pm.material = piece.thrown ? this.thrownMat : piece.controller !== null ? this.controlledMat : this.shapeMat(piece.shape);
      const mine = piece.phase === 'control' && piece.controller === myId;
      const showShadow = piece.shadowVisible || mine;
      sm.visible = showShadow;
      if (showShadow) {
        const [sx, sy] = piece.shadow[i];
        sm.position.set(sx + 0.5, sy + 0.5, piece.landZ + 0.03);
        sm.material = mine ? this.previewMat : dangerAt(sx, sy) ? this.dangerShadowMat : this.shadowMat;
        if (mine) this.previewMat.color.setHex(piece.fits ? 0xf0a030 : 0xff2020);
      }
    }

    // 용암
    const lava = state.lava;
    this.lava.visible = !!(lava && lava.active);
    this.lavaTop.visible = this.lava.visible;
    if (this.lava.visible) {
      const h = Math.max(0.01, lava.z - this.lavaBottom - 0.02);
      this.lava.scale.z = h;
      this.lava.position.set(C.GRID_W / 2, C.GRID_D / 2, this.lavaBottom + h / 2);
      this.lavaTop.position.set(C.GRID_W / 2, C.GRID_D / 2, lava.z);
      const now = performance.now() / 1000;
      this.lavaTop.material.uniforms.time.value = now;
      // 빛은 살짝 일렁임
      this.lavaLight.intensity = C.LAVA_LIGHT_INTENSITY * (0.85 + 0.15 * Math.sin(now * 7) * Math.sin(now * 2.3));
      this.lavaLight.position.set(C.GRID_W / 2, C.GRID_D / 2, lava.z + 1.2);
      // 불똥: 표면 아무 데서나 튀어 오름
      this.emberAcc += dt * C.LAVA_EMBER_RATE;
      for (; this.emberAcc >= 1; this.emberAcc--) {
        const pos = { x: -1 + Math.random() * (C.GRID_W + 2), y: -1 + Math.random() * (C.GRID_D + 2), z: lava.z + 0.05 };
        this.effects.burst(pos, null, Math.random() < 0.5 ? 0xffb030 : 0xff5010, 1, 4, 0.06, 0.8);
      }
    } else {
      this.lavaLight.intensity = 0;
    }

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
    this.updateBeams(state);
    if (me) this.viewArm.material.color.setHex(playerColor(me, state));
    const vp = this.effects.punchAmount(myId);
    this.viewArm.position.set(this.viewArmBase.x - 0.12 * vp, this.viewArmBase.y + 0.08 * vp, this.viewArmBase.z - 0.3 * vp);
    this.viewArm.visible = !!(me && me.alive) && this.skyBlend === 0 && !cam.victory && !cam.selfie && !this.third; // 3인칭은 팔 대신 내 몸
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
      look.set(C.GRID_W / 2, C.GRID_D / 2, this.overviewZ);
      const e = orbitEye(look, cam.yaw, cam.pitch, cam.overviewDist ?? C.SPECTATE_OVERVIEW_DIST);
      eye.set(e.x, e.y, Math.max(0.5, e.z));
    }
    if (!(me && me.alive && this.third)) this.tpDist = null; // 다음 3인칭은 처음 거리부터
    this.victoryCamera(state, cam, dt, eye, look);

    const b = this.skyBlend;
    const skyUp = new THREE.Vector3(Math.cos(this.skyYaw), Math.sin(this.skyYaw), 0);
    if (b >= 1) {
      this.skyCamera.up.copy(skyUp);
      this.skyCamera.lookAt(C.GRID_W / 2, C.GRID_D / 2, 0);
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
      this.draw(this.camera);
      return;
    }
    // 전환 중: 1인칭 자세 → 필드 위 높은 곳에서 내려다보는 자세로 날아오르며 줌인 (끝에서 직교 카메라로 교체)
    const t = b * b * (3 - 2 * b); // smoothstep
    const top = new THREE.Vector3(C.GRID_W / 2, C.GRID_D / 2, C.SKY_CAMERA_HEIGHT);
    const center = new THREE.Vector3(C.GRID_W / 2, C.GRID_D / 2, 0);
    const half = Math.max(C.GRID_W, C.GRID_D) / 2 + 1;
    const skyFov = (2 * Math.atan(half / C.SKY_CAMERA_HEIGHT) * 180) / Math.PI;
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
