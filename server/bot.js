// 서버 안에서 도는 AI 봇. 사람과 똑같이 handleInput / handleAction 으로만 조작한다 (판정 특혜 없음).
// BOT_THINK_MS 마다 한 번 판단하고, 그 사이에는 마지막 입력을 유지한다.
// 사람처럼 보이게: 그림자를 보고 BOT_REACTION_MS 뒤에야 피하기 시작하고, 조준에는 오차가 있다.
import { CONFIG as C, basicSet } from '../shared/config.js';
import { rotatedCells, footprint } from '../shared/pieces.js';

// 판 크기 (인원마다 다름): 봇이 판단할 때마다 그 게임의 크기로 맞춤 (update·useSkills 첫머리). 한 프로세스의 방들이 차례로 돌아서 안전
let W = C.GRID_W;
let D = C.GRID_D;

function pieceKey(piece) {
  return `${piece.id}:${piece.px},${piece.py},${piece.rot},${piece.stepMs}`;
}


function edgeDist(x, y) {
  return Math.min(x, W - x, y, D - y);
}

function clampIn(v, max) {
  return Math.max(0.45, Math.min(max - 0.45, v));
}

// 플레이어 AABB 가 칸 목록 중 하나와 겹치는가 (xy 만)
function overlapsCells(p, cells) {
  const h = C.PLAYER_HALF;
  for (const [cx, cy] of cells) {
    if (cx < p.x + h && cx + 1 > p.x - h && cy < p.y + h && cy + 1 > p.y - h) return true;
  }
  return false;
}

export class BotBrain {
  // level(): 지금 봇 난이도 ('easy' | 'normal' | 'hard'). 게임이 바꾸면 다음 판단부터 바로 반영
  constructor(rng = Math.random, level = () => C.BOT_LEVEL_DEFAULT) {
    this.rng = rng;
    this.level = level;
    this.nextThinkAt = 0;
    this.input = { fwd: 0, strafe: 0, jump: false, yaw: 0, pitch: 0 };
    this.dangerSeen = new Map(); // 블록 위치 키 -> 그림자를 처음 본 시각 (반응 시간 계산용)
    this.threatSeen = new Map(); // 상대 예고 키 -> { at(처음 본 시각), dodge(피할지 — 예고마다 한 번 정함) }
    this.aimedAt = null; // 조종 중: 목표 위에 맞춘 시각
    this.dropOffset = null; // 조종 중: 이 블록에서 겨냥을 빗나가게 할 만큼 { piece, x, y }
    this.lastPos = null;
    this.stuckMs = 0;
    this.unstickUntil = 0;
    this.unstickDir = 1;
    this.nextPushAt = 0; // 봇 자신의 밀치기 간격 (사람처럼 연타하지 않게)
    this.chainDelay = 0; // 평타 이어 치기 누르는 지연
    this.nextSkillAt = 0; // 캐릭터 스킬·필살기를 다시 써 볼 시각
    // 상대 고를 때 판마다 다시 뽑는 무작위 가산 거리. 거리가 같으면 늘 목록 맨 앞(사람)을 고르던 버그 수정:
    // 4인 판에서 봇 둘이 시작하자마자 사람을 협공했다 (2026-10-20 로그 3·16·17판, 재현 200판 중 200판)
    this.targetBias = new Map();
    this.biasRound = -1;
  }

  // 난이도가 걸린 수치: BOT_<name> × 난이도 배수
  k(name) {
    return C[`BOT_${name}`] * (C.BOT_LEVELS[this.level()]?.[name] ?? 1);
  }

  update(g, p) {
    W = g.W;
    D = g.D;
    if (!p.alive || g.phase !== 'playing') return;
    if (g.time < this.nextThinkAt) {
      g.handleInput(p.id, this.input);
      return;
    }
    this.nextThinkAt = g.time + C.BOT_THINK_MS;
    this.trackStuck(g, p);
    this.think(g, p);
    g.handleInput(p.id, this.input);
  }

  trackStuck(g, p) {
    if (this.lastPos && this.input.fwd) {
      const moved = Math.hypot(p.x - this.lastPos.x, p.y - this.lastPos.y);
      this.stuckMs = moved < 0.05 ? this.stuckMs + C.BOT_THINK_MS : 0;
    } else {
      this.stuckMs = 0;
    }
    this.lastPos = { x: p.x, y: p.y };
    if (this.stuckMs >= 500) {
      this.unstickUntil = g.time + 400;
      this.unstickDir = this.rng() < 0.5 ? -1 : 1;
      this.stuckMs = 0;
    }
  }

  // ---------- 상황 읽기 ----------
  enemies(g, p) {
    return [...g.players.values()].filter((o) => o !== p && g.onField(o) && !g.sameTeam(o, p)); // 팀전이면 같은 팀은 상대가 아님, 블록 마스터의 마스터는 필드에 없음
  }

  // 그림자가 보이는 떨어지는 블록들 → 각각의 발자국 칸·남은 시간·위치 키
  // p 를 주면 발밑보다 낮은 하늘 계단 블록은 뺌 (올라타 있는 블록이 착지해도 위험이 아님)
  visibleDangers(g, p = null) {
    const out = [];
    for (const piece of g.pieces) {
      if (piece.phase !== 'falling') continue;
      if (p && piece.sky && piece.pz + 1 <= p.z + 0.05) continue;
      const eta = Math.max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - g.time));
      if (!g.shadowVisible(piece, eta)) continue;
      out.push({ cells: piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]), eta, key: pieceKey(piece) });
    }
    // 놓인 폭탄: 폭발 범위(중심에서 BOMB_BLAST_RANGE 칸)를 위험 칸으로. 떨어지는 블록처럼 반응 시간 뒤에 피한다
    const R = Math.ceil(C.BOMB_BLAST_RANGE);
    for (const b of g.bombs) {
      const cells = [];
      for (let dx = -R; dx <= R; dx++) for (let dy = -R; dy <= R; dy++) if (Math.hypot(dx, dy) <= C.BOMB_BLAST_RANGE + C.BOT_BOMB_DANGER_PAD) cells.push([b.x + dx, b.y + dy]);
      out.push({ cells, eta: Math.max(0, b.explodeAt - g.time), key: `bomb:${b.id}` });
    }
    return out;
  }

  // 나를 노리는 상대 예고: { key, o(상대), left(남은 ms), radial(범위 공격이면 바깥으로) }
  telegraphs(g, p, enemies) {
    const out = [];
    for (const o of enemies) {
      const dx = p.x - o.x;
      const dy = p.y - o.y;
      const d = Math.hypot(dx, dy);
      if (Math.abs(p.z - o.z) > 2.5) continue;
      // 보는 방향 앞 직선·부채꼴 안인가
      const ahead = (yaw, len, half) => {
        const along = dx * Math.cos(yaw) + dy * Math.sin(yaw);
        const side = Math.abs(-dx * Math.sin(yaw) + dy * Math.cos(yaw));
        return along > -0.3 && along <= len && side <= half;
      };
      const inCone = (yaw, len, deg) => d <= len && (d < 0.5 || (dx * Math.cos(yaw) + dy * Math.sin(yaw)) / d >= Math.cos(((deg / 2) * Math.PI) / 180));
      if (o.windup) {
        const reach = o.char === 'tank' ? C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000) : o.char === 'ninja' ? C.NINJA_BLINK_DIST : C.HOOK_RANGE;
        if (ahead(o.windup.yaw, reach + 0.5, 0.9)) out.push({ key: `${o.id}:windup:${o.windup.at}`, o, left: o.windup.at - g.time });
      }
      if (o.slamAt && d <= C.TANK_SLAM_RANGE + C.TANK_RING_WIDTH + 0.3) out.push({ key: `${o.id}:slam:${o.slamAt}`, o, left: o.slamAt - g.time, radial: true });
      if (o.atk && o.atk.def.finish && !o.atk.def.shell && ahead(o.yaw, (o.atk.def.range || C.PUSH_RANGE) + 0.4, 1)) out.push({ key: `${o.id}:fin:${o.atk.at}`, o, left: o.atk.at - g.time });
      if (o.leap && !o.leap.endAt && o.leap.target === p.id) out.push({ key: `${o.id}:leap:${o.leap.at}`, o, left: o.leap.at - g.time });
      if (o.huntAim && g.markOf(o, p) > 0 && inCone(o.yaw, C.HUNTER_SHOT_RANGE, C.HUNTER_SHOT_ANGLE_DEG)) out.push({ key: `${o.id}:aim:${o.huntAim.at}`, o, left: o.huntAim.at - g.time });
      if (o.spin && d <= C.BERSERKER_SPIN_END_RANGE + 0.5) out.push({ key: `${o.id}:spin:${o.spin.endAt}`, o, left: o.spin.endAt - g.time, radial: true });
      if (o.amp && inCone(g.ampYaw(o), C.BARD_AMP_RANGE + 0.5, C.BARD_AMP_ANGLE_DEG + 10)) out.push({ key: `${o.id}:amp:${o.amp.endAt}`, o, left: o.amp.endAt - g.time });
    }
    return out;
  }

  // 예고를 처음 본 뒤 BOT_REACTION_MS 가 지나면, 예고마다 한 번 정한 확률로 옆(범위 공격이면 바깥)으로 피함. 피했으면 true
  dodgeTelegraph(g, p, enemies, avoid) {
    const threats = this.telegraphs(g, p, enemies);
    const live = new Set(threats.map((t) => t.key));
    for (const k of [...this.threatSeen.keys()]) if (!live.has(k)) this.threatSeen.delete(k);
    if (g.time < p.stunUntil) return false;
    const chance = Math.min(C.BOT_DODGE_CHANCE_MAX, this.k('DODGE_CHANCE'));
    for (const t of threats) {
      if (!this.threatSeen.has(t.key)) this.threatSeen.set(t.key, { at: g.time, dodge: this.rng() < chance });
      const seen = this.threatSeen.get(t.key);
      if (!seen.dodge || g.time - seen.at < this.k('REACTION_MS') || t.left <= 0) continue;
      const dx = p.x - t.o.x;
      const dy = p.y - t.o.y;
      const d = Math.hypot(dx, dy) || 1;
      // 후보: 바깥 (범위 공격) 또는 양옆 → 필드 안쪽으로 더 남는 쪽
      const dirs = t.radial ? [[dx / d, dy / d], [-dy / d, dx / d], [dy / d, -dx / d]] : [[-dy / d, dx / d], [dy / d, -dx / d]];
      let best = null;
      for (const [ux, uy] of dirs) {
        const spot = { x: p.x + ux * C.BOT_DODGE_STEP, y: p.y + uy * C.BOT_DODGE_STEP };
        const e = edgeDist(spot.x, spot.y);
        if (e < 0.8) continue;
        if (!best || e > best.e) best = { spot, e };
      }
      if (!best) continue;
      this.moveTo(g, p, best.spot, avoid);
      if (t.left < C.BOT_DODGE_DASH_MS && g.time >= p.dashReadyAt) {
        g.handleInput(p.id, this.input);
        g.handleAction(p.id, { name: 'dash' });
      }
      return true;
    }
    return false;
  }

  // ---------- 판단 ----------
  think(g, p) {
    this.input.jump = false;
    if (this.biasRound !== g.roundNumber) {
      this.biasRound = g.roundNumber;
      this.targetBias.clear();
    }
    const enemies = this.enemies(g, p);
    const dangers = this.visibleDangers(g, p);

    // 그림자를 처음 본 순간부터 반응 시간이 지나야 "안다"
    const live = new Set();
    for (const d of dangers) {
      live.add(d.key);
      if (!this.dangerSeen.has(d.key)) this.dangerSeen.set(d.key, g.time);
    }
    for (const k of [...this.dangerSeen.keys()]) if (!live.has(k)) this.dangerSeen.delete(k);
    const known = dangers.filter((d) => g.time - this.dangerSeen.get(d.key) >= this.k('REACTION_MS'));
    const avoid = known.flatMap((d) => d.cells);
    const danger = dangers.length ? dangers[0] : null;

    const mine = g.controlledPiece(p);
    if (p.master) {
      // 블록 마스터: 몸은 필드에 없음. 블록만 상대 위로 몬다 (다음 블록을 기다리는 동안은 아무것도 안 함)
      this.input.fwd = 0;
      this.input.strafe = 0;
      if (mine) this.controlPiece(g, p, enemies, mine);
      return;
    }
    if (mine) {
      this.controlPiece(g, p, enemies, mine);
      // 캐릭터는 내 블록 밑·가장자리·아는 그림자를 피해 가만히 (용암이 오면 올라간다)
      const hover = g.pieceWorldCells(mine).map(([x, y]) => [x, y]);
      if (!this.climbFromLava(g, p, avoid)) this.moveTo(g, p, this.safeSpot(g, p, hover.concat(avoid), null), avoid);
      return;
    }

    // 0.5) 복귀 (바드): 음유시인이면 공중 평타로 천천히 낙하하며 안쪽으로, 메탈이면 F 로 음유시인이 된 뒤
    if (p.char === 'bard' && !p.grounded && p.vz < 0 && p.z < -0.3 && g.time >= p.stunUntil) {
      this.moveTo(g, p, { x: W / 2, y: D / 2 });
      g.handleInput(p.id, this.input);
      if (p.form !== 'metal' && !p.glideUntil) g.handleAction(p.id, { name: 'push' });
      else if (p.form === 'metal' && g.time >= p.skillReadyAt) g.handleAction(p.id, { name: 'skill' });
      return;
    }

    // 0.5) 복귀: 필드 밖으로 떨어지는 중이면 공중 F 를 쓰고 안쪽으로 (건축가 발판 + 부스트, 닌자 순간 베기 → 막히면 벽 차기,
    // 갈고리는 안쪽 방향에 걸 블록이 있을 때만)
    const toCenter = Math.atan2(D / 2 - p.y, W / 2 - p.x);
    if ((p.char === 'builder' || p.char === 'ninja' || p.char === 'hunter' || p.char === 'cannon' || p.char === 'berserker' || (p.char === 'hook' && g.hookRayBlock(p, toCenter, 0))) && !p.grounded && p.vz < 0 && p.z < -0.3 && g.time >= p.skillReadyAt && g.time >= p.stunUntil) {
      this.moveTo(g, p, { x: W / 2, y: D / 2 });
      g.handleInput(p.id, this.input);
      g.handleAction(p.id, { name: 'skill' });
      return;
    }

    // 0.8) 상대 예고 피하기 (반응 시간 뒤, 예고마다 정한 확률로)
    if (this.dodgeTelegraph(g, p, enemies, avoid)) return;

    // 1) 피하기
    const hit = known.filter((d) => overlapsCells(p, d.cells));
    if (hit.length) {
      const spot = this.safeSpot(g, p, avoid, null);
      this.moveTo(g, p, spot);
      const dist = Math.hypot(spot.x - p.x, spot.y - p.y);
      const eta = Math.min(...hit.map((d) => d.eta));
      if (dist > 0.8 && eta < 900 && g.time >= p.dashReadyAt) g.handleAction(p.id, { name: 'dash' });
      return;
    }

    // 1.5) 용암이 다가오면 높은 곳으로 (하늘 계단이면 공중 블록 먼저). 올라갈 길이 없으면 설치 블록으로 발판을 만든다
    if (this.skyHop(g, p)) return;
    if (this.climbFromLava(g, p, avoid)) return;
    if (this.brickStep(g, p)) return;

    // 2) 가장자리에 너무 붙었으면 안쪽으로
    if (edgeDist(p.x, p.y) < 0.75) {
      this.moveTo(g, p, { x: W / 2, y: D / 2 }, avoid);
      return;
    }

    const target = this.nearest(p, enemies);

    // 2.5) 캐릭터 스킬·필살기 (캐릭터가 없는 게임은 건너뜀 → 난수 순서도 그대로)
    if (target && p.char && g.time >= this.nextSkillAt && this.useSkills(g, p, target, enemies, avoid)) {
      this.nextSkillAt = g.time + this.k('SKILL_INTERVAL_MS') * (0.7 + 0.6 * this.rng());
      return;
    }

    // 3) 투사체: 보이면 쏜다
    if (target && p.ammo > 0 && this.canShoot(g, p, target)) {
      this.aimAt(p, target);
      g.handleInput(p.id, this.input);
      g.handleAction(p.id, { name: 'fire' });
      this.input.fwd = 0;
      return;
    }

    // 3.5) 설치 블록: 용암 전에는 앞 칸에 선 상대 위에 놓아 밀어낸다 (용암이 켜지면 발판용으로 아낌)
    if (target && p.bricks > 0 && !g.lava.active && this.brickOnTarget(g, p, target)) return;
    // 3.6) 폭탄: 상대가 터지는 범위에 들면 던진다
    if (target && p.bombs > 0 && this.bombOnTarget(g, p, target)) return;

    // 4) 아이템: 내가 상대보다 가깝거나 비슷하면 먹으러 간다
    const item = this.pickItem(g, p, target);
    if (item) {
      this.moveTo(g, p, { x: item.x + 0.5, y: item.y + 0.5 }, avoid);
      // 낭떠러지에 막혀 한 발도 못 가면 아이템은 포기하고 공격으로 (안 그러면 못 가는 아이템 앞에 영원히 서 있음)
      if (this.input.fwd || Math.hypot(item.x + 0.5 - p.x, item.y + 0.5 - p.y) < 0.5) return;
    }

    // 5) 밀치기: 상대를 가장자리(또는 그림자) 쪽으로 밀 수 있는 자리로 돌아가서 민다
    if (target) {
      this.attack(g, p, target, danger, avoid);
      return;
    }
    this.moveTo(g, p, { x: W / 2, y: D / 2 }, avoid);
  }

  nearest(p, list) {
    let best = null;
    let bd = Infinity;
    for (const o of list) {
      if (!this.targetBias.has(o.id)) this.targetBias.set(o.id, this.rng() * C.BOT_TARGET_JITTER);
      const d = Math.hypot(o.x - p.x, o.y - p.y) + this.targetBias.get(o.id);
      if (d < bd) {
        bd = d;
        best = o;
      }
    }
    return best;
  }

  pickItem(g, p, target) {
    let best = null;
    let bd = Infinity;
    for (const it of g.items) {
      // 이미 가진·켜진 효과는 또 먹으러 가지 않는다
      if (C.HELD_ITEMS.includes(it.type) && g.heldItem(p)) continue; // 손 아이템은 하나만 (들고 있으면 못 주움)
      if (it.type === 'jump' && g.time < p.jumpUntil) continue;
      if (it.type === 'ghost' && g.time < p.ghostUntil) continue;
      if (it.z - p.z > this.jumpReach(g, p) + 0.15 || p.z - it.z > 6) continue; // 못 올라가는 높이·너무 아래면 안 감
      const d = Math.hypot(it.x + 0.5 - p.x, it.y + 0.5 - p.y);
      const de = target ? Math.hypot(it.x + 0.5 - target.x, it.y + 0.5 - target.y) : Infinity;
      if (d > de + 1) continue;
      if (d < bd) {
        bd = d;
        best = it;
      }
    }
    return best;
  }

  // 대포수 조준 오차 (좌우·위아래 각각 ±BOT_SHELL_AIM_ERROR_RAD)
  rollShellErr() {
    const e = this.k('SHELL_AIM_ERROR_RAD');
    this.shellErr = { yaw: (this.rng() * 2 - 1) * e, pitch: (this.rng() * 2 - 1) * e };
  }

  // 다음 평타 타의 사거리
  basicRange(p, g) {
    const set = basicSet(p.char, p.form);
    const n = Math.min(p.chainN, set.chain.length - 1); // 다음 지상 타 (0부터)
    if (p.char === 'ninja' && g && g.time < p.empowerUntil && n < 3) return C.NINJA_STAR.range; // R 강화 표창
    const d = set.chain[n];
    return d.range || C.PUSH_RANGE;
  }

  attack(g, p, t, dangerIn, avoid) {
    let danger = dangerIn;
    // 상대를 밀 방향: 그림자가 상대 근처면 그림자 쪽, 아니면 상대에게 가장 가까운 가장자리 쪽
    let dir = null;
    if (danger) {
      // 그림자 여러 개 중 상대에게 가장 가까운 것
      let best = null;
      let bd = Infinity;
      for (const d of g.pieces.length ? this.visibleDangers(g) : []) {
        const cx0 = d.cells.reduce((a, c) => a + c[0] + 0.5, 0) / d.cells.length;
        const cy0 = d.cells.reduce((a, c) => a + c[1] + 0.5, 0) / d.cells.length;
        const dd = Math.hypot(cx0 - t.x, cy0 - t.y);
        if (dd < bd) {
          bd = dd;
          best = d;
        }
      }
      danger = best || danger;
      const cx = danger.cells.reduce((a, c) => a + c[0] + 0.5, 0) / danger.cells.length;
      const cy = danger.cells.reduce((a, c) => a + c[1] + 0.5, 0) / danger.cells.length;
      const d = Math.hypot(cx - t.x, cy - t.y);
      if (d < 1.8 && d > 0.2) dir = { x: (cx - t.x) / d, y: (cy - t.y) / d };
    }
    if (!dir) {
      const opts = [
        { d: t.x, x: -1, y: 0 },
        { d: W - t.x, x: 1, y: 0 },
        { d: t.y, x: 0, y: -1 },
        { d: D - t.y, x: 0, y: 1 },
      ].sort((a, b) => a.d - b.d);
      dir = opts[0];
    }
    const dist = Math.hypot(t.x - p.x, t.y - p.y);
    const toT = { x: (t.x - p.x) / (dist || 1), y: (t.y - p.y) / (dist || 1) };
    // 대포수: 탄이 있으면 거리를 두고 상대 가슴을 조준해 쏨, 너무 붙으면 (가장자리가 아니면) 물러남
    if (p.char === 'cannon' && p.cannonAmmo > 0 && dist <= C.CANNON_SHELL_RANGE * 0.7) {
      const dz = t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.2);
      const err = this.shellErr || { yaw: 0, pitch: 0 }; // 쏠 때마다 새 조준 오차 (사람처럼 빗나감)
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x) + err.yaw;
      this.input.pitch = Math.atan2(dz, dist) + err.pitch;
      this.input.fwd = dist < 2.5 && edgeDist(p.x - toT.x * 1.5, p.y - toT.y * 1.5) > 1 ? -1 : 0;
      this.input.strafe = 0;
      g.handleInput(p.id, this.input);
      if (!p.atk && g.time >= p.pushReadyAt && g.time >= this.nextPushAt) {
        g.handleAction(p.id, { name: 'push' });
        this.nextPushAt = g.time + this.k('PUSH_INTERVAL_MS') * 0.5 * (0.7 + 0.6 * this.rng());
        this.rollShellErr(); // 다음 발 오차 (이번 발은 준비 동안 지금 오차로 조준)
      }
      return;
    }
    if (p.char === 'cannon') this.input.pitch = 0;
    // 바드 음유시인: 거리를 두고 류트 음파 (둔화)
    if (p.char === 'bard' && p.form !== 'metal' && dist <= C.BARD_NOTE_RANGE * 0.8) {
      const dz = t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.3);
      const err = this.shellErr || { yaw: 0, pitch: 0 };
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x) + err.yaw;
      this.input.pitch = Math.atan2(dz, dist) + err.pitch;
      this.input.fwd = dist < 2 && edgeDist(p.x - toT.x * 1.5, p.y - toT.y * 1.5) > 1 ? -1 : 0;
      this.input.strafe = 0;
      g.handleInput(p.id, this.input);
      if (!p.atk && g.time >= p.pushReadyAt && g.time >= this.nextPushAt) {
        g.handleAction(p.id, { name: 'push' });
        this.nextPushAt = g.time + this.k('PUSH_INTERVAL_MS') * 0.5 * (0.7 + 0.6 * this.rng());
        this.rollShellErr();
      }
      return;
    }
    if (p.char === 'bard') this.input.pitch = 0;
    // 닌자·탱크: 지상 마지막 타(올려 차기·방패 올려치기)로 띄운 상대를 점프해 따라가 공중 평타
    const lb = p.lastBasic;
    const launcher = p.char && !basicSet(p.char, p.form).chain.at(-1).finish;
    if (launcher && lb && !lb.air && lb.n === basicSet(p.char, p.form).chain.length && g.time - lb.at < 900 && t.z > p.z + 0.4 && g.time < t.stunUntil && dist < 2) {
      this.input.fwd = dist > 0.8 ? 1 : 0;
      this.input.strafe = 0;
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x);
      this.input.jump = p.grounded;
      g.handleInput(p.id, this.input);
      if (!p.grounded && p.vz < 2 && p.airJumps > 0 && t.z > p.z + 1) g.handleAction(p.id, { name: 'jump' });
      if (!p.grounded && Math.abs(t.z - p.z) < 1.4 && !p.atk) g.handleAction(p.id, { name: 'push' }); // 공중 1타 → (창 안에) 공중 2타 (탱크는 공중 1타가 마무리)
      return;
    }
    // 캐릭터 평타: 앞 타가 끝나고 창 안이면 상대를 보고 다음 타 (난이도별로 조금 늦게 누름). 준비 중에는 계속 상대를 봄
    if (p.char && (p.atk || ((p.chainN > 0 || p.airN > 0) && g.time < p.chainUntil && dist < this.basicRange(p, g) * 0.95))) {
      this.input.fwd = 0;
      this.input.strafe = 0;
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x);
      g.handleInput(p.id, this.input);
      if (!p.atk && g.time >= p.pushReadyAt + this.chainDelay - C.BOT_THINK_MS) {
        // 한 판단 주기 먼저 눌러 둠 (후딜 중 누르면 기다렸다 나감) → 실제 지연은 0 ~ chainDelay 쯤
        g.handleAction(p.id, { name: 'push' });
        this.chainDelay = this.k('CHAIN_DELAY_MS') * (0.7 + 0.6 * this.rng());
      }
      return;
    }
    // 겹쳐 서 있으면 (사람끼리는 안 부딪힘) 상대 쪽 방향이 없음 → 밀 방향으로 바로 민다
    // (안 그러면 "뒤로 돌아가기" 자리가 낭떠러지일 때 둘 다 겹친 채 영원히 멈춤)
    const overlap = dist < 0.3;
    const lined = overlap || toT.x * dir.x + toT.y * dir.y > 0.5; // 내가 상대 "뒤"에 있다
    if (dist < (p.char === 'ninja' ? this.basicRange(p, g) : C.PUSH_RANGE) * 0.85 && (lined || edgeDist(p.x, p.y) < 1.2)) { // 닌자 R 강화 중엔 표창 사거리
      this.input.fwd = 0;
      this.input.strafe = 0;
      this.input.yaw = overlap ? Math.atan2(dir.y, dir.x) : Math.atan2(t.y - p.y, t.x - p.x);
      // 상대가 경직이 풀리고 무적도 아닐 때, 또는 내가 넣은 콤보(스킬 등)가 이어지는 중이면 평타로 잇기
      const free = g.time >= t.stunUntil && g.time >= t.iframeUntil;
      const myCombo = p.char && t.comboHits > 0 && g.time < t.stunUntil && t.lastHit?.by === p.id;
      if (g.time >= p.pushReadyAt && (free || myCombo) && (myCombo || g.time >= this.nextPushAt)) {
        g.handleInput(p.id, this.input);
        g.handleAction(p.id, { name: 'push' });
        this.nextPushAt = g.time + this.k('PUSH_INTERVAL_MS') * (0.7 + 0.6 * this.rng());
        return;
      }
      if (g.time < this.nextPushAt) {
        // 다음 밀치기까지는 상대 주변을 돌며 "뒤"를 잡으러 간다 (붙어서 가만히 있지 않는다)
        const side = { x: -dir.y, y: dir.x };
        this.moveTo(g, p, { x: clampIn(t.x - dir.x * 1.2 + side.x * 0.6, W), y: clampIn(t.y - dir.y * 1.2 + side.y * 0.6, D) }, avoid);
      }
      return;
    }
    const spot = { x: clampIn(t.x - dir.x * 1.0, W), y: clampIn(t.y - dir.y * 1.0, D) };
    this.moveTo(g, p, spot, avoid);
  }

  // 캐릭터마다 간단한 규칙. 썼으면 true
  // 돌진·순간 베기 길(보는 방향 len 칸)이 피할 칸(떨어지는 블록 그림자·폭탄)을 지나가나.
  // 2026-10-25 재혁 로그 4판: 봇이 설치 블록을 던지고 그 착지 자리로 돌진해 자기 블록에 깔림
  pathHits(p, yaw, len, cells) {
    for (let d = 0; d <= len + 1e-9; d += 0.25) if (overlapsCells({ x: p.x + Math.cos(yaw) * d, y: p.y + Math.sin(yaw) * d }, cells)) return true;
    return false;
  }

  useSkills(g, p, t, enemies, avoid = []) {
    W = g.W;
    D = g.D;
    const dist = Math.hypot(t.x - p.x, t.y - p.y);
    const ultReady = p.ult >= g.ultMax(p);
    const skillReady = g.time >= p.skillReadyAt;
    const near = (r) => enemies.filter((o) => Math.hypot(o.x - p.x, o.y - p.y) <= r && Math.abs(o.z - p.z) <= 2);
    const face = () => {
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x);
      this.input.pitch = 0;
    };
    const act = (name) => {
      g.handleInput(p.id, this.input);
      const before = name === 'ult' ? p.ult : p.skillReadyAt;
      g.handleAction(p.id, { name });
      return name === 'ult' ? p.ult !== before : p.skillReadyAt > g.time; // 실제로 쓰였나 (자리 없음 등으로 안 쓰이면 쿨이 안 걸림)
    };
    const comboing = g.time < t.stunUntil && t.comboHits > 0; // 상대가 내 콤보에 걸려 있음 → 스킬로 이어 감
    const level = Math.abs(t.z - p.z) < 1;
    if (p.char === 'tank') {
      if (ultReady && near(C.TANK_SLAM_RANGE + C.TANK_RING_WIDTH * 0.5).length) return act('ult'); // 바깥 고리까지
      // 상대가 공격을 준비하면 아머 돌진으로 뚫고 들어감
      const reachNow = C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000);
      // 상대 평타 준비를 보고 아머 돌진: 사람처럼 BOT_REACTION_MS 뒤에야 반응 (2026-10-26 재혁: 봇 탱크가 100ms 안에 읽어 1:1 이 셌음)
      const atkSeen = t.atk ? g.time - (t.atk.at - t.atk.def.windup) : 0;
      if (skillReady && level && t.atk && atkSeen >= this.k('REACTION_MS') && dist <= reachNow && !this.pathHits(p, Math.atan2(t.y - p.y, t.x - p.x), dist, avoid)) {
        face();
        return act('skill');
      }
      const reach = C.TANK_CHARGE_SPEED * (C.TANK_CHARGE_MS / 1000);
      if (skillReady && level && dist >= 1 && dist <= reach && !this.pathHits(p, Math.atan2(t.y - p.y, t.x - p.x), Math.min(reach, dist + 0.5), avoid)) {
        face(); // 돌진
        return act('skill');
      }
    } else if (p.char === 'ninja') {
      if (ultReady && dist <= C.NINJA_STAR.range + 1) return act('ult'); // 강화 (표창 2연)
      if (skillReady && level && dist <= C.NINJA_BLINK_DIST && (comboing || dist > 1.5)) {
        const yaw = Math.atan2(t.y - p.y, t.x - p.x);
        const land = Math.min(C.NINJA_BLINK_DIST, dist + C.NINJA_BLINK_BEHIND); // 상대 바로 뒤에서 멈춤
        if (edgeDist(p.x + Math.cos(yaw) * land, p.y + Math.sin(yaw) * land) < 0.8) return false; // 떨어질 자리로는 안 감
        if (this.pathHits(p, yaw, land, avoid)) return false; // 블록 그림자로는 안 감
        face();
        return act('skill');
      }
    } else if (p.char === 'builder') {
      // 내 블록 옆에 상대가 있으면 블록을 쳐서 터뜨림 (블록 너머 상대 쪽으로 날아감)
      for (const b of g.bblocks.values()) {
        if (b.owner !== p.id || b.kind === 'pad' || g.time < p.pushReadyAt || p.atk) continue; // 봇은 발판을 일부러 치지 않음 (밟고 있다 떨어질 수 있어서)
        const bx = b.x + 0.5;
        const by = b.y + 0.5;
        const db = Math.hypot(bx - p.x, by - p.y);
        if (db > C.PUSH_RANGE || Math.abs(b.z - p.z) > 1) continue;
        const ahead = ((t.x - bx) * (bx - p.x) + (t.y - by) * (by - p.y)) / (db || 1); // 블록 너머 쪽
        if (Math.hypot(t.x - bx, t.y - by) > C.BUILDER_BLAST_RANGE + 0.8 || ahead < -0.3) continue;
        this.input.yaw = Math.atan2(by - p.y, bx - p.x);
        g.handleInput(p.id, this.input);
        g.handleAction(p.id, { name: 'push' });
        return true;
      }
      // 대폭발: 상대가 앞 3×3 (1칸 띄우고) 쯤에 있으면
      const bigFrom = C.BUILDER_BIG_GAP + 1;
      if (ultReady && level && dist >= bigFrom && dist <= bigFrom + C.BUILDER_BIG_SIZE) {
        face();
        return act('ult');
      }
      if (skillReady && level && p.grounded && dist >= 0.8 && dist < 2.2) {
        face(); // 상대 발밑에 벽을 솟게 해 띄움
        return act('skill');
      }
    } else if (p.char === 'cannon') {
      // R: 앞 직선에 상대가 있으면 대형 포탄 (블록째 뚫음)
      if (ultReady && dist <= C.CANNON_R_RANGE * 0.7 && Math.abs(t.z - p.z) < 2) {
        face();
        this.rollShellErr();
        this.input.yaw += this.shellErr.yaw;
        this.input.pitch = Math.atan2(t.z + C.PLAYER_HEIGHT * 0.5 - (p.z + C.EYE_HEIGHT - 0.2), dist) + this.shellErr.pitch;
        return act('ult');
      }
      // F: 붙은 상대가 공격을 준비하면 발밑 포격으로 띄워 내고 피함
      if (skillReady && dist < 1.6 && t.atk) return act('skill');
    } else if (p.char === 'berserker') {
      // R: 피해 % 가 높을 때 (분노 큼, 피해 % 도 깎음) 또는 둘 이상 붙어 있으면 소용돌이
      const around = near(C.BERSERKER_SPIN_END_RANGE).length;
      if (ultReady && around && (p.damage >= 80 || around >= 2)) return act('ult');
      // F: 조금 떨어진 상대에게 광폭 도약으로 붙음 (떨어질 자리·블록 그림자로는 안 감)
      if (skillReady && level && p.grounded && dist >= 2.5 && dist <= C.BERSERKER_LEAP_DIST + 1) {
        const yaw = Math.atan2(t.y - p.y, t.x - p.x);
        const land = C.BERSERKER_LEAP_DIST;
        if (edgeDist(p.x + Math.cos(yaw) * land, p.y + Math.sin(yaw) * land) < 1) return false;
        if (this.pathHits(p, yaw, land, avoid)) return false;
        face();
        return act('skill');
      }
    } else if (p.char === 'bard') {
      if (p.form !== 'metal') {
        // 음유: 앞 넓은 범위에 상대가 있으면 취약의 노래, 붙으면 메탈로 바꿔 기타 리프
        if (ultReady && dist <= C.BARD_SONG_RANGE * 0.9 && Math.abs(t.z - p.z) < 2) {
          face();
          return act('ult');
        }
        if (skillReady && dist <= C.BARD_RIFF_RANGE + 0.3) return act('skill');
      } else {
        // 메탈: 앞에 상대가 있으면 앰프 음파, 많이 맞았거나 멀어지면 음유시인으로 (치유)
        if (ultReady && level && dist <= C.BARD_AMP_RANGE * 0.8) {
          face();
          return act('ult');
        }
        if (skillReady && (p.damage >= 90 || dist > 4.5)) return act('skill');
      }
    } else if (p.char === 'hunter') {
      // R: 보는 방향 안에 쏠 표식 대상이 있으면 (표식 많은 상대 쪽을 봄)
      const marked = enemies.filter((o) => g.markOf(p, o) > 0 && Math.hypot(o.x - p.x, o.y - p.y) <= C.HUNTER_SHOT_RANGE && !g.lineBlocked(p, o));
      if (ultReady && marked.length) {
        const best = marked.sort((a, b) => g.markOf(p, b) - g.markOf(p, a))[0];
        this.input.yaw = Math.atan2(best.y - p.y, best.x - p.x);
        if (act('ult')) return true;
      }
      // F: 표식 있는 상대가 좀 떨어져 있으면 추적 도약
      const chase = enemies.some((o) => g.markOf(p, o) > 0 && Math.hypot(o.x - p.x, o.y - p.y) <= C.HUNTER_LEAP_RANGE && Math.hypot(o.x - p.x, o.y - p.y) > 2);
      if (skillReady && chase) return act('skill');
      // 찔러 넣기(표식) 뒤 콤보 중이면 F 덮침으로 이어 감 (평평평 → F → 평평평, 2026-10-26 재혁 "가")
      if (skillReady && comboing && g.markOf(p, t) > 0 && p.lastBasic && p.lastBasic.n === C.BASIC_ATTACKS.hunter.chain.length && !p.lastBasic.air && g.time - p.lastBasic.at < 400) return act('skill');
    } else if (p.char === 'hook') {
      // R 블록 내려찍기: 상대 쪽으로 블록이 닿고 상대가 내려찍는 직선 안이면
      const yawT = Math.atan2(t.y - p.y, t.x - p.x);
      if (ultReady && dist <= C.HOOK_SLAM_LEN && Math.abs(t.z - p.z) < 1.5 && g.hookRayBlock(p, yawT, 0)) {
        face();
        return act('ult');
      }
      if (skillReady && dist >= 1.6 && dist <= C.HOOK_RANGE * 0.9 && Math.abs(t.z - p.z) < 1.5 && (comboing || dist >= 2.5)) {
        face(); // 밀어낸 상대를 다시 당김
        return act('skill');
      }
    }
    return false;
  }

  canShoot(g, p, t) {
    const sx = p.x;
    const sy = p.y;
    const sz = p.z + C.EYE_HEIGHT;
    const tx = t.x;
    const ty = t.y;
    const tz = t.z + C.PLAYER_HEIGHT * 0.6;
    const len = Math.hypot(tx - sx, ty - sy, tz - sz);
    if (len > 7 || len < 1.2) return false;
    for (let s = 0.5; s < len; s += 0.25) {
      const k = s / len;
      if (g.solidAt(Math.floor(sx + (tx - sx) * k), Math.floor(sy + (ty - sy) * k), Math.floor(sz + (tz - sz) * k))) return false;
    }
    return true;
  }

  aimAt(p, t) {
    const err = () => (this.rng() * 2 - 1) * this.k('AIM_ERROR_RAD');
    const dx = t.x - p.x;
    const dy = t.y - p.y;
    const dz = t.z + C.PLAYER_HEIGHT * 0.6 - (p.z + C.EYE_HEIGHT);
    this.input.yaw = Math.atan2(dy, dx) + err();
    this.input.pitch = Math.atan2(dz, Math.hypot(dx, dy)) + err();
  }

  // 위험 칸·가장자리를 피하면서 지금 높이에서 갈 수 있는 가장 가까운 칸 중심
  safeSpot(g, p, bad, _unused) {
    const badSet = new Set(bad.map(([x, y]) => x * 100 + y));
    let best = null;
    let bs = Infinity;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        if (badSet.has(x * 100 + y)) continue;
        const top = g.columnTop(x, y);
        if (top > p.z + this.jumpReach(g, p)) continue; // 점프로 못 올라감
        if (g.lava.active && top < g.lava.z + 0.6) continue; // 용암에 잠겼거나 곧 잠김
        const cx = x + 0.5;
        const cy = y + 0.5;
        // 위험 칸에서 한 칸 떨어진 곳을 선호 (경계에 걸치면 AABB 가 겹친다)
        let near = 0;
        for (const [bx, by] of bad) if (Math.abs(bx - x) <= 1 && Math.abs(by - y) <= 1) near++;
        const score = Math.hypot(cx - p.x, cy - p.y) + (edgeDist(cx, cy) < 1 ? 0.8 : 0) + near * 0.15;
        if (score < bs) {
          bs = score;
          best = { x: cx, y: cy };
        }
      }
    }
    return best || { x: W / 2, y: D / 2 };
  }

  moveTo(g, p, spot, avoid = []) {
    if (g.time < this.unstickUntil) {
      // 막혔을 때: 옆으로 비켜 걸으며 점프
      this.input.fwd = 0.3;
      this.input.strafe = this.unstickDir;
      this.input.jump = true;
      return;
    }
    let tx = spot.x;
    let ty = spot.y;
    // 가는 목표가 위험 칸이면 그 칸 밖 가장 가까운 곳으로
    if (avoid.length && overlapsCells({ x: tx, y: ty }, avoid)) {
      const s = this.safeSpot(g, p, avoid, null);
      tx = s.x;
      ty = s.y;
    }
    const dx = tx - p.x;
    const dy = ty - p.y;
    const d = Math.hypot(dx, dy);
    if (d < 0.2) {
      this.input.fwd = 0;
      this.input.strafe = 0;
      return;
    }
    let ux = dx / d;
    let uy = dy / d;
    // 아는 위험 칸 쪽으로 한 발 내딛게 되면: 축 하나로 미끄러지거나, 안 되면 멈춘다
    // (안 그러면 "목표로 가다 걸침 → 도망 → 다시 목표로" 를 반복하다 경계에서 깔린다)
    if (avoid.length && !overlapsCells(p, avoid)) {
      // 판단 주기 사이에 약 0.6칸 움직이므로 0.35·0.7칸 앞을 둘 다 본다
      const hits = (vx, vy) =>
        overlapsCells({ x: p.x + vx * 0.35, y: p.y + vy * 0.35 }, avoid) || overlapsCells({ x: p.x + vx * 0.7, y: p.y + vy * 0.7 }, avoid);
      if (hits(ux, uy)) {
        if (Math.abs(ux) > 0.15 && !hits(Math.sign(ux), 0)) {
          ux = Math.sign(ux);
          uy = 0;
        } else if (Math.abs(uy) > 0.15 && !hits(0, Math.sign(uy))) {
          ux = 0;
          uy = Math.sign(uy);
        } else {
          this.input.fwd = 0;
          this.input.strafe = 0;
          return;
        }
      }
    }
    const ax = Math.floor(p.x + ux * 0.55);
    const ay = Math.floor(p.y + uy * 0.55);
    const top = g.columnTop(ax, ay);
    // 용암이 켜졌으면 용암 가까운 낮은 칸으로 내려가지 않는다
    // (안 그러면 높은 곳에 올라갔다가 바닥의 상대·아이템을 쫓아 내려와 용암을 맞는다)
    if (g.lava.active && top < this.standHeight(g, p) - 0.5 && top < g.lava.z + C.BOT_LAVA_MARGIN) {
      this.input.fwd = 0;
      this.input.strafe = 0;
      return;
    }
    this.input.yaw = Math.atan2(uy, ux);
    this.input.pitch = 0;
    this.input.fwd = 1;
    this.input.strafe = 0;
    // 앞 칸이 높으면 점프. 공중에서 아직 모자라면 꼭대기 근처에서 2단 점프
    if (p.grounded) {
      if (top > p.z + 0.05 && top <= p.z + this.jumpReach(g, p)) this.input.jump = true;
    } else if (top > p.z + 0.05 && p.airJumps > 0 && p.vz < C.BOT_AIR_JUMP_VZ) {
      g.handleAction(p.id, { name: 'jump' }); // 2단 점프
    }
  }

  // ---------- 조종 ----------
  controlPiece(g, p, enemies, piece) {
    const t = this.nearest(p, enemies);
    const timeLeft = piece.controlEndsAt - g.time;
    // 난이도가 낮으면 블록마다 한 번 정한 만큼 상대 옆을 겨냥 (CONTROL_AIM_ERROR 반경 안 무작위)
    if (!this.dropOffset || this.dropOffset.piece !== piece.id) {
      const R = this.k('CONTROL_AIM_ERROR');
      const r = R > 0 ? R * Math.sqrt(this.rng()) : 0; // 0 이면 난수를 안 써서 보통 봇의 난수 순서가 그대로
      const a = r > 0 ? this.rng() * Math.PI * 2 : 0;
      this.dropOffset = { piece: piece.id, x: r * Math.cos(a), y: r * Math.sin(a) };
    }
    const aim = t ? { ...t, x: t.x + this.dropOffset.x, y: t.y + this.dropOffset.y } : null;
    const plan = aim ? this.bestDrop(g, p, aim, piece) : null;
    if (!plan) {
      if (timeLeft < 1500 && piece.fits) this.drop(g, p, piece);
      else if (!piece.fits) g.handleAction(p.id, { name: 'pieceMove', dx: piece.px > W / 2 ? -1 : 1, dy: 0 });
      return;
    }
    // 키 하나씩: 회전 → x → y
    if (piece.rot !== plan.rot) {
      const diff = (plan.rot - piece.rot + 4) % 4;
      g.handleAction(p.id, { name: 'rotate', dir: diff === 3 ? -1 : 1 });
      this.aimedAt = null;
      return;
    }
    if (piece.px !== plan.px) {
      g.handleAction(p.id, { name: 'pieceMove', dx: Math.sign(plan.px - piece.px), dy: 0 });
      this.aimedAt = null;
      return;
    }
    if (piece.py !== plan.py) {
      g.handleAction(p.id, { name: 'pieceMove', dx: 0, dy: Math.sign(plan.py - piece.py) });
      this.aimedAt = null;
      return;
    }
    if (this.aimedAt === null) this.aimedAt = g.time;
    if (g.time - this.aimedAt >= this.k('DROP_DELAY_MS') || timeLeft < 1000) {
      this.drop(g, p, piece);
      this.aimedAt = null;
    }
  }

  // 내가 떨어뜨린 블록은 어디로 떨어지는지 이미 안다 → 반응 시간 없이 바로 피할 대상으로 등록
  // (안 그러면 반응 시간 동안 상대를 쫓아 내 블록 밑으로 걸어 들어간다)
  drop(g, p, piece) {
    g.handleAction(p.id, { name: 'drop' });
    if (piece.phase === 'falling') this.dangerSeen.set(pieceKey(piece), g.time - this.k('REACTION_MS'));
  }

  // 서 있는 높이 (칸). 점프 중이면 발밑 기둥 높이
  // (안 그러면 뛰어오른 순간 "이미 높다"며 오르기 계획을 버리거나, 바닥에서 뛰다 "내려간다"며 멈춘다)
  standHeight(g, p) {
    const x = Math.max(0, Math.min(W - 1, Math.floor(p.x)));
    const y = Math.max(0, Math.min(D - 1, Math.floor(p.y)));
    const under = g.columnTop(x, y);
    return p.grounded || under > p.z ? Math.floor(p.z + 0.05) : under;
  }

  // 용암이 2.5칸 안인데 걸어서 갈 더 높은 곳이 없을 때: 설치 블록을 던져 바로 앞에 높은 발판을 만든다. 던졌으면 true
  // (던진 건 떨어지는 동안 내 블록이라 피하고, 착지하면 다음 판단에서 climbFromLava 가 그 발판으로 올라간다)
  brickStep(g, p) {
    if (!p.grounded || !g.lava.active || p.z - g.lava.z > 2.5) return false;
    const h0 = this.standHeight(g, p);
    if (p.bricks <= 0) return false;
    if (g.pieces.some((pc) => pc.thrownBy === p.id)) return false; // 던진 게 아직 떨어지는 중
    const sides = [p.brickSide, !p.brickSide];
    const side0 = p.brickSide;
    let pick = null;
    for (const yaw of [0, Math.PI / 2, Math.PI, -Math.PI / 2]) {
      for (const side of sides) {
        p.brickSide = side; // 계획만 본다 (실제로 바꾸는 건 아래 rotate 입력)
        const plan = g.brickPlan(p, yaw, C.BOT_BRICK_STEP_PITCH);
        if (plan.ok && plan.z + 1 > h0 + 0.5 && plan.z + 1 <= h0 + this.jumpReach(g, p)) pick = pick || { yaw, side };
      }
    }
    p.brickSide = side0;
    if (!pick) return false;
    if (pick.side !== p.brickSide) g.handleAction(p.id, { name: 'rotate', dir: 1 }); // Q/E 로 1×2 방향 바꾸기
    this.throwAt(g, p, pick.yaw, C.BOT_BRICK_STEP_PITCH);
    return true;
  }

  // 상대 발밑을 조준했을 때 떨어질 칸이 상대를 덮으면 던진다. 던졌으면 true
  // 던질 때는 조준점을 BOT_BRICK_AIM_ERROR 반경 안에서 빗나가게 한다 (사람처럼 가끔 빗나감)
  brickOnTarget(g, p, t) {
    const aim = (tx, ty) => {
      const d = Math.hypot(tx - p.x, ty - p.y);
      return { yaw: Math.atan2(ty - p.y, tx - p.x), pitch: Math.atan2(t.z - (p.z + C.EYE_HEIGHT), d), d };
    };
    const exact = aim(t.x, t.y);
    if (exact.d > C.BRICK_RANGE || g.pieces.some((pc) => pc.thrownBy === p.id)) return false;
    const plan = g.brickPlan(p, exact.yaw, exact.pitch);
    if (!plan.ok || !overlapsCells(t, plan.cells)) return false;
    const r = this.k('BRICK_AIM_ERROR') * Math.sqrt(this.rng());
    const a = this.rng() * Math.PI * 2;
    const off = aim(t.x + r * Math.cos(a), t.y + r * Math.sin(a));
    const shot = g.brickPlan(p, off.yaw, off.pitch).ok ? off : exact; // 빗나간 조준이 못 던지는 자리면 정조준
    this.throwAt(g, p, shot.yaw, shot.pitch);
    return true;
  }

  // 상대 발밑 칸이 폭발 범위(가로세로 ±BOMB_RADIUS)에 들면 던진다. 조준 오차는 설치 블록과 같음. 던졌으면 true
  bombOnTarget(g, p, t) {
    const d = Math.hypot(t.x - p.x, t.y - p.y);
    if (d > C.BRICK_RANGE || d < C.BOMB_BLAST_RANGE) return false; // 너무 가까우면 나도 발판을 잃는다
    const aim = (tx, ty) => ({ yaw: Math.atan2(ty - p.y, tx - p.x), pitch: Math.atan2(t.z - (p.z + C.EYE_HEIGHT), Math.hypot(tx - p.x, ty - p.y)) });
    const exact = aim(t.x, t.y);
    const plan = g.bombPlan(p, exact.yaw, exact.pitch);
    if (!plan.ok) return false;
    const [bx, by] = plan.cells[0];
    if (Math.abs(Math.floor(t.x) - bx) > C.BOMB_RADIUS || Math.abs(Math.floor(t.y) - by) > C.BOMB_RADIUS) return false;
    const r = this.k('BRICK_AIM_ERROR') * Math.sqrt(this.rng());
    const a = this.rng() * Math.PI * 2;
    const off = aim(t.x + r * Math.cos(a), t.y + r * Math.sin(a));
    const shot = g.bombPlan(p, off.yaw, off.pitch).ok ? off : exact;
    this.throwAt(g, p, shot.yaw, shot.pitch);
    return true;
  }

  // 손에 든 것(설치 블록·폭탄)을 이 방향으로 우클릭
  throwAt(g, p, yaw, pitch) {
    this.input.yaw = yaw;
    this.input.pitch = pitch;
    this.input.fwd = 0;
    this.input.strafe = 0;
    g.handleInput(p.id, this.input);
    g.handleAction(p.id, { name: 'fire' });
    // 내가 던진 블록은 어디로 떨어지는지 안다 → 반응 시간 없이 피할 대상
    const mine = g.pieces.find((pc) => pc.thrownBy === p.id);
    if (mine) this.dangerSeen.set(pieceKey(mine), g.time - this.k('REACTION_MS'));
  }

  // 지금 한 번 점프로 올라갈 수 있는 높이 (칸)
  jumpReach(g, p) {
    return (g.time < p.jumpUntil ? 2.25 : 1.05) + (C.AIR_JUMPS > 0 ? 1 : 0); // 점프력 상승 중이면 2칸, 2단 점프로 1칸 더
  }

  // 하늘 계단: 용암이 BOT_SKY_HOP_LAVA 안이면 점프로 닿는 더 높은 하늘 블록으로 건너뛴다. 움직였거나 블록 위에서 버티면 true
  // (건널 블록 = 윗면이 지금보다 0.5칸 넘게 높고 점프 높이 안, 가장 가까운 칸까지 BOT_SKY_HOP_DIST 안. 높을수록·가까울수록 먼저)
  skyHop(g, p) {
    if (!g.sky || !g.lava.active || p.z - g.lava.z > C.BOT_SKY_HOP_LAVA) return false;
    const h0 = this.standHeight(g, p);
    const reach = this.jumpReach(g, p);
    let best = null;
    let bs = -Infinity;
    let onSky = false;
    for (const pc of g.pieces) {
      if (!pc.sky || pc.phase !== 'falling') continue;
      const top = pc.pz + 1;
      if (p.grounded && Math.abs(top - p.z) < 0.1 && pc.cells.some(([dx, dy]) => pc.px + dx === Math.floor(p.x) && pc.py + dy === Math.floor(p.y))) onSky = true;
      if (top <= h0 + 0.5 || top > h0 + reach) continue;
      let cell = null;
      let cd = Infinity;
      for (const [dx, dy] of pc.cells) {
        const cx = pc.px + dx + 0.5;
        const cy = pc.py + dy + 0.5;
        const d = Math.hypot(cx - p.x, cy - p.y);
        if (d < cd) {
          cd = d;
          cell = { x: cx, y: cy };
        }
      }
      if (cd - 0.5 > C.BOT_SKY_HOP_DIST) continue;
      const score = top * 2 - cd;
      if (score > bs) {
        bs = score;
        best = { cell, top, d: cd };
      }
    }
    if (!best) {
      if (!onSky) return false;
      this.input.fwd = 0; // 더 높은 블록이 없으면 지금 하늘 블록 위에서 버팀 (걸어 내려가면 용암)
      this.input.strafe = 0;
      return true;
    }
    this.input.yaw = Math.atan2(best.cell.y - p.y, best.cell.x - p.x);
    this.input.pitch = 0;
    this.input.fwd = best.d < 0.3 ? 0 : 1;
    this.input.strafe = 0;
    if (p.grounded) {
      if (best.d < 2.5) this.input.jump = true;
    } else if (p.airJumps > 0 && p.vz < C.BOT_AIR_JUMP_VZ && p.z < best.top) {
      g.handleAction(p.id, { name: 'jump' }); // 2단 점프
    }
    return true;
  }

  // 용암이 2.5칸 안으로 다가오면 걸어서 이어진 가장 높은 칸으로 간다. 움직였으면 true
  // 기둥 높이로 길찾기(BFS): 한 걸음에 점프 높이까지 오르고, 내려가기는 자유, 잠긴 칸은 못 감.
  // (예전엔 가장 가까운 높은 칸으로 직진만 해서 사이에 벽이 있으면 바닥에서 용암을 맞았다)
  climbFromLava(g, p, avoid) {
    if (!g.lava.active || p.z - g.lava.z > 2.5) return false;
    const reach = this.jumpReach(g, p);
    // 지나갈 칸은 아직 안 잠겼으면 된다 (한 칸 걷는 0.2초 동안 용암은 0.02칸 오름)
    const floorZ = g.lava.z + 0.15;
    const bad = new Set(avoid.map(([x, y]) => x * 100 + y));
    const sx = Math.max(0, Math.min(W - 1, Math.floor(p.x)));
    const sy = Math.max(0, Math.min(D - 1, Math.floor(p.y)));
    const h0 = this.standHeight(g, p);
    const start = sx * 100 + sy;
    const height = new Map([[start, h0]]);
    const first = new Map([[start, null]]); // 그 칸으로 가는 길의 첫 걸음
    const steps = new Map([[start, 0]]);
    const queue = [[sx, sy]];
    let best = null;
    let bs = -Infinity;
    while (queue.length) {
      const [x, y] = queue.shift();
      const k = x * 100 + y;
      const h = height.get(k);
      const score = h * 20 - steps.get(k); // 높이가 먼저, 같은 높이면 가까운 곳
      if (score > bs) {
        bs = score;
        best = k;
      }
      for (const [dx, dy] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) {
        const nx = x + dx;
        const ny = y + dy;
        const nk = nx * 100 + ny;
        if (nx < 0 || nx >= W || ny < 0 || ny >= D || height.has(nk) || bad.has(nk)) continue;
        const top = g.columnTop(nx, ny);
        if (top > h + reach || top < floorZ) continue;
        height.set(nk, top);
        steps.set(nk, steps.get(k) + 1);
        first.set(nk, first.get(k) ?? [nx, ny]);
        queue.push([nx, ny]);
      }
    }
    if (best === start || height.get(best) <= h0 + 0.5) return false; // 더 높은 곳으로 가는 길이 없으면 평소대로
    const [fx, fy] = first.get(best);
    this.moveTo(g, p, { x: fx + 0.5, y: fy + 0.5 }, avoid);
    return true;
  }

  // 상대가 서 있는 칸들을 덮고, 나는 안 덮고, 들어가는 배치 중 이동 키 수가 가장 적은 것
  bestDrop(g, p, t, piece) {
    const h = C.PLAYER_HALF;
    const tCells = new Set();
    for (const [ox, oy] of [[-h, -h], [h, -h], [-h, h], [h, h], [0, 0]]) tCells.add(Math.floor(t.x + ox) * 100 + Math.floor(t.y + oy));
    let best = null;
    let bs = Infinity;
    for (let r = 0; r < 4; r++) {
      const cells = rotatedCells(piece.shape, r);
      const { w, d } = footprint(cells);
      for (let px = 0; px <= W - w; px++) {
        for (let py = 0; py <= D - d; py++) {
          const world = cells.map(([dx, dy]) => [px + dx, py + dy]);
          const cover = world.filter(([x, y]) => tCells.has(x * 100 + y)).length;
          if (!cover) continue;
          if (overlapsCells(p, world)) continue;
          const landZ = Math.max(...world.map(([x, y]) => g.columnTop(x, y)));
          if (landZ + 1 > C.GRID_H) continue;
          if (g.mode === 'master' && g.tooTall(world, landZ)) continue; // 블록 마스터 높이 제한: 못 놓는 자리
          if (landZ > t.z + 0.5) continue; // 상대보다 높은 곳에 걸려서 안 닿음
          const keys = ((r - piece.rot + 4) % 4 === 3 ? 1 : (r - piece.rot + 4) % 4) + Math.abs(px - piece.px) + Math.abs(py - piece.py);
          const score = keys - cover * 2;
          if (score < bs) {
            bs = score;
            best = { rot: r, px, py };
          }
        }
      }
    }
    return best;
  }
}
