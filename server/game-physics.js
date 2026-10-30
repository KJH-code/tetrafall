// Game 메서드 묶음: 플레이어 물리: 이동·중력·충돌. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { EPS, cellKey } from './game-util.js';

export class PhysicsPart {
  // ---------- 플레이어 물리 ----------
  moveDir(p) {
    const f = p.input.fwd;
    const s = p.input.strafe;
    if (!f && !s) return null;
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const rx = Math.sin(p.yaw);
    const ry = -Math.cos(p.yaw);
    let x = fx * f + rx * s;
    let y = fy * f + ry * s;
    const len = Math.hypot(x, y) || 1;
    return { x: x / len, y: y / len };
  }

  integratePlayer(p, dt) {
    if (p.ghostUntil && this.time >= p.ghostUntil) {
      p.ghostUntil = 0;
      this.ejectFromBlocks(p);
    }
    if (p.shieldUntil && this.time >= p.shieldUntil) {
      p.shieldUntil = 0; // 무적 동안 블록이 통과했으면 꼭대기로
      this.ejectFromBlocks(p);
    }
    if (this.time < p.freezeUntil) return; // 히트스톱
    const stunned = this.time < p.stunUntil;
    let ix = 0;
    let iy = 0;
    if (p.grounded) {
      p.airJumps = C.AIR_JUMPS; // 땅에 닿아 있으면 2단 점프 다시 (같은 틱에 땅에서 뛰어도 채운 뒤)
      p.airDashes = C.AIR_DASHES; // 공중 대시도
    }
    if (this.time < p.chargeUntil) {
      ix = p.chargeDir.x * C.TANK_CHARGE_SPEED; // 탱크 돌진: 입력 대신 앞으로
      iy = p.chargeDir.y * C.TANK_CHARGE_SPEED;
    } else if (p.leap && p.leap.endAt && this.time < p.leap.endAt) {
      ix = p.leap.vx; // 사냥꾼 도약 중: 입력 대신 덮칠 자리로
      iy = p.leap.vy;
    } else if (p.rush && this.time < p.rush.endAt) {
      ix = p.rush.vx; // 광전사 도약 중: 입력 대신 앞으로
      iy = p.rush.vy;
    } else if (this.time < p.zipUntil) {
      ix = p.zipDir.x * C.HOOK_ZIP_SPEED; // 갈고리 블록 걸기: 블록 쪽으로 끌려감
      iy = p.zipDir.y * C.HOOK_ZIP_SPEED;
    } else if (!stunned && !this.isEmoting(p)) {
      const mv = this.moveDir(p);
      if (mv) {
        const speed =
          C.MOVE_SPEED *
          (this.time < p.speedUntil ? C.SPEED_MULT : 1) *
          (p.atk && p.atk.def.finish ? C.BASIC_FINISH_MOVE_MULT : 1) * // 평타 마무리 준비 중
          (p.spin ? C.BERSERKER_SPIN_MOVE_MULT : 1) * // 광전사 회전 중 (천천히 쫓아감)
          (p.amp ? C.BARD_AMP_MOVE_MULT : 1) * // 바드 앰프 연주 중
          (this.time < p.slowUntil ? 1 - C.BARD_SLOW : 1) * // 둔화
          (p.dive ? C.BARD_DIVE_MOVE_MULT : 1); // 기타 꽂기 낙하 중
        ix = mv.x * speed;
        iy = mv.y * speed;
      }
      if ((p.input.jump || this.time < p.jumpQueuedUntil) && p.grounded) {
        p.vz = this.time < p.jumpUntil ? C.JUMP_BOOST_SPEED : C.JUMP_SPEED;
        p.grounded = false;
        p.jumpQueuedUntil = 0;
      } else if (p.airJumpQueued && !p.grounded && p.airJumps > 0) {
        // 2단 점프: 공중에서 점프를 새로 누르면('jump' 행동) 한 번 더. 땅에 닿으면 다시 생김
        p.vz = C.AIR_JUMP_SPEED;
        p.airJumps--;
        this.emit({ type: 'airJump', who: p.id });
      }
    }
    p.airJumpQueued = false;
    const damp = Math.exp(-(p.grounded ? C.KB_DAMPING_GROUND : C.KB_DAMPING_AIR) * dt);
    p.kbx *= damp;
    p.kby *= damp;
    if (Math.abs(p.kbx) < 0.01) p.kbx = 0;
    if (Math.abs(p.kby) < 0.01) p.kby = 0;
    if (p.grounded && !p.dive) {
      p.glideCount = 0; // 땅·블록(하늘 블록 포함)에 서면 천천히 낙하 횟수 다시
      p.diveUsed = false; // 기타 꽂기도
    }
    if (p.glideUntil && (p.grounded || this.time >= p.glideUntil)) p.glideUntil = 0;
    p.vz -= C.GRAVITY * (p.glideUntil ? C.BARD_GLIDE_GRAVITY : 1) * dt; // 바드 천천히 낙하: 중력 줄임
    if (p.glideUntil && p.vz < -C.BARD_GLIDE_FALL) p.vz = -C.BARD_GLIDE_FALL;
    if (p.dive && p.vz > -C.BARD_DIVE_SPEED) p.vz = -C.BARD_DIVE_SPEED; // 기타 꽂기: 빠르게 아래로
    this.moveAxis(p, 'x', (ix + p.kbx) * dt);
    this.moveAxis(p, 'y', (iy + p.kby) * dt);
    p.grounded = false;
    this.moveAxis(p, 'z', p.vz * dt);
  }

  aabb(p) {
    return {
      x0: p.x - C.PLAYER_HALF,
      x1: p.x + C.PLAYER_HALF,
      y0: p.y - C.PLAYER_HALF,
      y1: p.y + C.PLAYER_HALF,
      z0: p.z,
      z1: p.z + C.PLAYER_HEIGHT,
    };
  }

  overlappingSolid(b) {
    const out = [];
    const cx0 = Math.floor(b.x0 + EPS);
    const cx1 = Math.floor(b.x1 - EPS);
    const cy0 = Math.floor(b.y0 + EPS);
    const cy1 = Math.floor(b.y1 - EPS);
    const cz0 = Math.floor(b.z0 + EPS);
    const cz1 = Math.floor(b.z1 - EPS);
    for (let cz = cz0; cz <= cz1; cz++) {
      for (let cy = cy0; cy <= cy1; cy++) {
        for (let cx = cx0; cx <= cx1; cx++) {
          if (this.solidAt(cx, cy, cz)) out.push([cx, cy, cz]);
        }
      }
    }
    return out;
  }

  moveAxis(p, axis, delta) {
    if (delta === 0) return;
    const prevZ = p.z;
    p[axis] += delta;
    let hits = this.overlappingSolid(this.aabb(p));
    if (hits.length && this.isGhost(p)) {
      // 유령: 옆·위로는 통과. 아래로는 "원래 그 위에 있던" 칸에만 착지 (한쪽 통과 발판)
      if (axis !== 'z' || delta > 0) return;
      hits = hits.filter((h) => h[2] + 1 <= prevZ + 1e-6);
    }
    if (!hits.length) return;
    const ai = axis === 'x' ? 0 : axis === 'y' ? 1 : 2;
    if (axis === 'z') {
      if (delta < 0) {
        let top = -Infinity;
        for (const h of hits) if (h[2] + 1 > top) top = h[2] + 1;
        p.z = top;
        p.vz = 0;
        p.grounded = true;
      } else {
        let bottom = Infinity;
        for (const h of hits) if (h[2] < bottom) bottom = h[2];
        p.z = bottom - C.PLAYER_HEIGHT;
        p.vz = 0;
      }
      return;
    }
    if (delta > 0) {
      let edge = Infinity;
      for (const h of hits) if (h[ai] < edge) edge = h[ai];
      p[axis] = edge - C.PLAYER_HALF;
    } else {
      let edge = -Infinity;
      for (const h of hits) if (h[ai] + 1 > edge) edge = h[ai] + 1;
      p[axis] = edge + C.PLAYER_HALF;
    }
    // 넉백으로 날아가다 벽에 박히면 그 속도를 위로 바꿔 넘김 (맞을 때마다 한 번). 오르는 동안은 수평 넉백을 살려 둬서 넘으면 계속 날아감
    const kb = axis === 'x' ? 'kbx' : 'kby';
    const speed = Math.abs(p[kb]);
    if (this.time < p.stunUntil && speed >= C.WALL_BOUNCE_MIN_SPEED) {
      if (!p.wallBounced) {
        p.wallBounced = true;
        p.vz = Math.max(p.vz, Math.min(C.WALL_BOUNCE_MAX_UP, speed * C.WALL_BOUNCE_RATIO));
        p.grounded = false;
      }
      if (p.vz > 0) return;
    }
    p[kb] = 0;
  }

  // 발밑 칸 종류 (GROUND_LOG 키): 몸 가운데 → 네 모서리 순으로 처음 닿는 칸. 필드 바닥 'floor', 맵 지형 'terrain',
  // 쌓인 블록(떨어진 블록·건축가·설치 블록) 'stack', 하늘 계단 블록 'sky', 떨어지는 보통 블록 'piece'
  groundKind(p) {
    const cz = Math.round(p.z) - 1;
    if (cz < 0) return 'floor';
    const h = C.PLAYER_HALF * 0.9;
    for (const [ox, oy] of [[0, 0], [-h, -h], [h, -h], [-h, h], [h, h]]) {
      const x = Math.floor(p.x + ox);
      const y = Math.floor(p.y + oy);
      const id = this.pieceCells.get(cellKey(x, y, cz));
      if (id !== undefined) return this.pieces.find((pc) => pc.id === id)?.sky ? 'sky' : 'piece';
      const v = this.gridAt(x, y, cz);
      if (v) return v === CELL.TERRAIN ? 'terrain' : 'stack';
    }
    return 'stack'; // 칸 경계에 걸쳐 서 있음 (건축가 블록이 막 사라진 칸 등): 블록 위로 셈
  }
}
