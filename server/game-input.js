// Game 메서드 묶음: 입력·행동·이모트. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';

export class InputPart {
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
        if (stunned || controlling || p.amp || this.time < p.dashReadyAt) return; // 조종 중 대시 불가. 바드 앰프 연주 중도 (제자리 규칙, 2026-10-30 재혁 S2: 예전엔 대시로 0.75칸 움직였음. 광전사 회전 중 대시는 됨)
        if (!p.grounded && p.airDashes <= 0) return; // 공중 대시는 착지 전 AIR_DASHES 번까지
        this.dash(p);
        return;
      case 'push':
        if (stunned || controlling || p.spin || p.amp) return; // 조종 중 공격 불가, 광전사 회전·바드 앰프 중 불가
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
        if (stunned || controlling || !p.char || p.ult < this.ultMax(p)) return;
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
}
