// Game 메서드 묶음: 판 흐름: 시작·끝·사망·부활·점수. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { MAPS, MAP_IDS, mapColumns } from './maps.js';
import { fmtTime, byCount, shareText, BOT_LEVEL_KO, TEAM_KO, LANDED_LOG, emptyLanded, GROUND_LOG, WEAPON_LOG, causeKo } from './game-util.js';

export class RoundPart {
  // ---------- 판 흐름 ----------
  startRound() {
    if (!this.canStart()) return false;
    const fielded = this.participants().length - (this.mode === 'master' ? 1 : 0);
    this.sky = this.skyStairs && this.mode !== 'master'; // 블록 마스터는 자동 블록이 없음
    this.skyTops = [];
    this.skyChains = byCount(C.SKY_CHAINS, fielded);
    this.skyLavaMs = byCount(C.SKY_LAVA_TRIGGER_BY_COUNT, fielded);
    this.setFieldSize(this.fieldSizeFor(fielded));
    this.mapId = this.mapChoice === 'random' ? MAP_IDS[Math.floor(this.rng() * MAP_IDS.length)] : this.mapChoice;
    for (const [x, y, h] of mapColumns(this.mapId, this.W, this.D)) {
      for (let z = 0; z < h && z < this.H; z++) this.grid[this.idx(x, y, z)] = CELL.TERRAIN;
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
    const oldQuakes = this.quakes; // 판 시작 때 버리는 솟는 땅 → 아래 events 를 비운 뒤 quakeFall 로 알림
    this.quakes = []; // 탱크 R 솟는 땅 (잠깐 솟았다 가라앉음): { id, cells: [[x,y,z]], at }
    this.shells = []; // 대포수 포탄 (보통·대형)
    this.notes = []; // 바드 류트 음파
    this.shellCounter = this.shellCounter || 0;
    this.bgroup = 0;
    this.bombCounter = 0;
    this.lastDeath = null;
    this.deaths = [];
    this.landed = emptyLanded();
    this.events = [];
    for (const q of oldQuakes) this.emit({ type: 'quakeFall', id: q.id, gone: [], cells: [] }); // 화면에서 그 솟는 땅을 지우게
    this.winnerId = null;
    this.winnerTeam = null;
    this.winnerIds = [];
    this.scores = new Map();
    this.teamScores = { red: 0, blue: 0 };
    this.roundNumber++;
    for (const p of this.players.values()) {
      const sp = this.spawnPoints[p.slot % this.spawnPoints.length];
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
        lastGround: null, // 마지막으로 밟은 칸 종류 (GROUND_LOG, 사망 로그 "밟은 칸")
        alive: !p.spectator,
        stunUntil: 0,
        freezeUntil: 0,
        jumpUntil: 0,
        airJumps: C.AIR_JUMPS,
        airDashes: C.AIR_DASHES,
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
        marks: new Map(),
        leap: null,
        windup: null,
        hookFly: null,
        huntAim: null,
        rush: null,
        spin: null,
        form: 'bard',
        glideUntil: 0,
        glideCount: 0,
        dive: null,
        diveUsed: false,
        amp: null,
        slowUntil: 0,
        vulnUntil: 0,
        cannonAmmo: C.CANNON_AMMO_MAX,
        reloadAt: 0,
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
      Object.assign(m, { master: true, x: this.W / 2, y: this.D / 2, z: this.H + 4 });
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
    this.log(`===== ROUND ${this.roundNumber} 시작 (${ps.length}명: ${ps.sort((a, b) => a.slot - b.slot).map((p) => p.name).join(' ')}, 맵 ${MAPS[this.mapId].log}${lv}) =====`); // 참가자 목록은 npm run stats 가 구성별로 셀 때 씀. 맵은 예전 이름 (log) 그대로 — 화면 이름은 MAPS name
    if (this.teamMode) this.log(`  팀: ${this.teamLine()}`); // npm run stats 가 팀 승리를 사람별로 나눌 때 씀
    if (this.sky) this.log('  하늘 계단: 켬'); // npm run stats 가 켬/끔을 나눠 봄 (끔은 예전 로그와 같게 안 찍음)
    if (this.hpMode) this.log(`  체력전: 켬 (HP ${C.HP_MAX})`); // npm run stats 가 켬/끔을 나눠 봄 (끔은 안 찍음)
    if (this.characters) this.log(`  캐릭터: ${ps.map((p) => `${p.name} ${C.CHAR_NAMES[p.char]}`).join(' / ')}`); // npm run stats 캐릭터별 승률
    // 모드 줄 (생존은 예전 로그와 같게 안 찍음). npm run stats 가 모드별로 셈
    if (this.mode === 'master') {
      this.roundEndsAt = this.time + C.MASTER_TIME_MS;
      const m = this.master(); // 카운트다운 중에 마스터가 나갔으면 없음 → 아래 checkRoundEnd 가 생존자 승으로 끝냄 (2026-10-30 감사: 예전엔 여기서 예외로 서버가 죽음)
      this.log(`  모드: ${C.MODE_NAMES.master} (${m ? `마스터 ${m.name}` : '마스터가 나감'}, ${fmtTime(C.MASTER_TIME_MS)} 버티기)`); // '마스터 이름,' 모양은 npm run stats 가 읽음
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
    // 판을 끝낸 죽음 (화면: 마지막 킬 슬로모션). FINAL_KILL_WINDOW_MS 안의 죽음만 (판정·서버 시간과 상관없는 화면 연출용)
    const d = this.lastDeath;
    if (d && this.time - d.at <= C.FINAL_KILL_WINDOW_MS) this.emit({ type: 'finalKill', ...d, winners: (winners || (winner ? [winner] : [])).map((p) => p.id), winnerTeam });
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
    this.log(`  블록: ${Object.entries(this.landed).map(([k, n]) => `${LANDED_LOG[k]} ${n}`).join(' / ')}`);
    this.log(`  지형 변화: 남은 칸 ${this.grid.reduce((n, v) => n + (v && v !== CELL.TERRAIN ? 1 : 0), 0)} / 평균 높이 +${(this.avgHeight() - this.baseAvgHeight).toFixed(2)}`); // 판 끝에 시작 지형 말고 남은 블록 칸 (층 클리어·사라진 건축가 블록은 빠짐)
    if (this.mode === 'master') {
      const m = this.master();
      this.log(`  결과: ${list.some((p) => p.master) ? `마스터 ${m.name} 승 (생존자 전멸)` : list.length ? `생존자 ${list.length}명 승` : '무승부'}`);
      // 마스터 편으로 넘어갔던 사람은 원래대로 (죽은 상태), 하늘에 떠 있던 다음 블록들은 치움
      for (const z of this.players.values()) if (z.zombie) Object.assign(z, { master: false, zombie: false, alive: false });
      this.pieces = this.pieces.filter((pc) => pc.phase !== 'control');
      this.refreshPieceCells();
      if (m) {
        // 판이 끝나면 마스터도 필드 가운데 꼭대기로 내려와 보통 사람처럼 (승리 연출·이모트)
        const cx = Math.floor(this.W / 2);
        const cy = Math.floor(this.D / 2);
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
    if (this.mode === 'practice') return; // 연습 판은 안 끝남
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
    for (let x = 0; x < this.W; x++) {
      for (let y = 0; y < this.D; y++) {
        const top = this.columnTop(x, y);
        if (top <= this.H - 3 && !busy.has(x * 100 + y)) cols.push({ x, y, top });
      }
    }
    if (!cols.length) return { x: this.W / 2, y: this.D / 2, z: this.columnTop(Math.floor(this.W / 2), Math.floor(this.D / 2)) };
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
      lastGround: null,
      alive: true,
      stunUntil: 0,
      freezeUntil: 0,
      jumpUntil: 0,
      airJumps: C.AIR_JUMPS,
      airDashes: C.AIR_DASHES,
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
      marks: new Map(),
      leap: null,
      windup: null,
      hookFly: null,
      huntAim: null,
      rush: null,
      spin: null,
      form: 'bard',
      glideUntil: 0,
      glideCount: 0,
      dive: null,
      diveUsed: false,
      amp: null,
      slowUntil: 0,
      vulnUntil: 0,
      cannonAmmo: C.CANNON_AMMO_MAX,
      reloadAt: 0,
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
    if (this.mode === 'practice' && (p.dummy || this.practice.noDeath)) return void this.practiceReset(p, cause); // 연습: 허수아비·안 죽음은 바로 제자리
    p.alive = false;
    p.deathCause = cause;
    p.hasControl = false;
    const t = this.time - this.roundStartTime;
    let credit = src ? { by: src.by, kind: src.kind, name: this.players.get(src.by)?.name } : p.lastHit;
    if (credit && (credit.by === p.id || !credit.name || this.sameTeam(this.players.get(credit.by), p))) credit = null; // 팀 블록에 깔려도 킬 아님
    this.deaths.push({ name: p.name, cause, t, killer: credit ? credit.name : null, weapon: credit ? credit.kind : null });
    // 화면 KO 연출: 죽은 자리 + 낙사면 떨어진 쪽 (필드 가장자리 바깥 방향 out). 판을 끝내는 죽음이면 endRound 가 finalKill 로 다시 알림
    const out = cause === 'fall' ? this.outward(p) : null;
    this.lastDeath = { who: p.id, cause, by: credit ? credit.by : null, x: p.x, y: p.y, z: p.z, out, at: this.time };
    this.emit({ type: 'death', who: p.id, cause, by: credit ? credit.by : null, weapon: credit ? credit.kind : null, byName: credit ? credit.name : null, x: p.x, y: p.y, z: p.z, out });
    const killText = credit ? `, 킬 ${credit.name} ${WEAPON_LOG[credit.kind]}` : ', 킬 없음'; // "킬 없음" 을 적어야 킬 기록이 없던 옛 로그와 구분됨
    // 밟은 칸: 죽기 전 마지막으로 서 있던 칸 (시작 지형 위 싸움인지, 블록이 바꾼 지형 위인지 → npm run stats)
    this.log(`  [사망] ${p.name} ${causeKo(cause)} @ ${fmtTime(t)} (위치 ${p.x.toFixed(1)}, ${p.y.toFixed(1)}, ${p.z.toFixed(1)}, 피해 ${p.damage}%${killText}, 밟은 칸 ${GROUND_LOG[p.lastGround ?? 'none']})`);
    if (this.mode === 'kills' && this.phase === 'playing') this.scoreDeath(p, credit);
    if (this.mode === 'master' && this.phase === 'playing' && !p.master && this.master()) this.joinMasterSide(p);
    if (this.mode === 'practice') p.respawnAt = this.time + C.PRACTICE_RESPAWN_MS; // 연습 ("안 죽음" 끔): 잠깐 뒤 제자리
    p.ghostReadyAt = this.time; // 유령 투하: 죽자마자 첫 1개
  }

  // 낙사한 쪽: 필드 밖이면 가장 가까운 필드 점에서 그 사람 쪽, 필드 안이면 가장 가까운 가장자리 바깥 (단위 벡터 {x, y})
  outward(p) {
    const cx = Math.max(0, Math.min(this.W, p.x));
    const cy = Math.max(0, Math.min(this.D, p.y));
    let dx = p.x - cx;
    let dy = p.y - cy;
    if (Math.hypot(dx, dy) < 1e-6) {
      const edges = [
        [p.x, -1, 0],
        [this.W - p.x, 1, 0],
        [p.y, 0, -1],
        [this.D - p.y, 0, 1],
      ].sort((a, b) => a[0] - b[0]);
      [, dx, dy] = edges[0];
    }
    const len = Math.hypot(dx, dy) || 1;
    return { x: dx / len, y: dy / len };
  }
}
