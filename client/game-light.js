// 판(실제 게임)에 타이틀의 '빛 언어' 를 섞기 (2026-10-30 재혁: 판은 밝기 유지 — 블록·상대·가장자리 판단이 먼저).
// 값은 config GAME_LIGHT (고른 안) · GAME_LIGHT_PRESETS. 그래픽 낮춤이면 꺼짐 (지금 모습 그대로)
// - 색 보정: 게임 캔버스에 CSS filter (채도·대비·밝기) — 화면 합성 단계라 그리기 수 0
// - 가장자리 어둠 (비네트): 캔버스 바로 위 div 의 방사 그라데이션, 가운데 필드는 그대로
// - 빛 무리·빛 터짐: 화면을 보는 가산 혼합 사각형 InstancedMesh 하나 (그리기 1번). 떨어지는 블록·아이템 둘레 빛 무리, 착지·KO·필살기 때 짧은 빛
// - 하늘·안개: 판 중에만 조금 어둡고 진하게 (sky) → 밝은 필드가 타이틀처럼 어둠 속에서 떠 보임. 필드 조명은 그대로
// - 블록 빛 테두리 (프레넬) 는 piece-look.js material 의 rim (render.js 가 이 값으로 재질을 만듦)
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const VERT = /* glsl */ `
attribute vec3 iColor;
attribute float iAlpha;
varying vec3 vC;
varying float vA;
varying vec2 vUv;
void main() {
  vec4 c = modelViewMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0);
  float s = length(instanceMatrix[0].xyz);
  c.xy += position.xy * s;
  gl_Position = projectionMatrix * c;
  vUv = uv; vC = iColor; vA = iAlpha;
}`;
const FRAG = /* glsl */ `
varying vec3 vC;
varying float vA;
varying vec2 vUv;
void main() {
  float d = length(vUv - 0.5) * 2.0;
  float a = pow(max(0.0, 1.0 - d), 2.2) * vA;
  if (a < 0.003) discard;
  gl_FragColor = vec4(vC, a);
}`;

export class GameLight {
  constructor(r) {
    this.r = r;
    this.low = false;
    this.cap = C.GAME_LIGHT_MAX;
    const geo = new THREE.PlaneGeometry(1, 1);
    this.col = new THREE.InstancedBufferAttribute(new Float32Array(this.cap * 3), 3);
    this.alpha = new THREE.InstancedBufferAttribute(new Float32Array(this.cap), 1);
    geo.setAttribute('iColor', this.col);
    geo.setAttribute('iAlpha', this.alpha);
    const mat = new THREE.ShaderMaterial({ vertexShader: VERT, fragmentShader: FRAG, transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, side: THREE.DoubleSide, fog: false });
    mat.userData.outlineParameters = { visible: false };
    this.mesh = new THREE.InstancedMesh(geo, mat, this.cap);
    this.mesh.frustumCulled = false;
    this.mesh.count = 0;
    this.mesh.renderOrder = 5;
    r.scene.add(this.mesh);
    this.flashes = []; // { x, y, z, color, size, until, ms }
    this.n = 0;
    this.m = new THREE.Matrix4();
    this.c = new THREE.Color();
    // 비네트: 캔버스 바로 다음 (HUD 아래)
    const cv = r.renderer.domElement;
    this.vig = document.createElement('div');
    this.vig.id = 'game-vignette';
    Object.assign(this.vig.style, { position: 'fixed', inset: '0', pointerEvents: 'none', display: 'none' });
    cv.parentNode?.insertBefore(this.vig, cv.nextSibling);
    this.setPreset(C.GAME_LIGHT);
  }

  // 안 고르기 ('off' · 'rim' · 'glow' · 'vivid' — config GAME_LIGHT_PRESETS). 확인용 __tf.renderer.setGameLight
  setPreset(name) {
    this.name = C.GAME_LIGHT_PRESETS[name] ? name : 'off';
    this.p = C.GAME_LIGHT_PRESETS[this.name];
    const v = this.p.vignette;
    this.vig.style.background = v[0] > 0 ? `radial-gradient(ellipse at center, rgba(0,0,0,0) ${v[1] * 100}%, rgba(${v[2]},${v[0]}) 100%)` : 'none';
  }

  // world.apply 끝: 하늘·안개 원래 색을 기억 (판 중에만 바꾸고 대기실·메뉴는 그대로)
  themeApplied() {
    const r = this.r;
    const u = r.dome.material.uniforms;
    this.skyBase = { top: u.top.value.clone(), mid: u.mid.value.clone(), horizon: u.horizon.value.clone(), below: u.below.value.clone(), bg: r.scene.background.clone(), fog: r.scene.fog.color.clone() };
    this.skyK = -1; // 다음 프레임에 다시 칠함
  }

  // 하늘·안개 어둡게 k (0 = 그대로 ~ 1 = 안의 sky 값만큼)
  paintSky(k) {
    if (!this.skyBase || Math.abs(k - this.skyK) < 0.002) return;
    this.skyK = k;
    const r = this.r;
    const u = r.dome.material.uniforms;
    const [dim, sat] = this.p.sky;
    const f = (src, dst) => dst.copy(src).multiplyScalar(1 - (1 - dim) * k).offsetHSL(0, sat * k, 0);
    for (const key of ['top', 'mid', 'horizon', 'below']) f(this.skyBase[key], u[key].value);
    f(this.skyBase.bg, r.scene.background);
    f(this.skyBase.fog, r.scene.fog.color);
  }

  // 지금 쓰는 값 (그래픽 낮춤이면 끔)
  get on() {
    return !this.low && this.name !== 'off';
  }

  get rim() {
    return this.on ? this.p.rim : 0;
  }

  setLow(on) {
    this.low = !!on;
  }

  // 짧은 빛 (착지·KO·필살기). size 칸, ms 동안 커지며 사라짐
  flash(x, y, z, color, size, ms) {
    if (!this.on || !this.p.flash) return;
    if (this.flashes.length >= C.GAME_LIGHT_FLASH_MAX) this.flashes.shift();
    this.flashes.push({ x, y, z, color, size: size * this.p.flash, ms, t0: performance.now() });
  }

  add(x, y, z, color, size, a) {
    if (this.n >= this.cap || a <= 0) return;
    this.m.makeScale(size, size, size).setPosition(x, y, z);
    this.mesh.setMatrixAt(this.n, this.m);
    this.c.set(color);
    this.col.setXYZ(this.n, this.c.r, this.c.g, this.c.b);
    this.alpha.setX(this.n, a);
    this.n++;
  }

  // 매 프레임 (render.js): active = 판 중 (대기실·메뉴는 끔). halos = [[x, y, z, color, 크기 배수]]
  frame(active, halos, dt = 1 / 60) {
    const on = active && this.on;
    const cv = this.r.renderer.domElement;
    const g = this.p.grade;
    const filter = on && (g[0] !== 1 || g[1] !== 1 || g[2] !== 1) ? `saturate(${g[0]}) contrast(${g[1]}) brightness(${g[2]})` : '';
    if (cv.style.filter !== filter) cv.style.filter = filter;
    this.vig.style.display = on && this.p.vignette[0] > 0 ? 'block' : 'none';
    // 하늘: 판이 시작하면 천천히 어둡게, 끝나면 돌아옴
    this.skyT = Math.max(0, Math.min(1, (this.skyT || 0) + (on ? 1 : -1) * C.GAME_LIGHT_SKY_SPEED * Math.min(dt || 0, 0.1)));
    this.paintSky(this.p.sky ? this.skyT : 0);
    this.n = 0;
    if (on) {
      const p = this.p;
      if (p.halo[0] > 0) for (const [x, y, z, color, k] of halos) this.add(x, y, z, color, p.halo[1] * (k || 1), p.halo[0]);
      const now = performance.now();
      this.flashes = this.flashes.filter((f) => now - f.t0 < f.ms);
      for (const f of this.flashes) {
        const k = (now - f.t0) / f.ms;
        this.add(f.x, f.y, f.z, f.color, f.size * (0.6 + 0.6 * k), (1 - k) * (1 - k));
      }
    } else this.flashes.length = 0;
    this.mesh.count = this.n;
    this.mesh.visible = this.n > 0;
    this.mesh.instanceMatrix.needsUpdate = true;
    this.col.needsUpdate = true;
    this.alpha.needsUpdate = true;
  }
}
