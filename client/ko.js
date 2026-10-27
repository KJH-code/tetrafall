// KO 연출 (2026-10-27 재혁): 스매시 폭발 줄기 · 마지막 킬 슬로모션 · 압사 강하게. 수치는 shared/config.js KO_*
// 화면만 (서버 시간·판정과 상관없음). main.js 는 이벤트를 넘기고 프레임 dt 에 timeScale 을 곱하기만, render.js 는 camHook 한 줄.
// 소리 (B2): ko.on('smash' | 'final' | 'crush', (info) => ...) — info = { who, by, x, y, z, out?, color, me(내가 죽음), near(가까움) }
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';

export class KO {
  // fx: Effects, scene: THREE.Scene, opts.colorOf(id) → 0xRRGGBB, opts.lowGfx() → bool, opts.field() → { w, d }
  constructor(scene, fx, { colorOf = () => 0xffffff, lowGfx = () => false, field = () => ({ w: C.GRID_W, d: C.GRID_D }) } = {}) {
    this.scene = scene;
    this.fx = fx;
    this.colorOf = colorOf;
    this.lowGfx = lowGfx;
    this.field = field;
    this.listeners = { smash: [], final: [], crush: [] };
    this.plumes = []; // { mesh, age, life }
    this.slow = null; // { start, until, x, y, z } 마지막 킬 슬로모션
    this.stopUntil = 0; // 압사 히트스톱 (화면 멈칫)
    this.edgeEl = document.createElement('div'); // 화면 끝 번쩍 (떨어진 쪽)
    this.edgeEl.id = 'koEdge';
    this.edgeEl.style.cssText = 'position:fixed;inset:0;pointer-events:none;z-index:40;opacity:0';
    document.body.appendChild(this.edgeEl);
    this.edgeUntil = 0;
  }

  on(type, cb) {
    this.listeners[type]?.push(cb);
  }

  emit(type, info) {
    for (const cb of this.listeners[type]) {
      try {
        cb(info);
      } catch (err) {
        console.error(err);
      }
    }
  }

  parts(n) {
    return Math.max(1, Math.round(n * (this.lowGfx() ? C.KO_LOW_GFX_PARTICLES : 1)));
  }

  // 서버 death 이벤트 (main.js handleEvent). pos = 화면에 보이던 그 사람 자리 {x,y,z} (없으면 서버 자리), me = 내가 죽음, dist = 나와의 거리
  death(e, pos, me, dist) {
    const p = pos || { x: e.x, y: e.y, z: e.z };
    const color = this.colorOf(e.who);
    const near = me || (dist !== undefined && dist < C.KO_NEAR_DIST);
    const info = { who: e.who, by: e.by, x: p.x, y: p.y, z: p.z, out: e.out, color, me, near };
    if (e.cause === 'fall' && e.out) {
      this.smash(p, e.out, color, me, near);
      this.emit('smash', info);
    } else if (e.cause === 'crush') {
      this.crush(p, me, near);
      this.emit('crush', info);
    }
  }

  // 스매시 줄기: 떨어진 쪽 필드 가장자리에서 바깥·위로 그 사람 색 폭발 줄기 + 파편 + 화면 흔들림 + 화면 끝 번쩍
  smash(p, out, color, me, near) {
    const { w, d } = this.field();
    const ex = Math.max(0, Math.min(w, p.x));
    const ey = Math.max(0, Math.min(d, p.y));
    const ez = Math.max(-1, Math.min(p.z, 1));
    const dir = new THREE.Vector3(out.x, out.y, C.KO_SMASH_UP).normalize();
    const geo = new THREE.ConeGeometry(C.KO_SMASH_WIDTH, C.KO_SMASH_LEN, 12, 1, true);
    geo.translate(0, -C.KO_SMASH_LEN / 2, 0); // 꼭짓점이 가장자리, 넓은 쪽이 바깥
    geo.rotateX(Math.PI); // 넓은 쪽 = +y
    const mat = new THREE.MeshBasicMaterial({ color, transparent: true, opacity: 0.9, blending: THREE.AdditiveBlending, depthWrite: false, side: THREE.DoubleSide });
    const mesh = new THREE.Mesh(geo, mat);
    mesh.position.set(ex, ey, ez);
    mesh.quaternion.setFromUnitVectors(new THREE.Vector3(0, 1, 0), dir);
    mesh.scale.set(0.2, 0.2, 0.2);
    this.scene.add(mesh);
    this.plumes.push({ mesh, age: 0, life: C.KO_SMASH_MS / 1000 });
    const at = { x: ex, y: ey, z: ez };
    this.fx.burst(at, { x: dir.x, y: dir.y }, color, this.parts(C.KO_SMASH_PARTICLES), 12, 0.16, 0.8);
    this.fx.burst(at, null, 0xffffff, this.parts(C.KO_SMASH_PARTICLES / 2), 6, 0.1, 0.5);
    this.fx.ring(at, color, 5, 0.4);
    if (me) this.fx.shake(C.KO_SHAKE_ME, C.KO_SHAKE_MS);
    else if (near) this.fx.shake(C.KO_SHAKE_NEAR, C.KO_SHAKE_MS);
    this.flashEdge(at, color);
  }

  // 화면 끝 번쩍: 떨어진 자리가 화면의 어느 쪽인지 (카메라에 비춰) 그쪽 끝을 그 사람 색으로
  flashEdge(at, color) {
    this.edgeAt = at;
    this.edgeColor = `#${color.toString(16).padStart(6, '0')}`;
    this.edgeUntil = performance.now() + C.KO_EDGE_MS;
  }

  crush(p, me, near) {
    const base = { x: p.x, y: p.y, z: p.z + 0.1 };
    this.fx.burst(base, null, 0x9a8a7a, this.parts(C.KO_CRUSH_DUST), 7, 0.22, 1.0); // 먼지 크게
    this.fx.burst({ ...base, z: base.z + 0.6 }, null, 0x5d6b7a, this.parts(C.KO_CRUSH_CHIPS), 9, 0.16, 0.8); // 블록 조각
    this.fx.ring(base, 0xd8c8b0, 3.5, 0.35, true);
    if (me || near) {
      this.stopUntil = performance.now() + C.KO_CRUSH_STOP_MS; // 짧은 히트스톱
      this.fx.shake(me ? C.KO_SHAKE_ME : C.KO_SHAKE_NEAR, C.KO_SHAKE_MS);
    }
  }

  // 서버 finalKill 이벤트: 판을 끝낸 킬 → 잠깐 느리게 + 그 자리로 줌
  final(e, pos) {
    const p = pos || { x: e.x, y: e.y, z: e.z };
    const now = performance.now();
    this.slow = { start: now, until: now + C.KO_FINAL_MS, x: p.x, y: p.y, z: p.z };
    this.emit('final', { who: e.who, by: e.by, x: p.x, y: p.y, z: p.z, out: e.out, color: this.colorOf(e.who), winners: e.winners });
  }

  // 프레임 dt 에 곱할 값 (main.js): 압사 히트스톱이면 거의 멈춤, 마지막 킬이면 느리게 → 점점 원래대로
  timeScale(now = performance.now()) {
    if (now < this.stopUntil) return C.KO_CRUSH_STOP_SCALE;
    if (!this.slow || now >= this.slow.until) return 1;
    const t = (now - this.slow.start) / (this.slow.until - this.slow.start);
    return C.KO_FINAL_SCALE + (1 - C.KO_FINAL_SCALE) * Math.max(0, (t - 0.6) / 0.4); // 앞 60% 는 느리게, 뒤 40% 동안 원래 속도로
  }

  // render.js 가 카메라를 정한 뒤 그리기 직전에 부름: 마지막 킬 줌 (시야를 좁히고 그 자리를 봄)
  camHook(camera) {
    const now = performance.now();
    this.drawEdge(camera, now);
    if (!this.slow || now >= this.slow.until) return;
    const t = (now - this.slow.start) / (this.slow.until - this.slow.start);
    const k = Math.sin(Math.min(1, t) * Math.PI); // 0 → 1 → 0
    const target = new THREE.Vector3(this.slow.x, this.slow.y, this.slow.z + 0.8);
    const look = new THREE.Vector3(0, 0, -1).applyQuaternion(camera.quaternion).add(camera.position);
    look.lerp(target, k * C.KO_FINAL_LOOK);
    camera.lookAt(look);
    camera.fov *= 1 - k * (1 - C.KO_FINAL_ZOOM);
    camera.updateProjectionMatrix();
  }

  drawEdge(camera, now) {
    if (now >= this.edgeUntil || !this.edgeAt) {
      if (this.edgeEl.style.opacity !== '0') this.edgeEl.style.opacity = '0';
      return;
    }
    const v = new THREE.Vector3(this.edgeAt.x, this.edgeAt.y, this.edgeAt.z).project(camera);
    let sx = v.x;
    let sy = v.y;
    if (v.z > 1) {
      sx = -sx; // 카메라 뒤: 반대쪽
      sy = -sy;
    }
    const m = Math.max(Math.abs(sx), Math.abs(sy), 1e-6);
    if (m < 1) {
      sx /= m; // 화면 안이어도 가장 가까운 끝으로 밀어냄
      sy /= m;
    } else {
      sx /= m;
      sy /= m;
    }
    const px = ((sx + 1) / 2) * 100;
    const py = ((1 - sy) / 2) * 100;
    const k = (this.edgeUntil - now) / C.KO_EDGE_MS;
    this.edgeEl.style.background = `radial-gradient(ellipse 45% 45% at ${px}% ${py}%, ${this.edgeColor}cc 0%, ${this.edgeColor}55 35%, transparent 70%)`;
    this.edgeEl.style.opacity = String(Math.min(1, k * 1.5));
  }

  update(dt) {
    for (const pl of [...this.plumes]) {
      pl.age += dt;
      const t = pl.age / pl.life;
      if (t >= 1) {
        this.scene.remove(pl.mesh);
        pl.mesh.geometry.dispose();
        pl.mesh.material.dispose();
        this.plumes = this.plumes.filter((x) => x !== pl);
        continue;
      }
      const grow = Math.min(1, t * 4); // 빠르게 뻗고
      pl.mesh.scale.set(0.4 + grow * 0.8 * (1 - t * 0.5), 0.2 + grow, 0.4 + grow * 0.8 * (1 - t * 0.5));
      pl.mesh.material.opacity = 0.9 * (1 - t) ** 1.5; // 천천히 사라짐
    }
  }
}
