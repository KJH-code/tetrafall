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
};

const PLAYER_COLORS = [0xe05050, 0x50c050, 0xb060e0, 0xe0c050, 0xf0f0f0, 0x40d0c0, 0xff80b0, 0x8a5a30];
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
      g.userData.arrow = arrow;
      g.userData.ring = ring;
      this.scene.add(g);
      this.playerMeshes.set(p.id, g);
    }
    return g;
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
      const sq = this.effects.squashAmount(p.id);
      g.scale.set(1 + 0.28 * sq, 1 + 0.28 * sq, 1 - 0.32 * sq);
      // 밀치기: 오른팔을 앞으로 뻗음
      const pu = this.effects.punchAmount(p.id);
      const arm = g.userData.arms[0];
      // 옆으로 뻗은 오른팔(-y 쪽)을 z축으로 돌려 앞(+x)을 향하게
      arm.position.x = arm.userData.base.x + 0.3 * pu;
      arm.position.z = arm.userData.base.z + 0.2 * pu;
      arm.rotation.z = (Math.PI / 2) * pu;
    }
    for (const [id, g] of this.playerMeshes) {
      if (!seen.has(id)) {
        this.scene.remove(g);
        this.playerMeshes.delete(id);
        this.smooth.delete(id);
      }
    }

    // 블록 + 그림자 (여러 개)
    const pieces = state.pieces || [];
    const need = pieces.length * 4;
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
      const piece = pieces[Math.floor(k / 4)];
      if (!piece) {
        pm.visible = false;
        sm.visible = false;
        continue;
      }
      const i = k % 4;
      const [x, y, z] = piece.cells[i];
      pm.position.set(x + 0.5, y + 0.5, z + 0.5);
      pm.visible = true;
      pm.material = piece.controller !== null ? this.controlledMat : this.pieceMat;
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
    if (me) this.viewArm.material.color.setHex(PLAYER_COLORS[me.slot % PLAYER_COLORS.length]);
    const vp = this.effects.punchAmount(myId);
    this.viewArm.position.set(this.viewArmBase.x - 0.12 * vp, this.viewArmBase.y + 0.08 * vp, this.viewArmBase.z - 0.3 * vp);
    this.viewArm.visible = !!(me && me.alive) && this.skyBlend === 0;
    this.viewHammer.visible = !!(me && me.weaponUses > 0);
    this.effects.update(dt, this.skyBlend >= 1 ? this.skyCamera : this.camera);
    this.pieceMat.opacity = this.skyBlend > 0.5 ? 0.55 : 1; // 하늘 시점에선 블록 너머로 착지 미리보기가 보이게
    this.controlledMat.opacity = this.pieceMat.opacity;

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
