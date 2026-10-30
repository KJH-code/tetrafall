// Game 메서드 묶음: 캐릭터: 바드. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C, basicSet } from '../shared/config.js';
import { basicLabel } from './game-util.js';

export class BardPart {
  // ---- 바드 (2026-10-26, docs/characters.md 3.8) ----
  // 류트 음파: 조준 방향으로 느린 음파를 날림 (updateNotes)
  bardNote(p) {
    const cp = Math.cos(p.pitch || 0);
    const dir = { x: cp * Math.cos(p.yaw), y: cp * Math.sin(p.yaw), z: Math.sin(p.pitch || 0) };
    const nt = {
      id: ++this.shellCounter,
      owner: p.id,
      x: p.x + dir.x * 0.5,
      y: p.y + dir.y * 0.5,
      z: p.z + C.EYE_HEIGHT - 0.3 + dir.z * 0.5,
      dir,
      dieAt: this.time + (C.BARD_NOTE_RANGE / C.BARD_NOTE_SPEED) * 1000,
    };
    this.notes.push(nt);
    this.emit({ type: 'noteFire', who: p.id, id: nt.id, x: nt.x, y: nt.y, z: nt.z, dir, speed: C.BARD_NOTE_SPEED });
  }

  // 음파 이동: 처음 닿는 사람 (약한 넉백 + 둔화) 또는 블록·바닥에서 사라짐
  updateNotes(dt) {
    const def = C.BASIC_ATTACKS.bard.chain[0];
    for (const nt of [...this.notes]) {
      const sub = Math.max(1, Math.ceil((C.BARD_NOTE_SPEED * dt) / 0.15));
      const h = dt / sub;
      const r = C.BARD_NOTE_RADIUS;
      let end = null;
      for (let s = 0; s < sub && !end; s++) {
        nt.x += nt.dir.x * C.BARD_NOTE_SPEED * h;
        nt.y += nt.dir.y * C.BARD_NOTE_SPEED * h;
        nt.z += nt.dir.z * C.BARD_NOTE_SPEED * h;
        const owner = this.players.get(nt.owner);
        for (const t of this.players.values()) {
          if (!this.onField(t) || t.id === nt.owner || !owner || this.sameTeam(owner, t)) continue;
          if (!(nt.x > t.x - C.PLAYER_HALF - r && nt.x < t.x + C.PLAYER_HALF + r && nt.y > t.y - C.PLAYER_HALF - r && nt.y < t.y + C.PLAYER_HALF + r && nt.z > t.z - r && nt.z < t.z + C.PLAYER_HEIGHT + r)) continue;
          const hit = this.applyKnockback(t, nt.dir.x, nt.dir.y, def.kb, def.up, def.stun, def.dmg, { by: nt.owner, kind: 'note' }, false, { fixed: true });
          if (hit) t.slowUntil = this.time + C.BARD_SLOW_MS; // 둔화: 갱신만
          this.emit({ type: 'hit', kind: 'note', by: nt.owner, target: t.id, ok: hit, streak: hit && owner ? owner.streak : 0 });
          this.log(`  [음파] ${owner.name} → ${t.name} ${hit ? `둔화 (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
          end = 'player';
          break;
        }
        if (!end && this.solidAt(Math.floor(nt.x), Math.floor(nt.y), Math.floor(nt.z))) end = 'block';
      }
      if (!end && this.time >= nt.dieAt) end = 'expire';
      if (!end) continue;
      this.notes = this.notes.filter((x) => x !== nt);
      this.emit({ type: 'noteEnd', id: nt.id, who: nt.owner, what: end, x: nt.x, y: nt.y, z: nt.z });
    }
  }

  // 음유 공중 평타: 천천히 낙하 (integratePlayer 가 중력을 줄임)
  bardGlide(p, ms) {
    p.glideUntil = this.time + ms; // 이어 치면 다시 늘어남
    p.glideCount++;
    if (p.vz < -C.BARD_GLIDE_FALL) p.vz = -C.BARD_GLIDE_FALL;
    this.emit({ type: 'glide', who: p.id, ms });
  }

  // 천천히 낙하 음파 고리: 몸 둘레 def.range 안 상대를 바깥으로 작게 밀침 (고정 넉백). 맞힌 사람이 있으면 true
  bardGlideRing(p, n, air, def, chained) {
    const set = basicSet(p.char, p.form);
    const label = basicLabel(set, n, air, def);
    const hits = [];
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t) || this.sameTeam(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > def.range || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), def.kb, def.up, def.stun, def.dmg, { by: p.id, kind: 'glide' }, false, { fixed: true, chained });
      if (hit) {
        p.freezeUntil = this.time + C.BASIC_HITSTOP_MS;
        t.freezeUntil = this.time + C.BASIC_HITSTOP_MS;
        hits.push(t.id);
      }
      this.emit({ type: 'hit', kind: 'glide', by: p.id, target: t.id, ok: hit, n, air, finish: false, streak: hit ? p.streak : 0 });
      this.log(`  [평타] ${p.name} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'} ${label}`);
    }
    this.emit({ type: 'glideRing', who: p.id, x: p.x, y: p.y, z: p.z, r: def.range, hits });
    return hits.length > 0;
  }

  // 메탈 공중 평타 기타 꽂기 시작: 아래로 빠르게, 수평으로는 느리게
  bardDive(p, def) {
    p.dive = { until: this.time + C.BARD_DIVE_MAX_MS, def };
    p.diveUsed = true;
    p.glideUntil = 0;
    p.vz = Math.min(p.vz, -C.BARD_DIVE_SPEED);
    p.kbx *= C.BARD_DIVE_MOVE_MULT;
    p.kby *= C.BARD_DIVE_MOVE_MULT;
    this.emit({ type: 'dive', who: p.id, x: p.x, y: p.y, z: p.z, speed: C.BARD_DIVE_SPEED });
  }

  // 기타 꽂기 판정 (한 번): 내려가며 아래 상대에 닿으면 아래로 꽂음, 아니면 착지 때 발밑 충격
  bardDiveUpdate(p) {
    const D = p.dive;
    const def = D.def;
    const hitOne = (t, dx, dy, up, how) => {
      const hit = this.applyKnockback(t, dx, dy, def.kb, up, def.stun, def.dmg, { by: p.id, kind: 'push' }, true, { finish: true });
      this.emit({ type: 'hit', kind: 'push', by: p.id, target: t.id, ok: hit, n: 1, air: true, finish: true, dive: how, streak: hit ? p.streak : 0 });
      this.log(`  [평타] ${p.name} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'} 공중 기타 꽂기${how === 'land' ? ' 착지' : ''}`);
      return hit;
    };
    // 내려가며 닿음: 수평 BARD_DIVE_HIT_R 안, 상대 머리가 내 발 근처~아래
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      if (Math.hypot(dx, dy) > C.BARD_DIVE_HIT_R || t.z > p.z + 0.3 || t.z + C.PLAYER_HEIGHT < p.z - 0.6) continue;
      p.dive = null;
      const landed = hitOne(t, dx || Math.cos(p.yaw), dy || Math.sin(p.yaw), def.up, 'air');
      p.atkLanded = landed;
      this.emit({ type: 'diveEnd', who: p.id, what: 'hit', x: p.x, y: p.y, z: p.z });
      return;
    }
    if (p.grounded) {
      p.dive = null;
      let any = false;
      for (const t of this.players.values()) {
        if (!this.foe(p, t)) continue;
        const dx = t.x - p.x;
        const dy = t.y - p.y;
        const d = Math.hypot(dx, dy);
        if (d > C.BARD_DIVE_LAND_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
        if (hitOne(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), C.BARD_DIVE_LAND_UP, 'land')) any = true;
      }
      p.atkLanded = any;
      this.emit({ type: 'diveEnd', who: p.id, what: 'land', x: p.x, y: p.y, z: p.z, r: C.BARD_DIVE_LAND_RANGE });
      return;
    }
    if (this.time >= D.until) {
      p.dive = null;
      this.emit({ type: 'diveEnd', who: p.id, what: 'expire', x: p.x, y: p.y, z: p.z });
    }
  }

  // F 폼 전환: 음유 → 메탈 = 충격파 + 기타 리프, 메탈 → 음유 = 치유파
  bardSwitch(p) {
    p.glideUntil = 0;
    if (p.form !== 'metal') {
      p.form = 'metal';
      const hits = [];
      for (const t of this.players.values()) {
        if (!this.foe(p, t)) continue;
        const dx = t.x - p.x;
        const dy = t.y - p.y;
        const d = Math.hypot(dx, dy);
        if (d > C.BARD_RIFF_RANGE || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
        const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(p.yaw), d > 0.05 ? dy : Math.sin(p.yaw), C.BARD_RIFF_KB_SPEED, C.BARD_RIFF_KB_UP, C.BARD_RIFF_STUN_MS, C.BARD_RIFF_DAMAGE, { by: p.id, kind: 'riff' }, true);
        this.emit({ type: 'hit', kind: 'riff', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
        if (hit) hits.push(`${t.name} ${t.damage}%`);
      }
      this.emit({ type: 'form', who: p.id, form: 'metal', x: p.x, y: p.y, z: p.z, r: C.BARD_RIFF_RANGE });
      this.log(`  [스킬] ${p.name} 메탈 폼 (기타 리프${hits.length ? ` → ${hits.join(', ')}` : ''})`);
    } else {
      p.form = 'bard';
      const healed = [];
      for (const t of this.players.values()) {
        if (!this.onField(t) || (t !== p && (!this.teamMode || !this.sameTeam(p, t) || Math.hypot(t.x - p.x, t.y - p.y) > C.BARD_HEAL_RANGE))) continue;
        const before = t.damage;
        t.damage = Math.max(0, t.damage - C.BARD_HEAL);
        healed.push({ id: t.id, from: before, to: t.damage });
      }
      this.emit({ type: 'form', who: p.id, form: 'bard', x: p.x, y: p.y, z: p.z, healed });
      this.log(`  [스킬] ${p.name} 음유시인 폼 (치유 ${healed.map((h) => `${this.players.get(h.id).name} ${h.from}% → ${h.to}%`).join(', ')})`);
    }
    p.chainN = 0; // 평타 세트가 바뀜
    p.airN = 0;
    return true;
  }

  // 음유 R 취약의 노래: 앞 넓은 범위 상대가 BARD_VULN_MS 동안 받는 넉백 ×BARD_VULN_MULT
  bardSong(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos(((C.BARD_SONG_ANGLE_DEG / 2) * Math.PI) / 180);
    const hit = [];
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.BARD_SONG_RANGE || Math.abs(t.z - p.z) > 2 || (d > 0.3 && (dx * fx + dy * fy) / d < cosHalf)) continue;
      t.vulnUntil = this.time + C.BARD_VULN_MS;
      hit.push(t);
    }
    this.emit({ type: 'song', who: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yaw, targets: hit.map((t) => t.id), ms: C.BARD_VULN_MS });
    this.log(`  [필살] ${p.name} 취약의 노래${hit.length ? ` → ${hit.map((t) => t.name).join(', ')}` : ''}`);
  }

  // 메탈 R 앰프 음파 시작
  bardAmp(p) {
    p.amp = { endAt: this.time + C.BARD_AMP_MS, nextTick: this.time, yaw: p.yaw };
    this.emit({ type: 'amp', who: p.id, ms: C.BARD_AMP_MS, yaw: p.yaw, lockYaw: C.BARD_AMP_LOCK_YAW });
    this.log(`  [필살] ${p.name} 앰프 음파`);
  }

  // 앰프 원뿔 방향: 시작 때 방향 고정 (BARD_AMP_LOCK_YAW) 또는 지금 보는 방향
  ampYaw(p) {
    return C.BARD_AMP_LOCK_YAW && p.amp ? p.amp.yaw : p.yaw;
  }

  // 앞 원뿔 안 상대 (앰프)
  ampTargets(p, yaw = this.ampYaw(p)) {
    const fx = Math.cos(yaw);
    const fy = Math.sin(yaw);
    const cosHalf = Math.cos(((C.BARD_AMP_ANGLE_DEG / 2) * Math.PI) / 180);
    return [...this.players.values()].filter((t) => {
      if (!this.foe(p, t)) return false;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      return d <= C.BARD_AMP_RANGE && Math.abs(t.z - p.z) <= C.PLAYER_HEIGHT && (d < 0.3 || (dx * fx + dy * fy) / d >= cosHalf);
    });
  }

  bardAmpUpdate(p) {
    const A = p.amp;
    const yaw = this.ampYaw(p);
    const fx = Math.cos(yaw);
    const fy = Math.sin(yaw);
    if (this.time >= A.nextTick && this.time < A.endAt) {
      A.nextTick += C.BARD_AMP_TICK_MS;
      for (const t of this.ampTargets(p)) {
        const hit = this.applyKnockback(t, fx, fy, C.BARD_AMP_TICK_KB, C.BARD_AMP_TICK_UP, C.BARD_AMP_TICK_STUN_MS, C.BARD_AMP_TICK_DAMAGE, { by: p.id, kind: 'amp' }, false, { fixed: true, chained: true });
        this.emit({ type: 'hit', kind: 'amp', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
      }
    }
    if (this.time < A.endAt) return;
    p.amp = null;
    const hits = [];
    for (const t of this.ampTargets(p, yaw)) {
      const hit = this.applyKnockback(t, fx, fy, C.BARD_AMP_END_KB_SPEED, C.BARD_AMP_END_KB_UP, C.BARD_AMP_END_STUN_MS, C.BARD_AMP_END_DAMAGE, { by: p.id, kind: 'ampend' }, true, { finish: true });
      this.emit({ type: 'hit', kind: 'ampend', by: p.id, target: t.id, ok: hit, streak: hit ? p.streak : 0 });
      if (hit) hits.push(`${t.name} ${t.damage}%`);
    }
    this.emit({ type: 'ampEnd', who: p.id, x: p.x, y: p.y, z: p.z, yaw });
    this.log(`  [필살] ${p.name} 앰프 끝${hits.length ? ` → ${hits.join(', ')}` : ''}`);
  }
}
