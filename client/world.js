// 맵 테마 (TABS 식 저폴리 자연, 모습만 — 규칙·지형 칸은 그대로). 맵 id → 테마는 config WORLD_MAP_THEME, 테마 값은 WORLD_THEMES.
// 표에 없는 맵(과 대기실)은 예전 노을 그대로. 테마가 있으면:
// 하늘·안개·조명 색(밤이면 별·달) / 바닥(2칸 체크 + 얇은 칸 선) / 지형 블록 재질(윗면·옆면, 빛나는 금·수정) / 필드 아래 떠 있는 섬(절벽 + 바위 뿌리) /
// 먼 배경 3층(가까운 작은 섬·구름 바다·먼 산) / 떠다니는 빛(반딧불·불씨·금가루). 위험(용암 자리) 모습은 hazard.js (테마의 hazard 값).
import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { CELL } from '/shared/pieces.js';

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

// 칸 위치 → 0~1 (같은 칸은 늘 같은 값). salt 로 여러 갈래
export function cellHash(x, y, z, salt = 0) {
  let h = (x * 374761393 + y * 668265263 + z * 2147483647 + salt * 1442695041) | 0;
  h = Math.imul(h ^ (h >>> 13), 1274126177);
  h ^= h >>> 16;
  return (h >>> 0) / 4294967296;
}

// 보로노이 판 (용암 껍질·현무암 기둥·수정 바탕 돌): 칸 안 점 몇 개에서 가장 가까운 점으로 칠하고,
// 가장 가까운 두 점 거리 차가 작은 곳이 금 (판 경계). sy < 1 이면 세로로 긴 판 (현무암 기둥 결)
function voronoi(n, r, count, sy) {
  const pts = [];
  for (let i = 0; i < count; i++) pts.push([r() * n, r() * n]);
  const near = new Int16Array(n * n);
  const edge = new Float32Array(n * n);
  for (let y = 0; y < n; y++) {
    for (let x = 0; x < n; x++) {
      let d1 = 1e9;
      let d2 = 1e9;
      let i1 = 0;
      pts.forEach(([px, py], i) => {
        const dx = x - px;
        const dy = (y - py) * sy;
        const d = Math.sqrt(dx * dx + dy * dy);
        if (d < d1) {
          d2 = d1;
          d1 = d;
          i1 = i;
        } else if (d < d2) d2 = d;
      });
      near[y * n + x] = i1;
      edge[y * n + x] = d2 - d1;
    }
  }
  return { near, edge };
}

// 캔버스에 쓸 sRGB 0~255 (THREE.Color 안쪽 값은 선형이라 그대로 쓰면 어두워짐)
const rgb = (c) => {
  const o = {};
  new THREE.Color(c).getRGB(o, THREE.SRGBColorSpace);
  return [o.r * 255, o.g * 255, o.b * 255];
};

// 현무암 / 식은 용암 껍질: 판마다 색이 조금씩 다르고 (식은 정도), 판 경계가 거미줄 같은 금. 금 일부는 빛나며 둘레로 빛이 번짐
function basaltFace(ctx, gctx, n, r, t, face) {
  const side = face !== 'top';
  const count = side ? 7 : 6;
  const { near, edge } = voronoi(n, r, count, side ? 0.35 : 1);
  const base = new THREE.Color(face === 'top' ? t.top : t.side);
  const crust = new THREE.Color(t.crust ?? t.side);
  const shades = Array.from({ length: count }, () => rgb(base.clone().lerp(crust, r() * 0.45).multiplyScalar(0.78 + r() * 0.35)));
  const hot = Array.from({ length: count }, () => r() < (face === 'side' ? 0.3 : 0.18)); // 이 판 둘레 금이 빛남 (적게 — 블록이 용암처럼 보이면 안 됨)
  const glow = rgb(t.glow);
  const core = rgb(new THREE.Color(t.glow).lerp(new THREE.Color(0xffd070), 0.45));
  const img = ctx.createImageData(n, n);
  const gimg = gctx.createImageData(n, n);
  for (let i = 0; i < n * n; i++) {
    const e = edge[i];
    let c = shades[near[i]];
    let g = [0, 0, 0];
    if (hot[near[i]]) {
      const k = Math.exp(-e / 1.8); // 금에서 멀어질수록 빛이 옅어짐
      if (e < 0.9) c = core;
      else c = c.map((v, j) => v + (glow[j] - v) * k * 0.35);
      g = (e < 0.9 ? core : glow).map((v) => v * (e < 0.9 ? 0.9 : k * 0.45));
    } else if (e < 1.2) {
      c = c.map((v) => v * 0.45); // 식은 금: 어두운 선
    } else if (e < 3) {
      c = c.map((v) => v * 0.82);
    }
    img.data.set([c[0], c[1], c[2], 255], i * 4);
    gimg.data.set([g[0], g[1], g[2], 255], i * 4);
  }
  ctx.putImageData(img, 0, 0);
  gctx.putImageData(gimg, 0, 0);
}

// 수정 바탕 돌: 낮은 대비 판 + 비스듬한 면 반사 띠, 그 위에 가장자리에서 솟은 각진 결정 결 (밝은 면·어두운 면·흰 반사 선)
function crystalFace(ctx, gctx, n, r, t, face, v) {
  const { near, edge } = voronoi(n, r, 5, 1);
  const base = new THREE.Color(face === 'top' ? t.top : t.side);
  const shades = Array.from({ length: 5 }, () => rgb(base.clone().multiplyScalar(0.85 + r() * 0.3)));
  const img = ctx.createImageData(n, n);
  for (let i = 0; i < n * n; i++) {
    const s = shades[near[i]];
    const k = edge[i] < 1.2 ? 0.7 : 1;
    img.data.set([s[0] * k, s[1] * k, s[2] * k, 255], i * 4);
  }
  ctx.putImageData(img, 0, 0);
  const band = ctx.createLinearGradient(0, n, n, 0); // 면 반사 띠
  const at = 0.3 + r() * 0.4;
  band.addColorStop(Math.max(0, at - 0.12), 'rgba(255,255,255,0)');
  band.addColorStop(at, 'rgba(220,230,255,0.16)');
  band.addColorStop(Math.min(1, at + 0.12), 'rgba(255,255,255,0)');
  ctx.fillStyle = band;
  ctx.fillRect(0, 0, n, n);
  const shards = [0, 1, 2, 3][v % 4] + (face === 'bottom' ? -1 : 0); // 변형마다 결 수가 다름 (0개짜리도 있음)
  const gl = new THREE.Color(t.glow);
  const col = (k) => hex(gl.clone().multiplyScalar(k));
  for (let s = 0; s < shards; s++) {
    // 가장자리 한 점에서 안쪽으로 뻗는 육각 기둥 실루엣
    const e = Math.floor(r() * 4);
    const u = 8 + r() * (n - 16);
    const [ox, oy, ang] = [[u, n, -Math.PI / 2], [u, 0, Math.PI / 2], [0, u, 0], [n, u, Math.PI]][e];
    const a = ang + (r() - 0.5) * 1.1;
    const len = 16 + r() * 18;
    const w = 4 + r() * 4;
    const dx = Math.cos(a);
    const dy = Math.sin(a);
    const px = -dy * w;
    const py = dx * w;
    const p = (l, sd) => [ox + dx * l + px * sd, oy + dy * l + py * sd];
    const outline = [p(0, -1), p(len * 0.75, -1), p(len, 0), p(len * 0.75, 1), p(0, 1)];
    const lit = [p(0, 0), p(len, 0), p(len * 0.75, 1), p(0, 1)];
    for (const [c, mult] of [[ctx, 1], [gctx, 0.75]]) {
      c.fillStyle = col(0.55 * mult);
      c.beginPath();
      outline.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y)));
      c.closePath();
      c.fill();
      c.fillStyle = col(1.0 * mult);
      c.beginPath();
      lit.forEach(([x, y], i) => (i ? c.lineTo(x, y) : c.moveTo(x, y)));
      c.closePath();
      c.fill();
      c.strokeStyle = `rgba(255,255,255,${0.85 * mult})`;
      c.lineWidth = 1.2;
      c.beginPath();
      c.moveTo(...p(len * 0.1, 0.45));
      c.lineTo(...p(len * 0.8, 0.45));
      c.stroke();
    }
  }
}

// 지형 블록 면: 변형 WORLD_BLOCK_VARIANTS 장을 가로로 이어 붙인 한 장 (칸마다 셰이더가 하나를 고름).
// 테두리를 어둡게 그려 칸 경계가 보이게 (예전 블록과 같은 방식).
// paint: grass(잔디 윗면·흙 옆면) · sandstone/bricks(벽돌) · crystal(수정 결) · basalt(현무암 껍질 + 빛나는 금) · stump(나이테 윗면·나무껍질 옆면)
function blockFace(t, face) {
  const K = C.WORLD_BLOCK_VARIANTS;
  const n = 64;
  const canvas = document.createElement('canvas');
  canvas.width = n * K;
  canvas.height = n;
  const glowCanvas = t.glow ? document.createElement('canvas') : null;
  if (glowCanvas) {
    glowCanvas.width = n * K;
    glowCanvas.height = n;
  }
  for (let v = 0; v < K; v++) {
    // 변형 한 장을 따로 그려서 붙임 (그리기 함수는 0..n 좌표만 씀)
    const one = document.createElement('canvas');
    one.width = one.height = n;
    const ctx = one.getContext('2d');
    let gctx = null;
    let gone = null;
    if (glowCanvas) {
      gone = document.createElement('canvas');
      gone.width = gone.height = n;
      gctx = gone.getContext('2d');
      gctx.fillStyle = '#000';
      gctx.fillRect(0, 0, n, n);
    }
    const r = rng((face === 'top' ? 3 : face === 'side' ? 5 : 9) + v * 101);
    const base = face === 'top' ? t.top : t.side;
    ctx.fillStyle = hex(base);
    ctx.fillRect(0, 0, n, n);
    if (t.paint === 'grass') {
      if (face === 'top') {
        speckle(ctx, 0, 0, n, { paint: 'grass' }, t.top, r);
      } else {
        ctx.fillStyle = hex(shade(t.side, 0.82));
        for (let k = 0; k < 16; k++) ctx.fillRect(r() * n, 18 + r() * (n - 20), 3 + r() * 4, 3 + r() * 3);
        ctx.fillStyle = hex(shade(t.side, 1.12));
        for (let k = 0; k < 3; k++) ctx.fillRect(r() * n, 24 + r() * (n - 28), 4 + r() * 3, 3); // 작은 돌
        if (face === 'side') {
          // 위쪽 띠: 잔디가 흘러내린 들쭉날쭉한 가장자리 (변형마다 길이가 다름)
          ctx.fillStyle = hex(t.top);
          ctx.beginPath();
          ctx.moveTo(0, 0);
          ctx.lineTo(n, 0);
          for (let x = n; x >= 0; x -= 6) ctx.lineTo(x, 9 + r() * 9);
          ctx.closePath();
          ctx.fill();
        }
      }
    } else if (t.paint === 'stump') {
      if (face === 'top') {
        const cx = n / 2 + (r() - 0.5) * 14;
        const cy = n / 2 + (r() - 0.5) * 14;
        const rings = 4 + Math.floor(r() * 3);
        for (let k = rings; k >= 1; k--) {
          ctx.strokeStyle = hex(shade(t.top, 0.76 + (k % 2) * 0.12));
          ctx.lineWidth = 1.5 + r() * 1.5;
          ctx.beginPath();
          ctx.ellipse(cx, cy, k * 5.5, k * (4.6 + r()), r(), 0, Math.PI * 2);
          ctx.stroke();
        }
        if (r() < 0.6) {
          // 마른 금 (가운데에서 바깥으로)
          ctx.strokeStyle = hex(shade(t.top, 0.55));
          ctx.lineWidth = 1.5;
          const a = r() * Math.PI * 2;
          ctx.beginPath();
          ctx.moveTo(cx, cy);
          ctx.lineTo(cx + Math.cos(a) * 26, cy + Math.sin(a) * 26);
          ctx.stroke();
        }
      } else {
        ctx.strokeStyle = hex(shade(t.side, 0.7));
        for (let x = 2 + r() * 4; x < n; x += 6 + r() * 5) {
          ctx.lineWidth = 2 + r() * 2;
          ctx.beginPath();
          ctx.moveTo(x, 0);
          ctx.bezierCurveTo(x + (r() - 0.5) * 8, n / 3, x + (r() - 0.5) * 8, (2 * n) / 3, x + (r() - 0.5) * 6, n);
          ctx.stroke();
        }
        if (r() < 0.4) {
          ctx.fillStyle = hex(shade(t.side, 0.55)); // 옹이
          ctx.beginPath();
          ctx.ellipse(12 + r() * 40, 14 + r() * 36, 4, 6, 0, 0, Math.PI * 2);
          ctx.fill();
        }
      }
    } else if (t.paint === 'basalt') {
      basaltFace(ctx, gctx, n, r, t, face);
    } else if (t.paint === 'crystal') {
      crystalFace(ctx, gctx, n, r, t, face, v);
    } else {
      ctx.fillStyle = hex(shade(base, 0.9));
      for (let k = 0; k < 14; k++) ctx.fillRect(r() * n, r() * n, 2 + r() * 3, 2 + r() * 3);
      bricks(ctx, n, base, face === 'top');
      // 변형마다 벽돌 한두 장 색이 다르거나 금이 감
      if (face !== 'top') {
        const row = Math.floor(r() * 3);
        ctx.fillStyle = hex(shade(base, r() < 0.5 ? 0.86 : 1.08));
        ctx.fillRect(4 + r() * 20, row * (n / 3) + 3, 18, n / 3 - 6);
      }
      if (r() < 0.5) {
        ctx.strokeStyle = hex(shade(base, 0.6));
        ctx.lineWidth = 1.2;
        let x = 10 + r() * 44;
        let y = 6 + r() * 20;
        ctx.beginPath();
        ctx.moveTo(x, y);
        for (let k = 0; k < 3; k++) ctx.lineTo((x += (r() - 0.5) * 14), (y += 6 + r() * 8));
        ctx.stroke();
      }
    }
    ctx.strokeStyle = hex(t.rim);
    ctx.lineWidth = t.paint === 'basalt' || t.paint === 'crystal' ? 3 : 4;
    ctx.strokeRect(2, 2, n - 4, n - 4);
    canvas.getContext('2d').drawImage(one, v * n, 0);
    if (gone) glowCanvas.getContext('2d').drawImage(gone, v * n, 0);
  }
  const tex = toTex(canvas);
  if (glowCanvas) tex.userData.glow = toTex(glowCanvas);
  return tex;
}

// 지형 블록 재질: 칸마다 인스턴스 속성 aVar (변형 번호, 90도 돌림 수, 좌우 뒤집기) 로 이어 붙인 한 장에서 변형을 고르고 돌림.
// uv 는 블록 안 위치·면 방향으로 셰이더가 직접 만듦 (모서리 깎은 블록이라도 면마다 0~1). 옆면은 위아래가 있는 무늬(잔디 띠·벽돌)면 뒤집기만
function blockMaterial(tex, sideRot) {
  const params = tex.userData.glow ? { map: tex, emissive: 0xffffff, emissiveMap: tex.userData.glow } : { map: tex };
  const mat = noOutline(toon(params));
  const K = C.WORLD_BLOCK_VARIANTS;
  mat.onBeforeCompile = (sh) => {
    sh.uniforms.uK = { value: K };
    sh.uniforms.uSideRot = { value: sideRot ? 1 : 0 };
    sh.vertexShader = `attribute vec4 aVar;\nuniform float uK;\nuniform float uSideRot;\n${sh.vertexShader}`.replace(
      '#include <uv_vertex>',
      `#include <uv_vertex>
      vec3 an = abs(normal);
      bool topF = an.z >= an.x && an.z >= an.y;
      vec2 tuv;
      if (topF) tuv = vec2(position.x * sign(normal.z), position.y);
      else if (an.x >= an.y) tuv = vec2(position.y * sign(normal.x), position.z);
      else tuv = vec2(-position.x * sign(normal.y), position.z);
      tuv = clamp(tuv + 0.5, 0.0, 1.0);
      if (aVar.z > 0.5) tuv.x = 1.0 - tuv.x;
      float rot = (topF || uSideRot > 0.5) ? aVar.y : 0.0;
      vec2 cc = tuv - 0.5;
      for (int i = 0; i < 3; i++) if (float(i) < rot) cc = vec2(-cc.y, cc.x);
      tuv = cc + 0.5;
      tuv.x = (clamp(tuv.x, 0.006, 0.994) + aVar.x) / uK;
      #ifdef USE_MAP
      vMapUv = tuv;
      #endif
      #ifdef USE_EMISSIVEMAP
      vEmissiveMapUv = tuv;
      #endif`,
    );
  };
  mat.customProgramCacheKey = () => `tf-block-${K}-${sideRot ? 1 : 0}`;
  return mat;
}

// 블록 위 소품 (드러난 옆면에 붙는 낮은 결정 덩어리 · 깨진 돌 조각). 원점이 붙는 자리, +z 가 바깥으로 뻗는 방향
function decorGeometry(kind) {
  const list = [];
  const push = (g, m) => {
    const x = g.index ? g.toNonIndexed() : g;
    x.deleteAttribute('uv');
    x.applyMatrix4(m);
    list.push(x);
  };
  if (kind === 'crystal') {
    for (const [ox, oy, h, tx, ty] of [[0, 0, 1, 0, 0], [0.32, 0.1, 0.65, 0.35, 0.1], [-0.28, -0.15, 0.55, -0.3, -0.2]]) {
      const m = M().makeTranslation(ox, oy, h * 0.45).multiply(new THREE.Matrix4().makeRotationFromEuler(new THREE.Euler(ty, tx, 0))).multiply(M().makeScale(0.22, 0.22, h * 0.55));
      push(new THREE.OctahedronGeometry(1, 0), m);
    }
  } else {
    for (const [ox, oy, s] of [[0, 0, 0.32], [0.38, 0.12, 0.2], [-0.3, 0.2, 0.17]]) push(new THREE.DodecahedronGeometry(s, 0), M().makeTranslation(ox, oy, s * 0.5).multiply(M().makeScale(1, 0.8, 0.7)));
  }
  const g = mergeGeometries(list);
  g.computeVertexNormals();
  return g;
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
      terrainGeo: r.blockMeshes.terrain.geometry,
      edges: r.edges.material.opacity,
    };
    this.group = new THREE.Group(); // 섬 + 장식 (판 크기·테마가 바뀌면 다시 만듦)
    this.drift = new THREE.Group(); // 천천히 도는 먼 섬·구름
    this.group.add(this.drift);
    r.scene.add(this.group);
    this.mats = [];
    this.motes = null; // 떠다니는 빛 { points, base, speed, rise }
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
    if (this.look) {
      this.layout();
      this.r.gridVersion = -1; // 블록 소품 켜기·끄기
    }
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
    this.clearDecor();
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
      r.blockMeshes.terrain.geometry = b.terrainGeo;
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
      // 빛나는 금·수정은 발광 지도 (밤에도 어둡게 안 묻힘). 칸마다 변형·돌림·뒤집기 (blockMaterial) + 모서리 깎은 모양
      const sideRot = ['crystal', 'basalt'].includes(L.terrain.paint); // 위아래 없는 무늬는 옆면도 돌림
      const side = blockMaterial(blockFace(L.terrain, 'side'), sideRot);
      const top = blockMaterial(blockFace(L.terrain, 'top'), true);
      const bottom = blockMaterial(blockFace(L.terrain, 'bottom'), true);
      r.blockMeshes.terrain.material = [side, side, side, side, top, bottom];
      r.blockMeshes.terrain.geometry = this.blockGeometry();
      r.terrainColor = 0xffffff;
      // 바닥 판: 윗면 체크무늬, 옆면(두께 0.3)은 테두리 색
      const ft = floorTexture(L.floor);
      const floorTop = toon(ft.userData.glow ? { map: ft, emissive: 0xffffff, emissiveMap: ft.userData.glow } : { map: ft });
      const rim = toon({ color: L.floor.rim });
      r.floor.material = [rim, rim, rim, rim, floorTop, rim];
      this.floorTop = floorTop;
      r.edges.material.opacity = L.edgeOpacity;
      this.mats.push(side, top, bottom, floorTop, rim);
    }
    r.hazard.setLook(L ? L.hazard : null); // 상승하는 위험 모습 (hazard.js)
    r.gridVersion = -1; // 지형 블록 색 다시
    r.setField(r.W, r.D, true, r.H); // 해 위치·섬 크기
  }

  // 테마 지형 블록 모양: 모서리 살짝 깎은 상자 (윗면 가운데는 평평 — 서는 자리 그대로) + 칸마다 변형 속성
  blockGeometry() {
    if (!this.blockGeo) {
      const g = new RoundedBoxGeometry(1, 1, 1, 2, C.WORLD_BLOCK_BEVEL);
      const n = this.r.blockMeshes.terrain.instanceMatrix.count;
      this.varAttr = new THREE.InstancedBufferAttribute(new Float32Array(n * 4), 4);
      g.setAttribute('aVar', this.varAttr);
      this.blockGeo = g;
    }
    return this.blockGeo;
  }

  // updateGrid 가 테마 지형 칸마다 부름: n 번째 인스턴스의 변형·돌림·뒤집기를 칸 위치로 정하고, 색(밝기·빛깔)을 조금 흔듦
  cellLook(n, x, y, z, color) {
    if (!this.look) return;
    const t = this.look.terrain;
    this.varAttr.setXYZW(n, Math.floor(cellHash(x, y, z, 1) * C.WORLD_BLOCK_VARIANTS), Math.floor(cellHash(x, y, z, 2) * 4), cellHash(x, y, z, 3) < 0.5 ? 1 : 0, 0);
    const j = t.jitter ?? C.WORLD_BLOCK_JITTER;
    color.multiplyScalar(1 - j + cellHash(x, y, z, 4) * j * 2);
    if (t.tints) color.lerp(new THREE.Color(t.tints[Math.floor(cellHash(x, y, z, 5) * t.tints.length)]), t.tintMix ?? 0.15);
  }

  // updateGrid 끝: 변형 속성 올리고, 드러난 옆면에 블록 소품 (결정 덩어리·깨진 돌) 다시 놓기
  gridDone(grid) {
    if (!this.look) return;
    this.varAttr.needsUpdate = true;
    this.placeDecor(grid);
  }

  placeDecor(grid) {
    const { r } = this;
    const dec = this.look.terrain.decor;
    if (this.decor) for (const m of this.decor) m.count = 0;
    if (!dec || this.low || !grid) return;
    if (!this.decor) {
      const geo = decorGeometry(dec.kind);
      const solid = new THREE.InstancedMesh(geo, toon({ color: 0xffffff, flatShading: true, emissive: dec.kind === 'crystal' ? shade(this.look.terrain.glow, 0.35) : 0x000000 }), C.WORLD_DECOR_MAX);
      const parts = [solid];
      if (dec.kind === 'rubble') {
        // 깨진 돌 틈으로 비치는 빛 (작은 조각)
        parts.push(new THREE.InstancedMesh(new THREE.OctahedronGeometry(0.09, 0), noOutline(new THREE.MeshBasicMaterial({ color: this.look.terrain.glow })), C.WORLD_DECOR_MAX));
      }
      for (const m of parts) {
        m.count = 0;
        m.frustumCulled = false;
        m.castShadow = dec.kind !== 'crystal';
        r.scene.add(m);
      }
      noOutline(solid.material);
      this.decor = parts;
    }
    const { W, D, H } = r;
    const at3 = (x, y, z) => (x < 0 || y < 0 || x >= W || y >= D || z < 0 || z >= H ? 0 : grid[(z * D + y) * W + x]);
    const m = new THREE.Matrix4();
    const q = new THREE.Quaternion();
    const up = new THREE.Vector3(0, 0, 1);
    const col = new THREE.Color();
    const palette = this.look.glow || [this.look.terrain.glow];
    let n = 0;
    const dirs = [[1, 0], [-1, 0], [0, 1], [0, -1]];
    for (let z = 0; z < H && n < C.WORLD_DECOR_MAX; z++) {
      for (let y = 0; y < D && n < C.WORLD_DECOR_MAX; y++) {
        for (let x = 0; x < W && n < C.WORLD_DECOR_MAX; x++) {
          if (grid[(z * D + y) * W + x] !== CELL.TERRAIN || cellHash(x, y, z, 6) > dec.chance) continue;
          const open = dirs.filter(([dx, dy]) => !at3(x + dx, y + dy, z));
          if (!open.length) continue;
          const [dx, dy] = open[Math.floor(cellHash(x, y, z, 7) * open.length)];
          const along = (cellHash(x, y, z, 8) - 0.5) * 0.6; // 면 위 가로 자리
          const h = dec.kind === 'crystal' ? 0.12 + cellHash(x, y, z, 9) * 0.3 : 0.02; // 결정은 옆면 아래~가운데, 돌은 바닥 모서리
          const pos = new THREE.Vector3(x + 0.5 + dx * 0.5 - dy * along, y + 0.5 + dy * 0.5 + dx * along, z + h);
          const out = new THREE.Vector3(dx, dy, 0);
          const dir = dec.kind === 'crystal' ? out.clone().multiplyScalar(0.8).add(new THREE.Vector3(0, 0, 0.6)).normalize() : up;
          q.setFromUnitVectors(up, dir);
          q.multiply(new THREE.Quaternion().setFromAxisAngle(up, cellHash(x, y, z, 10) * Math.PI * 2));
          const s = dec.size[0] + cellHash(x, y, z, 11) * (dec.size[1] - dec.size[0]);
          m.compose(pos, q, new THREE.Vector3(s, s, s));
          this.decor[0].setMatrixAt(n, m);
          col.set(dec.kind === 'crystal' ? palette[Math.floor(cellHash(x, y, z, 12) * palette.length)] : this.look.terrain.side).multiplyScalar(dec.kind === 'crystal' ? 1 : 0.8);
          this.decor[0].setColorAt(n, col);
          if (this.decor[1]) {
            m.compose(pos.clone().add(new THREE.Vector3(0, 0, 0.05)), q, new THREE.Vector3(s, s, s));
            this.decor[1].setMatrixAt(n, m);
          }
          n++;
        }
      }
    }
    for (const mesh of this.decor) {
      mesh.count = n;
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }
  }

  // 테마가 바뀌면 블록 소품을 치움 (다음 updateGrid 에서 새 테마로)
  clearDecor() {
    if (!this.decor) return;
    for (const m of this.decor) {
      this.r.scene.remove(m);
      m.geometry.dispose();
      m.material.dispose();
      m.dispose();
    }
    this.decor = null;
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
