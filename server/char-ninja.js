// Game 메서드 묶음: 캐릭터: 닌자. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { cellKey } from './game-util.js';

export class NinjaPart {
  // ---- 닌자 ----
  // 순간 베기: 보는 방향으로 NINJA_BLINK_DIST 만큼 (블록 앞까지, 상대가 있으면 그 바로 뒤까지) 순간이동하며 지나간 길의 상대를 벰 (한 사람 한 번).
  // 공중에서도 됨 (복귀). 블록에 막히면 벽 차기: 위로 튀어 오름 + 작은 충격파 (벽 통과 없음)
  ninjaBlink(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const from = { x: p.x, y: p.y, z: p.z };
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
}
