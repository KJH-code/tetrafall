// Tetrafall 서버 게임 상태. 권위는 전부 여기에 있다.
// 격자는 3D 정수 배열, 플레이어는 AABB + 넉백. 물리엔진 없음.
// 2026-10-30: 메서드는 묶음마다 server/game-*.js (격자·플레이어·판 흐름·입력·전투·아이템·블록·자리 고르기·물리·연습·스냅샷) 과
// server/char-*.js (캐릭터별) 로 나눠 두고 아래에서 Game.prototype 에 붙임. 여기엔 생성자·emit·tick 만
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES } from '../shared/pieces.js';
import { emptyLanded } from './game-util.js';
import { GridPart } from './game-grid.js';
import { PlayersPart } from './game-players.js';
import { RoundPart } from './game-round.js';
import { InputPart } from './game-input.js';
import { CombatPart } from './game-combat.js';
import { TankPart } from './char-tank.js';
import { NinjaPart } from './char-ninja.js';
import { HunterPart } from './char-hunter.js';
import { BardPart } from './char-bard.js';
import { BerserkerPart } from './char-berserker.js';
import { CannonPart } from './char-cannon.js';
import { BuilderPart } from './char-builder.js';
import { HookPart } from './char-hook.js';
import { ItemsPart } from './game-items.js';
import { PiecesPart } from './game-pieces.js';
import { PlacementPart } from './game-placement.js';
import { PhysicsPart } from './game-physics.js';
import { PracticePart } from './game-practice.js';
import { SnapshotPart } from './game-snapshot.js';
export { skyReach, cellGap } from './game-util.js';

export class Game {
  // countdownMs: 판 시작 전 카운트다운. 서버는 C.ROUND_COUNTDOWN_MS, 테스트는 기본 0 (바로 시작)
  // characters: 캐릭터(패시브·스킬·필살기)를 쓸지. 서버(방)는 켬, 예전 규칙 테스트는 끔 (모두 캐릭터 없음 = 예전 그대로)
  // skyStairs: 하늘 계단 (대기실 옵션). 서버(방)는 C.SKY_STAIRS_DEFAULT, 예전 규칙 테스트는 끔
  // hpMode: 체력전 (대기실 옵션, HP_MAX). 기본 끔
  constructor(log = () => {}, { countdownMs = 0, characters = false, skyStairs = false, hpMode = false } = {}) {
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
    this.skyStairs = !!skyStairs; // 호스트 옵션 (판 사이에만 바꿈)
    this.hpMode = !!hpMode; // 체력전: 호스트 옵션 (판 사이에만 바꿈)
    this.killsTarget = 0; // 킬 점수전 목표 (판 시작 때 인원·팀전·체력전으로 정함, KILLS_TARGET_BY_COUNT)
    this.masterStallUntil = 0; // 블록 마스터: 반격 아이템으로 마스터 편 다음 블록이 이때까지 안 나옴
    this.counterItemAt = 0; // 블록 마스터: 다음 반격 아이템 시각
    this.sky = false; // 이번 판에 하늘 계단이 도는지 (판 시작 때 정함, 블록 마스터는 끔)
    this.H = C.GRID_H; // 격자 높이 (판 시작 때: 하늘 계단이면 SKY_GRID_H)
    this.skyTops = []; // 하늘 계단 사슬마다 맨 위 블록 id (새 블록은 이 옆에)
    this.skyChains = 1; // 이번 판 사슬 수 (SKY_CHAINS, 판 시작 때 인원으로)
    this.skyLavaMs = C.SKY_LAVA_TRIGGER_MS; // 이번 판 용암 시작 시각 (SKY_LAVA_TRIGGER_BY_COUNT)
    this.rng = Math.random;
    this.time = 0; // 게임 시간 (ms). tick 마다 dt 만큼 증가
    this.phase = 'lobby'; // 'lobby' | 'countdown' | 'playing' | 'over'
    this.players = new Map(); // id -> player
    this.hostId = null;
    this.W = C.GRID_W; // 판 크기 (판 시작 때 인원으로 정함, FIELD_SIZES)
    this.D = C.GRID_D;
    this.spawnPoints = C.SPAWN_POINTS;
    this.grid = new Uint8Array(this.W * this.D * this.H);
    this.gridPiece = new Int32Array(this.grid.length); // 칸마다 착지한 블록 id (갈고리 R 덩어리). 블록이 아닌 칸·지워진 칸은 의미 없음 (grid 색과 같이 봄)
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
    this.shells = []; // 대포수 포탄 (보통·대형)
    this.notes = []; // 바드 류트 음파
    this.shellCounter = this.shellCounter || 0;
    this.bgroup = 0;
    this.bombCounter = 0;
    this.roundNumber = 0;
    this.roundStartTime = 0;
    this.roundEndTime = 0;
    this.winnerId = null;
    this.deaths = []; // 이번 판 사망 기록
    this.lastDeath = null; // 마지막 죽음 (finalKill)
    this.landed = emptyLanded(); // 이번 판 놓인 블록 수 (종류별, 판 끝 로그 "  블록:" → npm run stats)
    this.totals = { rounds: 0, crush: 0, fall: 0, lava: 0 }; // 누적 (합격선 측정용)
    this.totalsByCount = {}; // 인원수별 누적 { [n]: { rounds, crush, fall } }. 인원이 다르면 압사 비율을 따로 본다
    this.roundPlayerCount = 0;
    this.roundBotCount = 0;
    this.bots = new Map(); // 봇 플레이어 id -> BotBrain. 봇 id 는 음수
    this.proxies = new Map(); // 접속이 끊긴 사람 id -> 대신 조종하는 BotBrain (setAway, 봇처럼 handleInput·handleAction 만)
    this.botCounter = 0;
    this.nextSpawnAt = 0;
    this.controlItemNextAt = 0;
    this.powerItemNextAt = 0; // 조종권 외 아이템 다음 생성 시각
    this.gridDirty = true;
    this.events = []; // 클라이언트 알림용 이벤트. 브로드캐스트 때 drainEvents() 로 비운다
  }

  emit(e) {
    this.events.push(e);
    if (this.tutorial) this.tutorial.onEvent(e); // 튜토리얼 완료 판정 (치명타·스킬·낙사 등)
  }

  drainEvents() {
    const out = this.events;
    this.events = [];
    return out;
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
      else if (p && C.GHOST_DROP_BOTS && this.ghostCd(p) === 0) brain.ghostDrop(this, p); // 죽은 봇의 유령 투하 (봇 판 비교용)
    }
    for (const [id, brain] of this.proxies) {
      const p = this.players.get(id);
      if (p && p.alive && this.onField(p)) brain.update(this, p); // 끊긴 사람 대리 (블록 마스터의 마스터는 필드 밖이라 안 움직임)
    }
    this.updatePieces();
    let remaining = dt;
    while (remaining > 0) {
      const h = Math.min(remaining, C.MAX_STEP_DT);
      for (const p of this.players.values()) if (this.onField(p)) this.integratePlayer(p, h);
      remaining -= h;
    }
    for (const p of this.players.values()) if (p.grounded && p.alive && this.onField(p)) p.lastGround = this.groundKind(p);
    this.updateCombat();
    if (this.hpMode) this.hpKnockouts();
    for (const p of this.players.values()) {
      if (this.onField(p) && p.z < C.FALL_DEATH_Z) this.kill(p, 'fall');
    }
    if (this.mode === 'kills') {
      for (const p of this.participants()) if (!p.alive && p.respawnAt && this.time >= p.respawnAt) this.respawn(p);
    }
    if (this.mode === 'practice') this.updatePractice();
    if (this.tutorial) this.tutorial.update(dtMs);
    this.updateLava(dtMs);
    this.updateItems();
    this.updateProjectiles(dt);
    if (this.shells.length) this.updateShells(dt);
    if (this.notes.length) this.updateNotes(dt);
    this.updateBombs();
    if (C.ROUND_TIME_LIMIT_MS > 0 && this.time - this.roundStartTime >= C.ROUND_TIME_LIMIT_MS) {
      this.log('  시간 초과 → 무승부');
      this.endRound(null);
      return;
    }
    this.checkRoundEnd();
  }
}

// 메서드 묶음 (server/game-*.js · char-*.js) 을 Game 에 붙임. 같은 이름이 두 곳에 있으면 바로 에러
for (const part of [GridPart, PlayersPart, RoundPart, InputPart, CombatPart, TankPart, NinjaPart, HunterPart, BardPart, BerserkerPart, CannonPart, BuilderPart, HookPart, ItemsPart, PiecesPart, PlacementPart, PhysicsPart, PracticePart, SnapshotPart]) {
  for (const [name, desc] of Object.entries(Object.getOwnPropertyDescriptors(part.prototype))) {
    if (name === 'constructor') continue;
    if (Object.hasOwn(Game.prototype, name)) throw new Error(`Game.${name} 이 두 곳에 있음 (${part.name})`);
    Object.defineProperty(Game.prototype, name, desc);
  }
}

// 서버 시작 때 블록 자리 고르기를 몇 번 돌려 JIT 를 데움 (2026-10-26: 서버를 켠 뒤 첫 판의 첫 하늘 블록이 차가운 상태라 한 틱 20~40ms).
// 판 크기마다 평지에서 하늘 사슬 첫 블록·이어 붙이기·자동 블록. 결과는 버림 (약 0.1~0.3초)
export function warmUpPlacement(rounds = 3) {
  for (const size of Object.values(C.FIELD_SIZES)) {
    const g = new Game(() => {}, { skyStairs: true });
    g.sky = true;
    g.setFieldSize(size);
    for (let k = 0; k < rounds; k++) {
      const a = g.chooseSkyPlacement(null);
      if (a) g.chooseSkyPlacement(a);
      g.chooseAutoPlacement(SHAPE_NAMES[0]);
    }
  }
}
