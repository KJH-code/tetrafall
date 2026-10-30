// 건축가 블록 그리기 (2026-10-30 재혁 시안 A '공사장 나무 상자'): 부품(판자 상자·쇠 모서리·공사 줄무늬 띠·R 빛 판·묶음 쇠 띠)마다 InstancedMesh 하나.
// 칸 수가 늘어도 그리기 수는 그대로. 주인 색은 띠의 instanceColor, 금·하얀 깜빡임은 칸마다 값(aCrack·aFlash)을 셰이더가 읽음.
// 모양·곡선 순수 계산은 shared/bblock-look.js, 어느 칸을 어떤 상태로 그릴지는 render.js updateBBlocks 가 정함
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { outlineInstancing } from '/instpool.js';
import { bblockParts } from '/shared/bblock-look.js';

// ---------- 코드 텍스처 ----------
function canvasTex(n, draw) {
  const cv = document.createElement('canvas');
  cv.width = cv.height = n;
  draw(cv.getContext('2d'), n);
  const t = new THREE.CanvasTexture(cv);
  t.colorSpace = THREE.SRGBColorSpace;
  t.anisotropy = 4;
  return t;
}
function rng(seed) {
  let s = seed;
  return () => ((s = (s * 16807) % 2147483647) / 2147483647);
}
const shade = (c, k) => `rgb(${[16, 8, 0].map((sh) => Math.min(255, Math.max(0, ((c >> sh) & 255) * k)) | 0).join(',')})`;

// 판자: 가로(세로) 판 4장, 결, 틈, 못, (버팀목 대각선)
export function planksTexture(base, vertical = false, brace = true, seed = 7) {
  const r = rng(seed);
  return canvasTex(64, (g, n) => {
    g.fillStyle = shade(base, 1);
    g.fillRect(0, 0, n, n);
    const boards = 4;
    for (let i = 0; i < boards; i++) {
      const a = (i * n) / boards;
      g.fillStyle = shade(base, 0.86 + r() * 0.24);
      if (vertical) g.fillRect(a + 1, 0, n / boards - 2, n);
      else g.fillRect(0, a + 1, n, n / boards - 2);
      g.strokeStyle = shade(base, 0.7);
      g.lineWidth = 1;
      for (let k = 0; k < 3; k++) {
        const o = a + 3 + r() * (n / boards - 6);
        g.beginPath();
        if (vertical) {
          g.moveTo(o, 0);
          g.lineTo(o + (r() - 0.5) * 3, n);
        } else {
          g.moveTo(0, o);
          g.lineTo(n, o + (r() - 0.5) * 3);
        }
        g.stroke();
      }
      g.fillStyle = shade(base, 0.45);
      if (vertical) g.fillRect(a, 0, 1.5, n);
      else g.fillRect(0, a, n, 1.5);
    }
    if (brace) {
      g.strokeStyle = shade(base, 0.62);
      g.lineWidth = 9;
      g.beginPath();
      g.moveTo(4, n - 4);
      g.lineTo(n - 4, 4);
      g.stroke();
      g.strokeStyle = shade(base, 1.08);
      g.lineWidth = 6;
      g.stroke();
    }
    g.fillStyle = '#3a3a3a';
    for (const [x, y] of [[6, 6], [n - 6, 6], [6, n - 6], [n - 6, n - 6]]) {
      g.beginPath();
      g.arc(x, y, 1.6, 0, Math.PI * 2);
      g.fill();
    }
    g.strokeStyle = shade(base, 0.4);
    g.lineWidth = 3;
    g.strokeRect(1.5, 1.5, n - 3, n - 3);
  });
}

// 공사 줄무늬: 흰·검정 사선 (흰 부분에 주인 색이 곱해짐)
function stripesTexture() {
  const t = canvasTex(64, (g, n) => {
    g.fillStyle = '#ffffff';
    g.fillRect(0, 0, n, n);
    g.fillStyle = '#16161a';
    for (let x = -n; x < n * 2; x += 20) {
      g.beginPath();
      g.moveTo(x, n);
      g.lineTo(x + 10, n);
      g.lineTo(x + 10 + n, 0);
      g.lineTo(x + n, 0);
      g.fill();
    }
  });
  t.wrapS = t.wrapT = THREE.RepeatWrapping;
  t.repeat.set(...C.BB_LOOK.stripeRepeat);
  return t;
}

// 금 무늬 가리개: 금 선의 밝기 = 그 금이 나타나는 때 (가운데 어두움 = 먼저 → 바깥 밝음 = 나중). 셰이더가 '밝기 < 금 정도' 인 곳을 어둡게
function crackMask() {
  const r = rng(91);
  const t = canvasTex(64, (g, n) => {
    g.fillStyle = '#ffffff';
    g.fillRect(0, 0, n, n);
    g.lineJoin = 'bevel';
    for (const [ex, ey] of [[0.04, 0.22], [0.96, 0.12], [0.86, 0.96], [0.1, 0.88], [0.5, 0.02], [0.98, 0.6]]) {
      let px = n / 2;
      let py = n / 2;
      const steps = 6;
      for (let k = 1; k <= steps; k++) {
        const u = k / steps;
        const x = n * (0.5 + (ex - 0.5) * u) + (r() - 0.5) * 6;
        const y = n * (0.5 + (ey - 0.5) * u) + (r() - 0.5) * 6;
        const v = Math.round(20 + 225 * ((k - 1) / steps)); // 바깥 마디일수록 늦게
        g.strokeStyle = `rgb(${v},${v},${v})`;
        g.lineWidth = 3.2 - u * 1.4;
        g.beginPath();
        g.moveTo(px, py);
        g.lineTo(x, y);
        g.stroke();
        px = x;
        py = y;
      }
    }
  });
  t.colorSpace = THREE.NoColorSpace;
  return t;
}

// 판자·쇠 재질에 칸마다 금(aCrack)·하얀 번쩍(aFlash)
function patchCrack(mat, crackTex, crack) {
  mat.onBeforeCompile = (sh) => {
    if (crack) sh.uniforms.bbCrackMap = { value: crackTex };
    sh.vertexShader = 'attribute float aCrack;\nattribute float aFlash;\nvarying float vBbCrack;\nvarying float vBbFlash;\n' + sh.vertexShader.replace('#include <begin_vertex>', '#include <begin_vertex>\n\tvBbCrack = aCrack;\n\tvBbFlash = aFlash;');
    let f = 'varying float vBbCrack;\nvarying float vBbFlash;\n' + (crack ? 'uniform sampler2D bbCrackMap;\n' : '') + sh.fragmentShader;
    if (crack) f = f.replace('#include <map_fragment>', '#include <map_fragment>\n\tif (texture2D(bbCrackMap, vMapUv).r < vBbCrack * 0.97) diffuseColor.rgb *= 0.22;'); // 0.97: 바탕(흰 1.0)은 금이 다 퍼져도 안 어두워짐
    sh.fragmentShader = f.replace('#include <emissivemap_fragment>', '#include <emissivemap_fragment>\n\ttotalEmissiveRadiance += vec3(vBbFlash);');
  };
  mat.customProgramCacheKey = () => (crack ? 'bbCrack' : 'bbFlash');
  return mat;
}

// 한 부품 묶음 = InstancedMesh 하나 (모자라면 두 배로 다시 만듦). 판자·쇠는 칸마다 금·번쩍 값
class PartPool {
  constructor(scene, mat, { flash = false, color = false, castShadow = true } = {}) {
    this.scene = scene;
    this.mat = mat;
    this.flash = flash;
    this.color = color;
    this.castShadow = castShadow;
    this.im = null;
    this.n = 0;
  }

  make(cap) {
    if (this.im) {
      this.scene.remove(this.im);
      this.im.geometry.dispose();
      this.im.dispose();
    }
    const geo = new THREE.BoxGeometry(1, 1, 1); // 묶음마다 따로 (칸마다 값이 도형에 붙어서)
    if (this.flash) {
      geo.setAttribute('aCrack', new THREE.InstancedBufferAttribute(new Float32Array(cap), 1).setUsage(THREE.DynamicDrawUsage));
      geo.setAttribute('aFlash', new THREE.InstancedBufferAttribute(new Float32Array(cap), 1).setUsage(THREE.DynamicDrawUsage));
    }
    const im = new THREE.InstancedMesh(geo, this.mat, cap);
    im.frustumCulled = false;
    im.castShadow = this.castShadow;
    im.receiveShadow = true;
    im.onBeforeRender = outlineInstancing;
    if (this.color) {
      im.setColorAt(0, new THREE.Color(1, 1, 1));
      im.instanceColor.setUsage(THREE.DynamicDrawUsage);
    }
    im.count = 0;
    this.scene.add(im);
    this.im = im;
  }

  begin() {
    this.n = 0;
  }

  add(matrix, color, crack = 0, flash = 0) {
    if (!this.im || this.n >= this.im.instanceMatrix.count) {
      const old = this.im;
      const keep = old ? { m: old.instanceMatrix.array.slice(0, this.n * 16), c: old.instanceColor ? old.instanceColor.array.slice(0, this.n * 3) : null, k: this.flash ? old.geometry.attributes.aCrack.array.slice(0, this.n) : null, f: this.flash ? old.geometry.attributes.aFlash.array.slice(0, this.n) : null } : null;
      this.make(Math.max(C.INSTANCE_POOL_MIN, (old ? old.instanceMatrix.count : 0) * 2));
      if (keep) {
        this.im.instanceMatrix.array.set(keep.m);
        if (keep.c) this.im.instanceColor.array.set(keep.c);
        if (keep.k) this.im.geometry.attributes.aCrack.array.set(keep.k);
        if (keep.f) this.im.geometry.attributes.aFlash.array.set(keep.f);
      }
    }
    const i = this.n++;
    this.im.setMatrixAt(i, matrix);
    if (this.color && color) this.im.setColorAt(i, color);
    if (this.flash) {
      this.im.geometry.attributes.aCrack.array[i] = crack;
      this.im.geometry.attributes.aFlash.array[i] = flash;
    }
  }

  end() {
    if (!this.im) return;
    this.im.count = this.n;
    this.im.visible = this.n > 0;
    this.im.instanceMatrix.needsUpdate = true;
    if (this.im.instanceColor) this.im.instanceColor.needsUpdate = true;
    if (this.flash) {
      this.im.geometry.attributes.aCrack.needsUpdate = true;
      this.im.geometry.attributes.aFlash.needsUpdate = true;
    }
  }
}

const _m = new THREE.Matrix4();
const _p = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _v = new THREE.Vector3();
const _s = new THREE.Vector3();
const _axis = new THREE.Vector3();
const _plate = new THREE.Color();

export class BuilderBlocks {
  constructor(scene) {
    this.scene = scene;
    const L = C.BB_LOOK;
    const crack = crackMask();
    this.textures = { wood: planksTexture(L.wood), woodPad: planksTexture(L.woodPad, true, false, 11), woodBig: planksTexture(L.woodBig, false, true, 13) };
    const wood = (k) => patchCrack(toon({ map: this.textures[k] }), crack, true);
    this.pools = {
      wood: new PartPool(scene, wood('wood'), { flash: true }),
      woodPad: new PartPool(scene, wood('woodPad'), { flash: true }),
      woodBig: new PartPool(scene, wood('woodBig'), { flash: true }),
      corner: new PartPool(scene, patchCrack(toon({ color: L.steel }), crack, false), { flash: true }),
      band: new PartPool(scene, toon({ map: stripesTexture() }), { color: true }),
      plate: new PartPool(scene, noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff })), { color: true, castShadow: false }),
      strap: new PartPool(scene, toon({ color: 0x3a3a44 }), { castShadow: false }),
    };
    this.parts = Object.fromEntries(['wall', 'pad', 'third', 'big'].map((k) => [k, bblockParts(k)]));
  }

  // items: [{ x, y, z, kind, color (THREE.Color 띠 색), sx, sz, sink, tilt, tiltDir (라디안), crack 0~1, flash 0~1, glow 0~1 (R 빛 판) }]
  // straps: [{ x, y, z (칸 위 가운데), dx, dy }] 같은 묶음 이웃 칸 윗면 이음매 쇠 띠
  draw(items, straps = []) {
    for (const p of Object.values(this.pools)) p.begin();
    const L = C.BB_LOOK;
    for (const b of items) {
      const parts = this.parts[b.kind] || this.parts.wall;
      // 칸 바닥 가운데 → 기울기(바닥 모서리 기준) → 부풂·높이
      _axis.set(-Math.sin(b.tiltDir || 0), Math.cos(b.tiltDir || 0), 0);
      _q.setFromAxisAngle(_axis, b.tilt || 0);
      _p.compose(_v.set(b.x + 0.5, b.y + 0.5, b.z - (b.sink || 0)), _q, _s.set(b.sx || 1, b.sx || 1, b.sz ?? 1));
      for (const pt of parts) {
        _m.makeScale(pt.size[0], pt.size[1], pt.size[2]).setPosition(pt.at[0], pt.at[1], pt.at[2]);
        _m.premultiply(_p);
        if (pt.part === 'base') this.pools[pt.mat].add(_m, null, b.crack || 0, b.flash || 0);
        else if (pt.part === 'corner') this.pools.corner.add(_m, null, 0, b.flash || 0);
        else if (pt.part === 'band') this.pools.band.add(_m, b.flash ? _plate.copy(b.color).lerp(new THREE.Color(1, 1, 1), b.flash) : b.color);
        else if (pt.part === 'plate') {
          const g = b.glow || 0;
          _plate.setHex(L.plateCold).lerp(new THREE.Color(L.plateHot), Math.min(1, g * 1.4));
          if (g > 0.7) _plate.lerp(new THREE.Color(L.plateWhite), (g - 0.7) / 0.3);
          this.pools.plate.add(_m, _plate);
        }
      }
    }
    for (const s of straps) {
      _m.makeScale(s.dx ? 0.55 : 0.16, s.dy ? 0.55 : 0.16, 0.06).setPosition(s.x, s.y, s.z);
      this.pools.strap.add(_m);
    }
    for (const p of Object.values(this.pools)) p.end();
  }

  // 지금 그리는 InstancedMesh 수 (확인용)
  meshCount() {
    return Object.values(this.pools).filter((p) => p.im && p.im.visible).length;
  }
}
