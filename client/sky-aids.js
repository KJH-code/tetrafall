// 하늘 시점 도우미 (블록 마스터·블록 조종): 착지 미리보기 (내 블록이 놓일 칸 반투명 + 지금 칸에서 내려가는 빛 기둥, 못 놓으면 빨강)
// + 생존자 머리 위 표시 (아래로 향한 삼각뿔 + 바닥까지 빛 기둥, 그 사람 색). 그래픽 낮춤에서도 켬. InstancedMesh 넷 (그리기 4번, 안 쓰면 0)
// 착지 높이·놓을 수 있는지는 서버가 스냅샷에 보낸 piece.landZ·fits 그대로 (서버 판정과 같음). 칸 위치 계산은 shared/sky-view.js
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { noOutline } from '/toon.js';
import { landingPreview } from '/shared/sky-view.js';

const CAP = 16;

function pool(scene, geo, opacity, order) {
  const mat = noOutline(new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, opacity, depthWrite: false }));
  const m = new THREE.InstancedMesh(geo, mat, CAP);
  m.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(CAP * 3), 3);
  m.count = 0;
  m.frustumCulled = false;
  m.renderOrder = order;
  scene.add(m);
  return m;
}

export class SkyAids {
  constructor(scene) {
    const V = C.SKY_VIEW;
    this.ghost = pool(scene, new THREE.BoxGeometry(0.98, 0.98, 0.98), V.ghost, 3);
    this.ghostEdge = new THREE.LineSegments(new THREE.BufferGeometry(), noOutline(new THREE.LineBasicMaterial({ color: 0xffffff, transparent: true, opacity: 0.9 })));
    this.ghostEdge.frustumCulled = false;
    this.ghostEdge.renderOrder = 4;
    scene.add(this.ghostEdge);
    this.pillar = pool(scene, new THREE.BoxGeometry(1, 1, 1), V.pillar[1], 3);
    this.cone = pool(scene, new THREE.ConeGeometry(0.5, 1, 4).rotateX(-Math.PI / 2), 0.95, 6); // 아래로 향함 (+Y → −Z)
    this.beam = pool(scene, new THREE.BoxGeometry(1, 1, 1), V.beacon[4], 3);
    this.edgeBox = new THREE.EdgesGeometry(new THREE.BoxGeometry(0.98, 0.98, 0.98));
    this.m = new THREE.Matrix4();
    this.c = new THREE.Color();
  }

  // on: 하늘 시점일 때. piece: 내가 조종하는 블록 (없으면 null). people: [{ x, y, z, color }] 생존자 (화면 위치)
  update(on, piece, people) {
    const V = C.SKY_VIEW;
    const { m, c } = this;
    let g = 0;
    let p = 0;
    const edges = [];
    if (on && piece) {
      const { cells, pillars, ok } = landingPreview(piece);
      c.set(ok ? V.ok : V.bad);
      for (const [x, y, z] of cells) {
        if (g >= CAP) break;
        this.ghost.setMatrixAt(g, m.makeTranslation(x + 0.5, y + 0.5, z + 0.5));
        this.ghost.setColorAt(g++, c);
        const e = this.edgeBox.attributes.position.array;
        for (let i = 0; i < e.length; i += 3) edges.push(e[i] + x + 0.5, e[i + 1] + y + 0.5, e[i + 2] + z + 0.5);
      }
      for (const [x, y, z0, z1] of pillars) {
        if (p >= CAP) break;
        const w = V.pillar[0];
        this.pillar.setMatrixAt(p, m.makeScale(w, w, z1 - z0).setPosition(x + 0.5, y + 0.5, (z0 + z1) / 2));
        this.pillar.setColorAt(p++, c);
      }
      this.ghostEdge.material.color.copy(c);
    }
    this.ghostEdge.geometry.setAttribute('position', new THREE.Float32BufferAttribute(edges, 3));
    this.ghostEdge.visible = edges.length > 0;
    let b = 0;
    if (on) {
      const [size, lift, bob, bw] = V.beacon;
      const t = performance.now() / 1000;
      for (const s of people) {
        if (b >= CAP) break;
        const top = s.z + C.PLAYER_HEIGHT + lift + Math.sin(t * 3 + b) * bob;
        c.set(s.color);
        this.cone.setMatrixAt(b, m.makeScale(size, size, size * 1.2).setPosition(s.x, s.y, top + size * 0.6));
        this.cone.setColorAt(b, c);
        this.beam.setMatrixAt(b, m.makeScale(bw, bw, top).setPosition(s.x, s.y, top / 2));
        this.beam.setColorAt(b, c);
        b++;
      }
    }
    for (const [mesh, n] of [[this.ghost, g], [this.pillar, p], [this.cone, b], [this.beam, b]]) {
      mesh.count = n;
      mesh.visible = n > 0;
      mesh.instanceMatrix.needsUpdate = true;
      mesh.instanceColor.needsUpdate = true;
    }
  }
}
