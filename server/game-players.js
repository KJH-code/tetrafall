// Game 메서드 묶음: 플레이어 관리·대기실 설정·팀전·끊김 (봇 대리). server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { BotBrain } from './bot.js';
import { MAP_IDS, mapColumns } from './maps.js';
import { maxPlayers, BOT_LEVEL_KO, TEAM_KO } from './game-util.js';

export class PlayersPart {
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
    const sp = this.spawnPoints[slot % this.spawnPoints.length];
    const p = {
      id,
      slot,
      color: this.freeColor(), // 색 (PLAYER_PALETTE 번호). 처음엔 빈 색 중 앞의 것, 사람은 대기실에서 바꿈 (setColor)
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
      airDashes: C.AIR_DASHES, // 남은 공중 대시 (땅에 닿으면 다시 채움)
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
      killStreak: 0, // 죽지 않고 이어 낸 킬 수 (kill 이벤트 streak, 죽으면 0)
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
      marks: new Map(), // 사냥꾼 표식 (이 사람에게 붙은): 사냥꾼 id -> { n, at }
      leap: null, // 사냥꾼 F: { at(도약 시작), target, endAt, vx, vy }
      windup: null, // 이동 스킬 지상 준비 (닌자·탱크·갈고리 F): { at(나가는 시각), yaw(누른 순간 방향) }
      hookFly: null, // 갈고리 F 날아가는 중: { at(닿는 시각), yaw }
      huntAim: null, // 사냥꾼 R 조준: { at(쏘는 시각) }
      rush: null, // 광전사 F 도약: { endAt(도약 끝), vx, vy, landBy(이때까지 안 닿으면 충격파 없음) }
      spin: null, // 광전사 R 회전: { endAt, nextTick, rage(R 시작 때 피해 %) }
      form: 'bard', // 바드 폼: 'bard'(음유시인) / 'metal'
      glideUntil: 0, // 바드 음유 공중 평타 천천히 낙하 끝 시각
      glideCount: 0, // 착지 뒤 천천히 낙하 횟수 (BARD_GLIDE_MAX_PER_AIR)
      dive: null, // 바드 메탈 기타 꽂기 낙하: { until, def }
      diveUsed: false, // 착지 전 기타 꽂기 썼나
      amp: null, // 바드 메탈 R 앰프: { endAt, nextTick }
      slowUntil: 0, // 둔화 (바드 음파) 끝 시각
      vulnUntil: 0, // 넉백 취약 (바드 취약의 노래) 끝 시각
      cannonAmmo: C.CANNON_AMMO_MAX, // 대포수 탄 (판 시작·부활 때 가득)
      reloadAt: 0, // 대포수 다음 한 발 장전 시각 (0 = 가득)
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

  // 방에서 아무도 안 쓰는 색 중 가장 앞 번호 (자리가 팔레트보다 많을 일은 없지만 다 쓰였으면 0)
  freeColor() {
    const used = new Set([...this.players.values()].map((p) => p.color));
    for (let c = 0; c < C.PLAYER_PALETTE.length; c++) if (!used.has(c)) return c;
    return 0;
  }

  // 색 고르기 (2026-10-27 재혁): 판 사이에만, 팔레트 안 번호, 방에서 다른 사람이 쓰는 색은 안 됨 (먼저 고른 사람 우선).
  // 팀전이어도 받아 둠 (팀전 몸 색은 화면이 팀 계열로 칠함, 고른 색은 개인전에서). 되면 true
  setColor(id, raw) {
    const p = this.players.get(id);
    const c = raw; // 숫자만 (null·문자열은 거절)
    if (!p || this.inRound() || !Number.isInteger(c) || c < 0 || c >= C.PLAYER_PALETTE.length) return false;
    if (c === p.color) return true;
    if ([...this.players.values()].some((o) => o !== p && o.color === c)) return false;
    p.color = c;
    this.log(`${p.name} 색: ${c}`);
    return true;
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

  // 접속 끊김·복귀 (server/rooms.js 가 부름): 자리는 그대로, 끊긴 동안 봇이 대신 조종 (판정 특혜 없음). 돌아오면 바로 돌려받고 입력은 멈춤
  setAway(id, on) {
    const p = this.players.get(id);
    if (!p || p.isBot || !!p.away === !!on) return false;
    p.away = !!on;
    if (on) {
      this.proxies.set(id, new BotBrain(() => this.rng(), () => this.botLevel));
      this.log(`  [끊김] ${p.name} 자리 유지 ${C.RECONNECT_GRACE_MS / 1000}초${this.inRound() ? ' (봇 대리)' : ''}`);
    } else {
      this.proxies.delete(id);
      p.input.fwd = 0;
      p.input.strafe = 0;
      p.input.jump = false;
      this.log(`  [복귀] ${p.name}`);
    }
    return true;
  }

  humanCount() {
    return [...this.players.values()].filter((p) => !p.isBot).length;
  }

  removePlayer(id) {
    const p = this.players.get(id);
    if (!p) return;
    this.players.delete(id);
    this.bots.delete(id);
    this.proxies.delete(id);
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
    if (choice !== 'random' && !MAP_IDS.includes(choice)) return false;
    if (this.mode === 'practice' && this.inRound()) return this.practiceMap(choice); // 연습은 판 중에도 바로
    if (this.inRound()) return false;
    this.mapChoice = choice;
    return true;
  }

  // 연습: 지형을 바로 바꿈. 쌓인 블록·건축가 블록·떨어지던 블록·아이템은 치우고 모두 제자리로 (피해 % 는 설정값)
  practiceMap(choice) {
    this.mapChoice = choice;
    const mapId = choice === 'random' ? MAP_IDS[Math.floor(this.rng() * MAP_IDS.length)] : choice;
    const cells = [];
    for (const [x, y, h] of mapColumns(mapId, this.W, this.D)) for (let z = 0; z < h; z++) cells.push([x, y, z, CELL.TERRAIN]);
    return this.resetArena(mapId, cells);
  }

  // 연습·튜토리얼: 지형을 cells ([x, y, z, 칸 값]) 로 새로 깔고 나머지(블록·아이템·용암 등)는 치움, 모두 제자리로
  resetArena(mapId, cells) {
    this.mapId = mapId;
    this.grid = new Uint8Array(this.W * this.D * this.H);
    this.gridPiece = new Int32Array(this.grid.length);
    for (const [x, y, z, v] of cells) if (this.inXY(x, y) && z >= 0 && z < this.H) this.grid[this.idx(x, y, z)] = v;
    this.baseAvgHeight = this.avgHeight();
    this.pieces = [];
    this.refreshPieceCells();
    this.bblocks = new Map();
    this.bigBombs = [];
    for (const q of this.quakes) this.emit({ type: 'quakeFall', id: q.id, gone: [], cells: [] }); // 버리는 솟는 땅
    this.quakes = [];
    this.holes = [];
    this.items = [];
    this.bombs = [];
    this.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
    this.gridVersion++;
    this.gridDirty = true;
    for (const p of this.participants()) if (p.alive || p.dummy) this.practiceReset(p, null);
    this.emit({ type: 'mapChange', map: this.mapId });
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

  // 하늘 계단 켜고 끄기 (판 사이에만)
  setSkyStairs(on) {
    if (this.inRound() || this.skyStairs === !!on) return false;
    this.skyStairs = !!on;
    this.log(`[호스트] 하늘 계단 ${on ? '켬' : '끔'}`);
    return true;
  }

  // 체력전 켜고 끄기 (판 사이에만, 연습 방은 안 됨)
  setHpMode(on) {
    if (this.inRound() || this.mode === 'practice' || this.hpMode === !!on) return false;
    this.hpMode = !!on;
    this.log(`[호스트] 체력전 ${on ? '켬' : '끔'}`);
    return true;
  }

  // 체력전 최대 HP: 모드별 (HP_MAX_BY_MODE)
  hpMax() {
    return C.HP_MAX_BY_MODE[this.mode] ?? C.HP_MAX_BY_MODE.survival;
  }

  // 체력전: HP (hpMax − 피해 %) 가 0 이하인 사람은 그 자리에서 KO (마지막으로 때린 사람 킬, lastHit). 틱마다 전투 뒤에
  hpKnockouts() {
    const max = this.hpMax();
    for (const p of this.players.values()) if (p.alive && this.onField(p) && p.damage >= max) this.kill(p, 'hp');
  }

  // 캐릭터 고르기 (판 사이에만, 같은 캐릭터 여럿 됨)
  setChar(id, c) {
    const p = this.players.get(id);
    const live = this.mode === 'practice' && this.inRound(); // 연습은 판 중에도 바로
    if (!p || !this.characters || p.dummy || (this.inRound() && !live) || !C.CHARACTERS.includes(c) || p.char === c) return false;
    p.char = c;
    this.log(`${p.name} 캐릭터: ${C.CHAR_NAMES[c]}`);
    if (live && p.alive) {
      // 캐릭터별 상태(쿨·게이지·탄·장전·표식·준비 중 기술)를 되살아날 때처럼 새로, 위치·피해 % 는 그대로
      const keep = { x: p.x, y: p.y, z: p.z, yaw: p.yaw, pitch: p.pitch, vz: p.vz, kbx: p.kbx, kby: p.kby, grounded: p.grounded, damage: p.damage };
      if (p.grab) this.hookGrabDrop(p);
      this.respawn(p);
      Object.assign(p, keep, { shieldUntil: 0, skillReadyAt: 0, ult: 0 });
      this.emit({ type: 'charChange', who: p.id, char: c });
    }
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
      x: this.W / 2,
      y: this.D / 2,
      z: this.H + 4,
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
          if (own.has(nx * 100 + ny) || !this.inXY(nx, ny)) continue;
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
        if (this.inXY(cx, cy)) top = Math.max(top, this.columnTop(cx, cy));
      }
    }
    return top;
  }

  isHost(id) {
    return this.hostId === id;
  }

  canStart() {
    const ps = this.participants();
    if (this.mode === 'practice') return ps.length >= 1 && !this.inRound(); // 연습: 혼자도
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
      .slice(0, C.TEXT_RAW_MAX) // 먼저 자름 (긴 문자열 통째로 정규식을 돌리면 틱이 멈춤, 2026-10-30 감사)
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
}
