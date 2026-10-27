// 액티브 래그돌 (cannon-es). 판정은 서버 AABB 그대로, 몸 모습만 물리.
// 몸 조각 11개 (골반·가슴·머리·위팔·아래팔·허벅지·정강이)가 figure 관절마다 하나씩. 어깨는 공 관절, 나머지는 각도 제한 원뿔 (RAGDOLL_LIMITS).
// 매 프레임: figureAnim 이 정한 자세를 목표로 잡고 (capture) → 관절 모터(PD 토크)로 따라가며 물리를 돌리고 (step)
// → 조각의 회전을 figure 관절 회전으로 되돌려 넣음 (apply). 관절 위치·엉덩이 높이는 그대로라 옷·무기·납작·머리 박음은 그대로 붙음.
// 모터 세기는 ragdoll-math.js: 평소·공격 세게, 맞음·경직·낙사 약하게 (흐물흐물). 골반은 판정(보간) 위치를 강하게 따라감
import * as THREE from 'three';
import * as CANNON from 'cannon-es';
import { CONFIG as C } from '/shared/config.js';
import { ragdollMotor, pdAngular, rootPull, limbPull, quatDiffVec } from '/ragdoll-math.js';

const GROUND = 1;
const PART = 2;
const _p = new THREE.Vector3();
const _q = new THREE.Quaternion();
const _s = new THREE.Vector3();
const _v = new THREE.Vector3();
const _pq = new THREE.Quaternion();
const _cv = new CANNON.Vec3();
const _cv2 = new CANNON.Vec3();
const _cq = new CANNON.Quaternion();
const _acc = {};
const _pull = {};
const _lim = {};

// 몸 조각 정의: [이름, figure 관절, 부모 조각 번호, 반 크기(d → [x,y,z]), 관절에서 조각 가운데까지 z(d), 질량 키, 관절 제한 키]
function segDefs(fig) {
  const d = fig.d;
  const depth = d.depth || 0.75;
  return [
    ['pelvis', fig.hips, -1, [d.waistR * depth, Math.max(d.waistR, d.hipY + d.legR), 0.1], 0.02, 'pelvis', null], // figure.js pelvisGeo 와 같은 크기
    ['chest', fig.waist, 0, [d.chestR * depth, d.chestR, d.torso / 2], d.torso / 2, 'chest', 'waist'],
    ['head', fig.neck, 1, [d.headW / 2, d.headW / 2, d.head / 2], d.head / 2, 'head', 'neck'],
    ['upperR', fig.shoulders[0], 1, [d.armR, d.armR, d.upper / 2], -d.upper / 2, 'upper', null],
    ['upperL', fig.shoulders[1], 1, [d.armR, d.armR, d.upper / 2], -d.upper / 2, 'upper', null],
    ['foreR', fig.elbows[0], 3, [d.foreR, d.foreR, (d.lower + d.hand) / 2], -(d.lower + d.hand) / 2, 'fore', 'elbow'],
    ['foreL', fig.elbows[1], 4, [d.foreR, d.foreR, (d.lower + d.hand) / 2], -(d.lower + d.hand) / 2, 'fore', 'elbow'],
    ['thighR', fig.thighs[0], 0, [d.legR, d.legR, d.thigh / 2], -d.thigh / 2, 'thigh', 'hip'],
    ['thighL', fig.thighs[1], 0, [d.legR, d.legR, d.thigh / 2], -d.thigh / 2, 'thigh', 'hip'],
    ['shinR', fig.knees[0], 7, [d.legR * 0.85, d.legR * 0.85, (d.shin + d.foot) / 2], -(d.shin + d.foot) / 2, 'shin', 'knee'],
    ['shinL', fig.knees[1], 8, [d.legR * 0.85, d.legR * 0.85, (d.shin + d.foot) / 2], -(d.shin + d.foot) / 2, 'shin', 'knee'],
  ];
}

export class RagdollWorld {
  constructor() {
    this.world = new CANNON.World({ gravity: new CANNON.Vec3(0, 0, -C.RAGDOLL_GRAVITY) });
    this.world.broadphase = new CANNON.SAPBroadphase(this.world);
    this.world.solver.iterations = C.RAGDOLL_ITERATIONS;
    this.world.allowSleep = false;
    this.world.defaultContactMaterial.friction = C.RAGDOLL_FRICTION;
    this.world.defaultContactMaterial.restitution = 0.05;
    this.rags = new Map(); // id -> { fig, segs, constraints, motor, snap, hitId, mass }
    this.ground = new Map(); // "x,y,z" -> 정적 상자
    this.groundShape = new CANNON.Box(new CANNON.Vec3(0.5, 0.5, 0.5));
    this.acc = 0;
    this.stats = { ms: 0, steps: 0 }; // 마지막 프레임 물리 시간 (window.__tf.renderer.ragdoll.stats)
  }

  has(id) {
    return this.rags.has(id);
  }

  // 래그돌이 이 몸(fig)으로 만들어졌나 (캐릭터를 바꾸면 몸이 새로 만들어짐)
  figOf(id) {
    return this.rags.get(id)?.fig;
  }

  create(id, fig, char) {
    const S = C.FIGURE_SCALE;
    const segs = [];
    const constraints = [];
    let mass = 0;
    const weight = C.RAGDOLL_WEIGHT[(C.FIGURE_BODY && C.FIGURE_BODY[char]) || ''] ?? 1; // 체형별 무게 (무거우면 맞아도 덜 튐)
    for (const [name, joint, parent, half, cz, mk, lim] of segDefs(fig)) {
      const m = C.RAGDOLL_MASS[mk] * weight;
      const body = new CANNON.Body({
        mass: m,
        shape: new CANNON.Box(new CANNON.Vec3(half[0] * S, half[1] * S, Math.max(0.02, half[2] * S))),
        linearDamping: C.RAGDOLL_DAMPING,
        angularDamping: C.RAGDOLL_DAMPING,
        collisionFilterGroup: PART,
        collisionFilterMask: GROUND,
      });
      mass += m;
      this.world.addBody(body);
      segs.push({ name, joint, parent, body, cz, lim, rest: joint.rotation.clone(), tp: new THREE.Vector3(), tq: new THREE.Quaternion(), wq: new THREE.Quaternion(), tw: { x: 0, y: 0, z: 0 }, tv: new THREE.Vector3() });
    }
    // 관절: 자식 관절 원점 = 부모 관절 좌표의 joint.position. 조각 원점은 관절에서 z 로 cz 떨어진 가운데.
    // 각도 제한(RAGDOLL_LIMITS)이 있으면 원뿔: 부모 쪽 축(가운데 방향) 둘레 angle 안으로만 자식 축이 감 (무릎·팔꿈치가 반대로 안 꺾임)
    for (const sg of segs) {
      if (sg.parent < 0) continue;
      const pa = segs[sg.parent];
      const jp = sg.joint.position;
      const pivotA = new CANNON.Vec3(jp.x * S, jp.y * S, (jp.z - pa.cz) * S);
      const pivotB = new CANNON.Vec3(0, 0, -sg.cz * S);
      const L = sg.lim && C.RAGDOLL_LIMITS[sg.lim];
      let c;
      if (L) {
        // 가운데 방향: 기본 축(몸통·목은 위 +z, 팔다리는 아래 -z)을 부모 y 축으로 rotY 만큼 돌린 방향 (figure 관절 rotation.y 와 같은 부호)
        const u = L.up ? 1 : -1;
        const axisA = new CANNON.Vec3(u * Math.sin(L.rotY), 0, u * Math.cos(L.rotY));
        const axisB = new CANNON.Vec3(0, 0, u);
        c = new CANNON.ConeTwistConstraint(pa.body, sg.body, { pivotA, pivotB, axisA, axisB, angle: L.cone, twistAngle: L.twist ?? 0 });
        if (L.twist == null) c.equations = c.equations.filter((e) => e !== c.twistEquation); // 비틀림 제한 없음 (무릎·팔꿈치·엉덩이: 축이 기울어 있어 기준이 어긋남)
      } else c = new CANNON.PointToPointConstraint(pa.body, pivotA, sg.body, pivotB);
      c.collideConnected = false;
      this.world.addConstraint(c);
      constraints.push(c);
    }
    const rag = { fig, segs, constraints, motor: 1, snap: 0, hitId: null, mass, weight, fresh: true, rootV: new THREE.Vector3() };
    this.rags.set(id, rag);
    return rag;
  }

  // 래그돌을 끔: 물리에서 빼고 관절 회전을 처음 값으로 (figureAnim 이 안 건드리는 축이 물리 값으로 남지 않게)
  remove(id) {
    const rag = this.rags.get(id);
    if (!rag) return;
    for (const c of rag.constraints) this.world.removeConstraint(c);
    for (const sg of rag.segs) {
      this.world.removeBody(sg.body);
      sg.joint.rotation.copy(sg.rest);
    }
    this.rags.delete(id);
  }

  // figureAnim 전에: 관절 회전을 처음 값으로 (지난 프레임 물리 회전이 남지 않게)
  restore(id) {
    const rag = this.rags.get(id);
    if (rag) for (const sg of rag.segs) sg.joint.rotation.copy(sg.rest);
  }

  // figureAnim 뒤에: 지금 관절 자세를 목표로. g = 플레이어 그룹, st = ragdollMotor 입력, hit = { id, x, y, pow } (월드 방향) 또는 null
  capture(id, g, st, hit, dt) {
    const rag = this.rags.get(id);
    if (!rag) return;
    g.updateMatrixWorld(true);
    const root = rag.segs[0];
    for (const sg of rag.segs) {
      sg.joint.matrixWorld.decompose(_p, _q, _s);
      // 목표 각속도 = 지난 목표에서 이번 목표까지 돈 각 / dt
      if (rag.fresh || dt <= 0) Object.assign(sg.tw, { x: 0, y: 0, z: 0 });
      else {
        quatDiffVec(_q, sg.tq, sg.tw);
        sg.tw.x /= dt;
        sg.tw.y /= dt;
        sg.tw.z /= dt;
      }
      sg.tq.copy(_q);
      _v.copy(sg.tp);
      sg.tp.set(0, 0, sg.cz * _s.z).applyQuaternion(_q).add(_p);
      if (rag.fresh || dt <= 0) sg.tv.set(0, 0, 0);
      else sg.tv.copy(sg.tp).sub(_v).divideScalar(dt);
    }
    rag.rootV.copy(root.tv);
    const m = ragdollMotor(st);
    rag.motor = m.motor;
    rag.snap = m.snap;
    // 바닥·블록과 부딪힘은 힘이 빠졌을 때만 (세면 자세가 이미 발을 땅에 딛게 하므로 부딪힘이 자세와 싸우기만 함)
    const collide = m.motor < C.RAGDOLL_COLLIDE_BELOW;
    for (const sg of rag.segs) sg.body.collisionResponse = collide;
    if (rag.fresh) this.snapAll(rag);
    rag.fresh = false;
    if (hit && hit.id !== rag.hitId) {
      rag.hitId = hit.id;
      // 맞음: 가슴·머리를 밀린 쪽으로 툭 (골반은 판정 위치를 따라가니 윗몸이 포개짐)
      for (const k of [1, 2]) {
        const b = rag.segs[k].body;
        const j = (C.RAGDOLL_HIT_IMPULSE * hit.pow * b.mass) / rag.weight;
        b.applyImpulse(_cv.set(hit.x * j, hit.y * j, C.RAGDOLL_HIT_UP * j));
      }
    }
  }

  // 몸 전체를 목표 자세로 순간 맞춤 (처음·순간이동·너무 멀어짐)
  snapAll(rag) {
    for (const sg of rag.segs) {
      sg.body.position.set(sg.tp.x, sg.tp.y, sg.tp.z);
      sg.body.quaternion.set(sg.tq.x, sg.tq.y, sg.tq.z, sg.tq.w);
      sg.body.velocity.set(rag.rootV.x, rag.rootV.y, rag.rootV.z);
      sg.body.angularVelocity.set(0, 0, 0);
    }
  }

  // 판 바닥 (z < 0, 판 안은 다 단단함) = 판 크기 상자 하나. 판 크기가 바뀌면 다시
  updateFloor(w, d) {
    if (this.floorKey === `${w},${d}`) return;
    if (this.floor) this.world.removeBody(this.floor);
    this.floorKey = `${w},${d}`;
    this.floor = new CANNON.Body({ mass: 0, shape: new CANNON.Box(new CANNON.Vec3(w / 2, d / 2, 0.5)), position: new CANNON.Vec3(w / 2, d / 2, -0.5), collisionFilterGroup: GROUND, collisionFilterMask: PART });
    this.world.addBody(this.floor);
  }

  // 래그돌 둘레의 단단한 칸만 정적 상자로 (solid(x, y, z) = 그 점이 든 칸이 단단한가). 바닥 줄(z -1)은 updateFloor 가 맡음
  updateGround(solid) {
    const need = new Set();
    const R = C.RAGDOLL_GROUND_REACH;
    for (const rag of this.rags.values()) {
      const p = rag.segs[0].body.position;
      const bx = Math.floor(p.x), by = Math.floor(p.y), bz = Math.floor(p.z);
      for (let x = bx - R; x <= bx + R; x++) {
        for (let y = by - R; y <= by + R; y++) {
          for (let z = Math.max(0, bz - R); z <= bz + 1; z++) if (solid(x + 0.5, y + 0.5, z + 0.5)) need.add(`${x},${y},${z}`);
        }
      }
    }
    for (const [k, b] of this.ground) {
      if (!need.has(k)) {
        this.world.removeBody(b);
        this.ground.delete(k);
      }
    }
    for (const k of need) {
      if (this.ground.has(k)) continue;
      const [x, y, z] = k.split(',').map(Number);
      const b = new CANNON.Body({ mass: 0, shape: this.groundShape, position: new CANNON.Vec3(x + 0.5, y + 0.5, z + 0.5), collisionFilterGroup: GROUND, collisionFilterMask: PART });
      this.world.addBody(b);
      this.ground.set(k, b);
    }
  }

  // 물리 돌리기 (고정 걸음). 걸음마다 골반 끌어당김 + 관절 모터
  step(dt, solid, field) {
    const t0 = performance.now();
    this.stats.steps = 0;
    if (!this.rags.size) {
      this.stats.ms = 0;
      return;
    }
    this.updateFloor(field.w, field.d);
    this.updateGround(solid);
    this.acc = Math.min(this.acc + dt, C.RAGDOLL_STEP * C.RAGDOLL_MAX_STEPS);
    while (this.acc >= C.RAGDOLL_STEP) {
      this.acc -= C.RAGDOLL_STEP;
      for (const rag of this.rags.values()) this.drive(rag);
      this.world.step(C.RAGDOLL_STEP);
      this.stats.steps++;
    }
    for (const rag of this.rags.values()) {
      for (const sg of rag.segs) {
        const b = sg.body;
        if (![b.position.x, b.position.y, b.position.z, b.quaternion.w, b.velocity.x, b.angularVelocity.x].every(Number.isFinite)) {
          this.snapAll(rag); // 안전장치: 물리가 깨지면 목표 자세로
          break;
        }
      }
    }
    this.stats.ms = performance.now() - t0;
  }

  drive(rag) {
    const root = rag.segs[0];
    const rb = root.body;
    const pull = rootPull(rb.position, rb.velocity, root.tp, rag.rootV, rag.motor, _pull);
    if (pull.snap) {
      this.snapAll(rag);
      return;
    }
    // 골반: 판정 위치로. 다른 조각: 모터 세기만큼 자기 목표 위치로 + 힘이 빠진 만큼 골반 가속도 일부 (골반 혼자 몸 전체를 끌면 출렁여 깨짐)
    const share = C.RAGDOLL_ROOT_SHARE * (1 - Math.min(1, rag.motor));
    for (const sg of rag.segs) {
      const b = sg.body;
      if (sg.parent < 0) {
        b.force.x += pull.x * b.mass;
        b.force.y += pull.y * b.mass;
        b.force.z += pull.z * b.mass;
      } else {
        const l = limbPull(b.position, b.velocity, sg.tp, sg.tv, rag.motor, _lim);
        b.force.x += (l.x + pull.x * share) * b.mass;
        b.force.y += (l.y + pull.y * share) * b.mass;
        b.force.z += (l.z + pull.z * share) * b.mass;
      }
      const a = pdAngular(b.quaternion, sg.tq, b.angularVelocity, sg.tw, rag.motor, _acc);
      // 토크 = R · I · Rᵀ · 각가속도 (조각 관성 축 기준)
      b.quaternion.conjugate(_cq).vmult(_cv.set(a.x, a.y, a.z), _cv2);
      _cv2.x *= b.inertia.x;
      _cv2.y *= b.inertia.y;
      _cv2.z *= b.inertia.z;
      b.quaternion.vmult(_cv2, _cv);
      b.torque.vadd(_cv, b.torque);
    }
  }

  // 물리 자세를 figure 관절 회전으로 (부모부터). 공격 중엔 목표 자세 쪽으로 snap 만큼 섞음
  apply(id) {
    const rag = this.rags.get(id);
    if (!rag) return;
    for (const sg of rag.segs) {
      const bq = sg.body.quaternion;
      sg.wq.set(bq.x, bq.y, bq.z, bq.w);
      if (rag.snap > 0) sg.wq.slerp(sg.tq, rag.snap);
      if (sg.parent < 0) sg.joint.parent.getWorldQuaternion(_pq);
      else _pq.copy(rag.segs[sg.parent].wq);
      sg.joint.quaternion.copy(_pq.invert().multiply(sg.wq));
    }
  }

  // 이번 프레임에 래그돌로 그리지 않은 사람은 뺌
  prune(keep) {
    for (const id of [...this.rags.keys()]) if (!keep.has(id)) this.remove(id);
  }
}
