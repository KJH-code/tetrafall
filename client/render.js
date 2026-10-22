// three.js 렌더링. 단색 블록, 최소한의 비주얼. 좌표계는 게임과 같은 z-up.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { buildCharacter } from '/character.js';
import { Effects } from '/effects.js';
import { CELL, SHAPE_NAMES } from '/shared/pieces.js';
import { itemModel } from '/models.js';

THREE.Object3D.DEFAULT_UP.set(0, 0, 1);

// P1~P8 색. 블록(파랑 계열)·떨어지는 블록(주황)과 헷갈리지 않는 색 위주
// 아이템 모양·색: 멀리서도 종류를 구분하게
const ITEM_LOOK = {
  control: { color: 0x20e0e0, geo: () => new THREE.OctahedronGeometry(0.3) }, // 하늘색 팔면체
  knockback: { color: 0xe02020, geo: () => new THREE.SphereGeometry(0.24, 14, 10) }, // 빨간 공
  weapon: { color: 0xff8a10, geo: () => new THREE.BoxGeometry(0.42, 0.24, 0.24) }, // 주황 망치 머리
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

// 고른 핫바 칸에 든 것: 'block' | 'brick' | 'ball'(투사체) | 'bomb' | null
export function heldKind(p) {
  if (p.hand === 1) return p.blocks > 0 ? 'block' : null;
  if (p.hand === 2) return p.bricks > 0 ? 'brick' : p.ammo > 0 ? 'ball' : null;
  return p.bombs > 0 ? 'bomb' : null;
}
const HELD_COLOR = { block: 0x6f8fc8, brick: ITEM_LOOK.brick.color, ball: ITEM_LOOK.knockback.color, bomb: 0x222222 };
const HELD_ITEM = { block: null, brick: 'brick', ball: 'knockback', bomb: 'bomb' }; // 손에 든 것 → 아이템 모델

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
  return new THREE.ShaderMaterial({
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
  });
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
    this.canvas = this.renderer.domElement;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(C.SKY_HORIZON);
    this.scene.fog = new THREE.Fog(C.SKY_HORIZON, C.FOG_NEAR, C.FOG_FAR);
    this.scene.add(skyDome());

    this.camera = new THREE.PerspectiveCamera(75, window.innerWidth / window.innerHeight, 0.05, 200);
    this.camera.up.set(0, 0, 1);
    this.scene.add(this.camera); // 1인칭 팔(뷰모델)을 카메라에 붙이려고
    // 1인칭 팔: 화면 오른쪽 아래에 보이는 내 팔. 밀치기 때 앞으로 뻗는다
    this.viewArm = new THREE.Mesh(new THREE.CapsuleGeometry(0.06, 0.32, 4, 10), new THREE.MeshLambertMaterial({ color: 0xffffff }));
    this.viewArm.rotation.x = Math.PI / 2; // 캡슐을 화면 안쪽(-z) 방향으로 눕힘
    this.viewArmBase = new THREE.Vector3(0.26, -0.24, -0.42);
    this.viewArm.position.copy(this.viewArmBase);
    this.viewArm.visible = false;
    this.camera.add(this.viewArm);
    // 1인칭 망치 머리 (망치 있을 때만)
    this.viewHammer = itemModel(models, 'weapon', 0.26) || new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.12, 0.12), new THREE.MeshLambertMaterial({ color: 0xff8a10 }));
    this.viewHammer.position.set(0, -0.26, 0); // 캡슐 먼 끝 (x축 +90도 회전이라 로컬 -y 가 화면 안쪽)
    this.viewHammer.visible = false;
    this.viewArm.add(this.viewHammer);
    // 1인칭 손에 든 설치 블록 (설치 블록 있을 때만)
    // 손에 든 것 (고른 핫바 칸): 쌓기 블록은 파란 상자, 나머지는 아이템 모델
    this.viewHeld = {};
    for (const [kind, type] of Object.entries(HELD_ITEM)) {
      const o = (type && itemModel(models, type, 0.15)) || new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.13, 0.13), new THREE.MeshLambertMaterial({ color: HELD_COLOR[kind] }));
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

    // 바닥
    const floor = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W, C.GRID_D, 0.3),
      new THREE.MeshLambertMaterial({ color: 0xa49aa0 }),
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

    // 쌓인 블록 (인스턴스)
    this.blockMesh = new THREE.InstancedMesh(
      new THREE.BoxGeometry(1, 1, 1),
      new THREE.MeshLambertMaterial({ color: 0xffffff }),
      MAX_CELLS,
    );
    this.blockMesh.count = 0;
    // three.js 는 InstancedMesh 의 경계 구를 처음 한 번만 계산하고 갱신하지 않는다.
    // 블록이 0개일 때 계산된 빈 구가 남으면 원점 모서리가 시야 밖일 때 쌓인 블록 전체가 안 그려진다.
    // 최대 W×D×H 개 한 번의 draw call 이라 시야 판정을 끈다.
    this.blockMesh.frustumCulled = false;
    this.blockMesh.castShadow = true;
    this.blockMesh.receiveShadow = true;
    this.scene.add(this.blockMesh);
    this.gridVersion = -1;

    // 떨어지는 블록 셀 + 그림자 (블록 여러 개 → 필요한 만큼 늘어나는 풀)
    this.pieceMeshes = [];
    this.shadowMeshes = [];
    this.pieceMat = new THREE.MeshLambertMaterial({ color: 0xf0a030, transparent: true, opacity: 1 }); // 자동 블록
    this.controlledMat = new THREE.MeshLambertMaterial({ color: 0xd040d0, emissive: 0x501050, transparent: true, opacity: 1 }); // 누가 조종 중인 블록 (빛나서 T 모양 보라와 구분)
    this.shapeMats = {}; // 자동 블록: 모양마다 색
    this.thrownMat = new THREE.MeshLambertMaterial({ color: 0xffffff, emissive: 0x000000, transparent: true, opacity: 1 }); // 던진 설치 블록: 흰색 + 노랗게 깜빡임 (O 블록 노랑과 구분)
    this.shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45 });
    this.pieceBox = new THREE.BoxGeometry(1, 1, 1);
    this.shadowBox = new THREE.BoxGeometry(0.96, 0.96, 0.06);

    // 용암: 필드보다 넓은 판. 표면 높이 = state.lava.z
    this.lavaBottom = -6;
    this.lava = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W + 12, C.GRID_D + 12, 1),
      new THREE.MeshBasicMaterial({ color: 0x9a2408 }),
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
    this.previewMat = new THREE.MeshBasicMaterial({ color: 0xf0a030, transparent: true, opacity: 0.35 });
    // 조준 미리보기 (고른 핫바 칸): 쌓기 = 흰 상자 1칸, 설치 블록 = 노란 상자 2칸, 폭탄 = 부서질 3×3 범위 빨간 판. 못 쓰면 빨강
    this.aimMat = new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.3, depthWrite: false });
    this.aimEdgeMat = new THREE.LineBasicMaterial({ color: 0xffffff });
    this.aimBoxes = [];
    // 놓인 폭탄: 검은 공, 터질 때가 가까울수록 빨갛게 빨리 깜빡임
    this.bombMeshes = [];
    this.beams = [];
    this.beamMat = new THREE.MeshBasicMaterial({ color: 0xd040d0, transparent: true, opacity: 0.5, depthWrite: false });

    this.playerMeshes = new Map();
    this.itemMeshes = [];
    this.projMeshes = [];
    this.smooth = new Map(); // id -> {x,y,z}
    this.skyBlend = 0; // 0 = 1인칭, 1 = 하늘 시점. 사이 값은 전환 중
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

  updateGrid(grid) {
    const m = new THREE.Matrix4();
    const color = new THREE.Color();
    let n = 0;
    for (let z = 0; z < C.GRID_H; z++) {
      for (let y = 0; y < C.GRID_D; y++) {
        for (let x = 0; x < C.GRID_W; x++) {
          if (!grid[(z * C.GRID_D + y) * C.GRID_W + x]) continue;
          m.makeTranslation(x + 0.5, y + 0.5, z + 0.5);
          this.blockMesh.setMatrixAt(n, m);
          // 무엇이 남긴 칸인지에 따라 색 (지형 돌·쌓기 나무·설치 블록 모래·테트리미노 모양 색), 인접 칸은 체커보드로 살짝 명암
          color.setHex(cellColor(grid[(z * C.GRID_D + y) * C.GRID_W + x]));
          if ((x + y + z) % 2) color.multiplyScalar(0.94);
          this.blockMesh.setColorAt(n, color);
          n++;
        }
      }
    }
    this.blockMesh.count = n;
    this.blockMesh.instanceMatrix.needsUpdate = true;
    if (this.blockMesh.instanceColor) this.blockMesh.instanceColor.needsUpdate = true;
  }

  // 필드에 놓인 아이템 모양: 모델이 있으면 모델, 없으면 예전 도형 (이속 증가는 늘 번개 도형)
  itemShape(type) {
    const model = itemModel(this.models, type, C.ITEM_MODEL_SIZE);
    const look = ITEM_LOOK[type] || ITEM_LOOK.control;
    const o = model || new THREE.Mesh(look.geo(), new THREE.MeshLambertMaterial({ color: look.color, emissive: 0x222222 }));
    o.traverse((c) => {
      if (c.isMesh) c.castShadow = true;
    });
    return o;
  }

  shapeMat(shape) {
    if (!this.shapeMats[shape]) {
      this.shapeMats[shape] = new THREE.MeshLambertMaterial({ color: C.SHAPE_COLORS[shape] ?? 0xf0a030, transparent: true, opacity: 1 });
    }
    return this.shapeMats[shape];
  }

  // 그림자 켜기·끄기 (대기 화면 설정). 꺼지면 그림자 패스 자체를 안 돌아 느린 PC 에서 가벼움
  setShadows(on) {
    this.sun.castShadow = !!on;
  }

  getPlayerMesh(p) {
    let g = this.playerMeshes.get(p.id);
    if (!g) {
      const color = PLAYER_COLORS[p.slot % PLAYER_COLORS.length];
      const ch = buildCharacter(color, this.models);
      g = ch.group;
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
        new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, depthTest: false }),
      );
      arrow.position.z = C.PLAYER_HEIGHT + 0.05;
      arrow.renderOrder = 10;
      g.add(arrow);
      const ring = new THREE.Mesh(
        new THREE.RingGeometry(0.6, 0.78, 32),
        new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide, depthTest: false }),
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
    parts.position.z = -C.PLAYER_HEIGHT / 2 + (walking && !robot ? Math.abs(step) * C.ANIM_BOB : 0);
    g.userData.feet.forEach((f, i) => (f.position.x = f.userData.baseX + (i ? -step : step) * C.ANIM_STEP));
    // 경직된 채 빠르게 날아가면 뒤로 구름. 끝나면 가장 가까운 바로 선 자세로 돌아옴
    if (p.stunned && a.hs > C.ANIM_TUMBLE_MIN_SPEED) a.spin -= dt * C.ANIM_TUMBLE_SPEED;
    else a.spin += (Math.round(a.spin / (Math.PI * 2)) * Math.PI * 2 - a.spin) * (1 - Math.exp(-C.ANIM_SMOOTH * dt));
    const lean = Math.min(1, a.hs / C.MOVE_SPEED) * C.ANIM_LEAN;
    rig.rotation.y = lean + a.spin;
    rig.rotation.x = robot ? 0 : step * C.ANIM_SWAY; // 걸을 때 좌우로 살짝 흔들
    // 승자 춤·이모트 '춤': 깡충 뛰며 제자리에서 빙글
    const emote = p.emote ?? -1;
    const dancing = this.victoryId === p.id || emote === 1;
    a.dance = dancing ? (a.dance || 0) + dt : 0;
    rig.rotation.z = dancing && !robot ? a.dance * C.VICTORY_SPIN : 0;
    if (dancing && !robot) parts.position.z += Math.abs(Math.sin(a.dance * C.VICTORY_HOP_FREQ)) * C.VICTORY_HOP;
    if (robot) this.robotAnim(robot, p, a, air, walking, dancing, emote, dt);
    const stretch = a.vz > C.ANIM_AIR_VZ ? C.ANIM_STRETCH : 0; // 올라가는 중: 위로 늘어나고 옆은 가늘게
    const wide = 1 - stretch / 2 + a.land * C.ANIM_LAND_SQUASH * 0.6; // 착지: 납작해지며 옆으로 퍼짐
    rig.scale.set(wide, wide, 1 + stretch - a.land * C.ANIM_LAND_SQUASH);
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
    if (g.userData.robot) return; // 로봇은 모델 동작으로 (robotAnim)
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

  updateBombs(bombs) {
    while (this.bombMeshes.length < bombs.length) {
      // 재질을 복사해 폭탄마다 따로 깜빡이게
      const m = itemModel(this.models, 'bomb', C.BOMB_MODEL_SIZE, true) || new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), new THREE.MeshLambertMaterial({ color: 0x222222 }));
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
      g.visible = p.alive && !(p.id === myId && view === 'fps' && this.skyBlend === 0 && !cam.victory && !cam.selfie);
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
      const opacity = p.ghostLeft > 0 ? 0.35 + 0.1 * Math.sin(performance.now() / 120) : 1;
      for (const m of g.userData.mats) {
        m.transparent = opacity < 1;
        m.opacity = opacity;
      }
      if (p.jumpLeft > 0 && !p.stunned) bodyMat.emissive.setHex(0x1a5a1a);
      g.userData.hammer.visible = p.weaponUses > 0;
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
      label.sprite.visible = p.alive;
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
        sm.material = mine ? this.previewMat : this.shadowMat;
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
    this.updateBeams(state);
    if (me) this.viewArm.material.color.setHex(playerColor(me, state));
    const vp = this.effects.punchAmount(myId);
    this.viewArm.position.set(this.viewArmBase.x - 0.12 * vp, this.viewArmBase.y + 0.08 * vp, this.viewArmBase.z - 0.3 * vp);
    this.viewArm.visible = !!(me && me.alive) && this.skyBlend === 0 && !cam.victory && !cam.selfie;
    this.viewHammer.visible = !!(me && me.weaponUses > 0);
    // 손에 든 것: 고른 핫바 칸에 뭐가 있으면 그 색 상자 (망치가 있으면 망치가 우선)
    const kind = me ? heldKind(me) : null;
    for (const [k, o] of Object.entries(this.viewHeld)) o.visible = k === kind && !this.viewHammer.visible; // 망치가 있으면 망치가 우선
    this.effects.update(dt, this.skyBlend >= 1 ? this.skyCamera : this.camera);
    this.pieceMat.opacity = this.skyBlend > 0.5 ? 0.55 : 1; // 하늘 시점에선 블록 너머로 착지 미리보기가 보이게
    this.controlledMat.opacity = this.pieceMat.opacity;
    this.thrownMat.opacity = this.pieceMat.opacity;
    this.thrownMat.emissive.setHex(Math.floor(performance.now() / C.THROWN_BLINK_MS) % 2 ? 0x806000 : 0x000000);
    for (const m of Object.values(this.shapeMats)) m.opacity = this.pieceMat.opacity;

    // 1인칭(또는 관전) 자세
    const eye = new THREE.Vector3();
    const look = new THREE.Vector3();
    if (me && me.alive) {
      const s = this.smooth.get(me.id);
      eye.set(s.x, s.y, s.z + C.EYE_HEIGHT);
      const cp = Math.cos(cam.pitch);
      look.set(eye.x + cp * Math.cos(cam.yaw), eye.y + cp * Math.sin(cam.yaw), eye.z + Math.sin(cam.pitch));
    } else if (cam.follow !== null && cam.follow !== undefined && this.smooth.has(cam.follow)) {
      // 관전: 따라가는 사람 뒤 위에서 (그 사람이 보는 방향으로). 방향은 부드럽게 따라 돎
      const s = this.smooth.get(cam.follow);
      const target = state.players.find((p) => p.id === cam.follow);
      const want = target ? target.yaw : 0;
      if (this.followId !== cam.follow) {
        this.followId = cam.follow;
        this.followYaw = want;
      }
      const d = Math.atan2(Math.sin(want - this.followYaw), Math.cos(want - this.followYaw));
      this.followYaw += d * (1 - Math.exp(-C.SPECTATE_TURN * dt));
      eye.set(s.x - Math.cos(this.followYaw) * C.SPECTATE_BACK, s.y - Math.sin(this.followYaw) * C.SPECTATE_BACK, s.z + C.SPECTATE_UP);
      look.set(s.x, s.y, s.z + C.PLAYER_HEIGHT * 0.6);
    } else {
      // 죽었거나 아직 없음: 필드 밖 관전 시점 (마우스로 돌릴 수 있음)
      this.followId = null;
      eye.set(C.GRID_W / 2 - Math.cos(cam.yaw) * 10, C.GRID_D / 2 - Math.sin(cam.yaw) * 10, 7);
      look.set(C.GRID_W / 2, C.GRID_D / 2, 2);
    }
    this.victoryCamera(state, cam, dt, eye, look);

    const b = this.skyBlend;
    const skyUp = new THREE.Vector3(Math.cos(this.skyYaw), Math.sin(this.skyYaw), 0);
    if (b >= 1) {
      this.skyCamera.up.copy(skyUp);
      this.skyCamera.lookAt(C.GRID_W / 2, C.GRID_D / 2, 0);
      this.renderer.render(this.scene, this.skyCamera);
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
      this.renderer.render(this.scene, this.camera);
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
    this.renderer.render(this.scene, this.camera);
  }

  // view 목표로 skyBlend 를 SKY_TRANSITION_MS 동안 옮긴다. 0 = 1인칭, 1 = 하늘 시점
  stepView(view, dt) {
    const target = view === 'sky' ? 1 : 0;
    const step = (dt * 1000) / C.SKY_TRANSITION_MS;
    if (this.skyBlend < target) this.skyBlend = Math.min(target, this.skyBlend + step);
    else if (this.skyBlend > target) this.skyBlend = Math.max(target, this.skyBlend - step);
  }
}
