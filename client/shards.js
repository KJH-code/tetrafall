// 판자 조각 (건축가 블록이 터지거나 무너질 때): InstancedMesh 하나에 칸마다 색 (나무·어두운 나무·쇠). 중력·회전, 바닥(단단한 칸)에 한 번 튀고, 끝에 작아지며 사라짐
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon } from '/toon.js';
import { outlineInstancing } from '/instpool.js';

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _v = new THREE.Vector3();
const _s = new THREE.Vector3();

export class Shards {
  // solidAt(x, y, z): 그 자리가 단단한가 (튀기)
  constructor(scene, texture, solidAt) {
    const S = C.BB_SHARDS;
    this.solidAt = solidAt;
    this.list = [];
    this.im = new THREE.InstancedMesh(new THREE.BoxGeometry(1, 1, 1), toon({ map: texture }), S.max);
    this.im.frustumCulled = false;
    this.im.castShadow = true;
    this.im.onBeforeRender = outlineInstancing;
    this.im.setColorAt(0, new THREE.Color(1, 1, 1));
    this.im.instanceColor.setUsage(THREE.DynamicDrawUsage);
    this.im.count = 0;
    scene.add(this.im);
  }

  // pos 에서 n 개, dir(있으면) 쪽으로 더. colors: 칸마다 고를 색들
  spawn(pos, dir, n, colors, speed = C.BB_SHARDS.speed) {
    const S = C.BB_SHARDS;
    for (let i = 0; i < n; i++) {
      if (this.list.length >= S.max) this.list.shift();
      const a = Math.random() * Math.PI * 2;
      const r = 0.4 + Math.random() * 0.6;
      this.list.push({
        x: pos.x + (Math.random() - 0.5) * 0.6,
        y: pos.y + (Math.random() - 0.5) * 0.6,
        z: pos.z + (Math.random() - 0.5) * 0.5,
        vx: Math.cos(a) * r * speed * 0.55 + (dir ? dir.x * speed * 0.6 : 0),
        vy: Math.sin(a) * r * speed * 0.55 + (dir ? dir.y * speed * 0.6 : 0),
        vz: 1.5 + Math.random() * speed * 0.7,
        rx: Math.random() * 6,
        ry: Math.random() * 6,
        rz: Math.random() * 6,
        wx: (Math.random() - 0.5) * 16,
        wy: (Math.random() - 0.5) * 16,
        wz: (Math.random() - 0.5) * 10,
        k: 0.6 + Math.random() * 0.7, // 크기
        life: S.life * (0.7 + Math.random() * 0.5),
        max: 0,
        color: new THREE.Color(colors[Math.floor(Math.random() * colors.length)]),
        bounced: false,
      });
      this.list[this.list.length - 1].max = this.list[this.list.length - 1].life;
    }
  }

  update(dt) {
    const S = C.BB_SHARDS;
    let n = 0;
    this.list = this.list.filter((p) => (p.life -= dt) > 0);
    for (const p of this.list) {
      p.vz -= 14 * dt;
      const nz = p.z + p.vz * dt;
      if (p.vz < 0 && this.solidAt && this.solidAt(p.x, p.y, nz - 0.03)) {
        if (!p.bounced) {
          p.vz = -p.vz * 0.35;
          p.vx *= 0.5;
          p.vy *= 0.5;
          p.bounced = true;
        } else p.vz = 0;
        p.wx *= 0.4;
        p.wy *= 0.4;
      } else p.z = nz;
      p.x += p.vx * dt;
      p.y += p.vy * dt;
      p.rx += p.wx * dt;
      p.ry += p.wy * dt;
      p.rz += p.wz * dt;
      const fade = Math.min(1, p.life / (p.max * 0.3)); // 끝 30% 에 작아짐
      _q.setFromEuler(_e.set(p.rx, p.ry, p.rz));
      _m.compose(_v.set(p.x, p.y, p.z), _q, _s.set(S.size[0] * p.k * fade, S.size[1] * p.k * fade, S.size[2] * p.k * fade));
      this.im.setMatrixAt(n, _m);
      this.im.setColorAt(n, p.color);
      n++;
    }
    this.im.count = n;
    this.im.visible = n > 0;
    this.im.instanceMatrix.needsUpdate = true;
    this.im.instanceColor.needsUpdate = true;
  }
}
