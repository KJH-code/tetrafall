// 직접 해 보는 튜토리얼 (2026-10-29 재혁): 연습 모드 판 위에서 단계 하나씩. 단계가 바뀌면 지형(벽·계단)·허수아비·아이템을 다시 놓고,
// 틱마다·이벤트마다 완료를 판정 (shared/tutorial.js judge). 해내면 tutorialOk 이벤트 → TUTORIAL_NEXT_MS 뒤 다음 단계, 마지막이면 done.
// 넘기기(skip)는 언제든. 떨어져도·깔려도·용암에 닿아도 연습의 '안 죽음' 으로 그 단계 처음 자리 (용암은 처음 높이로)
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, cellOfShape } from '../shared/pieces.js';
import { tutorialLayout, tutorialSteps, judge, nextStep } from '../shared/tutorial.js';

export class Tutorial {
  constructor(game, playerId) {
    this.g = game;
    this.pid = playerId;
    this.i = 0;
    this.done = false;
    this.okAt = null;
    this.results = []; // 단계마다 'ok' | 'skip'
    const p = game.players.get(playerId);
    this.steps = tutorialSteps(p ? p.char : null); // 캐릭터에 없는 단계는 뺌 (바드 치명타)
    this.begin(0);
  }

  get step() {
    return this.steps[this.i];
  }

  me() {
    return this.g.players.get(this.pid) || null;
  }

  // 단계 시작: 지형·허수아비·아이템·토글을 단계 표대로, 나는 처음 자리로
  begin(i) {
    const g = this.g;
    this.i = i;
    this.okAt = null;
    const step = this.step;
    const L = (this.layout = tutorialLayout(step, g.W, g.D));
    this.ctx = { dummyMax: 0, dashed: false, ringout: false, crit: false, skill: false, ult: false, picked: false, itemUsed: false, dodged: 0, crushedAt: -Infinity };
    this.startAt = g.time;
    this.drop = null; // dodge: 지금 떨어지는 블록 { id, at }
    this.nextDropAt = g.time + C.TUTORIAL_DODGE_EVERY_MS;
    for (const d of g.dummies()) g.removeDummy(d.id);
    Object.assign(g.practice, { noCooldown: !!step.noCooldown, fullUlt: !!step.fullUlt, noBlocks: true, noDeath: true });
    const p = this.me();
    if (p) {
      p.home = { x: L.start.x, y: L.start.y };
      p.practiceDamage = 0;
      p.yaw = L.start.yaw;
      p.skillReadyAt = 0;
      if (!step.fullUlt) p.ult = 0;
      p.ammo = 0;
      p.bricks = 0;
      p.bombs = 0;
    }
    // 쌓인 블록처럼 보이는 칸 (튜토리얼 지형은 맵 지형이 아니라 오르는 블록): 단계마다 모양 색 하나
    const v = cellOfShape(SHAPE_NAMES[i % SHAPE_NAMES.length]);
    g.resetArena('flat', L.cells.map(([x, y, z]) => [x, y, z, v]));
    for (const d of L.dummies) this.addDummy(d.x, d.y, d.damage);
    for (const it of L.items) g.items.push({ type: it.type, x: Math.floor(it.x), y: Math.floor(it.y), z: g.columnTop(Math.floor(it.x), Math.floor(it.y)) });
    if (p && step.marks && p.char === 'hunter') for (const d of g.dummies()) for (let k = 0; k < step.marks; k++) g.addMark(p, d); // 사냥꾼 F·R 은 표식이 있어야
    if (step.kind === 'climb') g.lava = { active: true, z: C.TUTORIAL_LAVA_START_Z, startedAt: g.time };
    g.emit({ type: 'tutorialStep', i, id: step.id, yaw: L.start.yaw, who: this.pid });
    g.log(`[튜토리얼] ${i + 1}/${this.steps.length} ${step.id}`);
  }

  addDummy(x, y, damage) {
    const g = this.g;
    const d = g.addDummy(this.pid);
    if (!d) return null;
    d.home = { x, y };
    d.dummyDamage = damage;
    g.practiceReset(d, null);
    d.yaw = Math.PI; // 처음 자리(-x) 쪽을 봄
    return d;
  }

  onEvent(e) {
    if (this.done || this.okAt !== null) return;
    const c = this.ctx;
    const me = this.pid;
    if (e.type === 'hit' && e.by === me && e.crit) c.crit = true;
    else if (e.type === 'skill' && e.who === me) c.skill = true;
    else if (e.type === 'ult' && e.who === me) c.ult = true;
    else if (e.type === 'pickup' && e.who === me) c.picked = true;
    else if (e.type === 'practiceReset') {
      const d = this.g.players.get(e.who);
      if (d && d.dummy && e.cause === 'fall') c.ringout = true;
      if (e.who === me) {
        if (e.cause === 'crush') c.crushedAt = this.g.time;
        if (this.step.kind === 'climb') this.g.lava.z = C.TUTORIAL_LAVA_START_Z; // 다시 처음부터
      }
    }
  }

  // 넘기기: 지금 단계를 건너뜀 (체크 보여 주는 중이어도 바로 다음)
  skip() {
    if (this.done) return false;
    if (this.okAt === null) this.results[this.i] = 'skip';
    this.advance();
    return true;
  }

  advance() {
    const n = nextStep(this.i, this.steps.length);
    if (n === null) {
      this.done = true;
      this.okAt = null;
      for (const d of this.g.dummies()) this.g.removeDummy(d.id);
      this.g.lava = { active: false, z: C.LAVA_START_Z, startedAt: 0 };
      this.g.emit({ type: 'tutorialDone', who: this.pid, ok: this.results.filter((r) => r === 'ok').length });
      this.g.log('[튜토리얼] 끝');
      return;
    }
    this.begin(n);
  }

  update(dtMs) {
    if (this.done) return;
    const g = this.g;
    if (this.okAt !== null) {
      if (g.time >= this.okAt + C.TUTORIAL_NEXT_MS) this.advance();
      return;
    }
    const p = this.me();
    if (!p) return;
    const step = this.step;
    const c = this.ctx;
    if (p.dashReadyAt > this.startAt) c.dashed = true;
    // 허수아비 피해 % 는 콤보가 끝나도 안 돌아감 (진짜 판처럼 쌓임)
    for (const d of g.dummies()) {
      if (d.damage > d.dummyDamage) d.dummyDamage = d.damage;
      c.dummyMax = Math.max(c.dummyMax, d.damage);
    }
    const held = p.ammo + p.bricks + p.bombs;
    if (c.picked && c.lastHeld !== undefined && held < c.lastHeld) c.itemUsed = true;
    c.lastHeld = held;
    if (step.kind === 'dodge') this.updateDodge(p);
    if (step.kind === 'climb') this.updateLava(p, dtMs);
    const ok = judge(step, { ...c, me: { x: p.x, y: p.y, z: p.z, grounded: p.grounded && p.alive }, target: this.layout.target });
    if (ok) {
      this.okAt = g.time;
      this.results[this.i] = 'ok';
      g.emit({ type: 'tutorialOk', i: this.i, id: step.id, who: this.pid });
      g.log(`[튜토리얼] ${step.id} 해냄 (${((g.time - this.startAt) / 1000).toFixed(1)}초)`);
    }
  }

  // 그림자 보고 피하기: 내 자리를 덮는 O 블록을 낮은 데서 하나씩. 내려앉았는데 그동안 안 깔렸으면 하나 피함
  updateDodge(p) {
    const g = this.g;
    if (this.drop) {
      if (g.pieces.some((pc) => pc.id === this.drop.id)) return;
      if (this.ctx.crushedAt < this.drop.at) this.ctx.dodged++;
      this.drop = null;
      this.nextDropAt = g.time + C.TUTORIAL_DODGE_EVERY_MS;
      return;
    }
    if (g.time < this.nextDropAt || !p.alive) return;
    const px = Math.max(0, Math.min(g.W - 2, Math.floor(p.x) - (g.rng() < 0.5 ? 1 : 0)));
    const py = Math.max(0, Math.min(g.D - 2, Math.floor(p.y) - (g.rng() < 0.5 ? 1 : 0)));
    const top = Math.max(g.columnTop(px, py), g.columnTop(px + 1, py), g.columnTop(px, py + 1), g.columnTop(px + 1, py + 1));
    const pz = Math.min(g.H - 1, top + C.TUTORIAL_DODGE_DROP_Z);
    const piece = g.makePiece('O', 0, px, py, pz);
    const stepMs = C.TUTORIAL_DODGE_STEP_MS;
    g.addPiece(piece, { phase: 'falling', controller: null, stepMs, nextStepAt: g.time + stepMs, controlEndsAt: 0 });
    this.drop = { id: piece.id, at: g.time };
  }

  // 용암: 천천히 오르다 꼭대기 조금 아래에서 멈춤. 닿으면 처음 자리 (practiceReset → onEvent 가 용암도 처음 높이로)
  updateLava(p, dtMs) {
    const g = this.g;
    const top = this.step.z - C.TUTORIAL_LAVA_TOP_GAP;
    g.lava.z = Math.min(top, g.lava.z + dtMs / C.TUTORIAL_LAVA_MS_PER_CELL);
    if (p.alive && g.onField(p) && p.z < g.lava.z - 0.05) g.kill(p, 'lava');
  }

  snapshot() {
    const t = this.layout.target;
    return {
      i: this.i,
      n: this.steps.length,
      id: this.done ? null : this.step.id,
      ok: this.okAt !== null,
      done: this.done,
      target: !this.done && t ? { x: t.x, y: t.y, z: t.z } : null,
      dodged: this.ctx.dodged,
      results: this.results,
    };
  }
}
