// 테마 지형 블록 (TABS 저폴리): 칸마다 같은 텍스처를 반복하지 않고, 셰이더가 월드 좌표로 색·모양을 정한다.
// - 같은 지형 칸끼리 맞닿은 면·모서리는 테두리 없이 이어짐. 겉으로 드러난 모서리만 깎이고 어두워짐 (aOpen: 이웃이 빈 방향)
// - 꼭짓점을 월드 좌표 잡음으로 조금 흔들어 깎은 돌 모양 (이웃 칸과 같은 점은 같은 만큼 움직여 틈이 안 생김), 면은 평평하게 끊어 칠함
// - 색: 윗면·옆면·밑면 색 + 여러 칸에 걸친 큰 얼룩(테마 빛깔) + 높이 (아래 어둡게) + 드러난 모서리 닳음 + 테마 결 (용암 금·수정 맥)
// 판정 칸은 그대로 (화면만). 스타일 수치는 config WORLD_BLOCK_STYLES (WORLD_BLOCK_STYLE 로 고름)
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon, noOutline } from '/toon.js';
import { CELL } from '/shared/pieces.js';

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

// look = 테마 terrain ({ top, side, rim, glow, tints, crust, paint }), style = WORLD_BLOCK_STYLES 한 줄, low = 그래픽 낮춤
export function terrainMaterial(look, style, low) {
  const m = toon({ color: 0xffffff });
  noOutline(m);
  m.defines = { FLAT_SHADED: '' };
  const tints = (look.tints && look.tints.length ? look.tints : [look.side]).slice(0, 3);
  while (tints.length < 3) tints.push(tints[tints.length - 1]);
  const vein = style.veins && look.glow != null ? style.veins : 0;
  const uniforms = {
    tfTop: { value: new THREE.Color(look.top) },
    tfSide: { value: new THREE.Color(look.side) },
    tfRim: { value: new THREE.Color(look.rim) },
    tfTint0: { value: new THREE.Color(tints[0]) },
    tfTint1: { value: new THREE.Color(tints[1]) },
    tfTint2: { value: new THREE.Color(tints[2]) },
    tfGlow: { value: new THREE.Color(look.glow ?? 0x000000) },
    tfDisp: { value: low ? 0 : style.disp },
    tfChamfer: { value: new THREE.Vector2(style.chamfer[0], style.chamfer[1]) },
    tfStep: { value: low ? 0 : style.step },
    tfBlotch: { value: new THREE.Vector2(style.blotch[0], style.blotch[1]) },
    tfEdge: { value: style.edge },
    tfHeight: { value: new THREE.Vector2(style.height[0], style.height[1]) },
    tfVein: { value: vein },
    tfVeinScale: { value: style.veinScale || 1 },
    tfMottle: { value: style.mottle || 0 },
    tfWear: { value: style.wear || 0 },
    tfTopLift: { value: style.topLift || 1 },
  };
  m.userData.tfUniforms = uniforms;
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
  // 드러난 윗면은 칸마다 조금 높낮이 (기둥 느낌), 꼭짓점은 월드 잡음으로 흔듦 (깎은 돌)
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
varying vec3 vTfW; varying vec3 vTfCell; varying float vTfOpen;
${NOISE}
float tfBitF(float m, float b) { return mod(floor(m / b + 0.001), 2.0); }
float tfGlowAmt = 0.0;`,
      )
      .replace(
        '#include <color_fragment>',
        `#include <color_fragment>
  vec3 tfN = normalize(cross(dFdx(vTfW), dFdy(vTfW)));
  float up = smoothstep(0.55, 0.85, tfN.z);
  vec3 base = mix(tfSide, tfTop * tfTopLift, up);
  if (tfN.z < -0.5) base = tfSide * 0.6;
  // 여러 칸에 걸친 큰 얼룩 (테마 빛깔 셋)
  float b1 = tfFbm(vTfW * tfBlotch.x + 5.0);
  float b2 = tfFbm(vTfW * tfBlotch.x * 0.6 + 31.0);
  vec3 tint = mix(mix(tfTint0, tfTint1, smoothstep(0.35, 0.65, b1)), tfTint2, smoothstep(0.55, 0.75, b2));
  base = mix(base, tint * mix(1.0, 1.15, up), tfBlotch.y);
  // 높이: 아래로 갈수록 어둡게
  base *= mix(tfHeight.x, 1.0, clamp(vTfW.z / tfHeight.y, 0.0, 1.0));
  // 드러난 모서리 닳음: 이 면의 테두리 중 이웃이 빈 쪽 가까이 어둡게 (맞닿은 쪽은 이어 보임)
  vec3 l = vTfW - vTfCell;
  vec3 an = abs(tfN);
  float d = 1.0;
  if (an.x < 0.7) { if (tfBitF(vTfOpen, 1.0) > 0.5) d = min(d, 0.5 - l.x); if (tfBitF(vTfOpen, 2.0) > 0.5) d = min(d, 0.5 + l.x); }
  if (an.y < 0.7) { if (tfBitF(vTfOpen, 4.0) > 0.5) d = min(d, 0.5 - l.y); if (tfBitF(vTfOpen, 8.0) > 0.5) d = min(d, 0.5 + l.y); }
  if (an.z < 0.7) { if (tfBitF(vTfOpen, 16.0) > 0.5) d = min(d, 0.5 - l.z); if (tfBitF(vTfOpen, 32.0) > 0.5) d = min(d, 0.5 + l.z); }
  float e = 1.0 - smoothstep(0.0, 0.16, d);
  if (up > 0.5) base = mix(base, base * 1.35 + 0.04, tfWear * e); // 윗면 가장자리는 닳아 밝게
  else base = mix(base, tfRim, tfEdge * e); // 옆면 모서리는 어둡게
  // 면마다·자리마다 조금씩 다른 밝기 (깎은 면이 드러나게, 월드 좌표라 칸 경계와 상관없음)
  base *= 1.0 + (tfNoise(floor(vTfW * 3.0) + 0.5) - 0.5) * tfMottle + (tfNoise(vTfW * 0.7 + 2.0) - 0.5) * tfMottle;
  // 테마 결: 여러 칸에 걸쳐 이어지는 가는 빛 금 (용암·수정)
  if (tfVein > 0.0) {
    float v = tfNoise(vTfW * vec3(0.9, 0.9, 1.3) * tfVeinScale) - 0.5;
    float w = tfNoise(vTfW * 2.3 * tfVeinScale + 13.0) - 0.5;
    tfGlowAmt = (1.0 - smoothstep(0.0, 0.035, abs(v))) * smoothstep(-0.1, 0.15, w) * (1.0 - up * 0.6);
    base = mix(base, tfGlow, tfGlowAmt * tfVein);
  }
  diffuseColor.rgb *= base;`,
      )
      .replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
  totalEmissiveRadiance += tfGlow * tfGlowAmt * tfVein;`,
      );
  };
  m.customProgramCacheKey = () => `tfBlocks:${low ? 1 : 0}`;
  return m;
}

// 칸마다 이웃이 빈 방향 (aOpen 비트: 1 +x · 2 −x · 4 +y · 8 −y · 16 +z · 32 −z). 같은 지형 칸만 '막힘' (다른 블록이 옆에 와도 모서리는 깎인 채)
// skip: 그리지 않는 칸 (건축가 블록). 순서는 render.updateGrid 와 같게 (z → y → x, 지형 칸만)
export function terrainOpenMask(attr, grid, W, D, H, skip) {
  const at = (x, y, z) => x >= 0 && y >= 0 && z >= 0 && x < W && y < D && z < H && grid[(z * D + y) * W + x] === CELL.TERRAIN;
  let n = 0;
  for (let z = 0; z < H; z++) {
    for (let y = 0; y < D; y++) {
      for (let x = 0; x < W; x++) {
        const i = (z * D + y) * W + x;
        if (grid[i] !== CELL.TERRAIN || (skip && skip.has(i))) continue;
        let m = 0;
        if (!at(x + 1, y, z)) m |= 1;
        if (!at(x - 1, y, z)) m |= 2;
        if (!at(x, y + 1, z)) m |= 4;
        if (!at(x, y - 1, z)) m |= 8;
        if (!at(x, y, z + 1)) m |= 16;
        if (z > 0 && !at(x, y, z - 1)) m |= 32;
        if (n < attr.count) attr.setX(n, m);
        n++;
      }
    }
  }
  attr.needsUpdate = true;
  return n;
}
