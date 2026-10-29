// 테마 지형 블록 (TABS 저폴리, 2026-10-29 재혁: 주상절리 B): 칸마다 같은 텍스처를 반복하지 않고, 셰이더가 월드 좌표로 색·모양을 정한다.
// - 같은 지형 칸끼리 맞닿은 옆면·모서리는 테두리 없이 이어짐. 겉으로 드러난 모서리만 깎이고 어두워짐 (aOpen: 이웃이 빈 방향)
// - 밟는 윗면만 칸 경계가 살짝 보임 (grid) + 칸마다 조금 오르내림 (step, 기둥)
// - 입체감: 윗면 밝게·옆면 어둡게 (sideShade), 벽 밑·높이 차 그늘 (ao: 위 칸에 블록이 있는 윗면 가장자리, 바닥에 닿은 옆면 아래), 드러난 윗 모서리 하이라이트 (hi)
// - 튀어나온 조각 (BlockDecor): 수정 결정·현무암 기둥 끝·버섯·튀어나온 벽돌·사암 턱·풀 (테마 sprout, 그래픽 낮춤이면 끔)
// - 색: 윗면·옆면·밑면 색 + 여러 칸에 걸친 큰 얼룩(테마 빛깔) + 높이 (아래 어둡게) + 드러난 모서리 닳음 + 테마 결
//   (lip 윗면 색이 옆으로 흘러내림 = 잔디·이끼 · strata 사암 층 · brick 돌벽돌 · veins 용암 금·수정 맥 · sheen 수정 빛 테)
// 판정 칸은 그대로 (화면만). 값 계산은 shared/block-style.js (config WORLD_BLOCK_STYLES + 테마 terrain.block)
import * as THREE from 'three';
import { toon, noOutline } from '/toon.js';
import { cellLooks, sproutSpots, cellRand } from '/shared/block-style.js';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { CONFIG as C } from '/shared/config.js';

const NOISE = /* glsl */ `
float tfHash(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float tfNoise(vec3 x) {
  vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(tfHash(i), tfHash(i + vec3(1,0,0)), f.x), mix(tfHash(i + vec3(0,1,0)), tfHash(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(tfHash(i + vec3(0,0,1)), tfHash(i + vec3(1,0,1)), f.x), mix(tfHash(i + vec3(0,1,1)), tfHash(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float tfFbm(vec3 p) { return 0.5 * tfNoise(p) + 0.3 * tfNoise(p * 2.03 + 7.1) + 0.2 * tfNoise(p * 4.1 + 3.7); }
`;

// 칸 블록 모양: 면마다 나눈 상자 (꼭짓점을 흔들 자리)
export function terrainGeometry(count, segs) {
  const g = new THREE.BoxGeometry(1, 1, 1, segs, segs, segs);
  // 칸마다 (이웃 빈 방향 비트, 그늘 비트, 윗면 높낮이) — shared/block-style.js cellLooks
  g.setAttribute('aCell', new THREE.InstancedBufferAttribute(new Float32Array(count * 3), 3));
  return g;
}

const col = (c) => new THREE.Color(c);

// s = blockStyle(테마 terrain) 결과, low = 그래픽 낮춤 (꼭짓점 흔들기·높낮이 끔)
export function terrainMaterial(s, low) {
  const m = toon({ color: 0xffffff });
  noOutline(m);
  m.defines = { FLAT_SHADED: '' };
  // 얼룩 빛깔은 평균에 대한 비율로 곱함 (바탕 색은 그대로, 칸을 넘어 빛깔·밝기만 흔들림)
  const mean = new THREE.Color();
  for (const t of s.tints) mean.add(col(t).multiplyScalar(1 / 3));
  const rel = (t) => {
    const c = col(t);
    return new THREE.Vector3(c.r / Math.max(mean.r, 0.02), c.g / Math.max(mean.g, 0.02), c.b / Math.max(mean.b, 0.02));
  };
  const brick = s.brick || [1, 1, 0, 0];
  const uniforms = {
    tfTop: { value: col(s.top) },
    tfSide: { value: col(s.side) },
    tfRim: { value: col(s.rim) },
    tfTint0: { value: rel(s.tints[0]) },
    tfTint1: { value: rel(s.tints[1]) },
    tfTint2: { value: rel(s.tints[2]) },
    tfGlow: { value: col(s.glow ?? 0x000000) },
    tfDisp: { value: low ? 0 : s.disp },
    tfChamfer: { value: new THREE.Vector2(s.chamfer[0], s.chamfer[1]) },
    tfStep: { value: low ? 0 : s.step },
    tfBlotch: { value: new THREE.Vector2(s.blotch[0], s.blotch[1]) },
    tfEdge: { value: s.edge },
    tfHeight: { value: new THREE.Vector2(s.height[0], s.height[1]) },
    tfVein: { value: s.veins || 0 },
    tfVeinScale: { value: s.veinScale || 1 },
    tfMottle: { value: s.mottle || 0 },
    tfWear: { value: s.wear || 0 },
    tfTopLift: { value: s.topLift || 1 },
    tfGrid: { value: new THREE.Vector2(s.grid[0], s.grid[1]) },
    tfLip: { value: s.lip || 0 },
    tfStrata: { value: new THREE.Vector2(s.strata[0], s.strata[1]) },
    tfBrick: { value: new THREE.Vector4(...brick) },
    tfSheen: { value: s.sheen || 0 },
    tfSideShade: { value: s.sideShade ?? 1 },
    tfAO: { value: s.ao || 0 },
    tfHi: { value: s.hi || 0 },
  };
  m.userData.tfUniforms = uniforms;
  m.userData.tfStyle = s;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, uniforms);
    sh.vertexShader = sh.vertexShader
      .replace(
        '#include <common>',
        `#include <common>
attribute vec3 aCell;
uniform float tfDisp; uniform vec2 tfChamfer; uniform float tfStep;
varying vec3 vTfW; varying vec3 vTfCell; varying float vTfOpen; varying float vTfAO; varying float vTfLift;
${NOISE}
float tfBit(float m, float b) { return mod(floor(m / b), 2.0); }`,
      )
      .replace(
        '#include <begin_vertex>',
        `#include <begin_vertex>
#ifdef USE_INSTANCING
  vec3 tfCell = (modelMatrix * instanceMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
#else
  vec3 tfCell = (modelMatrix * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
#endif
  float aOpen = aCell.x;
  vTfCell = tfCell; vTfOpen = aOpen; vTfAO = aCell.y; vTfLift = aCell.z * tfStep;
  vec3 tfW0 = tfCell + position; // 흔들기 전 월드 점 (이웃 칸과 같은 점이면 같은 값)
  // 드러난 모서리 깎기: 꼭짓점이 놓인 면 경계 중 이웃이 빈 쪽이 둘 이상이면 그 쪽들로 안으로 당김 (칸마다 크기 다름)
  vec3 ex = vec3(0.0);
  if (position.x > 0.49) ex.x = tfBit(aOpen, 1.0); else if (position.x < -0.49) ex.x = -tfBit(aOpen, 2.0);
  if (position.y > 0.49) ex.y = tfBit(aOpen, 4.0); else if (position.y < -0.49) ex.y = -tfBit(aOpen, 8.0);
  if (position.z > 0.49) ex.z = tfBit(aOpen, 16.0); else if (position.z < -0.49) ex.z = -tfBit(aOpen, 32.0);
  float nEx = abs(ex.x) + abs(ex.y) + abs(ex.z);
  float tfOpenN = tfBit(aOpen, 1.0) + tfBit(aOpen, 2.0) + tfBit(aOpen, 4.0) + tfBit(aOpen, 8.0);
  float ch = mix(tfChamfer.x, tfChamfer.y, tfHash(floor(tfW0 * 2.0 + 0.5) + 3.1)) * (1.0 + 0.25 * tfOpenN);
  if (nEx > 1.5) transformed -= ex * ch;
  // 드러난 윗면은 칸마다 조금 높낮이 (기둥), 꼭짓점은 월드 잡음으로 흔듦 (깎은 돌)
  if (position.z > 0.49 && tfBit(aOpen, 16.0) > 0.5) transformed.z += vTfLift;
  vec3 q = tfW0 * 1.9;
  transformed += (vec3(tfNoise(q), tfNoise(q + 19.7), tfNoise(q + 41.3)) - 0.5) * tfDisp * vec3(1.0, 1.0, 0.6);
  vTfW = tfCell + transformed;`,
      );
    sh.fragmentShader = sh.fragmentShader
      .replace(
        '#include <common>',
        `#include <common>
uniform vec3 tfTop; uniform vec3 tfSide; uniform vec3 tfRim; uniform vec3 tfTint0; uniform vec3 tfTint1; uniform vec3 tfTint2; uniform vec3 tfGlow;
uniform vec2 tfBlotch; uniform float tfEdge; uniform vec2 tfHeight; uniform float tfVein; uniform float tfVeinScale; uniform float tfMottle; uniform float tfWear; uniform float tfTopLift;
uniform vec2 tfGrid; uniform float tfLip; uniform vec2 tfStrata; uniform vec4 tfBrick; uniform float tfSheen; uniform float tfSideShade; uniform float tfAO; uniform float tfHi;
varying vec3 vTfW; varying vec3 vTfCell; varying float vTfOpen; varying float vTfAO; varying float vTfLift;
${NOISE}
float tfBitF(float m, float b) { return mod(floor(m / b + 0.001), 2.0); }
float tfGlowAmt = 0.0;
float tfSheenAmt = 0.0;`,
      )
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
  vec3 tfN = normalize(cross(dFdx(vTfW), dFdy(vTfW)));
  float up = smoothstep(0.55, 0.85, tfN.z);
  bool tfSideFace = up < 0.5 && tfN.z > -0.5;
  vec3 l = vTfW - vTfCell;
  vec3 an = abs(tfN);
  vec3 top = tfTop * tfTopLift;
  // 잔디·이끼: 드러난 윗면 색이 옆면 위쪽으로 물결치며 흘러내림
  float lipD = tfLip * (0.55 + 0.9 * tfNoise(vec3(vTfW.xy * 3.1, 0.0)));
  bool tfLipHere = tfSideFace && tfLip > 0.0 && tfBitF(vTfOpen, 16.0) > 0.5 && l.z > 0.5 + vTfLift - lipD;
  vec3 base = mix(tfSide, top, up);
  if (tfLipHere) base = top * 0.92;
  if (tfN.z < -0.5) base = tfSide * 0.6;
  // 여러 칸에 걸친 큰 얼룩 (테마 빛깔 셋을 평균에 대한 비율로 곱함)
  float b1 = tfFbm(vTfW * tfBlotch.x + 5.0);
  float b2 = tfFbm(vTfW * tfBlotch.x * 0.6 + 31.0);
  vec3 tint = mix(mix(tfTint0, tfTint1, smoothstep(0.35, 0.65, b1)), tfTint2, smoothstep(0.55, 0.75, b2));
  base *= mix(vec3(1.0), tint, tfBlotch.y);
  // 높이: 아래로 갈수록 어둡게
  base *= mix(tfHeight.x, 1.0, clamp(vTfW.z / tfHeight.y, 0.0, 1.0));
  if (tfSideFace && !tfLipHere) {
    // 사암 층: 높이 따라 밝기가 다른 띠 (조금 물결) + 띠 사이 가는 금
    if (tfStrata.y > 0.0) {
      float t = vTfW.z * tfStrata.x + (tfNoise(vTfW * 0.9) - 0.5) * 0.7;
      base *= 1.0 + (tfHash(vec3(floor(t), 3.7, 1.3)) - 0.5) * 2.0 * tfStrata.y;
      base *= 1.0 - tfStrata.y * 1.6 * (1.0 - smoothstep(0.0, 0.07, fract(t)));
    }
    // 돌벽돌 (x 크기, z 높이, 줄눈 두께, 벽돌마다 밝기): 월드 좌표라 칸을 넘어 이어짐, 줄마다 반 칸 어긋남
    if (tfBrick.z > 0.0) {
      float u = an.x > an.y ? vTfW.y : vTfW.x;
      float row = floor(vTfW.z / tfBrick.y);
      float uu = u / tfBrick.x + row * 0.5;
      float fu = fract(uu); float fv = fract(vTfW.z / tfBrick.y);
      float mortar = min(min(fu, 1.0 - fu) * tfBrick.x, min(fv, 1.0 - fv) * tfBrick.y);
      base *= 1.0 + (tfHash(vec3(floor(uu), row, an.x > an.y ? 1.0 : 2.0)) - 0.5) * tfBrick.w;
      base *= mix(0.62, 1.0, smoothstep(tfBrick.z * 0.6, tfBrick.z, mortar));
    }
  }
  // 모서리: 이 면의 테두리 중 이웃이 빈 쪽 (맞닿은 쪽은 이어 보임). dV 옆 테두리 · dT 윗 테두리 · dB 아래 테두리
  float dV = 1.0, dT = 1.0, dB = 1.0;
  if (an.x < 0.7) { if (tfBitF(vTfOpen, 1.0) > 0.5) dV = min(dV, 0.5 - l.x); if (tfBitF(vTfOpen, 2.0) > 0.5) dV = min(dV, 0.5 + l.x); }
  if (an.y < 0.7) { if (tfBitF(vTfOpen, 4.0) > 0.5) dV = min(dV, 0.5 - l.y); if (tfBitF(vTfOpen, 8.0) > 0.5) dV = min(dV, 0.5 + l.y); }
  if (an.z < 0.7) { if (tfBitF(vTfOpen, 16.0) > 0.5) dT = 0.5 + vTfLift - l.z; if (tfBitF(vTfOpen, 32.0) > 0.5) dB = 0.5 + l.z; }
  if (up > 0.5) {
    base = mix(base, base * 1.35 + 0.04, tfWear * (1.0 - smoothstep(0.0, 0.16, dV))); // 윗면 가장자리는 닳아 밝게
    // 밟는 윗면만 칸 경계가 살짝 (맞닿은 칸 사이에도)
    vec2 g = abs(vTfW.xy - floor(vTfW.xy + 0.5));
    float gw = min(g.x, g.y); float aa = fwidth(gw) + 1e-4; // 멀리선 선이 굵어지지 않게 흐리게
    base *= 1.0 - tfGrid.x * clamp(1.5 - 0.5 * aa / tfGrid.y, 0.0, 1.0) * (1.0 - smoothstep(tfGrid.y - aa, tfGrid.y + aa, gw));
    // 그늘: 위 칸에 블록이 있는 쪽 가장자리 (벽 밑)
    float da = 1.0;
    if (tfBitF(vTfAO, 1.0) > 0.5) da = min(da, 0.5 - l.x);
    if (tfBitF(vTfAO, 2.0) > 0.5) da = min(da, 0.5 + l.x);
    if (tfBitF(vTfAO, 4.0) > 0.5) da = min(da, 0.5 - l.y);
    if (tfBitF(vTfAO, 8.0) > 0.5) da = min(da, 0.5 + l.y);
    float ka = 1.0 - smoothstep(0.0, 0.45, da);
    base *= 1.0 - tfAO * ka * ka;
  } else if (tfN.z > -0.5) {
    base *= tfSideShade; // 옆면은 어둡게 (윗면과 확 갈리게)
    base = mix(base, base * 1.25 + 0.03, tfHi * 0.5 * (1.0 - smoothstep(0.0, 0.1, dV))); // 드러난 세로 모서리 살짝 밝게
    base = mix(base, base * 1.6 + 0.07, tfHi * (1.0 - smoothstep(0.0, 0.07, dT))); // 드러난 윗 모서리 하이라이트
    base = mix(base, tfRim, tfEdge * (1.0 - smoothstep(0.0, 0.16, dB))); // 드러난 아래 모서리 어둡게
    // 그늘: 바깥 아래 칸이 막힌 옆면 (바닥·아래 단에 닿음)은 아래쪽 어둡게
    float bit = an.x > an.y ? (tfN.x > 0.0 ? 16.0 : 32.0) : (tfN.y > 0.0 ? 64.0 : 128.0);
    if (tfBitF(vTfAO, bit) > 0.5) { float ka = 1.0 - smoothstep(0.0, 0.55, l.z + 0.5); base *= 1.0 - tfAO * ka * ka; }
  }
  // 면마다·자리마다 조금씩 다른 밝기 (깎은 면이 드러나게, 월드 좌표라 칸 경계와 상관없음)
  base *= 1.0 + (tfNoise(floor(vTfW * 3.0) + 0.5) - 0.5) * tfMottle + (tfNoise(vTfW * 0.7 + 2.0) - 0.5) * tfMottle;
  // 테마 결: 여러 칸에 걸쳐 이어지는 가는 빛 금 (용암·수정)
  if (tfVein > 0.0) {
    float v = tfNoise(vTfW * vec3(0.9, 0.9, 1.3) * tfVeinScale) - 0.5;
    float w = tfNoise(vTfW * 2.3 * tfVeinScale + 13.0) - 0.5;
    tfGlowAmt = (1.0 - smoothstep(0.0, 0.035, abs(v))) * smoothstep(-0.1, 0.15, w) * (1.0 - up * 0.6);
    base = mix(base, tfGlow, tfGlowAmt * tfVein);
  }
  // 수정 빛 테: 비스듬히 보이는 면이 빛 색으로 (결정 면이 반짝)
  if (tfSheen > 0.0) tfSheenAmt = pow(1.0 - abs(dot(tfN, normalize(cameraPosition - vTfW))), 3.0) * tfSheen;
  diffuseColor.rgb *= base;`,
      )
      .replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
  totalEmissiveRadiance += tfGlow * (tfGlowAmt * tfVein + tfSheenAmt);`,
      );
  };
  m.customProgramCacheKey = () => `tfBlocks:${low ? 1 : 0}`;
  return m;
}

// 칸마다 (이웃 빈 방향, 그늘, 높낮이) 를 인스턴스 속성에 (값 계산은 shared/block-style.js cellLooks)
export function terrainCells(attr, grid, W, D, H, skip) {
  const { open, ao, lift } = cellLooks(grid, W, D, H, skip);
  const n = Math.min(open.length, attr.count);
  for (let i = 0; i < n; i++) attr.setXYZ(i, open[i], ao[i], lift[i]);
  attr.needsUpdate = true;
  return open.length;
}

// ---- 튀어나온 조각 (테마 sprout.kind). 조각은 +Z 로 서 있게 만들고, 놓을 때 면 바깥(옆면)·위(윗면) 로 돌림
const M4 = () => new THREE.Matrix4();
function merged(list) {
  const g = mergeGeometries(list.map(([geo, m]) => {
    const x = geo.index ? geo.toNonIndexed() : geo;
    x.deleteAttribute('uv');
    return x.applyMatrix4(m);
  }));
  g.computeVertexNormals();
  return g;
}
const zUp = (g) => g.applyMatrix4(M4().makeRotationX(Math.PI / 2)); // three 원기둥·원뿔은 +Y → +Z
function prism(r, h, tip) {
  return merged([
    [zUp(new THREE.CylinderGeometry(r, r, h, 6)), M4().makeTranslation(0, 0, h / 2)],
    [zUp(new THREE.ConeGeometry(r, tip, 6)), M4().makeTranslation(0, 0, h + tip / 2)],
  ]);
}
const rotXY = (x, y) => M4().makeRotationFromEuler(new THREE.Euler(x, y, 0));

// kind → { parts: [{ geo, color(spot, rnd) , emissive }], tilt: 옆면에서 위로 드는 각, tiltTop: 윗면에서 바깥으로 기우는 각, spin: 돌려 놓기, align: 'brick'|'ledge' }
function sproutKind(kind, s, palette) {
  const pick = (r) => palette[Math.floor(r * palette.length) % palette.length];
  const side = new THREE.Color(s.side);
  const top = new THREE.Color(s.top);
  if (kind === 'crystal') {
    const geo = merged([
      [prism(0.09, 0.42, 0.18), M4().makeTranslation(0, 0, -0.06)],
      [prism(0.07, 0.28, 0.13), M4().makeTranslation(0.1, 0.03, -0.04).multiply(rotXY(0.1, 0.5))],
      [prism(0.06, 0.22, 0.11), M4().makeTranslation(-0.09, -0.05, -0.04).multiply(rotXY(-0.4, -0.35))],
      [prism(0.05, 0.16, 0.09), M4().makeTranslation(0.0, -0.1, -0.03).multiply(rotXY(0.6, 0.0))],
      [prism(0.04, 0.12, 0.07), M4().makeTranslation(-0.05, 0.1, -0.02).multiply(rotXY(-0.2, 0.6))],
    ]);
    return { parts: [{ geo, color: (r) => new THREE.Color(pick(r)), glow: 0.4 }], tilt: 0.45, tiltTop: 0.3, spin: true };
  }
  if (kind === 'basalt') {
    const geo = merged([
      [zUp(new THREE.CylinderGeometry(0.085, 0.085, 0.26, 6)), M4().makeTranslation(0, 0, 0.13)],
      [zUp(new THREE.CylinderGeometry(0.075, 0.075, 0.18, 6)), M4().makeTranslation(0.15, 0.02, 0.09)],
      [zUp(new THREE.CylinderGeometry(0.07, 0.07, 0.12, 6)), M4().makeTranslation(0.06, 0.14, 0.06)],
    ]);
    const lava = merged([[new THREE.OctahedronGeometry(0.05, 0), M4().makeTranslation(0.07, 0.06, 0.02)]]);
    return { parts: [{ geo, color: (r) => side.clone().multiplyScalar(1.5 + r * 0.5) }, { geo: lava, color: () => new THREE.Color(s.glow ?? 0xff7a24), basic: true }], tilt: 0, tiltTop: 0, spin: true };
  }
  if (kind === 'mushroom') {
    const cap = merged([[new THREE.SphereGeometry(0.13, 8, 4, 0, Math.PI * 2, 0, Math.PI / 2), M4().makeTranslation(0, 0, 0.14).multiply(rotXY(Math.PI / 2, 0)).multiply(M4().makeScale(1, 0.75, 1))]]);
    const stem = merged([[zUp(new THREE.CylinderGeometry(0.035, 0.045, 0.16, 6)), M4().makeTranslation(0, 0, 0.08)]]);
    return { parts: [{ geo: cap, color: (r) => new THREE.Color(pick(r)), glow: 0.3 }, { geo: stem, color: () => new THREE.Color(0xe8dcc0) }], tilt: 1.0, tiltTop: 0.15, spin: true };
  }
  if (kind === 'brick') {
    const [w, h] = s.brick || [0.62, 0.333];
    const geo = new THREE.BoxGeometry(w * 0.9, h * 0.82, 0.12).translate(0, 0, 0.02);
    return { parts: [{ geo, color: (r) => side.clone().multiplyScalar((0.72 + r * 0.22) * (s.sideShade ?? 1) / 0.66) }], tilt: 0, tiltTop: 0, align: 'brick' };
  }
  if (kind === 'ledge') {
    const geo = new THREE.BoxGeometry(0.8, 0.08, 0.2).translate(0, 0, 0.04);
    return { parts: [{ geo, color: (r) => side.clone().multiplyScalar((0.8 + r * 0.15) * (s.sideShade ?? 1) / 0.66) }], tilt: 0, tiltTop: 0, align: 'ledge' };
  }
  // tuft: 풀 포기
  const blades = [];
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    blades.push([zUp(new THREE.ConeGeometry(0.022, 0.2 - (i % 2) * 0.05, 4)), M4().makeTranslation(Math.cos(a) * 0.035, Math.sin(a) * 0.035, 0.09).multiply(rotXY(Math.sin(a) * 0.4, -Math.cos(a) * 0.4))]);
  }
  return { parts: [{ geo: merged(blades), color: (r) => top.clone().multiplyScalar(0.8 + r * 0.35) }], tilt: 0.6, tiltTop: 0, spin: true };
}

const FACES = [[1, 0], [-1, 0], [0, 1], [0, -1]];
const cellRandLift = (p) => cellRand(p.x, p.y, p.z, 1) - 0.5; // 셰이더 윗면 높낮이와 같은 값 (cellLooks lift)
export class BlockDecor {
  // s = blockStyle 결과 (sprout 있음), palette = 테마 빛 색들
  constructor(scene, s, palette) {
    this.s = s;
    this.kind = sproutKind(s.sprout.kind, s, palette && palette.length ? palette : [s.glow ?? s.top]);
    this.meshes = this.kind.parts.map((p) => {
      const mat = p.basic ? new THREE.MeshBasicMaterial({ color: 0xffffff }) : toon({ color: 0xffffff, flatShading: true });
      noOutline(mat);
      if (p.glow) {
        // 결정·버섯 갓은 제 색으로 빛남 (인스턴스 색 × glow)
        mat.onBeforeCompile = (sh) => {
          sh.fragmentShader = sh.fragmentShader.replace('#include <emissivemap_fragment>', `#include <emissivemap_fragment>\n totalEmissiveRadiance += diffuseColor.rgb * ${p.glow.toFixed(3)};`);
        };
        mat.customProgramCacheKey = () => `tf-sprout-${p.glow}`;
      }
      const m = new THREE.InstancedMesh(p.geo, mat, C.BLOCK_SPROUT_MAX);
      m.count = 0;
      m.frustumCulled = false;
      m.castShadow = !p.basic && !p.glow;
      scene.add(m);
      return m;
    });
  }

  update(grid, W, D, H, skip, low) {
    const spots = low ? [] : sproutSpots(grid, W, D, H, skip, this.s.sprout, C.BLOCK_SPROUT_MAX);
    const K = this.kind;
    const s = this.s;
    const m = new THREE.Matrix4();
    const X = new THREE.Vector3(), Y = new THREE.Vector3(), Z = new THREE.Vector3();
    const up = new THREE.Vector3(0, 0, 1);
    const col = new THREE.Color();
    spots.forEach((p, i) => {
      const cx = p.x + 0.5, cy = p.y + 0.5;
      const lift = (cellRandLift(p) * s.step);
      let pos;
      if (p.face < 4) {
        const [nx, ny] = FACES[p.face];
        const n = new THREE.Vector3(nx, ny, 0);
        const t = new THREE.Vector3(-ny, nx, 0);
        let u = p.u, zc = p.z + 0.5 + p.v;
        if (K.align === 'brick' && s.brick) {
          // 벽돌 줄에 맞춤 (셰이더 돌벽돌과 같은 격자)
          const [w, h] = s.brick;
          const wu = (p.face < 2 ? p.y + 0.5 : p.x + 0.5) + p.u * (p.face < 2 ? nx : -ny);
          const row = Math.floor(zc / h);
          const id = Math.floor(wu / w + row * 0.5);
          zc = (row + 0.5) * h;
          u = ((id + 0.5 - row * 0.5) * w - (p.face < 2 ? p.y + 0.5 : p.x + 0.5)) * (p.face < 2 ? nx : -ny);
        } else if (K.align === 'ledge' && s.strata[0] > 0) zc = Math.round(zc * s.strata[0]) / s.strata[0];
        pos = new THREE.Vector3(cx, cy, 0).addScaledVector(n, 0.5).addScaledVector(t, u).setZ(Math.min(zc, p.z + 0.9));
        Z.copy(n).multiplyScalar(Math.cos(K.tilt)).addScaledVector(up, Math.sin(K.tilt)).normalize();
        X.copy(t);
      } else {
        pos = new THREE.Vector3(cx + p.u, cy + p.v, p.z + 1 + lift);
        const [ex, ey] = FACES[p.edge];
        Z.set(ex * Math.sin(K.tiltTop), ey * Math.sin(K.tiltTop), Math.cos(K.tiltTop)).normalize();
        X.set(-ey, ex, 0);
      }
      X.addScaledVector(Z, -X.dot(Z)).normalize();
      Y.crossVectors(Z, X);
      m.makeBasis(X, Y, Z);
      if (K.spin) m.multiply(new THREE.Matrix4().makeRotationZ(p.spin * Math.PI * 2));
      m.scale(new THREE.Vector3(p.s, p.s, p.s));
      m.setPosition(pos);
      K.parts.forEach((part, k) => {
        this.meshes[k].setMatrixAt(i, m);
        col.copy(part.color(p.spin));
        this.meshes[k].setColorAt(i, col);
      });
    });
    for (const mesh of this.meshes) {
      mesh.count = spots.length;
      mesh.instanceMatrix.needsUpdate = true;
      if (mesh.instanceColor) mesh.instanceColor.needsUpdate = true;
    }
  }

  dispose(scene) {
    for (const m of this.meshes) {
      scene.remove(m);
      m.geometry.dispose();
      m.material.dispose();
    }
  }
}
