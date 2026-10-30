// 테트리미노 칸 모습 (떨어지는·쌓인·하늘 계단·유령·R 집기, 렌더러 밖에서도 씀 — 예: new PieceLook(pieceSpec(테마 id)) 로 로고 블록): 맵 테마마다 모양(둥근 상자 크기·모서리)·면 텍스처·조각 색·셰이더 결.
// 값은 shared/piece-look.js pieceSpec (config PIECE_LOOK + WORLD_THEMES.*.piece). 그래픽 낮춤이면 모서리 한 단·빛 테·금 빛·금 테 끔 (제 색 빛남만)
// 모양 (shape: 보석·벽돌 층·버섯 갓·나무 상자·금 테 대리석) 은 piece-shapes.js — 부품마다 aAcc 로 조각 색 대신 accent 색 (흰 점·대·금·잎).
// 셰이더 결 (조각 색 기준이라 인스턴스 색에도 맞음): glow 제 색으로 빛남 · crack 텍스처 밝은 금이 빛남 (흑요석) · fresnel 비스듬한 면 빛 테 (보석·버섯)
import * as THREE from 'three';
import { pieceGeometry } from '/piece-shapes.js';
import { toon } from '/toon.js';
import { pieceTexture } from '/textures.js';

const f3 = (v) => Number(v).toFixed(3);

export class PieceLook {
  // spec = pieceSpec(테마), toyMap = 텍스처가 없을 때 (생략 가능), low = 그래픽 낮춤
  constructor(spec, toyMap = null, low = false) {
    this.spec = spec;
    this.low = !!low;
    this.geo = pieceGeometry(spec, this.low);
    this.map = pieceTexture(spec.style) || toyMap || pieceTexture('toy');
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
    const acc = (s.accent || [0xffffff, 0xffffff]).map((c) => new THREE.Color(c));
    const v3 = (c) => `vec3(${f3(c.r)}, ${f3(c.g)}, ${f3(c.b)})`;
    m.onBeforeCompile = (sh) => {
      sh.vertexShader = sh.vertexShader
        .replace('#include <common>', '#include <common>\nattribute float aAcc;\nvarying float vAcc;')
        .replace('#include <begin_vertex>', '#include <begin_vertex>\n  vAcc = aAcc;');
      // accent 부품은 조각 색 대신 정한 색 (면 텍스처는 조금만)
      sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nvarying float vAcc;').replace(
        '#include <color_fragment>',
        `#include <color_fragment>
  { vec3 tfMapC = vec3(1.0);
#ifdef USE_MAP
    tfMapC = sampledDiffuseColor.rgb;
#endif
    vec3 tfTex = mix(vec3(1.0), tfMapC, 0.35);
    diffuseColor.rgb = mix(diffuseColor.rgb, ${v3(acc[0])} * tfTex, 1.0 - step(0.5, abs(vAcc - 1.0)));
    diffuseColor.rgb = mix(diffuseColor.rgb, ${v3(acc[1])} * tfTex, step(1.5, vAcc)); }`,
      );
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
    m.customProgramCacheKey = () => `tf-piece:${s.style}:${f3(glow)}:${(s.accent || []).join()}:${fx ? `${f3(s.crack)}:${f3(s.fresnel)}` : 'low'}`;
    this.mats.push(m);
    return m;
  }

  dispose() {
    this.geo.dispose();
    for (const m of this.mats) m.dispose();
    this.mats = [];
  }
}
