// 1인칭 팔·무기 (뷰모델): 내 3인칭 몸(figure.js)을 복제해 팔과 무기만 화면 아래에 따로 그린다.
// 관절은 매 프레임 3인칭 몸에서 그대로 베낌 → 평타·F·R 동작, 장전 불꽃·분노 같은 표시를 그대로 재사용.
// 어깨 각만 바꿔 손이 화면 아래 구석에 오게 하고 (내린 팔 → 앞으로 든 팔), 몸통 흔들림은 조금만 따라감.
// 따로 그리는 장면 + 깊이를 지우고 그림 → 벽에 박히지 않고, FOV 도 따로 (VM_FOV)
import * as THREE from 'three';
import { CONFIG as C } from '/shared/config.js';
import { toon } from '/toon.js';

const LAYER = 2; // 뷰모델 카메라는 이 층만 그림 (복제한 몸 중 팔·무기만 이 층)
const HALF_PI = Math.PI / 2;

// 손에 쥔 표창 (네 날 별, 날아가는 표창보다 작게)
let _starGeo = null;
let _starMat = null;
function starGeo() {
  if (!_starGeo) {
    const sh = new THREE.Shape();
    for (let i = 0; i < 8; i++) {
      const r = i % 2 ? 0.025 : 0.085;
      const ang = (i / 8) * Math.PI * 2;
      if (i) sh.lineTo(Math.cos(ang) * r, Math.sin(ang) * r);
      else sh.moveTo(r, 0);
    }
    _starGeo = new THREE.ExtrudeGeometry(sh, { depth: 0.01, bevelEnabled: false });
  }
  return _starGeo;
}
function starMat() {
  return (_starMat ||= toon({ color: 0xc8d0dc }));
}

export class ViewModel {
  constructor() {
    this.scene = new THREE.Scene();
    this.camera = new THREE.PerspectiveCamera(C.VM_FOV, 1, 0.01, 20);
    this.camera.layers.set(LAYER);
    this.scene.add(this.camera);
    // 빛: 필드와 같은 노을 반구광 + 위·왼쪽 앞에서 비추는 해 (카메라에 붙어 시선이 바뀌어도 팔 밝기는 같음)
    const hemi = new THREE.HemisphereLight(0xffe2d2, 0x8a90b8, 1.15);
    const sun = new THREE.DirectionalLight(C.SUN_COLOR, 1.25);
    sun.position.set(-1, 2, 1);
    for (const l of [hemi, sun]) {
      l.layers.enable(LAYER);
      this.camera.add(l);
    }
    // 몸 좌표(앞 +x, 왼쪽 +y, 위 +z) → 카메라 좌표(앞 -z, 오른쪽 +x, 위 +y)
    this.anchor = new THREE.Group();
    this.baseQuat = new THREE.Quaternion().setFromRotationMatrix(new THREE.Matrix4().makeBasis(new THREE.Vector3(0, 0, -1), new THREE.Vector3(-1, 0, 0), new THREE.Vector3(0, 1, 0)));
    this.anchor.quaternion.copy(this.baseQuat);
    this.camera.add(this.anchor);
    this.src = null; // 지금 베끼는 3인칭 몸 (Group)
    this.pairs = []; // [원본, 복제] 관절·부품
    this.on = false;
  }

  // g: 내 3인칭 몸 (render.js playerMeshes). 바뀌면(캐릭터 바꿈·다시 들어옴) 다시 복제
  sync(g) {
    if (this.src === g) return;
    this.src = g;
    this.anchor.clear();
    this.pairs = [];
    this.fig = null;
    const fig = g && g.userData.figure;
    if (!fig) return;
    // userData 에 몸·재질 참조가 있어 clone 이 JSON 으로 못 베낌 → 잠깐 비우고 복제 (재질·모양은 원본과 같이 씀: 플레이어 색도 같이 바뀜)
    const saved = [];
    g.traverse((o) => {
      saved.push([o, o.userData]);
      o.userData = {};
    });
    const copy = g.clone(true);
    for (const [o, u] of saved) o.userData = u;
    const a = [];
    const b = [];
    g.traverse((o) => a.push(o));
    copy.traverse((o) => b.push(o));
    const twin = new Map(a.map((o, i) => [o, b[i]]));
    const waist = twin.get(fig.waist);
    // 허리 아래부터 베낌 (허리 자신은 따로: 몸통이 크게 숙이거나 돌아도 팔이 화면에서 안 사라지게)
    fig.waist.traverse((o) => {
      if (o !== fig.waist) this.pairs.push([o, twin.get(o)]);
    });
    const d = fig.d;
    waist.position.set(0, 0, -(d.torso - d.armR * 1.6)); // 어깨 높이가 기준점
    this.anchor.add(waist);
    // 화면에서 비스듬히 (바드 악기 목이 조준점 아래를 가로지르지 않게 오른쪽으로 세움)
    const roll = (C.VM_ROLL || {})[g.userData.look] || 0;
    this.anchor.quaternion.copy(this.baseQuat).premultiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), roll));
    this.anchor.scale.setScalar(C.FIGURE_SCALE * C.VM_SCALE * ((C.VM_SIZE || {})[g.userData.look] || 1)); // 굵은 몸(탱크·건축가)은 작게
    // 그릴 것: 팔꿈치 아래 (아래팔 소매·보호대·장갑·든 무기) + 캐릭터 무기 중 몸통에 붙은 것 (탱크 앞 방패, 대포수 어깨 대포, 바드 악기).
    // 윗팔·어깨 장식은 카메라 바로 옆이라 화면을 덮어서 안 그림
    const show = [...fig.elbows];
    if (fig.shields) show.push(fig.shields.front);
    if (fig.cannon) show.push(fig.cannon);
    if (fig.lute) show.push(fig.lute.lute);
    if (fig.guitar) show.push(fig.guitar);
    for (const o of show) twin.get(o).traverse((m) => m.layers.set(LAYER));
    // 캐릭터별 1인칭 소품
    this.star = null;
    if (g.userData.look === 'ninja') {
      // 닌자: 왼손엔 단검 대신 부채꼴로 쥔 표창 3개 (던지면 잠깐 비었다가 다시 쥠)
      const left = twin.get(fig.hands[1]);
      for (const o of fig.hands[1].children) if (o.userData.dagger) twin.get(o).layers.set(0);
      this.star = new THREE.Group();
      for (let i = 0; i < 3; i++) {
        const m = new THREE.Mesh(starGeo(), starMat());
        m.position.set(0.01 * i, 0, -0.02 * i);
        m.rotation.set(Math.PI / 2, 0.5 * (i - 1), 0);
        m.layers.set(LAYER);
        this.star.add(m);
      }
      this.star.position.set(0.02, 0, -fig.d.hand * 1.4);
      left.add(this.star);
    }
    this.pips = null;
    if (fig.cannon && fig.balls) {
      // 대포수: 대포 등에 남은 포탄 수만큼 쇠공 (허리 뒤 포탄은 1인칭에서 안 보여서)
      const cannon = twin.get(fig.cannon);
      this.pips = fig.balls.map((b, i) => {
        const m = new THREE.Mesh(b.geometry, b.material);
        m.scale.setScalar(C.VM_PIP_SCALE);
        m.position.set(0.05 + i * 0.13, 0, 0.14);
        m.layers.set(LAYER);
        cannon.add(m);
        return m;
      });
    }
    this.veins = null;
    if (fig.rage) {
      // 광전사: 분노가 차면 아래팔에도 핏줄 (머리 핏줄과 같이 벌떡벌떡)
      const mat = fig.rage.veins[0]?.material || toon({ color: 0x9a1020 });
      this.veins = fig.elbows.map((el) => {
        const g = new THREE.Group();
        // 갈라지는 핏줄 한 가닥 (줄기 + 양쪽 가지). 팔꿈치 쪽 (가운데는 가죽 팔목 보호대)
        for (const [y, z, len, rot] of [[0, 0.06, 0.08, 0], [0.012, 0.11, 0.04, 0.6], [-0.012, 0.12, 0.04, -0.6]]) {
          const v = new THREE.Mesh(new THREE.BoxGeometry(0.008, 0.008, len), mat);
          v.position.set(fig.d.foreR * 1.0, y, -z);
          v.rotation.x = rot;
          v.layers.set(LAYER);
          g.add(v);
        }
        twin.get(el).add(g);
        return g;
      });
    }
    this.raw = (C.VM_RAW_POSE || []).includes(g.userData.look);
    this.spin = (C.VM_SPIN || []).includes(g.userData.look); // 바드 활강처럼 계속 도는 건 화면을 덮어서 뺌
    this.cannon = fig.cannon ? twin.get(fig.cannon) : null;
    this.shield = fig.shields ? twin.get(fig.shields.front) : null; // 팔을 이미 몸 앞에 드는 캐릭터 (바드: 악기를 가슴에)
    this.thrownAt = -1e9;
    this.fig = fig;
    this.twin = { waist, shoulders: fig.shoulders.map((o) => twin.get(o)), elbows: fig.elbows.map((o) => twin.get(o)) };
    this.char = g.userData.look;
  }

  // 매 프레임: 관절 베끼기 + 어깨 각 바꾸기 + 걷기·숨쉬기 흔들림
  update(dt) {
    const fig = this.fig;
    if (!fig || !this.on) return;
    for (const [s, t] of this.pairs) {
      t.position.copy(s.position);
      t.quaternion.copy(s.quaternion);
      t.scale.copy(s.scale);
      t.visible = s.visible;
    }
    if (this.cannon) {
      // 어깨 대포는 카메라 바로 옆이라 그대로면 화면 오른쪽을 다 덮음 → 작게, 오른쪽 아래로
      this.cannon.scale.multiplyScalar(C.VM_CANNON[0]);
      this.cannon.position.y += C.VM_CANNON[1];
      this.cannon.position.z += C.VM_CANNON[2];
    }
    if (this.shield) {
      // 탱크 앞 방패: 그대로면 조준점 아래 가운데를 꽉 채움 → 작게, 왼쪽 아래로 비스듬히 (왼팔 방패)
      this.shield.scale.multiplyScalar(C.VM_SHIELD[0]);
      this.shield.position.y += C.VM_SHIELD[1];
      this.shield.position.z += C.VM_SHIELD[2];
      this.shield.rotation.z += C.VM_SHIELD[3];
    }
    const k = C.VM_BODY_FOLLOW;
    const w = fig.waist.rotation;
    // 몸 전체 돌기(광전사 소용돌이·회전 베기·갈고리 스핀)는 VM_SPIN 캐릭터만 그대로: 무기를 든 팔이 화면을 휩쓸고 지나감
    this.twin.waist.rotation.set(w.x * k, (w.y - fig.d.hunch) * k, w.z * k + (this.spin ? fig.hips.rotation.z : 0));
    for (let i = 0; i < 2; i++) {
      if (this.raw) continue;
      const side = i ? 1 : -1;
      const sh = fig.shoulders[i].rotation;
      const fwd = -sh.y;
      const out = side * sh.x;
      // 내린 팔(0)~앞으로 든 팔(π/2) 을 VM_ARM_LOW~π/2 로 눌러 담음 → 가만히 있어도 손이 화면 아래에 보이고, 앞으로 뻗으면 그대로 앞
      const up = Math.min(1, Math.max(0, fwd / HALF_PI));
      const f2 = fwd < HALF_PI ? C.VM_ARM_LOW + up * (HALF_PI - C.VM_ARM_LOW) : fwd;
      const ts = this.twin.shoulders[i];
      ts.rotation.set(side * out * C.VM_ARM_OUT, -f2, sh.z);
      ts.position.y = fig.shoulders[i].position.y * C.VM_NARROW; // 두 팔을 화면 가운데 쪽으로
      // 아래로 내린 팔일수록 팔꿈치를 더 굽혀 주먹이 올라오게
      this.twin.elbows[i].rotation.y = fig.elbows[i].rotation.y - C.VM_ELBOW_ADD * (1 - up);
    }
    // 갈고리: 장전된 권총은 앞으로 겨눔 (3인칭은 가슴 앞에 든 자세라 1인칭에선 총구가 하늘로 감). 탕 동작(팔이 더 올라감)은 그대로
    if (fig.gun?.loaded && -fig.shoulders[0].rotation.y < 0.6) {
      this.twin.shoulders[0].rotation.y = -C.VM_GUN_AIM[0];
      this.twin.elbows[0].rotation.y = -C.VM_GUN_AIM[1];
    }
    if (this.pips) this.pips.forEach((m, i) => (m.visible = fig.balls[i].visible));
    if (this.veins) {
      const r = fig.rage.k;
      const beat = 1 + 0.3 * Math.max(0, Math.sin((this.src.userData.anim.t || 0) * 9)) * r;
      for (const g of this.veins) {
        g.visible = r > 0.35;
        g.scale.set(beat, beat, 1);
      }
    }
    if (this.star) {
      // 표창: 던진 직후 잠깐 빈손, 그 뒤 다시 쥠 (작게 튀어나옴)
      const u = (performance.now() - this.thrownAt) / C.VM_STAR_HIDE_MS;
      this.star.visible = u >= 1;
      this.star.scale.setScalar(u >= 1 ? Math.min(1, 0.4 + (u - 1) * 3) : 0.01);
    }
    // 걷기 흔들림 (걸음 위상 따라 위아래·좌우), 가만히 있으면 숨쉬기
    const an = this.src.userData.anim;
    const amp = Math.min(1, (an.hs || 0) / C.MOVE_SPEED);
    const t = an.t || 0;
    const [x, y, z] = C.VM_POS[this.char] || C.VM_POS.default;
    this.anchor.position.set(
      x + Math.sin(an.walk || 0) * C.VM_BOB * 0.6 * amp,
      y - Math.abs(Math.cos(an.walk || 0)) * C.VM_BOB * amp + Math.sin(t * 2) * C.VM_BREATH,
      z,
    );
  }

  // 내가 표창을 던짐 (render.js starShot)
  starThrown() {
    this.thrownAt = performance.now();
  }

  // 필드를 그린 뒤 위에 겹쳐 그림 (깊이만 지움)
  draw(renderer, outline, aspect) {
    if (!this.fig || !this.on) return;
    if (this.camera.aspect !== aspect) {
      this.camera.aspect = aspect;
      this.camera.updateProjectionMatrix();
    }
    renderer.clearDepth();
    if (outline) {
      const ac = outline.autoClear;
      outline.autoClear = false;
      outline.render(this.scene, this.camera);
      outline.autoClear = ac;
    } else {
      const ac = renderer.autoClear;
      renderer.autoClear = false;
      renderer.render(this.scene, this.camera);
      renderer.autoClear = ac;
    }
  }
}
