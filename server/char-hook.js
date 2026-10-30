// Game 메서드 묶음: 캐릭터: 갈고리. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { DIR6, cellKey, overlapsCell, pieceCellValue } from './game-util.js';

export class HookPart {
  // ---- 갈고리 ----
  // 보는 방향 HOOK_RANGE 안 (반각 HOOK_HALF_ANGLE_DEG, 높이 차 2칸 안) 가장 가까운 상대
  hookTarget(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.HOOK_HALF_ANGLE_DEG * Math.PI) / 180);
    let best = null;
    let bd = Infinity;
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.HOOK_RANGE || d < 0.3 || Math.abs(t.z - p.z) > 2 || (dx * fx + dy * fy) / d < cosHalf) continue;
      if (d < bd) {
        bd = d;
        best = t;
      }
    }
    return best;
  }

  // 갈고리가 닿는 첫 블록 (격자 칸 또는 떨어지는 블록, 필드 바닥은 아님). { x, y, z, d(수평 거리) } 또는 null.
  // 조준 방향(yaw + pitch) 3D 직선을 눈 높이에서 HOOK_RANGE 만큼. 놓치면 보조로 발 층·한 칸 위 층을 수평으로
  // (2026-10-25 버그: 수평 한 층만 봐서 땅 위 1칸 높이 블록이 안 잡혀 R 이 거의 안 써졌음)
  // skip(x, y, z): 이 칸은 없는 셈 (R: 조종 중인 블록)
  hookRayBlock(p, yaw = p.yaw, pitch = p.pitch || 0, skip = null) {
    const solid = (x, y, z) => z >= 0 && z < this.H && ((this.inXY(x, y) && this.grid[this.idx(x, y, z)]) || this.pieceCells.has(cellKey(x, y, z))) && !(skip && skip(x, y, z));
    const cp = Math.cos(pitch);
    const dir = { x: Math.cos(yaw) * cp, y: Math.sin(yaw) * cp, z: Math.sin(pitch) };
    const eye = { x: p.x, y: p.y, z: p.z + C.EYE_HEIGHT };
    for (let d = 0; d <= C.HOOK_RANGE + 1e-9; d += 0.05) {
      const px = eye.x + dir.x * d;
      const py = eye.y + dir.y * d;
      const pz = eye.z + dir.z * d;
      if (pz < 0 && this.inXY(Math.floor(px), Math.floor(py))) break; // 필드 바닥에 닿음
      const x = Math.floor(px);
      const y = Math.floor(py);
      const z = Math.floor(pz);
      if (solid(x, y, z)) return { x, y, z, d: Math.hypot(px - p.x, py - p.y) };
    }
    const fx = Math.cos(yaw);
    const fy = Math.sin(yaw);
    for (let d = C.PLAYER_HALF; d <= C.HOOK_RANGE + 1e-9; d += 0.1) {
      const x = Math.floor(p.x + fx * d);
      const y = Math.floor(p.y + fy * d);
      for (const z of [Math.floor(p.z + 0.05), Math.floor(p.z + 0.05) + 1]) if (solid(x, y, z)) return { x, y, z, d };
    }
    return null;
  }

  // R 보조 판정: 보는 방향 반각 HOOK_GRAB_CONE_DEG, 수평 HOOK_RANGE 안, 발 층 -1 ~ +2 층의 블록 중 가장 가까운 것 (같으면 높은 칸)
  hookConeBlock(p, skip = null) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const cosHalf = Math.cos((C.HOOK_GRAB_CONE_DEG * Math.PI) / 180);
    const z0 = Math.floor(p.z + 0.05);
    let best = null;
    const R = Math.ceil(C.HOOK_RANGE) + 1;
    for (let x = Math.floor(p.x) - R; x <= Math.floor(p.x) + R; x++) {
      for (let y = Math.floor(p.y) - R; y <= Math.floor(p.y) + R; y++) {
        const dx = x + 0.5 - p.x;
        const dy = y + 0.5 - p.y;
        const d = Math.hypot(dx, dy);
        if (d > C.HOOK_RANGE + 0.5 || d < 0.5 || (dx * fx + dy * fy) / d < cosHalf) continue;
        for (let z = Math.max(0, z0 - 1); z <= Math.min(this.H - 1, z0 + 2); z++) {
          if (!((this.inXY(x, y) && this.grid[this.idx(x, y, z)]) || this.pieceCells.has(cellKey(x, y, z))) || (skip && skip(x, y, z))) continue;
          if (!best || d < best.d - 1e-9 || (Math.abs(d - best.d) < 1e-9 && z > best.z)) best = { x, y, z, d };
        }
      }
    }
    return best;
  }

  // 상대를 내 앞 HOOK_PULL_TO 거리까지 끌어옴 (블록에 막히면 거기까지). 콤보 한 타 (넉백 없이 경직 + 피해)
  pullTo(p, t, stunMs, gain, kind) {
    if (this.invulnerable(t)) return false;
    const dx = p.x - t.x;
    const dy = p.y - t.y;
    const d = Math.hypot(dx, dy) || 1;
    const go = Math.max(0, d - C.HOOK_PULL_TO);
    this.moveAxis(t, 'x', (dx / d) * go);
    this.moveAxis(t, 'y', (dy / d) * go);
    const hit = this.applyKnockback(t, dx, dy, 0, 0, stunMs, gain, { by: p.id, kind });
    t.kbx = 0;
    t.kby = 0;
    return hit;
  }

  // F 갈고리 (판정 즉시): 보는 방향에서 상대·블록 중 먼저 닿는 것. 상대면 끌어옴 + 장전, 블록이면 내가 끌려감 (공중 가능). 빗나가도 쿨타임
  // 갈고리를 던짐: 판정은 HOOK_FLY_MS 뒤 갈고리가 닿는 순간 (hookLand). 빗나가도 쿨타임
  hookPull(p) {
    p.hookFly = { at: this.time + C.HOOK_FLY_MS, yaw: p.yaw };
    this.emit({ type: 'hookThrow', who: p.id, yaw: p.yaw, ms: C.HOOK_FLY_MS });
    return true;
  }

  // 갈고리가 닿는 순간: 던진 방향, 지금 내 위치에서 상대·블록 판정 (예전 즉시 판정과 같은 규칙)
  hookLand(p) {
    const yaw = p.yaw;
    p.yaw = p.hookFly.yaw;
    p.hookFly = null;
    this.hookResolve(p);
    p.yaw = yaw;
  }

  hookResolve(p) {
    const t = this.hookTarget(p);
    const block = this.hookRayBlock(p);
    const td = t ? Math.hypot(t.x - p.x, t.y - p.y) : Infinity;
    if (block && block.d < td) {
      const go = Math.max(0, block.d - C.PLAYER_HALF - 0.05);
      p.zipDir = { x: Math.cos(p.yaw), y: Math.sin(p.yaw) }; // 던진 방향 (hookLand 가 yaw 를 잠깐 바꿔 둠)
      p.zipUntil = this.time + (go / C.HOOK_ZIP_SPEED) * 1000;
      p.vz = Math.max(p.vz, C.HOOK_ZIP_UP);
      p.grounded = false;
      p.kbx = 0;
      p.kby = 0;
      this.emit({ type: 'hook', who: p.id, target: null, block: [block.x, block.y, block.z], yaw: p.yaw });
      this.log(`  [스킬] ${p.name} 갈고리 → 블록 (${block.x},${block.y},${block.z}) ${go.toFixed(1)}칸 끌려감`);
      return true;
    }
    this.emit({ type: 'hook', who: p.id, target: t ? t.id : null, block: null, yaw: p.yaw });
    if (!t) {
      this.log(`  [스킬] ${p.name} 갈고리 빗나감`);
      return true; // 빗나가도 쿨타임
    }
    const hit = this.pullTo(p, t, C.HOOK_STUN_MS, C.HOOK_DAMAGE, 'hook');
    if (hit && !p.loaded) {
      p.loaded = true; // 끌어오면 장전
      this.emit({ type: 'reload', who: p.id });
    }
    this.log(`  [스킬] ${p.name} 갈고리 → ${t.name}${hit ? ` (${t.name} ${t.damage}%) 장전` : ' 무적이라 무시'}`);
    return true;
  }

  // R 으로 뽑을 덩어리: 맞은 칸이 떨어지는 블록이면 그 블록 통째로, 쌓인 블록이면 같은 블록 id·같은 색으로 6방향 이어진 칸 전부,
  // 시작 지형·건축가 블록·내려찍어 박힌 칸(id 없음)은 1칸 (2026-10-26 재혁 "갈고리 R = 테트로미노 통째로")
  hookGroup(b) {
    const key = cellKey(b.x, b.y, b.z);
    if (this.pieceCells.has(key)) {
      const pc = this.pieces.find((x) => x.id === this.pieceCells.get(key));
      const v = pieceCellValue(pc);
      return { piece: pc, cells: this.pieceWorldCells(pc).map(([x, y, z]) => ({ x, y, z, v, meta: null })) };
    }
    const i0 = this.idx(b.x, b.y, b.z);
    const v = this.grid[i0];
    const id = this.gridPiece[i0];
    const meta = this.bblocks.get(key) || null;
    if (!id || meta || !(v === CELL.THROWN || v >= CELL.SHAPE_BASE)) return { piece: null, cells: [{ x: b.x, y: b.y, z: b.z, v, meta }] };
    const cells = [];
    const seen = new Set([key]);
    const stack = [[b.x, b.y, b.z]];
    while (stack.length) {
      const [x, y, z] = stack.pop();
      cells.push({ x, y, z, v, meta: null });
      for (const [dx, dy, dz] of DIR6) {
        const nx = x + dx;
        const ny = y + dy;
        const nz = z + dz;
        const k = cellKey(nx, ny, nz);
        if (seen.has(k) || !this.inXY(nx, ny) || nz < 0 || nz >= this.H) continue;
        seen.add(k);
        const j = this.idx(nx, ny, nz);
        if (this.grid[j] === v && this.gridPiece[j] === id) stack.push([nx, ny, nz]);
      }
    }
    return { piece: null, cells };
  }

  // R 블록 내려찍기 1단계: 보는 방향 첫 블록의 덩어리를 뽑음 (격자에서 빠짐). 없으면 false (게이지 그대로)
  hookGrab(p) {
    const skip = (x, y, z) => this.controlledCell(x, y, z); // 조종 중인 블록은 안 잡음
    const b = this.hookRayBlock(p, p.yaw, p.pitch || 0, skip) || this.hookConeBlock(p, skip); // 조준이 살짝 빗나가도 원뿔로 너그럽게 (2026-10-26 재혁: R 을 두 번 눌러야 했음)
    if (!b) return false;
    const { piece, cells } = this.hookGroup(b);
    if (piece) this.removePiece(piece); // 떨어지는 블록 통째로 (하늘 계단 블록이면 사슬에서 빠짐 → 맨 위 보충, 녹을 때와 같음)
    else {
      for (const c of cells) {
        this.grid[this.idx(c.x, c.y, c.z)] = 0;
        if (c.meta) this.bblocks.delete(cellKey(c.x, c.y, c.z));
      }
      this.gridChanged();
    }
    for (const pc of this.pieces) this.updateLanding(pc);
    const meta = cells.length === 1 ? cells[0].meta : null; // 건축가 블록은 속성 그대로 옮김
    p.grab = { at: this.time + C.HOOK_GRAB_MS, cells, meta, from: [b.x, b.y, b.z], dir: { x: Math.cos(p.yaw), y: Math.sin(p.yaw) } };
    this.emit({ type: 'blockGrab', who: p.id, from: [b.x, b.y, b.z], cells: cells.map((c) => [c.x, c.y, c.z]), v: cells[0].v, ms: C.HOOK_GRAB_MS, builder: !!meta, sky: !!(piece && piece.sky) });
    this.log(`  [필살] ${p.name} 블록 뽑기 (${b.x},${b.y},${b.z})${cells.length > 1 ? ` ${cells.length}칸` : ''}${piece ? (piece.sky ? ' 하늘 블록' : ' 떨어지는 블록') : ''}`);
    return true;
  }

  // 조종 중인 블록의 칸인가
  controlledCell(x, y, z) {
    const id = this.pieceCells.get(cellKey(x, y, z));
    if (id === undefined) return false;
    const pc = this.pieces.find((q) => q.id === id);
    return !!(pc && pc.controller !== null);
  }

  hookSlam(p) {
    const g = p.grab;
    p.grab = null;
    const { dir } = g;
    let n = 0;
    for (const t of this.players.values()) {
      if (!this.foe(p, t) || Math.abs(t.z - p.z) > 2) continue;
      const along = (t.x - p.x) * dir.x + (t.y - p.y) * dir.y;
      const side = Math.abs((t.x - p.x) * dir.y - (t.y - p.y) * dir.x);
      if (along < 0.3 || along > C.HOOK_SLAM_LEN + 0.5 || side > C.HOOK_SLAM_WIDTH) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.HOOK_SLAM_KB_SPEED, C.HOOK_SLAM_KB_UP, C.HOOK_SLAM_STUN_MS, C.HOOK_SLAM_DAMAGE, { by: p.id, kind: 'blockslam' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'blockslam', by: p.id, target: t.id, ok: hit });
    }
    // 덩어리를 뽑은 모양 그대로 (방향도 그대로) 끝 칸을 중심으로, 모양 칸 아래 가장 높은 기둥 위에 박음. 필드 밖·떨어지는 블록과 겹치는 칸은 버림
    const ex = Math.floor(p.x + dir.x * C.HOOK_SLAM_LEN);
    const ey = Math.floor(p.y + dir.y * C.HOOK_SLAM_LEN);
    const cx = Math.round(g.cells.reduce((a, c) => a + c.x, 0) / g.cells.length - 0.5);
    const cy = Math.round(g.cells.reduce((a, c) => a + c.y, 0) / g.cells.length - 0.5);
    const at = g.cells.map((c) => ({ ...c, x: ex + c.x - cx, y: ey + c.y - cy })).filter((c) => this.inXY(c.x, c.y));
    let z = 0;
    for (const c of at) z = Math.max(z, this.columnTop(c.x, c.y));
    const placed = z < this.H ? at.filter((c) => !this.pieceCells.has(cellKey(c.x, c.y, z))) : [];
    const id = placed.length > 1 ? ++this.pieceCounter : 0; // 다시 덩어리로 잡히게 새 id (1칸은 id 없음)
    for (const c of placed) {
      const i = this.idx(c.x, c.y, z);
      this.grid[i] = c.v;
      this.gridPiece[i] = id;
      if (c.meta) this.bblocks.set(cellKey(c.x, c.y, z), { ...c.meta, x: c.x, y: c.y, z });
    }
    const cells = placed.map((c) => [c.x, c.y, z]);
    if (cells.length) {
      this.landed.hook++;
      this.gridChanged();
      for (const pc of this.pieces) this.updateLanding(pc);
      // 박힌 칸 사람은 압사 대신 밀쳐냄 (내려찍은 방향으로 덩어리 밖, 막히면 블록 위로)
      for (const t of this.players.values()) {
        if (!this.onField(t) || !cells.some(([x, y]) => overlapsCell(t, x, y, z))) continue;
        let moved = null;
        for (let d = 0.1; d <= 4.5 && !moved; d += 0.1) {
          const m = { ...t, x: t.x + dir.x * d, y: t.y + dir.y * d };
          if (!this.overlappingSolid(this.aabb(m)).length) moved = m;
        }
        if (moved) Object.assign(t, { x: moved.x, y: moved.y });
        else this.ejectFromBlocks(t);
      }
    }
    this.emit({ type: 'blockSlam', who: p.id, dir, len: C.HOOK_SLAM_LEN, cell: cells[0] || null, cells, builder: !!g.meta });
    const where = !cells.length ? ' → 필드 밖으로 사라짐' : cells.length === 1 ? ` → (${cells[0].join(',')}) 박힘` : ` → ${cells.length}칸 박힘 (${cells[0].join(',')})`;
    this.log(`  [필살] ${p.name} 블록 내려찍기 (${n}명)${where}`);
    this.clearLayers();
  }

  // 뽑는 중에 맞음: 덩어리를 제자리로 (빈 칸만)
  hookGrabDrop(p) {
    const g = p.grab;
    p.grab = null;
    const id = g.cells.length > 1 ? ++this.pieceCounter : 0;
    for (const c of g.cells) {
      if (c.z >= this.H || this.grid[this.idx(c.x, c.y, c.z)] || this.pieceCells.has(cellKey(c.x, c.y, c.z))) continue;
      this.grid[this.idx(c.x, c.y, c.z)] = c.v;
      this.gridPiece[this.idx(c.x, c.y, c.z)] = id;
      if (c.meta) this.bblocks.set(cellKey(c.x, c.y, c.z), { ...c.meta, x: c.x, y: c.y, z: c.z });
    }
    this.gridChanged();
    for (const pc of this.pieces) this.updateLanding(pc);
  }
}
