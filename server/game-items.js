// Game 메서드 묶음: 아이템·손 아이템(설치 블록·폭탄)·투사체. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { cellKey, overlapsCell } from './game-util.js';

export class ItemsPart {
  fire(p) {
    p.ammo--;
    const cp = Math.cos(p.pitch);
    const dx = cp * Math.cos(p.yaw);
    const dy = cp * Math.sin(p.yaw);
    const dz = Math.sin(p.pitch);
    this.projectiles.push({
      x: p.x + dx * 0.6,
      y: p.y + dy * 0.6,
      z: p.z + C.EYE_HEIGHT + dz * 0.6,
      dx,
      dy,
      dz,
      owner: p.id,
      dieAt: this.time + C.PROJECTILE_LIFE_MS,
    });
    this.emit({ type: 'fire', who: p.id });
    this.log(`  [발사] ${p.name} (남은 탄 ${p.ammo})`);
  }

  // 설치 블록이 떨어질 칸들과 착지 높이. 눈에서 조준 방향으로 시선을 따라가다 BRICK_MIN_DIST~BRICK_RANGE 사이에서
  // 지형(기둥 꼭대기·바닥)에 처음 닿는 칸이 기준. 안 닿으면 BRICK_RANGE 끝 칸 (필드를 벗어나면 마지막 필드 안 칸).
  // 1×2 는 바라보는 방향을 가로·세로 중 가까운 쪽으로 맞춰 앞(또는 Q/E 로 옆)으로 한 칸 더, 2×2 는 앞·왼쪽으로.
  // ok 가 false 면 못 던짐 (소모 안 함)
  // 던지는 것(설치 블록·폭탄)의 기준 칸 [x, y] 또는 null
  aimAnchor(p, yaw = p.yaw, pitch = p.pitch) {
    const cp = Math.cos(pitch);
    const dx = cp * Math.cos(yaw);
    const dy = cp * Math.sin(yaw);
    const dz = Math.sin(pitch);
    const hlen = Math.hypot(dx, dy);
    const ez = p.z + C.EYE_HEIGHT;
    let anchor = null;
    // 수평 거리로 0.05칸씩 (거의 수직으로 보면 hlen ≈ 0 이라 시선 길이로 세면 안 끝난다)
    for (let h = C.BRICK_MIN_DIST; hlen > 1e-6 && h <= C.BRICK_RANGE; h += 0.05) {
      const t = h / hlen;
      const cx = Math.floor(p.x + dx * t);
      const cy = Math.floor(p.y + dy * t);
      if (!this.inXY(cx, cy)) break;
      anchor = [cx, cy];
      if (ez + dz * t <= this.columnTop(cx, cy)) break; // 시선이 지형에 닿음
    }
    return anchor;
  }

  brickPlan(p, yaw = p.yaw, pitch = p.pitch) {
    const anchor = this.aimAnchor(p, yaw, pitch);
    if (!anchor) return { cells: [], z: 0, ok: false };
    const fx = Math.cos(yaw);
    const fy = Math.sin(yaw);
    const along = Math.abs(fx) >= Math.abs(fy) ? [Math.sign(fx), 0] : [0, Math.sign(fy)];
    const left = [-along[1], along[0]];
    const [ax, ay] = anchor;
    const offs = [[0, 0], p.brickSide ? left : along];
    const cells = offs.map(([ox, oy]) => [ax + ox, ay + oy]);
    if (!cells.every(([x, y]) => this.inXY(x, y))) return { cells: cells.map(([x, y]) => [x, y, 0]), z: 0, ok: false };
    const z = Math.max(...cells.map(([x, y]) => this.columnTop(x, y)));
    const spawnZ = Math.min(z + C.BRICK_DROP_HEIGHT, this.H - 1);
    const ok =
      z < this.H - 1 &&
      !cells.some(([x, y]) => this.pieceCells.has(cellKey(x, y, spawnZ))) && // 생길 자리에 떨어지는 블록이 있음
      !cells.some(([x, y]) => overlapsCell(p, x, y, p.z)); // 내 머리 위 (xy 가 내 몸과 겹침)
    return { cells: cells.map(([x, y]) => [x, y, z]), z, spawnZ, ok };
  }

  // 조준한 칸 위 공중에 블록을 만들어 떨어뜨린다. 떨어지는 동안은 보통 블록과 같다 (그림자·압사·공중에서 서로 막힘)
  throwBrick(p) {
    const plan = this.brickPlan(p);
    if (!plan.ok) return false;
    p.bricks--;
    const [ax, ay] = plan.cells[0];
    const piece = {
      id: 0,
      shape: '1×2',
      rot: 0,
      cells: plan.cells.map(([x, y]) => [x - ax, y - ay]),
      px: ax,
      py: ay,
      pz: plan.spawnZ,
      landZ: 0,
      fits: false,
    };
    this.updateLanding(piece);
    this.addPiece(piece, { phase: 'falling', controller: null, thrownBy: p.id, stepMs: C.BRICK_FALL_STEP_MS, nextStepAt: this.time + C.BRICK_FALL_STEP_MS, controlEndsAt: 0 });
    this.emit({ type: 'throw', who: p.id, cells: plan.cells });
    this.log(`  [투척] ${p.name} ${piece.shape} → (${ax},${ay}) z=${plan.z} (남은 ${p.bricks}개)`);
    if (p.bricks === 0) p.brickSide = false;
    return true;
  }

  // ---- 폭탄 (핫바 3번) ----
  // 설치 블록과 같은 조준. cells 는 미리보기용 부서질 범위 (가로세로 ±BOMB_RADIUS), 첫 칸이 폭탄 자리
  bombPlan(p, yaw = p.yaw, pitch = p.pitch) {
    const anchor = this.aimAnchor(p, yaw, pitch);
    if (!anchor) return { cells: [], ok: false };
    const [ax, ay] = anchor;
    const z = this.columnTop(ax, ay);
    const cells = [[ax, ay, z]];
    const R = C.BOMB_RADIUS;
    for (let dx = -R; dx <= R; dx++) for (let dy = -R; dy <= R; dy++) if ((dx || dy) && this.inXY(ax + dx, ay + dy)) cells.push([ax + dx, ay + dy, z]);
    return { cells, ok: z < this.H };
  }

  throwBomb(p) {
    if (p.bombs <= 0) return false;
    const plan = this.bombPlan(p);
    if (!plan.ok) return false;
    p.bombs--;
    const [x, y, z] = plan.cells[0];
    this.bombs.push({ id: ++this.bombCounter, x, y, z, by: p.id, explodeAt: this.time + C.BOMB_FUSE_MS });
    this.emit({ type: 'bombPlace', who: p.id, x, y, z });
    this.log(`  [폭탄] ${p.name} → (${x},${y}) z=${z} 설치, ${C.BOMB_FUSE_MS / 1000}초 뒤 폭발`);
    return true;
  }

  updateBombs() {
    for (const b of [...this.bombs]) {
      b.z = this.columnTop(b.x, b.y);
      if (this.time < b.explodeAt) continue;
      this.bombs.splice(this.bombs.indexOf(b), 1);
      this.explodeBomb(b);
    }
  }

  // 폭탄 칸 중심 ±BOMB_RADIUS 정육면체 블록을 부수고 BOMB_BLAST_RANGE 안의 사람을 날린다 (던진 사람 면제)
  explodeBomb(b) {
    const R = C.BOMB_RADIUS;
    let removed = 0;
    for (let x = b.x - R; x <= b.x + R; x++) {
      for (let y = b.y - R; y <= b.y + R; y++) {
        for (let z = b.z - R; z <= b.z + R; z++) {
          if (!this.inXY(x, y) || z < 0 || z >= this.H || !this.grid[this.idx(x, y, z)]) continue;
          this.grid[this.idx(x, y, z)] = 0;
          removed++;
        }
      }
    }
    const by = this.players.get(b.by);
    const cx = b.x + 0.5;
    const cy = b.y + 0.5;
    const cz = b.z + 0.5;
    this.emit({ type: 'boom', who: b.by, x: cx, y: cy, z: cz });
    this.log(`  [폭탄] ${by ? by.name : '?'} 의 폭탄 폭발 (${b.x},${b.y}) z=${b.z}, 블록 ${removed}칸 파괴`);
    for (const t of this.players.values()) {
      if (!this.onField(t) || t.id === b.by || this.sameTeam(by, t)) continue; // 같은 팀은 안 맞음
      const dx = t.x - cx;
      const dy = t.y - cy;
      if (Math.hypot(dx, dy) > C.BOMB_BLAST_RANGE || Math.abs(t.z + C.PLAYER_HEIGHT / 2 - cz) > C.BOMB_BLAST_RANGE) continue;
      const a = this.rng() * Math.PI * 2; // 바로 위에 서 있으면 방향이 없어서 무작위
      const hit = Math.hypot(dx, dy) > 0.05
        ? this.applyKnockback(t, dx, dy, C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN.bomb, { by: b.by, kind: 'bomb' }, true)
        : this.applyKnockback(t, Math.cos(a), Math.sin(a), C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN.bomb, { by: b.by, kind: 'bomb' }, true);
      this.emit({ type: 'hit', kind: 'bomb', by: b.by, target: t.id, ok: hit });
      this.log(`  [폭탄] ${by ? by.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
    }
    if (removed) this.gridChanged();
  }

  // 손에 든 것으로 우클릭하면 생길 것 (클라이언트 미리보기)
  aimPreview(p) {
    if (p.bricks > 0) return { kind: 'brick', ...this.brickPlan(p) };
    if (p.bombs > 0) return { kind: 'bomb', ...this.bombPlan(p) };
    return null;
  }

  // 던진 블록이 착지하면 바로 옆(BRICK_SHOCK_RANGE 안)에 있던 사람을 바깥쪽으로 날린다
  brickShock(piece) {
    const by = this.players.get(piece.thrownBy);
    const cells = this.pieceWorldCells(piece);
    const x0 = Math.min(...cells.map((c) => c[0]));
    const x1 = Math.max(...cells.map((c) => c[0])) + 1;
    const y0 = Math.min(...cells.map((c) => c[1]));
    const y1 = Math.max(...cells.map((c) => c[1])) + 1;
    const z = cells[0][2];
    const cx = (x0 + x1) / 2;
    const cy = (y0 + y1) / 2;
    for (const t of this.players.values()) {
      if (!this.onField(t) || t.id === piece.thrownBy || this.sameTeam(this.players.get(piece.thrownBy), t)) continue; // 던진 사람·같은 팀은 충격파를 안 맞음
      const gx = Math.max(x0 - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - x1, 0);
      const gy = Math.max(y0 - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - y1, 0);
      if (Math.hypot(gx, gy) > C.BRICK_SHOCK_RANGE || Math.abs(t.z - z) > C.BRICK_SHOCK_HEIGHT) continue;
      const hit = this.applyKnockback(t, t.x - cx, t.y - cy, C.BRICK_SHOCK_KB_SPEED, C.BRICK_SHOCK_KB_UP, C.BRICK_SHOCK_STUN_MS, C.DAMAGE_GAIN.shock, { by: piece.thrownBy, kind: 'shock' }, true);
      this.emit({ type: 'hit', kind: 'shock', by: piece.thrownBy, target: t.id, ok: hit });
      this.log(`  [충격파] ${by ? by.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
    }
  }

  // ---------- 아이템 ----------
  spawnItem(type) {
    for (let i = 0; i < C.SPAWN_TRIES; i++) {
      const x = Math.floor(this.rng() * this.W);
      const y = Math.floor(this.rng() * this.D);
      const z = this.columnTop(x, y);
      if (z >= this.H) continue;
      if (this.lava.active && z < this.lava.z + 1) continue; // 용암에 잠길 자리는 피함
      if (this.items.some((it) => it.x === x && it.y === y)) continue;
      this.items.push({ type, x, y, z });
      return true;
    }
    return false;
  }

  // 조종권 아이템이 나오는 판인지: 블록 마스터는 조종권 없음, 하늘 계단은 조종 블록이 계단 사이에 끼어 배치가 깨져서 끔
  controlItemOn() {
    return C.CONTROL_ITEM && this.mode !== 'master' && !this.sky;
  }

  // 조종권이 필드·누군가의 손·조종 중인 블록 어딘가에 있음 → 다음 조종권 시계가 안 돎
  controlInPlay() {
    return (
      this.items.some((it) => it.type === 'control') ||
      [...this.players.values()].some((p) => p.hasControl) ||
      this.pieces.some((pc) => pc.controller !== null)
    );
  }

  // 다음 조종권·아이템까지 남은 ms. 시계가 안 도는 동안(조종권이 돌고 있음, 필드에 아이템이 꽉 참, 판 밖)은 null
  itemTimers() {
    if (this.phase !== 'playing') return { control: null, power: null };
    const powerCount = this.items.filter((it) => it.type !== 'control').length;
    return {
      control: !this.controlItemOn() || this.controlInPlay() ? null : Math.max(0, this.controlItemNextAt - this.time),
      power: !C.ITEMS_ENABLED || powerCount >= this.itemMax() ? null : Math.max(0, this.powerItemNextAt - this.time),
    };
  }

  updateItems() {
    if (this.tutorial) return this.pickupItems(); // 튜토리얼: 단계가 놓은 아이템만
    if (this.controlItemOn() && !this.controlInPlay() && this.time >= this.controlItemNextAt) {
      if (!this.spawnItem('control')) this.controlItemNextAt = this.time + 1000;
    }
    const powerCount = this.items.filter((it) => it.type !== 'control').length;
    if (C.ITEMS_ENABLED && powerCount < this.itemMax() && this.time >= this.powerItemNextAt) { // 아이템 꺼 두면 안 나옴
      const type = C.ITEM_POOL[Math.floor(this.rng() * C.ITEM_POOL.length)];
      this.powerItemNextAt = this.time + (this.spawnItem(type) ? C.ITEM_RESPAWN_MS : 1000);
    }
    if (this.mode === 'master' && this.phase === 'playing' && !this.items.some((it) => it.type === 'counter') && this.time >= this.counterItemAt) {
      this.counterItemAt = this.time + (this.spawnItem('counter') ? C.MASTER_COUNTER_RESPAWN_MS : 1000); // 블록 마스터 반격 아이템 (한 번에 하나)
    }
    this.pickupItems();
  }

  // 필드 아이템 줍기 (닿으면)
  pickupItems() {
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      it.z = this.columnTop(it.x, it.y);
      for (const p of this.players.values()) {
        if (!this.onField(p)) continue;
        const dx = p.x - (it.x + 0.5);
        const dy = p.y - (it.y + 0.5);
        if (Math.hypot(dx, dy) > C.ITEM_PICK_RADIUS) continue;
        if (Math.abs(p.z - it.z) > C.ITEM_HEIGHT_TOL) continue;
        if (C.HELD_ITEMS.includes(it.type) && this.heldItem(p)) continue; // 손 아이템은 하나만: 들고 있으면 못 주움
        this.items.splice(i, 1);
        if (it.type === 'control') {
          p.hasControl = true;
          this.emit({ type: 'pickup', who: p.id, item: 'control' });
          this.log(`  [아이템] ${p.name} 조종권 획득`);
          this.startControlNow(p);
        } else {
          this.givePower(p, it.type);
          this.powerItemNextAt = Math.max(this.powerItemNextAt, this.time + C.ITEM_RESPAWN_MS);
          this.emit({ type: 'pickup', who: p.id, item: it.type });
        }
        break;
      }
    }
  }

  givePower(p, type) {
    if (type === 'knockback') {
      p.ammo += C.KNOCKBACK_AMMO;
      this.log(`  [아이템] ${p.name} 넉백 아이템 획득 (탄 ${p.ammo})`);
    } else if (type === 'jump') {
      p.jumpUntil = this.time + C.JUMP_BOOST_MS;
      this.log(`  [아이템] ${p.name} 점프력 상승 획득`);
    } else if (type === 'ghost') {
      p.ghostUntil = this.time + C.GHOST_MS;
      this.log(`  [아이템] ${p.name} 유령화 획득`);
    } else if (type === 'brick') {
      p.bricks = C.BRICK_USES;
      p.brickSide = false;
      this.log(`  [아이템] ${p.name} 설치 블록 1×2 획득 (${p.bricks}개)`);
    } else if (type === 'bomb') {
      p.bombs = C.BOMB_USES;
      this.log(`  [아이템] ${p.name} 폭탄 획득`);
    } else if (type === 'speed') {
      p.speedUntil = this.time + C.SPEED_MS;
      this.log(`  [아이템] ${p.name} 이속 증가 획득`);
    } else if (type === 'counter') {
      // 블록 마스터 반격: 마스터 편 전원의 다음 블록이 늦게 나옴 (겹쳐 먹으면 이어 붙음)
      this.masterStallUntil = Math.max(this.masterStallUntil, this.time) + C.MASTER_COUNTER_STALL_MS;
      this.counterItemAt = this.time + C.MASTER_COUNTER_RESPAWN_MS;
      this.emit({ type: 'masterStall', who: p.id, until: this.masterStallUntil, ms: C.MASTER_COUNTER_STALL_MS });
      this.log(`  [아이템] ${p.name} 반격 → 마스터 편 블록 ${C.MASTER_COUNTER_STALL_MS / 1000}초 멈춤`);
    }
  }

  isGhost(p) {
    return this.time < p.ghostUntil;
  }

  // 유령화가 끝났는데 블록 안이면 그 기둥 꼭대기로 밀어 올린다
  ejectFromBlocks(p) {
    for (let i = 0; i < this.H + 2; i++) {
      const hits = this.overlappingSolid(this.aabb(p));
      if (!hits.length) return;
      let top = -Infinity;
      for (const h of hits) if (h[2] + 1 > top) top = h[2] + 1;
      p.z = top;
      p.vz = 0;
    }
  }

  // ---------- 투사체 ----------
  updateProjectiles(dt) {
    const sub = Math.max(1, Math.ceil((C.PROJECTILE_SPEED * dt) / 0.2));
    const h = dt / sub;
    for (let i = this.projectiles.length - 1; i >= 0; i--) {
      const pr = this.projectiles[i];
      let dead = this.time >= pr.dieAt;
      for (let s = 0; s < sub && !dead; s++) {
        pr.x += pr.dx * C.PROJECTILE_SPEED * h;
        pr.y += pr.dy * C.PROJECTILE_SPEED * h;
        pr.z += pr.dz * C.PROJECTILE_SPEED * h;
        if (this.solidAt(Math.floor(pr.x), Math.floor(pr.y), Math.floor(pr.z))) {
          dead = true;
          break;
        }
        for (const t of this.players.values()) {
          if (!this.onField(t) || t.id === pr.owner || this.sameTeam(this.players.get(pr.owner), t)) continue; // 같은 팀은 통과
          const r = C.PROJECTILE_RADIUS;
          if (
            pr.x > t.x - C.PLAYER_HALF - r &&
            pr.x < t.x + C.PLAYER_HALF + r &&
            pr.y > t.y - C.PLAYER_HALF - r &&
            pr.y < t.y + C.PLAYER_HALF + r &&
            pr.z > t.z - r &&
            pr.z < t.z + C.PLAYER_HEIGHT + r
          ) {
            const shooter = this.players.get(pr.owner);
            const hit = this.applyKnockback(t, pr.dx, pr.dy, C.PROJECTILE_KB_SPEED, C.PROJECTILE_KB_UP, C.STUN_MS, C.DAMAGE_GAIN.projectile, { by: pr.owner, kind: 'projectile' }, true);
            this.emit({ type: 'hit', kind: 'projectile', by: pr.owner, target: t.id, ok: hit });
            this.log(`  [투사체] ${shooter ? shooter.name : '?'} → ${t.name} ${hit ? '넉백' : '무적이라 무시'}`);
            dead = true;
            break;
          }
        }
      }
      if (dead) this.projectiles.splice(i, 1);
    }
  }
}
