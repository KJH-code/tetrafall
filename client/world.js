// 맵 테마 (TABS 식 저폴리 자연, 모습만 — 규칙·지형 칸은 그대로). 맵 id → 테마는 config WORLD_MAP_THEME, 테마 값은 WORLD_THEMES.
// 표에 없는 맵(과 대기실)은 예전 노을 그대로. 테마가 있으면:
// 하늘·안개·조명 색(밤이면 별·달) / 바닥(2칸 체크 + 얇은 칸 선) / 지형 블록 재질(윗면·옆면, 빛나는 금·수정) / 필드 아래 떠 있는 섬(절벽 + 바위 뿌리) /
// 먼 배경 3층(가까운 작은 섬·구름 바다·먼 산) / 떠다니는 빛(반딧불·불씨·금가루) / 위험(용암 자리) 모습 (물·독늪·에너지·번개 구름·용암).
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

function toTex(canvas, repeat) {
  const tex = new THREE.CanvasTexture(canvas);
  tex.colorSpace = THREE.SRGBColorSpace;
  tex.anisotropy = 4;
  if (repeat) tex.wrapS = tex.wrapT = THREE.RepeatWrapping;
  return tex;
}

// 한 장 그리기. glow 를 주면 같은 크기의 검은 판(빛나는 부분만 그릴 곳)도 같이 넘김 → 발광 지도
function canvasTex(n, draw, repeat, glow = false) {
  const canvas = document.createElement('canvas');
  canvas.width = canvas.height = n;
  let g = null;
  if (glow) {
    g = document.createElement('canvas');
    g.width = g.height = n;
    const gc = g.getContext('2d');
    gc.fillStyle = '#000';
    gc.fillRect(0, 0, n, n);
  }
  draw(canvas.getContext('2d'), n, g && g.getContext('2d'));
  const tex = toTex(canvas, repeat);
  if (g) tex.userData.glow = toTex(g, repeat);
  return tex;
}

// 갈라진 금 (용암 바닥·현무암): 몇 갈래 꺾인 선. ctx 와 발광 판에 같이
function cracks(ctxs, n, r, color, count, width, step = 0.45) {
  for (const c of ctxs) {
    if (!c) continue;
    c.strokeStyle = color;
    c.lineWidth = width;
    c.lineCap = 'round';
  }
  for (let k = 0; k < count; k++) {
    let x = r() * n;
    let y = r() * n;
    const pts = [[x, y]];
    let a = r() * Math.PI * 2; // 한 방향으로 흐르며 조금씩 꺾임 (V 자 화살표처럼 안 보이게)
    for (let s = 0; s < 5; s++) {
      a += (r() - 0.5) * 1.2;
      x += Math.cos(a) * n * step * (0.5 + r() * 0.5);
      y += Math.sin(a) * n * step * (0.5 + r() * 0.5);
      pts.push([x, y]);
    }
    for (const c of ctxs) {
      if (!c) continue;
      c.beginPath();
      pts.forEach(([px, py], i) => (i ? c.lineTo(px, py) : c.moveTo(px, py)));
      c.stroke();
    }
  }
}

// 바닥 무늬 한 칸: grass 풀 자국 · sand 물결 자국 · stone 자갈 점 · cracks 빛나는 금 · marble 결 · moss 이끼 얼룩
function speckle(ctx, x0, y0, n, f, base, r, gctx) {
  const kind = f.paint;
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
  } else if (kind === 'stone' || kind === 'moss') {
    for (let k = 0; k < 14; k++) {
      ctx.fillStyle = hex(shade(base, kind === 'moss' ? 0.8 + r() * 0.35 : 0.85 + r() * 0.25));
      const s = kind === 'moss' ? 5 + r() * 9 : 2 + r() * 4;
      ctx.beginPath();
      ctx.arc(x0 + 4 + r() * (n - 8), y0 + 4 + r() * (n - 8), s / 2, 0, Math.PI * 2);
      ctx.fill();
    }
  } else if (kind === 'cracks') {
    ctx.save();
    ctx.translate(x0, y0);
    gctx?.save();
    gctx?.translate(x0, y0);
    cracks([ctx, gctx], n, r, hex(f.glow), 1, 1.5, 0.22);
    ctx.restore();
    gctx?.restore();
  } else if (kind === 'marble') {
    ctx.strokeStyle = hex(shade(base, 0.86));
    ctx.lineWidth = 1;
    for (let k = 0; k < 2; k++) {
      ctx.beginPath();
      ctx.moveTo(x0, y0 + r() * n);
      ctx.bezierCurveTo(x0 + n * 0.3, y0 + r() * n, x0 + n * 0.7, y0 + r() * n, x0 + n, y0 + r() * n);
      ctx.stroke();
    }
  } else {
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
}

// 바닥: 2×2 칸 한 장 (체크무늬) + 칸 경계 얇은 선. repeat 은 판 크기 / 2
function floorTexture(f) {
  return canvasTex(128, (ctx, n, gctx) => {
    const r = rng(7);
    const h = n / 2;
    for (let i = 0; i < 2; i++) {
      for (let j = 0; j < 2; j++) {
        const c = (i + j) % 2 ? f.b : f.a;
        ctx.fillStyle = hex(c);
        ctx.fillRect(i * h, j * h, h, h);
        speckle(ctx, i * h, j * h, h, f, c, r, gctx);
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
  }, true, !!f.glow);
}

// 벽돌 두 줄 (옆면) / 안쪽 판 (윗면)
function bricks(ctx, n, base, top) {
  ctx.strokeStyle = hex(shade(base, 0.72));
  ctx.lineWidth = 2;
  if (top) {
    ctx.strokeRect(9, 9, n - 18, n - 18);
    return;
  }
  for (const y of [n / 3, (2 * n) / 3]) {
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
}

// 지형 블록 면 (64px 한 장 = 블록 한 면). 테두리를 어둡게 그려 칸 경계가 보이게 (예전 블록과 같은 방식).
// paint: grass(잔디 윗면·흙 옆면) · sandstone/bricks(벽돌) · crystal(어두운 돌 + 빛나는 수정 결) · basalt(현무암 + 빛나는 금) · stump(나이테 윗면·나무껍질 옆면)
function blockFace(t, face) {
  const glow = !!t.glow;
  return canvasTex(64, (ctx, n, gctx) => {
    const r = rng(face === 'top' ? 3 : face === 'side' ? 5 : 9);
    const base = face === 'top' ? t.top : t.side;
    ctx.fillStyle = hex(base);
    ctx.fillRect(0, 0, n, n);
    if (t.paint === 'grass') {
      if (face === 'top') {
        speckle(ctx, 0, 0, n, { paint: 'grass' }, t.top, r);
      } else {
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
    } else if (t.paint === 'stump') {
      if (face === 'top') {
        for (let k = 5; k >= 1; k--) {
          ctx.strokeStyle = hex(shade(t.top, 0.78 + (k % 2) * 0.1));
          ctx.lineWidth = 2;
          ctx.beginPath();
          ctx.arc(n / 2 + (r() - 0.5) * 2, n / 2 + (r() - 0.5) * 2, k * 5.5, 0, Math.PI * 2);
          ctx.stroke();
        }
      } else {
        ctx.strokeStyle = hex(shade(t.side, 0.7));
        ctx.lineWidth = 3;
        for (let x = 4; x < n; x += 7 + r() * 4) {
          ctx.beginPath();
          ctx.moveTo(x, 0);
          ctx.lineTo(x + (r() - 0.5) * 6, n);
          ctx.stroke();
        }
      }
    } else if (t.paint === 'crystal' || t.paint === 'basalt') {
      ctx.fillStyle = hex(shade(base, 0.85));
      for (let k = 0; k < 10; k++) ctx.fillRect(r() * n, r() * n, 3 + r() * 5, 3 + r() * 5);
      if (t.paint === 'basalt') {
        cracks([ctx, gctx], n, r, hex(t.glow), 1, 1.8, 0.22);
      } else {
        // 수정 결: 모서리에서 솟은 빛나는 각진 조각
        for (let k = 0; k < (face === 'top' ? 3 : 2); k++) {
          const x = 8 + r() * (n - 16);
          const y = 8 + r() * (n - 16);
          const s = 5 + r() * 6;
          for (const c of [ctx, gctx]) {
            c.fillStyle = hex(t.glow);
            c.beginPath();
            c.moveTo(x, y - s);
            c.lineTo(x + s * 0.6, y);
            c.lineTo(x, y + s);
            c.lineTo(x - s * 0.6, y);
            c.closePath();
            c.fill();
          }
        }
      }
    } else {
      ctx.fillStyle = hex(shade(base, 0.9));
      for (let k = 0; k < 14; k++) ctx.fillRect(r() * n, r() * n, 2 + r() * 3, 2 + r() * 3);
      bricks(ctx, n, base, face === 'top');
    }
    ctx.strokeStyle = hex(t.rim);
    ctx.lineWidth = 4;
    ctx.strokeRect(2, 2, n - 4, n - 4);
  }, false, glow);
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

// 장식은 전부 꼭짓점 색 + 재질마다 한 메시로 합침 (그리기 호출 적게)
class Parts {
  constructor() {
    this.list = [];
  }
  add(geo, color, m) {
    const g = geo.index ? geo.toNonIndexed() : geo.clone();
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
    if (!this.list.length) {
      material.dispose();
      return null;
    }
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
const pick = (r, list) => list[Math.floor(r() * list.length)];

// 소품 하나를 (x, y, z) 에 세움. P = { solid, glow } (glow = 스스로 빛나는 것: 수정·버섯 갓·용암 돌)
// kind: pine round rock cactus palm pyramid crystal mushroom deadtree lavarock tower spire house
function prop(P, kind, look, r, x, y, z, s) {
  const parts = P.solid;
  const rz = r() * Math.PI * 2;
  const leaf = pick(r, look.leaf);
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
  } else if (kind === 'lavarock') {
    const m = at(x, y, z + 0.15 * s, rz, s, false).scale(new THREE.Vector3(1, 0.8, 0.6));
    parts.add(new THREE.DodecahedronGeometry(0.45, 0), look.rock, m);
    P.glow.add(new THREE.DodecahedronGeometry(0.2, 0), pick(r, look.glow), at(x + 0.25 * s, y, z + 0.3 * s, rz, s, false));
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
  } else if (kind === 'crystal') {
    // 수정 다발: 길쭉한 팔면체 3~4개, 살짝씩 기울여
    const col = pick(r, look.glow);
    const n = 3 + Math.floor(r() * 2);
    for (let k = 0; k < n; k++) {
      const h = (0.7 + r() * 0.9) * s;
      const m = M().compose(new THREE.Vector3(x + (r() - 0.5) * 0.5 * s, y + (r() - 0.5) * 0.5 * s, z + h * 0.45), new THREE.Quaternion().setFromEuler(new THREE.Euler((r() - 0.5) * 0.7, (r() - 0.5) * 0.7, r() * 3)), new THREE.Vector3(0.22 * s, 0.22 * s, h));
      P.glow.add(new THREE.OctahedronGeometry(1, 0), shade(col, 0.85 + r() * 0.3), m);
    }
  } else if (kind === 'mushroom') {
    const h = (0.8 + r() * 0.8) * s;
    parts.add(new THREE.CylinderGeometry(0.12 * s, 0.18 * s, h, 6), look.trunk, at(x, y, z + h / 2, rz));
    const cap = M().compose(new THREE.Vector3(x, y, z + h), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, rz)), new THREE.Vector3(s, s, s)).multiply(M().makeScale(1, 1, 0.55)).multiply(Z_UP);
    P.glow.add(new THREE.SphereGeometry(0.6, 7, 3, 0, Math.PI * 2, 0, Math.PI / 2), pick(r, look.glow), cap);
  } else if (kind === 'deadtree') {
    parts.add(new THREE.CylinderGeometry(0.07, 0.14, 1.4, 5), look.trunk, at(x, y, z + 0.7 * s, rz, s));
    for (let k = 0; k < 3; k++) {
      const a = rz + k * 2.1;
      const m = M().compose(new THREE.Vector3(x + Math.cos(a) * 0.22 * s, y + Math.sin(a) * 0.22 * s, z + (0.9 + k * 0.18) * s), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, 0, a)), new THREE.Vector3(s, s, s));
      m.multiply(M().makeRotationY(0.9));
      parts.add(new THREE.CylinderGeometry(0.03, 0.06, 0.6, 4), look.trunk, m.multiply(Z_UP));
    }
  } else if (kind === 'tower' || kind === 'spire') {
    const tall = kind === 'spire';
    const h = (tall ? 2.2 : 1.4) * s;
    const rad = (tall ? 0.32 : 0.45) * s;
    parts.add(new THREE.CylinderGeometry(rad, rad * 1.08, h, 8), look.wall, at(x, y, z + h / 2, rz));
    parts.add(new THREE.ConeGeometry(rad * 1.35, (tall ? 1.1 : 0.8) * s, 8), look.roof, at(x, y, z + h + (tall ? 0.55 : 0.4) * s, rz));
    if (look.flag) {
      parts.add(new THREE.CylinderGeometry(0.02 * s, 0.02 * s, 0.6 * s, 4), look.trunk, at(x, y, z + h + 1.0 * s, rz));
      parts.add(new THREE.BoxGeometry(0.35 * s, 0.02 * s, 0.22 * s), look.flag, at(x + 0.18 * s, y, z + h + 1.15 * s, 0, 1, false));
    }
  } else if (kind === 'house') {
    parts.add(new THREE.BoxGeometry(0.9 * s, 0.8 * s, 0.7 * s), look.wall, at(x, y, z + 0.35 * s, rz, 1, false));
    parts.add(new THREE.ConeGeometry(0.78 * s, 0.6 * s, 4), look.roof, at(x, y, z + 1.0 * s, rz + Math.PI / 4));
  }
}

// 먼 떠 있는 작은 섬: 바위 뿌리 + 윗면 + 소품 몇 개
function islet(P, look, r, x, y, z) {
  const s = 1.6 + r() * 2.4;
  const geo = islandGeometry(s * 2, s * 2, s * 1.8, Math.floor(r() * 1e6), look.cliff);
  P.solid.addColored(geo, M().makeTranslation(x, y, z));
  geo.dispose();
  P.solid.add(new THREE.BoxGeometry(s * 2, s * 2, 0.3), look.floor.a, M().makeTranslation(x, y, z + 0.15));
  const n = 1 + Math.floor(r() * 3);
  for (let k = 0; k < n; k++) prop(P, pick(r, look.props), look, r, x + (r() - 0.5) * s * 1.2, y + (r() - 0.5) * s * 1.2, z + 0.3, 0.8 + r() * 0.6);
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

// 먼 배경 (지평선 둘레, 안개 없이 지평선 색을 미리 섞어 멀게). shapes:
// peak 봉우리 · mesa 메사 · pyramid · volcano 화산(꼭대기 빛) · crystal 거대 수정 · cumulus 뭉게구름 기둥 · bigshroom 거대 버섯 · castle 성
function farShapes(P, look, r, cx, cy, n) {
  const f = look.far;
  const S = C.WORLD_FAR;
  for (let k = 0; k < n; k++) {
    const a = (k / n) * Math.PI * 2 + r() * 0.35;
    const dist = S.dist[0] + r() * (S.dist[1] - S.dist[0]);
    const h = S.height[0] + r() * (S.height[1] - S.height[0]);
    const rad = S.radius[0] + r() * (S.radius[1] - S.radius[0]);
    const kind = pick(r, f.shapes);
    const x = cx + Math.cos(a) * dist;
    const y = cy + Math.sin(a) * dist;
    const tint = new THREE.Color(f.color).lerp(new THREE.Color(look.sky.horizon), f.haze[0] + r() * (f.haze[1] - f.haze[0]));
    const base = f.base;
    if (kind === 'mesa') {
      P.solid.add(new THREE.CylinderGeometry(rad * 0.7, rad, h * 0.6, 7, 1), tint, at(x, y, base + h * 0.3, r() * 3));
    } else if (kind === 'pyramid') {
      P.solid.add(new THREE.ConeGeometry(rad, h, 4), tint, at(x, y, base + h / 2, r() * 3));
    } else if (kind === 'volcano') {
      P.solid.add(new THREE.CylinderGeometry(rad * 0.22, rad, h, 8, 1), tint, at(x, y, base + h / 2, r() * 3));
      P.glow.add(new THREE.CylinderGeometry(rad * 0.2, rad * 0.21, 0.6, 8), pick(r, look.glow), at(x, y, base + h + 0.1, 0));
    } else if (kind === 'crystal') {
      for (let j = 0; j < 3; j++) {
        const hh = h * (0.6 + r() * 0.6);
        const m = M().compose(new THREE.Vector3(x + (r() - 0.5) * rad, y + (r() - 0.5) * rad, base + hh * 0.5), new THREE.Quaternion().setFromEuler(new THREE.Euler((r() - 0.5) * 0.4, (r() - 0.5) * 0.4, r() * 3)), new THREE.Vector3(rad * 0.25, rad * 0.25, hh * 0.6));
        P.glow.add(new THREE.OctahedronGeometry(1, 0), new THREE.Color(pick(r, look.glow)).lerp(new THREE.Color(look.sky.horizon), 0.35), m);
      }
    } else if (kind === 'cumulus') {
      for (let j = 0; j < 5; j++) {
        const b = rad * (0.5 + r() * 0.4) * (1 - j * 0.12);
        const m = M().compose(new THREE.Vector3(x + (r() - 0.5) * rad * 0.8, y + (r() - 0.5) * rad * 0.8, base + j * b * 0.9), new THREE.Quaternion().setFromEuler(new THREE.Euler(r(), r(), r())), new THREE.Vector3(b, b, b * 0.75));
        P.glow.add(new THREE.IcosahedronGeometry(1, 0), shade(tint, 0.94 + j * 0.03), m); // 스스로 밝게 (그늘지면 바위처럼 보임)
      }
    } else if (kind === 'bigshroom') {
      P.solid.add(new THREE.CylinderGeometry(rad * 0.12, rad * 0.18, h, 6), tint, at(x, y, base + h / 2, 0));
      const cap = M().makeTranslation(x, y, base + h).multiply(M().makeScale(rad * 0.7, rad * 0.7, rad * 0.35)).multiply(Z_UP);
      P.glow.add(new THREE.SphereGeometry(1, 8, 3, 0, Math.PI * 2, 0, Math.PI / 2), new THREE.Color(pick(r, look.glow)).lerp(new THREE.Color(look.sky.horizon), 0.3), cap);
    } else if (kind === 'castle') {
      const wv = rad * 1.2;
      P.solid.add(new THREE.BoxGeometry(wv, wv * 0.5, h * 0.4), tint, at(x, y, base + h * 0.2, a, 1, false));
      for (const side of [-1, 1]) {
        P.solid.add(new THREE.CylinderGeometry(rad * 0.18, rad * 0.18, h * 0.65, 7), tint, at(x + Math.cos(a + Math.PI / 2) * side * wv * 0.5, y + Math.sin(a + Math.PI / 2) * side * wv * 0.5, base + h * 0.33, 0));
        P.solid.add(new THREE.ConeGeometry(rad * 0.24, h * 0.25, 7), shade(tint, 0.85), at(x + Math.cos(a + Math.PI / 2) * side * wv * 0.5, y + Math.sin(a + Math.PI / 2) * side * wv * 0.5, base + h * 0.78, 0));
      }
    } else {
      const geo = new THREE.ConeGeometry(rad, h, 5 + Math.floor(r() * 3));
      const p = geo.attributes.position;
      for (let i = 0; i < p.count; i++) if (p.getY(i) > h / 2 - 0.01) p.setX(i, p.getX(i) + (r() - 0.5) * 2); // 봉우리를 살짝 비틀기
      P.solid.add(geo, tint, at(x, y, base + h / 2, r() * 3));
    }
  }
}

// 위험 표면 셰이더 (용암 자리). style: water 물결·물마루 · swamp 독늪 거품 방울 · energy 빛 띠 · storm 번개 구름.
// 공통: 필드 가장자리를 따라 출렁이는 밝은 테 (위험 높이가 바로 읽히게)
const HAZARD_STYLE = { water: 0, swamp: 1, energy: 2, storm: 3 };
function hazardMaterial(h) {
  return noOutline(new THREE.ShaderMaterial({
    defines: { STYLE: HAZARD_STYLE[h.style] ?? 0 },
    uniforms: {
      time: { value: 0 },
      deep: { value: new THREE.Color(h.deep) },
      mid: { value: new THREE.Color(h.mid) },
      foam: { value: new THREE.Color(h.foam) },
      rect: { value: new THREE.Vector4(5, 5, 5, 5) }, // 필드 가운데 x, y, 반폭, 반깊이 (layout)
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
      float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
      void main() {
        vec2 q = vW;
        float t = time;
        float n = sin(q.x * 0.9 + t * 0.8) + sin(q.y * 1.2 - t * 0.7) + sin((q.x + q.y) * 0.6 + t * 0.5) + sin(length(q - rect.xy) * 1.3 - t * 1.2);
        vec3 c = mix(deep, mid, smoothstep(-3.0, 2.5, n));
      #if STYLE == 0
        float l = abs(fract(q.x * 0.33 + sin(q.y * 0.5 + t * 0.6) * 0.45 + t * 0.12) - 0.5);
        c = mix(c, foam, (1.0 - smoothstep(0.0, 0.035, l)) * 0.4);
        c = mix(c, foam, smoothstep(2.6, 3.0, n) * 0.8);
      #elif STYLE == 1
        // 독늪: 칸마다 부풀었다 터지는 거품 방울 고리 + 짙은 찌꺼기 얼룩
        c = mix(c, deep * 0.7, smoothstep(0.5, 1.8, sin(q.x * 0.5 - t * 0.2) + sin(q.y * 0.6 + t * 0.15)) * 0.5);
        vec2 cell = floor(q * 0.9);
        vec2 f = fract(q * 0.9) - 0.5;
        float rnd = hash(cell);
        vec2 ctr = vec2(hash(cell + 3.1), hash(cell + 7.7)) - 0.5;
        float life = fract(t * (0.25 + rnd * 0.35) + rnd);
        float rad = life * 0.32;
        float ring = 1.0 - smoothstep(0.0, 0.04, abs(length(f - ctr * 0.5) - rad));
        c = mix(c, foam, ring * (1.0 - life) * step(0.35, rnd));
      #elif STYLE == 2
        // 에너지: 가운데에서 퍼져 나가는 빛 띠 + 반짝임
        float d0 = length(q - rect.xy);
        float band = pow(0.5 + 0.5 * sin(d0 * 1.6 - t * 2.4 + n * 0.4), 6.0);
        c = mix(c, foam, band * 0.7);
        float sp = step(0.985, hash(floor(q * 4.0) + floor(t * 6.0)));
        c = mix(c, vec3(1.0), sp * 0.8);
      #else
        // 번개 구름: 소용돌이 구름 + 가끔 번쩍이는 갈래 번개
        vec2 rel = q - rect.xy;
        float ang = atan(rel.y, rel.x);
        float sw = sin(ang * 3.0 + length(rel) * 0.5 - t * 0.6) + sin(ang * 5.0 - length(rel) * 0.3 + t * 0.4);
        c = mix(deep, mid, smoothstep(-2.0, 2.0, sw + n * 0.5));
        float flash = pow(max(0.0, sin(t * 1.7) * sin(t * 2.9 + 1.3)), 10.0);
        float zig = abs(sin(q.x * 0.8 + sin(q.y * 2.3 + floor(t * 3.0)) * 1.4));
        c = mix(c, foam, (1.0 - smoothstep(0.0, 0.06, zig)) * (0.25 + flash * 0.75));
        c += foam * flash * 0.25;
      #endif
        vec2 dd = abs(q - rect.xy) - rect.zw;
        float dist = length(max(dd, 0.0)) + min(max(dd.x, dd.y), 0.0);
        float edge = 0.45 + 0.18 * sin(t * 2.2 + q.x * 1.9 + q.y * 1.6);
        c = mix(c, foam, (1.0 - smoothstep(edge * 0.6, edge, abs(dist))) * 0.95);
        gl_FragColor = vec4(c, 1.0);
        #include <colorspace_fragment>
      }`,
  }));
}

// 아래 구름 바다: 넓은 원판, 끝으로 갈수록 투명해져 하늘에 녹아듦 (판 끝이 지평선에 곡선으로 보이지 않게)
function seaMaterial(color, inner, outer) {
  return noOutline(new THREE.ShaderMaterial({
    transparent: true,
    depthWrite: false,
    uniforms: { color: { value: new THREE.Color(color) }, inner: { value: inner }, outer: { value: outer } },
    vertexShader: `varying vec2 vP; void main() { vP = position.xy; gl_Position = projectionMatrix * modelViewMatrix * vec4(position, 1.0); }`,
    fragmentShader: `uniform vec3 color; uniform float inner; uniform float outer; varying vec2 vP;
      void main() { gl_FragColor = vec4(color, 1.0 - smoothstep(inner, outer, length(vP))); }`,
  }));
}

// 떠다니는 빛 (반딧불·불씨·금가루) 한 점 그림: 가운데 밝은 동그라미
let dotTex = null;
function dotTexture() {
  if (dotTex) return dotTex;
  const c = document.createElement('canvas');
  c.width = c.height = 32;
  const ctx = c.getContext('2d');
  const g = ctx.createRadialGradient(16, 16, 0, 16, 16, 16);
  g.addColorStop(0, 'rgba(255,255,255,1)');
  g.addColorStop(0.35, 'rgba(255,255,255,0.8)');
  g.addColorStop(1, 'rgba(255,255,255,0)');
  ctx.fillStyle = g;
  ctx.fillRect(0, 0, 32, 32);
  dotTex = new THREE.CanvasTexture(c);
  return dotTex;
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
      sky: Object.fromEntries(['top', 'mid', 'horizon', 'below', 'sunDir', 'glow', 'disc'].map((k) => [k, u[k].value.clone()])),
      discSize: u.discSize.value,
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
    this.motes = null; // 떠다니는 빛 { points, base, speed, rise }
  }

  // 위험(용암 자리) 모습: 테마가 있으면 그 값, 없으면 null (render.js 가 예전 용암 색). 용암 테마는 빛·입자만
  get hazard() {
    return this.look ? this.look.hazard : null;
  }

  // 매 프레임: 맵이 바뀌면 테마를 갈아 끼우고, 먼 섬·구름을 천천히 돌리고, 떠다니는 빛을 움직임
  update(state, dt) {
    const id = (state && state.map && C.WORLD_MAP_THEME[state.map.id]) || null;
    if (id !== this.id) this.apply(id);
    if (!this.look) return;
    this.drift.rotation.z += dt * C.WORLD_DRIFT_SPEED;
    const m = this.motes;
    if (m) {
      const t = performance.now() / 1000;
      const p = m.points.geometry.attributes.position;
      const top = this.r.H * 0.6;
      for (let i = 0; i < p.count; i++) {
        const [bx, by, bz, ph] = m.base[i];
        if (m.rise) {
          // 불씨: 위로 올라가다 맨 위에서 아래로 다시
          const z = ((bz + t * m.speed * (0.6 + ph)) % top + top) % top - 2;
          p.setXYZ(i, bx + Math.sin(t * 0.8 + ph * 9) * 0.4, by + Math.cos(t * 0.7 + ph * 7) * 0.4, z);
        } else {
          p.setXYZ(i, bx + Math.sin(t * 0.5 + ph * 9) * 0.8, by + Math.cos(t * 0.43 + ph * 7) * 0.8, bz + Math.sin(t * 0.9 + ph * 5) * 0.5);
        }
      }
      p.needsUpdate = true;
      m.points.material.opacity = 0.65 + 0.35 * Math.sin(t * 2.3);
    }
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
      for (const k of Object.keys(b.sky)) u[k].value.copy(b.sky[k]);
      u.discSize.value = b.discSize;
      u.stars.value = 0;
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
      const sky = L.sky;
      for (const k of ['top', 'mid', 'horizon', 'below']) u[k].value.set(sky[k]);
      u.sunDir.value.set(...L.sunDir).normalize();
      const v3 = (c, dflt) => (c === undefined ? dflt.clone() : new THREE.Vector3().setFromColor(new THREE.Color(c)));
      u.glow.value.copy(v3(sky.glow, b.sky.glow));
      u.disc.value.copy(v3(sky.disc, b.sky.disc));
      u.discSize.value = sky.discSize ?? b.discSize;
      u.stars.value = sky.stars || 0;
      r.scene.background.set(sky.horizon);
      r.scene.fog.color.set(L.fog[0]);
      [r.scene.fog.near, r.scene.fog.far] = [L.fog[1], L.fog[2]];
      r.hemi.color.set(L.hemi[0]);
      r.hemi.groundColor.set(L.hemi[1]);
      r.hemi.intensity = L.hemi[2];
      r.sun.color.set(L.sunColor);
      r.sun.intensity = L.sunIntensity;
      r.sunDir = L.sunDir;
      // 지형 블록: 윗면·옆면·밑면 따로 (BoxGeometry 면 순서 +x −x +y −y +z −z). 인스턴스 색은 흰색으로 (재질 색 그대로).
      // 빛나는 금·수정은 발광 지도 (밤에도 어둡게 안 묻힘)
      const mk = (map) => noOutline(toon(map.userData.glow ? { map, emissive: 0xffffff, emissiveMap: map.userData.glow } : { map }));
      const side = mk(blockFace(L.terrain, 'side'));
      const top = mk(blockFace(L.terrain, 'top'));
      const bottom = mk(blockFace(L.terrain, 'bottom'));
      r.blockMeshes.terrain.material = [side, side, side, side, top, bottom];
      r.terrainColor = 0xffffff;
      // 바닥 판: 윗면 체크무늬, 옆면(두께 0.3)은 테두리 색
      const ft = floorTexture(L.floor);
      const floorTop = toon(ft.userData.glow ? { map: ft, emissive: 0xffffff, emissiveMap: ft.userData.glow } : { map: ft });
      const rim = toon({ color: L.floor.rim });
      r.floor.material = [rim, rim, rim, rim, floorTop, rim];
      this.floorTop = floorTop;
      const h = L.hazard;
      if (h.style === 'lava') {
        r.lavaTop.material = b.lavaTop; // 예전 용암 그대로 (빛·입자 색만 테마)
        r.lava.material.color.copy(b.lavaBody);
      } else {
        r.lavaTop.material = hazardMaterial(h);
        r.lava.material.color.set(h.deep);
        this.mats.push(r.lavaTop.material);
      }
      r.lavaLight.color.set(h.light[0]);
      r.edges.material.opacity = L.edgeOpacity;
      this.mats.push(side, top, bottom, floorTop, rim);
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
    this.motes = null;
    if (r.gridLines) r.gridLines.visible = !L;
    if (!L) return;
    const w = r.W;
    const d = r.D;
    const cx = w / 2;
    const cy = d / 2;
    this.floorTop.map.repeat.set(w / 2, d / 2);
    this.floorTop.emissiveMap?.repeat.set(w / 2, d / 2);
    if (r.lavaTop.material.uniforms.rect) r.lavaTop.material.uniforms.rect.value.set(cx, cy, w / 2, d / 2);
    const rand = rng(L.seed);
    const k = this.low ? C.WORLD_LOW_DETAIL : 1;
    // 필드 아래 섬 (윗면은 바닥 판 바로 아래)
    const island = new THREE.Mesh(islandGeometry(w, d, Math.max(w, d) * 0.85, L.seed, L.cliff), toon({ vertexColors: true, flatShading: true }));
    island.position.set(cx, cy, -0.3);
    island.receiveShadow = true;
    this.group.add(island);
    // 섬 뿌리에 매달린 바위 + 먼 섬 (한 메시) + 빛나는 소품 (한 메시)
    const near = { solid: new Parts(), glow: new Parts() };
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
    const add = (mesh, parent = this.drift) => mesh && parent.add(mesh);
    add(near.solid.mesh(noOutline(toon({ vertexColors: true, flatShading: true }))));
    add(near.glow.mesh(noOutline(new THREE.MeshBasicMaterial({ vertexColors: true }))));
    // 구름은 스스로 조금 빛나게 (그늘 쪽이 흙색으로 칙칙해지지 않게)
    add(sky.mesh(noOutline(toon({ vertexColors: true, flatShading: true, emissive: shade(L.cloud, L.cloudGlow ?? 0.45) }))));
    this.drift.position.set(cx, cy, 0);
    // 구름 바다: 아래를 가리는 넓은 판 (낮은 구름이 반쯤 잠기고, 먼 산 밑동이 묻힘). 끝은 투명하게 하늘로
    const sea = new THREE.Mesh(new THREE.CircleGeometry(C.WORLD_SEA_FADE[1], 48), seaMaterial(L.sea[0], ...C.WORLD_SEA_FADE));
    sea.position.set(cx, cy, L.sea[1]);
    sea.renderOrder = -0.5; // 하늘 다음, 나머지 전
    this.group.add(sea);
    // 먼 배경: 안개 없이 (멀리서도 실루엣)
    const far = { solid: new Parts(), glow: new Parts() };
    farShapes(far, L, rand, cx, cy, Math.round(L.far.count * (this.low ? 0.6 : 1)));
    add(far.solid.mesh(noOutline(new THREE.MeshLambertMaterial({ vertexColors: true, flatShading: true, fog: false }))), this.group);
    add(far.glow.mesh(noOutline(new THREE.MeshBasicMaterial({ vertexColors: true, fog: false }))), this.group);
    // 떠다니는 빛: 필드 둘레 (반딧불은 떠돌고, 불씨는 위로)
    if (L.motes) {
      const n = Math.round(L.motes.count * k);
      const pos = new Float32Array(n * 3);
      const base = [];
      for (let i = 0; i < n; i++) {
        const bx = cx + (rand() - 0.5) * (w + 10);
        const by = cy + (rand() - 0.5) * (d + 10);
        const bz = rand() * (L.motes.rise ? r.H * 0.6 : 7) + (L.motes.rise ? 0 : 0.5);
        base.push([bx, by, bz, rand()]);
        pos.set([bx, by, bz], i * 3);
      }
      const geo = new THREE.BufferGeometry();
      geo.setAttribute('position', new THREE.BufferAttribute(pos, 3));
      const mat = noOutline(new THREE.PointsMaterial({ color: L.motes.color, size: L.motes.size, map: dotTexture(), transparent: true, depthWrite: false, blending: THREE.AdditiveBlending, fog: false }));
      const points = new THREE.Points(geo, mat);
      points.frustumCulled = false;
      this.group.add(points);
      this.motes = { points, base, speed: L.motes.speed || 1, rise: !!L.motes.rise };
    }
  }
}
