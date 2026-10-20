// three.js 렌더링. 단색 블록, 최소한의 비주얼. 좌표계는 게임과 같은 z-up.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

THREE.Object3D.DEFAULT_UP.set(0, 0, 1);

const PLAYER_COLORS = [0xe05050, 0x50c050, 0x5080e0, 0xe0c050];
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
    // 최대 432개 한 번의 draw call 이라 시야 판정을 끈다.
    this.blockMesh.frustumCulled = false;
    this.scene.add(this.blockMesh);
    this.gridVersion = -1;

    // 떨어지는 블록 셀 4개 + 그림자 4개
    this.pieceMeshes = [];
    this.shadowMeshes = [];
    const pieceMat = new THREE.MeshLambertMaterial({ color: 0xf0a030, transparent: true, opacity: 1 });
    this.pieceMat = pieceMat;
    const shadowMat = new THREE.MeshBasicMaterial({ color: 0x000000, transparent: true, opacity: 0.45 });
    this.shadowMat = shadowMat;
    for (let i = 0; i < 4; i++) {
      const m = new THREE.Mesh(new THREE.BoxGeometry(1, 1, 1), pieceMat);
      m.visible = false;
      this.scene.add(m);
      this.pieceMeshes.push(m);
      const s = new THREE.Mesh(new THREE.BoxGeometry(0.96, 0.96, 0.06), shadowMat);
      s.visible = false;
      this.scene.add(s);
      this.shadowMeshes.push(s);
    }
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
      g = new THREE.Group();
      const body = new THREE.Mesh(
        new THREE.BoxGeometry(C.PLAYER_HALF * 2, C.PLAYER_HALF * 2, C.PLAYER_HEIGHT),
        new THREE.MeshLambertMaterial({ color: PLAYER_COLORS[p.slot % PLAYER_COLORS.length] }),
      );
      body.position.z = C.PLAYER_HEIGHT / 2;
      g.add(body);
      const nose = new THREE.Mesh(
        new THREE.BoxGeometry(0.25, 0.15, 0.15),
        new THREE.MeshLambertMaterial({ color: 0x222222 }),
      );
      nose.position.set(C.PLAYER_HALF + 0.1, 0, C.EYE_HEIGHT);
      g.add(nose);
      g.userData.body = body;
      g.userData.color = PLAYER_COLORS[p.slot % PLAYER_COLORS.length];
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
      const body = g.userData.body;
      // 경직 중엔 흰색으로 빠르게 깜빡임
      const blinkOn = p.stunned && Math.floor(performance.now() / 70) % 2 === 0;
      body.material.color.setHex(blinkOn ? 0xffffff : g.userData.color);
      body.material.emissive.setHex(p.stunned ? 0x664400 : p.hasControl ? 0x005566 : 0x000000);
      const skyMarks = this.skyBlend > 0.5;
      g.userData.arrow.visible = skyMarks;
      g.userData.arrow.material.color.setHex(p.id === myId ? 0xffffff : g.userData.color);
      g.userData.ring.visible = skyMarks && p.id === myId;
    }
    for (const [id, g] of this.playerMeshes) {
      if (!seen.has(id)) {
        this.scene.remove(g);
        this.playerMeshes.delete(id);
        this.smooth.delete(id);
      }
    }

    // 블록 + 그림자
    const piece = state.piece;
    for (let i = 0; i < 4; i++) {
      const pm = this.pieceMeshes[i];
      const sm = this.shadowMeshes[i];
      if (!piece) {
        pm.visible = false;
        sm.visible = false;
        continue;
      }
      const [x, y, z] = piece.cells[i];
      pm.position.set(x + 0.5, y + 0.5, z + 0.5);
      pm.visible = true;
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

    // 아이템
    while (this.itemMeshes.length < state.items.length) {
      const m = new THREE.Mesh(new THREE.OctahedronGeometry(0.3), new THREE.MeshLambertMaterial({ color: 0xffffff }));
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
      m.visible = true;
      m.position.set(it.x + 0.5, it.y + 0.5, it.z + 0.45);
      m.rotation.z += dt * 2;
      m.material.color.setHex(it.type === 'control' ? 0x20e0e0 : 0xe02020);
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
    this.pieceMat.opacity = this.skyBlend > 0.5 ? 0.55 : 1; // 하늘 시점에선 블록 너머로 착지 미리보기가 보이게

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
