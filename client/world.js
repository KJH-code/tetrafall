// 맵 테마 (TABS 식 저폴리 자연, 모습만 — 규칙·지형 칸은 그대로). 맵 id → 테마는 config WORLD_MAP_THEME, 테마 값은 WORLD_THEMES.
// 표에 없는 맵(과 대기실)은 예전 노을 그대로. 테마가 있으면:
// 하늘·안개·조명 색 / 바닥(2칸 체크 + 얇은 칸 선) / 지형 블록 재질(윗면·옆면) / 필드 아래 떠 있는 섬(절벽 + 바위 뿌리) /
// 먼 배경 3층(가까운 작은 섬·구름 바다·먼 산) / 위험(용암 자리) 모습.
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';

// 같은 모양이 매번 같게 (새로고침마다 배경이 바뀌지 않게)
function rng(seed) {
  let s = seed >>> 0;
  return () => {
    s = (s * 1664525 + 1013904223) >>> 0;
    return s / 4294967296;
  };
}

const hex = (c) => `#${new THREE.Color(c).getHexString()}`;
const shade = (c, k) => new THREE.Color(c).multiplyScalar(k);
const Z_UP = new THREE.Matrix4().makeRotationX(Math.PI / 2); // three.js 기본 도형(y 위) → z 위

function canvasTex(n, draw, repeat) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = n;
  draw(canvas.getContext('2d'), n);
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  if (repeat) tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  return tex;
}

// 바닥 무늬 한 칸 (잔디: 풀 자국, 모래: 물결 자국)
function speckle(ctx, x0, y0, n, kind, base, r) {
  if (kind === 'sand') {
    ctx.strokeStyle = hex(shade(base, 0.9));
    ctx.lineWidth = 1.5;
    for (let k = 0; k < 3; k++) {
      const y = y0 + n * (0.25 + k * 0.25) + (r() - 0.5) * 4;
      ctx.beginPath();
      ctx.moveTo(x0 + 4, y);
      ctx.quadraticCurveTo(x0 + n / 2, y - 4 - r() * 3, x0 + n - 4, y);
      ctx.stroke();
    }
    return;
  }
  ctx.fillStyle = hex(new THREE.Color(base).lerp(new THREE.Color(0xffffff), 0.18));
  for (let k = 0; k < 10; k++) {
    const x = x0 + 4 + r() * (n - 8);
    const y = y0 + 6 + r() * (n - 10);
    ctx.beginPath();
    ctx.moveTo(x, y);
    ctx.lineTo(x + 2, y - 5);
    ctx.lineTo(x + 4, y);
    ctx.fill();
  }
}

// 바닥: 2×2 칸 한 장 (체크무늬) + 칸 경계 얇은 선. repeat 은 판 크기 / 2
function floorTexture(f) {
  return canvasTex(128, (ctx, n) => {
    const r = rng(7);
    const h = n / 2;
    for (let i = 0; i < 2; i++) {
      for (let j = 0; j < 2; j++) {
        const c = (i + j) % 2 ? f.b : f.a;
        ctx.fillStyle = hex(c);
        ctx.fillRect(i * h, j * h, h, h);
        speckle(ctx, i * h, j * h, h, f.paint, c, r);
      }
    }
    ctx.strokeStyle = f.line;
    ctx.lineWidth = 2;
    for (let k = 0; k <= 2; k++) {
      ctx.beginPath();
      ctx.moveTo(k * h, 0);
      ctx.lineTo(k * h, n);
      ctx.moveTo(0, k * h);
      ctx.lineTo(n, k * h);
      ctx.stroke();
    }
  }, true);
}

// 지형 블록 면 (64px 한 장 = 블록 한 면). 테두리를 어둡게 그려 칸 경계가 보이게 (예전 블록과 같은 방식)
function blockFace(t, face) {
  return canvasTex(64, (ctx, n) => {
    const r = rng(face === 'top' ? 3 : face === 'side' ? 5 : 9);
    if (t.paint === 'grass') {
      if (face === 'top') {
        ctx.fillStyle = hex(t.top);
        ctx.fillRect(0, 0, n, n);
        speckle(ctx, 0, 0, n, 'grass', t.top, r);
      } else {
        ctx.fillStyle = hex(t.side);
        ctx.fillRect(0, 0, n, n);
        ctx.fillStyle = hex(shade(t.side, 0.82));
        for (let k = 0; k < 16; k++) ctx.fillRect(r() * n, 18 + r() * (n - 20), 3 + r() * 4, 3 + r() * 3);
        if (face === 'side') {
          // 위쪽 띠: 잔디가 흘러내린 들쭉날쭉한 가장자리
          ctx.fillStyle = hex(t.top);
          ctx.beginPath();
          ctx.moveTo(0, 0);
          ctx.lineTo(n, 0);
          for (let x = n; x >= 0; x -= 8) ctx.lineTo(x, 11 + ((x / 8) % 2) * 6 + r() * 3);
          ctx.closePath();
          ctx.fill();
        }
      }
    } else {
      // 사암 벽돌: 윗면은 밝은 판, 옆면은 엇갈린 벽돌 두 줄
      const base = face === 'top' ? t.top : t.side;
      ctx.fillStyle = hex(base);
      ctx.fillRect(0, 0, n, n);
      ctx.fillStyle = hex(shade(base, 0.9));
      for (let k = 0; k < 14; k++) ctx.fillRect(r() * n, r() * n, 2 + r() * 3, 2 + r() * 3);
      ctx.strokeStyle = hex(shade(base, 0.72));
      ctx.lineWidth = 2;
      if (face !== 'top') {
        for (const [y, off] of [[n / 3, 0], [(2 * n) / 3, n / 4]]) {
          ctx.beginPath();
          ctx.moveTo(0, y);
          ctx.lineTo(n, y);
          ctx.stroke();
        }
        for (const [y0, off] of [[0, n / 2], [n / 3, n / 4], [(2 * n) / 3, (3 * n) / 4]]) {
          ctx.beginPath();
          ctx.moveTo(off, y0);
          ctx.lineTo(off, y0 + n / 3);
          ctx.stroke();
        }
      } else {
        ctx.strokeRect(9, 9, n - 18, n - 18);
      }
    }
    ctx.strokeStyle = hex(t.rim);
    ctx.lineWidth = 4;
    ctx.strokeRect(2, 2, n - 4, n - 4);
  });
}

// 떠 있는 섬 아랫부분: 윗고리는 필드 테두리(정사각형) 그대로 → 첫 띠는 거의 수직 절벽 → 아래로 좁아지며 울퉁불퉁한 바위 뿌리.
// bands: 띠마다 색 (위에서 아래로). 꼭짓점 색 + 면 평평 음영
function islandGeometry(w, d, depth, seed, bands) {
  const r = rng(seed);
  const N = 36;
  const spec = [
    [0, 1, 0],
    [-1.1, 0.985, 0.02],
    [-0.3 * depth, 0.82, 0.08],
    [-0.55 * depth, 0.58, 0.12],
    [-0.8 * depth, 0.33, 0.15],
    [-0.95 * depth, 0.14, 0.2],
  ];
  const rings = spec.map(([z, s, jit], k) => {
    const ring = [];
    for (let i = 0; i < N; i++) {
      const a = (i / N) * Math.PI * 2 + Math.PI / 4;
      const c = Math.cos(a);
      const sn = Math.sin(a);
      const sq = 1 / Math.max(Math.abs(c), Math.abs(sn)); // 정사각형 둘레
      const round = THREE.MathUtils.lerp(sq, 1.05, Math.min(1, k / 2.5));
      const j = 1 + (r() - 0.5) * 2 * jit;
      ring.push(new THREE.Vector3(c * round * (w / 2) * s * j, sn * round * (d / 2) * s * j, z * (k > 1 ? 0.9 + r() * 0.2 : 1)));
    }
    return ring;
  });
  const tip = new THREE.Vector3((r() - 0.5) * 1.5, (r() - 0.5) * 1.5, -depth * 1.1);
  const pos = [];
  const col = [];
  const tri = (a, b, c, color) => {
    pos.push(a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z);
    for (let i = 0; i < 3; i++) col.push(color.r, color.g, color.b);
  };
  const last = rings.length - 1;
  for (let k = 0; k < last; k++) {
    const base = new THREE.Color(bands[Math.min(k, bands.length - 1)]);
    for (let i = 0; i < N; i++) {
      const a = rings[k][i];
      const b = rings[k][(i + 1) % N];
      const c = rings[k + 1][i];
      const e = rings[k + 1][(i + 1) % N];
      const v = base.clone().multiplyScalar(0.92 + ((i * 7 + k * 3) % 5) * 0.035);
      tri(a, c, b, v);
      tri(b, c, e, v);
    }
  }
  const tipCol = shade(bands[bands.length - 1], 0.75);
  for (let i = 0; i < N; i++) tri(rings[last][i], tip, rings[last][(i + 1) % N], tipCol);
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('color', new THREE.Float32BufferAttribute(col, 3));
  g.computeVertexNormals();
  return g;
}

// 장식은 전부 꼭짓점 색 + 한 메시로 합침 (그리기 호출 1번)
class Parts {
  constructor() {
    this.list = [];
  }
  add(geo, color, m) {
    const g = (geo.index ? geo.toNonIndexed() : geo.clone());
    g.deleteAttribute('uv');
    if (!g.attributes.normal) g.computeVertexNormals();
    const c = new THREE.Color(color);
    const arr = new Float32Array(g.attributes.position.count * 3);
    for (let i = 0; i < arr.length; i += 3) [arr[i], arr[i + 1], arr[i + 2]] = [c.r, c.g, c.b];
    g.setAttribute('color', new THREE.BufferAttribute(arr, 3));
    g.applyMatrix4(m);
    this.list.push(g);
    geo.dispose();
  }
  addColored(g, m) {
    const c = g.clone();
    c.applyMatrix4(m);
    this.list.push(c);
  }
  mesh(material) {
    if (!this.list.length) return null;
    const merged = mergeGeometries(this.list);
    for (const g of this.list) g.dispose();
    return new THREE.Mesh(merged, material);
  }
}

const M = () => new THREE.Matrix4();
const at = (x, y, z, rz = 0, s = 1, upright = true) => {
  const m = M().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, rz)), new THREE.Vector3(s, s, s));
  return upright ? m.multiply(Z_UP) : m;
};

// 소품 하나를 (x, y, z) 에 세움. kind: pine round rock cactus palm pyramid
function prop(parts, kind, look, r, x, y, z, s) {
  const rz = r() * Math.PI * 2;
  const leaf = look.leaf[Math.floor(r() * look.leaf.length)];
  if (kind === 'pine') {
    parts.add(new THREE.CylinderGeometry(0.1, 0.15, 0.6, 5), look.trunk, at(x, y, z + 0.3 * s, rz, s));
    for (let k = 0; k < 3; k++) parts.add(new THREE.ConeGeometry(0.7 - k * 0.17, 0.85, 6), shade(leaf, 1 - k * 0.04), at(x, y, z + (0.85 + k * 0.42) * s, rz + k, s));
  } else if (kind === 'round') {
    parts.add(new THREE.CylinderGeometry(0.1, 0.15, 0.9, 5), look.trunk, at(x, y, z + 0.45 * s, rz, s));
    parts.add(new THREE.IcosahedronGeometry(0.65, 0), leaf, at(x, y, z + 1.3 * s, rz, s, false));
    parts.add(new THREE.IcosahedronGeometry(0.42, 0), shade(leaf, 1.1), at(x + 0.4 * s, y, z + 1.0 * s, rz, s, false));
  } else if (kind === 'rock') {
    const m = at(x, y, z + 0.15 * s, rz, s, false).scale(new THREE.Vector3(1, 0.8, 0.6));
    parts.add(new THREE.DodecahedronGeometry(0.45, 0), look.rock, m);
  } else if (kind === 'cactus') {
    parts.add(new THREE.CylinderGeometry(0.16, 0.18, 1.3, 6), leaf, at(x, y, z + 0.65 * s, rz, s));
    for (const side of [-1, 1]) {
      const ax = x + Math.cos(rz) * 0.3 * side * s;
      const ay = y + Math.sin(rz) * 0.3 * side * s;
      const hz = z + (0.55 + (side > 0 ? 0.2 : 0)) * s;
      parts.add(new THREE.CylinderGeometry(0.1, 0.1, 0.45, 6), leaf, at(ax, ay, hz + 0.22 * s, rz, s));
      parts.add(new THREE.CylinderGeometry(0.1, 0.1, 0.3, 6), leaf, at((ax + x) / 2, (ay + y) / 2, hz, rz, s).multiply(M().makeRotationZ(Math.PI / 2)));
    }
  } else if (kind === 'palm') {
    let px = x;
    let py = y;
    const lean = r() * Math.PI * 2;
    for (let k = 0; k < 4; k++) {
      parts.add(new THREE.CylinderGeometry(0.09, 0.12, 0.45, 5), look.trunk, at(px, py, z + (0.22 + k * 0.42) * s, rz, s));
      px += Math.cos(lean) * 0.08 * s;
      py += Math.sin(lean) * 0.08 * s;
    }
    const top = z + 1.75 * s;
    for (let k = 0; k < 5; k++) {
      const a = (k / 5) * Math.PI * 2 + rz;
      const m = M().compose(new THREE.Vector3(px + Math.cos(a) * 0.4 * s, py + Math.sin(a) * 0.4 * s, top - 0.1 * s), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, a)), new THREE.Vector3(s, s, s));
      m.multiply(M().makeRotationY(Math.PI / 2 + 0.5)); // 잎을 바깥으로 눕힘
      parts.add(new THREE.ConeGeometry(0.16, 0.9, 4), leaf, m.multiply(Z_UP));
    }
  } else if (kind === 'pyramid') {
    parts.add(new THREE.ConeGeometry(1.0, 1.1, 4), look.terrain.top, at(x, y, z + 0.55 * s, Math.PI / 4 + rz, s));
  }
}

// 먼 떠 있는 작은 섬: 바위 뿌리 + 윗면 + 소품 몇 개
function islet(parts, look, r, x, y, z) {
  const s = 1.6 + r() * 2.4;
  const geo = islandGeometry(s * 2, s * 2, s * 1.8, Math.floor(r() * 1e6), look.cliff);
  parts.addColored(geo, M().makeTranslation(x, y, z));
  geo.dispose();
  parts.add(new THREE.BoxGeometry(s * 2, s * 2, 0.3), look.floor.a, M().makeTranslation(x, y, z + 0.15));
  const n = 1 + Math.floor(r() * 3);
  for (let k = 0; k < n; k++) {
    const kind = look.props[Math.floor(r() * look.props.length)];
    prop(parts, kind, look, r, x + (r() - 0.5) * s * 1.2, y + (r() - 0.5) * s * 1.2, z + 0.3, 0.8 + r() * 0.6);
  }
}

// 구름 한 덩이: 납작한 각진 공 몇 개
function cloud(parts, color, r, x, y, z, s) {
  const n = 3 + Math.floor(r() * 3);
  for (let k = 0; k < n; k++) {
    const b = (1.1 + r() * 1.5) * s;
    const m = M().compose(new THREE.Vector3(x + (k - n / 2) * 1.5 * s, y + (r() - 0.5) * 1.4 * s, z + (r() - 0.3) * 0.7 * s), new THREE.Quaternion().setFromEuler(new THREE.Euler(r(), r(), r())), new THREE.Vector3(b, b, b * 0.6));
    parts.add(new THREE.IcosahedronGeometry(1, 0), color, m);
  }
}

// 먼 산 (뾰족 봉우리 / 평평한 메사 / 피라미드) — 지평선 둘레, 안개 없이 지평선 색을 미리 섞어 멀게
function farShapes(parts, look, r, cx, cy, n) {
  const f = look.far;
  for (let k = 0; k < n; k++) {
    const a = (k / n) * Math.PI * 2 + r() * 0.35;
    const dist = 100 + r() * 30;
    const h = 12 + r() * 16;
    const kind = f.shapes[Math.floor(r() * f.shapes.length)];
    const rad = 8 + r() * 9;
    const geo = kind === 'mesa' ? new THREE.CylinderGeometry(rad * 0.7, rad, h * 0.6, 7, 1) : kind === 'pyramid' ? new THREE.ConeGeometry(rad, h, 4) : new THREE.ConeGeometry(rad, h, 5 + Math.floor(r() * 3));
    const hh = kind === 'mesa' ? h * 0.6 : h;
    const tint = new THREE.Color(f.color).lerp(new THREE.Color(look.sky.horizon), 0.45 + r() * 0.3);
    parts.add(geo, tint, at(cx + Math.cos(a) * dist, cy + Math.sin(a) * dist, f.base + hh / 2, r() * 3));
  }
}

// 물 위험 표면: 물결 + 흰 물마루 + 흐르는 잔물결 선 + 필드 가장자리를 따라 출렁이는 거품 테 (위험 높이가 바로 읽히게)
function waterMaterial(h) {
  return noOutline(new THREE.ShaderMaterial({
    uniforms: {
      time: { value: 0 },
      deep: { value: new THREE.Color(h.deep) },
      mid: { value: new THREE.Color(h.mid) },
      foam: { value: new THREE.Color(h.foam) },
      rect: { value: new THREE.Vector4(5, 5, 5, 5) }, // 필드 가운데 x, y, 반폭, 반깊이 (setRect)
    },
    vertexShader: `uniform float time; varying vec2 vW;
      void main() {
        vec4 w = modelMatrix * vec4(position, 1.0);
        vW = w.xy;
        vec3 p = position;
        p.z += sin(w.x * 1.1 + time * 1.3) * 0.05 + sin(w.y * 1.4 - time * 1.1) * 0.04;
        gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
      }`,
    fragmentShader: `uniform float time; uniform vec3 deep; uniform vec3 mid; uniform vec3 foam; uniform vec4 rect; varying vec2 vW;
      void main() {
        vec2 q = vW;
        float n = sin(q.x * 0.9 + time * 0.8) + sin(q.y * 1.2 - time * 0.7) + sin((q.x + q.y) * 0.6 + time * 0.5) + sin(length(q - rect.xy) * 1.3 - time * 1.2);
        vec3 c = mix(deep, mid, smoothstep(-3.0, 2.5, n));
        float l = abs(fract(q.x * 0.33 + sin(q.y * 0.5 + time * 0.6) * 0.45 + time * 0.12) - 0.5);
        c = mix(c, foam, (1.0 - smoothstep(0.0, 0.035, l)) * 0.4);
        c = mix(c, foam, smoothstep(2.6, 3.0, n) * 0.8);
        vec2 dd = abs(q - rect.xy) - rect.zw;
        float dist = length(max(dd, 0.0)) + min(max(dd.x, dd.y), 0.0);
        float band = 0.45 + 0.18 * sin(time * 2.2 + q.x * 1.9 + q.y * 1.6);
        c = mix(c, foam, (1.0 - smoothstep(band * 0.6, band, abs(dist))) * 0.95);
        gl_FragColor = vec4(c, 1.0);
        #include <colorspace_fragment>
      }`,
  }));
}

export class World {
  // r: Renderer. 테마 없는 모습(예전 노을)을 기억해 두고, 테마가 없는 맵으로 오면 되돌린다
  constructor(r) {
    this.r = r;
    this.id = null; // 지금 테마 id (null = 예전 모습)
    this.look = null;
    this.low = false;
    const u = r.dome.material.uniforms;
    this.base = {
      sky: { top: u.top.value.clone(), mid: u.mid.value.clone(), horizon: u.horizon.value.clone(), below: u.below.value.clone(), sunDir: u.sunDir.value.clone() },
      background: r.scene.background.clone(),
      fog: [r.scene.fog.color.clone(), r.scene.fog.near, r.scene.fog.far],
      hemi: [r.hemi.color.clone(), r.hemi.groundColor.clone(), r.hemi.intensity],
      sun: [r.sun.color.clone(), r.sun.intensity],
      floor: r.floor.material,
      terrain: r.blockMeshes.terrain.material,
      lavaTop: r.lavaTop.material,
      lavaBody: r.lava.material.color.clone(),
      lavaLight: r.lavaLight.color.clone(),
      edges: r.edges.material.opacity,
    };
    this.group = new THREE.Group(); // 섬 + 장식 (판 크기·테마가 바뀌면 다시 만듦)
    this.drift = new THREE.Group(); // 천천히 도는 먼 섬·구름
    this.group.add(this.drift);
    r.scene.add(this.group);
    this.mats = [];
  }

  // 위험(용암 자리) 모습: 테마가 있으면 그 값, 없으면 null (render.js 가 예전 용암 색)
  get hazard() {
    return this.look ? this.look.hazard : null;
  }

  // 매 프레임: 맵이 바뀌면 테마를 갈아 끼우고, 먼 섬·구름을 천천히 돌림
  update(state, dt) {
    const id = (state && state.map && C.WORLD_MAP_THEME[state.map.id]) || null;
    if (id !== this.id) this.apply(id);
    if (this.look) this.drift.rotation.z += dt * C.WORLD_DRIFT_SPEED;
  }

  setLow(on) {
    if (this.low === !!on) return;
    this.low = !!on;
    if (this.look) this.layout();
  }

  apply(id) {
    const { r } = this;
    this.id = id;
    this.look = id ? C.WORLD_THEMES[id] : null;
    const L = this.look;
    const b = this.base;
    const u = r.dome.material.uniforms;
    for (const m of this.mats) m.dispose?.();
    this.mats = [];
    if (!L) {
      u.top.value.copy(b.sky.top);
      u.mid.value.copy(b.sky.mid);
      u.horizon.value.copy(b.sky.horizon);
      u.below.value.copy(b.sky.below);
      u.sunDir.value.copy(b.sky.sunDir);
      r.scene.background.copy(b.background);
      [r.scene.fog.near, r.scene.fog.far] = [b.fog[1], b.fog[2]];
      r.scene.fog.color.copy(b.fog[0]);
      r.hemi.color.copy(b.hemi[0]);
      r.hemi.groundColor.copy(b.hemi[1]);
      r.hemi.intensity = b.hemi[2];
      r.sun.color.copy(b.sun[0]);
      r.sun.intensity = b.sun[1];
      r.sunDir = C.SUN_DIR;
      r.floor.material = b.floor;
      r.blockMeshes.terrain.material = b.terrain;
      r.lavaTop.material = b.lavaTop;
      r.lava.material.color.copy(b.lavaBody);
      r.lavaLight.color.copy(b.lavaLight);
      r.edges.material.opacity = b.edges;
      r.terrainColor = null;
    } else {
      u.top.value.set(L.sky.top);
      u.mid.value.set(L.sky.mid);
      u.horizon.value.set(L.sky.horizon);
      u.below.value.set(L.sky.below);
      u.sunDir.value.set(...L.sunDir).normalize();
      r.scene.background.set(L.sky.horizon);
      r.scene.fog.color.set(L.fog[0]);
      [r.scene.fog.near, r.scene.fog.far] = [L.fog[1], L.fog[2]];
      r.hemi.color.set(L.hemi[0]);
      r.hemi.groundColor.set(L.hemi[1]);
      r.hemi.intensity = L.hemi[2];
      r.sun.color.set(L.sunColor);
      r.sun.intensity = L.sunIntensity;
      r.sunDir = L.sunDir;
      // 지형 블록: 윗면·옆면·밑면 따로 (BoxGeometry 면 순서 +x −x +y −y +z −z). 인스턴스 색은 흰색으로 (재질 색 그대로)
      const mk = (map) => noOutline(toon({ map }));
      const side = mk(blockFace(L.terrain, 'side'));
      const top = mk(blockFace(L.terrain, 'top'));
      const bottom = mk(blockFace(L.terrain, 'bottom'));
      r.blockMeshes.terrain.material = [side, side, side, side, top, bottom];
      r.terrainColor = 0xffffff;
      // 바닥 판: 윗면 체크무늬, 옆면(두께 0.3)은 절벽 윗띠 색
      const floorTop = toon({ map: floorTexture(L.floor) });
      const rim = toon({ color: L.floor.rim });
      r.floor.material = [rim, rim, rim, rim, floorTop, rim];
      this.floorTop = floorTop;
      const h = L.hazard;
      r.lavaTop.material = waterMaterial(h);
      r.lava.material.color.set(h.deep);
      r.lavaLight.color.set(h.light[0]);
      r.edges.material.opacity = L.edgeOpacity;
      this.mats.push(side, top, bottom, floorTop, rim, r.lavaTop.material);
    }
    r.gridVersion = -1; // 지형 블록 색 다시
    r.setField(r.W, r.D, true, r.H); // 해 위치·섬 크기
  }

  // 판 크기에 맞춰 섬·장식을 다시 만듦 (setField 가 부름)
  layout() {
    const { r } = this;
    const L = this.look;
    for (const o of [...this.group.children, ...this.drift.children]) {
      if (o === this.drift) continue;
      o.parent.remove(o);
      o.geometry?.dispose();
      o.material?.dispose();
    }
    if (r.gridLines) r.gridLines.visible = !L;
    if (!L) return;
    const w = r.W;
    const d = r.D;
    const cx = w / 2;
    const cy = d / 2;
    this.floorTop.map.repeat.set(w / 2, d / 2);
    if (r.lavaTop.material.uniforms.rect) r.lavaTop.material.uniforms.rect.value.set(cx, cy, w / 2, d / 2);
    const rand = rng(L.seed);
    const k = this.low ? C.WORLD_LOW_DETAIL : 1;
    // 필드 아래 섬 (윗면은 바닥 판 바로 아래)
    const island = new THREE.Mesh(islandGeometry(w, d, Math.max(w, d) * 0.85, L.seed, L.cliff), toon({ vertexColors: true, flatShading: true }));
    island.position.set(cx, cy, -0.3);
    island.receiveShadow = true;
    this.group.add(island);
    // 섬 뿌리에 매달린 바위 + 먼 섬 + 구름 바다 (한 메시)
    const near = new Parts();
    for (let i = 0; i < 6; i++) {
      const a = rand() * Math.PI * 2;
      prop(near, 'rock', L, rand, Math.cos(a) * w * 0.3, Math.sin(a) * d * 0.3, -2.5 - rand() * 4, 1.2 + rand() * 1.5);
    }
    const islets = Math.round(L.islets * k);
    for (let i = 0; i < islets; i++) {
      const a = (i / islets) * Math.PI * 2 + rand() * 0.6;
      const dist = w * 0.5 + 14 + rand() * 26;
      islet(near, L, rand, Math.cos(a) * dist, Math.sin(a) * dist, -7 + rand() * 13);
    }
    const sky = new Parts();
    const clouds = Math.round(L.clouds * k);
    for (let i = 0; i < clouds; i++) {
      const a = rand() * Math.PI * 2;
      const low = i < clouds * 0.7; // 대부분은 섬 아래 구름 바다, 나머지는 멀리 하늘에
      const dist = low ? 6 + rand() * 55 : 45 + rand() * 40;
      cloud(sky, L.cloud, rand, Math.cos(a) * dist, Math.sin(a) * dist, low ? L.sea[1] + 1.5 - rand() * 2.5 : 16 + rand() * 14, 1 + rand() * 1.4);
    }
    const nearMesh = near.mesh(noOutline(toon({ vertexColors: true, flatShading: true })));
    if (nearMesh) this.drift.add(nearMesh);
    // 구름은 스스로 조금 빛나게 (그늘 쪽이 흙색으로 칙칙해지지 않게)
    const cloudMesh = sky.mesh(noOutline(toon({ vertexColors: true, flatShading: true, emissive: shade(L.cloud, 0.45) })));
    if (cloudMesh) this.drift.add(cloudMesh);
    this.drift.position.set(cx, cy, 0);
    // 구름 바다 바닥: 아래를 가리는 넓은 판 (낮은 구름이 반쯤 잠기고, 먼 산 밑동이 묻힘). 멀수록 안개색으로
    const sea = new THREE.Mesh(new THREE.CircleGeometry(160, 40), noOutline(new THREE.MeshBasicMaterial({ color: L.sea[0] })));
    sea.position.set(cx, cy, L.sea[1]);
    this.group.add(sea);
    // 먼 산: 안개 없이 (멀리서도 실루엣)
    const far = new Parts();
    farShapes(far, L, rand, cx, cy, Math.round(L.far.count * (this.low ? 0.6 : 1)));
    const farMat = noOutline(new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true, fog: false }));
    const farMesh = far.mesh(farMat);
    if (farMesh) this.group.add(farMesh);
  }
}
