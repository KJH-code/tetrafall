// 대기실 큰 3D 캐릭터 (캐릭터 고르기): 내 캐릭터를 내 색으로 크게, 천천히 돌고, 고르면 정면에서 전용 도발 한 번.
// 게임 장면과 따로: 초상(portrait.js)과 같은 렌더러로 그려 자기 2D 캔버스에 옮김 (WebGL 문맥을 새로 안 만들어 셰이더를 다시 안 만듦 — 대기실 첫 진입 멈춤).
// main.js 가 대기실 판이 떠 있을 때만 draw() 를 부르고, 판이 시작하면 release() 로 몸을 놓는다.
// 래그돌 없이 figureAnim 만. 방향·도발 시간은 shared/char-select.js
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { buildCharacter } from '/character.js';
import { figureAnim } from '/figure.js';
import { stageYaw, tauntAt } from '/shared/char-select.js';
import { sharedGL } from '/portrait.js';

export class CharStage {
  // box: 캔버스를 넣을 칸
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
    this.ctx = this.canvas.getContext('2d');
    this.gl = sharedGL();
    if (this.scene) return; // 장면·빛·카메라는 한 번만
    this.scene = new THREE.Scene();
    this.scene.add(new THREE.AmbientLight(0xffffff, 1.05));
    const key = new THREE.DirectionalLight(0xffffff, 1.5);
    key.position.set(3, -2, 4);
    this.scene.add(key);
    this.rim = new THREE.DirectionalLight(0x99bbff, 0.9); // 테두리 빛: 대기실 장면 테마 빛 색 (tint)
    this.rim.position.set(-3, 2, 1);
    this.scene.add(this.rim);
    this.theme = null;
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

  // 테두리 빛을 테마 빛 색으로 (theme = config TITLE_THEMES 키 = body data-theme, 없으면 예전 하늘색)
  tint(theme) {
    if (!this.gl || theme === this.theme) return;
    this.theme = theme;
    const T = C.TITLE_THEMES[theme];
    this.rim.color.setHex(T ? T.edge : 0x99bbff);
    this.rim.intensity = T ? 1.3 : 0.9;
  }

  draw(now = performance.now()) {
    if (!this.gl || !this.ch) return;
    const w = this.canvas.clientWidth;
    const h = this.canvas.clientHeight;
    if (!w || !h) return;
    const dpr = Math.min(2, window.devicePixelRatio || 1);
    const W = Math.round(w * dpr);
    const H = Math.round(h * dpr);
    if (this.canvas.width !== W || this.canvas.height !== H) {
      this.canvas.width = W;
      this.canvas.height = H;
      this.camera.aspect = w / h;
      this.camera.updateProjectionMatrix();
    }
    // 같이 쓰는 렌더러라 매번 크기를 맞춤 (초상이 그 사이에 바꿨을 수 있음)
    this.gl.setPixelRatio(1);
    this.gl.setSize(W, H, false);
    const dt = Math.min(0.1, this.last ? (now - this.last) / 1000 : 0);
    this.last = now;
    const age = now - this.pickedAt;
    this.turn.rotation.z = stageYaw(age / 1000);
    if (this.ch.figure) {
      const tz = tauntAt(age);
      figureAnim(this.ch.figure, { air: false, walking: false, hs: 0, walk: 0, t: now / 1000, flip: -1, emote: tz.on ? C.EMOTE_CHAR : -1, emoteT: tz.t, punch: 0, dizzy: 0, whirl: -1, sniffAt: null }, dt);
    }
    this.gl.render(this.scene, this.camera);
    this.ctx.clearRect(0, 0, W, H);
    this.ctx.drawImage(this.gl.domElement, 0, 0);
  }

  // 판이 시작하면: 몸을 놓아 판 중엔 아무것도 안 돎 (대기실로 오면 set 이 다시 만듦). 렌더러는 초상과 같이 쓰므로 그대로 둠
  release() {
    if (!this.gl) return;
    if (this.ch) this.turn.remove(this.ch.group);
    this.ch = null;
    this.key = '';
    this.gl = null;
    this.canvas.remove();
    this.canvas = null;
    this.ctx = null;
  }

  get active() {
    return !!this.gl;
  }
}
