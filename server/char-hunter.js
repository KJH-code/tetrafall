// Game 메서드 묶음: 캐릭터: 사냥꾼. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { EPS } from './game-util.js';

export class HunterPart {
  // ---- 사냥꾼 (2026-10-26, docs/characters.md 3.5) ----
  // R 게이지 필요량 (사냥꾼은 HUNTER_ULT_MULT 배)
  ultMax(p) {
    return C.ULT_MAX * (p && p.char === 'hunter' ? C.HUNTER_ULT_MULT : 1);
  }

  // 표식 +1 (최대 HUNTER_MARK_MAX), 쌓인 시각 갱신
  addMark(p, t) {
    const m = t.marks.get(p.id) || { n: 0, at: 0 };
    m.n = Math.min(C.HUNTER_MARK_MAX, m.n + 1);
    m.at = this.time;
    t.marks.set(p.id, m);
    this.emit({ type: 'mark', by: p.id, target: t.id, n: m.n });
    this.log(`  [표식] ${p.name} → ${t.name} ${m.n}개`);
  }

  markOf(p, t) {
    return t.marks.get(p.id)?.n || 0;
  }

  // 마지막으로 쌓인 뒤 HUNTER_MARK_MS 지난 표식은 사라짐
  expireMarks(t) {
    for (const [by, m] of t.marks) {
      if (this.time - m.at < C.HUNTER_MARK_MS) continue;
      t.marks.delete(by);
      this.emit({ type: 'markGone', by, target: t.id });
    }
  }

  // 블록이 시선을 가리나 (눈 높이 → 상대 가슴, 격자 칸·떨어지는 블록)
  lineBlocked(p, t) {
    const a = { x: p.x, y: p.y, z: p.z + C.EYE_HEIGHT };
    const b = { x: t.x, y: t.y, z: t.z + C.PLAYER_HEIGHT * 0.6 };
    const len = Math.hypot(b.x - a.x, b.y - a.y, b.z - a.z);
    for (let d = 0.3; d < len - 0.3; d += 0.1) {
      const k = d / len;
      if (this.solidAt(Math.floor(a.x + (b.x - a.x) * k), Math.floor(a.y + (b.y - a.y) * k), Math.floor(a.z + (b.z - a.z) * k))) return true;
    }
    return false;
  }

  // R 대상: 보는 방향 HUNTER_SHOT_ANGLE_DEG·HUNTER_SHOT_RANGE 안 내 표식이 있는 상대 (시선 검사는 따로)
  shotTargets(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos(((C.HUNTER_SHOT_ANGLE_DEG / 2) * Math.PI) / 180);
    return [...this.players.values()].filter((t) => {
      if (!this.foe(p, t) || !this.markOf(p, t)) return false;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      return d <= C.HUNTER_SHOT_RANGE && (d < EPS || (dx * fx + dy * fy) / d >= cosHalf);
    });
  }

  // F 추적 도약: 예고 HUNTER_LEAP_WINDUP_MS 뒤 표식 있는 가장 가까운 상대에게 (없으면 보는 방향 HUNTER_LEAP_DIST)
  hunterLeap(p) {
    let target = null;
    let bd = Infinity;
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || !this.markOf(p, t) || Math.abs(t.z - p.z) > 3) continue;
      const d = Math.hypot(t.x - p.x, t.y - p.y);
      if (d <= C.HUNTER_LEAP_RANGE && d < bd) {
        bd = d;
        target = t;
      }
    }
    p.leap = { at: this.time + C.HUNTER_LEAP_WINDUP_MS, target: target ? target.id : null, endAt: 0, yaw: p.yaw };
    this.emit({ type: 'leapWarn', who: p.id, target: p.leap.target, ms: C.HUNTER_LEAP_WINDUP_MS });
    this.log(`  [스킬] ${p.name} 추적 도약 준비${target ? ` → ${target.name}` : ''}`);
    return true;
  }

  hunterLeapUpdate(p) {
    const L = p.leap;
    if (!L.endAt) {
      if (this.time < L.at) return;
      const t = L.target !== null ? this.players.get(L.target) : null;
      let to;
      if (t && this.foe(p, t)) {
        const dx = t.x - p.x;
        const dy = t.y - p.y;
        const d = Math.hypot(dx, dy) || 1;
        const go = Math.max(0, d - C.HUNTER_LEAP_BEHIND);
        to = { x: p.x + (dx / d) * go, y: p.y + (dy / d) * go };
        p.yaw = Math.atan2(dy, dx);
      } else to = { x: p.x + Math.cos(L.yaw) * C.HUNTER_LEAP_DIST, y: p.y + Math.sin(L.yaw) * C.HUNTER_LEAP_DIST };
      const sec = C.HUNTER_LEAP_MS / 1000;
      L.vx = (to.x - p.x) / sec;
      L.vy = (to.y - p.y) / sec;
      L.to = { ...to };
      L.to0 = { ...to };
      L.endAt = this.time + C.HUNTER_LEAP_MS;
      p.vz = C.HUNTER_LEAP_UP;
      p.grounded = false;
      p.kbx = 0;
      p.kby = 0;
      this.emit({ type: 'leap', who: p.id, target: L.target, from: { x: p.x, y: p.y, z: p.z }, to: { ...to, z: p.z }, ms: C.HUNTER_LEAP_MS });
      return;
    }
    if (this.time < L.endAt) {
      this.hunterLeapHome(p, L);
      return;
    }
    p.leap = null;
    const t = L.target !== null ? this.players.get(L.target) : null;
    if (!t || !this.foe(p, t) || Math.hypot(t.x - p.x, t.y - p.y) > C.HUNTER_POUNCE_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) return;
    // 덮침은 연타를 잇는 타 (재혁 "가": 평평평 → F 덮침 → 평평평): COMBO_MS 가 지나도 시간 마무리 아님. F 쿨이 있어 무한히 안 늘어남
    const hit = this.applyKnockback(t, t.x - p.x, t.y - p.y, 0, 0, C.HUNTER_POUNCE_STUN_MS, C.HUNTER_POUNCE_DAMAGE, { by: p.id, kind: 'pounce' }, false, { chained: true });
    this.emit({ type: 'hit', kind: 'pounce', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
    this.log(`  [스킬] ${p.name} 덮침 → ${t.name}${hit ? ` (${t.name} ${t.damage}%)` : ' 무적이라 무시'}`);
  }

  // 도약 유도 (재혁 "다"): 내릴 자리를 대상(앞 HUNTER_LEAP_BEHIND) 쪽으로 옮기고 (처음 자리에서 최대 HUNTER_LEAP_HOMING_MAX), 남은 시간에 맞춰 속도
  hunterLeapHome(p, L) {
    const t = L.target !== null ? this.players.get(L.target) : null;
    const left = (L.endAt - this.time) / 1000;
    if (!t || !this.foe(p, t) || left < 0.01) return; // 마지막 순간 (남은 시간 ~0) 은 그대로
    const dx = t.x - p.x;
    const dy = t.y - p.y;
    const d = Math.hypot(dx, dy) || 1;
    const go = Math.max(0, d - C.HUNTER_LEAP_BEHIND);
    const want = { x: p.x + (dx / d) * go, y: p.y + (dy / d) * go };
    let nx = L.to.x + (want.x - L.to.x) * C.HUNTER_LEAP_HOMING;
    let ny = L.to.y + (want.y - L.to.y) * C.HUNTER_LEAP_HOMING;
    const ox = nx - L.to0.x;
    const oy = ny - L.to0.y;
    const off = Math.hypot(ox, oy);
    if (off > C.HUNTER_LEAP_HOMING_MAX) {
      nx = L.to0.x + (ox / off) * C.HUNTER_LEAP_HOMING_MAX;
      ny = L.to0.y + (oy / off) * C.HUNTER_LEAP_HOMING_MAX;
    }
    L.to = { x: nx, y: ny };
    L.vx = (nx - p.x) / left;
    L.vy = (ny - p.y) / left;
    p.yaw = Math.atan2(dy, dx);
  }

  // R 처형 사격 조준: 대상이 하나도 없으면 안 쓰임 (게이지 그대로)
  hunterAim(p) {
    const ts = this.shotTargets(p).filter((t) => !this.lineBlocked(p, t));
    if (!ts.length) return false;
    p.huntAim = { at: this.time + C.HUNTER_SHOT_WINDUP_MS };
    this.emit({ type: 'aim', who: p.id, targets: ts.map((t) => t.id), ms: C.HUNTER_SHOT_WINDUP_MS });
    this.log(`  [필살] ${p.name} 처형 사격 조준 (${ts.map((t) => `${t.name} ${this.markOf(p, t)}개`).join(', ')})`);
    return true;
  }

  // 쏨 (즉시 판정): 지금 보는 방향 안 표식 대상 전부. 블록이 가리면 막힘. 표식 수만큼 세게, 표식 소모. 최대 표식 대상을 맞히면 게이지 돌려받음
  hunterShoot(p) {
    p.huntAim = null;
    const shots = [];
    let refund = false;
    for (const t of this.shotTargets(p)) {
      const n = this.markOf(p, t);
      if (this.lineBlocked(p, t)) {
        shots.push({ target: t.id, marks: n, blocked: true, to: { x: t.x, y: t.y, z: t.z + 1 } });
        continue;
      }
      const hit = this.applyKnockback(t, t.x - p.x, t.y - p.y, C.HUNTER_SHOT_KB_BASE + n * C.HUNTER_SHOT_KB_PER_MARK, C.HUNTER_SHOT_UP, C.HUNTER_SHOT_STUN_MS, n * C.HUNTER_SHOT_DAMAGE_PER_MARK, { by: p.id, kind: 'execute' }, true);
      this.emit({ type: 'hit', kind: 'execute', by: p.id, target: t.id, ok: hit, marks: n });
      if (hit) {
        t.marks.delete(p.id);
        if (n >= C.HUNTER_MARK_MAX) refund = true;
      }
      shots.push({ target: t.id, marks: n, blocked: false, ok: hit, to: { x: t.x, y: t.y, z: t.z + 1 } });
    }
    this.emit({ type: 'shot', who: p.id, from: { x: p.x, y: p.y, z: p.z + C.EYE_HEIGHT }, shots });
    if (refund) {
      p.ult = this.ultMax(p);
      this.emit({ type: 'ultRefund', who: p.id });
    }
    const txt = shots.map((x) => `${this.players.get(x.target).name} ${x.marks}개${x.blocked ? ' 막힘' : ''}`).join(', ');
    this.log(`  [필살] ${p.name} 처형 사격 (${txt || '대상 없음'})${refund ? ' 게이지 회수' : ''}`);
  }
}
