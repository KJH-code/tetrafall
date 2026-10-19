// Tetrafall 서버 게임 상태. 권위는 전부 여기에 있다.
// 격자는 3D 정수 배열, 플레이어는 AABB + 넉백. 물리엔진 없음.
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, rotatedCells, footprint } from '../shared/pieces.js';

const EPS = 1e-6;

function inXY(cx, cy) {
  return cx >= 0 && cx < C.GRID_W && cy >= 0 && cy < C.GRID_D;
}

function cellKey(cx, cy, cz) {
  return `${cx},${cy},${cz}`;
}

function fmtTime(ms) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export class Game {
  constructor(log = () => {}) {
    this.log = log;
    this.rng = Math.random;
    this.time = 0; // 게임 시간 (ms). tick 마다 dt 만큼 증가
    this.phase = 'lobby'; // 'lobby' | 'playing' | 'over'
    this.players = new Map(); // id -> player
    this.hostId = null;
    this.grid = new Uint8Array(C.GRID_W * C.GRID_D * C.GRID_H);
    this.gridVersion = 0;
    this.piece = null;
    this.pieceCells = new Set(); // 현재 블록이 차지한 셀 키 (충돌용)
    this.items = [];
    this.projectiles = [];
    this.roundNumber = 0;
    this.roundStartTime = 0;
    this.roundEndTime = 0;
    this.winnerId = null;
    this.deaths = []; // 이번 판 사망 기록
    this.totals = { rounds: 0, crush: 0, fall: 0 }; // 누적 (합격선 측정용)
    this.nextSpawnAt = 0;
    this.controlItemNextAt = 0;
    this.knockbackItemNextAt = 0;
    this.gridDirty = true;
  }

  // ---------- 격자 ----------
  idx(cx, cy, cz) {
    return (cz * C.GRID_D + cy) * C.GRID_W + cx;
  }

  gridAt(cx, cy, cz) {
    if (!inXY(cx, cy) || cz < 0 || cz >= C.GRID_H) return 0;
    return this.grid[this.idx(cx, cy, cz)];
  }

  // 플레이어 충돌용: 바닥, 쌓인 블록, 떨어지는 블록
  solidAt(cx, cy, cz) {
    if (cz < 0) return inXY(cx, cy); // 필드 안은 바닥, 밖은 허공
    if (inXY(cx, cy) && cz < C.GRID_H && this.grid[this.idx(cx, cy, cz)]) return true;
    return this.pieceCells.has(cellKey(cx, cy, cz));
  }

  // 그 기둥에서 가장 높은 블록 바로 위 z (블록 없으면 0)
  columnTop(cx, cy) {
    for (let z = C.GRID_H - 1; z >= 0; z--) {
      if (this.grid[this.idx(cx, cy, z)]) return z + 1;
    }
    return 0;
  }

  // ---------- 플레이어 관리 ----------
  addPlayer(id) {
    const used = new Set([...this.players.values()].map((p) => p.slot));
    let slot = -1;
    for (let s = 0; s < C.PLAYER_COUNT; s++) {
      if (!used.has(s)) {
        slot = s;
        break;
      }
    }
    if (slot < 0) return null;
    const sp = C.SPAWN_POINTS[slot % C.SPAWN_POINTS.length];
    const p = {
      id,
      slot,
      name: `P${slot + 1}`,
      x: sp.x,
      y: sp.y,
      z: 0,
      yaw: sp.yaw,
      pitch: 0,
      vz: 0,
      kbx: 0,
      kby: 0,
      grounded: true,
      alive: this.phase !== 'playing', // 진행 중 난입은 관전 (죽은 상태)
      stunUntil: 0,
      dashReadyAt: 0,
      pushReadyAt: 0,
      hasControl: false,
      ammo: 0,
      deathCause: null,
      input: { fwd: 0, strafe: 0, jump: false },
    };
    this.players.set(id, p);
    if (this.hostId === null) this.hostId = id;
    this.log(`${p.name} 접속 (slot ${slot})${this.hostId === id ? ' — 호스트' : ''}`);
    return p;
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    this.log(`${p.name} 접속 종료`);
    if (this.hostId === id) {
      this.hostId = this.players.size ? this.players.keys().next().value : null;
    }
    if (this.piece && this.piece.controller === id) this.piece.controller = null;
    if (this.phase === 'playing' && p.alive) {
      this.deaths.push({ name: p.name, cause: 'disconnect', t: this.time - this.roundStartTime });
      this.checkRoundEnd();
    }
  }

  isHost(id) {
    return this.hostId === id;
  }

  canStart() {
    return this.players.size >= C.PLAYER_COUNT && this.phase !== 'playing';
  }

  // ---------- 판 흐름 ----------
  startRound() {
    if (!this.canStart()) return false;
    this.grid.fill(0);
    this.gridVersion++;
    this.gridDirty = true;
    this.piece = null;
    this.pieceCells.clear();
    this.items = [];
    this.projectiles = [];
    this.deaths = [];
    this.winnerId = null;
    this.roundNumber++;
    this.roundStartTime = this.time;
    this.nextSpawnAt = this.time + C.FIRST_SPAWN_DELAY_MS;
    this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
    this.knockbackItemNextAt = this.time + C.KNOCKBACK_ITEM_RESPAWN_MS;
    for (const p of this.players.values()) {
      const sp = C.SPAWN_POINTS[p.slot % C.SPAWN_POINTS.length];
      Object.assign(p, {
        x: sp.x,
        y: sp.y,
        z: 0,
        yaw: sp.yaw,
        pitch: 0,
        vz: 0,
        kbx: 0,
        kby: 0,
        grounded: true,
        alive: true,
        stunUntil: 0,
        dashReadyAt: 0,
        pushReadyAt: 0,
        hasControl: false,
        ammo: 0,
        deathCause: null,
      });
    }
    this.phase = 'playing';
    this.log(`===== ROUND ${this.roundNumber} 시작 (${this.players.size}명) =====`);
    return true;
  }

  endRound(winner) {
    this.phase = 'over';
    this.roundEndTime = this.time;
    this.winnerId = winner ? winner.id : null;
    const dur = this.time - this.roundStartTime;
    const crush = this.deaths.filter((d) => d.cause === 'crush').length;
    const fall = this.deaths.filter((d) => d.cause === 'fall').length;
    this.totals.rounds++;
    this.totals.crush += crush;
    this.totals.fall += fall;
    const deathStr = this.deaths.length
      ? this.deaths.map((d) => `${d.name} ${causeKo(d.cause)}@${fmtTime(d.t)}`).join(', ')
      : '없음';
    this.log(`===== ROUND ${this.roundNumber} 종료 | 길이 ${fmtTime(dur)} | 승자: ${winner ? winner.name : '무승부'} =====`);
    this.log(`  사망: ${deathStr}`);
    this.log(`  이번 판: 압사 ${crush} / 낙사 ${fall}`);
    const per = (this.totals.crush / this.totals.rounds).toFixed(2);
    this.log(`  누적 ${this.totals.rounds}판: 압사 ${this.totals.crush} (판당 ${per}) / 낙사 ${this.totals.fall}`);
  }

  checkRoundEnd() {
    if (this.phase !== 'playing') return;
    const alive = [...this.players.values()].filter((p) => p.alive);
    if (alive.length <= 1 && this.players.size >= 1) {
      this.endRound(alive[0] || null);
    }
  }

  kill(p, cause) {
    if (!p.alive) return;
    p.alive = false;
    p.deathCause = cause;
    p.hasControl = false;
    const t = this.time - this.roundStartTime;
    this.deaths.push({ name: p.name, cause, t });
    this.log(`  [사망] ${p.name} ${causeKo(cause)} @ ${fmtTime(t)} (위치 ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)})`);
  }

  // ---------- 입력 ----------
  handleInput(id, input) {
    const p = this.players.get(id);
    if (!p) return;
    const clamp = (v) => (Number.isFinite(v) ? Math.max(-1, Math.min(1, v)) : 0);
    p.input.fwd = clamp(input.fwd);
    p.input.strafe = clamp(input.strafe);
    p.input.jump = !!input.jump;
    if (Number.isFinite(input.yaw)) p.yaw = input.yaw;
    if (Number.isFinite(input.pitch)) p.pitch = Math.max(-1.5, Math.min(1.5, input.pitch));
  }

  isControlling(p) {
    return !!(this.piece && this.piece.phase === 'control' && this.piece.controller === p.id);
  }

  handleAction(id, action) {
    const p = this.players.get(id);
    if (!p || this.phase !== 'playing' || !p.alive) return;
    const stunned = this.time < p.stunUntil;
    const controlling = this.isControlling(p);
    switch (action.name) {
      case 'dash':
        if (stunned || controlling || this.time < p.dashReadyAt) return; // 조종 중 대시 불가
        this.dash(p);
        return;
      case 'push':
        if (stunned || controlling || this.time < p.pushReadyAt) return; // 조종 중 공격 불가
        this.push(p);
        return;
      case 'fire':
        if (stunned || controlling || p.ammo <= 0) return;
        this.fire(p);
        return;
      case 'pieceMove':
        if (!controlling) return;
        this.movePiece(action.dx | 0, action.dy | 0);
        return;
      case 'rotate':
        if (!controlling) return;
        this.rotatePiece(action.dir > 0 ? 1 : -1);
        return;
      case 'drop':
        if (!controlling) return;
        this.dropPiece();
        return;
      default:
    }
  }

  // ---------- 전투 ----------
  dash(p) {
    let dx = Math.cos(p.yaw);
    let dy = Math.sin(p.yaw);
    const mv = this.moveDir(p);
    if (mv) {
      dx = mv.x;
      dy = mv.y;
    }
    p.kbx = dx * C.DASH_SPEED;
    p.kby = dy * C.DASH_SPEED;
    p.dashReadyAt = this.time + C.DASH_COOLDOWN_MS;
  }

  push(p) {
    p.pushReadyAt = this.time + C.PUSH_COOLDOWN_MS;
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.PUSH_HALF_ANGLE_DEG * Math.PI) / 180);
    for (const t of this.players.values()) {
      if (t === p || !t.alive) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > C.PUSH_RANGE) continue;
      if (Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (dist > EPS && (dx * fx + dy * fy) / dist < cosHalf) continue;
      const hit = this.applyKnockback(t, fx, fy, C.PUSH_KB_SPEED, C.PUSH_KB_UP);
      this.log(`  [밀치기] ${p.name} → ${t.name} ${hit ? '넉백' : '경직 중이라 무시'}`);
    }
  }

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
    this.log(`  [발사] ${p.name} (남은 탄 ${p.ammo})`);
  }

  // 경직 중이면 무시 (연속 넉백 불가). 성공 시 true
  applyKnockback(t, dx, dy, speed, up) {
    if (this.time < t.stunUntil) return false;
    const len = Math.hypot(dx, dy) || 1;
    t.kbx = (dx / len) * speed;
    t.kby = (dy / len) * speed;
    t.vz = up;
    t.grounded = false;
    t.stunUntil = this.time + C.STUN_MS;
    return true;
  }

  // ---------- 블록 ----------
  pieceWorldCells(piece = this.piece) {
    return piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy, piece.pz]);
  }

  refreshPieceCells() {
    this.pieceCells.clear();
    if (!this.piece) return;
    for (const [x, y, z] of this.pieceWorldCells()) this.pieceCells.add(cellKey(x, y, z));
  }

  // 현재 xy 에서 착지 z (착지 가능한 가장 낮은 z). 격자만 본다 (플레이어는 압사 대상이지 장애물이 아님)
  computeLandZ(piece) {
    let landZ = 0;
    for (const [dx, dy] of piece.cells) {
      const top = this.columnTop(piece.px + dx, piece.py + dy);
      if (top > landZ) landZ = top;
    }
    return landZ;
  }

  pieceFits(piece) {
    return piece.landZ + 1 <= C.GRID_H && piece.landZ <= piece.pz;
  }

  updateLanding(piece) {
    piece.landZ = this.computeLandZ(piece);
    piece.fits = this.pieceFits(piece);
  }

  makePiece(shape, rot, px, py, pz) {
    const cells = rotatedCells(shape, rot);
    const piece = { shape, rot, cells, px, py, pz, landZ: 0, fits: false };
    this.updateLanding(piece);
    return piece;
  }

  spawnPiece() {
    const controller = [...this.players.values()].find((p) => p.alive && p.hasControl) || null;
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const rot = Math.floor(this.rng() * 4);
    if (controller) {
      const { w, d } = footprint(rotatedCells(shape, rot));
      const px = Math.floor((C.GRID_W - w) / 2);
      const py = Math.floor((C.GRID_D - d) / 2);
      const piece = this.makePiece(shape, rot, px, py, C.CONTROL_HOVER_Z);
      Object.assign(piece, {
        phase: 'control',
        controller: controller.id,
        stepMs: C.HARD_DROP_STEP_MS,
        nextStepAt: 0,
        controlEndsAt: this.time + C.CONTROL_TIME_MS,
      });
      controller.hasControl = false;
      this.piece = piece;
      this.refreshPieceCells();
      this.log(`  [블록] ${shape} 조종 시작: ${controller.name}`);
      return;
    }
    for (let i = 0; i < C.SPAWN_TRIES; i++) {
      const r = Math.floor(this.rng() * 4);
      const { w, d } = footprint(rotatedCells(shape, r));
      const px = Math.floor(this.rng() * (C.GRID_W - w + 1));
      const py = Math.floor(this.rng() * (C.GRID_D - d + 1));
      const piece = this.makePiece(shape, r, px, py, C.PIECE_SPAWN_Z);
      if (!piece.fits) continue;
      Object.assign(piece, {
        phase: 'falling',
        controller: null,
        stepMs: C.AUTO_FALL_STEP_MS,
        nextStepAt: this.time + C.AUTO_FALL_STEP_MS,
        controlEndsAt: 0,
      });
      this.piece = piece;
      this.refreshPieceCells();
      return;
    }
    // 들어갈 자리가 없음 (필드가 꽉 참). 나중에 다시 시도
    this.nextSpawnAt = this.time + C.AUTO_SPAWN_DELAY_MS;
  }

  movePiece(dx, dy) {
    const piece = this.piece;
    const { w, d } = footprint(piece.cells);
    const nx = Math.max(0, Math.min(C.GRID_W - w, piece.px + dx));
    const ny = Math.max(0, Math.min(C.GRID_D - d, piece.py + dy));
    if (nx === piece.px && ny === piece.py) return;
    piece.px = nx;
    piece.py = ny;
    this.updateLanding(piece);
    this.refreshPieceCells();
  }

  rotatePiece(dir) {
    const piece = this.piece;
    const rot = (piece.rot + dir + 4) % 4;
    const cells = rotatedCells(piece.shape, rot);
    const { w, d } = footprint(cells);
    piece.rot = rot;
    piece.cells = cells;
    piece.px = Math.max(0, Math.min(C.GRID_W - w, piece.px));
    piece.py = Math.max(0, Math.min(C.GRID_D - d, piece.py));
    this.updateLanding(piece);
    this.refreshPieceCells();
  }

  dropPiece() {
    const piece = this.piece;
    if (!piece.fits) return; // 그 자리엔 못 넣는다 (기둥이 꽉 참)
    const who = this.players.get(piece.controller);
    piece.phase = 'falling';
    piece.stepMs = C.HARD_DROP_STEP_MS;
    piece.nextStepAt = this.time + C.HARD_DROP_STEP_MS;
    this.log(`  [블록] ${piece.shape} 하드드롭 by ${who ? who.name : '?'} → (${piece.px},${piece.py}) 착지 z=${piece.landZ}`);
  }

  discardPiece(reason) {
    this.log(`  [블록] ${this.piece.shape} 폐기 (${reason})`);
    this.piece = null;
    this.pieceCells.clear();
    this.nextSpawnAt = this.time + C.AUTO_SPAWN_DELAY_MS;
    this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
  }

  updatePiece() {
    const piece = this.piece;
    if (!piece) {
      if (this.time >= this.nextSpawnAt) this.spawnPiece();
      return;
    }
    if (piece.phase === 'control') {
      const ctl = this.players.get(piece.controller);
      if (!ctl || !ctl.alive) {
        // 조종자가 죽거나 나가면 그 자리에서 자동 낙하 (안 맞으면 폐기)
        if (piece.fits) this.dropPiece();
        else this.discardPiece('조종자 이탈, 자리 없음');
        return;
      }
      if (this.time >= piece.controlEndsAt) {
        if (piece.fits) {
          this.log(`  [블록] 8초 초과 → 자동 낙하`);
          this.dropPiece();
        } else {
          this.discardPiece('시간 초과, 자리 없음');
        }
      }
      return;
    }
    // falling
    while (this.piece === piece && this.time >= piece.nextStepAt) {
      if (piece.pz <= piece.landZ) {
        this.landPiece();
        return;
      }
      piece.pz--;
      piece.nextStepAt += piece.stepMs;
      this.refreshPieceCells();
      this.crushCheck();
      if (piece.pz <= piece.landZ) {
        this.landPiece();
        return;
      }
    }
  }

  // 블록 셀이 플레이어 AABB 와 겹치면 압사
  crushCheck() {
    const cells = this.pieceWorldCells();
    for (const p of this.players.values()) {
      if (!p.alive) continue;
      for (const [cx, cy, cz] of cells) {
        if (
          cx < p.x + C.PLAYER_HALF - EPS &&
          cx + 1 > p.x - C.PLAYER_HALF + EPS &&
          cy < p.y + C.PLAYER_HALF - EPS &&
          cy + 1 > p.y - C.PLAYER_HALF + EPS &&
          cz < p.z + C.PLAYER_HEIGHT - EPS &&
          cz + 1 > p.z + EPS
        ) {
          this.kill(p, 'crush');
          break;
        }
      }
    }
  }

  landPiece() {
    const piece = this.piece;
    for (const [x, y, z] of this.pieceWorldCells()) {
      if (z >= 0 && z < C.GRID_H) this.grid[this.idx(x, y, z)] = 1;
    }
    const wasControlled = piece.controller !== null;
    this.piece = null;
    this.pieceCells.clear();
    this.gridVersion++;
    this.gridDirty = true;
    this.clearLayers();
    this.nextSpawnAt = this.time + C.AUTO_SPAWN_DELAY_MS;
    if (wasControlled) this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
    for (const it of this.items) it.z = this.columnTop(it.x, it.y);
  }

  // 6×6 한 층이 꽉 차면 제거하고 위의 블록·플레이어·아이템을 내린다
  clearLayers() {
    const layerSize = C.GRID_W * C.GRID_D;
    const full = [];
    for (let z = 0; z < C.GRID_H; z++) {
      let ok = true;
      for (let i = 0; i < layerSize && ok; i++) if (!this.grid[z * layerSize + i]) ok = false;
      if (ok) full.push(z);
    }
    if (!full.length) return;
    const next = new Uint8Array(this.grid.length);
    let dst = 0;
    for (let z = 0; z < C.GRID_H; z++) {
      if (full.includes(z)) continue;
      next.set(this.grid.subarray(z * layerSize, (z + 1) * layerSize), dst * layerSize);
      dst++;
    }
    this.grid = next;
    this.gridVersion++;
    this.gridDirty = true;
    for (const p of this.players.values()) {
      let shift = 0;
      for (const z of full) if (p.z >= z + 1 - 1e-3) shift++;
      p.z -= shift;
    }
    this.log(`  [층 클리어] z=${full.join(',')} 제거 → 위 블록·플레이어 ${full.length}칸 내려앉음`);
  }

  // ---------- 아이템 ----------
  spawnItem(type) {
    for (let i = 0; i < C.SPAWN_TRIES; i++) {
      const x = Math.floor(this.rng() * C.GRID_W);
      const y = Math.floor(this.rng() * C.GRID_D);
      const z = this.columnTop(x, y);
      if (z >= C.GRID_H) continue;
      if (this.items.some((it) => it.x === x && it.y === y)) continue;
      this.items.push({ type, x, y, z });
      return true;
    }
    return false;
  }

  updateItems() {
    const anyControl =
      this.items.some((it) => it.type === 'control') ||
      [...this.players.values()].some((p) => p.hasControl) ||
      (this.piece && this.piece.controller !== null);
    if (!anyControl && this.time >= this.controlItemNextAt) {
      if (!this.spawnItem('control')) this.controlItemNextAt = this.time + 1000;
    }
    if (!this.items.some((it) => it.type === 'knockback') && this.time >= this.knockbackItemNextAt) {
      if (!this.spawnItem('knockback')) this.knockbackItemNextAt = this.time + 1000;
    }
    for (let i = this.items.length - 1; i >= 0; i--) {
      const it = this.items[i];
      it.z = this.columnTop(it.x, it.y);
      for (const p of this.players.values()) {
        if (!p.alive) continue;
        const dx = p.x - (it.x + 0.5);
        const dy = p.y - (it.y + 0.5);
        if (Math.hypot(dx, dy) > C.ITEM_PICK_RADIUS) continue;
        if (Math.abs(p.z - it.z) > C.ITEM_HEIGHT_TOL) continue;
        this.items.splice(i, 1);
        if (it.type === 'control') {
          p.hasControl = true;
          this.log(`  [아이템] ${p.name} 조종권 획득`);
        } else {
          p.ammo += C.KNOCKBACK_AMMO;
          this.knockbackItemNextAt = this.time + C.KNOCKBACK_ITEM_RESPAWN_MS;
          this.log(`  [아이템] ${p.name} 넉백 아이템 획득 (탄 ${p.ammo})`);
        }
        break;
      }
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
          if (!t.alive || t.id === pr.owner) continue;
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
            const hit = this.applyKnockback(t, pr.dx, pr.dy, C.PROJECTILE_KB_SPEED, C.PROJECTILE_KB_UP);
            this.log(`  [투사체] ${shooter ? shooter.name : '?'} → ${t.name} ${hit ? '넉백' : '경직 중이라 무시'}`);
            dead = true;
            break;
          }
        }
      }
      if (dead) this.projectiles.splice(i, 1);
    }
  }

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
    const stunned = this.time < p.stunUntil;
    let ix = 0;
    let iy = 0;
    if (!stunned) {
      const mv = this.moveDir(p);
      if (mv) {
        ix = mv.x * C.MOVE_SPEED;
        iy = mv.y * C.MOVE_SPEED;
      }
      if (p.input.jump && p.grounded) {
        p.vz = C.JUMP_SPEED;
        p.grounded = false;
      }
    }
    const damp = Math.exp(-(p.grounded ? C.KB_DAMPING_GROUND : C.KB_DAMPING_AIR) * dt);
    p.kbx *= damp;
    p.kby *= damp;
    if (Math.abs(p.kbx) < 0.01) p.kbx = 0;
    if (Math.abs(p.kby) < 0.01) p.kby = 0;
    p.vz -= C.GRAVITY * dt;
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
    p[axis] += delta;
    const hits = this.overlappingSolid(this.aabb(p));
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
    if (axis === 'x') p.kbx = 0;
    else p.kby = 0;
  }

  // ---------- 틱 ----------
  tick(dtMs) {
    this.time += dtMs;
    if (this.phase !== 'playing') return;
    const dt = dtMs / 1000;
    this.updatePiece();
    let remaining = dt;
    while (remaining > 0) {
      const h = Math.min(remaining, C.MAX_STEP_DT);
      for (const p of this.players.values()) if (p.alive) this.integratePlayer(p, h);
      remaining -= h;
    }
    for (const p of this.players.values()) {
      if (p.alive && p.z < C.FALL_DEATH_Z) this.kill(p, 'fall');
    }
    this.updateItems();
    this.updateProjectiles(dt);
    if (C.ROUND_TIME_LIMIT_MS > 0 && this.time - this.roundStartTime >= C.ROUND_TIME_LIMIT_MS) {
      this.log('  시간 초과 → 무승부');
      this.endRound(null);
      return;
    }
    this.checkRoundEnd();
  }

  // ---------- 스냅샷 ----------
  snapshot(includeGrid = false) {
    const piece = this.piece;
    let pieceOut = null;
    if (piece) {
      let eta = Infinity;
      if (piece.phase === 'falling') {
        eta = Math.max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - this.time));
      }
      pieceOut = {
        shape: piece.shape,
        cells: this.pieceWorldCells(),
        phase: piece.phase,
        controller: piece.controller,
        landZ: piece.landZ,
        fits: piece.fits,
        shadow: piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]),
        shadowVisible: piece.phase === 'falling' && eta <= C.SHADOW_LEAD_MS,
        timeLeft: piece.phase === 'control' ? Math.max(0, piece.controlEndsAt - this.time) : 0,
      };
    }
    const out = {
      type: 'state',
      time: this.time,
      phase: this.phase,
      hostId: this.hostId,
      canStart: this.canStart(),
      round: {
        n: this.roundNumber,
        elapsed: this.phase === 'playing' ? this.time - this.roundStartTime : this.roundEndTime - this.roundStartTime,
        winnerId: this.winnerId,
        deaths: this.deaths,
        totals: this.totals,
      },
      players: [...this.players.values()].map((p) => ({
        id: p.id,
        slot: p.slot,
        name: p.name,
        x: p.x,
        y: p.y,
        z: p.z,
        yaw: p.yaw,
        pitch: p.pitch,
        alive: p.alive,
        stunned: this.time < p.stunUntil,
        hasControl: p.hasControl,
        ammo: p.ammo,
        dashCd: Math.max(0, p.dashReadyAt - this.time),
        controlling: this.isControlling(p),
        cause: p.deathCause,
      })),
      piece: pieceOut,
      items: this.items,
      projectiles: this.projectiles.map((pr) => ({ x: pr.x, y: pr.y, z: pr.z })),
      gridVersion: this.gridVersion,
    };
    if (includeGrid || this.gridDirty) {
      out.grid = Array.from(this.grid);
      this.gridDirty = false;
    }
    return out;
  }
}

function causeKo(cause) {
  if (cause === 'crush') return '압사';
  if (cause === 'fall') return '낙사';
  if (cause === 'disconnect') return '접속 끊김';
  return cause;
}
