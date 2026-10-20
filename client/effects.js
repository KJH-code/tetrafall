// 타격감 이펙트: 파편, 충격파 고리, 화면 흔들림, 캐릭터 찌그러짐·팔 휘두르기 타이머.
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

const MAX_PARTICLES = 160;
const MAX_RINGS = 12;

export class Effects {
  constructor(scene) {
    this.scene = scene;
    const box = new THREE.BoxGeometry(1, 1, 1);
    this.particles = [];
    for (let i = 0; i < MAX_PARTICLES; i++) {
      const m = new THREE.Mesh(box, new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true }));
      m.visible = false;
      m.userData = { vx: 0, vy: 0, vz: 0, life: 0, max: 1, size: 0.1 };
      scene.add(m);
      this.particles.push(m);
    }
    const ringGeo = new THREE.RingGeometry(0.8, 1, 40);
    this.rings = [];
    for (let i = 0; i < MAX_RINGS; i++) {
      const m = new THREE.Mesh(ringGeo, new THREE.MeshBasicMaterial({ color: 0xffffff, transparent: true, side: THREE.DoubleSide, depthWrite: false }));
      m.visible = false;
      m.userData = { life: 0, max: 1, grow: 1 };
      scene.add(m);
      this.rings.push(m);
    }
    this.pi = 0;
    this.ri = 0;
    this.shakeAmp = 0;
    this.shakeUntil = 0;
    this.shakeMs = 1;
    this.squash = new Map(); // 플레이어 id -> { t0, dx, dy }
    this.punch = new Map(); // 플레이어 id -> t0
  }

  // pos 에서 dir 쪽으로 퍼지는 파편
  burst(pos, dir, color, count = C.FX_PARTICLES, speed = 5, size = 0.1, life = 0.45) {
    for (let i = 0; i < count; i++) {
      const m = this.particles[this.pi++ % MAX_PARTICLES];
      const a = Math.random() * Math.PI * 2;
      const r = Math.random();
      const u = m.userData;
      u.vx = (dir ? dir.x * speed : 0) + Math.cos(a) * r * speed * 0.6;
      u.vy = (dir ? dir.y * speed : 0) + Math.sin(a) * r * speed * 0.6;
      u.vz = 1.5 + Math.random() * speed * 0.6;
      u.life = u.max = life * (0.6 + Math.random() * 0.6);
      u.size = size * (0.6 + Math.random() * 0.8);
      m.position.set(pos.x, pos.y, pos.z);
      m.scale.setScalar(u.size);
      m.material.color.setHex(color);
      m.material.opacity = 1;
      m.visible = true;
    }
  }

  // 퍼지는 충격파 고리. horizontal 이면 바닥에 눕힘, 아니면 카메라를 바라봄
  ring(pos, color = 0xffffff, grow = 2.2, life = 0.28, horizontal = false) {
    const m = this.rings[this.ri++ % MAX_RINGS];
    const u = m.userData;
    u.life = u.max = life;
    u.grow = grow;
    u.horizontal = horizontal;
    m.position.set(pos.x, pos.y, pos.z);
    m.rotation.set(0, 0, 0);
    m.scale.setScalar(0.2);
    m.material.color.setHex(color);
    m.material.opacity = 0.9;
    m.visible = true;
  }

  shake(amp, ms = C.FX_SHAKE_MS) {
    const now = performance.now();
    // 더 센 흔들림이 이긴다
    const cur = now < this.shakeUntil ? this.shakeAmp * ((this.shakeUntil - now) / this.shakeMs) : 0;
    if (amp < cur) return;
    this.shakeAmp = amp;
    this.shakeMs = ms;
    this.shakeUntil = now + ms;
  }

  shakeOffset() {
    const now = performance.now();
    if (now >= this.shakeUntil) return null;
    const k = (this.shakeUntil - now) / this.shakeMs;
    const a = this.shakeAmp * k * k;
    return { x: (Math.random() * 2 - 1) * a, y: (Math.random() * 2 - 1) * a, z: (Math.random() * 2 - 1) * a * 0.6 };
  }

  hitSquash(id, dx = 0, dy = 0) {
    this.squash.set(id, { t0: performance.now(), dx, dy });
  }

  // 0~1 찌그러짐 정도 (0 = 평상시)
  squashAmount(id) {
    const s = this.squash.get(id);
    if (!s) return 0;
    const t = (performance.now() - s.t0) / C.FX_SQUASH_MS;
    if (t >= 1) {
      this.squash.delete(id);
      return 0;
    }
    return Math.sin(Math.PI * t) * (1 - t) * 1.6;
  }

  startPunch(id) {
    this.punch.set(id, performance.now());
  }

  // 0~1 팔 뻗은 정도
  punchAmount(id) {
    const t0 = this.punch.get(id);
    if (t0 === undefined) return 0;
    const t = (performance.now() - t0) / 220;
    if (t >= 1) {
      this.punch.delete(id);
      return 0;
    }
    return t < 0.3 ? t / 0.3 : 1 - (t - 0.3) / 0.7;
  }

  update(dt, camera) {
    for (const m of this.particles) {
      if (!m.visible) continue;
      const u = m.userData;
      u.life -= dt;
      if (u.life <= 0) {
        m.visible = false;
        continue;
      }
      u.vz -= 14 * dt;
      m.position.x += u.vx * dt;
      m.position.y += u.vy * dt;
      m.position.z += u.vz * dt;
      m.material.opacity = Math.min(1, (u.life / u.max) * 1.5);
      m.rotation.x += dt * 8;
      m.rotation.y += dt * 6;
    }
    for (const m of this.rings) {
      if (!m.visible) continue;
      const u = m.userData;
      u.life -= dt;
      if (u.life <= 0) {
        m.visible = false;
        continue;
      }
      const k = 1 - u.life / u.max;
      m.scale.setScalar(0.2 + k * u.grow);
      m.material.opacity = 0.9 * (1 - k);
      if (!u.horizontal && camera) m.quaternion.copy(camera.quaternion);
    }
  }
}
