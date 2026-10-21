// three.js 렌더링. 단색 블록, 최소한의 비주얼. 좌표계는 게임과 같은 z-up.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { buildCharacter } from '/character.js';
import { Effects } from '/effects.js';

THREE.Object3D.DEFAULT_UP.set(0, 0, 1);

// P1~P8 색. 블록(파랑 계열)·떨어지는 블록(주황)과 헷갈리지 않는 색 위주
// 아이템 모양·색: 멀리서도 종류를 구분하게
const ITEM_LOOK = {
  control: { color: 0x20e0e0, geo: () => new THREE.OctahedronGeometry(0.3) }, // 하늘색 팔면체
  knockback: { color: 0xe02020, geo: () => new THREE.SphereGeometry(0.24, 14, 10) }, // 빨간 공
  weapon: { color: 0xff8a10, geo: () => new THREE.BoxGeometry(0.42, 0.24, 0.24) }, // 주황 망치 머리
  jump: { color: 0x40e040, geo: () => new THREE.ConeGeometry(0.24, 0.45, 12) }, // 초록 원뿔(위로)
  ghost: { color: 0xe8e8ff, geo: () => new THREE.TorusGeometry(0.2, 0.07, 8, 18) }, // 흰 고리
  brick: { color: 0xf0d060, geo: () => new THREE.BoxGeometry(0.32, 0.32, 0.32) }, // 노란 작은 블록
  bomb: { color: 0x222222, geo: () => new THREE.SphereGeometry(0.22, 14, 10) }, // 검은 공
};

// 고른 핫바 칸에 든 것: 'block' | 'brick' | 'ball'(투사체) | 'bomb' | null
export function heldKind(p) {
  if (p.hand === 1) return p.blocks > 0 ? 'block' : null;
  if (p.hand === 2) return p.bricks > 0 ? 'brick' : p.ammo > 0 ? 'ball' : null;
  return p.bombs > 0 ? 'bomb' : null;
}
const HELD_COLOR = { block: 0x6f8fc8, brick: ITEM_LOOK.brick.color, ball: ITEM_LOOK.knockback.color, bomb: 0x222222 };

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

export const PLAYER_COLORS = [0xe05050, 0x50c050, 0xb060e0, 0xe0c050, 0xf0f0f0, 0x40d0c0, 0xff80b0, 0x8a5a30];
const MAX_CELLS = C.GRID_W * C.GRID_D * C.GRID_H;

export class Renderer {
  constructor(canvasParent) {
    this.renderer = new THREE.WebGLRenderer({ antialias: true });
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2));
    this.renderer.setSize(window.innerWidth, window.innerHeight);
    canvasParent.appendChild(this.renderer.domElement);
    this.canvas = this.renderer.domElement;

    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(0x87a8c8);
    this.scene.fog = new THREE.Fog(0x87a8c8, 30, 80);

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
    this.viewHammer = new THREE.Mesh(new THREE.BoxGeometry(0.15, 0.12, 0.12), new THREE.MeshLambertMaterial({ color: 0xff8a10 }));
    this.viewHammer.position.set(0, -0.24, 0); // 캡슐 먼 끝 (x축 +90도 회전이라 로컬 -y 가 화면 안쪽)
    this.viewHammer.visible = false;
    this.viewArm.add(this.viewHammer);
    // 1인칭 손에 든 설치 블록 (설치 블록 있을 때만)
    this.viewBrick = new THREE.Mesh(new THREE.BoxGeometry(0.13, 0.13, 0.13), new THREE.MeshLambertMaterial({ color: ITEM_LOOK.brick.color }));
    this.viewBrick.position.set(0, -0.24, 0);
    this.viewBrick.visible = false;
    this.viewArm.add(this.viewBrick);
    // 하늘 시점: 필드가 화면에 꽉 차는 직교 카메라 (블록과 그림자가 같은 크기로 보인다)
    this.skyCamera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 100);
    this.skyCamera.up.set(0, 1, 0);
    this.skyCamera.position.set(C.GRID_W / 2, C.GRID_D / 2, C.SKY_CAMERA_HEIGHT);
    this.skyCamera.lookAt(C.GRID_W / 2, C.GRID_D / 2, 0);
    this.fitSkyCamera();

    const hemi = new THREE.HemisphereLight(0xffffff, 0x556677, 0.9);
    this.scene.add(hemi);
    const sun = new THREE.DirectionalLight(0xffffff, 1.0);
    sun.position.set(4, -6, 12);
    this.scene.add(sun);

    // 바닥
    const floor = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W, C.GRID_D, 0.3),
      new THREE.MeshLambertMaterial({ color: 0x777777 }),
    );
    floor.position.set(C.GRID_W / 2, C.GRID_D / 2, -0.15);
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
    this.scene.add(this.blockMesh);
    this.gridVersion = -1;

    // 떨어지는 블록 셀 + 그림자 (블록 여러 개 → 필요한 만큼 늘어나는 풀)
    this.pieceMeshes = [];
    this.shadowMeshes = [];
    this.pieceMat = new THREE.MeshLambertMaterial({ color: 0xf0a030, transparent: true, opacity: 1 }); // 자동 블록
    this.controlledMat = new THREE.MeshLambertMaterial({ color: 0xd040d0, transparent: true, opacity: 1 }); // 누가 조종 중인 블록
    this.thrownMat = new THREE.MeshLambertMaterial({ color: 0xf0d060, transparent: true, opacity: 1 }); // 던진 설치 블록
    this.shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45 });
    this.pieceBox = new THREE.BoxGeometry(1, 1, 1);
    this.shadowBox = new THREE.BoxGeometry(0.96, 0.96, 0.06);

    // 용암: 필드보다 넓은 판. 표면 높이 = state.lava.z
    this.lavaBottom = -6;
    this.lava = new THREE.Mesh(
      new THREE.BoxGeometry(C.GRID_W + 12, C.GRID_D + 12, 1),
      new THREE.MeshBasicMaterial({ color: 0xff5010, transparent: true, opacity: 0.85 }),
    );
    this.lava.visible = false;
    this.scene.add(this.lava);

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
          // 단색이되 인접 셀이 구분되게 체커보드로 살짝 명암만 준다
          color.setHex((x + y + z) % 2 ? 0x6a8fc8 : 0x5c7fb5);
          this.blockMesh.setColorAt(n, color);
          n++;
        }
      }
    }
    this.blockMesh.count = n;
    this.blockMesh.instanceMatrix.needsUpdate = true;
    if (this.blockMesh.instanceColor) this.blockMesh.instanceColor.needsUpdate = true;
  }

  getPlayerMesh(p) {
    let g = this.playerMeshes.get(p.id);
    if (!g) {
      const color = PLAYER_COLORS[p.slot % PLAYER_COLORS.length];
      const ch = buildCharacter(color);
      g = ch.group;
      g.userData.bodyMat = ch.bodyMaterial;
      g.userData.arms = ch.arms;
      g.userData.hammer = ch.hammer;
      g.userData.held = ch.held;
      g.userData.waitMark = ch.waitMark;
      g.userData.color = color;
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
      const base = aim.kind === 'build' ? 0xffffff : aim.kind === 'brick' ? 0xf0d060 : 0xff5030;
      const color = aim.ok ? base : 0xff2020;
      this.aimMat.color.setHex(color);
      this.aimEdgeMat.color.setHex(color);
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
      const m = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.05, 1, 8, 1, true), this.beamMat);
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
    this.beamMat.opacity = 0.35 + 0.2 * Math.sin(performance.now() / 150);
  }

  updateBombs(bombs) {
    while (this.bombMeshes.length < bombs.length) {
      const m = new THREE.Mesh(new THREE.SphereGeometry(0.3, 16, 12), new THREE.MeshLambertMaterial({ color: 0x222222, emissive: 0x000000 }));
      this.scene.add(m);
      this.bombMeshes.push(m);
    }
    this.bombMeshes.forEach((m, i) => {
      const b = bombs[i];
      m.visible = !!b;
      if (!b) return;
      m.position.set(b.x + 0.5, b.y + 0.5, b.z + 0.3);
      const period = 80 + Math.min(1, b.left / C.BOMB_FUSE_MS) * 320; // 남은 시간이 짧을수록 빨리
      const on = Math.floor(performance.now() / period) % 2 === 0;
      m.material.emissive.setHex(on ? 0xff2000 : 0x000000);
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
      g.visible = p.alive && !(p.id === myId && view === 'fps' && this.skyBlend === 0);
      const bodyMat = g.userData.bodyMat;
      // 경직 중엔 흰색으로 빠르게 깜빡임
      const blinkOn = p.stunned && Math.floor(performance.now() / 70) % 2 === 0;
      bodyMat.color.setHex(blinkOn ? 0xffffff : g.userData.color);
      bodyMat.emissive.setHex(p.stunned ? 0x664400 : p.hasControl ? 0x005566 : 0x000000);
      const skyMarks = this.skyBlend > 0.5;
      g.userData.arrow.visible = skyMarks;
      g.userData.arrow.material.color.setHex(p.id === myId ? 0xffffff : g.userData.color);
      g.userData.ring.visible = skyMarks && p.id === myId;
      // 맞으면 찌그러졌다 펴짐
      // 유령화: 반투명, 점프력 상승: 초록 빛, 망치: 오른팔에 망치 머리
      bodyMat.transparent = true;
      bodyMat.opacity = p.ghostLeft > 0 ? 0.35 + 0.1 * Math.sin(performance.now() / 120) : 1;
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
      // 이름 + 피해 % 표시: 바뀔 때만 다시 그림
      const label = g.userData.label;
      const dmg = p.damage || 0;
      const name = p.nick || p.name;
      const key = `${name}|${dmg}`;
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
      pm.material = piece.thrown ? this.thrownMat : piece.controller !== null ? this.controlledMat : this.pieceMat;
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
    if (this.lava.visible) {
      const h = Math.max(0.01, lava.z - this.lavaBottom);
      this.lava.scale.z = h;
      this.lava.position.set(C.GRID_W / 2, C.GRID_D / 2, this.lavaBottom + h / 2);
    }

    // 아이템
    while (this.itemMeshes.length < state.items.length) {
      const m = new THREE.Mesh(ITEM_LOOK.control.geo(), new THREE.MeshLambertMaterial({ color: 0xffffff, emissive: 0x222222 }));
      m.userData.type = 'control';
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
      const look = ITEM_LOOK[it.type] || ITEM_LOOK.control;
      if (m.userData.type !== it.type) {
        m.geometry.dispose();
        m.geometry = look.geo();
        m.userData.type = it.type;
      }
      m.visible = true;
      m.position.set(it.x + 0.5, it.y + 0.5, it.z + 0.45 + Math.sin(performance.now() / 300 + i) * 0.06);
      m.rotation.z += dt * 2;
      m.material.color.setHex(look.color);
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
    if (me) this.viewArm.material.color.setHex(PLAYER_COLORS[me.slot % PLAYER_COLORS.length]);
    const vp = this.effects.punchAmount(myId);
    this.viewArm.position.set(this.viewArmBase.x - 0.12 * vp, this.viewArmBase.y + 0.08 * vp, this.viewArmBase.z - 0.3 * vp);
    this.viewArm.visible = !!(me && me.alive) && this.skyBlend === 0;
    this.viewHammer.visible = !!(me && me.weaponUses > 0);
    // 손에 든 것: 고른 핫바 칸에 뭐가 있으면 그 색 상자 (망치가 있으면 망치가 우선)
    const held = me && heldKind(me) ? HELD_COLOR[heldKind(me)] : null;
    this.viewBrick.visible = held !== null && !this.viewHammer.visible;
    if (held !== null) this.viewBrick.material.color.setHex(held);
    this.effects.update(dt, this.skyBlend >= 1 ? this.skyCamera : this.camera);
    this.pieceMat.opacity = this.skyBlend > 0.5 ? 0.55 : 1; // 하늘 시점에선 블록 너머로 착지 미리보기가 보이게
    this.controlledMat.opacity = this.pieceMat.opacity;
    this.thrownMat.opacity = this.pieceMat.opacity;

    // 1인칭(또는 관전) 자세
    const eye = new THREE.Vector3();
    const look = new THREE.Vector3();
    if (me && me.alive) {
      const s = this.smooth.get(me.id);
      eye.set(s.x, s.y, s.z + C.EYE_HEIGHT);
      const cp = Math.cos(cam.pitch);
      look.set(eye.x + cp * Math.cos(cam.yaw), eye.y + cp * Math.sin(cam.yaw), eye.z + Math.sin(cam.pitch));
    } else {
      // 죽었거나 아직 없음: 필드 밖 관전 시점 (마우스로 돌릴 수 있음)
      eye.set(C.GRID_W / 2 - Math.cos(cam.yaw) * 10, C.GRID_D / 2 - Math.sin(cam.yaw) * 10, 7);
      look.set(C.GRID_W / 2, C.GRID_D / 2, 2);
    }

    const b = this.skyBlend;
    if (b >= 1) {
      this.renderer.render(this.scene, this.skyCamera);
      return;
    }
    if (b <= 0) {
      this.camera.fov = 75;
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
    this.camera.fov = 75 + (skyFov - 75) * t;
    this.camera.updateProjectionMatrix();
    this.camera.position.lerpVectors(eye, top, t);
    this.camera.up.set(0, t, 1 - t).normalize();
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
