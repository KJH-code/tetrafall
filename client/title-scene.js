// 타이틀 화면 3D: 메뉴 섬 위 먼 하늘에 테트리미노 블록이 떨어져 쌓이며 로고 (shared/title.js 계산), 누르면 카메라가 메뉴 섬 자리로 확 내려옴.
// Renderer 가 메뉴 장면(menu-scene.js)과 같이 그림 (render.js: this.title). 블록 텍스처·색은 게임 블록 그대로
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { titleCells, titlePieces, dropSchedule, titleDoneAt, pieceLift } from '/shared/title.js';
import { toon, noOutline } from '/toon.js';

const ease = (k) => (k < 0 ? 0 : k > 1 ? 1 : k * k * (3 - 2 * k));

export class TitleScene {
  // r: Renderer. yaw: 메뉴 카메라 방향 (로고는 그 앞 하늘에, 내려오면 그대로 메뉴 카메라로). instant: 떨어짐 없이 완성 로고 (그래픽 낮춤·움직임 줄이기)
  constructor(r, yaw, instant = false) {
    this.r = r;
    this.t = 0; // 로고 시계 (ms)
    this.fast = false; // 누름 → 빨리 감기
    this.zoomT = null; // 내려오기 시작 뒤 ms (null = 아직)
    this.instant = instant;
    const { cells, width, height } = titleCells(C.TITLE_TEXT);
    this.pieces = titlePieces(cells);
    this.start = dropSchedule(this.pieces);
    this.doneAt = instant ? 0 : titleDoneAt(this.start);
    this.size = [width, height];
    // 로고 자리: 섬 가운데에서 카메라가 보는 쪽으로 TITLE_AHEAD 칸, 위로 TITLE_HEIGHT 칸. 글자는 카메라 오른쪽으로 늘어섬
    const d = new THREE.Vector3(Math.cos(yaw), Math.sin(yaw), 0);
    this.dir = d;
    this.right = new THREE.Vector3(d.y, -d.x, 0);
    this.center = new THREE.Vector3(r.W / 2, r.D / 2, 0).addScaledVector(d, C.TITLE_AHEAD).add(new THREE.Vector3(0, 0, C.TITLE_HEIGHT));
    const n = cells.length;
    const mat = noOutline(toon({ color: 0xffffff, map: r.tex.tetris, emissive: 0x202030 }));
    this.mesh = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), mat, n);
    this.mesh.frustumCulled = false;
    const col = new THREE.Color();
    let i = 0;
    this.slots = []; // 인스턴스 → [조각 번호, 칸]
    this.pieces.forEach((p, pi) => {
      for (const c of p.cells) {
        col.set(C.SHAPE_COLORS[p.shape]);
        this.mesh.setColorAt(i, col);
        this.slots.push([pi, c]);
        i++;
      }
    });
    this.rot = new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), Math.atan2(this.right.y, this.right.x));
    r.scene.add(this.mesh);
    this.place();
  }

  // 블록 자리 (지금 시계로)
  place() {
    const s = C.TITLE_SCALE;
    const [w, h] = this.size;
    const m = new THREE.Matrix4();
    const pos = new THREE.Vector3();
    const zero = new THREE.Vector3(0, 0, 0);
    const one = new THREE.Vector3(s * 0.97, s * 0.97, s * 0.97);
    this.slots.forEach(([pi, c], i) => {
      const lift = this.instant ? 0 : pieceLift(this.t, this.start[pi]);
      pos.copy(this.center).addScaledVector(this.right, (c.x - w / 2 + 0.5) * s);
      pos.z += (c.y - h / 2 + 0.5 + (lift || 0)) * s;
      m.compose(pos, this.rot, lift === null ? zero : one);
      this.mesh.setMatrixAt(i, m);
    });
    this.mesh.instanceMatrix.needsUpdate = true;
  }

  get done() {
    return this.t >= this.doneAt;
  }

  // 누름: 다 안 쌓였으면 빨리 감은 뒤, 다 쌓였으면 바로 내려오기
  press() {
    this.fast = true;
  }

  // 한 프레임. 돌려주는 값: { pose: { eye, look }, shift: 화면 밀기 비율 (0 → 메뉴 값), k: 내려온 정도 0~1 }
  step(dt, menuPose) {
    const ms = dt * 1000;
    if (!this.done) this.t = Math.min(this.doneAt, this.t + ms * (this.fast ? C.TITLE_FAST : 1));
    else if (this.fast && this.zoomT === null) this.zoomT = 0;
    if (this.zoomT !== null) this.zoomT += ms;
    this.place();
    // 로고를 살짝 아래·옆에서 (정면이면 블록이 납작한 그림처럼 보임) + 천천히 흔들려 입체가 보이게
    const sway = Math.sin(this.t / 1000 * 0.7) * C.TITLE_CAM_SWAY;
    const titleEye = this.center.clone().addScaledVector(this.dir, -C.TITLE_CAM_DIST).addScaledVector(this.right, C.TITLE_CAM_SIDE + sway).add(new THREE.Vector3(0, 0, C.TITLE_CAM_UP));
    const k = this.zoomT === null ? 0 : ease(this.zoomT / C.TITLE_ZOOM_MS);
    // 내려오기: 처음엔 천천히 뒤로 빠졌다가 섬 쪽으로 확 (k 를 한 번 더 굽힘)
    const kk = k * k;
    const eye = titleEye.clone().lerp(menuPose.eye, kk);
    const look = this.center.clone().lerp(menuPose.look, Math.min(1, k * 1.4));
    return { pose: { eye, look }, shift: C.MENU_VIEW_SHIFT * kk, k };
  }

  dispose() {
    this.r.scene.remove(this.mesh);
    this.mesh.geometry.dispose();
    this.mesh.material.dispose();
    this.mesh.dispose();
  }
}
