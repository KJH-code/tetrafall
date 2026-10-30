// Game 메서드 묶음: 캐릭터: 탱크. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { cellKey, overlapsCell } from './game-util.js';

export class TankPart {
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
        if (d <= r0 || d > r1 || !this.inXY(x, y)) continue;
        const z = this.columnTop(x, y);
        if (z >= this.H || Math.abs(z - p.z) > 2.5 || this.pieceCells.has(cellKey(x, y, z))) continue;
        this.grid[this.idx(x, y, z)] = CELL.BUILD;
        cells.push([x, y, z]);
      }
    }
    if (!cells.length) return 0;
    this.gridChanged();
    const qid = (this.quakeCounter = (this.quakeCounter || 0) + 1); // 솟는 땅 id (quakeRise·quakeFall 짝, 층 클리어로 칸이 옮겨지거나 지워져도 그대로)
    this.quakes.push({ id: qid, cells, at: this.time + C.TANK_RING_MS });
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.onField(t) || !cells.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t)) continue;
      const hit = this.applyKnockback(t, t.x - p.x, t.y - p.y, 0, C.TANK_RING_UP, C.TANK_RING_STUN_MS, 0, { by: p.id, kind: 'slam' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'quake', by: p.id, target: t.id, ok: hit });
    }
    this.emit({ type: 'quakeRise', id: qid, who: p.id, cells, ms: C.TANK_RING_MS });
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
      this.emit({ type: 'quakeFall', id: q.id, gone, cells: gone }); // cells 는 예전 이름 (gone 과 같음)
    }
  }
}
