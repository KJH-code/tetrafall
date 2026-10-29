// 테마 지형 블록 (TABS 저폴리, 2026-10-29 재혁: 주상절리 B): 칸마다 같은 텍스처를 반복하지 않고, 셰이더가 월드 좌표로 색·모양을 정한다.
// - 같은 지형 칸끼리 맞닿은 옆면·모서리는 테두리 없이 이어짐. 겉으로 드러난 모서리만 깎이고 어두워짐 (aOpen: 이웃이 빈 방향)
// - 밟는 윗면만 칸 경계가 살짝 보임 (grid) + 칸마다 조금 오르내림 (step, 기둥)
// - 색: 윗면·옆면·밑면 색 + 여러 칸에 걸친 큰 얼룩(테마 빛깔) + 높이 (아래 어둡게) + 드러난 모서리 닳음 + 테마 결
//   (lip 윗면 색이 옆으로 흘러내림 = 잔디·이끼 · strata 사암 층 · brick 돌벽돌 · veins 용암 금·수정 맥 · sheen 수정 빛 테)
// 판정 칸은 그대로 (화면만). 값 계산은 shared/block-style.js (config WORLD_BLOCK_STYLES + 테마 terrain.block)
import * as THREE from 'three';
import { toon, noOutline } from '/toon.js';
import { openBits } from '/shared/block-style.js';

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
  const open = new THREE.InstancedBufferAttribute(new Float32Array(count), 1);
  g.setAttribute('aOpen', open);
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
  };
  m.userData.tfUniforms = uniforms;
  m.userData.tfStyle = s;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, uniforms);
    sh.vertexShader = sh.vertexShader
      .replace(
        '#include <common>',
        `#include <common>
attribute float aOpen;
uniform float tfDisp; uniform vec2 tfChamfer; uniform float tfStep;
varying vec3 vTfW; varying vec3 vTfCell; varying float vTfOpen;
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
  vTfCell = tfCell; vTfOpen = aOpen;
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
  if (position.z > 0.49 && tfBit(aOpen, 16.0) > 0.5) transformed.z += (tfHash(floor(tfCell) + 11.3) - 0.5) * tfStep;
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
uniform vec2 tfGrid; uniform float tfLip; uniform vec2 tfStrata; uniform vec4 tfBrick; uniform float tfSheen;
varying vec3 vTfW; varying vec3 vTfCell; varying float vTfOpen;
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
  bool tfLipHere = tfSideFace && tfLip > 0.0 && tfBitF(vTfOpen, 16.0) > 0.5 && l.z > 0.5 - lipD;
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
  // 드러난 모서리 닳음: 이 면의 테두리 중 이웃이 빈 쪽 가까이 (맞닿은 쪽은 이어 보임)
  float d = 1.0;
  if (an.x < 0.7) { if (tfBitF(vTfOpen, 1.0) > 0.5) d = min(d, 0.5 - l.x); if (tfBitF(vTfOpen, 2.0) > 0.5) d = min(d, 0.5 + l.x); }
  if (an.y < 0.7) { if (tfBitF(vTfOpen, 4.0) > 0.5) d = min(d, 0.5 - l.y); if (tfBitF(vTfOpen, 8.0) > 0.5) d = min(d, 0.5 + l.y); }
  if (an.z < 0.7) { if (tfBitF(vTfOpen, 16.0) > 0.5) d = min(d, 0.5 - l.z); if (tfBitF(vTfOpen, 32.0) > 0.5) d = min(d, 0.5 + l.z); }
  float e = 1.0 - smoothstep(0.0, 0.16, d);
  if (up > 0.5) {
    base = mix(base, base * 1.35 + 0.04, tfWear * e); // 윗면 가장자리는 닳아 밝게
    // 밟는 윗면만 칸 경계가 살짝 (맞닿은 칸 사이에도)
    vec2 g = abs(vTfW.xy - floor(vTfW.xy + 0.5));
    float gw = min(g.x, g.y); float aa = fwidth(gw) + 1e-4; // 멀리선 선이 굵어지지 않게 흐리게
    base *= 1.0 - tfGrid.x * clamp(1.5 - 0.5 * aa / tfGrid.y, 0.0, 1.0) * (1.0 - smoothstep(tfGrid.y - aa, tfGrid.y + aa, gw));
  } else if (!tfLipHere) base = mix(base, tfRim, tfEdge * e); // 옆면 모서리는 어둡게
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

// 칸마다 이웃이 빈 방향을 인스턴스 속성에 (값 계산은 shared/block-style.js openBits)
const bits = [];
export function terrainOpenMask(attr, grid, W, D, H, skip) {
  openBits(grid, W, D, H, skip, bits);
  const n = Math.min(bits.length, attr.count);
  for (let i = 0; i < n; i++) attr.setX(i, bits[i]);
  attr.needsUpdate = true;
  return bits.length;
}
