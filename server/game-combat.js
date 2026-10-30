// Game 메서드 묶음: 전투: 대시·밀치기·캐릭터 평타·스킬/필살기 발동·넉백·콤보. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C, basicSet } from '../shared/config.js';
import { EPS, overlapsCell, basicLabel, ULT_KINDS } from './game-util.js';

export class CombatPart {
  // ---------- 전투 ----------
  dash(p) {
    let dx = Math.cos(p.yaw);
    let dy = Math.sin(p.yaw);
    const mv = this.moveDir(p);
    if (mv) {
      dx = mv.x;
      dy = mv.y;
    }
    p.kbx = dx * C.DASH_SPEED;
    p.kby = dy * C.DASH_SPEED;
    p.dashReadyAt = this.time + C.DASH_COOLDOWN_MS;
    if (!p.grounded) p.airDashes--;
  }

  push(p) {
    p.pushReadyAt = this.time + C.PUSH_COOLDOWN_MS;
    p.atkLanded = false;
    const kind = 'push';
    const speed = C.PUSH_KB_SPEED;
    const up = C.PUSH_KB_UP;
    const stun = C.STUN_MS;
    this.emit({ type: 'swing', who: p.id, kind });
    const falling = !p.grounded && p.vz < 0; // 치명타: 떨어지면서 때림 (높이 조건은 상대마다)
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.PUSH_HALF_ANGLE_DEG * Math.PI) / 180);
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t) || this.sameTeam(p, t)) continue; // 같은 팀은 그냥 통과
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > C.PUSH_RANGE) continue;
      if (Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (dist > EPS && (dx * fx + dy * fy) / dist < cosHalf) continue;
      const crit = falling && p.z - t.z >= C.CRIT_MIN_HEIGHT;
      const gain = crit ? Math.round(C.DAMAGE_GAIN[kind] * C.CRIT_DAMAGE_MULT) : C.DAMAGE_GAIN[kind];
      const hit = this.applyKnockback(t, fx, fy, crit ? speed * C.CRIT_KB_MULT : speed, up, stun, gain, { by: p.id, kind });
      const stop = crit ? C.HITSTOP_MS * C.CRIT_HITSTOP_MULT : C.HITSTOP_MS;
      if (hit) {
        p.freezeUntil = this.time + stop; // 때린 쪽도 같이 멈칫
        t.freezeUntil = this.time + stop;
      }
      if (hit && !this.sameTeam(p, t)) p.atkLanded = true; // 맞혔으면 F·R 로 쿨 캔슬 (그림자 일격 → 순간 베기)
      this.emit({ type: 'hit', kind, by: p.id, target: t.id, ok: hit, crit: hit && crit });
      this.log(`  [밀치기] ${p.name} → ${t.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${t.name} ${t.damage}%)` : '무적이라 무시'}`);
    }
  }

  // F·R 캔슬 (2026-10-25 재혁 승인): 평타가 맞은 뒤 후딜이면 후딜을 끊고 바로. 빗나간 뒤 후딜이면 후딜이 끝나고.
  // 평타 준비 중이면 기억했다가 판정 결과에 따라 (준비 중인 평타는 안 취소). 핑 때문에 미리 눌러 두는 것을 서버가 판정
  cast(p, kind) {
    if (p.atk || (this.time < p.pushReadyAt && !p.atkLanded)) {
      p.castQueued = kind;
      p.atkQueued = false; // 나중에 누른 스킬이 먼저 누른 평타 선입력보다 우선
      return;
    }
    if (this.time < p.pushReadyAt) p.pushReadyAt = this.time; // 맞힌 평타의 후딜 캔슬
    if (kind === 'skill') this.useSkill(p);
    else if (!this.useUlt(p)) {
      // 못 씀 (게이지 그대로): 화면이 알 수 있게 (갈고리 블록 없음, 건축가 솟을 자리 없음, 다른 기술 중)
      const reason = p.slamAt || p.wallAt || p.grab || p.huntAim || p.rush || p.spin || p.amp || this.time < p.chargeUntil ? 'busy' : p.char === 'hook' ? 'noBlock' : p.char === 'hunter' ? 'noTarget' : 'noSpace';
      this.emit({ type: 'ultFail', who: p.id, reason });
      this.log(`  [필살] ${p.name} 못 씀 (${reason})`);
    }
  }

  // 기억한 F·R 을 지금 쓸 수 있으면 씀 (맞힌 평타 판정 직후 또는 후딜 끝)
  castQueuedNow(p) {
    const kind = p.castQueued;
    p.castQueued = null;
    if (this.time < p.stunUntil || this.isControlling(p) || (kind === 'skill' ? this.time < p.skillReadyAt : p.ult < this.ultMax(p))) {
      this.emit({ type: 'castDrop', who: p.id, kind }); // 기억했던 F·R 이 버려짐 (소모 없음)
      return;
    }
    this.cast(p, kind);
  }

  // ---------- 캐릭터 평타 (BASIC_ATTACKS) ----------
  // 준비·후딜 중에 누르면 기다렸다 나감 (updateCombat)
  basicPress(p) {
    if (p.atk || this.time < p.pushReadyAt) {
      p.atkQueued = true;
      return;
    }
    this.basicStart(p);
  }

  // 몇 번째 타인지 정하고 준비 시작. 지상·공중 각각 이어 치기 창 안이면 다음 타, 아니면 1타 (공중은 air 배열 순서)
  basicStart(p) {
    const set = basicSet(p.char, p.form);
    const air = !p.grounded;
    const live = this.time < p.chainUntil;
    const n = air ? (p.airN > 0 && live && p.airN < set.air.length ? p.airN + 1 : 1) : p.chainN > 0 && live && p.chainN < set.chain.length ? p.chainN + 1 : 1;
    let def = air ? set.air[n - 1] : set.chain[n - 1];
    if (def.dive && p.diveUsed) return; // 바드 기타 꽂기: 착지 전 1번
    if (def.loaded && p.loaded) def = def.loaded; // 갈고리 3타: 장전돼 있으면 탕
    if (def.ammo && p.cannonAmmo > 0) def = def.ammo; // 대포수: 탄이 있으면 포탄
    // 닌자 R 강화: 지상 1~3타와 공중 평타가 표창 2연발 (4타 올려 차기는 그대로)
    if (p.char === 'ninja' && this.time < p.empowerUntil && (air || n <= 3)) def = { ...def, name: '표창', windup: C.NINJA_STAR.windup, step: 0, star: true };
    // 연타를 이어 가는 중인 타 (지상 2타~, 공중 2타~, 띄우는 마지막 지상 타 뒤 공중 1타): 시간 마무리가 되지 않음
    const chained = air ? (p.airN > 0 && live) || this.time < p.launchUntil : n > 1;
    p.atk = { n, def, air, chained, at: this.time + def.windup };
    p.atkLanded = false;
    p.pushReadyAt = this.time + def.windup + def.rec;
    const glided = !!def.glide && p.glideCount < C.BARD_GLIDE_MAX_PER_AIR; // 횟수를 다 쓰면 낙하도 고리도 없음
    if (glided) this.bardGlide(p, def.windup + def.rec);
    if (glided) p.atk.glided = true;
    if (def.dive) this.bardDive(p, def); // 바드 기타 꽂기: 누르는 순간 아래로 // 바드 공중 평타: 동작(준비+후딜) 동안만 천천히 낙하, 착지 전 N번까지
    this.emit({ type: 'attack', who: p.id, char: p.char, n, air, name: def.name, windup: def.windup, finish: !!def.finish, star: !!def.star });
    if (def.windup <= 0) this.basicHit(p);
  }

  // 판정: 앞으로 step 만큼 나가며 부채꼴 안을 침. 중간 타는 고정 넉백, 마무리 타·공중 평타는 % 배율
  basicHit(p) {
    const { n, def, air, chained, glided } = p.atk;
    p.atk = null;
    const set = basicSet(p.char, p.form);
    if (def.star) return this.starVolley(p, n, air, def, chained);
    if (def.shell) {
      this.cannonShot(p);
      return this.basicChain(p, n, air, false, def);
    }
    if (def.note || def.glide || def.dive) { // 기타 꽂기 판정은 낙하 중 (bardDiveUpdate)
      if (def.note) this.bardNote(p); // 천천히 낙하는 누를 때 시작 (basicStart)
      const landed = glided && this.bardGlideRing(p, n, air, def, chained);
      return this.basicChain(p, n, air, landed, def);
    }
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    if (def.step) {
      // 앞으로 나가되 앞 상대를 지나치지 않게 (BASIC_STEP_GAP 앞에서 멈춤)
      let step = def.step;
      for (const t of this.players.values()) {
        if (!this.foe(p, t) || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
        const along = (t.x - p.x) * fx + (t.y - p.y) * fy;
        const side = Math.abs((t.x - p.x) * fy - (t.y - p.y) * fx);
        if (along > 0 && side < C.BASIC_STEP_GAP) step = Math.min(step, Math.max(0, along - C.BASIC_STEP_GAP));
      }
      this.moveAxis(p, 'x', fx * step);
      this.moveAxis(p, 'y', fy * step);
    }
    this.emit({ type: 'swing', who: p.id, kind: 'push', char: p.char, n });
    if (def.shot) {
      p.loaded = false; // 탕: 쏘면 빈 총 (맞든 안 맞든)
      this.emit({ type: 'bang', who: p.id, x: p.x, y: p.y, z: p.z, yaw: p.yaw });
    }
    const range = def.range || C.PUSH_RANGE;
    const cosHalf = Math.cos(((def.angle ?? C.PUSH_HALF_ANGLE_DEG) * Math.PI) / 180);
    const falling = !p.grounded && p.vz < 0;
    const finish = !!def.finish;
    const single = air && set.air.length === 1; // 공중 한 타짜리: 예전처럼 % 배율 넉백·보통 멈칫
    const label = basicLabel(set, n, air, def);
    let landed = null; // 처음 맞힌 상대 (같은 팀 빼고)
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t) || this.sameTeam(p, t)) continue; // 같은 팀은 그냥 통과
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > range || Math.abs(t.z - p.z) > C.PLAYER_HEIGHT) continue;
      if (dist > C.BASIC_STEP_GAP && (dx * fx + dy * fy) / dist < cosHalf) continue; // 몸이 붙어 있으면 방향 상관없이
      const crit = air && falling && p.z - t.z >= C.CRIT_MIN_HEIGHT; // 치명타는 공중 평타만
      const gain = crit ? Math.round(def.dmg * C.CRIT_DAMAGE_MULT) : def.dmg;
      const speed = crit ? def.kb * C.CRIT_KB_MULT : def.kb;
      const radial = def.radial && dist > 0.05; // 사방 치는 타 (광전사 회전 베기): 바깥으로
      const hit = this.applyKnockback(t, radial ? dx : fx, radial ? dy : fy, speed, def.up, def.stun, gain, { by: p.id, kind: 'push' }, finish, { fixed: !single && !finish, finish, chained });
      if (hit) {
        const stop =
          (finish ? C.BASIC_FINISH_HITSTOP_MS : single ? C.HITSTOP_MS : C.BASIC_HITSTOP_MS) *
          (crit ? C.CRIT_HITSTOP_MULT : 1) *
          (t.counterAt === this.time ? C.COUNTER_HITSTOP_MULT : 1);
        p.freezeUntil = this.time + stop;
        t.freezeUntil = this.time + stop;
        if (!landed && !this.sameTeam(p, t)) landed = t;
        if (def.mark && !this.sameTeam(p, t)) this.addMark(p, t); // 사냥꾼 찔러 넣기: 표식 +1
      }
      this.emit({ type: 'hit', kind: 'push', by: p.id, target: t.id, ok: hit, crit: hit && crit, n, air, finish, streak: hit ? p.streak : 0 });
      this.log(`  [평타] ${p.name} → ${t.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${t.name} ${t.damage}%)` : '무적이라 무시'} ${label}`);
    }
    this.basicChain(p, n, air, !!landed, def);
    if (p.char === 'builder' && this.hammerBlocks(p, range, cosHalf)) p.atkLanded = true; // 망치로 내 블록을 치면 폭발 (맞힌 것으로 침: F·R 캔슬)
    if (def.raise) this.basicRaise(p, landed);
  }

  // 평타 한 타가 끝난 뒤: 이어 치기 번호·창, 맞혔는지, 닌자 F 쿨 감소
  // 허공 이어 치기 (2026-10-25 재혁): 빗나가도 다음 타로 (후딜은 다 받음). BASIC_CHAIN_WINDOW_MS 안에 안 치면 1타로.
  // 타 번호는 때린 쪽에 남음 → 상대를 바꿔도 이어짐 (닌자 갈아타기)
  basicChain(p, n, air, landed, def) {
    const set = basicSet(p.char, p.form);
    // 띄우는 마지막 지상 타(마무리 아님) 뒤에는 후딜 + 이어 치기 창 동안 공중 1타가 연타로 이어짐
    if (!air && n === set.chain.length && !def.finish) p.launchUntil = this.time + def.rec + C.BASIC_CHAIN_WINDOW_MS;
    if (air) {
      p.airN = n < set.air.length ? n : 0;
      if (p.airN > 0 || p.chainN > 0) p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS; // 지상 타 번호도 그대로
    } else if (n < set.chain.length) {
      p.chainN = n;
      p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS;
    } else p.chainN = 0;
    p.atkLanded = landed;
    p.lastBasic = { n, air, at: this.time };
    if (landed) this.ninjaCdCut(p);
  }

  // 닌자 적중 보상: 평타가 맞을 때마다 F 쿨 NINJA_HIT_CD_CUT_MS 줄어듦
  ninjaCdCut(p) {
    if (p.char === 'ninja') p.skillReadyAt = Math.max(this.time, p.skillReadyAt - C.NINJA_HIT_CD_CUT_MS);
  }

  // 닌자 R 강화 표창 2연발: 첫 발은 지금, 둘째 발은 NINJA_STAR.gap 뒤 (updateCombat). 즉시 판정 (날아가는 물체 아님)
  starVolley(p, n, air, def, chained) {
    const landed = this.starShot(p, n, air, def, 1, chained);
    this.basicChain(p, n, air, landed, def);
    p.star2 = { at: this.time + C.NINJA_STAR.gap, n, air, def, chained };
  }

  // 표창 한 발: 보는 방향 좁은 각 NINJA_STAR.range 안 가장 가까운 상대 하나. 마무리 타 자리면 둘째 발이 그 타의 마무리
  starShot(p, n, air, def, shot, chained = false) {
    const S = C.NINJA_STAR;
    const set = basicSet(p.char, p.form);
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((S.angle * Math.PI) / 180);
    let best = null;
    let bd = Infinity;
    for (const t of this.players.values()) {
      if (t === p || !this.onField(t) || this.sameTeam(p, t)) continue; // 같은 팀은 그냥 통과
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > S.range || Math.abs(t.z - p.z) > S.range || dist < EPS || (dx * fx + dy * fy) / dist < cosHalf) continue;
      if (dist < bd) {
        bd = dist;
        best = t;
      }
    }
    const fin = shot === 2 && !!def.finish;
    const from = { x: p.x, y: p.y, z: p.z + C.EYE_HEIGHT - 0.3 };
    this.emit({ type: 'star', who: p.id, shot, target: best ? best.id : null, from, to: best ? { x: best.x, y: best.y, z: best.z + 0.8 } : { x: p.x + fx * S.range, y: p.y + fy * S.range, z: from.z } });
    if (!best) return false;
    const falling = !p.grounded && p.vz < 0;
    const crit = air && falling && p.z - best.z >= C.CRIT_MIN_HEIGHT;
    const dmg = fin ? def.dmg : S.dmg;
    const gain = crit ? Math.round(dmg * C.CRIT_DAMAGE_MULT) : dmg;
    const hit = this.applyKnockback(best, fx, fy, (fin ? def.kb : S.kb) * (crit ? C.CRIT_KB_MULT : 1), fin ? def.up : S.up, fin ? def.stun : S.stun, gain, { by: p.id, kind: 'push' }, fin, { fixed: !fin, finish: fin, chained: chained || shot === 2 });
    if (hit) {
      const stop = (fin ? C.BASIC_FINISH_HITSTOP_MS : C.BASIC_HITSTOP_MS) * (crit ? C.CRIT_HITSTOP_MULT : 1) * (best.counterAt === this.time ? C.COUNTER_HITSTOP_MULT : 1);
      best.freezeUntil = this.time + stop;
    }
    const ok = hit && !this.sameTeam(p, best);
    this.emit({ type: 'hit', kind: 'push', by: p.id, target: best.id, ok: hit, crit: hit && crit, n, air, finish: fin, star: true, streak: hit ? p.streak : 0 });
    this.log(`  [평타] ${p.name} → ${best.name} ${hit ? `넉백${crit ? ' 치명타' : ''} (${best.name} ${best.damage}%)` : '무적이라 무시'} ${basicLabel(set, n, air, def)}`);
    return ok;
  }

  // 건축가 내려찍기: 맞힌 사람 발밑 (빗나가면 앞 1.5칸) 기둥 꼭대기에 건축가 블록 1칸 ('third', 최대 BUILDER_THIRD_MAX 개).
  // 내 몸과 겹치는 칸이면 앞으로 0.5칸씩 (2026-10-25 버그: 몸이 옆 칸에 걸쳐 있으면 내 밑에서 솟아 나를 띄웠음)
  basicRaise(p, t) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    let bx = t ? t.x : p.x + fx * 1.5;
    let by = t ? t.y : p.y + fy * 1.5;
    const mine = (x, y) => overlapsCell(p, Math.floor(x), Math.floor(y), this.columnTop(Math.floor(x), Math.floor(y))) || (Math.floor(x) === Math.floor(p.x) && Math.floor(y) === Math.floor(p.y));
    for (let i = 0; i < 3 && this.inXY(Math.floor(bx), Math.floor(by)) && mine(bx, by); i++) {
      bx += fx * 0.5;
      by += fy * 0.5;
    }
    const cx = Math.floor(bx);
    const cy = Math.floor(by);
    if (!this.inXY(cx, cy) || mine(bx, by)) return;
    const z = this.columnTop(cx, cy);
    const g = ++this.bgroup;
    if (!this.placeBBlock(p, cx, cy, z, 'third', g)) return;
    // 3타 블록은 동시에 BUILDER_THIRD_MAX 개까지: 넘으면 제일 오래된 것부터 사라짐
    const thirds = [...this.bblocks.values()].filter((b) => b.owner === p.id && b.kind === 'third').sort((a, b) => a.born - b.born);
    for (const b of thirds.slice(0, Math.max(0, thirds.length - C.BUILDER_THIRD_MAX))) this.removeBBlock(b, 'old');
    this.gridChanged();
    for (const o of this.players.values()) if (this.onField(o) && overlapsCell(o, cx, cy, z)) this.ejectFromBlocks(o);
    this.emit({ type: 'wallRise', who: p.id, cells: [[cx, cy, z]] });
    this.emit({ type: 'bblock', who: p.id, kind: 'third', group: g, cells: [[cx, cy, z]], ms: C.BUILDER_BLOCK_MS });
    this.log(`  [평타] ${p.name} 블록 솟음 (${cx},${cy},${z})`);
    this.clearLayers();
  }

  // ---------- 캐릭터 스킬·필살기 ----------
  useSkill(p) {
    if (p.slamAt || p.wallAt || p.grab || p.leap || p.windup || p.hookFly || p.huntAim || p.rush || p.spin || p.amp || this.time < p.chargeUntil) return false; // 다른 기술 발동 중
    p.skillReadyAt = this.time + C.SKILL_CD_MS[p.char]; // 먼저 걸어 둠 (그림자 일격이 순간 베기 쿨을 초기화하는 것과 순서가 안 꼬이게)
    if (p.grounded && C.SKILL_WINDUP_CHARS.includes(p.char)) {
      // 이동 스킬 지상 예고: SKILL_WINDUP_MS 뒤 누른 순간 방향으로 나감 (updateCombat → fireWindup)
      p.windup = { at: this.time + C.SKILL_WINDUP_MS, yaw: p.yaw };
      this.emit({ type: 'skillWindup', who: p.id, kind: p.char, ms: C.SKILL_WINDUP_MS });
      this.log(`  [스킬] ${p.name} ${C.CHAR_NAMES[p.char]} F 준비`);
      return true;
    }
    return this.fireSkill(p);
  }

  // 이동 스킬 예고가 끝남: 누른 순간 방향으로 나감 (지금 보는 방향은 나간 뒤 돌려 둠)
  fireWindup(p) {
    const yaw = p.yaw;
    p.yaw = p.windup.yaw;
    p.windup = null;
    if (!this.fireSkill(p)) this.log(`  [스킬] ${p.name} ${C.CHAR_NAMES[p.char]} F 못 나감 (자리 없음, 쿨타임 안 씀)`);
    p.yaw = yaw; // 방향은 나갈 때 정해짐 (돌진 chargeDir·갈고리 hookFly·순간 베기 위치) → 보는 방향만 원래대로
  }

  // F 를 실제로 냄 (쿨타임은 useSkill 이 걸어 둠)
  fireSkill(p) {
    const ok =
      p.char === 'tank'
        ? this.tankCharge(p)
        : p.char === 'ninja'
          ? this.ninjaBlink(p)
          : p.char === 'builder'
            ? this.builderWall(p)
            : p.char === 'hunter'
              ? this.hunterLeap(p)
              : p.char === 'cannon'
                ? this.cannonJump(p)
                : p.char === 'berserker'
                  ? this.berserkerLeap(p)
                  : p.char === 'bard'
                    ? this.bardSwitch(p)
                    : this.hookPull(p);
    if (!ok) {
      p.skillReadyAt = this.time; // 못 쓰는 상황(벽 세울 자리 없음 등)이면 쿨타임 안 돎 — 갈고리는 빗나가도 돎 (hookPull 이 정함)
      return false;
    }
    if (p.chainN > 0 && this.time < p.chainUntil) p.chainUntil = this.time + C.BASIC_CHAIN_WINDOW_MS; // 평타 → 스킬 → 평타
    this.emit({ type: 'skill', who: p.id, char: p.char, x: p.x, y: p.y, z: p.z });
    return true;
  }

  useUlt(p) {
    if (p.slamAt || p.wallAt || p.grab || p.leap || p.windup || p.hookFly || p.huntAim || p.rush || p.spin || p.amp || this.time < p.chargeUntil) return false;
    if (p.char === 'tank') this.tankSlamStart(p);
    else if (p.char === 'ninja') this.ninjaEmpower(p); else if (p.char === 'builder') {
      if (!this.builderBigBomb(p)) return false; // 솟을 자리가 없으면 게이지 그대로
    } else if (p.char === 'cannon') this.cannonBig(p);
    else if (p.char === 'berserker') this.berserkerSpin(p);
    else if (p.char === 'bard') {
      if (p.form === 'metal') this.bardAmp(p);
      else this.bardSong(p);
    }
    else if (p.char === 'hunter') {
      if (!this.hunterAim(p)) return false; // 사냥꾼: 쏠 표식 대상이 없으면 게이지 그대로
    } else if (!this.hookGrab(p)) return false; // 갈고리: 닿는 블록이 없으면 게이지 그대로
    p.ult = 0;
    this.emit({ type: 'ult', who: p.id, char: p.char, x: p.x, y: p.y, z: p.z });
    return true;
  }

  // 남에게 맞힐 수 있는 상대인가 (필드 위·다른 팀·나 아님)
  foe(p, t) {
    return t !== p && this.onField(t) && !this.sameTeam(p, t);
  }


  // 틱마다: 콤보가 끊긴 사람 무적, 돌진 부딪힘, 내려찍기·솟는 벽·블록 내려찍기 발동
  updateCombat() {
    if (this.bblocks.size || this.bigBombs.length || this.holes.length) this.updateBBlocks();
    if (this.quakes.length) this.updateQuakes();
    for (const p of this.players.values()) {
      if (p.comboHits > 0 && this.time >= p.stunUntil) this.endCombo(p);
      if (!this.onField(p)) {
        p.chargeUntil = p.slamAt = p.wallAt = p.zipUntil = 0;
        p.leap = p.huntAim = p.rush = p.spin = p.amp = p.windup = p.hookFly = null;
        p.glideUntil = 0;
        p.dive = null;
        p.marks.clear();
        if (p.grab) this.hookGrabDrop(p);
        p.atk = null;
        p.atkQueued = false;
        p.castQueued = null;
        p.star2 = null;
        continue;
      }
      if (p.atk && this.time >= p.atk.at) this.basicHit(p);
      if (p.star2 && this.time >= p.star2.at) {
        const s2 = p.star2;
        p.star2 = null;
        if (this.starShot(p, s2.n, s2.air, s2.def, 2, s2.chained)) {
          p.atkLanded = true;
          this.ninjaCdCut(p);
        }
      }
      if (p.char === 'ninja') this.ninjaTouch(p);
      if (p.marks.size) this.expireMarks(p);
      if (p.char === 'cannon') this.cannonReload(p);
      if (p.windup && this.time >= p.windup.at) this.fireWindup(p);
      if (p.hookFly && this.time >= p.hookFly.at) this.hookLand(p);
      if (p.leap) this.hunterLeapUpdate(p);
      if (p.rush) this.berserkerLeapUpdate(p);
      if (p.spin) this.berserkerSpinUpdate(p);
      if (p.amp) this.bardAmpUpdate(p);
      if (p.dive) this.bardDiveUpdate(p);
      if (p.huntAim && this.time >= p.huntAim.at) this.hunterShoot(p);
      if (p.castQueued && !p.atk && (p.atkLanded || this.time >= p.pushReadyAt)) this.castQueuedNow(p);
      else if (p.atkQueued && !p.atk && this.time >= p.pushReadyAt) {
        p.atkQueued = false;
        if (this.time >= p.stunUntil && !this.isControlling(p)) this.basicStart(p);
      }
      if (this.time < p.chargeUntil) this.chargeHit(p);
      if (p.slamAt && this.time >= p.slamAt) this.tankSlam(p);
      if (p.wallAt && this.time >= p.wallAt) this.builderWallRise(p);
      if (p.grab && this.time >= p.grab.at) this.hookSlam(p);
    }
  }

  // src: { by, kind } — 누가 무엇으로 날렸는지 (킬 판정용 lastHit)
  // heavy: 무거운 공격 (망치·투사체·폭탄·충격파·필살기·평타 마무리 타) 은 콤보 중에도 넉백을 안 줄임
  // opts.fixed: 평타 중간 타 — 넉백 고정 (피해 % 배율·콤보 감쇠·탱크 패시브 없음). opts.finish: 평타 마무리 타 — 콤보 2타 이상이면 시간과 상관없이 마무리
  applyKnockback(t, dx, dy, speed, up, stunMs = C.STUN_MS, gain = 0, src = null, heavy = false, opts = {}) {
    if (this.invulnerable(t)) return false; // 콤보 뒤 무적·부활 무적
    const teammate = src && this.sameTeam(this.players.get(src.by), t);
    if (teammate) return false; // 2026-10-26 재혁: 팀전에서 같은 팀 공격은 아무 효과 없음 (넉백·경직·피해·끊김 없이 통과)
    // 탱크 아머 (F 돌진 중·R 떠오르는 동안): 넉백·경직 없이 피해 % 만. 마무리 타·필살기면 깨지고 보통처럼 (카운터는 안 당함)
    let armorBroken = false;
    if (!teammate && t.char === 'tank' && (this.time < t.chargeUntil || t.slamAt)) {
      const name = this.players.get(src?.by)?.name || '?';
      if (!opts.finish && !ULT_KINDS.has(src?.kind)) {
        if (src && src.by !== t.id) t.lastHit = { by: src.by, kind: src.kind, name };
        t.damage += gain;
        this.gainUlt(t, src, gain);
        this.emit({ type: 'armor', who: t.id, by: src ? src.by : null });
        this.log(`  [아머] ${t.name} ← ${name} 버팀 (${t.name} ${t.damage}%)`);
        return true;
      }
      armorBroken = true;
      this.emit({ type: 'armorBreak', who: t.id, by: src ? src.by : null });
      this.log(`  [아머] ${t.name} ← ${name} 깨짐`);
    }
    // 콤보: 경직이 안 풀렸는데 또 맞으면 이어짐. 첫 타에서 COMBO_MS 가 지난 뒤 들어간 타가 마지막 타 (크게 날리고 무적). 같은 팀은 콤보로 안 셈 (무적도 안 붙음)
    if (!teammate) {
      t.comboHits = this.time < t.stunUntil && t.comboHits > 0 ? t.comboHits + 1 : 1;
      if (t.comboHits === 1) {
        t.comboBy = new Set(); // 이 콤보를 넣은 사람들 (로그·통계용)
        t.comboStartAt = this.time;
      }
      const hitter = src && src.by !== t.id ? this.players.get(src.by) : null;
      if (hitter) t.comboBy.add(hitter.name);
    }
    // 카운터히트: 맞는 쪽이 평타 준비·후딜, 스킬·필살기 준비(돌진 중 포함) 중이었음 → 경직·멈칫 길게
    const counter = !teammate && !armorBroken && !!src && !!t.char && this.time >= t.stunUntil && this.busy(t); // 이미 경직 중(콤보)이면 아님, 탱크 아머 중이면 아님
    if (counter) {
      stunMs *= C.COUNTER_STUN_MULT;
      t.counterAt = this.time;
      this.emit({ type: 'counter', by: src.by, target: t.id });
      this.log(`  [카운터] ${this.players.get(src.by)?.name} → ${t.name}`);
    }
    // 2026-10-25 재혁: 때린 쪽이 연타를 이어 가는 중인 타(opts.chained)는 COMBO_MS 가 지나도 시간 마무리가 아님.
    // 연타는 길이가 정해져 있어서 (지상 마지막 타 → 공중 마무리) 무한히 안 늘어남. 스킬·다른 사람 타는 예전처럼 시간 마무리
    const finisher = !teammate && t.comboHits >= 2 && (opts.finish || (this.time - t.comboStartAt >= C.COMBO_MS && !opts.chained));
    const fixed = opts.fixed && !finisher;
    if (!fixed) speed *= finisher ? C.COMBO_FINISH_KB : heavy ? 1 : C.COMBO_LIGHT_KB;
    // 광전사 분노: 주는 넉백 × (1 + 자기 피해 % × 계수), 상한 없음. 고정 넉백 중간 타는 빼고. R 마지막 날림은 R 시작 때 피해 % (src.rage)
    const rager = !teammate && src && src.by !== t.id ? this.players.get(src.by) : null;
    if (!fixed && rager && rager.char === 'berserker') speed *= this.rageMult(src.rage ?? rager.damage);
    if (!teammate && t.comboHits >= 2 && src) this.emit({ type: 'combo', by: src.by, target: t.id, n: t.comboHits, finish: finisher });
    // 맞아서 끊긴 공격: 쿨타임·게이지를 돌려주고 interrupt 이벤트 (화면에서 끊긴 모션)
    if (t.atk) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'basic', n: t.atk.n });
      t.pushReadyAt = this.time; // 안 나간 평타는 후딜 없음
    }
    if (this.time < t.chargeUntil) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'skill' });
      t.skillReadyAt = this.time; // 아무도 못 친 돌진은 쿨타임 안 씀
    }
    if (t.slamAt) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      t.ult = this.ultMax(t); // 준비 중에 끊긴 내려찍기는 게이지 돌려줌
    }
    if (t.grab) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      this.hookGrabDrop(t); // 뽑던 블록은 제자리로
      t.ult = this.ultMax(t); // 게이지 돌려줌
    }
    if (t.windup || t.hookFly) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'skill' });
      t.skillReadyAt = this.time; // 준비 중·갈고리가 닿기 전에 끊긴 F 는 쿨타임 안 씀
      t.windup = t.hookFly = null;
    }
    t.zipUntil = 0; // 끌려가다 맞으면 멈춤
    if (t.leap) {
      if (!t.leap.endAt) {
        this.emit({ type: 'interrupt', who: t.id, kind: 'skill' });
        t.skillReadyAt = this.time; // 뛰기 전에 끊긴 도약은 쿨타임 안 씀
      }
      t.leap = null;
    }
    if (t.huntAim) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      t.huntAim = null;
      t.ult = this.ultMax(t); // 조준 중에 끊긴 처형 사격은 게이지 돌려줌
    }
    t.rush = null; // 광전사 도약 중에 맞으면 충격파 없음 (쿨타임은 씀)
    t.glideUntil = 0; // 바드 천천히 낙하: 맞으면 풀림
    t.dive = null; // 기타 꽂기 낙하도 끊김
    // 바드 앰프 음파: 맞아도 안 끊김 — 넉백은 받고 연주는 끝까지 (2026-10-26 재혁 가: 봇 판 끊김 56~65%)
    if (t.spin) {
      this.emit({ type: 'interrupt', who: t.id, kind: 'ult' });
      this.log(`  [필살] ${t.name} 분노 소용돌이 끊김`);
      t.spin = null; // 회전 중에 맞으면 끝 (게이지·깎은 피해 % 안 돌려줌)
    }
    t.emoteUntil = 0; // 맞으면 이모트 끊김
    t.chargeUntil = 0; // 맞으면 돌진·내려찍기 끊김
    t.slamAt = 0;
    t.atk = null; // 맞으면 평타 준비·이어 치기 끊김
    t.star2 = null;
    t.streak = 0;
    t.atkQueued = false;
    if (t.castQueued) this.emit({ type: 'castDrop', who: t.id, kind: t.castQueued }); // 맞아서 기억했던 F·R 이 버려짐 (소모 없음)
    t.castQueued = null;
    t.chainN = 0;
    if (teammate) gain = 0; // 팀전: 같은 팀은 밀리기만 (피해 % 없음, 킬로도 안 침)
    else if (src && src.by !== t.id) {
      t.lastHit = { by: src.by, kind: src.kind, name: this.players.get(src.by)?.name };
      // 때린 쪽의 이어 넣은 타 수 (상대가 바뀌어도 STREAK_MS 안이면 이어짐 → 닌자 갈아타기 'N HIT')
      const by = this.players.get(src.by);
      if (by) {
        by.streak = this.time < by.streakUntil ? by.streak + 1 : 1;
        by.streakUntil = this.time + C.STREAK_MS;
        if (by.streak >= 2) this.emit({ type: 'streak', who: by.id, n: by.streak, target: t.id });
      }
    }
    const taken = t.char === 'tank' ? C.TANK_KB_TAKEN : t.char === 'ninja' ? C.NINJA_KB_TAKEN : 1; // 탱크 패시브: 덜 밀림, 닌자 약점: 잘 밀림
    const vuln = !teammate && this.time < t.vulnUntil ? C.BARD_VULN_MULT : 1; // 바드 취약의 노래 (% 배율 넉백에만)
    const mult = fixed ? 1 : (C.DAMAGE_KB_BASE + t.damage * C.DAMAGE_KB_PER_PERCENT) * taken * vuln;
    t.damage += gain;
    this.gainUlt(t, src, gain);
    const len = Math.hypot(dx, dy) || 1;
    t.kbx = (dx / len) * speed * mult;
    t.kby = (dy / len) * speed * mult;
    t.vz = up;
    t.grounded = false;
    t.wallBounced = false; // 벽 튕김은 맞을 때마다 한 번
    t.stunUntil = this.time + stunMs;
    t.freezeUntil = this.time + C.HITSTOP_MS * (counter ? C.COUNTER_HITSTOP_MULT : 1); // 멈칫 뒤에 날아간다 (날아가는 거리는 그대로)
    if (finisher) this.endCombo(t, t.stunUntil, true);
    return true;
  }

  // 필살기 게이지: 피해 % 를 주거나 받은 만큼
  gainUlt(t, src, gain) {
    if (gain <= 0) return;
    t.ult = Math.min(this.ultMax(t), t.ult + gain * C.ULT_PER_DAMAGE);
    const by = src && src.by !== t.id ? this.players.get(src.by) : null;
    if (by) by.ult = Math.min(this.ultMax(by), by.ult + gain * C.ULT_PER_DAMAGE);
  }

  // 카운터히트 대상 (2026-10-25 재혁 결정, 첫 사람 플레이테스트: 1:1 에서 동시에 누르면 거의 다 카운터였음):
  // 빗나간 평타의 후딜, 돌진 중, 내려찍기·솟는 벽 준비·갈고리 블록 뽑는 중. 평타 준비 중·맞힌 평타의 후딜·걷기·점프는 아님
  busy(t) {
    return !!((this.time < t.pushReadyAt && !t.atk && !t.atkLanded) || this.time < t.chargeUntil || t.slamAt || t.wallAt || t.grab || t.leap || t.windup || t.huntAim || t.rush || t.spin || t.amp);
  }

  // 공격이 안 들어가는 상태: 콤보 뒤 무적·부활 무적. 경직이 이미 풀린 콤보는 여기서 먼저 끝냄
  // (봇 행동·블록 충격파는 틱 안에서 updateCombat 보다 먼저 돌아서, 끝난 콤보에 새 콤보가 붙어 무적을 건너뛰던 것)
  invulnerable(t) {
    if (t.comboHits > 0 && this.time >= t.stunUntil) this.endCombo(t);
    return this.time < t.iframeUntil || this.time < t.shieldUntil;
  }

  // 콤보 끝: 그때부터 COMBO_IFRAME_MS 무적 (마지막 타는 경직이 끝날 때까지 + 무적)
  endCombo(t, from = this.time, finished = false) {
    if (t.comboHits >= 2) {
      const line = `  [콤보] ${[...(t.comboBy || [])].join('+') || '?'} → ${t.name} ${t.comboHits}타${finished ? ' 마무리' : ''}`; // 때린 사람 여럿이면 P1+P3
      if (finished) this.pendingLogs.push(line); // 마무리 타는 그 공격 줄 뒤에
      else this.log(line);
    }
    t.comboHits = 0;
    t.iframeUntil = from + C.COMBO_IFRAME_MS;
  }
}
