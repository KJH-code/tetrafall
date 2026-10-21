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

// 플레이어 AABB 가 칸 (cx, cy, cz) 와 겹치는가 (경계에 닿기만 하면 아님)
function overlapsCell(p, cx, cy, cz) {
  return (
    cx < p.x + C.PLAYER_HALF - EPS &&
    cx + 1 > p.x - C.PLAYER_HALF + EPS &&
    cy < p.y + C.PLAYER_HALF - EPS &&
    cy + 1 > p.y - C.PLAYER_HALF + EPS &&
    cz < p.z + C.PLAYER_HEIGHT - EPS &&
    cz + 1 > p.z + EPS
  );
}

function fmtTime(ms) {
  const s = Math.floor(ms / 1000);
  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
}

export class Game {
  // countdownMs: 판 시작 전 카운트다운. 서버는 C.ROUND_COUNTDOWN_MS, 테스트는 기본 0 (바로 시작)
  constructor(log = () => {}, { countdownMs = 0 } = {}) {
    this.log = log;
    this.countdownMs = countdownMs;
    this.rng = Math.random;
    this.time = 0; // 게임 시간 (ms). tick 마다 dt 만큼 증가
    this.phase = 'lobby'; // 'lobby' | 'countdown' | 'playing' | 'over'
    this.players = new Map(); // id -> player
    this.hostId = null;
    this.grid = new Uint8Array(C.GRID_W * C.GRID_D * C.GRID_H);
    this.gridVersion = 0;
    this.pieces = []; // 떨어지는·조종 중인 블록들
    this.pieceCounter = 0;
    this.pieceCells = new Map(); // 셀 키 -> 블록 id (충돌용)
    this.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
    this.botLevel = C.BOT_LEVEL_DEFAULT; // 봇 난이도 (모든 봇 공통)
    this.mapChoice = 'flat'; // 호스트가 고른 맵 ('random' 또는 MAP_IDS 중 하나). 서버는 시작 때 C.MAP_DEFAULT 로 바꾼다
    this.mapId = 'flat'; // 이번 판 맵
    this.baseAvgHeight = 0; // 판 시작 때 지형 평균 높이 (용암은 여기서 더 쌓인 만큼으로 판단)
    this.items = [];
    this.projectiles = [];
    this.bombs = []; // 놓여서 터지길 기다리는 폭탄
    this.bombCounter = 0;
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
      alive: !this.inRound(), // 진행 중(카운트다운 포함) 난입은 관전 (죽은 상태)
      stunUntil: 0,
      freezeUntil: 0, // 히트스톱: 이 시각까지 움직임 정지 (속도는 보존)
      weaponUses: 0, // 망치 남은 횟수
      jumpUntil: 0, // 점프력 상승 끝나는 시각
      ghostUntil: 0, // 유령화 끝나는 시각
      spectator: false, // 호스트가 관전으로 돌린 사람: 판에 안 들어가고 통계·승수 표시에서 빠짐
      nick: '', // 대기 화면에서 넣은 이름 (머리 위 표시용. 로그·승수는 name = P1 그대로)
      hand: 1, // 핫바에서 고른 칸. 1 쌓기 블록 · 2 던지는 아이템 · 3 폭탄
      blocks: 0, // 쌓기 블록 남은 개수 (판마다 BUILD_BLOCKS_PER_ROUND)
      bombs: 0, // 폭탄 남은 개수
      bricks: 0, // 설치 블록(1×2) 남은 개수
      brickSide: false, // 1×2 방향. false = 바라보는 쪽으로 뻗음, true = 옆으로
      damage: 0, // 피해 % (대난투식). 높을수록 멀리 날아감
      wins: 0, // 이긴 판 수 (서버가 켜져 있는 동안, 나가면 사라짐)
      dashReadyAt: 0,
      pushReadyAt: 0,
      hasControl: false,
      ammo: 0,
      deathCause: null,
      lastHit: null, // 판 안에서 마지막으로 나를 날린 사람 { by, name, kind } — 킬 판정
      input: { fwd: 0, strafe: 0, jump: false },
    };
    this.players.set(id, p);
    if (this.hostId === null && !isBot) this.hostId = id;
    this.log(`${p.name} 접속 (slot ${slot})${this.hostId === id ? ' — 호스트' : ''}`);
    return p;
  }

  // 봇 추가 (판 진행 중에는 안 됨). 성공하면 플레이어, 자리가 없으면 null
  addBot() {
    if (this.inRound()) return null;
    const id = -++this.botCounter;
    const p = this.addPlayer(id, true);
    if (p) this.bots.set(id, new BotBrain(() => this.rng(), () => this.botLevel));
    return p;
  }

  // 가장 나중에 넣은 봇 하나 빼기
  removeBot() {
    if (this.inRound() || !this.bots.size) return false;
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
    if (this.inRound() && p.alive) {
      // 카운트다운 중에 나가도 사망 목록에 남긴다 (판 시계는 아직 0)
      this.deaths.push({ name: p.name, cause: 'disconnect', t: this.phase === 'playing' ? this.time - this.roundStartTime : 0 });
      this.checkRoundEnd();
    }
  }

  // 봇 난이도: 판 사이에만. 바꾸면 이미 있는 봇에도 바로 적용
  setBotLevel(level) {
    if (this.inRound() || !Object.hasOwn(C.BOT_LEVELS, level) || level === this.botLevel) return false;
    this.botLevel = level;
    this.log(`[호스트] 봇 난이도: ${BOT_LEVEL_KO[level]}`);
    return true;
  }

  setMap(choice) {
    if (this.inRound()) return false;
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
    return this.participants().length >= C.MIN_PLAYERS && !this.inRound();
  }

  // 판에 참가하는 사람 (관전자 빼고)
  participants() {
    return [...this.players.values()].filter((p) => !p.spectator);
  }

  // 호스트가 관전 ↔ 참가 전환 (판 사이에만)
  setSpectator(id, on) {
    const p = this.players.get(id);
    if (!p || this.inRound()) return false;
    p.spectator = !!on;
    p.alive = !p.spectator; // 판 사이라 참가로 되돌리면 새로 들어온 사람처럼 살아 있는 상태 (리뷰 지적: 죽은 채 남았음)
    this.log(`[호스트] ${p.name} ${p.spectator ? '관전으로' : '참가로'}`);
    return true;
  }

  // 이름 바꾸기: 판 사이에만. 제어 문자 빼고 공백 하나로, NAME_MAX_LEN 글자까지 (한글도 한 글자)
  setNick(id, raw) {
    const p = this.players.get(id);
    if (!p || this.inRound()) return false;
    const clean = String(raw ?? '')
      .replace(/[\u0000-\u001f\u007f]/g, '')
      .replace(/\s+/g, ' ')
      .trim();
    const nick = Array.from(clean).slice(0, C.NAME_MAX_LEN).join('');
    if (nick === p.nick) return true;
    p.nick = nick;
    this.log(`${p.name} 이름: ${nick || '(없음)'}`);
    return true;
  }

  // 판 진행 중 (카운트다운 포함): 봇·맵을 못 바꾸고, 들어온 사람은 관전
  inRound() {
    return this.phase === 'playing' || this.phase === 'countdown';
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
    this.bombs = []; // 놓여서 터지길 기다리는 폭탄
    this.bombCounter = 0;
    this.deaths = [];
    this.events = [];
    this.winnerId = null;
    this.roundNumber++;
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
        alive: !p.spectator,
        stunUntil: 0,
        freezeUntil: 0,
        weaponUses: 0,
        jumpUntil: 0,
        ghostUntil: 0,
        hand: 1,
        blocks: C.BUILD_BLOCKS_PER_ROUND,
        bombs: 0,
        bricks: 0,
        brickSide: false,
        damage: 0,
        dashReadyAt: 0,
        pushReadyAt: 0,
        hasControl: false,
        ammo: 0,
        deathCause: null,
        lastHit: null,
      });
    }
    if (this.countdownMs > 0) {
      this.phase = 'countdown';
      this.countdownEndsAt = this.time + this.countdownMs;
    } else {
      this.beginPlay();
    }
    return true;
  }

  // 카운트다운이 끝나면 (또는 바로) 판 시작. 판 시간·블록·아이템 시계는 여기서부터
  beginPlay() {
    this.phase = 'playing';
    // 인원수별 통계는 실제로 판을 시작한 인원으로 (카운트다운 중에 나간 사람은 빼고)
    const ps = this.participants();
    this.roundPlayerCount = ps.length;
    this.roundBotCount = ps.filter((p) => p.isBot).length;
    this.roundStartTime = this.time;
    this.nextSpawnAt = this.time + C.FIRST_SPAWN_DELAY_MS;
    this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
    this.powerItemNextAt = this.time + C.ITEM_FIRST_SPAWN_MS;
    const lv = ps.some((p) => p.isBot) ? `, 봇 ${BOT_LEVEL_KO[this.botLevel]}` : '';
    this.log(`===== ROUND ${this.roundNumber} 시작 (${ps.length}명: ${ps.sort((a, b) => a.slot - b.slot).map((p) => p.name).join(' ')}, 맵 ${MAPS[this.mapId].name}${lv}) =====`); // 참가자 목록은 npm run stats 가 구성별로 셀 때 씀
    this.checkRoundEnd(); // 카운트다운 중에 나가서 혼자 남았으면 바로 끝
  }

  endRound(winner) {
    this.phase = 'over';
    this.roundEndTime = this.time;
    this.winnerId = winner ? winner.id : null;
    if (winner) winner.wins++;
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
    this.log(`  승수: ${this.participants().sort((a, b) => a.slot - b.slot).map((p) => `${p.name} ${p.wins}`).join(' / ')}`);
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

  // 킬: src(그 블록을 조종·투척한 사람)가 있으면 그 사람, 없으면 판 안에서 마지막으로 나를 날린 사람 (시간 제한 없음).
  // 내 블록에 내가 깔리면 킬 없음
  kill(p, cause, src = null) {
    if (!p.alive) return;
    p.alive = false;
    p.deathCause = cause;
    p.hasControl = false;
    const t = this.time - this.roundStartTime;
    let credit = src ? { by: src.by, kind: src.kind, name: this.players.get(src.by)?.name } : p.lastHit;
    if (credit && (credit.by === p.id || !credit.name)) credit = null;
    this.deaths.push({ name: p.name, cause, t, killer: credit ? credit.name : null, weapon: credit ? credit.kind : null });
    this.emit({ type: 'death', who: p.id, cause, by: credit ? credit.by : null, weapon: credit ? credit.kind : null, byName: credit ? credit.name : null });
    const killText = credit ? `, 킬 ${credit.name} ${WEAPON_LOG[credit.kind]}` : ', 킬 없음'; // "킬 없음" 을 적어야 킬 기록이 없던 옛 로그와 구분됨
    this.log(`  [사망] ${p.name} ${causeKo(cause)} @ ${fmtTime(t)} (위치 ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}, 피해 ${p.damage}%${killText})`);
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
      case 'fire': // 우클릭: 고른 핫바 칸을 씀
        if (stunned || controlling) return;
        if (p.hand === 1) this.placeBlock(p);
        else if (p.hand === 2) {
          if (p.bricks > 0) this.throwBrick(p);
          else if (p.ammo > 0) this.fire(p);
        } else if (p.hand === 3) this.throwBomb(p);
        return;
      case 'hand': // 숫자키 1·2·3
        if ([1, 2, 3].includes(action.n)) p.hand = action.n;
        return;
      case 'handNext': // 마우스 휠
        p.hand = ((p.hand - 1 + (action.dir > 0 ? 1 : 2)) % 3) + 1;
        return;
      case 'pieceMove':
        if (!controlling) return;
        this.movePiece(this.controlledPiece(p), action.dx | 0, action.dy | 0);
        return;
      case 'rotate':
        if (!controlling) {
          if (p.bricks > 0) p.brickSide = !p.brickSide; // 조종 중이 아니면 Q/E 는 1×2 방향 바꾸기
          return;
        }
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
    // 망치가 있으면 밀치기 대신 망치. 누군가를 실제로 날렸을 때만 1회 소모 (2026-10-20 재혁: 적중 시만)
    const weapon = p.weaponUses > 0;
    let landed = false;
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
      const hit = this.applyKnockback(t, fx, fy, speed, up, stun, C.DAMAGE_GAIN[kind], { by: p.id, kind });
      if (hit) p.freezeUntil = this.time + C.HITSTOP_MS; // 때린 쪽도 같이 멈칫
      if (hit && weapon && !landed) {
        landed = true;
        p.weaponUses--; // 한 번 휘둘러 여럿 맞혀도 1회
      }
      this.emit({ type: 'hit', kind, by: p.id, target: t.id, ok: hit });
      this.log(`  [${weapon ? '망치' : '밀치기'}] ${p.name} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '경직 중이라 무시'}${weapon ? ` (남은 ${p.weaponUses}회)` : ''}`);
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
      if (!inXY(cx, cy)) break;
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
    if (!cells.every(([x, y]) => inXY(x, y))) return { cells: cells.map(([x, y]) => [x, y, 0]), z: 0, ok: false };
    const z = Math.max(...cells.map(([x, y]) => this.columnTop(x, y)));
    const spawnZ = Math.min(z + C.BRICK_DROP_HEIGHT, C.GRID_H - 1);
    const ok =
      z < C.GRID_H - 1 &&
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

  // ---- 쌓기 블록 (핫바 1번) ----
  // 시선이 처음 닿는 블록 면(바닥 포함) 바로 앞 칸. 칸 단위로 시선을 따라간다 (DDA). 사거리 BUILD_RANGE
  buildPlan(p, yaw = p.yaw, pitch = p.pitch) {
    const cp = Math.cos(pitch);
    const d = [cp * Math.cos(yaw), cp * Math.sin(yaw), Math.sin(pitch)];
    const o = [p.x, p.y, p.z + C.EYE_HEIGHT];
    const cell = o.map(Math.floor);
    const step = d.map((v) => (v > 0 ? 1 : v < 0 ? -1 : 0));
    const tMax = d.map((v, i) => (v === 0 ? Infinity : ((v > 0 ? cell[i] + 1 : cell[i]) - o[i]) / v));
    const tDelta = d.map((v) => (v === 0 ? Infinity : Math.abs(1 / v)));
    const solid = ([x, y, z]) => (z < 0 ? inXY(x, y) : inXY(x, y) && z < C.GRID_H && !!this.grid[this.idx(x, y, z)]);
    let prev = cell.slice();
    for (let n = 0; n < 64; n++) {
      const a = tMax[0] < tMax[1] ? (tMax[0] < tMax[2] ? 0 : 2) : tMax[1] < tMax[2] ? 1 : 2;
      if (tMax[a] > C.BUILD_RANGE) break;
      prev = cell.slice();
      cell[a] += step[a];
      tMax[a] += tDelta[a];
      if (!solid(cell)) continue;
      const [x, y, z] = prev;
      const free = inXY(x, y) && z >= 0 && z < C.GRID_H && !this.grid[this.idx(x, y, z)] && !this.pieceCells.has(cellKey(x, y, z));
      const nobody = ![...this.players.values()].some((t) => t.alive && overlapsCell(t, x, y, z));
      return { cells: [[x, y, z]], ok: free && nobody };
    }
    return { cells: [], ok: false };
  }

  placeBlock(p) {
    if (p.blocks <= 0) return false;
    const plan = this.buildPlan(p);
    if (!plan.ok) return false;
    const [x, y, z] = plan.cells[0];
    p.blocks--;
    this.grid[this.idx(x, y, z)] = 1;
    this.gridChanged();
    this.emit({ type: 'build', who: p.id, cells: plan.cells });
    this.log(`  [쌓기] ${p.name} → (${x},${y},${z}) (남은 ${p.blocks}개)`);
    this.clearLayers();
    return true;
  }

  // 격자가 바뀐 뒤: 떨어지는 블록 착지점, 아이템·폭탄 높이 다시 계산
  gridChanged() {
    this.gridVersion++;
    this.gridDirty = true;
    for (const pc of this.pieces) this.updateLanding(pc);
    for (const it of this.items) it.z = this.columnTop(it.x, it.y);
    for (const b of this.bombs) b.z = this.columnTop(b.x, b.y);
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
    for (let dx = -R; dx <= R; dx++) for (let dy = -R; dy <= R; dy++) if ((dx || dy) && inXY(ax + dx, ay + dy)) cells.push([ax + dx, ay + dy, z]);
    return { cells, ok: z < C.GRID_H };
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
          if (!inXY(x, y) || z < 0 || z >= C.GRID_H || !this.grid[this.idx(x, y, z)]) continue;
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
      if (!t.alive || t.id === b.by) continue;
      const dx = t.x - cx;
      const dy = t.y - cy;
      if (Math.hypot(dx, dy) > C.BOMB_BLAST_RANGE || Math.abs(t.z + C.PLAYER_HEIGHT / 2 - cz) > C.BOMB_BLAST_RANGE) continue;
      const a = this.rng() * Math.PI * 2; // 바로 위에 서 있으면 방향이 없어서 무작위
      const hit = Math.hypot(dx, dy) > 0.05
        ? this.applyKnockback(t, dx, dy, C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN.bomb, { by: b.by, kind: 'bomb' })
        : this.applyKnockback(t, Math.cos(a), Math.sin(a), C.BOMB_KB_SPEED, C.BOMB_KB_UP, C.BOMB_STUN_MS, C.DAMAGE_GAIN.bomb, { by: b.by, kind: 'bomb' });
      this.emit({ type: 'hit', kind: 'bomb', by: b.by, target: t.id, ok: hit });
      this.log(`  [폭탄] ${by ? by.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '경직 중이라 무시'}`);
    }
    if (removed) this.gridChanged();
  }

  // 지금 고른 핫바 칸으로 우클릭하면 생길 것 (클라이언트 미리보기)
  aimPreview(p) {
    if (p.hand === 1 && p.blocks > 0) return { kind: 'build', ...this.buildPlan(p) };
    if (p.hand === 2 && p.bricks > 0) return { kind: 'brick', ...this.brickPlan(p) };
    if (p.hand === 3 && p.bombs > 0) return { kind: 'bomb', ...this.bombPlan(p) };
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
      if (!t.alive || t.id === piece.thrownBy) continue; // 던진 사람은 자기 충격파를 안 맞음
      const gx = Math.max(x0 - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - x1, 0);
      const gy = Math.max(y0 - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - y1, 0);
      if (Math.hypot(gx, gy) > C.BRICK_SHOCK_RANGE || Math.abs(t.z - z) > C.BRICK_SHOCK_HEIGHT) continue;
      const hit = this.applyKnockback(t, t.x - cx, t.y - cy, C.BRICK_SHOCK_KB_SPEED, C.BRICK_SHOCK_KB_UP, C.BRICK_SHOCK_STUN_MS, C.DAMAGE_GAIN.shock, { by: piece.thrownBy, kind: 'shock' });
      this.emit({ type: 'hit', kind: 'shock', by: piece.thrownBy, target: t.id, ok: hit });
      this.log(`  [충격파] ${by ? by.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '경직 중이라 무시'}`);
    }
  }

  // 경직 중이면 무시 (연속 넉백 불가). 성공 시 true
  // gain: 이번 공격으로 쌓이는 피해 %. 맞기 전까지 쌓인 % 로 수평 넉백을 키우고 그다음에 쌓는다
  // (위로 튀는 속도는 그대로)
  // src: { by, kind } — 누가 무엇으로 날렸는지 (킬 판정용 lastHit)
  applyKnockback(t, dx, dy, speed, up, stunMs = C.STUN_MS, gain = 0, src = null) {
    if (this.time < t.stunUntil) return false;
    if (src && src.by !== t.id) t.lastHit = { by: src.by, kind: src.kind, name: this.players.get(src.by)?.name };
    const mult = C.DAMAGE_KB_BASE + t.damage * C.DAMAGE_KB_PER_PERCENT;
    t.damage += gain;
    const len = Math.hypot(dx, dy) || 1;
    t.kbx = (dx / len) * speed * mult;
    t.kby = (dy / len) * speed * mult;
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
    const autos = this.pieces.filter((pc) => pc.controller === null && !pc.thrownBy).length; // 던진 블록은 안 셈
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
    for (const pc of this.pieces) if (pc.phase === 'falling' && !pc.thrownBy && (!piece || pc.pz > piece.pz)) piece = pc; // 던진 블록은 못 뺏음
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
          if (piece.thrownBy) {
            const by = this.players.get(piece.thrownBy);
            this.log(`  [투척] ${by ? by.name : '?'} 의 ${piece.shape} 에 ${p.name} 깔림`);
          }
          // 조종한 블록·던진 블록이면 그 사람의 킬, 자동 블록이면 마지막으로 날린 사람
          const src = piece.controller !== null ? { by: piece.controller, kind: 'control' } : piece.thrownBy ? { by: piece.thrownBy, kind: 'thrown' } : null;
          this.kill(p, 'crush', src);
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
    if (piece.thrownBy) this.brickShock(piece);
    this.removePiece(piece);
    this.gridVersion++;
    this.gridDirty = true;
    this.clearLayers();
    for (const pc of this.pieces) this.updateLanding(pc);
    if (!piece.thrownBy) this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + this.autoSpawnDelayMs()); // 던진 블록은 자동 블록 간격에 안 끼어듦
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
    // 필드 밖에서 용암 높이 아래로 가면 밀려 떨어진 것이라 낙사로 센다 (용암판은 필드보다 넓게 그려짐)
    for (const p of this.players.values()) {
      if (!p.alive || p.z >= lava.z - 0.05) continue;
      const inField = p.x >= 0 && p.x < C.GRID_W && p.y >= 0 && p.y < C.GRID_D;
      this.kill(p, inField ? 'lava' : 'fall');
    }
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
      control: this.controlInPlay() ? null : Math.max(0, this.controlItemNextAt - this.time),
      power: powerCount >= C.ITEM_MAX_ON_FIELD ? null : Math.max(0, this.powerItemNextAt - this.time),
    };
  }

  updateItems() {
    if (!this.controlInPlay() && this.time >= this.controlItemNextAt) {
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
      const dropped = p.bricks;
      p.bricks = 0; // 핫바 2번 칸 공유: 나중에 먹은 쪽만 남는다
      p.ammo += C.KNOCKBACK_AMMO;
      p.hand = 2;
      this.log(`  [아이템] ${p.name} 넉백 아이템 획득 (탄 ${p.ammo})${dropped ? ' — 설치 블록 버림' : ''}`);
    } else if (type === 'weapon') {
      p.weaponUses = C.WEAPON_USES;
      this.log(`  [아이템] ${p.name} 망치 획득 (${p.weaponUses}회)`);
    } else if (type === 'jump') {
      p.jumpUntil = this.time + C.JUMP_BOOST_MS;
      this.log(`  [아이템] ${p.name} 점프력 상승 획득`);
    } else if (type === 'ghost') {
      p.ghostUntil = this.time + C.GHOST_MS;
      this.log(`  [아이템] ${p.name} 유령화 획득`);
    } else if (type === 'brick') {
      const dropped = p.ammo;
      p.ammo = 0;
      p.bricks = C.BRICK_USES;
      p.brickSide = false;
      p.hand = 2;
      this.log(`  [아이템] ${p.name} 설치 블록 1×2 획득 (${p.bricks}개)${dropped ? ' — 투사체 버림' : ''}`);
    } else if (type === 'bomb') {
      p.bombs = C.BOMB_USES;
      p.hand = 3;
      this.log(`  [아이템] ${p.name} 폭탄 획득`);
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
            const hit = this.applyKnockback(t, pr.dx, pr.dy, C.PROJECTILE_KB_SPEED, C.PROJECTILE_KB_UP, C.STUN_MS, C.DAMAGE_GAIN.projectile, { by: pr.owner, kind: 'projectile' });
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
    if (this.phase === 'countdown' && this.time >= this.countdownEndsAt) this.beginPlay();
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
    this.updateBombs();
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
        thrown: !!piece.thrownBy, // 설치 블록 (노랑)
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
        elapsed: this.phase === 'playing' ? this.time - this.roundStartTime : this.phase === 'countdown' ? 0 : this.roundEndTime - this.roundStartTime,
        countdownLeft: this.phase === 'countdown' ? Math.max(0, this.countdownEndsAt - this.time) : 0,
        winnerId: this.winnerId,
        deaths: this.deaths,
        totals: this.totals,
      },
      players: [...this.players.values()].map((p) => ({
        id: p.id,
        slot: p.slot,
        name: p.name,
        nick: p.nick,
        spectator: p.spectator,
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
        pushCd: Math.max(0, p.pushReadyAt - this.time),
        weaponUses: p.weaponUses,
        jumpLeft: Math.max(0, p.jumpUntil - this.time),
        ghostLeft: Math.max(0, p.ghostUntil - this.time),
        hand: p.hand,
        blocks: p.blocks,
        bombs: p.bombs,
        bricks: p.bricks,
        brickSide: p.brickSide,
        aim: p.alive ? this.aimPreview(p) : null, // 고른 칸으로 우클릭하면 어디에 무엇이 생기는지
        damage: p.damage,
        wins: p.wins,
        controlling: this.isControlling(p),
        cause: p.deathCause,
      })),
      pieces: piecesOut,
      nextSpawnIn,
      lava: { active: this.lava.active, z: this.lava.z },
      itemTimers: this.itemTimers(),
      botLevel: this.botLevel,
      map: { choice: this.mapChoice, id: this.mapId, name: MAPS[this.mapId].name },
      items: this.items,
      projectiles: this.projectiles.map((pr) => ({ x: pr.x, y: pr.y, z: pr.z })),
      bombs: this.bombs.map((b) => ({ id: b.id, x: b.x, y: b.y, z: b.z, left: Math.max(0, b.explodeAt - this.time) })),
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

const BOT_LEVEL_KO = { easy: '쉬움', normal: '보통', hard: '어려움' };

// 킬 로그의 공격 이름 (npm run stats 가 한 단어로 읽음)
const WEAPON_LOG = { push: '밀치기', weapon: '망치', projectile: '투사체', shock: '충격파', bomb: '폭탄', control: '조종블록', thrown: '설치블록' };

function causeKo(cause) {
  if (cause === 'crush') return '압사';
  if (cause === 'fall') return '낙사';
  if (cause === 'lava') return '용암';
  if (cause === 'disconnect') return '접속 끊김';
  return cause;
}
