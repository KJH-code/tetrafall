// Tetrafall 서버 게임 상태. 권위는 전부 여기에 있다.
// 격자는 3D 정수 배열, 플레이어는 AABB + 넉백. 물리엔진 없음.
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, CELL, cellOfShape, rotatedCells, footprint } from '../shared/pieces.js';
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
  // characters: 캐릭터(패시브·스킬·필살기)를 쓸지. 서버(방)는 켬, 예전 규칙 테스트는 끔 (모두 캐릭터 없음 = 예전 그대로)
  constructor(log = () => {}, { countdownMs = 0, characters = false } = {}) {
    // 콤보 마무리 줄은 그 타의 [평타]·[돌진] 줄 다음에 찍히게 미뤄 둠 (다음 로그 줄 뒤, 또는 틱 시작에)
    this.pendingLogs = [];
    this.log = (m) => {
      log(m);
      this.flushLogs();
    };
    this.flushLogs = () => {
      while (this.pendingLogs.length) log(this.pendingLogs.shift());
    };
    this.countdownMs = countdownMs;
    this.characters = characters;
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
    this.teamMode = false; // 팀전 (호스트가 대기 화면에서 켬). 사람마다 team = 'red' | 'blue'
    this.mode = C.MODE_DEFAULT; // 게임 모드: 'survival' | 'master' | 'kills' (MODES)
    this.masterTurn = 0; // 블록 마스터: 다음 판 마스터 차례 (자리 순서)
    this.roundEndsAt = 0; // 블록 마스터·킬 점수전: 판이 시간으로 끝나는 시각
    this.scores = new Map(); // 킬 점수전: 플레이어 id → 점수 (판마다 초기화)
    this.teamScores = { red: 0, blue: 0 }; // 킬 점수전 팀전: 팀 점수
    this.winnerIds = []; // 이번 판 승자들 (블록 마스터에서 생존자가 이기면 여럿)
    this.teamWins = { red: 0, blue: 0 };
    this.winnerTeam = null;
    this.mapChoice = 'flat'; // 호스트가 고른 맵 ('random' 또는 MAP_IDS 중 하나). 서버는 시작 때 C.MAP_DEFAULT 로 바꾼다
    this.mapId = 'flat'; // 이번 판 맵
    this.baseAvgHeight = 0; // 판 시작 때 지형 평균 높이 (용암은 여기서 더 쌓인 만큼으로 판단)
    this.items = [];
    this.projectiles = [];
    this.bombs = []; // 놓여서 터지길 기다리는 폭탄
    this.bblocks = new Map(); // 건축가 블록: 셀 키 -> { x, y, z, owner, kind: 'wall'|'third'|'pad'|'big', group, expiresAt, born }
    this.bigBombs = []; // 건축가 대폭발 대기: { owner, group, at, dir }
    this.holes = []; // 폭발 구멍 (테스트 옵션 BUILDER_BLAST_HOLE): { x, y, z, v, at }
    this.quakes = []; // 탱크 R 솟는 땅 (잠깐 솟았다 가라앉음): { cells: [[x,y,z]], at }
    this.bgroup = 0;
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
      jumpUntil: 0, // 점프력 상승 끝나는 시각
      airJumps: C.AIR_JUMPS, // 남은 2단 점프 (땅에 닿으면 다시 채움)
      airJumpQueued: false, // 공중에서 점프 키를 새로 눌렀음 (다음 틱에 2단 점프)
      jumpQueuedUntil: 0, // 땅에서 누른 점프 기억 (JUMP_BUFFER_MS)
      ghostUntil: 0, // 유령화 끝나는 시각
      speedUntil: 0, // 이속 증가 끝나는 시각
      spectator: false, // 호스트가 관전으로 돌린 사람: 판에 안 들어가고 통계·승수 표시에서 빠짐
      nick: '', // 대기 화면에서 넣은 이름 (머리 위 표시용. 로그·승수는 name = P1 그대로)
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
      team: this.smallerTeam(), // 팀전용. 들어올 때 사람이 적은 팀으로
      emote: -1, // 이모트 번호 (EMOTE_NAMES), -1 = 안 함
      emoteUntil: 0,
      emoteReadyAt: 0,
      master: false, // 블록 마스터 판의 마스터 편: 살아 있지만 필드에 없음 (하늘에서 블록만 조종)
      zombie: false, // 블록 마스터: 죽어서 마스터 편이 된 생존자 (처음 마스터는 false)
      nextPieceAt: 0, // 블록 마스터: 마스터 편 각자의 다음 블록 시각
      respawnAt: 0, // 킬 점수전: 죽은 뒤 부활하는 시각 (0 = 부활 안 함)
      shieldUntil: 0, // 킬 점수전: 부활 직후 무적 (안 밀리고 안 깔림)
      wallBounced: false, // 이번 넉백에서 벽 튕김을 이미 했나
      char: this.characters ? (isBot ? C.CHARACTERS[Math.floor(this.rng() * C.CHARACTERS.length)] : C.CHAR_DEFAULT) : null, // 캐릭터 (봇은 무작위)
      skillReadyAt: 0, // 스킬 F 다시 쓸 수 있는 시각
      ult: 0, // 필살기 게이지 (ULT_MAX 면 R)
      comboHits: 0, // 지금 이어지는 콤보에서 맞은 횟수 (경직 중에 또 맞으면 +1)
      comboStartAt: 0, // 이 콤보 첫 타 시각 (COMBO_MS 가 지나면 다음 타가 마무리)
      iframeUntil: 0, // 콤보가 끝난 뒤 무적 (공격만 막음)
      chargeUntil: 0, // 탱크 돌진 중
      slamAt: 0, // 탱크 내려찍기: 이 시각에 쾅
      wallAt: 0, // 건축가 솟는 벽: 이 시각에 솟음 (wallCells)
      wallCells: null,
      loaded: true, // 갈고리 플린트록 장전 (판 시작·부활 때 장전, F 로 상대를 끌어오면 장전, 탕 쏘면 빈 총)
      zipUntil: 0, // 갈고리 F 블록 걸기: 이 시각까지 zipDir 로 끌려감
      zipDir: null,
      grab: null, // 갈고리 R: 뽑은 블록 { at, v, meta, from } (at 에 내려찍기)
      atk: null, // 캐릭터 평타 준비 중: { n(몇 번째 타, 공중 0), def, at(판정 시각) }
      atkQueued: false, // 후딜·준비 중에 누른 평타 (끝나면 나감)
      atkLanded: false, // 마지막 평타가 상대를 맞혔나 (맞았으면 후딜을 스킬로 캔슬)
      castQueued: null, // 평타 준비·빗나간 후딜 중에 누른 'skill' 또는 'ult' (판정·후딜이 끝나면 나감)
      chainN: 0, // 마지막으로 맞힌 평타 타 번호 (0 = 다음은 1타)
      chainUntil: 0, // 이 시각까지 누르면 다음 타
      launchUntil: 0, // 띄우는 마지막 지상 타 뒤 공중 1타가 연타로 이어지는 시각
      airN: 0, // 마지막으로 친 공중 평타 번호 (0 = 다음은 공중 1타)
      lastBasic: null, // 마지막 평타 { n, air, at } (봇)
      streak: 0, // 내가 이어 넣은 타 수 (상대가 바뀌어도 이어짐: 닌자 갈아타기 'N HIT')
      streakUntil: 0,
      empowerUntil: 0, // 닌자 R 강화 (표창 2연)
      star2: null, // 표창 둘째 발 { at, n, air, def }
      touchPiece: 0, // 닌자 패시브: 마지막으로 닿은 떨어지는 블록 id (한 블록에 한 번)
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
    if (this.inRound() && p.alive && !p.zombie) {
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

  // 게임 모드 (판 사이에만). 블록 마스터는 1 대 다라 팀전을 끈다
  setMode(mode) {
    if (this.inRound() || !Object.hasOwn(C.MODE_NAMES, mode) || this.mode === mode) return false;
    this.mode = mode;
    this.log(`[호스트] 모드: ${C.MODE_NAMES[mode]}`);
    if (mode === 'master' && this.teamMode) {
      this.teamMode = false;
      this.log('[호스트] 팀전 끔 (블록 마스터는 1 대 다)');
    }
    return true;
  }

  // 캐릭터 고르기 (판 사이에만, 같은 캐릭터 여럿 됨)
  setChar(id, c) {
    const p = this.players.get(id);
    if (!p || !this.characters || this.inRound() || !C.CHARACTERS.includes(c) || p.char === c) return false;
    p.char = c;
    this.log(`${p.name} 캐릭터: ${C.CHAR_NAMES[c]}`);
    return true;
  }

  // 손에 든 아이템 (하나만): 'knockback' | 'brick' | 'bomb' | null
  heldItem(p) {
    return p.ammo > 0 ? 'knockback' : p.bricks > 0 ? 'brick' : p.bombs > 0 ? 'bomb' : null;
  }

  // 필드 위에 있는 사람: 살아 있고 블록 마스터의 마스터가 아님. 밀치기·폭탄·압사·용암·아이템·물리의 대상
  onField(p) {
    return p.alive && !p.master;
  }

  // 블록 마스터 판의 처음 마스터 (없으면 null). 죽어서 넘어간 마스터 편(zombie)은 빼고
  master() {
    return [...this.players.values()].find((p) => p.master && !p.zombie) || null;
  }

  // 블록 마스터: 죽은 생존자는 하늘로 올라가 마스터 편이 됨 (자기 블록을 따로 떨어뜨림, 이겨도 승수는 처음 마스터만)
  joinMasterSide(p) {
    Object.assign(p, {
      alive: true,
      master: true,
      zombie: true,
      x: C.GRID_W / 2,
      y: C.GRID_D / 2,
      z: C.GRID_H + 4,
      vz: 0,
      kbx: 0,
      kby: 0,
      stunUntil: 0,
      ghostUntil: 0,
      hasControl: false,
      nextPieceAt: this.time + C.MASTER_NEXT_PIECE_MS,
    });
    this.emit({ type: 'zombie', who: p.id });
    this.log(`  [마스터 편] ${p.name} → 하늘에서 블록`);
  }

  // 블록 마스터 탑 방지: 놓인 뒤 높이(landZ+1)가 둘레(8방향, 필드 밖은 0) 가장 높은 기둥보다 MASTER_MAX_RISE 넘게 높으면 true
  tooTall(cellsXY, landZ) {
    const own = new Set(cellsXY.map(([x, y]) => x * 100 + y));
    let ring = 0;
    for (const [x, y] of cellsXY) {
      for (let dx = -1; dx <= 1; dx++) {
        for (let dy = -1; dy <= 1; dy++) {
          const nx = x + dx;
          const ny = y + dy;
          if (own.has(nx * 100 + ny) || !inXY(nx, ny)) continue;
          ring = Math.max(ring, this.columnTop(nx, ny));
        }
      }
    }
    return landZ + 1 - ring > C.MASTER_MAX_RISE;
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
    const ps = this.participants();
    if (this.teamMode && !(ps.some((p) => p.team === 'red') && ps.some((p) => p.team === 'blue'))) return false; // 팀마다 한 명 이상
    return ps.length >= C.MIN_PLAYERS && !this.inRound();
  }

  // ---------- 팀전 ----------
  // 같은 팀이면 밀리기는 하지만 피해 % 는 안 쌓이고, 킬로도 안 친다 (2026-10-22 재혁)
  sameTeam(a, b) {
    return this.teamMode && !!a && !!b && a !== b && a.team === b.team;
  }

  smallerTeam() {
    const ps = [...this.players.values()];
    return ps.filter((p) => p.team === 'red').length <= ps.filter((p) => p.team === 'blue').length ? 'red' : 'blue';
  }

  setTeamMode(on) {
    if (this.inRound() || this.teamMode === !!on) return false;
    if (on && this.mode === 'master') return false; // 블록 마스터는 팀전 없음
    this.teamMode = !!on;
    this.log(`[호스트] 팀전 ${this.teamMode ? '켬' : '끔'}`);
    return true;
  }

  setTeam(id, team) {
    const p = this.players.get(id);
    if (!p || this.inRound() || (team !== 'red' && team !== 'blue')) return false;
    p.team = team;
    this.log(`[호스트] ${p.name} ${TEAM_KO[team]}팀으로`);
    return true;
  }

  // 참가자를 무작위로 섞어 반씩 (홀수면 빨강이 한 명 더)
  shuffleTeams() {
    if (this.inRound()) return false;
    const ps = this.participants();
    for (let i = ps.length - 1; i > 0; i--) {
      const j = Math.floor(this.rng() * (i + 1));
      [ps[i], ps[j]] = [ps[j], ps[i]];
    }
    ps.forEach((p, i) => (p.team = i < Math.ceil(ps.length / 2) ? 'red' : 'blue'));
    this.log(`[호스트] 팀 섞기: ${this.teamLine()}`);
    return true;
  }

  teamLine() {
    const ps = this.participants().sort((a, b) => a.slot - b.slot);
    return ['red', 'blue'].map((t) => `${TEAM_KO[t]} ${ps.filter((p) => p.team === t).map((p) => p.name).join(' ')}`).join(' / ');
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
      for (let z = 0; z < h && z < C.GRID_H; z++) this.grid[this.idx(x, y, z)] = CELL.TERRAIN;
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
    this.bblocks = new Map(); // 건축가 블록: 셀 키 -> { x, y, z, owner, kind: 'wall'|'third'|'pad'|'big', group, expiresAt, born }
    this.bigBombs = []; // 건축가 대폭발 대기: { owner, group, at, dir }
    this.holes = []; // 폭발 구멍 (테스트 옵션 BUILDER_BLAST_HOLE): { x, y, z, v, at }
    this.quakes = []; // 탱크 R 솟는 땅 (잠깐 솟았다 가라앉음): { cells: [[x,y,z]], at }
    this.bgroup = 0;
    this.bombCounter = 0;
    this.deaths = [];
    this.events = [];
    this.winnerId = null;
    this.winnerTeam = null;
    this.winnerIds = [];
    this.scores = new Map();
    this.teamScores = { red: 0, blue: 0 };
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
        jumpUntil: 0,
        airJumps: C.AIR_JUMPS,
        ghostUntil: 0,
        speedUntil: 0,
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
        emoteUntil: 0,
        emoteReadyAt: 0,
        master: false,
        zombie: false,
        nextPieceAt: 0,
        respawnAt: 0,
        shieldUntil: 0,
        skillReadyAt: 0,
        ult: 0,
        comboHits: 0,
        comboStartAt: 0,
        iframeUntil: 0,
        chargeUntil: 0,
        slamAt: 0,
        wallAt: 0,
        wallCells: null,
        loaded: true,
        zipUntil: 0,
        zipDir: null,
        grab: null,
        atk: null,
        atkQueued: false,
        atkLanded: false,
        castQueued: null,
        chainN: 0,
        chainUntil: 0,
        launchUntil: 0,
        airN: 0,
        lastBasic: null,
        streak: 0,
        streakUntil: 0,
        empowerUntil: 0,
        star2: null,
        touchPiece: 0,
      });
    }
    if (this.mode === 'master') {
      // 마스터는 자리 순서로 돌아감. 필드 위 하늘에 둠 (물리·판정에서 빠지고 화면엔 안 그림)
      const ps = this.participants().sort((a, b) => a.slot - b.slot);
      const m = ps[this.masterTurn % ps.length];
      this.masterTurn++;
      Object.assign(m, { master: true, x: C.GRID_W / 2, y: C.GRID_D / 2, z: C.GRID_H + 4 });
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
    if (this.teamMode) this.log(`  팀: ${this.teamLine()}`); // npm run stats 가 팀 승리를 사람별로 나눌 때 씀
    if (this.characters) this.log(`  캐릭터: ${ps.map((p) => `${p.name} ${C.CHAR_NAMES[p.char]}`).join(' / ')}`); // npm run stats 캐릭터별 승률
    // 모드 줄 (생존은 예전 로그와 같게 안 찍음). npm run stats 가 모드별로 셈
    if (this.mode === 'master') {
      this.roundEndsAt = this.time + C.MASTER_TIME_MS;
      this.log(`  모드: ${C.MODE_NAMES.master} (마스터 ${this.master().name}, ${fmtTime(C.MASTER_TIME_MS)} 버티기)`);
    } else if (this.mode === 'kills') {
      this.roundEndsAt = this.time + C.KILLS_TIME_MS;
      this.log(`  모드: ${C.MODE_NAMES.kills} (${fmtTime(C.KILLS_TIME_MS)} 또는 ${this.teamMode ? `팀 ${C.KILLS_TARGET_TEAM}` : C.KILLS_TARGET}킬)`);
    } else {
      this.roundEndsAt = 0;
    }
    this.checkRoundEnd(); // 카운트다운 중에 나가서 혼자 남았으면 바로 끝
  }

  // 팀전이면 winner 대신 winnerTeam: 그 팀 참가자 모두 승수 +1, 팀 승수 +1
  // winners: 승자가 여럿일 때 (블록 마스터에서 살아남은 생존자들, 킬 점수전 동점) 모두 승수 +1
  endRound(winner, winnerTeam = null, winners = null) {
    for (const p of this.players.values()) if (p.comboHits >= 2) this.endCombo(p); // 판이 끝날 때 이어지던 콤보도 로그에 (통계)
    this.phase = 'over';
    this.roundEndTime = this.time;
    const list = winners || (winner ? [winner] : []);
    this.winnerIds = list.map((p) => p.id);
    this.winnerId = list.length === 1 ? list[0].id : null;
    this.winnerTeam = winnerTeam;
    for (const w of list) w.wins++;
    if (winnerTeam) {
      this.teamWins[winnerTeam]++;
      for (const p of this.participants()) if (p.team === winnerTeam) p.wins++;
    }
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
    const winText = winnerTeam ? `${TEAM_KO[winnerTeam]}팀` : list.length ? list.map((p) => p.name).join(' ') : '무승부'; // 여럿이면 공백으로 (npm run stats)
    this.log(`===== ROUND ${this.roundNumber} 종료 | 길이 ${fmtTime(dur)} | 승자: ${winText} =====`);
    this.log(`  사망: ${deathStr}`);
    if (this.mode === 'master') {
      const m = this.master();
      this.log(`  결과: ${list.some((p) => p.master) ? `마스터 ${m.name} 승 (생존자 전멸)` : list.length ? `생존자 ${list.length}명 승` : '무승부'}`);
      // 마스터 편으로 넘어갔던 사람은 원래대로 (죽은 상태), 하늘에 떠 있던 다음 블록들은 치움
      for (const z of this.players.values()) if (z.zombie) Object.assign(z, { master: false, zombie: false, alive: false });
      this.pieces = this.pieces.filter((pc) => pc.phase !== 'control');
      this.refreshPieceCells();
      if (m) {
        // 판이 끝나면 마스터도 필드 가운데 꼭대기로 내려와 보통 사람처럼 (승리 연출·이모트)
        const cx = Math.floor(C.GRID_W / 2);
        const cy = Math.floor(C.GRID_D / 2);
        Object.assign(m, { master: false, x: cx + 0.5, y: cy + 0.5, z: this.columnTop(cx, cy), vz: 0 });
      }
    } else if (this.mode === 'kills') {
      this.log(`  점수: ${this.participants().sort((a, b) => a.slot - b.slot).map((p) => `${p.name} ${this.scores.get(p.id) || 0}`).join(' / ')}`);
      if (this.teamMode) this.log(`  팀 점수: 빨강 ${this.teamScores.red} : ${this.teamScores.blue} 파랑`);
    }
    this.log(`  승수: ${this.participants().sort((a, b) => a.slot - b.slot).map((p) => `${p.name} ${p.wins}`).join(' / ')}`);
    if (this.teamMode) this.log(`  팀 승수: 빨강 ${this.teamWins.red} : ${this.teamWins.blue} 파랑`);
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
    if (this.mode === 'master') return void this.checkMasterEnd();
    if (this.mode === 'kills') return void this.checkKillsEnd();
    const alive = [...this.players.values()].filter((p) => p.alive);
    if (this.teamMode) {
      // 살아 있는 사람이 한 팀뿐이면 그 팀 승리 (둘 다 없으면 무승부)
      const teams = new Set(alive.map((p) => p.team));
      if (teams.size <= 1) this.endRound(null, alive.length ? alive[0].team : null);
      return;
    }
    if (alive.length <= 1 && this.players.size >= 1) {
      this.endRound(alive[0] || null);
    }
  }

  // 블록 마스터: 생존자가 다 죽으면 마스터 승, 시간이 끝나면 살아 있는 생존자 모두 승. 마스터가 나가면 생존자 승
  checkMasterEnd() {
    const m = this.master();
    const survivors = this.participants().filter((p) => !p.master && p.alive);
    if (!m) this.endRound(null, null, survivors);
    else if (!survivors.length) this.endRound(m);
    else if (this.time >= this.roundEndsAt) {
      this.log(`  시간 끝 (${fmtTime(C.MASTER_TIME_MS)}) → 생존자 승`);
      this.endRound(null, null, survivors);
    }
  }

  // 킬 점수전: 시간이 끝나거나 목표 점수에 닿거나 상대가 다 나가면 끝. 점수가 가장 높은 사람(동점이면 모두)·팀 승
  checkKillsEnd() {
    const ps = this.participants();
    let reason = null;
    if (this.time >= this.roundEndsAt) reason = `시간 끝 (${fmtTime(C.KILLS_TIME_MS)})`;
    if (this.teamMode) {
      const { red, blue } = this.teamScores;
      if (Math.max(red, blue) >= C.KILLS_TARGET_TEAM) reason = `팀 ${C.KILLS_TARGET_TEAM}킬`;
      if (!ps.some((p) => p.team === 'red') || !ps.some((p) => p.team === 'blue')) reason = '한 팀이 다 나감';
      if (!reason) return;
      this.log(`  ${reason} → 판 끝`);
      this.endRound(null, red > blue ? 'red' : blue > red ? 'blue' : null);
      return;
    }
    const top = Math.max(-Infinity, ...ps.map((p) => this.scores.get(p.id) || 0));
    if (top >= C.KILLS_TARGET) reason = `${C.KILLS_TARGET}킬`;
    if (ps.length < C.MIN_PLAYERS) reason = '상대가 다 나감';
    if (!reason) return;
    this.log(`  ${reason} → 판 끝`);
    this.endRound(null, null, ps.filter((p) => (this.scores.get(p.id) || 0) === top));
  }

  // 킬 점수전 점수: 킬 낸 사람 +1, 킬 없이 죽으면(자멸) 죽은 사람 -1. 킬 낸 사람이 이미 나갔으면 점수 없음
  scoreDeath(p, credit) {
    const by = credit ? this.players.get(credit.by) : null;
    p.respawnAt = this.time + C.KILLS_RESPAWN_MS;
    if (credit && !by) return;
    const who = by || p;
    const d = by ? 1 : -1;
    this.scores.set(who.id, (this.scores.get(who.id) || 0) + d);
    if (this.teamMode) this.teamScores[who.team] += d;
    this.log(`  [점수] ${who.name} ${d > 0 ? '+1' : '자멸 -1'} → ${this.scores.get(who.id)}${this.teamMode ? ` (팀 빨강 ${this.teamScores.red} : ${this.teamScores.blue} 파랑)` : ''}`);
  }

  // 킬 점수전 부활 자리: 가장 높은 기둥들(가장 높은 것 -1칸까지) 중 살아 있는 상대에게서 가장 먼 곳. 떨어지는 블록 밑은 피함
  respawnSpot(p) {
    const busy = new Set();
    for (const pc of this.pieces) for (const [dx, dy] of pc.cells) busy.add((pc.px + dx) * 100 + (pc.py + dy));
    const others = [...this.players.values()].filter((o) => o !== p && this.onField(o));
    const cols = [];
    for (let x = 0; x < C.GRID_W; x++) {
      for (let y = 0; y < C.GRID_D; y++) {
        const top = this.columnTop(x, y);
        if (top <= C.GRID_H - 3 && !busy.has(x * 100 + y)) cols.push({ x, y, top });
      }
    }
    if (!cols.length) return { x: C.GRID_W / 2, y: C.GRID_D / 2, z: this.columnTop(Math.floor(C.GRID_W / 2), Math.floor(C.GRID_D / 2)) };
    const maxTop = Math.max(...cols.map((c) => c.top));
    let best = null;
    let bestD = -1;
    for (const c of cols) {
      if (c.top < maxTop - 1) continue;
      const d = Math.min(Infinity, ...others.map((o) => Math.hypot(o.x - (c.x + 0.5), o.y - (c.y + 0.5))));
      if (d > bestD) {
        bestD = d;
        best = c;
      }
    }
    return { x: best.x + 0.5, y: best.y + 0.5, z: best.top };
  }

  respawn(p) {
    const s = this.respawnSpot(p);
    Object.assign(p, {
      ...s,
      vz: 0,
      kbx: 0,
      kby: 0,
      grounded: true,
      alive: true,
      stunUntil: 0,
      freezeUntil: 0,
      jumpUntil: 0,
      airJumps: C.AIR_JUMPS,
      ghostUntil: 0,
      speedUntil: 0,
      bombs: 0,
      bricks: 0,
      ammo: 0,
      damage: 0,
      comboHits: 0,
      comboStartAt: 0,
      iframeUntil: 0,
      chargeUntil: 0,
      slamAt: 0,
      wallAt: 0,
      wallCells: null,
      loaded: true,
      zipUntil: 0,
      zipDir: null,
      grab: null,
      atk: null,
      atkQueued: false,
      atkLanded: false,
      castQueued: null,
      chainN: 0,
      chainUntil: 0,
      launchUntil: 0,
      airN: 0,
      lastBasic: null,
      streak: 0,
      streakUntil: 0,
      empowerUntil: 0,
      star2: null,
      touchPiece: 0,
      hasControl: false,
      deathCause: null,
      lastHit: null,
      emoteUntil: 0,
      respawnAt: 0,
      shieldUntil: this.time + C.KILLS_SHIELD_MS,
    });
    this.emit({ type: 'respawn', who: p.id });
    this.log(`  [부활] ${p.name} → (${Math.floor(s.x)},${Math.floor(s.y)}) z=${s.z}`);
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
    if (credit && (credit.by === p.id || !credit.name || this.sameTeam(this.players.get(credit.by), p))) credit = null; // 팀 블록에 깔려도 킬 아님
    this.deaths.push({ name: p.name, cause, t, killer: credit ? credit.name : null, weapon: credit ? credit.kind : null });
    this.emit({ type: 'death', who: p.id, cause, by: credit ? credit.by : null, weapon: credit ? credit.kind : null, byName: credit ? credit.name : null });
    const killText = credit ? `, 킬 ${credit.name} ${WEAPON_LOG[credit.kind]}` : ', 킬 없음'; // "킬 없음" 을 적어야 킬 기록이 없던 옛 로그와 구분됨
    this.log(`  [사망] ${p.name} ${causeKo(cause)} @ ${fmtTime(t)} (위치 ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}, 피해 ${p.damage}%${killText})`);
    if (this.mode === 'kills' && this.phase === 'playing') this.scoreDeath(p, credit);
    if (this.mode === 'master' && this.phase === 'playing' && !p.master && this.master()) this.joinMasterSide(p);
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
    // 이모트는 판이 끝난 뒤에도 됨 (GG). 하는 동안 못 움직이고, 맞거나 공격하면 끊김
    if (action.name === 'emote') return void this.startEmote(p, action.n);
    if (!p || this.phase !== 'playing' || !p.alive) return;
    if (p.master && !['pieceMove', 'rotate', 'drop'].includes(action.name)) return; // 마스터는 블록 조종만
    const stunned = this.time < p.stunUntil;
    const controlling = this.isControlling(p);
    if (['dash', 'push', 'fire', 'skill', 'ult'].includes(action.name)) p.emoteUntil = 0;
    switch (action.name) {
      case 'jump':
        // 점프 키를 누른 순간 (연속 입력의 jump 는 '누르고 있음'이라 빨리 떼었다 누르면 서버가 놓침).
        // 땅에서는 연속 입력이 뛰고, 공중이면 다음 틱에 2단 점프
        // 땅에서 누른 것도 JUMP_BUFFER_MS 동안 기억 (멈칫·짧게 누름에 안 씹히게: 닌자 올려 차기 → 점프 → 공중 평타)
        if (!p.grounded) p.airJumpQueued = true;
        else p.jumpQueuedUntil = this.time + C.JUMP_BUFFER_MS;
        return;
      case 'dash':
        if (stunned || controlling || this.time < p.dashReadyAt) return; // 조종 중 대시 불가
        this.dash(p);
        return;
      case 'push':
        if (stunned || controlling) return; // 조종 중 공격 불가
        if (p.char) return void this.basicPress(p); // 캐릭터 평타
        if (this.time < p.pushReadyAt) return;
        this.push(p);
        return;
      case 'fire': // 우클릭: 손에 든 아이템을 씀
        if (stunned || controlling) return;
        if (p.bricks > 0) this.throwBrick(p);
        else if (p.ammo > 0) this.fire(p);
        else if (p.bombs > 0) this.throwBomb(p);
        return;
      case 'skill': // F: 캐릭터 스킬 (쿨타임)
        if (stunned || controlling || !p.char || this.time < p.skillReadyAt) return;
        this.cast(p, 'skill');
        return;
      case 'ult': // R: 필살기 (게이지가 다 차면)
        if (stunned || controlling || !p.char || p.ult < C.ULT_MAX) return;
        this.cast(p, 'ult');
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
    p.atkLanded = false;
    const kind = 'push';
    const speed = C.PUSH_KB_SPEED;
    const up = C.PUSH_KB_UP;
    const stun = C.STUN_MS;
    this.emit({ type: 'swing', who: p.id, kind });
    const falling = !p.grounded && p.vz < 0; // 치명타: 떨어지면서 때림 (높이 조건은 상대마다)
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.PUSH_HALF_ANGLE_DEG * Math.PI) / 180);
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > C.PUSH_RANGE) continue;
      if (Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (dist > EPS && (dx * fx + dy * fy) / dist < cosHalf) continue;
      const crit = falling && p.z - t.z >= C.CRIT_MIN_HEIGHT;
      const gain = crit ? Math.round(C.DAMAGE_GAIN[kind] * C.CRIT_DAMAGE_MULT) : C.DAMAGE_GAIN[kind];
      const hit = this.applyKnockback(t, fx, fy, crit ? speed * C.CRIT_KB_MULT : speed, up, stun, gain, { by: p.id, kind });
      const stop = crit ? C.HITSTOP_MS * C.CRIT_HITSTOP_MULT : C.HITSTOP_MS;
      if (hit) {
        p.freezeUntil = this.time + stop; // 때린 쪽도 같이 멈칫
        t.freezeUntil = this.time + stop;
      }
      if (hit && !this.sameTeam(p, t)) p.atkLanded = true; // 맞혔으면 F·R 로 쿨 캔슬 (그림자 일격 → 순간 베기)
      this.emit({ type: 'hit', kind, by: p.id, target: t.id, ok: hit, crit: hit && crit });
      this.log(`  [밀치기] ${p.name} → ${t.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
    }
  }

  // F·R 캔슬 (2026-10-25 재혁 승인): 평타가 맞은 뒤 후딜이면 후딜을 끊고 바로. 빗나간 뒤 후딜이면 후딜이 끝나고.
  // 평타 준비 중이면 기억했다가 판정 결과에 따라 (준비 중인 평타는 안 취소). 핑 때문에 미리 눌러 두는 것을 서버가 판정
  cast(p, kind) {
    if (p.atk || (this.time < p.pushReadyAt && !p.atkLanded)) {
      p.castQueued = kind;
      p.atkQueued = false; // 나중에 누른 스킬이 먼저 누른 평타 선입력보다 우선
      return;
    }
    if (this.time < p.pushReadyAt) p.pushReadyAt = this.time; // 맞힌 평타의 후딜 캔슬
    if (kind === 'skill') this.useSkill(p);
    else this.useUlt(p);
  }

  // 기억한 F·R 을 지금 쓸 수 있으면 씀 (맞힌 평타 판정 직후 또는 후딜 끝)
  castQueuedNow(p) {
    const kind = p.castQueued;
    p.castQueued = null;
    if (this.time < p.stunUntil || this.isControlling(p)) return;
    if (kind === 'skill' ? this.time < p.skillReadyAt : p.ult < C.ULT_MAX) return;
    this.cast(p, kind);
  }

  // ---------- 캐릭터 평타 (BASIC_ATTACKS) ----------
  // 준비·후딜 중에 누르면 기다렸다 나감 (updateCombat)
  basicPress(p) {
    if (p.atk || this.time < p.pushReadyAt) {
      p.atkQueued = true;
      return;
    }
    this.basicStart(p);
  }

  // 몇 번째 타인지 정하고 준비 시작. 지상·공중 각각 이어 치기 창 안이면 다음 타, 아니면 1타 (공중은 air 배열 순서)
  basicStart(p) {
    const set = C.BASIC_ATTACKS[p.char];
    const air = !p.grounded;
    const live = this.time < p.chainUntil;
    const n = air ? (p.airN > 0 && live && p.airN < set.air.length ? p.airN + 1 : 1) : p.chainN > 0 && live && p.chainN < set.chain.length ? p.chainN + 1 : 1;
    let def = air ? set.air[n - 1] : set.chain[n - 1];
    if (def.loaded && p.loaded) def = def.loaded; // 갈고리 3타: 장전돼 있으면 탕
    // 닌자 R 강화: 지상 1~3타와 공중 평타가 표창 2연발 (4타 올려 차기는 그대로)
    if (p.char === 'ninja' && this.time < p.empowerUntil && (air || n <= 3)) def = { ...def, name: '표창', windup: C.NINJA_STAR.windup, step: 0, star: true };
    // 연타를 이어 가는 중인 타 (지상 2타~, 공중 2타~, 띄우는 마지막 지상 타 뒤 공중 1타): 시간 마무리가 되지 않음
    const chained = air ? (p.airN > 0 && live) || this.time < p.launchUntil : n > 1;
    p.atk = { n, def, air, chained, at: this.time + def.windup };
    p.atkLanded = false;
    p.pushReadyAt = this.time + def.windup + def.rec;
    this.emit({ type: 'attack', who: p.id, char: p.char, n, air, name: def.name, windup: def.windup, finish: !!def.finish, star: !!def.star });
    if (def.windup <= 0) this.basicHit(p);
  }

  // 판정: 앞으로 step 만큼 나가며 부채꼴 안을 침. 중간 타는 고정 넉백, 마무리 타·공중 평타는 % 배율
  basicHit(p) {
    const { n, def, air, chained } = p.atk;
    p.atk = null;
    const set = C.BASIC_ATTACKS[p.char];
    if (def.star) return this.starVolley(p, n, air, def, chained);
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    if (def.step) {
      // 앞으로 나가되 앞 상대를 지나치지 않게 (BASIC_STEP_GAP 앞에서 멈춤)
      let step = def.step;
      for (const t of this.players.values()) {
        if (!this.foe(p, t) || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
        const along = (t.x - p.x) * fx + (t.y - p.y) * fy;
        const side = Math.abs((t.x - p.x) * fy - (t.y - p.y) * fx);
        if (along > 0 && side < C.BASIC_STEP_GAP) step = Math.min(step, Math.max(0, along - C.BASIC_STEP_GAP));
      }
      this.moveAxis(p, 'x', fx * step);
      this.moveAxis(p, 'y', fy * step);
    }
    this.emit({ type: 'swing', who: p.id, kind: 'push', char: p.char, n });
    if (def.shot) {
      p.loaded = false; // 탕: 쏘면 빈 총 (맞든 안 맞든)
      this.emit({ type: 'bang', who: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yaw });
    }
    const range = def.range || C.PUSH_RANGE;
    const cosHalf = Math.cos(((def.angle ?? C.PUSH_HALF_ANGLE_DEG) * Math.PI) / 180);
    const falling = !p.grounded && p.vz < 0;
    const finish = !!def.finish;
    const single = air && set.air.length === 1; // 공중 한 타짜리: 예전처럼 % 배율 넉백·보통 멈칫
    const label = basicLabel(set, n, air, def);
    let landed = null; // 처음 맞힌 상대 (같은 팀 빼고)
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > range || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (dist > C.BASIC_STEP_GAP && (dx * fx + dy * fy) / dist < cosHalf) continue; // 몸이 붙어 있으면 방향 상관없이
      const crit = air && falling && p.z - t.z >= C.CRIT_MIN_HEIGHT; // 치명타는 공중 평타만
      const gain = crit ? Math.round(def.dmg * C.CRIT_DAMAGE_MULT) : def.dmg;
      const speed = crit ? def.kb * C.CRIT_KB_MULT : def.kb;
      const hit = this.applyKnockback(t, fx, fy, speed, def.up, def.stun, gain, { by: p.id, kind: 'push' }, finish, { fixed: !single && !finish, finish, chained });
      if (hit) {
        const stop =
          (finish ? C.BASIC_FINISH_HITSTOP_MS : single ? C.HITSTOP_MS : C.BASIC_HITSTOP_MS) *
          (crit ? C.CRIT_HITSTOP_MULT : 1) *
          (t.counterAt === this.time ? C.COUNTER_HITSTOP_MULT : 1);
        p.freezeUntil = this.time + stop;
        t.freezeUntil = this.time + stop;
        if (!landed && !this.sameTeam(p, t)) landed = t;
      }
      this.emit({ type: 'hit', kind: 'push', by: p.id, target: t.id, ok: hit, crit: hit && crit, n, air, finish, streak: hit ? p.streak : 0 });
      this.log(`  [평타] ${p.name} → ${t.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${t.name} ${t.damage}%)` : '무적이라 무시'} ${label}`);
    }
    this.basicChain(p, n, air, !!landed, def);
    if (p.char === 'builder' && this.hammerBlocks(p, range, cosHalf)) p.atkLanded = true; // 망치로 내 블록을 치면 폭발 (맞힌 것으로 침: F·R 캔슬)
    if (def.raise) this.basicRaise(p, landed);
  }

  // 평타 한 타가 끝난 뒤: 이어 치기 번호·창, 맞혔는지, 닌자 F 쿨 감소
  // 허공 이어 치기 (2026-10-25 재혁): 빗나가도 다음 타로 (후딜은 다 받음). BASIC_CHAIN_WINDOW_MS 안에 안 치면 1타로.
  // 타 번호는 때린 쪽에 남음 → 상대를 바꿔도 이어짐 (닌자 갈아타기)
  basicChain(p, n, air, landed, def) {
    const set = C.BASIC_ATTACKS[p.char];
    // 띄우는 마지막 지상 타(마무리 아님) 뒤에는 후딜 + 이어 치기 창 동안 공중 1타가 연타로 이어짐
    if (!air && n === set.chain.length && !def.finish) p.launchUntil = this.time + def.rec + C.BASIC_CHAIN_WINDOW_MS;
    if (air) {
      p.airN = n < set.air.length ? n : 0;
      if (p.airN > 0 || p.chainN > 0) p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS; // 지상 타 번호도 그대로
    } else if (n < set.chain.length) {
      p.chainN = n;
      p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS;
    } else p.chainN = 0;
    p.atkLanded = landed;
    p.lastBasic = { n, air, at: this.time };
    if (landed) this.ninjaCdCut(p);
  }

  // 닌자 적중 보상: 평타가 맞을 때마다 F 쿨 NINJA_HIT_CD_CUT_MS 줄어듦
  ninjaCdCut(p) {
    if (p.char === 'ninja') p.skillReadyAt = Math.max(this.time, p.skillReadyAt - C.NINJA_HIT_CD_CUT_MS);
  }

  // 닌자 R 강화 표창 2연발: 첫 발은 지금, 둘째 발은 NINJA_STAR.gap 뒤 (updateCombat). 즉시 판정 (날아가는 물체 아님)
  starVolley(p, n, air, def, chained) {
    const landed = this.starShot(p, n, air, def, 1, chained);
    this.basicChain(p, n, air, landed, def);
    p.star2 = { at: this.time + C.NINJA_STAR.gap, n, air, def, chained };
  }

  // 표창 한 발: 보는 방향 좁은 각 NINJA_STAR.range 안 가장 가까운 상대 하나. 마무리 타 자리면 둘째 발이 그 타의 마무리
  starShot(p, n, air, def, shot, chained = false) {
    const S = C.NINJA_STAR;
    const set = C.BASIC_ATTACKS[p.char];
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((S.angle * Math.PI) / 180);
    let best = null;
    let bd = Infinity;
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > S.range || Math.abs(t.z - p.z) > S.range || dist < EPS || (dx * fx + dy * fy) / dist < cosHalf) continue;
      if (dist < bd) {
        bd = dist;
        best = t;
      }
    }
    const fin = shot === 2 && !!def.finish;
    const from = { x: p.x, y: p.y, z: p.z + C.EYE_HEIGHT - 0.3 };
    this.emit({ type: 'star', who: p.id, shot, target: best ? best.id : null, from, to: best ? { x: best.x, y: best.y, z: best.z + 0.8 } : { x: p.x + fx * S.range, y: p.y + fy * S.range, z: from.z } });
    if (!best) return false;
    const falling = !p.grounded && p.vz < 0;
    const crit = air && falling && p.z - best.z >= C.CRIT_MIN_HEIGHT;
    const dmg = fin ? def.dmg : S.dmg;
    const gain = crit ? Math.round(dmg * C.CRIT_DAMAGE_MULT) : dmg;
    const hit = this.applyKnockback(best, fx, fy, (fin ? def.kb : S.kb) * (crit ? C.CRIT_KB_MULT : 1), fin ? def.up : S.up, fin ? def.stun : S.stun, gain, { by: p.id, kind: 'push' }, fin, { fixed: !fin, finish: fin, chained: chained || shot === 2 });
    if (hit) {
      const stop = (fin ? C.BASIC_FINISH_HITSTOP_MS : C.BASIC_HITSTOP_MS) * (crit ? C.CRIT_HITSTOP_MULT : 1) * (best.counterAt === this.time ? C.COUNTER_HITSTOP_MULT : 1);
      best.freezeUntil = this.time + stop;
    }
    const ok = hit && !this.sameTeam(p, best);
    this.emit({ type: 'hit', kind: 'push', by: p.id, target: best.id, ok: hit, crit: hit && crit, n, air, finish: fin, star: true, streak: hit ? p.streak : 0 });
    this.log(`  [평타] ${p.name} → ${best.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${best.name} ${best.damage}%)` : '무적이라 무시'} ${basicLabel(set, n, air, def)}`);
    return ok;
  }

  // 건축가 내려찍기: 맞힌 사람 발밑 (빗나가면 앞 1.5칸) 기둥 꼭대기에 건축가 블록 1칸 ('third', 최대 BUILDER_THIRD_MAX 개).
  // 내 몸과 겹치는 칸이면 앞으로 0.5칸씩 (2026-10-25 버그: 몸이 옆 칸에 걸쳐 있으면 내 밑에서 솟아 나를 띄웠음)
  basicRaise(p, t) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    let bx = t ? t.x : p.x + fx * 1.5;
    let by = t ? t.y : p.y + fy * 1.5;
    const mine = (x, y) => overlapsCell(p, Math.floor(x), Math.floor(y), this.columnTop(Math.floor(x), Math.floor(y))) || (Math.floor(x) === Math.floor(p.x) && Math.floor(y) === Math.floor(p.y));
    for (let i = 0; i < 3 && inXY(Math.floor(bx), Math.floor(by)) && mine(bx, by); i++) {
      bx += fx * 0.5;
      by += fy * 0.5;
    }
    const cx = Math.floor(bx);
    const cy = Math.floor(by);
    if (!inXY(cx, cy) || mine(bx, by)) return;
    const z = this.columnTop(cx, cy);
    const g = ++this.bgroup;
    if (!this.placeBBlock(p, cx, cy, z, 'third', g)) return;
    // 3타 블록은 동시에 BUILDER_THIRD_MAX 개까지: 넘으면 제일 오래된 것부터 사라짐
    const thirds = [...this.bblocks.values()].filter((b) => b.owner === p.id && b.kind === 'third').sort((a, b) => a.born - b.born);
    for (const b of thirds.slice(0, Math.max(0, thirds.length - C.BUILDER_THIRD_MAX))) this.removeBBlock(b, 'old');
    this.gridChanged();
    for (const o of this.players.values()) if (this.onField(o) && overlapsCell(o, cx, cy, z)) this.ejectFromBlocks(o);
    this.emit({ type: 'wallRise', who: p.id, cells: [[cx, cy, z]] });
    this.emit({ type: 'bblock', who: p.id, kind: 'third', group: g, cells: [[cx, cy, z]], ms: C.BUILDER_BLOCK_MS });
    this.log(`  [평타] ${p.name} 블록 솟음 (${cx},${cy},${z})`);
    this.clearLayers();
  }

  // ---------- 캐릭터 스킬·필살기 ----------
  useSkill(p) {
    if (p.slamAt || p.wallAt || p.grab || this.time < p.chargeUntil) return false; // 다른 기술 발동 중
    p.skillReadyAt = this.time + C.SKILL_CD_MS[p.char]; // 먼저 걸어 둠 (그림자 일격이 순간 베기 쿨을 초기화하는 것과 순서가 안 꼬이게)
    const ok =
      p.char === 'tank' ? this.tankCharge(p) : p.char === 'ninja' ? this.ninjaBlink(p) : p.char === 'builder' ? this.builderWall(p) : this.hookPull(p);
    if (!ok) {
      p.skillReadyAt = this.time; // 못 쓰는 상황(벽 세울 자리 없음 등)이면 쿨타임 안 돎 — 갈고리는 빗나가도 돎 (hookPull 이 정함)
      return false;
    }
    if (p.chainN > 0 && this.time < p.chainUntil) p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS; // 평타 → 스킬 → 평타
    this.emit({ type: 'skill', who: p.id, char: p.char, x: p.x, y: p.y, z: p.z });
    return true;
  }

  useUlt(p) {
    if (p.slamAt || p.wallAt || p.grab || this.time < p.chargeUntil) return false;
    if (p.char === 'tank') this.tankSlamStart(p);
    else if (p.char === 'ninja') this.ninjaEmpower(p); else if (p.char === 'builder') {
      if (!this.builderBigBomb(p)) return false; // 솟을 자리가 없으면 게이지 그대로
    } else if (!this.hookGrab(p)) return false; // 갈고리: 닿는 블록이 없으면 게이지 그대로
    p.ult = 0;
    this.emit({ type: 'ult', who: p.id, char: p.char, x: p.x, y: p.y, z: p.z });
    return true;
  }

  // 남에게 맞힐 수 있는 상대인가 (필드 위·다른 팀·나 아님)
  foe(p, t) {
    return t !== p && this.onField(t) && !this.sameTeam(p, t);
  }

  // ---- 탱크 ----
  // 돌진: TANK_CHARGE_MS 동안 보는 방향으로 빠르게. 처음 부딪힌 상대를 치고 멈춤 (updateCombat)
  tankCharge(p) {
    p.chargeUntil = this.time + C.TANK_CHARGE_MS;
    p.chargeDir = { x: Math.cos(p.yaw), y: Math.sin(p.yaw) };
    this.emit({ type: 'charge', who: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yaw });
    this.log(`  [스킬] ${p.name} 돌진`);
    return true;
  }

  chargeHit(p) {
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || Math.hypot(t.x - p.x, t.y - p.y) > C.TANK_CHARGE_HIT_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      p.chargeUntil = 0;
      p.kbx = 0;
      p.kby = 0;
      const hit = this.applyKnockback(t, p.chargeDir.x, p.chargeDir.y, C.TANK_CHARGE_KB_SPEED, C.TANK_CHARGE_KB_UP, C.TANK_CHARGE_STUN_MS, C.TANK_CHARGE_DAMAGE, { by: p.id, kind: 'charge' });
      this.emit({ type: 'hit', kind: 'charge', by: p.id, target: t.id, ok: hit });
      this.log(`  [돌진] ${p.name} → ${t.name} ${hit ? `(${t.name} ${t.damage}%)` : '무적이라 무시'}`);
      return;
    }
  }

  // 내려찍기: 떠올랐다가 TANK_SLAM_WINDUP_MS 뒤 쾅 (바닥에 범위 예고). 주변을 위로 띄움
  tankSlamStart(p) {
    p.slamAt = this.time + C.TANK_SLAM_WINDUP_MS;
    p.vz = C.TANK_SLAM_JUMP;
    p.grounded = false;
    this.emit({ type: 'slamWarn', who: p.id, x: p.x, y: p.y, z: p.z, r: C.TANK_SLAM_RANGE, ms: C.TANK_SLAM_WINDUP_MS });
    this.log(`  [필살] ${p.name} 내려찍기 준비`);
  }

  tankSlam(p) {
    p.slamAt = 0;
    p.vz = Math.min(p.vz, -C.TANK_SLAM_JUMP); // 쾅 내려옴
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      if (Math.hypot(dx, dy) > C.TANK_SLAM_RANGE || Math.abs(t.z - p.z) > 2.5) continue;
      const a = this.rng() * Math.PI * 2; // 겹쳐 서 있으면 방향이 없어서 무작위
      const len = Math.hypot(dx, dy);
      const hit = this.applyKnockback(t, len > 0.05 ? dx : Math.cos(a), len > 0.05 ? dy : Math.sin(a), C.TANK_SLAM_KB_SPEED, C.TANK_SLAM_KB_UP, C.TANK_SLAM_STUN_MS, C.TANK_SLAM_DAMAGE, { by: p.id, kind: 'slam' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'slam', by: p.id, target: t.id, ok: hit });
    }
    this.emit({ type: 'slam', who: p.id, x: p.x, y: p.y, z: p.z, r: C.TANK_SLAM_RANGE });
    const lifted = this.tankRing(p);
    this.log(`  [필살] ${p.name} 내려찍기 (${n}명${lifted ? `, 솟는 땅 ${lifted}명` : ''})`);
  }

  // R 바깥 고리: 충격파 바깥 TANK_RING_WIDTH 칸 고리의 기둥 꼭대기에 블록 1층이 솟아 위 사람을 띄움 → TANK_RING_MS 뒤 가라앉음.
  // 블록이 아래에서 솟으니 압사 없음, 층 클리어로도 안 셈. 띄운 사람 수를 돌려줌
  tankRing(p) {
    const r0 = C.TANK_SLAM_RANGE;
    const r1 = r0 + C.TANK_RING_WIDTH;
    const cells = [];
    for (let x = Math.floor(p.x - r1); x <= Math.floor(p.x + r1); x++) {
      for (let y = Math.floor(p.y - r1); y <= Math.floor(p.y + r1); y++) {
        const d = Math.hypot(x + 0.5 - p.x, y + 0.5 - p.y);
        if (d <= r0 || d > r1 || !inXY(x, y)) continue;
        const z = this.columnTop(x, y);
        if (z >= C.GRID_H || Math.abs(z - p.z) > 2.5 || this.pieceCells.has(cellKey(x, y, z))) continue;
        this.grid[this.idx(x, y, z)] = CELL.BUILD;
        cells.push([x, y, z]);
      }
    }
    if (!cells.length) return 0;
    this.gridChanged();
    this.quakes.push({ cells, at: this.time + C.TANK_RING_MS });
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.onField(t) || !cells.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t)) continue;
      const hit = this.applyKnockback(t, t.x - p.x, t.y - p.y, 0, C.TANK_RING_UP, C.TANK_RING_STUN_MS, 0, { by: p.id, kind: 'slam' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'quake', by: p.id, target: t.id, ok: hit });
    }
    this.emit({ type: 'quakeRise', who: p.id, cells, ms: C.TANK_RING_MS });
    return n;
  }

  // 솟은 땅이 가라앉음 (그 사이 다른 블록이 덮어쓴 칸은 그대로)
  updateQuakes() {
    for (const q of [...this.quakes]) {
      if (this.time < q.at) continue;
      this.quakes = this.quakes.filter((x) => x !== q);
      const gone = q.cells.filter(([x, y, z]) => this.grid[this.idx(x, y, z)] === CELL.BUILD && !this.bblocks.has(cellKey(x, y, z)));
      for (const [x, y, z] of gone) this.grid[this.idx(x, y, z)] = 0;
      if (gone.length) this.gridChanged();
      this.emit({ type: 'quakeFall', cells: gone });
    }
  }

  // ---- 닌자 ----
  // 순간 베기: 보는 방향으로 NINJA_BLINK_DIST 만큼 (블록 앞까지, 상대가 있으면 그 바로 뒤까지) 순간이동하며 지나간 길의 상대를 벰 (한 사람 한 번).
  // 공중에서도 됨 (복귀). 블록에 막히면 벽 차기: 위로 튀어 오름 + 작은 충격파 (벽 통과 없음)
  ninjaBlink(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const from = { x: p.x, y: p.y };
    let best = 0;
    let blocked = false;
    for (let d = 0.1; d <= C.NINJA_BLINK_DIST + 1e-9; d += 0.1) {
      const b = this.aabb({ x: p.x + fx * d, y: p.y + fy * d, z: p.z + 0.05 }); // 발이 바닥에 살짝 안 걸리게
      if (this.overlappingSolid(b).length) {
        blocked = true;
        break;
      }
      best = d;
    }
    if (best < 0.3 && !blocked) return false;
    // 길 위의 상대: 지나갈 선분에서 NINJA_SLASH_WIDTH 안. 처음 만나는 상대 바로 뒤(NINJA_BLINK_BEHIND)에서 멈춤 → 바로 평타로 이어짐
    const onPath = (t, len) => {
      const along = (t.x - from.x) * fx + (t.y - from.y) * fy;
      return along >= 0 && along <= len && Math.hypot(from.x + fx * along - t.x, from.y + fy * along - t.y) <= C.NINJA_SLASH_WIDTH ? along : null;
    };
    const wall = best;
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      const along = onPath(t, best);
      if (along !== null) best = Math.min(best, along + C.NINJA_BLINK_BEHIND);
    }
    p.x += fx * best;
    p.y += fy * best;
    this.emit({ type: 'blink', who: p.id, from, to: { x: p.x, y: p.y, z: p.z } });
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (onPath(t, best) === null) continue;
      const hit = this.applyKnockback(t, fx, fy, C.NINJA_SLASH_KB_SPEED, C.NINJA_SLASH_KB_UP, C.NINJA_SLASH_STUN_MS, C.NINJA_SLASH_DAMAGE, { by: p.id, kind: 'slash' });
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'slash', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
    }
    const kicked = blocked && best >= wall - 1e-9; // 상대 뒤에서 먼저 멈췄으면 벽 차기 아님
    this.log(`  [스킬] ${p.name} 순간 베기 ${best.toFixed(1)}칸${n ? ` (${n}명)` : ''}${kicked ? ' 벽 차기' : ''}`);
    if (kicked) this.ninjaWallKick(p, fx, fy);
    return true;
  }

  // 벽 차기: 블록을 차고 위로 + 둘레 상대를 바깥으로 (피해 작게, 넉백만)
  ninjaWallKick(p, fx, fy) {
    p.vz = C.NINJA_WALLKICK_UP;
    p.grounded = false;
    p.kbx = 0;
    p.kby = 0;
    const hits = [];
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.NINJA_WALLKICK_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : -fx, d > 0.05 ? dy : -fy, C.NINJA_WALLKICK_KB_SPEED, C.NINJA_WALLKICK_KB_UP, C.NINJA_WALLKICK_STUN_MS, C.NINJA_WALLKICK_DAMAGE, { by: p.id, kind: 'wallkick' });
      this.emit({ type: 'hit', kind: 'wallkick', by: p.id, target: t.id, ok: hit });
      if (hit) hits.push(t.name);
    }
    this.emit({ type: 'wallKick', who: p.id, x: p.x, y: p.y, z: p.z, dir: { x: fx, y: fy } });
    this.log(`  [스킬] ${p.name} 벽 차기${hits.length ? ` → ${hits.join(', ')}` : ''}`);
  }

  // R 강화: NINJA_EMPOWER_MS 동안 지상 1~3타·공중 평타가 표창 2연발
  ninjaEmpower(p) {
    p.empowerUntil = this.time + C.NINJA_EMPOWER_MS;
    this.emit({ type: 'empower', who: p.id, ms: C.NINJA_EMPOWER_MS });
    this.log(`  [필살] ${p.name} 강화 (${C.NINJA_EMPOWER_MS / 1000}초 표창)`);
  }

  // 패시브: 공중에서 떨어지는 블록에 닿으면 (밟거나 옆면) 공중 점프 회복. 한 블록에 한 번
  ninjaTouch(p) {
    if (p.grounded && !this.standingOnPiece(p)) {
      p.touchPiece = 0;
      return;
    }
    const box = this.aabb(p);
    const pad = 0.06;
    for (const pc of this.pieces) {
      if (pc.phase !== 'falling' || pc.id === p.touchPiece) continue;
      const touch = this.pieceWorldCells(pc).some(([x, y, z]) => x < box.x1 + pad && x + 1 > box.x0 - pad && y < box.y1 + pad && y + 1 > box.y0 - pad && z < box.z1 + pad && z + 1 > box.z0 - pad);
      if (!touch) continue;
      p.touchPiece = pc.id;
      p.airJumps = C.AIR_JUMPS;
      this.emit({ type: 'ninjaTouch', who: p.id, piece: pc.id });
      return;
    }
  }

  standingOnPiece(p) {
    const z = Math.round(p.z) - 1;
    for (let x = Math.floor(p.x - C.PLAYER_HALF); x <= Math.floor(p.x + C.PLAYER_HALF); x++) for (let y = Math.floor(p.y - C.PLAYER_HALF); y <= Math.floor(p.y + C.PLAYER_HALF); y++) if (this.pieceCells.has(cellKey(x, y, z))) return true;
    return false;
  }

  // ---- 건축가 (2026-10-25 재혁 확정, docs/characters.md 3.1) ----
  // 건축가 블록: 격자에는 CELL.BUILD 로 두고 주인·종류·묶음·수명은 this.bblocks 에. 건축가 망치로 치면 폭발 (치는 방향 앞만, 자신 제외),
  // 같은 F 벽 묶음끼리만 연쇄. BUILDER_BLOCK_MS 뒤 사라짐. 패시브: 내 블록이 터지면 1칸당 게이지 (대폭발 블록 제외)

  // 지상 F: 솟는 벽 — 바로 앞(네 방향으로 맞춤) 줄에 가로 BUILDER_WALL_WIDTH × BUILDER_WALL_HEIGHT. 바닥에 예고 → BUILDER_WALL_WARN_MS 뒤 솟음
  // 공중 F: 발판 — 발밑에 블록 1칸 + 위로 부스트 (쿨 같이 씀)
  builderWall(p) {
    if (!p.grounded) return this.builderPad(p);
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const along = Math.abs(fx) >= Math.abs(fy) ? [Math.sign(fx), 0] : [0, Math.sign(fy)];
    const side = [-along[1], along[0]];
    const cx = Math.floor(p.x) + along[0];
    const cy = Math.floor(p.y) + along[1];
    const z0 = Math.max(0, Math.round(p.z));
    const half = Math.floor(C.BUILDER_WALL_WIDTH / 2);
    const cells = [];
    for (let i = -half; i <= half; i++) {
      const x = cx + side[0] * i;
      const y = cy + side[1] * i;
      if (!inXY(x, y) || this.grid[this.idx(x, y, z0)]) continue;
      for (let h = 0; h < C.BUILDER_WALL_HEIGHT; h++) if (z0 + h < C.GRID_H) cells.push([x, y, z0 + h]);
    }
    if (!cells.length) return false;
    p.wallAt = this.time + C.BUILDER_WALL_WARN_MS;
    p.wallCells = cells;
    this.emit({ type: 'wallWarn', who: p.id, cells, ms: C.BUILDER_WALL_WARN_MS });
    this.log(`  [스킬] ${p.name} 솟는 벽 준비`);
    return true;
  }

  builderWallRise(p) {
    const cells = p.wallCells;
    p.wallAt = 0;
    p.wallCells = null;
    const g = ++this.bgroup;
    const placed = cells.filter(([x, y, z]) => this.placeBBlock(p, x, y, z, 'wall', g));
    if (!placed.length) return;
    this.gridChanged();
    const launched = new Set();
    // 벽 칸에 있던 사람은 벽 위로 올리고 띄움 (건축가 자신은 밀려남만)
    for (const t of this.players.values()) {
      if (!this.onField(t) || !placed.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t) || launched.has(t.id)) continue;
      launched.add(t.id);
      const hit = this.applyKnockback(t, Math.cos(p.yaw), Math.sin(p.yaw), 0, C.BUILDER_WALL_KB_UP, C.BUILDER_WALL_STUN_MS, C.BUILDER_WALL_DAMAGE, { by: p.id, kind: 'wall' });
      this.emit({ type: 'hit', kind: 'wall', by: p.id, target: t.id, ok: hit });
    }
    this.emit({ type: 'wallRise', who: p.id, cells: placed });
    this.emit({ type: 'bblock', who: p.id, kind: 'wall', group: g, cells: placed, ms: C.BUILDER_BLOCK_MS });
    this.log(`  [스킬] ${p.name} 솟는 벽 (${placed.length}칸${launched.size ? `, ${launched.size}명 띄움` : ''})`);
    this.clearLayers();
  }

  // 공중 F: 발밑 칸에 발판 + 위로 BUILDER_PAD_BOOST. 칸을 못 놓아도(필드 밖·막힘) 부스트는 함 (복귀기)
  builderPad(p) {
    const x = Math.floor(p.x);
    const y = Math.floor(p.y);
    const z = Math.floor(p.z) - 1;
    const g = ++this.bgroup;
    const ok = inXY(x, y) && z >= 0 && ![...this.players.values()].some((o) => this.onField(o) && overlapsCell(o, x, y, z)) && this.placeBBlock(p, x, y, z, 'pad', g);
    if (ok) {
      this.gridChanged();
      this.emit({ type: 'bblock', who: p.id, kind: 'pad', group: g, cells: [[x, y, z]], ms: C.BUILDER_BLOCK_MS });
    }
    p.vz = C.BUILDER_PAD_BOOST;
    p.grounded = false;
    this.emit({ type: 'padBoost', who: p.id, cell: ok ? [x, y, z] : null });
    this.log(`  [스킬] ${p.name} 발판${ok ? ` (${x},${y},${z})` : ' (칸 없이 부스트)'}`);
    return true;
  }

  // 건축가 블록 놓기 (빈 칸일 때만). 놓았으면 true
  placeBBlock(p, x, y, z, kind, group) {
    if (!inXY(x, y) || z < 0 || z >= C.GRID_H || this.grid[this.idx(x, y, z)] || this.pieceCells.has(cellKey(x, y, z))) return false;
    this.grid[this.idx(x, y, z)] = CELL.BUILD;
    this.bblocks.set(cellKey(x, y, z), { x, y, z, owner: p.id, kind, group, expiresAt: this.time + C.BUILDER_BLOCK_MS, born: this.time });
    return true;
  }

  removeBBlock(b, why) {
    this.bblocks.delete(cellKey(b.x, b.y, b.z));
    if (this.grid[this.idx(b.x, b.y, b.z)] === CELL.BUILD) this.grid[this.idx(b.x, b.y, b.z)] = 0;
    this.gridChanged();
    if (why !== 'blast') this.emit({ type: 'bblockGone', cells: [[b.x, b.y, b.z]], why });
  }

  // R 대폭발: 앞(네 방향으로 맞춤) BUILDER_BIG_GAP 칸 띄우고 BUILDER_BIG_SIZE × BUILDER_BIG_SIZE 기둥 꼭대기에서 블록이 솟음 (위 사람 띄움)
  // → BUILDER_BIG_FUSE_MS 뒤 자동 대폭발. 망치로 치면 바로. 블록이 위에서 떨어지지 않음 (압사 억까 금지)
  builderBigBomb(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const along = Math.abs(fx) >= Math.abs(fy) ? [Math.sign(fx), 0] : [0, Math.sign(fy)];
    const side = [-along[1], along[0]];
    const half = Math.floor(C.BUILDER_BIG_SIZE / 2);
    const g = ++this.bgroup;
    const placed = [];
    for (let a = 0; a < C.BUILDER_BIG_SIZE; a++) {
      for (let i = -half; i <= half; i++) {
        const x = Math.floor(p.x) + along[0] * (C.BUILDER_BIG_GAP + 1 + a) + side[0] * i;
        const y = Math.floor(p.y) + along[1] * (C.BUILDER_BIG_GAP + 1 + a) + side[1] * i;
        if (!inXY(x, y)) continue;
        const z = this.columnTop(x, y);
        if (this.placeBBlock(p, x, y, z, 'big', g)) placed.push([x, y, z]);
      }
    }
    if (!placed.length) return false;
    this.gridChanged();
    const launched = new Set();
    for (const t of this.players.values()) {
      if (!this.onField(t) || !placed.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t) || launched.has(t.id)) continue;
      launched.add(t.id);
      const hit = this.applyKnockback(t, along[0], along[1], 0, C.BUILDER_BIG_RISE_UP, C.BUILDER_BIG_RISE_STUN_MS, 0, { by: p.id, kind: 'bigbomb' });
      this.emit({ type: 'hit', kind: 'bigbomb', by: p.id, target: t.id, ok: hit });
    }
    this.bigBombs.push({ owner: p.id, group: g, at: this.time + C.BUILDER_BIG_FUSE_MS, dir: { x: along[0], y: along[1] } });
    this.emit({ type: 'bigBombWarn', who: p.id, cells: placed, ms: C.BUILDER_BIG_FUSE_MS, group: g });
    this.log(`  [필살] ${p.name} 대폭발 준비 (${placed.length}칸${launched.size ? `, ${launched.size}명 띄움` : ''})`);
    this.clearLayers();
    return true;
  }

  // 대폭발 터짐 (자동 또는 망치). 범위 안 사람 한 번씩 dir 쪽으로 날림, 범위 안 내 블록(벽·3타)도 같이 터짐
  explodeBig(bomb, dir) {
    this.bigBombs = this.bigBombs.filter((b) => b !== bomb);
    const p = this.players.get(bomb.owner);
    const cells = [...this.bblocks.values()].filter((b) => b.group === bomb.group);
    for (const b of cells) this.removeBBlock(b, 'blast');
    if (!cells.length) return;
    this.holeUnder(cells);
    let n = 0;
    for (const t of this.players.values()) {
      if (!p || !this.foe(p, t) || !cells.some((b) => this.nearCell(t, b, C.BUILDER_BIG_RANGE))) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.BUILDER_BIG_KB_SPEED, C.BUILDER_BIG_KB_UP, C.BUILDER_BIG_STUN_MS, C.BUILDER_BIG_DAMAGE, { by: bomb.owner, kind: 'bigbomb' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'bigbomb', by: bomb.owner, target: t.id, ok: hit });
    }
    this.emit({ type: 'bigBomb', who: bomb.owner, cells: cells.map((b) => [b.x, b.y, b.z]), dir });
    // 범위 안 내 블록도 같이 (묶음째)
    const near = [...this.bblocks.values()].filter((b) => b.owner === bomb.owner && b.kind !== 'big' && cells.some((c) => Math.abs(c.x - b.x) <= 1 && Math.abs(c.y - b.y) <= 1 && Math.abs(c.z - b.z) <= 1));
    let also = 0;
    const done = new Set();
    for (const b of near) {
      if (!this.bblocks.has(cellKey(b.x, b.y, b.z)) || done.has(b.group)) continue;
      done.add(b.group);
      also += this.blast(b, dir);
    }
    this.log(`  [필살] ${p ? p.name : '?'} 대폭발 (${n}명${also ? `, 같이 터진 블록 ${also}칸` : ''})`);
  }

  // 사람 몸(가로 상자)이 칸 가장자리에서 r 안, 높이 차 BUILDER_BLAST_HEIGHT 안
  nearCell(t, b, r) {
    const gx = Math.max(b.x - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - (b.x + 1), 0);
    const gy = Math.max(b.y - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - (b.y + 1), 0);
    return Math.hypot(gx, gy) <= r && Math.abs(t.z - b.z) <= C.BUILDER_BLAST_HEIGHT;
  }

  // 망치(평타) 판정이 닿은 내 블록을 터뜨림. 터뜨렸으면 true
  hammerBlocks(p, range, cosHalf) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const hitGroups = new Set();
    const targets = [];
    for (const b of this.bblocks.values()) {
      if (b.owner !== p.id || hitGroups.has(b.group)) continue; // 발판도 터짐 (2026-10-25 재혁: 밟고 있는 발판을 쳐서 떨어지는 건 플레이어가 고름)
      const dx = b.x + 0.5 - p.x;
      const dy = b.y + 0.5 - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > range + 0.5 || b.z + 1 < p.z - 0.1 || b.z > p.z + C.PLAYER_HEIGHT) continue;
      if (dist > C.BASIC_STEP_GAP + 0.5 && (dx * fx + dy * fy) / dist < cosHalf) continue;
      hitGroups.add(b.group);
      targets.push(b);
    }
    for (const b of targets) {
      if (b.kind === 'big') {
        const bomb = this.bigBombs.find((x) => x.group === b.group);
        if (bomb) this.explodeBig(bomb, { x: fx, y: fy });
      } else if (this.bblocks.has(cellKey(b.x, b.y, b.z))) this.blast(b, { x: fx, y: fy });
    }
    return targets.length > 0;
  }

  // 벽·3타 블록·발판 폭발. 벽은 같은 묶음끼리 이어진 칸으로 연쇄. 사람은 한 번씩, 가까운 터진 칸 수 × BUILDER_BLAST_DAMAGE.
  // 치는 방향(dir) 앞쪽 사람만 dir 쪽으로 날림, 건축가 자신은 안 맞음. 터진 칸 수를 돌려줌
  blast(start, dir) {
    const p = this.players.get(start.owner);
    const order = [start];
    const seen = new Set([cellKey(start.x, start.y, start.z)]);
    if (start.kind === 'wall') {
      for (let i = 0; i < order.length; i++) {
        const c = order[i];
        for (const [ox, oy, oz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
          const k = cellKey(c.x + ox, c.y + oy, c.z + oz);
          const nb = this.bblocks.get(k);
          if (nb && !seen.has(k) && nb.group === start.group) {
            seen.add(k);
            order.push(nb);
          }
        }
      }
    }
    for (const b of order) this.removeBBlock(b, 'blast');
    this.holeUnder(order);
    if (p) p.ult = Math.min(C.ULT_MAX, p.ult + order.length * C.BUILDER_BLAST_ULT); // 패시브: 내 블록 폭발 1칸당 게이지
    const hits = [];
    for (const t of this.players.values()) {
      if (!p || !this.foe(p, t)) continue;
      const near = order.filter((b) => this.nearCell(t, b, C.BUILDER_BLAST_RANGE) && (t.x - (b.x + 0.5)) * dir.x + (t.y - (b.y + 0.5)) * dir.y > -0.5);
      if (!near.length) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.BUILDER_BLAST_KB_SPEED, C.BUILDER_BLAST_KB_UP, C.BUILDER_BLAST_STUN_MS, near.length * C.BUILDER_BLAST_DAMAGE, { by: start.owner, kind: 'blast' }, true);
      this.emit({ type: 'hit', kind: 'blast', by: start.owner, target: t.id, ok: hit });
      hits.push(`${t.name}${hit ? ` ${t.damage}%` : ' 무적'}`);
    }
    this.emit({ type: 'blast', who: start.owner, kind: start.kind, group: start.group, cells: order.map((b) => [b.x, b.y, b.z]), dir });
    this.log(`  [폭발] ${p ? p.name : '?'} ${BBLOCK_LOG[start.kind]} ${order.length}칸${hits.length ? ` → ${hits.join(', ')}` : ''}`);
    return order.length;
  }

  // 테스트 옵션: 터진 칸 바로 아래 바닥 1칸을 BUILDER_HOLE_MS 동안 구멍으로 (건축가 블록·떨어지는 블록은 빼고)
  holeUnder(cells) {
    if (!C.BUILDER_BLAST_HOLE) return;
    for (const b of cells) {
      const z = b.z - 1;
      if (z < 0 || this.bblocks.has(cellKey(b.x, b.y, z)) || this.pieceCells.has(cellKey(b.x, b.y, z))) continue;
      const v = this.grid[this.idx(b.x, b.y, z)];
      if (!v) continue;
      this.grid[this.idx(b.x, b.y, z)] = 0;
      this.holes.push({ x: b.x, y: b.y, z, v, at: this.time + C.BUILDER_HOLE_MS });
    }
    this.gridChanged();
  }

  // 틱마다: 수명 끝난 건축가 블록 사라짐, 다른 이유로 없어진 칸(폭탄 등)은 기록에서 지움, 대폭발 시간, 구멍 메우기
  updateBBlocks() {
    for (const b of [...this.bblocks.values()]) {
      if (this.grid[this.idx(b.x, b.y, b.z)] !== CELL.BUILD) this.bblocks.delete(cellKey(b.x, b.y, b.z));
      else if (this.time >= b.expiresAt && b.kind !== 'big') this.removeBBlock(b, 'expire');
    }
    for (const bomb of [...this.bigBombs]) if (this.time >= bomb.at) this.explodeBig(bomb, bomb.dir);
    for (const h of [...this.holes]) {
      if (this.time < h.at) continue;
      if (this.grid[this.idx(h.x, h.y, h.z)] || [...this.players.values()].some((o) => this.onField(o) && overlapsCell(o, h.x, h.y, h.z))) continue; // 사람이 있으면 다음 틱
      this.grid[this.idx(h.x, h.y, h.z)] = h.v;
      this.holes = this.holes.filter((x) => x !== h);
      this.gridChanged();
    }
  }

  // ---- 갈고리 ----
  // 보는 방향 HOOK_RANGE 안 (반각 HOOK_HALF_ANGLE_DEG, 높이 차 2칸 안) 가장 가까운 상대
  hookTarget(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.HOOK_HALF_ANGLE_DEG * Math.PI) / 180);
    let best = null;
    let bd = Infinity;
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.HOOK_RANGE || d < 0.3 || Math.abs(t.z - p.z) > 2 || (dx * fx + dy * fy) / d < cosHalf) continue;
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    return best;
  }

  // 보는 방향 수평으로 HOOK_RANGE 안 첫 블록 (격자 칸 또는 떨어지는 블록, 바닥은 아님). { x, y, z, d } 또는 null
  hookRayBlock(p, yaw = p.yaw) {
    const fx = Math.cos(yaw);
    const fy = Math.sin(yaw);
    const z = Math.floor(p.z + C.HOOK_RAY_HEIGHT);
    for (let d = C.PLAYER_HALF; d <= C.HOOK_RANGE + 1e-9; d += 0.1) {
      const x = Math.floor(p.x + fx * d);
      const y = Math.floor(p.y + fy * d);
      if (z < 0 || z >= C.GRID_H) return null;
      if ((inXY(x, y) && this.grid[this.idx(x, y, z)]) || this.pieceCells.has(cellKey(x, y, z))) return { x, y, z, d };
    }
    return null;
  }

  // 상대를 내 앞 HOOK_PULL_TO 거리까지 끌어옴 (블록에 막히면 거기까지). 콤보 한 타 (넉백 없이 경직 + 피해)
  pullTo(p, t, stunMs, gain, kind) {
    if (this.invulnerable(t)) return false;
    const dx = p.x - t.x;
    const dy = p.y - t.y;
    const d = Math.hypot(dx, dy) || 1;
    const go = Math.max(0, d - C.HOOK_PULL_TO);
    this.moveAxis(t, 'x', (dx / d) * go);
    this.moveAxis(t, 'y', (dy / d) * go);
    const hit = this.applyKnockback(t, dx, dy, 0, 0, stunMs, gain, { by: p.id, kind });
    t.kbx = 0;
    t.kby = 0;
    return hit;
  }

  // F 갈고리 (판정 즉시): 보는 방향에서 상대·블록 중 먼저 닿는 것. 상대면 끌어옴 + 장전, 블록이면 내가 끌려감 (공중 가능). 빗나가도 쿨타임
  hookPull(p) {
    const t = this.hookTarget(p);
    const block = this.hookRayBlock(p);
    const td = t ? Math.hypot(t.x - p.x, t.y - p.y) : Infinity;
    if (block && block.d < td) {
      const go = Math.max(0, block.d - C.PLAYER_HALF - 0.05);
      p.zipDir = { x: Math.cos(p.yaw), y: Math.sin(p.yaw) };
      p.zipUntil = this.time + (go / C.HOOK_ZIP_SPEED) * 1000;
      p.vz = Math.max(p.vz, C.HOOK_ZIP_UP);
      p.grounded = false;
      p.kbx = 0;
      p.kby = 0;
      this.emit({ type: 'hook', who: p.id, target: null, block: [block.x, block.y, block.z], yaw: p.yaw });
      this.log(`  [스킬] ${p.name} 갈고리 → 블록 (${block.x},${block.y},${block.z}) ${go.toFixed(1)}칸 끌려감`);
      return true;
    }
    this.emit({ type: 'hook', who: p.id, target: t ? t.id : null, block: null, yaw: p.yaw });
    if (!t) {
      this.log(`  [스킬] ${p.name} 갈고리 빗나감`);
      return true; // 빗나가도 쿨타임
    }
    const hit = this.pullTo(p, t, C.HOOK_STUN_MS, C.HOOK_DAMAGE, 'hook');
    if (hit && !p.loaded) {
      p.loaded = true; // 끌어오면 장전
      this.emit({ type: 'reload', who: p.id });
    }
    this.log(`  [스킬] ${p.name} 갈고리 → ${t.name}${hit ? ` (${t.name} ${t.damage}%) 장전` : ' 무적이라 무시'}`);
    return true;
  }

  // R 블록 내려찍기 1단계: 보는 방향 첫 블록 1칸을 뽑음 (격자에서 빠짐). 없으면 false (게이지 그대로)
  hookGrab(p) {
    const b = this.hookRayBlock(p);
    if (!b) return false;
    const key = cellKey(b.x, b.y, b.z);
    let v = CELL.THROWN;
    if (this.pieceCells.has(key)) {
      const pc = this.pieces.find((x) => x.id === this.pieceCells.get(key));
      v = cellOfShape(pc.shape);
      pc.cells = pc.cells.filter(([dx, dy]) => !(pc.px + dx === b.x && pc.py + dy === b.y));
      if (!pc.cells.length) this.removePiece(pc);
      else {
        this.refreshPieceCells();
        this.updateLanding(pc);
      }
    } else {
      v = this.grid[this.idx(b.x, b.y, b.z)];
      this.grid[this.idx(b.x, b.y, b.z)] = 0;
      this.gridChanged();
    }
    const meta = this.bblocks.get(key) || null; // 건축가 블록은 속성 그대로 옮김
    if (meta) this.bblocks.delete(key);
    p.grab = { at: this.time + C.HOOK_GRAB_MS, v, meta, from: [b.x, b.y, b.z], dir: { x: Math.cos(p.yaw), y: Math.sin(p.yaw) } };
    this.emit({ type: 'blockGrab', who: p.id, from: [b.x, b.y, b.z], ms: C.HOOK_GRAB_MS, builder: !!meta });
    this.log(`  [필살] ${p.name} 블록 뽑기 (${b.x},${b.y},${b.z})`);
    return true;
  }

  // R 2단계: 앞 직선 HOOK_SLAM_LEN 칸을 내려찍음 (넉백 + 띄움) → 끝 칸 기둥 꼭대기에 박힘 (사람은 밀쳐냄, 필드 밖이면 사라짐)
  hookSlam(p) {
    const g = p.grab;
    p.grab = null;
    const { dir } = g;
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || Math.abs(t.z - p.z) > 2) continue;
      const along = (t.x - p.x) * dir.x + (t.y - p.y) * dir.y;
      const side = Math.abs((t.x - p.x) * dir.y - (t.y - p.y) * dir.x);
      if (along < 0.3 || along > C.HOOK_SLAM_LEN + 0.5 || side > C.HOOK_SLAM_WIDTH) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.HOOK_SLAM_KB_SPEED, C.HOOK_SLAM_KB_UP, C.HOOK_SLAM_STUN_MS, C.HOOK_SLAM_DAMAGE, { by: p.id, kind: 'blockslam' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'blockslam', by: p.id, target: t.id, ok: hit });
    }
    const x = Math.floor(p.x + dir.x * C.HOOK_SLAM_LEN);
    const y = Math.floor(p.y + dir.y * C.HOOK_SLAM_LEN);
    let cell = null;
    if (inXY(x, y)) {
      const z = this.columnTop(x, y);
      if (z < C.GRID_H && !this.pieceCells.has(cellKey(x, y, z))) {
        this.grid[this.idx(x, y, z)] = g.v;
        if (g.meta) this.bblocks.set(cellKey(x, y, z), { ...g.meta, x, y, z });
        cell = [x, y, z];
        this.gridChanged();
        // 그 칸 사람은 압사 대신 밀쳐냄 (내려찍은 방향으로 칸 밖, 막히면 블록 위로)
        for (const t of this.players.values()) {
          if (!this.onField(t) || !overlapsCell(t, x, y, z)) continue;
          const nx = dir.x > 0.5 ? x + 1 + C.PLAYER_HALF + 0.01 : dir.x < -0.5 ? x - C.PLAYER_HALF - 0.01 : t.x;
          const ny = dir.y > 0.5 ? y + 1 + C.PLAYER_HALF + 0.01 : dir.y < -0.5 ? y - C.PLAYER_HALF - 0.01 : t.y;
          const moved = { ...t, x: nx, y: ny };
          if ((nx !== t.x || ny !== t.y) && !this.overlappingSolid(this.aabb(moved)).length) Object.assign(t, { x: nx, y: ny });
          else this.ejectFromBlocks(t);
        }
      }
    }
    this.emit({ type: 'blockSlam', who: p.id, dir, len: C.HOOK_SLAM_LEN, cell, builder: !!g.meta });
    this.log(`  [필살] ${p.name} 블록 내려찍기 (${n}명)${cell ? ` → (${cell.join(',')}) 박힘` : ' → 필드 밖으로 사라짐'}`);
    this.clearLayers();
  }

  // R 뽑는 중에 맞아서 끊김: 블록은 원래 자리로 (비었으면), 아니면 사라짐
  hookGrabDrop(p) {
    const g = p.grab;
    p.grab = null;
    const [x, y, z] = g.from;
    if (!this.grid[this.idx(x, y, z)] && !this.pieceCells.has(cellKey(x, y, z))) {
      this.grid[this.idx(x, y, z)] = g.v;
      if (g.meta) this.bblocks.set(cellKey(x, y, z), { ...g.meta, x, y, z });
      this.gridChanged();
    }
  }

  // 틱마다: 콤보가 끊긴 사람 무적, 돌진 부딪힘, 내려찍기·솟는 벽·블록 내려찍기 발동
  updateCombat() {
    if (this.bblocks.size || this.bigBombs.length || this.holes.length) this.updateBBlocks();
    if (this.quakes.length) this.updateQuakes();
    for (const p of this.players.values()) {
      if (p.comboHits > 0 && this.time >= p.stunUntil) this.endCombo(p);
      if (!this.onField(p)) {
        p.chargeUntil = p.slamAt = p.wallAt = p.zipUntil = 0;
        if (p.grab) this.hookGrabDrop(p);
        p.atk = null;
        p.atkQueued = false;
        p.castQueued = null;
        p.star2 = null;
        continue;
      }
      if (p.atk && this.time >= p.atk.at) this.basicHit(p);
      if (p.star2 && this.time >= p.star2.at) {
        const s2 = p.star2;
        p.star2 = null;
        if (this.starShot(p, s2.n, s2.air, s2.def, 2, s2.chained)) {
          p.atkLanded = true;
          this.ninjaCdCut(p);
        }
      }
      if (p.char === 'ninja') this.ninjaTouch(p);
      if (p.castQueued && !p.atk && (p.atkLanded || this.time >= p.pushReadyAt)) this.castQueuedNow(p);
      else if (p.atkQueued && !p.atk && this.time >= p.pushReadyAt) {
        p.atkQueued = false;
        if (this.time >= p.stunUntil && !this.isControlling(p)) this.basicStart(p);
      }
      if (this.time < p.chargeUntil) this.chargeHit(p);
      if (p.slamAt && this.time >= p.slamAt) this.tankSlam(p);
      if (p.wallAt && this.time >= p.wallAt) this.builderWallRise(p);
      if (p.grab && this.time >= p.grab.at) this.hookSlam(p);
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
      if (!this.onField(t) || t.id === b.by) continue;
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
      if (!this.onField(t) || t.id === piece.thrownBy) continue; // 던진 사람은 자기 충격파를 안 맞음
      const gx = Math.max(x0 - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - x1, 0);
      const gy = Math.max(y0 - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - y1, 0);
      if (Math.hypot(gx, gy) > C.BRICK_SHOCK_RANGE || Math.abs(t.z - z) > C.BRICK_SHOCK_HEIGHT) continue;
      const hit = this.applyKnockback(t, t.x - cx, t.y - cy, C.BRICK_SHOCK_KB_SPEED, C.BRICK_SHOCK_KB_UP, C.BRICK_SHOCK_STUN_MS, C.DAMAGE_GAIN.shock, { by: piece.thrownBy, kind: 'shock' }, true);
      this.emit({ type: 'hit', kind: 'shock', by: piece.thrownBy, target: t.id, ok: hit });
      this.log(`  [충격파] ${by ? by.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
    }
  }

  // 경직 중이면 무시 (연속 넉백 불가). 성공 시 true
  // gain: 이번 공격으로 쌓이는 피해 %. 맞기 전까지 쌓인 % 로 수평 넉백을 키우고 그다음에 쌓는다
  // (위로 튀는 속도는 그대로)
  startEmote(p, n) {
    if (!p || !this.onField(p) || (this.phase !== 'playing' && this.phase !== 'over')) return false;
    if (!Number.isInteger(n) || n < 0 || n >= C.EMOTE_NAMES.length) return false;
    if (this.time < p.emoteReadyAt || this.time < p.stunUntil || this.isControlling(p)) return false;
    p.emote = n;
    p.emoteUntil = this.time + C.EMOTE_MS;
    p.emoteReadyAt = this.time + C.EMOTE_COOLDOWN_MS;
    return true;
  }

  isEmoting(p) {
    return this.time < p.emoteUntil;
  }

  // src: { by, kind } — 누가 무엇으로 날렸는지 (킬 판정용 lastHit)
  // heavy: 무거운 공격 (망치·투사체·폭탄·충격파·필살기·평타 마무리 타) 은 콤보 중에도 넉백을 안 줄임
  // opts.fixed: 평타 중간 타 — 넉백 고정 (피해 % 배율·콤보 감쇠·탱크 패시브 없음). opts.finish: 평타 마무리 타 — 콤보 2타 이상이면 시간과 상관없이 마무리
  applyKnockback(t, dx, dy, speed, up, stunMs = C.STUN_MS, gain = 0, src = null, heavy = false, opts = {}) {
    if (this.invulnerable(t)) return false; // 콤보 뒤 무적·부활 무적
    const teammate = src && this.sameTeam(this.players.get(src.by), t);
    // 탱크 아머 (F 돌진 중·R 떠오르는 동안): 넉백·경직 없이 피해 % 만. 마무리 타·필살기면 깨지고 보통처럼 (카운터는 안 당함)
    let armorBroken = false;
    if (!teammate && t.char === 'tank' && (this.time < t.chargeUntil || t.slamAt)) {
      const name = this.players.get(src?.by)?.name || '?';
      if (!opts.finish && !ULT_KINDS.has(src?.kind)) {
        if (src && src.by !== t.id) t.lastHit = { by: src.by, kind: src.kind, name };
        t.damage += gain;
        this.gainUlt(t, src, gain);
        this.emit({ type: 'armor', who: t.id, by: src ? src.by : null });
        this.log(`  [아머] ${t.name} ← ${name} 버팀 (${t.name} ${t.damage}%)`);
        return true;
      }
      armorBroken = true;
      this.emit({ type: 'armorBreak', who: t.id, by: src ? src.by : null });
      this.log(`  [아머] ${t.name} ← ${name} 깨짐`);
    }
    // 콤보: 경직이 안 풀렸는데 또 맞으면 이어짐. 첫 타에서 COMBO_MS 가 지난 뒤 들어간 타가 마지막 타 (크게 날리고 무적). 같은 팀은 콤보로 안 셈 (무적도 안 붙음)
    if (!teammate) {
      t.comboHits = this.time < t.stunUntil && t.comboHits > 0 ? t.comboHits + 1 : 1;
      if (t.comboHits === 1) {
        t.comboBy = new Set(); // 이 콤보를 넣은 사람들 (로그·통계용)
        t.comboStartAt = this.time;
      }
      const hitter = src && src.by !== t.id ? this.players.get(src.by) : null;
      if (hitter) t.comboBy.add(hitter.name);
    }
    // 카운터히트: 맞는 쪽이 평타 준비·후딜, 스킬·필살기 준비(돌진 중 포함) 중이었음 → 경직·멈칫 길게
    const counter = !teammate && !armorBroken && !!src && !!t.char && this.time >= t.stunUntil && this.busy(t); // 이미 경직 중(콤보)이면 아님, 탱크 아머 중이면 아님
    if (counter) {
      stunMs *= C.COUNTER_STUN_MULT;
      t.counterAt = this.time;
      this.emit({ type: 'counter', by: src.by, target: t.id });
      this.log(`  [카운터] ${this.players.get(src.by)?.name} → ${t.name}`);
    }
    // 2026-10-25 재혁: 때린 쪽이 연타를 이어 가는 중인 타(opts.chained)는 COMBO_MS 가 지나도 시간 마무리가 아님.
    // 연타는 길이가 정해져 있어서 (지상 마지막 타 → 공중 마무리) 무한히 안 늘어남. 스킬·다른 사람 타는 예전처럼 시간 마무리
    const finisher = !teammate && t.comboHits >= 2 && (opts.finish || (this.time - t.comboStartAt >= C.COMBO_MS && !opts.chained));
    const fixed = opts.fixed && !finisher;
    if (!fixed) speed *= finisher ? C.COMBO_FINISH_KB : heavy ? 1 : C.COMBO_LIGHT_KB;
    if (!teammate && t.comboHits >= 2 && src) this.emit({ type: 'combo', by: src.by, target: t.id, n: t.comboHits, finish: finisher });
    // 맞아서 끊긴 공격: 쿨타임·게이지를 돌려주고 interrupt 이벤트 (화면에서 끊긴 모션)
    if (t.atk) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'basic', n: t.atk.n });
      t.pushReadyAt = this.time; // 안 나간 평타는 후딜 없음
    }
    if (this.time < t.chargeUntil) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'skill' });
      t.skillReadyAt = this.time; // 아무도 못 친 돌진은 쿨타임 안 씀
    }
    if (t.slamAt) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      t.ult = C.ULT_MAX; // 준비 중에 끊긴 내려찍기는 게이지 돌려줌
    }
    if (t.grab) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      this.hookGrabDrop(t); // 뽑던 블록은 제자리로
      t.ult = C.ULT_MAX; // 게이지 돌려줌
    }
    t.zipUntil = 0; // 끌려가다 맞으면 멈춤
    t.emoteUntil = 0; // 맞으면 이모트 끊김
    t.chargeUntil = 0; // 맞으면 돌진·내려찍기 끊김
    t.slamAt = 0;
    t.atk = null; // 맞으면 평타 준비·이어 치기 끊김
    t.star2 = null;
    t.streak = 0;
    t.atkQueued = false;
    t.castQueued = null;
    t.chainN = 0;
    if (teammate) gain = 0; // 팀전: 같은 팀은 밀리기만 (피해 % 없음, 킬로도 안 침)
    else if (src && src.by !== t.id) {
      t.lastHit = { by: src.by, kind: src.kind, name: this.players.get(src.by)?.name };
      // 때린 쪽의 이어 넣은 타 수 (상대가 바뀌어도 STREAK_MS 안이면 이어짐 → 닌자 갈아타기 'N HIT')
      const by = this.players.get(src.by);
      if (by) {
        by.streak = this.time < by.streakUntil ? by.streak + 1 : 1;
        by.streakUntil = this.time + C.STREAK_MS;
        if (by.streak >= 2) this.emit({ type: 'streak', who: by.id, n: by.streak, target: t.id });
      }
    }
    const taken = t.char === 'tank' ? C.TANK_KB_TAKEN : t.char === 'ninja' ? C.NINJA_KB_TAKEN : 1; // 탱크 패시브: 덜 밀림, 닌자 약점: 잘 밀림
    const mult = fixed ? 1 : (C.DAMAGE_KB_BASE + t.damage * C.DAMAGE_KB_PER_PERCENT) * taken;
    t.damage += gain;
    this.gainUlt(t, src, gain);
    const len = Math.hypot(dx, dy) || 1;
    t.kbx = (dx / len) * speed * mult;
    t.kby = (dy / len) * speed * mult;
    t.vz = up;
    t.grounded = false;
    t.wallBounced = false; // 벽 튕김은 맞을 때마다 한 번
    t.stunUntil = this.time + stunMs;
    t.freezeUntil = this.time + C.HITSTOP_MS * (counter ? C.COUNTER_HITSTOP_MULT : 1); // 멈칫 뒤에 날아간다 (날아가는 거리는 그대로)
    if (finisher) this.endCombo(t, t.stunUntil, true);
    return true;
  }

  // 필살기 게이지: 피해 % 를 주거나 받은 만큼 (탱크 패시브: 받은 피해로는 × TANK_ULT_TAKEN_MULT)
  gainUlt(t, src, gain) {
    if (gain <= 0) return;
    t.ult = Math.min(C.ULT_MAX, t.ult + gain * C.ULT_PER_DAMAGE * (t.char === 'tank' ? C.TANK_ULT_TAKEN_MULT : 1));
    const by = src && src.by !== t.id ? this.players.get(src.by) : null;
    if (by) by.ult = Math.min(C.ULT_MAX, by.ult + gain * C.ULT_PER_DAMAGE);
  }

  // 카운터히트 대상 (2026-10-25 재혁 결정, 첫 사람 플레이테스트: 1:1 에서 동시에 누르면 거의 다 카운터였음):
  // 빗나간 평타의 후딜, 돌진 중, 내려찍기·솟는 벽 준비·갈고리 블록 뽑는 중. 평타 준비 중·맞힌 평타의 후딜·걷기·점프는 아님
  busy(t) {
    return !!((this.time < t.pushReadyAt && !t.atk && !t.atkLanded) || this.time < t.chargeUntil || t.slamAt || t.wallAt || t.grab);
  }

  // 공격이 안 들어가는 상태: 콤보 뒤 무적·부활 무적. 경직이 이미 풀린 콤보는 여기서 먼저 끝냄
  // (봇 행동·블록 충격파는 틱 안에서 updateCombat 보다 먼저 돌아서, 끝난 콤보에 새 콤보가 붙어 무적을 건너뛰던 것)
  invulnerable(t) {
    if (t.comboHits > 0 && this.time >= t.stunUntil) this.endCombo(t);
    return this.time < t.iframeUntil || this.time < t.shieldUntil;
  }

  // 콤보 끝: 그때부터 COMBO_IFRAME_MS 무적 (마지막 타는 경직이 끝날 때까지 + 무적)
  endCombo(t, from = this.time, finished = false) {
    if (t.comboHits >= 2) {
      const line = `  [콤보] ${[...(t.comboBy || [])].join('+') || '?'} → ${t.name} ${t.comboHits}타${finished ? ' 마무리' : ''}`; // 때린 사람 여럿이면 P1+P3
      if (finished) this.pendingLogs.push(line); // 마무리 타는 그 공격 줄 뒤에
      else this.log(line);
    }
    t.comboHits = 0;
    t.iframeUntil = from + C.COMBO_IFRAME_MS;
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

  // 떨어지는 블록이 이 사람을 깔기까지 남은 시간 (ms). CRUSH_WARN_MS 안에 깔 블록이 없으면 null.
  // 블록 칸이 몸(가로 판정 상자)과 겹치고, 지금 몸 위에 있으며, 착지 높이가 머리보다 낮으면 깔림
  crushDanger(p) {
    if (this.isGhost(p) || this.time < p.shieldUntil) return null; // 블록이 통과하는 사람 (유령·부활 무적)
    let best = null;
    const b = this.aabb(p);
    for (const piece of this.pieces) {
      if (piece.phase !== 'falling') continue;
      if (!(piece.pz + 1 > p.z && piece.landZ < p.z + C.PLAYER_HEIGHT)) continue;
      const over = piece.cells.some(([dx, dy]) => {
        const x = piece.px + dx;
        const y = piece.py + dy;
        return x < b.x1 && x + 1 > b.x0 && y < b.y1 && y + 1 > b.y0;
      });
      if (!over) continue;
      // 몸 꼭대기(머리)에 닿을 때까지: 지금 높이에서 머리 위 칸까지 내려오는 칸 수 × 한 칸 간격
      const steps = Math.max(0, Math.ceil(piece.pz - (p.z + C.PLAYER_HEIGHT)));
      const eta = Math.max(0, steps * piece.stepMs + (piece.nextStepAt - this.time) - piece.stepMs);
      if (eta <= C.CRUSH_WARN_MS && (best === null || eta < best)) best = eta;
    }
    return best;
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
    if (piece.landZ + 1 > C.GRID_H || piece.landZ > piece.pz) return false;
    // 블록 마스터: 조종 중인 블록은 주변보다 너무 높게 못 놓음 (빨간 미리보기)
    if (this.mode === 'master' && piece.phase === 'control' && this.tooTall(piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]), piece.landZ)) return false;
    return true;
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

  // randomSpot: 블록 마스터는 무작위 자리에서 시작 (바로 Enter 를 눌러도 한 곳에 탑이 안 쌓이게)
  spawnControlled(controller, randomSpot = false) {
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const rot = Math.floor(this.rng() * 4);
    const { w, d } = footprint(rotatedCells(shape, rot));
    const px = randomSpot ? Math.floor(this.rng() * (C.GRID_W - w + 1)) : Math.floor((C.GRID_W - w) / 2);
    const py = randomSpot ? Math.floor(this.rng() * (C.GRID_D - d + 1)) : Math.floor((C.GRID_D - d) / 2);
    const piece = this.makePiece(shape, rot, px, py, C.CONTROL_HOVER_Z);
    this.addPiece(piece, {
      phase: 'control',
      controller: controller.id,
      stepMs: C.HARD_DROP_STEP_MS,
      nextStepAt: 0,
      controlEndsAt: this.time + C.CONTROL_TIME_MS,
    });
    this.updateLanding(piece); // 조종 블록이 된 뒤 다시 (블록 마스터 높이 제한)
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
    if (this.mode === 'master') {
      // 블록 마스터: 자동 블록 없이 마스터 편 각자의 블록만. 떨어뜨리면 MASTER_NEXT_PIECE_MS 뒤 다음 블록 (dropPiece 가 시계를 맞춤)
      for (const p of this.players.values()) {
        if (p.master && p.alive && this.time >= p.nextPieceAt && !this.controlledPiece(p)) this.spawnControlled(p, true);
      }
      return;
    }
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
    if (this.mode === 'master' && who && who.master) who.nextPieceAt = this.time + C.MASTER_NEXT_PIECE_MS;
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
    this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + (this.mode === 'master' ? C.MASTER_NEXT_PIECE_MS : this.autoSpawnDelayMs()));
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
      if (!this.onField(p) || this.isGhost(p) || this.time < p.shieldUntil) continue; // 유령·부활 무적은 블록이 통과 (압사 면역)
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
    const cell = piece.thrownBy ? CELL.THROWN : cellOfShape(piece.shape); // 색 구분용
    for (const [x, y, z] of this.pieceWorldCells(piece)) {
      if (z >= 0 && z < C.GRID_H) this.grid[this.idx(x, y, z)] = cell;
    }
    const cells = this.pieceWorldCells(piece);
    this.emit({ type: 'land', cells: cells.map(([x, y, z]) => [x, y, z]), controlled: piece.controller !== null });
    const wasControlled = piece.controller !== null;
    if (piece.thrownBy) this.brickShock(piece);
    this.removePiece(piece);
    this.gridVersion++;
    this.gridDirty = true;
    this.clearLayers();
    if (this.mode === 'kills') this.sinkIfTall();
    for (const pc of this.pieces) this.updateLanding(pc);
    if (!piece.thrownBy && this.mode !== 'master') this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + this.autoSpawnDelayMs()); // 던진 블록은 자동 블록 간격에 안 끼어듦 (마스터 블록은 dropPiece 가 정함)
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
    this.dropLayers(full);
    this.emit({ type: 'clear', n: full.length });
    this.log(`  [층 클리어] z=${full.join(',')} 제거 → 위 블록·플레이어 ${full.length}칸 내려앉음`);
  }

  // 킬 점수전: 가장 높은 기둥이 KILLS_SINK_HEIGHT 에 닿으면 맨 아래 층을 지워 전체를 한 칸씩 내림 (필드가 안 막히게)
  sinkIfTall() {
    let n = 0;
    while (this.maxColumnTop() >= C.KILLS_SINK_HEIGHT) {
      this.dropLayers([0]);
      n++;
    }
    if (n) this.log(`  [가라앉음] 가장 높은 기둥 ${C.KILLS_SINK_HEIGHT}칸 → 맨 아래 ${n}층 지움, 전체가 ${n}칸 내려앉음`);
  }

  maxColumnTop() {
    let top = 0;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) top = Math.max(top, this.columnTop(x, y));
    return top;
  }

  // 층들을 지우고 위의 블록·플레이어·용암을 그만큼 내린다
  dropLayers(full) {
    const layerSize = C.GRID_W * C.GRID_D;
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
      if (p.master) continue; // 마스터는 필드 위 하늘에 둔 채로
      let shift = 0;
      for (const z of full) if (p.z >= z + 1 - 1e-3) shift++;
      p.z -= shift;
    }
    if (this.lava.active) this.lava.z -= full.filter((z) => z < this.lava.z).length;
    // 건축가 블록·구멍 기록도 같이 내림 (지워진 층에 있던 것은 버림)
    const moved = new Map();
    for (const b of this.bblocks.values()) {
      if (full.includes(b.z)) continue;
      b.z -= full.filter((z) => z < b.z).length;
      moved.set(cellKey(b.x, b.y, b.z), b);
    }
    this.bblocks = moved;
    for (const q of this.quakes) q.cells = q.cells.filter(([, , z]) => !full.includes(z)).map(([x, y, z]) => [x, y, z - full.filter((f) => f < z).length]);
    this.holes = this.holes.filter((h) => !full.includes(h.z));
    for (const h of this.holes) h.z -= full.filter((z) => z < h.z).length;
  }

  // ---------- 용암 ----------
  avgHeight() {
    let sum = 0;
    for (let x = 0; x < C.GRID_W; x++) for (let y = 0; y < C.GRID_D; y++) sum += this.columnTop(x, y);
    return sum / (C.GRID_W * C.GRID_D);
  }

  updateLava(dtMs) {
    if (this.mode === 'kills') return; // 킬 점수전은 용암 대신 아래층을 지움 (sinkIfTall)
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
      if (!this.onField(p) || p.z >= lava.z - 0.05) continue;
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
      control: !C.CONTROL_ITEM || this.mode === 'master' || this.controlInPlay() ? null : Math.max(0, this.controlItemNextAt - this.time),
      power: powerCount >= C.ITEM_MAX_ON_FIELD ? null : Math.max(0, this.powerItemNextAt - this.time),
    };
  }

  updateItems() {
    if (C.CONTROL_ITEM && this.mode !== 'master' && !this.controlInPlay() && this.time >= this.controlItemNextAt) { // 블록 마스터는 조종권 없음
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
          if (!this.onField(t) || t.id === pr.owner) continue;
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
    if (p.grounded) p.airJumps = C.AIR_JUMPS; // 땅에 닿아 있으면 2단 점프 다시 (같은 틱에 땅에서 뛰어도 채운 뒤)
    if (this.time < p.chargeUntil) {
      ix = p.chargeDir.x * C.TANK_CHARGE_SPEED; // 탱크 돌진: 입력 대신 앞으로
      iy = p.chargeDir.y * C.TANK_CHARGE_SPEED;
    } else if (this.time < p.zipUntil) {
      ix = p.zipDir.x * C.HOOK_ZIP_SPEED; // 갈고리 블록 걸기: 블록 쪽으로 끌려감
      iy = p.zipDir.y * C.HOOK_ZIP_SPEED;
    } else if (!stunned && !this.isEmoting(p)) {
      const mv = this.moveDir(p);
      if (mv) {
        const speed =
          C.MOVE_SPEED *
          (this.time < p.speedUntil ? C.SPEED_MULT : 1) *
          (p.atk && p.atk.def.finish ? C.BASIC_FINISH_MOVE_MULT : 1); // 평타 마무리 준비 중
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

  // ---------- 틱 ----------
  tick(dtMs) {
    this.flushLogs();
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
      for (const p of this.players.values()) if (this.onField(p)) this.integratePlayer(p, h);
      remaining -= h;
    }
    this.updateCombat();
    for (const p of this.players.values()) {
      if (this.onField(p) && p.z < C.FALL_DEATH_Z) this.kill(p, 'fall');
    }
    if (this.mode === 'kills') {
      for (const p of this.participants()) if (!p.alive && p.respawnAt && this.time >= p.respawnAt) this.respawn(p);
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
        winnerTeam: this.winnerTeam,
        winnerIds: this.winnerIds,
        left: this.phase === 'playing' && this.roundEndsAt ? Math.max(0, this.roundEndsAt - this.time) : null, // 블록 마스터·킬 점수전 남은 시간
        deaths: this.deaths,
        totals: this.totals,
      },
      players: [...this.players.values()].map((p) => ({
        id: p.id,
        slot: p.slot,
        name: p.name,
        nick: p.nick,
        spectator: p.spectator,
        team: p.team,
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
        jumpLeft: Math.max(0, p.jumpUntil - this.time),
        danger: p.alive ? this.crushDanger(p) : null, // 머리 위로 떨어지는 블록이 깔기까지 남은 ms (없으면 null)
        ghostLeft: Math.max(0, p.ghostUntil - this.time),
        speedLeft: Math.max(0, p.speedUntil - this.time),
        emote: this.isEmoting(p) ? p.emote : -1,
        emoteLeft: Math.max(0, p.emoteUntil - this.time),
        held: this.heldItem(p),
        bombs: p.bombs,
        bricks: p.bricks,
        brickSide: p.brickSide,
        aim: p.alive ? this.aimPreview(p) : null, // 고른 칸으로 우클릭하면 어디에 무엇이 생기는지
        damage: p.damage,
        wins: p.wins,
        controlling: this.isControlling(p),
        cause: p.deathCause,
        master: p.master,
        zombie: p.zombie,
        char: p.char,
        skillCd: Math.max(0, p.skillReadyAt - this.time),
        ult: Math.floor(p.ult),
        iframeLeft: Math.max(0, p.iframeUntil - this.time), // 콤보 뒤 무적 (깜빡임)
        combo: this.time < p.stunUntil ? p.comboHits : 0,
        empower: Math.max(0, p.empowerUntil - this.time), // 닌자 R 강화 남은 시간
        loaded: p.char === 'hook' ? p.loaded : undefined, // 갈고리 장전
        respawnIn: !p.alive && p.respawnAt ? Math.max(0, p.respawnAt - this.time) : null,
        shieldLeft: Math.max(0, p.shieldUntil - this.time),
        score: this.scores.get(p.id) || 0,
      })),
      pieces: piecesOut,
      nextSpawnIn,
      lava: { active: this.lava.active, z: this.lava.z },
      itemTimers: this.itemTimers(),
      botLevel: this.botLevel,
      teamMode: this.teamMode,
      teamWins: this.teamWins,
      mode: this.mode,
      teamScores: this.teamScores,
      map: { choice: this.mapChoice, id: this.mapId, name: MAPS[this.mapId].name },
      items: this.items,
      projectiles: this.projectiles.map((pr) => ({ x: pr.x, y: pr.y, z: pr.z })),
      bombs: this.bombs.map((b) => ({ id: b.id, x: b.x, y: b.y, z: b.z, left: Math.max(0, b.explodeAt - this.time) })),
      bblocks: [...this.bblocks.values()].map((b) => ({ x: b.x, y: b.y, z: b.z, owner: b.owner, kind: b.kind, group: b.group, left: b.kind === 'big' ? Math.max(0, (this.bigBombs.find((x) => x.group === b.group)?.at ?? this.time) - this.time) : Math.max(0, b.expiresAt - this.time) })), // 건축가 블록 (B: 색·깜빡임·묶음)
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
const TEAM_KO = { red: '빨강', blue: '파랑' };

// 킬 로그의 공격 이름 (npm run stats 가 한 단어로 읽음)
// 평타 로그 이름: "2타 반대 찌르기", 공중이면 "공중 망치 내려찍기" (공중 연타가 있는 캐릭터는 "공중 2타 내려 차기")
function basicLabel(set, n, air, def) {
  return air ? `공중 ${set.air.length > 1 ? `${n}타 ` : ''}${def.name}` : `${n}타 ${def.name}`;
}

// 필살기 공격 종류 (탱크 아머를 깸)
const ULT_KINDS = new Set(['slam', 'bigbomb', 'blockslam']);

const BBLOCK_LOG = { wall: '벽', third: '3타 블록', pad: '발판' };
const WEAPON_LOG = { push: '밀치기', wallkick: '벽차기', blast: '블록폭발', bigbomb: '대폭발', projectile: '투사체', shock: '충격파', bomb: '폭탄', control: '조종블록', thrown: '설치블록', slam: '내려찍기', hook: '갈고리', charge: '돌진', slash: '순간베기', wall: '솟는벽', blockslam: '블록내려찍기' };

function causeKo(cause) {
  if (cause === 'crush') return '압사';
  if (cause === 'fall') return '낙사';
  if (cause === 'lava') return '용암';
  if (cause === 'disconnect') return '접속 끊김';
  return cause;
}
