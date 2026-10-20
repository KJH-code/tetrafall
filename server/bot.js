// 서버 안에서 도는 AI 봇. 사람과 똑같이 handleInput / handleAction 으로만 조작한다 (판정 특혜 없음).
// BOT_THINK_MS 마다 한 번 판단하고, 그 사이에는 마지막 입력을 유지한다.
// 사람처럼 보이게: 그림자를 보고 BOT_REACTION_MS 뒤에야 피하기 시작하고, 조준에는 오차가 있다.
import { CONFIG as C } from '../shared/config.js';
import { rotatedCells, footprint } from '../shared/pieces.js';

const W = C.GRID_W;
const D = C.GRID_D;

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
  constructor(rng = Math.random) {
    this.rng = rng;
    this.nextThinkAt = 0;
    this.input = { fwd: 0, strafe: 0, jump: false, yaw: 0, pitch: 0 };
    this.dangerSeen = new Map(); // 블록 위치 키 -> 그림자를 처음 본 시각 (반응 시간 계산용)
    this.aimedAt = null; // 조종 중: 목표 위에 맞춘 시각
    this.lastPos = null;
    this.stuckMs = 0;
    this.unstickUntil = 0;
    this.unstickDir = 1;
    this.nextPushAt = 0; // 봇 자신의 밀치기 간격 (사람처럼 연타하지 않게)
    // 상대 고를 때 판마다 다시 뽑는 무작위 가산 거리. 거리가 같으면 늘 목록 맨 앞(사람)을 고르던 버그 수정:
    // 4인 판에서 봇 둘이 시작하자마자 사람을 협공했다 (2026-10-20 로그 3·16·17판, 재현 200판 중 200판)
    this.targetBias = new Map();
    this.biasRound = -1;
  }

  update(g, p) {
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
    return [...g.players.values()].filter((o) => o !== p && o.alive);
  }

  // 그림자가 보이는 떨어지는 블록들 → 각각의 발자국 칸·남은 시간·위치 키
  visibleDangers(g) {
    const out = [];
    for (const piece of g.pieces) {
      if (piece.phase !== 'falling') continue;
      const eta = Math.max(0, (piece.pz - piece.landZ - 1) * piece.stepMs + (piece.nextStepAt - g.time));
      if (eta > C.SHADOW_LEAD_MS) continue;
      out.push({ cells: piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]), eta, key: pieceKey(piece) });
    }
    return out;
  }

  // ---------- 판단 ----------
  think(g, p) {
    this.input.jump = false;
    if (this.biasRound !== g.roundNumber) {
      this.biasRound = g.roundNumber;
      this.targetBias.clear();
    }
    const enemies = this.enemies(g, p);
    const dangers = this.visibleDangers(g);

    // 그림자를 처음 본 순간부터 반응 시간이 지나야 "안다"
    const live = new Set();
    for (const d of dangers) {
      live.add(d.key);
      if (!this.dangerSeen.has(d.key)) this.dangerSeen.set(d.key, g.time);
    }
    for (const k of [...this.dangerSeen.keys()]) if (!live.has(k)) this.dangerSeen.delete(k);
    const known = dangers.filter((d) => g.time - this.dangerSeen.get(d.key) >= C.BOT_REACTION_MS);
    const avoid = known.flatMap((d) => d.cells);
    const danger = dangers.length ? dangers[0] : null;

    const mine = g.controlledPiece(p);
    if (mine) {
      this.controlPiece(g, p, enemies, mine);
      // 캐릭터는 내 블록 밑·가장자리·아는 그림자를 피해 가만히 (용암이 오면 올라간다)
      const hover = g.pieceWorldCells(mine).map(([x, y]) => [x, y]);
      if (!this.climbFromLava(g, p, avoid)) this.moveTo(g, p, this.safeSpot(g, p, hover.concat(avoid), null), avoid);
      return;
    }

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

    // 1.5) 용암이 다가오면 높은 곳으로
    if (this.climbFromLava(g, p, avoid)) return;

    // 2) 가장자리에 너무 붙었으면 안쪽으로
    if (edgeDist(p.x, p.y) < 0.75) {
      this.moveTo(g, p, { x: W / 2, y: D / 2 }, avoid);
      return;
    }

    const target = this.nearest(p, enemies);

    // 3) 투사체: 보이면 쏜다
    if (target && p.ammo > 0 && this.canShoot(g, p, target)) {
      this.aimAt(p, target);
      g.handleInput(p.id, this.input);
      g.handleAction(p.id, { name: 'fire' });
      this.input.fwd = 0;
      return;
    }

    // 4) 아이템: 내가 상대보다 가깝거나 비슷하면 먹으러 간다
    const item = this.pickItem(g, p, target);
    if (item) {
      this.moveTo(g, p, { x: item.x + 0.5, y: item.y + 0.5 }, avoid);
      return;
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
      if (it.type === 'knockback' && p.ammo > 0) continue;
      if (Math.abs(it.z - p.z) > 1.2) continue; // 2칸 이상 높으면 못 감
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
    const lined = toT.x * dir.x + toT.y * dir.y > 0.5; // 내가 상대 "뒤"에 있다
    if (dist < C.PUSH_RANGE * 0.85 && (lined || edgeDist(p.x, p.y) < 1.2)) {
      this.input.fwd = 0;
      this.input.strafe = 0;
      this.input.yaw = Math.atan2(t.y - p.y, t.x - p.x);
      if (g.time >= p.pushReadyAt && g.time >= t.stunUntil && g.time >= this.nextPushAt) {
        g.handleInput(p.id, this.input);
        g.handleAction(p.id, { name: 'push' });
        this.nextPushAt = g.time + C.BOT_PUSH_INTERVAL_MS * (0.7 + 0.6 * this.rng());
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
    const err = () => (this.rng() * 2 - 1) * C.BOT_AIM_ERROR_RAD;
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
    this.input.yaw = Math.atan2(uy, ux);
    this.input.pitch = 0;
    this.input.fwd = 1;
    this.input.strafe = 0;
    // 앞 칸이 1칸 높으면 점프
    const ax = Math.floor(p.x + ux * 0.55);
    const ay = Math.floor(p.y + uy * 0.55);
    const top = g.columnTop(ax, ay);
    if (top > p.z + 0.05 && top <= p.z + this.jumpReach(g, p)) this.input.jump = true;
  }

  // ---------- 조종 ----------
  controlPiece(g, p, enemies, piece) {
    const t = this.nearest(p, enemies);
    const timeLeft = piece.controlEndsAt - g.time;
    const plan = t ? this.bestDrop(g, p, t, piece) : null;
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
    if (g.time - this.aimedAt >= C.BOT_DROP_DELAY_MS || timeLeft < 1000) {
      this.drop(g, p, piece);
      this.aimedAt = null;
    }
  }

  // 내가 떨어뜨린 블록은 어디로 떨어지는지 이미 안다 → 반응 시간 없이 바로 피할 대상으로 등록
  // (안 그러면 반응 시간 동안 상대를 쫓아 내 블록 밑으로 걸어 들어간다)
  drop(g, p, piece) {
    g.handleAction(p.id, { name: 'drop' });
    if (piece.phase === 'falling') this.dangerSeen.set(pieceKey(piece), g.time - C.BOT_REACTION_MS);
  }

  // 지금 한 번 점프로 올라갈 수 있는 높이 (칸)
  jumpReach(g, p) {
    return 1.05;
  }

  // 용암이 2.5칸 안으로 다가오면 더 높은 칸으로 한 단계씩 올라간다. 움직였으면 true
  climbFromLava(g, p, avoid) {
    if (!g.lava.active || p.z - g.lava.z > 2.5) return false;
    const bad = new Set(avoid.map(([x, y]) => x * 100 + y));
    let best = null;
    let bs = -Infinity;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        if (bad.has(x * 100 + y)) continue;
        const top = g.columnTop(x, y);
        if (top > p.z + this.jumpReach(g, p) || top < g.lava.z + 0.6) continue;
        const score = top * 3 - Math.hypot(x + 0.5 - p.x, y + 0.5 - p.y);
        if (score > bs) {
          bs = score;
          best = { x: x + 0.5, y: y + 0.5, top };
        }
      }
    }
    if (!best || best.top <= p.z + 0.5) return false; // 더 높은 곳이 없으면 평소대로
    this.moveTo(g, p, best, avoid);
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
