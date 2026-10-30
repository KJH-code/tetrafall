// 그리기 수 줄이기: 같은 모양을 여러 개 그리는 것(떨어지는 블록 칸·그 그림자 칸)을 재질마다 InstancedMesh 하나로.
// 그리는 쪽은 예전처럼 칸마다 '자리' 객체(Object3D, 장면엔 안 넣음)에 position·visible·material 을 정하고, flush 로 한 번에 옮긴다.
// OutlineEffect 는 원래 인스턴스 위치를 모르고 테두리를 밀어내서, 그 테두리 재질만 인스턴스 행렬을 쓰게 고친다 (outlineInstancing).
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const OUTLINE_FROM = 'vec4 pos2 = projectionMatrix * modelViewMatrix * vec4( skinned.xyz + normal, 1.0 );';
const OUTLINE_TO = 'vec4 p2 = vec4( skinned.xyz + normal, 1.0 );\n#ifdef USE_INSTANCING\n\tp2 = instanceMatrix * p2;\n#endif\n\tvec4 pos2 = projectionMatrix * modelViewMatrix * p2;';

// InstancedMesh.onBeforeRender: 테두리 패스(OutlineEffect 의 ShaderMaterial)면 셰이더를 한 번 고침. #ifdef 라 보통 메시에 같이 써도 그대로
export function outlineInstancing(renderer, scene, camera, geometry, material) {
  if (!material || !material.isShaderMaterial || material.userData.instOutline) return;
  if (!material.vertexShader.includes(OUTLINE_FROM)) return;
  material.vertexShader = material.vertexShader.replace(OUTLINE_FROM, OUTLINE_TO);
  material.userData.instOutline = true;
  material.needsUpdate = true;
}

export class InstancePool {
  // opts: { castShadow, receiveShadow, renderOrder }
  constructor(scene, geometry, opts = {}) {
    this.scene = scene;
    this.geo = geometry;
    this.opts = opts;
    this.meshes = new Map(); // 재질 → InstancedMesh
    this.by = new Map();
  }

  make(mat, cap) {
    const im = new THREE.InstancedMesh(this.geo, mat, cap);
    im.frustumCulled = false; // 경계 구를 한 번만 계산해서 칸이 움직이면 틀림
    im.castShadow = !!this.opts.castShadow;
    im.receiveShadow = !!this.opts.receiveShadow;
    im.renderOrder = this.opts.renderOrder || 0;
    im.onBeforeRender = outlineInstancing;
    im.count = 0;
    this.scene.add(im);
    this.meshes.set(mat, im);
    return im;
  }

  // 모양이 바뀌면 (맵 테마마다 다른 테트리미노 칸) 만든 메시를 다 버리고 새 모양으로
  reset(geometry) {
    for (const im of this.meshes.values()) {
      this.scene.remove(im);
      im.dispose();
    }
    this.meshes.clear();
    this.by.clear();
    this.geo = geometry;
  }

  // slots: 자리 객체들 (visible 인 것만, 재질마다 모아 그림)
  flush(slots) {
    const by = this.by;
    for (const a of by.values()) a.length = 0;
    for (const o of slots) {
      if (!o.visible) continue;
      let a = by.get(o.material);
      if (!a) by.set(o.material, (a = []));
      a.push(o);
    }
    for (const [mat, im] of this.meshes) {
      const list = by.get(mat);
      if (!list || !list.length) {
        im.count = 0;
        im.visible = false;
      }
    }
    for (const [mat, list] of by) {
      if (!list.length) continue;
      let im = this.meshes.get(mat);
      if (!im || im.instanceMatrix.count < list.length) {
        const cap = Math.max(list.length, im ? im.instanceMatrix.count * 2 : C.INSTANCE_POOL_MIN);
        if (im) {
          this.scene.remove(im);
          im.dispose();
        }
        im = this.make(mat, cap);
      }
      for (let i = 0; i < list.length; i++) {
        const o = list[i];
        o.updateMatrix();
        im.setMatrixAt(i, o.matrix);
      }
      im.count = list.length;
      im.visible = true;
      im.instanceMatrix.needsUpdate = true;
    }
  }
}
