// 타이틀 전용 어두운 '엔딩 아트' 장면 (지오메트리 대시 엔딩처럼): 테마마다 밤·빛·안개 무대 (config TITLE_THEMES).
// 로고 (title-scene.js) 는 원점, 글자는 x 로 늘어서고 z 가 위, 카메라는 -y 쪽에서 봄. 판 맵·메뉴 섬과 무관한 별도 THREE.Scene.
// 무대마다 소품 (수정 동굴 = 천장·바닥 자수정 무리, 화산 = 용암 균열·먼 화산, 사막 = 별·달·피라미드, 버섯 = 빛 버섯 숲,
// 하늘 성 = 밤 구름 바다 위 성, 성채 = 횃불 성벽, 초원 = 반딧불·나무 그림자) + 떠다니는 빛 가루 + (보통 그래픽이면) 아래 거울 바닥
import * as THREE from 'three';
import { Reflector } from 'three/addons/objects/Reflector.js';
import { CONFIG as C } from '/shared/config.js';

// 0~1 결정적 난수 (테마마다 같은 장면)
function rng(seed) {
  let s = seed >>> 0 || 1;
  return () => {
    s = (s + 0x6d2b79f5) >>> 0;
    let t = s;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

// 부드러운 빛 점 텍스처 (가운데 하얗고 가장자리 투명)
let glowTexture = null;
export function glowTex() {
  if (glowTexture) return glowTexture;
  const c = document.createElement('canvas');
  c.width = c.height = 128;
  const g = c.getContext('2d');
  const gr = g.createRadialGradient(64, 64, 0, 64, 64, 64);
  gr.addColorStop(0, 'rgba(255,255,255,1)');
  gr.addColorStop(0.18, 'rgba(255,255,255,0.75)');
  gr.addColorStop(0.45, 'rgba(255,255,255,0.18)');
  gr.addColorStop(1, 'rgba(255,255,255,0)');
  g.fillStyle = gr;
  g.fillRect(0, 0, 128, 128);
  glowTexture = new THREE.CanvasTexture(c);
  return glowTexture;
}

// 빛 번짐 스프라이트 (더하기 섞기)
export function glowSprite(color, w, h = w, opacity = 1) {
  const s = new THREE.Sprite(new THREE.SpriteMaterial({ map: glowTex(), color, transparent: true, opacity, blending: THREE.AdditiveBlending, depthWrite: false, fog: false }));
  s.scale.set(w, h, 1);
  return s;
}

// 떠다니는 빛 가루 (셰이더에서 움직임): 칸마다 천천히 흔들리고 rise 만큼 위로 올라가 맨 위에서 아래로. blink 면 반딧불처럼 켜졌다 꺼짐
function motes(n, color, size, rise, box, rnd, blink = 0) {
  const pos = new Float32Array(n * 3);
  const ph = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    pos[i * 3] = box[0] + rnd() * (box[1] - box[0]);
    pos[i * 3 + 1] = box[2] + rnd() * (box[3] - box[2]);
    pos[i * 3 + 2] = box[4] + rnd() * (box[5] - box[4]);
    ph[i] = rnd();
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  g.setAttribute('aPh', new THREE.BufferAttribute(ph, 1));
  const m = new THREE.ShaderMaterial({
    uniforms: {
      uTime: { value: 0 },
      uColor: { value: new THREE.Color(color) },
      uSize: { value: size },
      uScale: { value: 400 },
      uLit: { value: 1 },
      uRise: { value: rise },
      uZ: { value: new THREE.Vector2(box[4], box[5]) },
      uBlink: { value: blink },
    },
    vertexShader: /* glsl */ `
      attribute float aPh;
      uniform float uTime, uSize, uScale, uRise, uBlink;
      uniform vec2 uZ;
      varying float vA;
      void main() {
        vec3 p = position;
        float t = uTime;
        p.x += sin(t * 0.45 + aPh * 37.0) * 0.9;
        p.y += cos(t * 0.38 + aPh * 21.0) * 0.9;
        float h = uZ.y - uZ.x;
        p.z = uZ.x + mod(p.z - uZ.x + t * uRise * (0.6 + aPh) + sin(t * 0.8 + aPh * 13.0) * 0.4, h);
        vec4 mv = modelViewMatrix * vec4(p, 1.0);
        gl_Position = projectionMatrix * mv;
        float tw = 0.55 + 0.45 * sin(t * (1.5 + aPh * 2.5) + aPh * 40.0);
        if (uBlink > 0.0) tw = pow(max(0.0, sin(t * (0.7 + aPh * 0.9) + aPh * 30.0)), 3.0);
        float edge = smoothstep(0.0, 1.2, p.z - uZ.x) * smoothstep(0.0, 1.2, uZ.y - p.z);
        vA = tw * edge;
        gl_PointSize = uSize * uScale / -mv.z * (0.6 + 0.8 * aPh);
      }`,
    fragmentShader: /* glsl */ `
      uniform vec3 uColor;
      uniform float uLit;
      varying float vA;
      void main() {
        float d = length(gl_PointCoord - 0.5) * 2.0;
        float a = smoothstep(1.0, 0.0, d);
        a = a * a;
        gl_FragColor = vec4(uColor * (1.0 + 1.5 * a), a * vA * uLit);
      }`,
    transparent: true,
    depthWrite: false,
    blending: THREE.AdditiveBlending,
  });
  const pts = new THREE.Points(g, m);
  pts.frustumCulled = false;
  return pts;
}

// 하늘 별 (위쪽 반구)
function stars(n, rnd, r = 150) {
  const pos = new Float32Array(n * 3);
  for (let i = 0; i < n; i++) {
    const a = rnd() * Math.PI * 2;
    const e = 0.05 + rnd() * 1.4;
    pos[i * 3] = Math.cos(a) * Math.cos(e) * r;
    pos[i * 3 + 1] = Math.abs(Math.sin(a)) * Math.cos(e) * r + 20;
    pos[i * 3 + 2] = Math.sin(e) * r * 0.8 - 10;
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
  return new THREE.Points(g, new THREE.PointsMaterial({ color: 0xffffff, size: 0.7, map: glowTex(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
}

// 울퉁불퉁한 판 (바위 천장·바닥·벽): 크기 w×h, 높낮이 amp, 면 각지게
function rockPlane(w, h, seg, amp, color, rnd, emissive = 0x000000) {
  const g = new THREE.PlaneGeometry(w, h, seg, Math.max(2, Math.round((seg * h) / w)));
  const p = g.attributes.position;
  for (let i = 0; i < p.count; i++) p.setZ(i, (rnd() - 0.5) * amp + Math.sin(p.getX(i) * 0.15) * amp * 0.4);
  g.computeVertexNormals();
  return new THREE.Mesh(g, new THREE.MeshStandardMaterial({ color, emissive, roughness: 0.95, metalness: 0, flatShading: true }));
}

// 인스턴스 모음: geo 하나를 [{ p, s, r, c }] 자리마다 (위치·크기 Vector3·돌림 Euler·색)
function instanced(geo, mat, list) {
  const m = new THREE.InstancedMesh(geo, mat, Math.max(1, list.length));
  const mx = new THREE.Matrix4();
  const q = new THREE.Quaternion();
  list.forEach((it, i) => {
    q.setFromEuler(it.r || new THREE.Euler());
    mx.compose(it.p, q, it.s);
    m.setMatrixAt(i, mx);
    if (it.c !== undefined) m.setColorAt(i, new THREE.Color(it.c));
  });
  m.count = list.length;
  return m;
}

// 수정 결정 무리 (늘인 팔면체 여러 개): at 자리, dir = 1 위로 / -1 아래로 (천장), size 크기, colors 색들
function crystalCluster(list, at, dir, size, colors, rnd) {
  const n = 3 + Math.floor(rnd() * 5);
  for (let i = 0; i < n; i++) {
    const h = size * (0.6 + rnd() * 1.0) * (i === 0 ? 1.5 : 1);
    const r = h * (0.18 + rnd() * 0.1);
    const tilt = i === 0 ? 0 : 0.25 + rnd() * 0.6;
    const a = rnd() * Math.PI * 2;
    const p = at.clone().add(new THREE.Vector3(Math.cos(a) * size * 0.3 * (i ? 1 : 0), Math.sin(a) * size * 0.3 * (i ? 1 : 0), dir * h * 0.35));
    const e = new THREE.Euler(Math.cos(a) * tilt * dir, Math.sin(a) * tilt * dir, rnd() * Math.PI);
    list.push({ p, s: new THREE.Vector3(r, r, h), r: e, c: colors[Math.floor(rnd() * colors.length)] });
  }
}

// 무대: theme = config TITLE_THEMES 키. low = 그래픽 낮춤 (반사 바닥·빛 줄임). logoW·logoH = 로고 크기 (게임 칸), camDist = 카메라 거리
export class TitleStage {
  constructor(theme, { low = false, logoW = 50, logoH = 7, camDist = 40 } = {}) {
    this.id = C.TITLE_THEMES[theme] ? theme : Object.keys(C.TITLE_THEMES)[0];
    const T = (this.T = C.TITLE_THEMES[this.id]);
    this.low = low;
    this.scene = new THREE.Scene();
    this.scene.background = new THREE.Color(T.bg);
    this.scene.fog = new THREE.Fog(T.fog[0], camDist + T.fog[1], camDist + T.fog[2]);
    this.floorZ = -logoH / 2 - C.TITLE_FLOOR_GAP;
    this.logoW = logoW;
    this.lights = []; // [빛, 원래 세기] — 장면 밝기 lit 를 곱함
    this.updaters = []; // (t, lit) => {} 매 프레임
    this.disposables = [];
    const rnd = rng([...this.id].reduce((a, ch) => a * 31 + ch.charCodeAt(0), 7));
    this.rnd = rnd;
    const amb = new THREE.HemisphereLight(T.amb[0], T.bg, T.amb[1]);
    this.light(amb, T.amb[1]);
    const key = new THREE.PointLight(T.key[0], T.key[1] * C.TITLE_LIGHT[0], 0, 1.4);
    key.position.set(-logoW * 0.25, -camDist * 0.55, 10);
    this.light(key, key.intensity);
    const back = new THREE.PointLight(T.back[0], T.back[1] * C.TITLE_LIGHT[1], 0, 1.3);
    back.position.set(0, 9, 3);
    this.light(back, back.intensity);
    this.backLight = back;
    this.floor(T);
    this[this.id]?.(T, rnd);
    const n = Math.round(T.motes[1] * (low ? C.WORLD_LOW_DETAIL : 1));
    const box = this.moteBox || [-logoW * 0.9, logoW * 0.9, -camDist * 0.6, 40, this.floorZ, this.floorZ + 18];
    this.dust = motes(n, T.motes[0], T.motes[2], T.motes[3], box, rnd, this.id === 'meadow' ? 1 : 0);
    this.scene.add(this.dust);
  }

  light(l, base) {
    this.lights.push([l, base]);
    this.scene.add(l);
    return l;
  }

  add(...o) {
    this.scene.add(...o);
    return o[0];
  }

  // 바닥: 보통이면 거울 (Reflector, 테마 바닥 색으로 흐리게) + 그 위 반투명 바닥 판. 거울 없는 테마 (mirror: false) 는 테마가 바닥을 만듦
  floor(T) {
    if (T.mirror === false) return;
    const size = 400;
    if (!this.low) {
      const tint = new THREE.Color(T.floor).lerp(new THREE.Color(0xffffff), C.TITLE_REFLECT);
      const w = window.innerWidth;
      const h = window.innerHeight;
      const mirror = new Reflector(new THREE.PlaneGeometry(size, size), { color: tint, textureWidth: Math.round(w * 0.5), textureHeight: Math.round(h * 0.5), clipBias: 0.003 });
      mirror.position.z = this.floorZ - 0.02;
      this.add(mirror);
      this.mirror = mirror;
    }
    const over = new THREE.Mesh(
      new THREE.PlaneGeometry(size, size),
      new THREE.MeshStandardMaterial({ color: T.floor, roughness: 0.9, transparent: !this.low, opacity: this.low ? 1 : 0.62, depthWrite: !!this.low }),
    );
    over.position.z = this.floorZ;
    this.add(over);
  }

  // ===== 테마별 소품 =====

  crystal(T, rnd) {
    const ceilZ = 13;
    const ceil = rockPlane(260, 160, 60, 3.5, T.rock, rnd);
    ceil.rotation.x = Math.PI; // 아래를 봄
    ceil.position.set(0, 40, ceilZ);
    const wall = rockPlane(260, 60, 50, 5, T.rock, rnd);
    wall.rotation.x = Math.PI / 2;
    wall.position.set(0, 75, ceilZ - 25);
    this.add(ceil, wall);
    // 천장 종유석
    const st = [];
    for (let i = 0; i < (this.low ? 30 : 70); i++) {
      const x = (rnd() - 0.5) * 180;
      const y = -30 + rnd() * 100;
      const h = 2 + rnd() * 6;
      if (Math.abs(x) < this.logoW * 0.6 && y < 10) continue;
      st.push({ p: new THREE.Vector3(x, y, ceilZ - h / 2), s: new THREE.Vector3(0.6 + rnd() * 1.4, 0.6 + rnd() * 1.4, h), r: new THREE.Euler(-Math.PI / 2, 0, 0) });
    }
    this.add(instanced(new THREE.ConeGeometry(1, 1, 5).rotateX(-Math.PI / 2), new THREE.MeshStandardMaterial({ color: T.rock, roughness: 1, flatShading: true }), st));
    // 자수정 무리: 천장에서 아래로 · 바닥에서 위로 (로고 바로 앞 가운데는 비움)
    const cr = [];
    for (let i = 0; i < (this.low ? 10 : 22); i++) {
      const x = (rnd() - 0.5) * 160;
      const y = -20 + rnd() * 90;
      if (Math.abs(x) < this.logoW * 0.6 && y < 18) continue; // 글자 앞을 가리지 않게
      crystalCluster(cr, new THREE.Vector3(x, y, ceilZ - 0.5), -1, 1.5 + rnd() * 2.5, T.crystals, rnd);
    }
    for (let i = 0; i < (this.low ? 14 : 34); i++) {
      const x = (rnd() - 0.5) * 170;
      const y = -26 + rnd() * 100;
      if (Math.abs(x) < this.logoW * 0.55 && y < 6) continue; // 로고 앞
      crystalCluster(cr, new THREE.Vector3(x, y, this.floorZ), 1, 1.2 + rnd() * (y > 20 ? 4 : 2.2), T.crystals, rnd);
    }
    const crm = new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.5, roughness: 0.25, metalness: 0.1, flatShading: true });
    crm.onBeforeCompile = (sh) => {
      sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance *= diffuseColor.rgb;'); // 결정 색으로 빛남
    };
    const cm = instanced(new THREE.OctahedronGeometry(1, 0), crm, cr);
    this.add(cm);
    this.glowMat = crm;
    // 결정 빛 몇 개
    for (let i = 0; i < 3; i++) {
      const l = new THREE.PointLight(T.crystals[i % T.crystals.length], C.TITLE_LIGHT[2], 50, 1.6);
      l.position.set((i - 1) * 40, 18 + rnd() * 20, this.floorZ + 3);
      this.light(l, C.TITLE_LIGHT[2]);
    }
    // 둥근 바위
    const rocks = [];
    for (let i = 0; i < 26; i++) {
      const x = (rnd() - 0.5) * 150;
      const y = -24 + rnd() * 80;
      if (Math.abs(x) < this.logoW * 0.5 && y < 8) continue;
      const s = 0.8 + rnd() * 2.2;
      rocks.push({ p: new THREE.Vector3(x, y, this.floorZ + s * 0.3), s: new THREE.Vector3(s, s * (0.7 + rnd() * 0.5), s * 0.7), r: new THREE.Euler(rnd(), rnd(), rnd()) });
    }
    this.add(instanced(new THREE.DodecahedronGeometry(1, 0), new THREE.MeshStandardMaterial({ color: T.rock, roughness: 1, flatShading: true }), rocks));
    this.moteBox = [-90, 90, -30, 60, this.floorZ, ceilZ];
  }

  volcano(T, rnd) {
    // 용암 균열: 바닥 위 빛나는 금 (마구 걷는 선, 가는 상자)
    const seg = [];
    for (let k = 0; k < (this.low ? 10 : 22); k++) {
      let x = (rnd() - 0.5) * 160;
      let y = -24 + rnd() * 90;
      let a = rnd() * Math.PI * 2;
      for (let s = 0; s < 8 + rnd() * 10; s++) {
        const len = 1.5 + rnd() * 3;
        a += (rnd() - 0.5) * 1.2;
        const nx = x + Math.cos(a) * len;
        const ny = y + Math.sin(a) * len;
        seg.push({ p: new THREE.Vector3((x + nx) / 2, (y + ny) / 2, this.floorZ + 0.03), s: new THREE.Vector3(len, 0.12 + rnd() * 0.3, 0.06), r: new THREE.Euler(0, 0, a) });
        x = nx;
        y = ny;
      }
    }
    const lava = new THREE.MeshBasicMaterial({ color: new THREE.Color(T.lava).multiplyScalar(2.2), fog: true });
    this.add(instanced(new THREE.BoxGeometry(1, 1, 1), lava, seg));
    this.lavaMat = lava;
    // 먼 화산 (그림자) + 분화구 빛
    const coneMat = new THREE.MeshStandardMaterial({ color: T.rock, roughness: 1, flatShading: true });
    for (const [x, y, r, h] of [[-45, 95, 34, 34], [55, 110, 42, 44], [5, 130, 30, 26]]) {
      const c = new THREE.Mesh(new THREE.CylinderGeometry(r * 0.15, r, h, 9, 3).rotateX(Math.PI / 2), coneMat);
      c.position.set(x, y, this.floorZ + h / 2);
      this.add(c);
      const g = glowSprite(T.lava, r * 1.2, r * 0.6, 0.9);
      g.position.set(x, y, this.floorZ + h + 2);
      this.add(g);
    }
    // 하늘 붉은 기운
    const sky = glowSprite(0xff3a08, 260, 70, 0.35);
    sky.position.set(0, 140, 20);
    this.add(sky);
    for (let i = 0; i < 2; i++) {
      const l = new THREE.PointLight(T.lava, 80, 60, 1.5);
      l.position.set((i ? 30 : -30), 15, this.floorZ + 1.5);
      this.light(l, 80);
    }
    this.updaters.push((t) => (lava.color.setHex(T.lava).multiplyScalar(1.9 + 0.5 * Math.sin(t * 1.7))));
    const rocks = [];
    for (let i = 0; i < 24; i++) {
      const x = (rnd() - 0.5) * 160;
      const y = -24 + rnd() * 80;
      if (Math.abs(x) < this.logoW * 0.5 && y < 8) continue;
      const s = 1 + rnd() * 2.5;
      rocks.push({ p: new THREE.Vector3(x, y, this.floorZ + s * 0.2), s: new THREE.Vector3(s, s, s * 0.8), r: new THREE.Euler(rnd(), rnd(), rnd()) });
    }
    this.add(instanced(new THREE.DodecahedronGeometry(1, 0), coneMat, rocks));
    this.moteBox = [-90, 90, -20, 70, this.floorZ, this.floorZ + 30];
  }

  desert(T, rnd) {
    this.add(stars(this.low ? 500 : 1400, rnd));
    const moon = new THREE.Mesh(new THREE.SphereGeometry(6, 24, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.moon), fog: false }));
    moon.position.set(-60, 130, 48);
    this.add(moon);
    const mg = glowSprite(T.moon, 50, 50, 0.22);
    mg.position.copy(moon.position);
    this.add(mg);
    // 모래 언덕 (납작한 공)
    const sandMat = new THREE.MeshStandardMaterial({ color: T.sand, roughness: 1 });
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(400, 400), sandMat);
    ground.position.z = this.floorZ;
    this.add(ground);
    const dunes = [];
    for (let i = 0; i < 14; i++) dunes.push({ p: new THREE.Vector3((rnd() - 0.5) * 220, 20 + rnd() * 110, this.floorZ - 2), s: new THREE.Vector3(30 + rnd() * 30, 14 + rnd() * 14, 4 + rnd() * 5), r: new THREE.Euler(0, 0, rnd() * 3) });
    this.add(instanced(new THREE.SphereGeometry(1, 20, 10), sandMat, dunes));
    // 피라미드 + 빛나는 금 꼭대기
    const pyr = new THREE.MeshStandardMaterial({ color: T.stone, roughness: 0.9, flatShading: true });
    for (const [x, y, s] of [[-38, 70, 26], [28, 95, 36], [75, 60, 16]]) {
      const p = new THREE.Mesh(new THREE.ConeGeometry(s, s * 0.9, 4).rotateX(Math.PI / 2).rotateZ(Math.PI / 4), pyr);
      p.position.set(x, y, this.floorZ + s * 0.45);
      this.add(p);
      const cap = new THREE.Mesh(new THREE.ConeGeometry(s * 0.12, s * 0.11, 4).rotateX(Math.PI / 2).rotateZ(Math.PI / 4), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.cap).multiplyScalar(2) }));
      cap.position.set(x, y, this.floorZ + s * 0.9 - s * 0.05);
      this.add(cap);
      const g = glowSprite(T.cap, s * 0.9, s * 0.9, 0.7);
      g.position.copy(cap.position);
      this.add(g);
    }
    this.moteBox = [-90, 90, -30, 60, this.floorZ, this.floorZ + 6];
  }

  mushroom(T, rnd) {
    const stem = new THREE.MeshStandardMaterial({ color: T.stem, emissive: T.stem, emissiveIntensity: 0.25, roughness: 0.9 });
    const capGeo = new THREE.SphereGeometry(1, 20, 10, 0, Math.PI * 2, 0, Math.PI / 2);
    const capMat = new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.9, roughness: 0.5 });
    capMat.onBeforeCompile = (sh) => {
      sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n totalEmissiveRadiance *= diffuseColor.rgb;');
    };
    const stems = [];
    const caps = [];
    const spots = [];
    const place = (x, y, h) => {
      const r = h * (0.45 + rnd() * 0.25);
      const lean = (rnd() - 0.5) * 0.3;
      stems.push({ p: new THREE.Vector3(x, y, this.floorZ + h / 2), s: new THREE.Vector3(h * 0.09, h * 0.09, h), r: new THREE.Euler(lean, 0, 0) });
      const c = T.caps[Math.floor(rnd() * T.caps.length)];
      caps.push({ p: new THREE.Vector3(x, y - lean * h * 0.5, this.floorZ + h), s: new THREE.Vector3(r, r, r * 0.55), c });
      for (let k = 0; k < 5; k++) {
        const a = rnd() * Math.PI * 2;
        const e = 0.3 + rnd() * 0.9;
        spots.push({ p: new THREE.Vector3(x + Math.cos(a) * Math.cos(e) * r, y - lean * h * 0.5 + Math.sin(a) * Math.cos(e) * r, this.floorZ + h + Math.sin(e) * r * 0.55), s: new THREE.Vector3(r * 0.09, r * 0.09, r * 0.05) });
      }
      return c;
    };
    const big = [];
    for (let i = 0; i < (this.low ? 14 : 30); i++) {
      const x = (rnd() - 0.5) * 170;
      const y = -22 + rnd() * 110;
      if (Math.abs(x) < this.logoW * 0.55 && y < 8) continue;
      const h = (y > 15 ? 6 : 2) + rnd() * (y > 15 ? 16 : 4);
      const c = place(x, y, h);
      if (h > 14 && big.length < 3) big.push([x, y, h, c]);
    }
    this.add(instanced(new THREE.CylinderGeometry(0.7, 1, 1, 8).rotateX(Math.PI / 2), stem, stems));
    this.add(instanced(capGeo.rotateX(Math.PI / 2), capMat, caps));
    this.add(instanced(new THREE.SphereGeometry(1, 8, 6), new THREE.MeshBasicMaterial({ color: 0xffffff }), spots));
    for (const [x, y, h, c] of big) {
      const l = new THREE.PointLight(c, 90, 40, 1.5);
      l.position.set(x, y, this.floorZ + h - 1);
      this.light(l, 90);
    }
    // 땅 풀 (작은 빛 점)
    this.moteBox = [-90, 90, -25, 70, this.floorZ, this.floorZ + 20];
  }

  skycastle(T, rnd) {
    this.add(stars(this.low ? 500 : 1400, rnd));
    const moon = new THREE.Mesh(new THREE.SphereGeometry(8, 24, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.moon), fog: false }));
    moon.position.set(55, 140, 55);
    this.add(moon);
    const mg = glowSprite(T.moon, 60, 60, 0.2);
    mg.position.copy(moon.position);
    this.add(mg);
    const moonLight = new THREE.DirectionalLight(T.moon, 1.4);
    moonLight.position.set(55, 140, 55);
    this.light(moonLight, 1.4);
    // 구름 바다 (납작한 공 무더기)
    const cloudMat = new THREE.MeshStandardMaterial({ color: T.cloud, roughness: 1, emissive: T.cloud, emissiveIntensity: 0.15 });
    const cl = [];
    for (let i = 0; i < (this.low ? 120 : 260); i++) {
      const x = (rnd() - 0.5) * 300;
      const y = -40 + rnd() * 200;
      const s = 5 + rnd() * 9;
      cl.push({ p: new THREE.Vector3(x, y, this.floorZ - 1 - s * 0.45 + rnd() * 0.8), s: new THREE.Vector3(s * 1.6, s, s * 0.45) }); // 윗면이 글자 밑 근처
    }
    this.add(instanced(new THREE.SphereGeometry(1, 14, 8), cloudMat, cl));
    // 먼 성: 탑 (원기둥 + 원뿔 지붕) · 성벽 · 불 켜진 창
    const wall = new THREE.MeshStandardMaterial({ color: T.wall, roughness: 0.9, flatShading: true });
    const roof = new THREE.MeshStandardMaterial({ color: T.roof, roughness: 0.8, flatShading: true });
    const win = new THREE.MeshBasicMaterial({ color: new THREE.Color(T.window).multiplyScalar(1.6) });
    const wins = [];
    const castle = (cx, cy, k) => {
      const towers = [[-8, 0, 3, 22], [8, 0, 3, 22], [0, 4, 4, 32], [-14, 6, 2.2, 16], [14, 6, 2.2, 16]];
      for (const [dx, dy, r, h] of towers) {
        const t = new THREE.Mesh(new THREE.CylinderGeometry(r * k, r * k, h * k, 10).rotateX(Math.PI / 2), wall);
        t.position.set(cx + dx * k, cy + dy * k, this.floorZ + (h * k) / 2 - 2);
        const rf = new THREE.Mesh(new THREE.ConeGeometry(r * k * 1.3, r * k * 2.6, 10).rotateX(Math.PI / 2), roof);
        rf.position.set(cx + dx * k, cy + dy * k, this.floorZ + h * k - 2 + r * k * 1.3);
        this.add(t, rf);
        for (let j = 0; j < 3; j++) wins.push({ p: new THREE.Vector3(cx + dx * k, cy + dy * k - r * k - 0.05, this.floorZ - 2 + h * k * (0.35 + j * 0.2)), s: new THREE.Vector3(0.6 * k, 0.2, 1.1 * k) });
      }
      const w = new THREE.Mesh(new THREE.BoxGeometry(16 * k, 3 * k, 10 * k), wall);
      w.position.set(cx, cy, this.floorZ + 5 * k - 2);
      this.add(w);
    };
    castle(-30, 85, 1.4);
    castle(48, 120, 1.1);
    castle(-80, 130, 0.9);
    this.add(instanced(new THREE.BoxGeometry(1, 1, 1), win, wins));
    this.moteBox = [-90, 90, -30, 80, this.floorZ, this.floorZ + 25];
  }

  castle(T, rnd) {
    // 벽돌 성벽 (로고 뒤) + 위 톱니 + 양 끝 탑
    const brick = document.createElement('canvas');
    brick.width = brick.height = 128;
    const g = brick.getContext('2d');
    const base = new THREE.Color(T.wall);
    g.fillStyle = `#${base.clone().multiplyScalar(0.5).getHexString()}`;
    g.fillRect(0, 0, 128, 128);
    for (let row = 0; row < 8; row++) {
      for (let col = -1; col < 4; col++) {
        const v = 0.75 + rnd() * 0.5;
        g.fillStyle = `#${base.clone().multiplyScalar(v).getHexString()}`;
        g.fillRect(col * 40 + (row % 2) * 20 + 2, row * 16 + 2, 36, 12);
      }
    }
    const tex = new THREE.CanvasTexture(brick);
    tex.colorSpace = THREE.SRGBColorSpace;
    tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(30, 5);
    const wallMat = new THREE.MeshStandardMaterial({ map: tex, roughness: 0.95 });
    const wallY = 22;
    const wallH = 24;
    const w = new THREE.Mesh(new THREE.BoxGeometry(220, 6, wallH), wallMat);
    w.position.set(0, wallY, this.floorZ + wallH / 2);
    this.add(w);
    const cren = [];
    for (let x = -108; x <= 108; x += 5) cren.push({ p: new THREE.Vector3(x, wallY, this.floorZ + wallH + 1.2), s: new THREE.Vector3(2.6, 6, 2.4) });
    const tm = new THREE.MeshStandardMaterial({ color: T.wall, roughness: 1 });
    this.add(instanced(new THREE.BoxGeometry(1, 1, 1), tm, cren));
    for (const x of [-62, 62]) {
      const t = new THREE.Mesh(new THREE.CylinderGeometry(8, 8, wallH + 14, 12).rotateX(Math.PI / 2), wallMat);
      t.position.set(x, wallY - 3, this.floorZ + (wallH + 14) / 2);
      this.add(t);
    }
    // 횃불: 받침 + 일렁이는 불꽃 빛 (빛은 몇 개만)
    const flames = [];
    const xs = [-48, -32, -16, 16, 32, 48];
    xs.forEach((x, i) => {
      const z = this.floorZ + 7;
      const stick = new THREE.Mesh(new THREE.CylinderGeometry(0.25, 0.18, 2.2, 6).rotateX(Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0x2a1a10 }));
      stick.position.set(x, wallY - 3.3, z);
      this.add(stick);
      const f = glowSprite(T.torch, 3.2, 4.4, 1);
      f.position.set(x, wallY - 3.4, z + 1.8);
      const core = glowSprite(0xffe2a0, 1.4, 2, 1);
      core.position.copy(f.position);
      const halo = glowSprite(T.torch, 16, 16, 0.35);
      halo.position.copy(f.position);
      this.add(f, core, halo);
      flames.push([f, core, halo, rnd() * 10]);
      if (!this.low || i % 2 === 0) {
        const l = new THREE.PointLight(T.torch, 45, 30, 1.6);
        l.position.set(x, wallY - 5, z + 2);
        this.light(l, 45);
        flames[flames.length - 1].push(l);
      }
    });
    this.updaters.push((t) => {
      for (const [f, core, halo, ph, l] of flames) {
        const k = 0.85 + 0.15 * Math.sin(t * 13 + ph) * Math.sin(t * 7.3 + ph * 2);
        f.scale.set(3.2 * k, 4.4 * (0.9 + 0.2 * Math.sin(t * 11 + ph)), 1);
        core.scale.set(1.4 * k, 2 * k, 1);
        halo.material.opacity = 0.3 * k;
        if (l) l.userData.flicker = k;
      }
    });
    this.flames = flames;
    this.moteBox = [-80, 80, -20, 20, this.floorZ, this.floorZ + 26];
  }

  meadow(T, rnd) {
    this.add(stars(this.low ? 600 : 1600, rnd));
    const moon = new THREE.Mesh(new THREE.SphereGeometry(5, 24, 16), new THREE.MeshBasicMaterial({ color: new THREE.Color(T.moon), fog: false }));
    moon.position.set(60, 130, 45);
    this.add(moon);
    const mg = glowSprite(T.moon, 45, 45, 0.2);
    mg.position.copy(moon.position);
    this.add(mg);
    const moonLight = new THREE.DirectionalLight(T.moon, 0.3);
    moonLight.position.set(60, 130, 45);
    this.light(moonLight, 0.3);
    const ground = rockPlane(400, 400, 50, 1.2, T.grass, rnd);
    ground.position.z = this.floorZ - 0.3;
    this.add(ground);
    // 풀잎 (가는 원뿔)
    const blades = [];
    for (let i = 0; i < (this.low ? 900 : 2600); i++) {
      const x = (rnd() - 0.5) * 180;
      const y = -30 + rnd() * 100;
      if (Math.abs(x) < this.logoW * 0.5 && y > -12 && y < 4) continue; // 로고 아래는 비움
      const h = 0.6 + rnd() * 1.4;
      blades.push({ p: new THREE.Vector3(x, y, this.floorZ + h / 2 - 0.1), s: new THREE.Vector3(0.12, 0.12, h), r: new THREE.Euler((rnd() - 0.5) * 0.5, (rnd() - 0.5) * 0.5, 0), c: new THREE.Color(T.grass).multiplyScalar(0.8 + rnd() * 0.8).getHex() });
    }
    this.add(instanced(new THREE.ConeGeometry(1, 1, 3).rotateX(Math.PI / 2), new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1 }), blades));
    // 나무 그림자 (원뿔 쌓기)
    const tm = new THREE.MeshStandardMaterial({ color: T.tree, roughness: 1, flatShading: true });
    const cones = [];
    for (let i = 0; i < 40; i++) {
      const x = (rnd() - 0.5) * 240;
      const y = 35 + rnd() * 100;
      const h = 10 + rnd() * 16;
      for (let k = 0; k < 3; k++) cones.push({ p: new THREE.Vector3(x, y, this.floorZ + h * (0.35 + k * 0.22)), s: new THREE.Vector3(h * (0.32 - k * 0.07), h * (0.32 - k * 0.07), h * 0.45) });
    }
    this.add(instanced(new THREE.ConeGeometry(1, 1, 7).rotateX(Math.PI / 2), tm, cones));
    this.moteBox = [-80, 80, -30, 50, this.floorZ + 0.3, this.floorZ + 9];
  }

  // 매 프레임: t = 초, lit = 장면 밝기 0~1 (캄캄 → 밝아짐), scale = 화면 높이 기준 점 크기
  update(t, lit, scale) {
    for (const [l, base] of this.lights) l.intensity = base * lit * (l.userData.flicker ?? 1);
    const u = this.dust.material.uniforms;
    u.uTime.value = t;
    u.uLit.value = 0.3 + 0.7 * lit;
    u.uScale.value = scale;
    for (const f of this.updaters) f(t, lit);
  }

  dispose() {
    this.scene.traverse((o) => {
      o.geometry?.dispose();
      const ms = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
      for (const m of ms) {
        m.map?.dispose();
        m.dispose();
      }
    });
    this.mirror?.getRenderTarget().dispose();
  }
}
