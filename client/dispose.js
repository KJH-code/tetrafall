// 장면에서 뗀 몸·효과의 GPU 자원 풀어 주기 (2026-11 감사 C3). three.js 는 scene.remove 만으론 지오메트리·재질·텍스처를 안 놓음 →
// 캐릭터를 바꾸거나 사람이 들락날락할 때마다 15~30개씩 쌓였음 (6명 들락날락 10번에 geometries 32→172).
// 공유 자원은 빼야 함: 모델 원본 (robot·아이템 — 몸은 이걸 복제해 지오메트리·그림을 같이 씀), 렌더러가 들고 있는 그림 (궁 빛기둥 텍스처),
// 아직 남은 다른 사람 몸이 쓰는 것. 그런 건 `protect` 집합에 넣어 건너뜀 (풀어도 다시 그릴 때 올려지지만 매번 올리면 낭비).

// 재질 하나가 쥔 텍스처 (map·gradientMap 등 속성 + ShaderMaterial uniform)
function texturesOf(mat, out) {
  for (const k in mat) {
    const v = mat[k];
    if (v && v.isTexture) out.add(v);
  }
  if (mat.uniforms) for (const k in mat.uniforms) {
    const v = mat.uniforms[k] && mat.uniforms[k].value;
    if (v && v.isTexture) out.add(v);
  }
}

// root 아래 지오메트리·재질·텍스처 (Set 하나에 다 담음 — 같은 객체가 두 종류일 일은 없음)
export function collectResources(root, into = new Set()) {
  if (!root) return into;
  root.traverse((o) => {
    if (o.geometry && !o.isSprite) into.add(o.geometry); // 스프라이트 지오메트리는 three 안에서 모두가 같이 씀
    const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
    for (const m of mats) {
      into.add(m);
      const t = new Set();
      texturesOf(m, t);
      for (const x of t) into.add(x);
    }
  });
  return into;
}

// 여러 root 가 쓰는 자원 모음 (공유 보호 집합 만들기). 더 보호할 개별 자원은 extra
export function protectSet(roots, extra = []) {
  const s = new Set(extra);
  for (const r of roots) collectResources(r, s);
  return s;
}

// root 의 자원을 놓음 (장면에서 떼는 건 부르는 쪽 몫). protect 에 든 건 건너뜀. 놓은 개수 { geometries, materials, textures }
export function disposeObject(root, protect = new Set()) {
  const n = { geometries: 0, materials: 0, textures: 0 };
  if (!root) return n;
  const seen = new Set();
  const free = (res, kind) => {
    if (!res || seen.has(res) || protect.has(res)) return;
    seen.add(res);
    res.dispose();
    n[kind]++;
  };
  root.traverse((o) => {
    if (o.isSkinnedMesh && o.skeleton && o.skeleton.dispose) o.skeleton.dispose(); // 뼈 텍스처
    if (o.geometry && !o.isSprite) free(o.geometry, 'geometries');
    const mats = Array.isArray(o.material) ? o.material : o.material ? [o.material] : [];
    for (const m of mats) {
      const t = new Set();
      texturesOf(m, t);
      for (const x of t) free(x, 'textures');
      free(m, 'materials');
    }
  });
  return n;
}
