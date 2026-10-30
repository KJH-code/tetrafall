// Game 메서드 묶음: 연습 모드·튜토리얼·허수아비. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { Tutorial } from './tutorial.js';
import { practiceDamage, comboOut } from './game-util.js';

export class PracticePart {
  // ---------- 연습 모드 (2026-10-26 재혁) ----------
  // 혼자 쓰는 방에서 바로 시작, 판이 안 끝남. 토글(practice)은 방 전체, 내 피해 % 는 사람마다. 허수아비 = 입력 없는 플레이어 (dummy)
  startPractice() {
    this.mode = 'practice';
    this.practice = { noCooldown: false, fullUlt: false, noBlocks: true, noDeath: true };
    this.skyStairs = false;
    this.hpMode = false; // 연습·튜토리얼은 체력전 없음
    this.mapChoice = 'flat';
    this.countdownMs = 0;
    this.dummyCounter = this.dummyCounter || 0;
    if (!this.startRound()) return false;
    for (const p of this.players.values()) p.home = { x: p.x, y: p.y };
    this.log('[연습] 시작');
    return true;
  }

  // 튜토리얼 (2026-10-29): 연습 판 위에서 단계 하나씩 (server/tutorial.js). id = 배우는 사람
  startTutorial(id) {
    if (!this.startPractice()) return false;
    this.tutorial = new Tutorial(this, id);
    return true;
  }

  // 토글·내 피해 %. 맞는 값이면 true
  practiceSet(id, key, value) {
    if (this.mode !== 'practice') return false;
    if (key === 'myDamage') {
      const p = this.players.get(id);
      const v = practiceDamage(value);
      if (!p || p.dummy || v === null) return false;
      p.practiceDamage = v;
      p.damage = v;
      return true;
    }
    if (!Object.hasOwn(this.practice, key) || typeof value !== 'boolean') return false;
    this.practice[key] = value;
    if (key === 'noBlocks' && value) {
      this.pieces = this.pieces.filter((pc) => pc.controller !== null || pc.thrownBy); // 떨어지던 자동·하늘 블록 치움 (조종·설치 블록은 그대로)
      this.refreshPieceCells();
      this.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
    }
    if (key === 'noBlocks' && !value) this.nextSpawnAt = this.time + C.FIRST_SPAWN_DELAY_MS;
    return true;
  }

  // 허수아비 추가: 보낸 사람 앞 PRACTICE_DUMMY_DIST 칸 (필드 안으로). 자리가 꽉 찼거나 PRACTICE_DUMMY_MAX 개면 null
  addDummy(byId) {
    if (this.mode !== 'practice' || this.dummies().length >= C.PRACTICE_DUMMY_MAX) return null;
    const id = -(1000 + ++this.dummyCounter);
    const p = this.addPlayer(id, true);
    if (!p) return null;
    const by = this.players.get(byId);
    const yaw = by ? by.yaw : 0;
    const clamp = (v, n) => Math.max(0.5, Math.min(n - 0.5, v));
    const x = clamp((by ? by.x : this.W / 2) + Math.cos(yaw) * C.PRACTICE_DUMMY_DIST, this.W);
    const y = clamp((by ? by.y : this.D / 2) + Math.sin(yaw) * C.PRACTICE_DUMMY_DIST, this.D);
    Object.assign(p, { name: `허수아비${this.dummyCounter}`, dummy: true, char: null, home: { x, y }, dummyDamage: 0, combo: null, lastCombo: null });
    this.practiceReset(p, null);
    p.yaw = yaw + Math.PI; // 나를 봄
    this.log(`[연습] ${p.name} 추가`);
    return p;
  }

  removeDummy(id) {
    const list = this.dummies();
    const d = id === undefined || id === null ? list[list.length - 1] : list.find((x) => x.id === id);
    if (!d) return false;
    d.alive = false; // 판 중에 나간 사람처럼 사망 기록을 남기지 않게
    this.removePlayer(d.id);
    return true;
  }

  setDummyDamage(id, value) {
    const v = practiceDamage(value);
    if (v === null) return false;
    const list = id === undefined || id === null ? this.dummies() : this.dummies().filter((d) => d.id === id);
    for (const d of list) {
      d.dummyDamage = v;
      if (!d.combo || !d.combo.active) d.damage = d.prevDamage = v; // 설정으로 바뀐 건 맞은 걸로 안 셈
    }
    return list.length > 0;
  }

  dummies() {
    return [...this.players.values()].filter((p) => p.dummy).sort((a, b) => a.id - b.id).reverse();
  }

  // 제자리로 (허수아비: 추가한 자리, 사람: 처음 자리). 피해 % 는 설정값. cause 가 있으면 떨어지거나 깔려서
  practiceReset(p, cause) {
    if (p.dummy && p.combo && p.combo.active) this.finishCombo(p);
    const home = p.home || this.spawnPoints[p.slot % this.spawnPoints.length];
    this.respawn(p);
    const z = this.spawnZ(home.x, home.y);
    Object.assign(p, { x: home.x, y: home.y, z, damage: p.dummy ? p.dummyDamage : p.practiceDamage || 0, shieldUntil: 0, spectator: false });
    p.prevX = p.x;
    p.prevY = p.y;
    p.prevZ = p.z;
    p.prevDamage = p.damage;
    p.prevCombo = 0;
    if (cause) this.emit({ type: 'practiceReset', who: p.id, cause });
  }

  // 들어온 친구: 관전 말고 바로 처음 자리에서
  practiceJoin(id) {
    const p = this.players.get(id);
    if (!p || this.mode !== 'practice' || !this.inRound()) return;
    p.home = { x: p.x, y: p.y };
    this.practiceReset(p, null);
  }

  // 틱마다: 쿨 없음·게이지 가득, 허수아비 콤보 기록·피해 % 되돌리기
  updatePractice() {
    const P = this.practice;
    for (const p of this.participants()) if (!p.alive && p.respawnAt && this.time >= p.respawnAt) this.practiceReset(p, null); // "안 죽음" 끔
    for (const p of this.players.values()) {
      if (!p.alive || p.dummy) continue;
      if (P.noCooldown && p.skillReadyAt > this.time) p.skillReadyAt = this.time;
      if (P.fullUlt && p.char) p.ult = this.ultMax(p);
    }
    for (const d of this.dummies()) {
      if (!d.alive) continue;
      const hit = d.damage > d.prevDamage || d.comboHits > d.prevCombo;
      if (hit) {
        if (!d.combo || !d.combo.active) d.combo = { active: true, hits: 0, damage: 0, dist: 0, height: 0, sx: d.prevX, sy: d.prevY, sz: d.prevZ, dmg0: d.prevDamage };
        d.combo.hits++;
        d.combo.damage = d.damage - d.combo.dmg0;
      }
      const c = d.combo;
      if (c && c.active) {
        c.dist = Math.max(c.dist, Math.hypot(d.x - c.sx, d.y - c.sy));
        c.height = Math.max(c.height, d.z - c.sz);
        if (hit) this.emit({ type: 'dummyCombo', id: d.id, ...comboOut(c), done: false });
        else if (d.comboHits === 0 && this.time >= d.stunUntil && d.grounded) this.finishCombo(d);
      } else if (d.grounded && d.damage !== d.dummyDamage) d.damage = d.dummyDamage;
      d.prevX = d.x;
      d.prevY = d.y;
      d.prevZ = d.z;
      d.prevDamage = d.damage;
      d.prevCombo = d.comboHits;
    }
  }

  // 허수아비 콤보 끝: 기록을 남기고 피해 % 를 설정값으로
  finishCombo(d) {
    const c = d.combo;
    c.active = false;
    d.lastCombo = comboOut(c);
    this.emit({ type: 'dummyCombo', id: d.id, ...d.lastCombo, done: true });
    d.damage = d.dummyDamage;
    d.prevDamage = d.damage;
  }

  practiceSnapshot() {
    return {
      ...this.practice,
      dummies: this.dummies().map((d) => ({ id: d.id, damageSet: d.dummyDamage, combo: d.combo ? { ...comboOut(d.combo), active: d.combo.active } : null, last: d.lastCombo })),
    };
  }
}
