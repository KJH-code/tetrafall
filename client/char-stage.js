// 대기실 큰 3D 캐릭터 (캐릭터 고르기): 내 캐릭터를 내 색으로 크게, 천천히 돌고, 고르면 정면에서 전용 도발 한 번.
// 게임 장면과 따로 (자기 캔버스·렌더러). main.js 가 대기실 판이 떠 있을 때만 draw() 를 부르고, 판이 시작하면 release() 로 렌더러를 놓는다.
// 래그돌 없이 figureAnim 만. 방향·도발 시간은 shared/char-select.js
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { buildCharacter } from '/character.js';
import { figureAnim } from '/figure.js';
import { stageYaw, tauntAt } from '/shared/char-select.js';

export class CharStage {
  // box: 캔버스를 넣을 칸 (캔버스는 init 때 새로 — 놓은 렌더러의 캔버스는 다시 못 씀)
  constructor(box, models = null) {
    this.box = box;
    this.canvas = null;
    this.models = models;
    this.gl = null;
    this.key = ''; // `${char}|${color}`
    this.ch = null;
    this.pickedAt = -Infinity; // 고른 시각 (도발·정면 기준)
    this.last = 0;
  }

  init() {
    if (this.gl) return;
    this.canvas = document.createElement('canvas');
    this.box.prepend(this.canvas);
    this.gl = new THREE.WebGLRenderer({ canvas: this.canvas, alpha: true, antialias: true });
    this.gl.setClearColor(0x000000, 0);
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.AmbientLight(0xffffff, 1.05));
    const key = new THREE.DirectionalLight(0xffffff, 1.5);
    key.position.set(3, -2, 4);
    this.scene.add(key);
    const rim = new THREE.DirectionalLight(0x99bbff, 0.9);
    rim.position.set(-3, 2, 1);
    this.scene.add(rim);
    this.camera = new THREE.PerspectiveCamera(26, 1, 0.05, 60);
    this.camera.up.set(0, 0, 1); // 게임과 같은 z-up
    this.turn = new THREE.Group(); // 도는 받침
    this.scene.add(this.turn);
  }

  // 캐릭터·색이 바뀌면 몸을 새로 만듦. taunt: 고른 순간이면 도발 (처음 들어올 땐 안 함)
  set(char, color, taunt) {
    const key = `${char}|${color}`;
    if (key === this.key) return;
    this.init();
    if (this.ch) this.turn.remove(this.ch.group);
    this.ch = buildCharacter(color, this.models, char);
    this.turn.add(this.ch.group);
    // 몸 크기에 맞춰 카메라 (portrait.js 전신과 같은 방식, 정면에서)
    this.ch.group.updateMatrixWorld(true);
    const box = new THREE.Box3().setFromObject(this.ch.rig);
    const top = Number.isFinite(box.max.z) ? box.max.z : C.PLAYER_HEIGHT;
    const bot = Number.isFinite(box.min.z) ? box.min.z : 0;
    const half = ((top - bot) / 2) * 1.18;
    const dist = half / Math.tan((this.camera.fov / 2) * (Math.PI / 180));
    const at = new THREE.Vector3(0, 0, (top + bot) / 2);
    this.camera.position.set(dist, 0, at.z + half * 0.12); // +x 가 몸 앞 → 정면
    this.camera.lookAt(at);
    if (taunt && this.key) this.pickedAt = performance.now();
    else if (!this.key) this.pickedAt = performance.now() - C.EMOTE_MS; // 처음: 도발 없이 바로 돌기 시작
    this.key = key;
  }

  draw(now = performance.now()) {
    if (!this.gl || !this.ch) return;
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    if (!w || !h) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    if (this.canvas.width !== Math.round(w * dpr) || this.canvas.height !== Math.round(h * dpr)) {
      this.gl.setPixelRatio(dpr);
      this.gl.setSize(w, h, false);
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    }
    const dt = Math.min(0.1, this.last ? (now - this.last) / 1000 : 0);
    this.last = now;
    const age = now - this.pickedAt;
    this.turn.rotation.z = stageYaw(age / 1000);
    if (this.ch.figure) {
      const tz = tauntAt(age);
      figureAnim(this.ch.figure, { air: false, walking: false, hs: 0, walk: 0, t: now / 1000, flip: -1, emote: tz.on ? C.EMOTE_CHAR : -1, emoteT: tz.t, punch: 0, dizzy: 0, whirl: -1, sniffAt: null }, dt);
    }
    this.gl.render(this.scene, this.camera);
  }

  // 판이 시작하면: 렌더러를 놓아 판 중엔 아무것도 안 돎 (대기실로 오면 set 이 다시 만듦)
  release() {
    if (!this.gl) return;
    if (this.ch) this.turn.remove(this.ch.group);
    this.ch = null;
    this.key = '';
    this.gl.dispose();
    this.gl.forceContextLoss();
    this.gl = null;
    this.canvas.remove();
    this.canvas = null;
  }

  get active() {
    return !!this.gl;
  }
}
