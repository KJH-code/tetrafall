// 타이틀 화면 3D (지오메트리 대시 엔딩 아트처럼): 테마 무대 (title-world.js, 켤 때마다 무작위) 가운데에 테트리미노 블록이 떨어져 쌓이며 로고
// (shared/title.js 계산). 캄캄하게 시작 → 장면 빛이 천천히 → 블록이 닿을 때마다 번쩍 → 다 쌓이면 빛 터짐 (블룸·불티·렌즈 플레어) → 빛 띠·반짝임.
// 누르면 카메라가 앞으로 빠져나가며 하얗게 (title.js 가 하얀 막을 씌우고 메뉴 섬으로 바꿈). 메뉴 장면과 따로 그림 (자기 THREE.Scene·카메라·블룸)
import * as THREE from 'three';
import { EffectComposer } from 'three/addons/postprocessing/EffectComposer.js';
import { RenderPass } from 'three/addons/postprocessing/RenderPass.js';
import { UnrealBloomPass } from 'three/addons/postprocessing/UnrealBloomPass.js';
import { OutputPass } from 'three/addons/postprocessing/OutputPass.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { CONFIG as C } from '/shared/config.js';
import { titleCells, titlePieces, dropSchedule, titleDoneAt, pieceLift, titleInterval, titleCamDist, titleLight, titleExit, landedBetween } from '/shared/title.js';
import { TitleStage, glowSprite, glowTex } from '/title-world.js';

export class TitleScene {
  // r: Renderer (WebGLRenderer·블록 텍스처를 빌림). theme: config TITLE_THEMES 키. instant: 떨어짐 없이 완성 로고 (움직임 줄이기). low: 그래픽 낮춤 (블룸·반사 끔)
  constructor(r, theme, { instant = false, low = false } = {}) {
    this.r = r;
    this.theme = theme;
    this.T = C.TITLE_THEMES[theme];
    this.low = low;
    this.t = 0; // 로고 시계 (ms)
    this.fast = false; // 누름 → 빨리 감기
    this.exitT = null; // 빠져나가기 시작 뒤 ms (null = 아직)
    this.instant = instant;
    this.on = { land: () => {}, burst: () => {}, exit: () => {} }; // 소리 훅 (title.js)
    const { cells, width, height } = titleCells(C.TITLE_TEXT, C.TITLE_GAP, C.TITLE_BOLD);
    this.pieces = titlePieces(cells);
    this.start = dropSchedule(this.pieces, titleInterval(this.pieces.length));
    this.doneAt = instant ? 0 : titleDoneAt(this.start);
    if (instant) this.t = C.TITLE_DARK_MS + C.TITLE_BURST_MS; // 완성·다 밝은 모습
    this.burstFired = instant;
    this.size = [width, height];
    const s = C.TITLE_SCALE;
    const logoW = width * s;
    const logoH = height * s;
    this.camera = new THREE.PerspectiveCamera(C.TITLE_FOV, window.innerWidth / window.innerHeight, 0.1, 400);
    this.camera.up.set(0, 0, 1);
    this.dist = titleCamDist(logoW, C.TITLE_FOV, this.camera.aspect);
    this.stage = new TitleStage(theme, { low, logoW, logoH, camDist: this.dist });
    const scene = (this.scene = this.stage.scene);

    // 글자 블록: 모서리 깎은 매끈한 블록 + 테마 글자 색 (조각마다 차례로), 스스로 빛남 (테마 빛 색) + 닿을 때 번쩍 + 지나가는 빛 띠
    const n = cells.length;
    this.flash = new Float32Array(n); // 블록마다 번쩍 (0~1, 줄어듦)
    const geo = new RoundedBoxGeometry(1, 1, 1, 1, C.TITLE_BEVEL);
    this.flashAttr = new THREE.InstancedBufferAttribute(this.flash, 1);
    geo.setAttribute('aFlash', this.flashAttr);
    const mat = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 0.28, metalness: 0.45 });
    this.u = { uGlow: { value: 0 }, uGlowCol: { value: new THREE.Color(this.T.glow) }, uSweepX: { value: -1e4 }, uSweepW: { value: C.TITLE_SWEEP_W } };
    mat.onBeforeCompile = (sh) => {
      Object.assign(sh.uniforms, this.u);
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nattribute float aFlash;\nvarying float vFlash;\nvarying float vWX;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\nvFlash = aFlash;\nvWX = (modelMatrix * instanceMatrix * vec4(position, 1.0)).x;');
      sh.fragmentShader = sh.fragmentShader
        .replace('#include <common>', '#include <common>\nuniform float uGlow, uSweepX, uSweepW;\nuniform vec3 uGlowCol;\nvarying float vFlash;\nvarying float vWX;')
        .replace(
          '#include <emissivemap_fragment>',
          `#include <emissivemap_fragment>
          float sw = exp(-pow((vWX - uSweepX) / uSweepW, 2.0));
          totalEmissiveRadiance += mix(diffuseColor.rgb, uGlowCol, 0.4) * uGlow + vec3(1.0) * (vFlash * 1.6 + sw * 0.55 * uGlow);`,
        );
    };
    mat.customProgramCacheKey = () => 'tf-title-letter';
    this.mesh = new THREE.InstancedMesh(geo, mat, n);
    this.mesh.frustumCulled = false;
    // 빛 테두리: 뒤집은 껍데기 (테마 테두리 색, 글자 빛 따라 밝아짐)
    this.edgeCol = new THREE.Color(this.T.edge);
    this.shell = new THREE.InstancedMesh(geo, new THREE.MeshBasicMaterial({ color: 0x000000, side: THREE.BackSide, fog: false }), n);
    this.shell.frustumCulled = false;
    let i = 0;
    this.slots = []; // 인스턴스 → [조각 번호, 칸]
    this.pieces.forEach((p, pi) => {
      const col = new THREE.Color(this.T.letter[pi % this.T.letter.length]);
      for (const c of p.cells) {
        this.mesh.setColorAt(i, col);
        this.slots.push([pi, c]);
        i++;
      }
    });
    this.byPiece = this.pieces.map(() => []);
    this.slots.forEach(([pi], k) => this.byPiece[pi].push(k));
    scene.add(this.mesh, this.shell);

    // 빛 터짐: 로고 뒤 큰 빛 + 가로 줄기 (렌즈 플레어 줄기) + 불티
    this.halo = glowSprite(this.T.glow, logoW * 1.5, logoH * 4.5, 0);
    this.halo.position.set(0, 3, 0);
    this.streak = glowSprite(this.T.flare, logoW * 2.4, 1.6, 0);
    this.streak.position.set(0, -1, 0);
    scene.add(this.halo, this.streak);
    this.sparks = this.makeSparks(C.TITLE_SPARKS[low ? 1 : 0]);
    scene.add(this.sparks.points);
    // 렌즈 플레어: 로고 왼쪽 위 빛 → 화면 가운데를 지나 반대쪽으로 늘어선 동그라미들 (화면에 맞춰 매 프레임 자리)
    this.flareSrc = new THREE.Vector3(-logoW * 0.4, 8, logoH * 1.9);
    this.flares = low
      ? []
      : [
          [0, 1.4, 0.6],
          [0.35, 0.5, 0.25],
          [0.6, 0.3, 0.35],
          [0.85, 0.9, 0.15],
          [1.25, 0.4, 0.25],
          [1.6, 1.4, 0.12],
        ].map(([f, sz, a]) => {
          const sp = glowSprite(this.T.flare, sz, sz, 0);
          sp.material.depthTest = false;
          sp.renderOrder = 10;
          sp.userData = { f, sz, a };
          scene.add(sp);
          return sp;
        });

    // 블룸 (그래픽 낮춤이면 없이 바로 그림)
    if (!low) {
      const w = window.innerWidth;
      const h = window.innerHeight;
      this.composer = new EffectComposer(r.renderer);
      this.composer.addPass(new RenderPass(scene, this.camera));
      const [str, rad, thr] = C.TITLE_BLOOM;
      this.bloom = new UnrealBloomPass(new THREE.Vector2(w, h), str, rad, thr);
      this.composer.addPass(this.bloom);
      this.composer.addPass(new OutputPass());
      this.sizeKey = '';
    }
    this.place();
  }

  // 불티: 빛 터질 때 글자 자리에서 사방으로 튐 (CPU 로 움직임, 수 적음)
  makeSparks(n) {
    const pos = new Float32Array(n * 3);
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    const m = new THREE.PointsMaterial({ color: new THREE.Color(this.T.edge).multiplyScalar(1.6), size: 0.35, map: glowTex(), transparent: true, opacity: 0, depthWrite: false, blending: THREE.AdditiveBlending, fog: false });
    const points = new THREE.Points(g, m);
    points.frustumCulled = false;
    return { points, vel: new Float32Array(n * 3), n, age: Infinity };
  }

  fireSparks() {
    const { points, vel, n } = this.sparks;
    const p = points.geometry.attributes.position;
    const s = C.TITLE_SCALE;
    const [w, h] = this.size;
    for (let i = 0; i < n; i++) {
      const [, c] = this.slots[Math.floor(Math.random() * this.slots.length)];
      p.setXYZ(i, (c.x - w / 2 + 0.5) * s, -0.4, (c.y - h / 2 + 0.5) * s);
      const a = Math.random() * Math.PI * 2;
      const sp = 3 + Math.random() * 9;
      vel[i * 3] = Math.cos(a) * sp;
      vel[i * 3 + 1] = -Math.random() * 4;
      vel[i * 3 + 2] = Math.sin(a) * sp * 0.7 + 3;
    }
    p.needsUpdate = true;
    this.sparks.age = 0;
  }

  stepSparks(dt) {
    const S = this.sparks;
    if (S.age === Infinity) return;
    S.age += dt;
    const p = S.points.geometry.attributes.position;
    for (let i = 0; i < S.n; i++) {
      S.vel[i * 3 + 2] -= 6 * dt;
      for (let k = 0; k < 3; k++) S.vel[i * 3 + k] *= 1 - 1.4 * dt;
      p.setXYZ(i, p.getX(i) + S.vel[i * 3] * dt, p.getY(i) + S.vel[i * 3 + 1] * dt, p.getZ(i) + S.vel[i * 3 + 2] * dt);
    }
    p.needsUpdate = true;
    S.points.material.opacity = Math.max(0, 1 - S.age / 1.6);
    if (S.age > 1.6) S.age = Infinity;
  }

  // 블록 자리 (지금 시계로)
  place() {
    const s = C.TITLE_SCALE;
    const [w, h] = this.size;
    const m = new THREE.Matrix4();
    const pos = new THREE.Vector3();
    const q = new THREE.Quaternion();
    const zero = new THREE.Vector3(0, 0, 0);
    const one = new THREE.Vector3(s * 0.97, s * 0.97, s * 0.97);
    const big = new THREE.Vector3(s * (1 + C.TITLE_OUTLINE), s * (1 + C.TITLE_OUTLINE), s * (1 + C.TITLE_OUTLINE));
    this.slots.forEach(([pi, c], i) => {
      const lift = this.instant ? 0 : pieceLift(this.t, this.start[pi]);
      pos.set((c.x - w / 2 + 0.5) * s, 0, (c.y - h / 2 + 0.5 + (lift || 0)) * s);
      m.compose(pos, q, lift === null ? zero : one);
      this.mesh.setMatrixAt(i, m);
      m.compose(pos, q, lift === null ? zero : big);
      this.shell.setMatrixAt(i, m);
    });
    this.mesh.instanceMatrix.needsUpdate = true;
    this.shell.instanceMatrix.needsUpdate = true;
  }

  get done() {
    return this.t >= this.doneAt;
  }

  // 'Enter' 안내를 보일 때 (빛 터진 뒤 조금)
  get ready() {
    return this.instant || this.t >= this.doneAt + C.TITLE_HINT_DELAY_MS;
  }

  // 누름: 다 안 쌓였으면 빨리 감은 뒤, 다 쌓였으면 바로 빠져나가기
  press() {
    this.fast = true;
  }

  // 빠져나가기 진행 (shared/title.js titleExit): title.js 가 하얀 막·메뉴로 바꾸기에 씀
  get exit() {
    return this.exitT === null ? null : titleExit(this.exitT);
  }

  // 한 프레임
  step(dt) {
    const ms = dt * 1000;
    const t0 = this.t;
    if (!this.done) this.t = Math.min(this.doneAt, this.t + ms * (this.fast ? C.TITLE_FAST : 1));
    else {
      this.t += ms;
      if (this.fast && this.exitT === null) {
        this.exitT = 0;
        this.on.exit();
      }
    }
    if (this.exitT !== null) this.exitT += ms;
    // 닿은 조각: 그 블록 번쩍 + 소리
    if (!this.instant) {
      const landed = landedBetween(this.start, t0, Math.min(this.t, this.doneAt));
      for (const pi of landed) for (const k of this.byPiece[pi]) this.flash[k] = 1;
      if (landed.length) this.on.land(landed.length);
    }
    if (!this.burstFired && this.t >= this.doneAt) {
      this.burstFired = true;
      this.fireSparks();
      this.on.burst();
    }
    // 반짝임: 다 쌓인 뒤 아무 블록이나 가끔 번쩍
    if (this.t > this.doneAt + C.TITLE_BURST_MS * 0.5) {
      const want = C.TITLE_TWINKLE * (this.slots.length / 100) * dt;
      for (let k = 0; k < 4; k++) if (Math.random() < want / 4) this.flash[Math.floor(Math.random() * this.flash.length)] = 0.7;
    }
    const fall = Math.exp(-dt * 1000 / C.TITLE_LAND_FLASH_MS * 3);
    for (let k = 0; k < this.flash.length; k++) this.flash[k] *= fall;
    this.flashAttr.needsUpdate = true;
    this.place();
    this.stepSparks(dt);

    const L = titleLight(this.t, this.doneAt);
    const ex = this.exit;
    const push = ex && !this.instant ? ex.push : 0; // 움직임 줄이기면 카메라는 그대로, 하얗게만
    const wh = ex ? ex.white : 0; // 하얗게 되는 동안 빛도 같이 세짐
    this.u.uGlow.value = L.glow * (1 + wh * 2);
    const sweepU = this.t - this.doneAt - C.TITLE_BURST_MS * 0.7; // 빛 터짐이 가라앉은 뒤부터
    const sweepP = (((sweepU % C.TITLE_SWEEP_MS) + C.TITLE_SWEEP_MS) % C.TITLE_SWEEP_MS) / C.TITLE_SWEEP_MS;
    const lw = this.size[0] * C.TITLE_SCALE;
    this.u.uSweepX.value = sweepU < 0 ? -1e4 : -lw * 0.8 + sweepP * lw * 2.4;
    this.shell.material.color.copy(this.edgeCol).multiplyScalar(Math.min(3, 0.3 + L.glow * 1.6));
    this.halo.material.opacity = Math.min(1, L.burst * 0.18 + (this.t >= this.doneAt ? 0.04 : 0) + wh * 0.5);
    this.halo.scale.set(this.size[0] * C.TITLE_SCALE * (1.15 + L.burst * 0.3), this.size[1] * C.TITLE_SCALE * (1.8 + L.burst * 1.4), 1);
    this.streak.material.opacity = Math.min(1, L.burst * 0.8 + (this.t >= this.doneAt ? 0.15 : 0));
    this.stage.update(this.t / 1000, Math.min(1, L.lit + L.burst * 0.5), window.innerHeight * 0.5 * this.r.renderer.getPixelRatio());

    // 카메라: 로고를 살짝 아래·옆에서, 천천히 흔들리며 다가감. 터질 때 작게 흔들림. 빠져나가면 앞으로 (로고 위로) 확
    const cam = this.camera;
    const aspect = window.innerWidth / window.innerHeight;
    if (cam.aspect !== aspect) {
      cam.aspect = aspect;
      cam.updateProjectionMatrix();
      this.dist = titleCamDist(lw, C.TITLE_FOV, aspect);
    }
    const ts = this.t / 1000;
    const build = Math.min(1, this.t / Math.max(1, this.doneAt + C.TITLE_BURST_MS));
    const d = this.dist * (1 + C.TITLE_CAM_PUSH * (1 - build));
    const sway = Math.sin(ts * 0.5) * C.TITLE_CAM_SWAY;
    const shake = L.burst * L.burst * 0.25;
    // 빠져나가기: 로고 위로 솟으며 앞으로 날아가 (로고가 발 밑으로 지나감) 장면 안쪽 (동굴 깊은 곳·먼 산) 을 바라봄
    const [fwd, up, ahead] = C.TITLE_EXIT_FLY;
    const ey = -d + push * d * (1 - fwd);
    const ez = C.TITLE_CAM_UP + Math.sin(ts * 0.37) * 0.4 + push * up;
    cam.position.set((C.TITLE_CAM_SIDE + sway) * (1 - push) + (Math.random() - 0.5) * shake, ey, ez + (Math.random() - 0.5) * shake);
    cam.lookAt(0, push * d * ahead, push * up * 0.55);
    const fov = C.TITLE_FOV + push * 18;
    if (cam.fov !== fov) {
      cam.fov = fov;
      cam.updateProjectionMatrix();
    }
    cam.updateMatrixWorld();
    this.placeFlares(L.burst, this.t >= this.doneAt);
    if (this.bloom) this.bloom.strength = C.TITLE_BLOOM[0] + (C.TITLE_BLOOM_BURST - C.TITLE_BLOOM[0]) * Math.max(L.burst, wh);
  }

  // 렌즈 플레어: 빛 자리를 화면에 비춰, 화면 가운데를 지나 반대쪽으로 동그라미 (카메라 앞 일정 거리에 놓음)
  placeFlares(burst, lit) {
    if (!this.flares.length) return;
    const cam = this.camera;
    const sp = this.flareSrc.clone().project(cam);
    const on = Math.min(1, burst * 1.3 + (lit ? 0.25 : 0));
    const v = new THREE.Vector3();
    const depth = 6;
    const hh = Math.tan(((cam.fov * Math.PI) / 180) / 2) * depth;
    for (const f of this.flares) {
      const { f: k, sz, a } = f.userData;
      v.set(sp.x * (1 - 2 * k), sp.y * (1 - 2 * k), 0.5).unproject(cam).sub(cam.position).normalize();
      f.position.copy(cam.position).addScaledVector(v, depth);
      const s = (sz * hh) / 8;
      f.scale.set(s, s, 1);
      f.material.opacity = on * a;
    }
  }

  // 그리기: 블룸이면 composer, 아니면 바로
  draw() {
    const R = this.r.renderer;
    if (!this.composer) return R.render(this.scene, this.camera);
    const sz = R.getSize(new THREE.Vector2());
    const key = `${sz.x}x${sz.y}x${R.getPixelRatio()}`;
    if (key !== this.sizeKey) {
      this.sizeKey = key;
      this.composer.setPixelRatio(R.getPixelRatio());
      this.composer.setSize(sz.x, sz.y);
    }
    this.composer.render();
  }

  dispose() {
    this.scene.remove(this.mesh, this.shell);
    this.mesh.geometry.dispose();
    this.mesh.material.dispose();
    this.shell.material.dispose();
    this.mesh.dispose();
    this.shell.dispose();
    this.stage.dispose();
    if (this.composer) {
      this.bloom.dispose();
      this.composer.dispose();
    }
  }
}
