// 툰 셰이딩: 빛을 3단계로 끊어 칠하는 재질 + 외곽선에서 뺄 재질 표시.
// 외곽선은 render.js 가 OutlineEffect 로 그린다 (설정에서 끌 수 있음).
import * as THREE from 'three';

// 3단계 명암 (어두운 면 · 중간 · 밝은 면). 픽셀 사이를 섞지 않아야 단이 진다
const steps = new Uint8Array([110, 175, 255]);
export const TOON_GRADIENT = new THREE.DataTexture(steps, steps.length, 1, THREE.RedFormat);
TOON_GRADIENT.minFilter = THREE.NearestFilter;
TOON_GRADIENT.magFilter = THREE.NearestFilter;
TOON_GRADIENT.needsUpdate = true;

export function toon(params = {}) {
  return new THREE.MeshToonMaterial({ gradientMap: TOON_GRADIENT, ...params });
}

// 외곽선을 안 그릴 재질 (하늘·용암·그림자 판·조준 미리보기·파편처럼 테두리가 어색한 것)
export function noOutline(material) {
  material.userData.outlineParameters = { visible: false };
  return material;
}

// 불러온 모델의 재질(Standard 등)을 툰으로 바꾼다. 색·그림(색표)·발광·투명도는 그대로
export function toonifyObject(root) {
  const done = new Map();
  root.traverse((o) => {
    if (!o.isMesh) return;
    const conv = (m) => {
      if (!done.has(m)) {
        done.set(
          m,
          toon({
            name: m.name,
            color: m.color ? m.color.clone() : new THREE.Color(0xffffff),
            map: m.map || null,
            emissive: m.emissive ? m.emissive.clone() : new THREE.Color(0x000000),
            transparent: m.transparent,
            opacity: m.opacity,
            side: m.side,
          }),
        );
      }
      return done.get(m);
    };
    o.material = Array.isArray(o.material) ? o.material.map(conv) : conv(o.material);
  });
  return root;
}
