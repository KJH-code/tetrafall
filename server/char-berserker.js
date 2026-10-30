// Game 메서드 묶음: 캐릭터: 광전사. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';

export class BerserkerPart {
  // ---- 광전사 (2026-10-26, docs/characters.md 3.7) ----
  // 분노 배율: 피해 % 에 비례, 상한 없음
  rageMult(damage) {
    return 1 + damage * C.BERSERKER_RAGE_PER_PERCENT;
  }

  // F 광폭 도약: 보는 방향으로 크게 뜀 → 땅에 닿으면 착지 충격파 (berserkerLeapUpdate)
  berserkerLeap(p) {
    const sec = C.BERSERKER_LEAP_MS / 1000;
    const v = C.BERSERKER_LEAP_DIST / sec;
    p.rush = { endAt: this.time + C.BERSERKER_LEAP_MS, vx: Math.cos(p.yaw) * v, vy: Math.sin(p.yaw) * v, landBy: this.time + C.BERSERKER_LEAP_MS + C.BERSERKER_LEAP_LAND_MS };
    p.vz = C.BERSERKER_LEAP_UP;
    p.grounded = false;
    p.kbx = 0;
    p.kby = 0;
    const to = { x: p.x + Math.cos(p.yaw) * C.BERSERKER_LEAP_DIST, y: p.y + Math.sin(p.yaw) * C.BERSERKER_LEAP_DIST, z: p.z };
    this.emit({ type: 'rush', who: p.id, from: { x: p.x, y: p.y, z: p.z }, to, ms: C.BERSERKER_LEAP_MS });
    this.log(`  [스킬] ${p.name} 광폭 도약`);
    return true;
  }

  berserkerLeapUpdate(p) {
    if (this.time < p.rush.endAt) return;
    if (!p.grounded) {
      if (this.time >= p.rush.landBy) p.rush = null; // 너무 오래 떨어짐 (낭떠러지): 충격파 없음
      return;
    }
    p.rush = null;
    const hits = [];
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.BERSERKER_WAVE_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), C.BERSERKER_WAVE_KB_SPEED, C.BERSERKER_WAVE_KB_UP, C.BERSERKER_WAVE_STUN_MS, C.BERSERKER_WAVE_DAMAGE, { by: p.id, kind: 'leapwave' }, true);
      this.emit({ type: 'hit', kind: 'leapwave', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
      if (hit) hits.push(`${t.name} ${t.damage}%`);
    }
    if (hits.length && p.chainN > 0) p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS; // F → 평 평
    this.emit({ type: 'rushLand', who: p.id, x: p.x, y: p.y, z: p.z, r: C.BERSERKER_WAVE_RANGE });
    this.log(`  [스킬] ${p.name} 착지 충격파${hits.length ? ` → ${hits.join(', ')}` : ''}`);
  }

  // R 분노 소용돌이: 피해 % 를 깎고 (최대 BERSERKER_RAGE_CUT), 깎은 뒤 피해 % 를 마지막 날림 분노로 기억 (2026-10-26 재혁 가: 쓰면 분노가 식음)
  berserkerSpin(p) {
    const before = p.damage;
    const cut = Math.min(C.BERSERKER_RAGE_CUT, p.damage);
    p.damage -= cut;
    const rage = p.damage;
    p.spin = { endAt: this.time + C.BERSERKER_SPIN_MS, nextTick: this.time, rage };
    this.emit({ type: 'spin', who: p.id, ms: C.BERSERKER_SPIN_MS, rage: this.rageMult(rage), cut, damage: p.damage });
    this.log(`  [필살] ${p.name} 분노 소용돌이 (분노 ×${this.rageMult(rage).toFixed(2)}, 피해 ${before}% → ${p.damage}%)`);
  }

  berserkerSpinUpdate(p) {
    const S = p.spin;
    if (this.time >= S.nextTick && this.time < S.endAt) {
      S.nextTick += C.BERSERKER_SPIN_TICK_MS;
      for (const t of this.players.values()) {
        if (!this.foe(p, t)) continue;
        const dx = t.x - p.x;
        const dy = t.y - p.y;
        const d = Math.hypot(dx, dy);
        if (d > C.BERSERKER_SPIN_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
        // 작은 밀침: 바깥으로 (빨아들이지 않음), 고정 넉백, 연타로 침 (시간 마무리 안 됨)
        const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), C.BERSERKER_SPIN_TICK_KB, C.BERSERKER_SPIN_TICK_UP, C.BERSERKER_SPIN_TICK_STUN_MS, C.BERSERKER_SPIN_TICK_DAMAGE, { by: p.id, kind: 'spin' }, false, { fixed: true, chained: true });
        this.emit({ type: 'hit', kind: 'spin', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
      }
    }
    if (this.time < S.endAt) return;
    p.spin = null;
    const hits = [];
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.BERSERKER_SPIN_END_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), C.BERSERKER_SPIN_END_KB_SPEED, C.BERSERKER_SPIN_END_KB_UP, C.BERSERKER_SPIN_END_STUN_MS, C.BERSERKER_SPIN_END_DAMAGE, { by: p.id, kind: 'spinend', rage: S.rage }, true, { finish: true });
      this.emit({ type: 'hit', kind: 'spinend', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
      if (hit) hits.push(`${t.name} ${t.damage}%`);
    }
    this.emit({ type: 'spinEnd', who: p.id, x: p.x, y: p.y, z: p.z, r: C.BERSERKER_SPIN_END_RANGE, rage: this.rageMult(S.rage) });
    this.log(`  [필살] ${p.name} 소용돌이 끝${hits.length ? ` → ${hits.join(', ')}` : ''}`);
  }
}
