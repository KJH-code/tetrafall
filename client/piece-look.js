// 테트리미노 칸 모습 (떨어지는·쌓인·하늘 계단·유령·R 집기·타이틀 로고): 맵 테마마다 모양(둥근 상자 크기·모서리)·면 텍스처·조각 색·셰이더 결.
// 값은 shared/piece-look.js pieceSpec (config PIECE_LOOK + WORLD_THEMES.*.piece). 그래픽 낮춤이면 모서리 한 단·빛 테·금 빛·금 테 끔 (제 색 빛남만)
// 셰이더 결 (모두 조각 색 기준이라 인스턴스 색에도 맞음): glow 제 색으로 빛남 · crack 텍스처 밝은 금이 빛남 (흑요석) · fresnel 비스듬한 면 빛 테 (보석·버섯) · band 면 가장자리 금속 테 (대리석 금 테)
import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { toon } from '/toon.js';
import { pieceTexture } from '/textures.js';

const f3 = (v) => Number(v).toFixed(3);

export class PieceLook {
  // spec = pieceSpec(테마), toyMap = 기본 장난감 블록 텍스처, low = 그래픽 낮춤
  constructor(spec, toyMap, low) {
    this.spec = spec;
    this.low = !!low;
    this.geo = new RoundedBoxGeometry(spec.size, spec.size, spec.size, this.low ? 1 : spec.segs, spec.bevel);
    this.map = pieceTexture(spec.style) || toyMap;
    this.mats = [];
  }

  color(shape) {
    return this.spec.colors[shape] ?? 0xf0a030;
  }

  // 툰 재질 (map·결 셰이더 붙임). params 는 toon 값 (color·emissive·transparent·opacity …). extraGlow: 더 빛남 (타이틀)
  material(params = {}, extraGlow = 0) {
    const s = this.spec;
    const m = toon({ map: this.map, ...params });
    const glow = (s.glow || 0) + extraGlow;
    const fx = !this.low;
    const band = fx && s.band ? s.band : null;
    const bandCol = band ? new THREE.Color(band[1]) : null;
    m.onBeforeCompile = (sh) => {
      if (band) {
        sh.fragmentShader = sh.fragmentShader.replace(
          '#include <color_fragment>',
          `#include <color_fragment>
#ifdef USE_MAP
  { vec2 tfE = min(vMapUv, 1.0 - vMapUv); float tfB = 1.0 - smoothstep(${f3(band[0])}, ${f3(band[0] + 0.03)}, min(tfE.x, tfE.y));
    diffuseColor.rgb = mix(diffuseColor.rgb, vec3(${f3(bandCol.r)}, ${f3(bandCol.g)}, ${f3(bandCol.b)}), tfB); }
#endif`,
        );
      }
      sh.fragmentShader = sh.fragmentShader.replace(
        '#include <emissivemap_fragment>',
        `#include <emissivemap_fragment>
  totalEmissiveRadiance += diffuseColor.rgb * ${f3(glow)};
#ifdef USE_MAP
  totalEmissiveRadiance += diffuseColor.rgb * ${f3(fx ? s.crack : 0)} * smoothstep(0.6, 0.95, sampledDiffuseColor.r);
#endif
  totalEmissiveRadiance += mix(diffuseColor.rgb, vec3(1.0), 0.4) * ${f3(fx ? s.fresnel : 0)} * pow(1.0 - abs(dot(normal, normalize(vViewPosition))), 2.5);`,
      );
    };
    m.customProgramCacheKey = () => `tf-piece:${s.style}:${f3(glow)}:${fx ? `${f3(s.crack)}:${f3(s.fresnel)}:${band ? band.join() : ''}` : 'low'}`;
    this.mats.push(m);
    return m;
  }

  dispose() {
    this.geo.dispose();
    for (const m of this.mats) m.dispose();
    this.mats = [];
  }
}
