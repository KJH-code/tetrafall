// Tetrafall 서버 게임 상태. 권위는 전부 여기에 있다.
// 격자는 3D 정수 배열, 플레이어는 AABB + 넉백. 물리엔진 없음.
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, rotatedCells, footprint } from '../shared/pieces.js';
import { BotBrain } from './bot.js';
import { MAPS, MAP_IDS, mapColumns } from './maps.js';

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
    this.pieces = []; // 떨어지는·조종 중인 블록들
    this.pieceCounter = 0;
    this.pieceCells = new Map(); // 셀 키 -> 블록 id (충돌용)
    this.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
    this.mapChoice = 'flat'; // 호스트가 고른 맵 ('random' 또는 MAP_IDS 중 하나). 서버는 시작 때 C.MAP_DEFAULT 로 바꾼다
    this.mapId = 'flat'; // 이번 판 맵
    this.baseAvgHeight = 0; // 판 시작 때 지형 평균 높이 (용암은 여기서 더 쌓인 만큼으로 판단)
    this.items = [];
    this.projectiles = [];
    this.roundNumber = 0;
    this.roundStartTime = 0;
    this.roundEndTime = 0;
    this.winnerId = null;
    this.deaths = []; // 이번 판 사망 기록
    this.totals = { rounds: 0, crush: 0, fall: 0, lava: 0 }; // 누적 (합격선 측정용)
    this.totalsByCount = {}; // 인원수별 누적 { [n]: { rounds, crush, fall } }. 인원이 다르면 압사 비율을 따로 본다
    this.roundPlayerCount = 0;
    this.roundBotCount = 0;
    this.bots = new Map(); // 봇 플레이어 id -> BotBrain. 봇 id 는 음수
    this.botCounter = 0;
    this.nextSpawnAt = 0;
    this.controlItemNextAt = 0;
    this.powerItemNextAt = 0; // 조종권 외 아이템 다음 생성 시각
    this.gridDirty = true;
    this.events = []; // 클라이언트 알림용 이벤트. 브로드캐스트 때 drainEvents() 로 비운다
  }

  emit(e) {
    this.events.push(e);
  }

  drainEvents() {
    const out = this.events;
    this.events = [];
    return out;
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
  addPlayer(id, isBot = false) {
    const used = new Set([...this.players.values()].map((p) => p.slot));
    let slot = -1;
    for (let s = 0; s < maxPlayers(); s++) {
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
      name: `P${slot + 1}${isBot ? '(봇)' : ''}`,
      isBot,
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
      freezeUntil: 0, // 히트스톱: 이 시각까지 움직임 정지 (속도는 보존)
      weaponUses: 0, // 망치 남은 횟수
      jumpUntil: 0, // 점프력 상승 끝나는 시각
      ghostUntil: 0, // 유령화 끝나는 시각
      dashReadyAt: 0,
      pushReadyAt: 0,
      hasControl: false,
      ammo: 0,
      deathCause: null,
      input: { fwd: 0, strafe: 0, jump: false },
    };
    this.players.set(id, p);
    if (this.hostId === null && !isBot) this.hostId = id;
    this.log(`${p.name} 접속 (slot ${slot})${this.hostId === id ? ' — 호스트' : ''}`);
    return p;
  }

  // 봇 추가 (판 진행 중에는 안 됨). 성공하면 플레이어, 자리가 없으면 null
  addBot() {
    if (this.phase === 'playing') return null;
    const id = -++this.botCounter;
    const p = this.addPlayer(id, true);
    if (p) this.bots.set(id, new BotBrain(() => this.rng()));
    return p;
  }

  // 가장 나중에 넣은 봇 하나 빼기
  removeBot() {
    if (this.phase === 'playing' || !this.bots.size) return false;
    const id = Math.min(...this.bots.keys()); // 음수라 가장 작은 게 가장 최근
    this.removePlayer(id);
    return true;
  }

  removeAllBots() {
    for (const id of [...this.bots.keys()]) this.removePlayer(id);
  }

  humanCount() {
    return [...this.players.values()].filter((p) => !p.isBot).length;
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    this.bots.delete(id);
    this.log(`${p.name} ${p.isBot ? '빠짐' : '접속 종료'}`);
    if (this.hostId === id) {
      const next = [...this.players.values()].find((o) => !o.isBot);
      this.hostId = next ? next.id : null;
    }
    for (const pc of this.pieces) if (pc.controller === id) pc.controller = null;
    if (this.phase === 'playing' && p.alive) {
      this.deaths.push({ name: p.name, cause: 'disconnect', t: this.time - this.roundStartTime });
      this.checkRoundEnd();
    }
  }

  setMap(choice) {
    if (this.phase === 'playing') return false;
    if (choice !== 'random' && !MAP_IDS.includes(choice)) return false;
    this.mapChoice = choice;
    return true;
  }

  // 시작 위치에서 발이 놓일 높이: 플레이어가 걸치는 칸들 중 가장 높은 기둥 위
  spawnZ(x, y) {
    let top = 0;
    for (const ox of [-C.PLAYER_HALF, C.PLAYER_HALF]) {
      for (const oy of [-C.PLAYER_HALF, C.PLAYER_HALF]) {
        const cx = Math.floor(x + ox);
        const cy = Math.floor(y + oy);
        if (inXY(cx, cy)) top = Math.max(top, this.columnTop(cx, cy));
      }
    }
    return top;
  }

  isHost(id) {
    return this.hostId === id;
  }

  canStart() {
    return this.players.size >= C.MIN_PLAYERS && this.phase !== 'playing';
  }

  // ---------- 판 흐름 ----------
  startRound() {
    if (!this.canStart()) return false;
    this.grid.fill(0);
    this.mapId = this.mapChoice === 'random' ? MAP_IDS[Math.floor(this.rng() * MAP_IDS.length)] : this.mapChoice;
    for (const [x, y, h] of mapColumns(this.mapId, C.GRID_W, C.GRID_D)) {
      for (let z = 0; z < h && z < C.GRID_H; z++) this.grid[this.idx(x, y, z)] = 1;
    }
    this.baseAvgHeight = this.avgHeight();
    this.gridVersion++;
    this.gridDirty = true;
    this.pieces = [];
    this.pieceCells.clear();
    this.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
    this.items = [];
    this.projectiles = [];
    this.deaths = [];
    this.events = [];
    this.winnerId = null;
    this.roundNumber++;
    this.roundStartTime = this.time;
    this.nextSpawnAt = this.time + C.FIRST_SPAWN_DELAY_MS;
    this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
    this.powerItemNextAt = this.time + C.ITEM_FIRST_SPAWN_MS;
    for (const p of this.players.values()) {
      const sp = C.SPAWN_POINTS[p.slot % C.SPAWN_POINTS.length];
      Object.assign(p, {
        x: sp.x,
        y: sp.y,
        z: this.spawnZ(sp.x, sp.y),
        yaw: sp.yaw,
        pitch: 0,
        vz: 0,
        kbx: 0,
        kby: 0,
        grounded: true,
        alive: true,
        stunUntil: 0,
        freezeUntil: 0,
        weaponUses: 0,
        jumpUntil: 0,
        ghostUntil: 0,
        dashReadyAt: 0,
        pushReadyAt: 0,
        hasControl: false,
        ammo: 0,
        deathCause: null,
      });
    }
    this.phase = 'playing';
    this.roundPlayerCount = this.players.size;
    this.roundBotCount = this.bots.size;
    this.log(`===== ROUND ${this.roundNumber} 시작 (${this.players.size}명, 맵 ${MAPS[this.mapId].name}) =====`);
    return true;
  }

  endRound(winner) {
    this.phase = 'over';
    this.roundEndTime = this.time;
    this.winnerId = winner ? winner.id : null;
    const dur = this.time - this.roundStartTime;
    const crush = this.deaths.filter((d) => d.cause === 'crush').length;
    const fall = this.deaths.filter((d) => d.cause === 'fall').length;
    const lava = this.deaths.filter((d) => d.cause === 'lava').length;
    this.totals.rounds++;
    this.totals.crush += crush;
    this.totals.fall += fall;
    this.totals.lava += lava;
    const deathStr = this.deaths.length
      ? this.deaths.map((d) => `${d.name} ${causeKo(d.cause)}@${fmtTime(d.t)}`).join(', ')
      : '없음';
    this.log(`===== ROUND ${this.roundNumber} 종료 | 길이 ${fmtTime(dur)} | 승자: ${winner ? winner.name : '무승부'} =====`);
    this.log(`  사망: ${deathStr}`);
    this.log(`  이번 판: 압사 ${crush} / 낙사 ${fall} / 용암 ${lava}${this.lava.active ? ` (용암 시작 @ ${fmtTime(this.lava.startedAt - this.roundStartTime)})` : ''}`);
    const per = (this.totals.crush / this.totals.rounds).toFixed(2);
    this.log(`  누적 ${this.totals.rounds}판: 압사 ${this.totals.crush} (판당 ${per}) / 낙사 ${this.totals.fall} / 용암 ${this.totals.lava}`);
    const n = this.roundPlayerCount;
    // 봇이 낀 판은 따로 센다 (봇의 회피 실력이 압사 비율을 좌우하므로 사람끼리 판과 섞지 않는다)
    const label = this.roundBotCount ? `${n}인(봇 ${this.roundBotCount})` : `${n}인`;
    const t = (this.totalsByCount[label] = this.totalsByCount[label] || { rounds: 0, crush: 0, fall: 0, lava: 0 });
    t.rounds++;
    t.crush += crush;
    t.fall += fall;
    t.lava += lava;
    this.log(`  누적 사망 중 압사 비율: ${shareText(this.totals)}`);
    if (Object.keys(this.totalsByCount).length > 1 || label !== '2인') {
      // 인원이 섞이면 인원수별로도 찍는다 (합격 판정은 같은 인원끼리 비교)
      for (const [k, v] of Object.entries(this.totalsByCount)) {
        this.log(`    ${k} 판 ${v.rounds}판: 압사 ${v.crush} / 낙사 ${v.fall} / 용암 ${v.lava} → ${shareText(v)}`);
      }
    }
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
    this.emit({ type: 'death', who: p.id, cause });
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
    return !!this.controlledPiece(p);
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
        this.movePiece(this.controlledPiece(p), action.dx | 0, action.dy | 0);
        return;
      case 'rotate':
        if (!controlling) return;
        this.rotatePiece(this.controlledPiece(p), action.dir > 0 ? 1 : -1);
        return;
      case 'drop':
        if (!controlling) return;
        this.dropPiece(this.controlledPiece(p));
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
    // 망치가 있으면 밀치기 대신 망치 (빗나가도 1회 소모)
    const weapon = p.weaponUses > 0;
    if (weapon) p.weaponUses--;
    const kind = weapon ? 'weapon' : 'push';
    const speed = weapon ? C.WEAPON_KB_SPEED : C.PUSH_KB_SPEED;
    const up = weapon ? C.WEAPON_KB_UP : C.PUSH_KB_UP;
    const stun = weapon ? C.WEAPON_STUN_MS : C.STUN_MS;
    this.emit({ type: 'swing', who: p.id, kind });
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
      const hit = this.applyKnockback(t, fx, fy, speed, up, stun);
      if (hit) p.freezeUntil = this.time + C.HITSTOP_MS; // 때린 쪽도 같이 멈칫
      this.emit({ type: 'hit', kind, by: p.id, target: t.id, ok: hit });
      this.log(`  [${weapon ? '망치' : '밀치기'}] ${p.name} → ${t.name} ${hit ? '넉백' : '경직 중이라 무시'}${weapon ? ` (남은 ${p.weaponUses}회)` : ''}`);
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
    this.emit({ type: 'fire', who: p.id });
    this.log(`  [발사] ${p.name} (남은 탄 ${p.ammo})`);
  }

  // 경직 중이면 무시 (연속 넉백 불가). 성공 시 true
  applyKnockback(t, dx, dy, speed, up, stunMs = C.STUN_MS) {
    if (this.time < t.stunUntil) return false;
    const len = Math.hypot(dx, dy) || 1;
    t.kbx = (dx / len) * speed;
    t.kby = (dy / len) * speed;
    t.vz = up;
    t.grounded = false;
    t.stunUntil = this.time + stunMs;
    t.freezeUntil = this.time + C.HITSTOP_MS; // 멈칫 뒤에 날아간다 (날아가는 거리는 그대로)
    return true;
  }

  // ---------- 블록 ----------
  // 떨어지는 블록은 여러 개 (this.pieces). 조종 블록은 한 번에 하나 (조종권 아이템이 하나뿐이라).
  // 블록끼리는 공중에서 겹치지 않는다: 한 칸 아래를 다른 블록이 차지하고 있으면 그 칸이 빌 때까지 기다린다.

  // 예전 코드·테스트 호환: "대표 블록" = 조종 중인 블록, 없으면 첫 블록
  get piece() {
    return this.pieces.find((pc) => pc.phase === 'control') || this.pieces[0] || null;
  }

  set piece(v) {
    this.pieces = v ? [v] : [];
    if (v && !v.id) v.id = ++this.pieceCounter;
    this.refreshPieceCells();
  }

  pieceWorldCells(piece = this.piece) {
    return piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy, piece.pz]);
  }

  refreshPieceCells() {
    this.pieceCells.clear();
    for (const piece of this.pieces) {
      for (const [x, y, z] of this.pieceWorldCells(piece)) this.pieceCells.set(cellKey(x, y, z), piece.id);
    }
  }

  controlledPiece(p) {
    return this.pieces.find((pc) => pc.phase === 'control' && pc.controller === p.id) || null;
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
    const piece = { id: 0, shape, rot, cells, px, py, pz, landZ: 0, fits: false };
    this.updateLanding(piece);
    return piece;
  }

  // ---- 판이 길어질수록 빨라지고 많아진다 ----
  elapsed() {
    return this.time - this.roundStartTime;
  }

  rampT() {
    return Math.min(1, Math.max(0, this.elapsed() / C.RAMP_FULL_MS));
  }

  autoFallStepMs() {
    return C.AUTO_FALL_STEP_MS + (C.AUTO_FALL_STEP_MIN_MS - C.AUTO_FALL_STEP_MS) * this.rampT();
  }

  autoSpawnDelayMs() {
    return C.AUTO_SPAWN_DELAY_MS + (C.AUTO_SPAWN_DELAY_MIN_MS - C.AUTO_SPAWN_DELAY_MS) * this.rampT();
  }

  targetConcurrent() {
    return Math.min(C.CONCURRENT_MAX, 1 + Math.floor(this.elapsed() / C.CONCURRENT_RAMP_MS));
  }

  addPiece(piece, fields) {
    piece.id = ++this.pieceCounter;
    Object.assign(piece, fields);
    this.pieces.push(piece);
    this.refreshPieceCells();
    return piece;
  }

  spawnControlled(controller) {
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const rot = Math.floor(this.rng() * 4);
    const { w, d } = footprint(rotatedCells(shape, rot));
    const px = Math.floor((C.GRID_W - w) / 2);
    const py = Math.floor((C.GRID_D - d) / 2);
    const piece = this.makePiece(shape, rot, px, py, C.CONTROL_HOVER_Z);
    this.addPiece(piece, {
      phase: 'control',
      controller: controller.id,
      stepMs: C.HARD_DROP_STEP_MS,
      nextStepAt: 0,
      controlEndsAt: this.time + C.CONTROL_TIME_MS,
    });
    controller.hasControl = false;
    this.emit({ type: 'controlStart', who: controller.id });
    this.log(`  [블록] ${shape} 조종 시작: ${controller.name}`);
    return piece;
  }

  spawnAuto() {
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const piece = this.chooseAutoPlacement(shape);
    if (!piece) return null;
    const stepMs = this.autoFallStepMs();
    return this.addPiece(piece, { phase: 'falling', controller: null, stepMs, nextStepAt: this.time + stepMs, controlEndsAt: 0 });
  }

  // 예전 호환: 조종권 보유자가 있으면 조종 블록, 없으면 자동 블록 하나
  spawnPiece() {
    const holder = [...this.players.values()].find((p) => p.alive && p.hasControl) || null;
    if (holder && !this.pieces.some((pc) => pc.controller !== null)) return this.spawnControlled(holder);
    return this.spawnAuto();
  }

  updateSpawning() {
    if (this.time < this.nextSpawnAt) return;
    const holder = [...this.players.values()].find((p) => p.alive && p.hasControl) || null;
    if (holder && !this.pieces.some((pc) => pc.controller !== null)) {
      this.spawnControlled(holder);
      this.nextSpawnAt = this.time + this.autoSpawnDelayMs();
      return;
    }
    const autos = this.pieces.filter((pc) => pc.controller === null).length;
    if (autos >= this.targetConcurrent()) return;
    this.spawnAuto(); // 자리가 없으면 다음 간격에 다시
    this.nextSpawnAt = this.time + this.autoSpawnDelayMs();
  }

  // 자동 블록 고르기: 들어갈 수 있는 모든 (모양, 회전, 위치) 중에서 가중 무작위로 하나.
  // 가중치 = exp(CLEAR_BIAS × 점수). CLEAR_BIAS 0 이면 완전 무작위, 클수록 가장 낮은 층을 클리어하는 쪽으로 몰린다.
  // CLEAR_PICK_SHAPE 가 false 면 모양은 무작위로 정하고 회전·위치만 고른다 (이 경우 클리어가 거의 안 일어난다).
  chooseAutoPlacement(randomShape) {
    const shapes = C.CLEAR_BIAS > 0 && C.CLEAR_PICK_SHAPE ? SHAPE_NAMES : [randomShape];
    const L = this.lowestLayer();
    // 다른 블록(떨어지는 중·조종 중)과 같은 기둥에는 안 떨어뜨린다: 그림자가 겹치지 않게
    const busy = new Set();
    for (const pc of this.pieces) for (const [dx, dy] of pc.cells) busy.add((pc.px + dx) * 100 + (pc.py + dy));
    const cands = [];
    let best = -Infinity;
    for (const shape of shapes) {
      for (let r = 0; r < 4; r++) {
        const { w, d } = footprint(rotatedCells(shape, r));
        for (let px = 0; px <= C.GRID_W - w; px++) {
          for (let py = 0; py <= C.GRID_D - d; py++) {
            const piece = this.makePiece(shape, r, px, py, C.PIECE_SPAWN_Z);
            if (!piece.fits) continue;
            if (busy.size && piece.cells.some(([dx, dy]) => busy.has((px + dx) * 100 + (py + dy)))) continue;
            const score = C.CLEAR_BIAS > 0 ? this.placementScore(piece, L) : 0;
            if (score > best) best = score;
            cands.push({ piece, score });
          }
        }
      }
    }
    if (!cands.length) return null;
    let total = 0;
    for (const c of cands) {
      c.w = Math.exp(C.CLEAR_BIAS * (c.score - best)); // best 기준으로 빼서 overflow 방지
      total += c.w;
    }
    let x = this.rng() * total;
    for (const c of cands) {
      x -= c.w;
      if (x <= 0) return c.piece;
    }
    return cands[cands.length - 1].piece;
  }

  // 가장 낮은 기둥 높이 = 아직 안 찬 가장 낮은 층
  lowestLayer() {
    let L = Infinity;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) L = Math.min(L, this.columnTop(x, y));
    return L;
  }

  // 자동 블록 자리 점수. 높을수록 가장 낮은 층(L) 클리어에 가깝다.
  // - 밑에 빈칸(구멍)을 만들면 벌점: 구멍 위층은 다시 채울 수 없다
  // - L 층에 딱 붙으면 가점, 그걸로 L 층이 다 차면 큰 가점
  // - L 층에 남는 빈 영역 중 칸 수가 4의 배수가 아닌 덩어리는 벌점: 평평한 4칸 블록으로 영영 못 채운다
  // - L 보다 높은 곳에 평평하게 얹으면 높이만큼 약한 벌점
  placementScore(piece, L) {
    const S = C.CLEAR_SCORE;
    const z = piece.landZ;
    let holes = 0;
    for (const [dx, dy] of piece.cells) holes += z - this.columnTop(piece.px + dx, piece.py + dy);
    if (holes > 0) return -S.HOLE * holes - (z - L);
    if (z !== L) return -(z - L);
    const covered = new Set(piece.cells.map(([dx, dy]) => (piece.px + dx) * 100 + (piece.py + dy)));
    const open = (x, y) => this.columnTop(x, y) === L && !covered.has(x * 100 + y);
    let remaining = 0;
    let bad = 0;
    const seen = new Set();
    for (let x = 0; x < C.GRID_W; x++) {
      for (let y = 0; y < C.GRID_D; y++) {
        if (!open(x, y) || seen.has(x * 100 + y)) continue;
        let size = 0;
        const stack = [[x, y]];
        seen.add(x * 100 + y);
        while (stack.length) {
          const [cx, cy] = stack.pop();
          size++;
          for (const [nx, ny] of [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]]) {
            if (nx < 0 || ny < 0 || nx >= C.GRID_W || ny >= C.GRID_D) continue;
            if (!open(nx, ny) || seen.has(nx * 100 + ny)) continue;
            seen.add(nx * 100 + ny);
            stack.push([nx, ny]);
          }
        }
        remaining += size;
        if (size % 4 !== 0) bad++;
      }
    }
    return S.FILL + (remaining === 0 ? S.CLEAR : 0) - S.BAD_GAP * bad;
  }

  movePiece(piece, dx, dy) {
    const { w, d } = footprint(piece.cells);
    const nx = Math.max(0, Math.min(C.GRID_W - w, piece.px + dx));
    const ny = Math.max(0, Math.min(C.GRID_D - d, piece.py + dy));
    if (nx === piece.px && ny === piece.py) return;
    piece.px = nx;
    piece.py = ny;
    this.updateLanding(piece);
    this.refreshPieceCells();
  }

  rotatePiece(piece, dir) {
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

  // reason: 'hard' = 조종자가 Enter, 'timeout' = 8초 초과, 'left' = 조종자 사망·이탈
  dropPiece(piece = this.piece, reason = 'hard') {
    if (!piece || !piece.fits) return; // 그 자리엔 못 넣는다 (기둥이 꽉 참)
    const who = this.players.get(piece.controller);
    piece.phase = 'falling';
    piece.stepMs = C.HARD_DROP_STEP_MS;
    piece.nextStepAt = this.time + C.HARD_DROP_STEP_MS;
    const name = who ? who.name : '?';
    const what = reason === 'hard' ? `하드드롭 by ${name}` : reason === 'timeout' ? `자동 낙하 (8초 초과, 조종자 ${name})` : `자동 낙하 (조종자 ${name} 사망·이탈)`;
    this.log(`  [블록] ${piece.shape} ${what} → (${piece.px},${piece.py}) 착지 z=${piece.landZ}`);
  }

  // 조종권을 먹은 순간 바로 조종을 시작한다 (CONTROL_TAKEOVER).
  // 자동 블록이 떨어지는 중이면 가장 높이 있는 것을 하늘로 올려 넘겨받고, 없으면 새 블록을 하늘에.
  // 다른 사람이 조종한 블록이 아직 있으면 그 블록이 착지한 뒤 다음 블록을 조종한다.
  startControlNow(p) {
    if (!C.CONTROL_TAKEOVER || !p.hasControl) return;
    if (this.pieces.some((pc) => pc.controller !== null)) return;
    let piece = null;
    for (const pc of this.pieces) if (pc.phase === 'falling' && (!piece || pc.pz > piece.pz)) piece = pc;
    if (!piece) {
      this.spawnControlled(p);
      return;
    }
    Object.assign(piece, {
      pz: C.CONTROL_HOVER_Z,
      phase: 'control',
      controller: p.id,
      stepMs: C.HARD_DROP_STEP_MS,
      nextStepAt: 0,
      controlEndsAt: this.time + C.CONTROL_TIME_MS,
    });
    p.hasControl = false;
    this.updateLanding(piece);
    this.refreshPieceCells();
    this.emit({ type: 'controlStart', who: p.id });
    this.log(`  [블록] ${piece.shape} 조종 시작: ${p.name} (떨어지던 블록 넘겨받음)`);
  }

  removePiece(piece) {
    const i = this.pieces.indexOf(piece);
    if (i >= 0) this.pieces.splice(i, 1);
    this.refreshPieceCells();
  }

  discardPiece(piece, reason) {
    this.log(`  [블록] ${piece.shape} 폐기 (${reason})`);
    this.removePiece(piece);
    this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + this.autoSpawnDelayMs());
    if (piece.controller !== null) this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
  }

  // 한 칸 아래에 다른 블록이 있으면 true (그 블록이 비킬 때까지 기다린다)
  blockedByPiece(piece) {
    for (const [x, y, z] of this.pieceWorldCells(piece)) {
      const other = this.pieceCells.get(cellKey(x, y, z - 1));
      if (other !== undefined && other !== piece.id) return true;
    }
    return false;
  }

  updatePieces() {
    this.updateSpawning();
    for (const piece of [...this.pieces]) {
      if (piece.phase === 'control') {
        const ctl = this.players.get(piece.controller);
        if (!ctl || !ctl.alive) {
          // 조종자가 죽거나 나가면 그 자리에서 자동 낙하 (안 맞으면 폐기)
          if (piece.fits) this.dropPiece(piece, 'left');
          else this.discardPiece(piece, '조종자 이탈, 자리 없음');
        } else if (this.time >= piece.controlEndsAt) {
          if (piece.fits) this.dropPiece(piece, 'timeout');
          else this.discardPiece(piece, '시간 초과, 자리 없음');
        }
        continue;
      }
      // falling
      while (this.pieces.includes(piece) && this.time >= piece.nextStepAt) {
        if (piece.pz <= piece.landZ) {
          this.landPiece(piece);
          break;
        }
        piece.nextStepAt += piece.stepMs;
        if (this.blockedByPiece(piece)) continue;
        piece.pz--;
        this.refreshPieceCells();
        this.crushCheck(piece);
        if (piece.pz <= piece.landZ) {
          this.landPiece(piece);
          break;
        }
      }
    }
  }

  // 블록 셀이 플레이어 AABB 와 겹치면 압사
  crushCheck(piece = this.piece) {
    const cells = this.pieceWorldCells(piece);
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

  landPiece(piece = this.piece) {
    for (const [x, y, z] of this.pieceWorldCells(piece)) {
      if (z >= 0 && z < C.GRID_H) this.grid[this.idx(x, y, z)] = 1;
    }
    const cells = this.pieceWorldCells(piece);
    this.emit({ type: 'land', cells: cells.map(([x, y, z]) => [x, y, z]), controlled: piece.controller !== null });
    const wasControlled = piece.controller !== null;
    this.removePiece(piece);
    this.gridVersion++;
    this.gridDirty = true;
    this.clearLayers();
    for (const pc of this.pieces) this.updateLanding(pc);
    this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + this.autoSpawnDelayMs());
    if (wasControlled) {
      this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
      // 남의 조종 블록이 끝나길 기다리던 조종권 보유자는 바로 조종 시작
      const holder = [...this.players.values()].find((p) => p.alive && p.hasControl);
      if (holder) this.startControlNow(holder);
    }
    for (const it of this.items) it.z = this.columnTop(it.x, it.y);
  }

  // 한 층이 꽉 차면 제거하고 위의 블록·플레이어·아이템을 내린다 (용암도 같이 내려간다)
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
    if (this.lava.active) this.lava.z -= full.filter((z) => z < this.lava.z).length;
    this.emit({ type: 'clear', n: full.length });
    this.log(`  [층 클리어] z=${full.join(',')} 제거 → 위 블록·플레이어 ${full.length}칸 내려앉음`);
  }

  // ---------- 용암 ----------
  avgHeight() {
    let sum = 0;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) sum += this.columnTop(x, y);
    return sum / (C.GRID_W * C.GRID_D);
  }

  updateLava(dtMs) {
    const lava = this.lava;
    if (!lava.active) {
      if (this.avgHeight() - this.baseAvgHeight < C.LAVA_TRIGGER_AVG_HEIGHT) return; // 시작 지형 빼고 쌓인 만큼
      lava.active = true;
      lava.z = C.LAVA_START_Z;
      lava.startedAt = this.time;
      this.emit({ type: 'lava' });
      this.log(`  [용암] 쌓인 평균 높이 ${(this.avgHeight() - this.baseAvgHeight).toFixed(2)} → 용암 상승 시작 @ ${fmtTime(this.elapsed())}`);
      return;
    }
    lava.z = Math.min(C.GRID_H + 1, lava.z + dtMs / C.LAVA_RISE_MS_PER_CELL);
    for (const p of this.players.values()) if (p.alive && p.z < lava.z - 0.05) this.kill(p, 'lava');
    this.items = this.items.filter((it) => it.z >= lava.z);
  }

  // ---------- 아이템 ----------
  spawnItem(type) {
    for (let i = 0; i < C.SPAWN_TRIES; i++) {
      const x = Math.floor(this.rng() * C.GRID_W);
      const y = Math.floor(this.rng() * C.GRID_D);
      const z = this.columnTop(x, y);
      if (z >= C.GRID_H) continue;
      if (this.lava.active && z < this.lava.z + 1) continue; // 용암에 잠길 자리는 피함
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
      this.pieces.some((pc) => pc.controller !== null);
    if (!anyControl && this.time >= this.controlItemNextAt) {
      if (!this.spawnItem('control')) this.controlItemNextAt = this.time + 1000;
    }
    const powerCount = this.items.filter((it) => it.type !== 'control').length;
    if (powerCount < C.ITEM_MAX_ON_FIELD && this.time >= this.powerItemNextAt) {
      const type = C.ITEM_POOL[Math.floor(this.rng() * C.ITEM_POOL.length)];
      this.powerItemNextAt = this.time + (this.spawnItem(type) ? C.ITEM_RESPAWN_MS : 1000);
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
    } else if (type === 'weapon') {
      p.weaponUses = C.WEAPON_USES;
      this.log(`  [아이템] ${p.name} 망치 획득 (${p.weaponUses}회)`);
    } else if (type === 'jump') {
      p.jumpUntil = this.time + C.JUMP_BOOST_MS;
      this.log(`  [아이템] ${p.name} 점프력 상승 획득`);
    } else if (type === 'ghost') {
      p.ghostUntil = this.time + C.GHOST_MS;
      this.log(`  [아이템] ${p.name} 유령화 획득`);
    }
  }

  isGhost(p) {
    return this.time < p.ghostUntil;
  }

  // 유령화가 끝났는데 블록 안이면 그 기둥 꼭대기로 밀어 올린다
  ejectFromBlocks(p) {
    for (let i = 0; i < C.GRID_H + 2; i++) {
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
            this.emit({ type: 'hit', kind: 'projectile', by: pr.owner, target: t.id, ok: hit });
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
    if (p.ghostUntil && this.time >= p.ghostUntil) {
      p.ghostUntil = 0;
      this.ejectFromBlocks(p);
    }
    if (this.time < p.freezeUntil) return; // 히트스톱
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
        p.vz = this.time < p.jumpUntil ? C.JUMP_BOOST_SPEED : C.JUMP_SPEED;
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
    if (axis === 'x') p.kbx = 0;
    else p.kby = 0;
  }

  // ---------- 틱 ----------
  tick(dtMs) {
    this.time += dtMs;
    if (this.phase !== 'playing') return;
    const dt = dtMs / 1000;
    for (const [id, brain] of this.bots) {
      const p = this.players.get(id);
      if (p && p.alive) brain.update(this, p);
    }
    this.updatePieces();
    let remaining = dt;
    while (remaining > 0) {
      const h = Math.min(remaining, C.MAX_STEP_DT);
      for (const p of this.players.values()) if (p.alive) this.integratePlayer(p, h);
      remaining -= h;
    }
    for (const p of this.players.values()) {
      if (p.alive && p.z < C.FALL_DEATH_Z) this.kill(p, 'fall');
    }
    this.updateLava(dtMs);
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
    const piecesOut = this.pieces.map((piece) => {
      const eta = piece.phase === 'falling' ? Math.max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - this.time)) : Infinity;
      return {
        id: piece.id,
        shape: piece.shape,
        cells: this.pieceWorldCells(piece),
        phase: piece.phase,
        controller: piece.controller,
        landZ: piece.landZ,
        fits: piece.fits,
        shadow: piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]),
        shadowVisible: piece.phase === 'falling' && eta <= C.SHADOW_LEAD_MS,
        eta,
        timeLeft: piece.phase === 'control' ? Math.max(0, piece.controlEndsAt - this.time) : 0,
      };
    });
    // 조종권 보유자에게 "N초 후 조종 시작" 표시용: 남이 조종한 블록이 있으면 그게 착지할 때까지, 아니면 다음 생성까지
    let nextSpawnIn = Math.max(0, this.nextSpawnAt - this.time);
    const ctl = piecesOut.find((pc) => pc.controller !== null);
    if (ctl) nextSpawnIn = ctl.phase === 'control' ? null : ctl.eta;
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
        isBot: !!p.isBot,
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
        weaponUses: p.weaponUses,
        jumpLeft: Math.max(0, p.jumpUntil - this.time),
        ghostLeft: Math.max(0, p.ghostUntil - this.time),
        controlling: this.isControlling(p),
        cause: p.deathCause,
      })),
      pieces: piecesOut,
      nextSpawnIn,
      lava: { active: this.lava.active, z: this.lava.z },
      map: { choice: this.mapChoice, id: this.mapId, name: MAPS[this.mapId].name },
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

function maxPlayers() {
  return Math.min(C.MAX_PLAYERS, C.SPAWN_POINTS.length);
}

function shareText(t) {
  const deaths = t.crush + t.fall + (t.lava || 0);
  if (!deaths) return '사망 없음';
  const share = t.crush / deaths;
  const pass = share >= C.PASS_CRUSH_SHARE ? '합격선 이상' : '합격선 미만';
  return `${(share * 100).toFixed(0)}% (합격선 ${(C.PASS_CRUSH_SHARE * 100).toFixed(0)}% → ${pass})`;
}

function causeKo(cause) {
  if (cause === 'crush') return '압사';
  if (cause === 'fall') return '낙사';
  if (cause === 'lava') return '용암';
  if (cause === 'disconnect') return '접속 끊김';
  return cause;
}
