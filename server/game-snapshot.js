// Game 메서드 묶음: 스냅샷 (서버 → 화면). server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { MAPS } from './maps.js';

export class SnapshotPart {
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
        ghostBy: piece.ghostBy || null, // 유령 투하: 떨어뜨린 사람 id
        ghostSlot: piece.ghostBy ? piece.ghostSlot : null, // 그 사람 자리
        ghostColor: piece.ghostBy ? piece.ghostColor : null, // 그 사람 색 (PLAYER_PALETTE 번호)
        sky: !!piece.sky, // 하늘 계단 블록
        landZ: piece.landZ,
        fits: piece.fits,
        shadow: piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]),
        shadowVisible: this.shadowVisible(piece, eta),
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
        killsTarget: this.mode === 'kills' ? this.killsTarget : undefined, // 킬 점수전 목표 (판마다 인원으로 정함)
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
        away: !!p.away, // 접속 끊김 (자리 유지 중, 판 중이면 봇 대리)
        color: p.color, // PLAYER_PALETTE 번호
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
        airDashes: p.airDashes, // 남은 공중 대시 (공중에서 0 이면 Shift 안 됨)
        dummy: !!p.dummy, // 연습 허수아비
        ghostCd: this.ghostCd(p), // 유령 투하: null = 지금 못 함 (살아 있음·모드 아님), 0 = 바로, 아니면 남은 쿨 ms
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
        hp: this.hpMode ? Math.max(0, this.hpMax(p) - p.damage) : undefined, // 체력전: 남은 HP (켰을 때만)
        hpMax: this.hpMode ? this.hpMax(p) : undefined, // 체력전: 이 사람 최대 HP (캐릭터 배율 HP_CHAR_MULT)
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
        ultMax: this.ultMax(p), // 필살기 게이지 필요량 (사냥꾼 2배)
        cannon: p.char === 'cannon' ? { ammo: p.cannonAmmo, max: C.CANNON_AMMO_MAX, reloadLeft: p.reloadAt ? Math.max(0, p.reloadAt - this.time) : 0, reloadMs: C.CANNON_RELOAD_MS } : undefined, // 대포수 탄·장전
        bard: p.char === 'bard' ? { form: p.form, glideLeft: p.glideUntil ? Math.max(0, p.glideUntil - this.time) : 0, glidesLeft: Math.max(0, C.BARD_GLIDE_MAX_PER_AIR - p.glideCount), ampLeft: p.amp ? Math.max(0, p.amp.endAt - this.time) : 0, ampMs: C.BARD_AMP_MS, ampYaw: p.amp ? this.ampYaw(p) : null } : undefined, // 바드 폼·천천히 낙하·앰프
        slowLeft: Math.max(0, p.slowUntil - this.time), // 둔화 남은 ms (바드 음파)
        vulnLeft: Math.max(0, p.vulnUntil - this.time), // 넉백 취약 남은 ms (바드 취약의 노래, 머리 위 음표)
        berserker: p.char === 'berserker' ? { rage: this.rageMult(p.damage), spinLeft: p.spin ? Math.max(0, p.spin.endAt - this.time) : 0, spinMs: C.BERSERKER_SPIN_MS, spinRage: p.spin ? this.rageMult(p.spin.rage) : 0 } : undefined, // 광전사 분노 배율·회전
        ultTarget: p.char === 'hunter' ? this.onField(p) && this.shotTargets(p).some((t) => !this.lineBlocked(p, t)) : undefined, // 사냥꾼: 지금 R 쏠 대상이 있나 (R 버튼 회색)
        marks: [...p.marks].map(([by, m]) => ({ by, n: m.n, left: Math.max(0, C.HUNTER_MARK_MS - (this.time - m.at)) })), // 이 사람에게 붙은 사냥꾼 표식
        respawnIn: !p.alive && p.respawnAt ? Math.max(0, p.respawnAt - this.time) : null,
        shieldLeft: Math.max(0, p.shieldUntil - this.time),
        score: this.scores.get(p.id) || 0,
      })),
      pieces: piecesOut,
      nextSpawnIn,
      lava: { active: this.lava.active, z: this.lava.z },
      itemTimers: this.itemTimers(),
      itemsEnabled: C.ITEMS_ENABLED || this.controlItemOn(), // 필드에 아이템이 나오는 판인지 (false 면 화면의 우클릭 아이템 칸·다음 아이템 타이머 숨김)
      botLevel: this.botLevel,
      teamMode: this.teamMode,
      practice: this.mode === 'practice' ? this.practiceSnapshot() : null,
      tutorial: this.tutorial ? this.tutorial.snapshot() : null, // 튜토리얼 진행 (단계·해냄·끝) // 연습 모드 토글·허수아비 콤보 기록
      skyStairs: this.skyStairs, // 대기실 옵션 (이번 판에 도는지는 field.h 가 SKY_GRID_H 인지로도 앎)
      hpMode: this.hpMode || undefined, // 체력전 (켰을 때만 실음 — 끄면 스냅샷이 예전과 같게)
      hpMax: this.hpMode ? this.hpMax() : undefined, // 지금 모드의 최대 HP (HP_MAX_BY_MODE, 캐릭터 배율 전 — 사람마다는 players[].hpMax)
      teamWins: this.teamWins,
      mode: this.mode,
      teamScores: this.teamScores,
      map: { choice: this.mapChoice, id: this.mapId, name: MAPS[this.mapId].name },
      items: this.items,
      projectiles: this.projectiles.map((pr) => ({ x: pr.x, y: pr.y, z: pr.z })),
      shells: this.shells.map((sh) => ({ id: sh.id, owner: sh.owner, big: sh.big, x: sh.x, y: sh.y, z: sh.z, dir: sh.dir })), // 대포수 포탄 (보통·대형)
      notes: this.notes.map((nt) => ({ id: nt.id, owner: nt.owner, x: nt.x, y: nt.y, z: nt.z, dir: nt.dir })), // 바드 류트 음파
      bombs: this.bombs.map((b) => ({ id: b.id, x: b.x, y: b.y, z: b.z, left: Math.max(0, b.explodeAt - this.time) })),
      bblocks: [...this.bblocks.values()].map((b) => ({ x: b.x, y: b.y, z: b.z, owner: b.owner, kind: b.kind, group: b.group, left: b.kind === 'big' ? Math.max(0, (this.bigBombs.find((x) => x.group === b.group)?.at ?? this.time) - this.time) : Math.max(0, b.expiresAt - this.time) })), // 건축가 블록 (B: 색·깜빡임·묶음)
      gridVersion: this.gridVersion,
      field: { w: this.W, d: this.D, h: this.H }, // 판 크기 (인원별, FIELD_SIZES). grid 배열은 (z * d + y) * w + x
    };
    if (includeGrid || this.gridDirty) {
      out.grid = Array.from(this.grid);
      this.gridDirty = false;
    }
    return out;
  }
}
