// Game 메서드 묶음: 캐릭터: 건축가. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { cellKey, overlapsCell, BBLOCK_LOG } from './game-util.js';

export class BuilderPart {
  // ---- 건축가 (2026-10-25 재혁 확정, docs/characters.md 3.1) ----
  // 건축가 블록: 격자에는 CELL.BUILD 로 두고 주인·종류·묶음·수명은 this.bblocks 에. 건축가 망치로 치면 폭발 (치는 방향 앞만, 자신 제외),
  // 같은 F 벽 묶음끼리만 연쇄. BUILDER_BLOCK_MS 뒤 사라짐. 패시브: 내 블록이 터지면 1칸당 게이지 (대폭발 블록 제외)

  // 지상 F: 솟는 벽 — 바로 앞(네 방향으로 맞춤) 줄에 가로 BUILDER_WALL_WIDTH × BUILDER_WALL_HEIGHT. 바닥에 예고 → BUILDER_WALL_WARN_MS 뒤 솟음
  // 공중 F: 발판 — 발밑에 블록 1칸 + 위로 부스트 (쿨 같이 씀)
  builderWall(p) {
    if (!p.grounded) return this.builderPad(p);
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const along = Math.abs(fx) >= Math.abs(fy) ? [Math.sign(fx), 0] : [0, Math.sign(fy)];
    const side = [-along[1], along[0]];
    const cx = Math.floor(p.x) + along[0];
    const cy = Math.floor(p.y) + along[1];
    const z0 = Math.max(0, Math.round(p.z));
    const half = Math.floor(C.BUILDER_WALL_WIDTH / 2);
    const cells = [];
    for (let i = -half; i <= half; i++) {
      const x = cx + side[0] * i;
      const y = cy + side[1] * i;
      if (!this.inXY(x, y) || this.grid[this.idx(x, y, z0)]) continue;
      for (let h = 0; h < C.BUILDER_WALL_HEIGHT; h++) if (z0 + h < this.H) cells.push([x, y, z0 + h]);
    }
    if (!cells.length) return false;
    p.wallAt = this.time + C.BUILDER_WALL_WARN_MS;
    p.wallCells = cells;
    this.emit({ type: 'wallWarn', who: p.id, cells, ms: C.BUILDER_WALL_WARN_MS });
    this.log(`  [스킬] ${p.name} 솟는 벽 준비`);
    return true;
  }

  builderWallRise(p) {
    const cells = p.wallCells;
    p.wallAt = 0;
    p.wallCells = null;
    const g = ++this.bgroup;
    // 예고 동안 건축가가 벽 칸으로 걸어 들어갔으면 그 칸은 안 솟음 (2026-10-26 재혁: 자기 벽에 같이 떠올랐음)
    const placed = cells.filter(([x, y, z]) => !overlapsCell(p, x, y, z) && this.placeBBlock(p, x, y, z, 'wall', g));
    if (!placed.length) return;
    this.gridChanged();
    const launched = new Set();
    // 벽 칸에 있던 사람은 벽 위로 올리고 띄움 (건축가 자신은 밀려남만)
    for (const t of this.players.values()) {
      if (!this.onField(t) || !placed.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t) || launched.has(t.id)) continue;
      launched.add(t.id);
      const hit = this.applyKnockback(t, Math.cos(p.yaw), Math.sin(p.yaw), 0, C.BUILDER_WALL_KB_UP, C.BUILDER_WALL_STUN_MS, C.BUILDER_WALL_DAMAGE, { by: p.id, kind: 'wall' });
      this.emit({ type: 'hit', kind: 'wall', by: p.id, target: t.id, ok: hit });
    }
    this.emit({ type: 'wallRise', who: p.id, cells: placed });
    this.emit({ type: 'bblock', who: p.id, kind: 'wall', group: g, cells: placed, ms: C.BUILDER_BLOCK_MS });
    this.log(`  [스킬] ${p.name} 솟는 벽 (${placed.length}칸${launched.size ? `, ${launched.size}명 띄움` : ''})`);
    this.clearLayers();
  }

  // 공중 F (2026-10-30 재혁: 1칸 발판 + 부스트 → 세로 기둥): 발밑으로 BUILDER_PAD_HEIGHT 칸 기둥을 세우고 나는 그 위에 섬 (부스트 없음).
  // 기둥은 발밑 칸부터 아래로, 막힌 칸(블록·바닥·사람)에서 멈춤 (그 아래가 바로 땅이면 1칸). 한 칸도 못 놓으면(필드 밖·바로 밑이 막힘) 예전처럼 위로 부스트 (복귀기).
  // 두 칸은 같은 묶음 → 망치로 치면 같이 터짐, BUILDER_BLOCK_MS 뒤 같이 사라짐
  builderPad(p) {
    const x = Math.floor(p.x);
    const y = Math.floor(p.y);
    const top = Math.floor(p.z); // 서게 될 높이 (발밑 칸 윗면)
    const g = ++this.bgroup;
    const cells = [];
    for (let k = 1; k <= C.BUILDER_PAD_HEIGHT; k++) {
      const z = top - k;
      if (!this.inXY(x, y) || z < 0 || this.grid[this.idx(x, y, z)] || this.pieceCells.has(cellKey(x, y, z))) break;
      if ([...this.players.values()].some((o) => o !== p && this.onField(o) && overlapsCell(o, x, y, z))) break;
      cells.push([x, y, z]);
    }
    const placed = cells.filter(([cx, cy, cz]) => this.placeBBlock(p, cx, cy, cz, 'pad', g));
    if (placed.length) {
      this.gridChanged();
      this.emit({ type: 'bblock', who: p.id, kind: 'pad', group: g, cells: placed, ms: C.BUILDER_BLOCK_MS });
      p.z = top;
      p.vz = 0;
      p.grounded = true;
    } else {
      p.vz = C.BUILDER_PAD_BOOST;
      p.grounded = false;
    }
    this.emit({ type: 'padBoost', who: p.id, cell: placed.length ? placed[0] : null, cells: placed, stand: placed.length > 0 });
    this.log(`  [스킬] ${p.name} 발판${placed.length ? ` 기둥 ${placed.length}칸 (${x},${y},${placed[placed.length - 1][2]}~${placed[0][2]})` : ' (칸 없이 부스트)'}`);
    return true;
  }

  // 건축가 블록 놓기 (빈 칸일 때만). 놓았으면 true
  placeBBlock(p, x, y, z, kind, group) {
    if (!this.inXY(x, y) || z < 0 || z >= this.H || this.grid[this.idx(x, y, z)] || this.pieceCells.has(cellKey(x, y, z))) return false;
    this.grid[this.idx(x, y, z)] = CELL.BUILD;
    this.bblocks.set(cellKey(x, y, z), { x, y, z, owner: p.id, kind, group, expiresAt: this.time + C.BUILDER_BLOCK_MS, born: this.time });
    this.landed.builder++;
    return true;
  }

  removeBBlock(b, why) {
    this.bblocks.delete(cellKey(b.x, b.y, b.z));
    if (this.grid[this.idx(b.x, b.y, b.z)] === CELL.BUILD) this.grid[this.idx(b.x, b.y, b.z)] = 0;
    this.gridChanged();
    if (why !== 'blast') this.emit({ type: 'bblockGone', cells: [[b.x, b.y, b.z]], why });
  }

  // R 대폭발: 앞(네 방향으로 맞춤) BUILDER_BIG_GAP 칸 띄우고 BUILDER_BIG_SIZE × BUILDER_BIG_SIZE 기둥 꼭대기에서 블록이 솟음 (위 사람 띄움)
  // → BUILDER_BIG_FUSE_MS 뒤 자동 대폭발. 망치로 치면 바로. 블록이 위에서 떨어지지 않음 (압사 억까 금지)
  builderBigBomb(p) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const along = Math.abs(fx) >= Math.abs(fy) ? [Math.sign(fx), 0] : [0, Math.sign(fy)];
    const side = [-along[1], along[0]];
    const half = Math.floor(C.BUILDER_BIG_SIZE / 2);
    const g = ++this.bgroup;
    const placed = [];
    for (let a = 0; a < C.BUILDER_BIG_SIZE; a++) {
      for (let i = -half; i <= half; i++) {
        const x = Math.floor(p.x) + along[0] * (C.BUILDER_BIG_GAP + 1 + a) + side[0] * i;
        const y = Math.floor(p.y) + along[1] * (C.BUILDER_BIG_GAP + 1 + a) + side[1] * i;
        if (!this.inXY(x, y)) continue;
        const z = this.columnTop(x, y);
        if (this.placeBBlock(p, x, y, z, 'big', g)) placed.push([x, y, z]);
      }
    }
    if (!placed.length) return false;
    this.gridChanged();
    const launched = new Set();
    for (const t of this.players.values()) {
      if (!this.onField(t) || !placed.some(([x, y, z]) => overlapsCell(t, x, y, z))) continue;
      this.ejectFromBlocks(t);
      if (!this.foe(p, t) || launched.has(t.id)) continue;
      launched.add(t.id);
      const hit = this.applyKnockback(t, along[0], along[1], 0, C.BUILDER_BIG_RISE_UP, C.BUILDER_BIG_RISE_STUN_MS, 0, { by: p.id, kind: 'bigbomb' });
      this.emit({ type: 'hit', kind: 'bigbomb', by: p.id, target: t.id, ok: hit });
    }
    this.bigBombs.push({ owner: p.id, group: g, at: this.time + C.BUILDER_BIG_FUSE_MS, dir: { x: along[0], y: along[1] } });
    this.emit({ type: 'bigBombWarn', who: p.id, cells: placed, ms: C.BUILDER_BIG_FUSE_MS, group: g });
    this.log(`  [필살] ${p.name} 대폭발 준비 (${placed.length}칸${launched.size ? `, ${launched.size}명 띄움` : ''})`);
    this.clearLayers();
    return true;
  }

  // 대폭발 터짐 (자동 또는 망치). 범위 안 사람 한 번씩 dir 쪽으로 날림, 범위 안 내 블록(벽·3타)도 같이 터짐
  explodeBig(bomb, dir) {
    this.bigBombs = this.bigBombs.filter((b) => b !== bomb);
    const p = this.players.get(bomb.owner);
    const cells = [...this.bblocks.values()].filter((b) => b.group === bomb.group);
    for (const b of cells) this.removeBBlock(b, 'blast');
    if (!cells.length) return;
    this.holeUnder(cells);
    let n = 0;
    for (const t of this.players.values()) {
      if (!p || !this.foe(p, t) || !cells.some((b) => this.nearCell(t, b, C.BUILDER_BIG_RANGE))) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.BUILDER_BIG_KB_SPEED, C.BUILDER_BIG_KB_UP, C.BUILDER_BIG_STUN_MS, C.BUILDER_BIG_DAMAGE, { by: bomb.owner, kind: 'bigbomb' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'bigbomb', by: bomb.owner, target: t.id, ok: hit });
    }
    this.emit({ type: 'bigBomb', who: bomb.owner, cells: cells.map((b) => [b.x, b.y, b.z]), dir });
    // 범위 안 내 블록도 같이 (묶음째)
    const near = [...this.bblocks.values()].filter((b) => b.owner === bomb.owner && b.kind !== 'big' && cells.some((c) => Math.abs(c.x - b.x) <= 1 && Math.abs(c.y - b.y) <= 1 && Math.abs(c.z - b.z) <= 1));
    let also = 0;
    const done = new Set();
    for (const b of near) {
      if (!this.bblocks.has(cellKey(b.x, b.y, b.z)) || done.has(b.group)) continue;
      done.add(b.group);
      also += this.blast(b, dir);
    }
    this.log(`  [필살] ${p ? p.name : '?'} 대폭발 (${n}명${also ? `, 같이 터진 블록 ${also}칸` : ''})`);
  }

  // 사람 몸(가로 상자)이 칸 가장자리에서 r 안, 높이 차 BUILDER_BLAST_HEIGHT 안
  nearCell(t, b, r) {
    const gx = Math.max(b.x - (t.x + C.PLAYER_HALF), t.x - C.PLAYER_HALF - (b.x + 1), 0);
    const gy = Math.max(b.y - (t.y + C.PLAYER_HALF), t.y - C.PLAYER_HALF - (b.y + 1), 0);
    return Math.hypot(gx, gy) <= r && Math.abs(t.z - b.z) <= C.BUILDER_BLAST_HEIGHT;
  }

  // 망치(평타) 판정이 닿은 내 블록을 터뜨림. 터뜨렸으면 true
  hammerBlocks(p, range, cosHalf) {
    const fx = Math.cos(p.yaw);
    const fy = Math.sin(p.yaw);
    const hitGroups = new Set();
    const targets = [];
    for (const b of this.bblocks.values()) {
      if (b.owner !== p.id || hitGroups.has(b.group)) continue; // 발판도 터짐 (2026-10-25 재혁: 밟고 있는 발판을 쳐서 떨어지는 건 플레이어가 고름)
      const dx = b.x + 0.5 - p.x;
      const dy = b.y + 0.5 - p.y;
      const dist = Math.hypot(dx, dy);
      if (dist > range + 0.5 || b.z + 1 < p.z - 0.1 || b.z > p.z + C.PLAYER_HEIGHT) continue;
      if (dist > C.BASIC_STEP_GAP + 0.5 && (dx * fx + dy * fy) / dist < cosHalf) continue;
      hitGroups.add(b.group);
      targets.push(b);
    }
    for (const b of targets) {
      if (b.kind === 'big') {
        const bomb = this.bigBombs.find((x) => x.group === b.group);
        if (bomb) this.explodeBig(bomb, { x: fx, y: fy });
      } else if (this.bblocks.has(cellKey(b.x, b.y, b.z))) this.blast(b, { x: fx, y: fy });
    }
    return targets.length > 0;
  }

  // 벽·3타 블록·발판 폭발. 벽·발판 기둥은 같은 묶음(같은 F)끼리 이어진 칸으로 연쇄. 사람은 한 번씩, 가까운 터진 칸 수 × BUILDER_BLAST_DAMAGE.
  // 치는 방향(dir) 앞쪽 사람만 dir 쪽으로 날림, 건축가 자신은 안 맞음. 터진 칸 수를 돌려줌
  blast(start, dir) {
    const p = this.players.get(start.owner);
    const order = [start];
    const seen = new Set([cellKey(start.x, start.y, start.z)]);
    if (start.kind === 'wall' || start.kind === 'pad') {
      for (let i = 0; i < order.length; i++) {
        const c = order[i];
        for (const [ox, oy, oz] of [[1, 0, 0], [-1, 0, 0], [0, 1, 0], [0, -1, 0], [0, 0, 1], [0, 0, -1]]) {
          const k = cellKey(c.x + ox, c.y + oy, c.z + oz);
          const nb = this.bblocks.get(k);
          if (nb && !seen.has(k) && nb.group === start.group) {
            seen.add(k);
            order.push(nb);
          }
        }
      }
    }
    for (const b of order) this.removeBBlock(b, 'blast');
    this.holeUnder(order);
    if (p) p.ult = Math.min(this.ultMax(p), p.ult + order.length * C.BUILDER_BLAST_ULT); // 패시브: 내 블록 폭발 1칸당 게이지
    const hits = [];
    for (const t of this.players.values()) {
      if (!p || !this.foe(p, t)) continue;
      const near = order.filter((b) => this.nearCell(t, b, C.BUILDER_BLAST_RANGE) && (t.x - (b.x + 0.5)) * dir.x + (t.y - (b.y + 0.5)) * dir.y > -0.5);
      if (!near.length) continue;
      const hit = this.applyKnockback(t, dir.x, dir.y, C.BUILDER_BLAST_KB_SPEED, C.BUILDER_BLAST_KB_UP, C.BUILDER_BLAST_STUN_MS, near.length * C.BUILDER_BLAST_DAMAGE, { by: start.owner, kind: 'blast' }, true);
      this.emit({ type: 'hit', kind: 'blast', by: start.owner, target: t.id, ok: hit });
      hits.push(`${t.name}${hit ? ` ${t.damage}%` : ' 무적'}`);
    }
    this.emit({ type: 'blast', who: start.owner, kind: start.kind, group: start.group, cells: order.map((b) => [b.x, b.y, b.z]), dir });
    this.log(`  [폭발] ${p ? p.name : '?'} ${BBLOCK_LOG[start.kind]} ${order.length}칸${hits.length ? ` → ${hits.join(', ')}` : ''}`);
    return order.length;
  }

  // 테스트 옵션: 터진 칸 바로 아래 바닥 1칸을 BUILDER_HOLE_MS 동안 구멍으로 (건축가 블록·떨어지는 블록은 빼고)
  holeUnder(cells) {
    if (!C.BUILDER_BLAST_HOLE) return;
    for (const b of cells) {
      const z = b.z - 1;
      if (z < 0 || this.bblocks.has(cellKey(b.x, b.y, z)) || this.pieceCells.has(cellKey(b.x, b.y, z))) continue;
      const v = this.grid[this.idx(b.x, b.y, z)];
      if (!v) continue;
      this.grid[this.idx(b.x, b.y, z)] = 0;
      this.holes.push({ x: b.x, y: b.y, z, v, id: this.gridPiece[this.idx(b.x, b.y, z)], at: this.time + C.BUILDER_HOLE_MS });
    }
    this.gridChanged();
  }

  // 틱마다: 수명 끝난 건축가 블록 사라짐, 다른 이유로 없어진 칸(폭탄 등)은 기록에서 지움, 대폭발 시간, 구멍 메우기
  updateBBlocks() {
    for (const b of [...this.bblocks.values()]) {
      if (this.grid[this.idx(b.x, b.y, b.z)] !== CELL.BUILD) this.bblocks.delete(cellKey(b.x, b.y, b.z));
      else if (this.time >= b.expiresAt && b.kind !== 'big') this.removeBBlock(b, 'expire');
    }
    for (const bomb of [...this.bigBombs]) if (this.time >= bomb.at) this.explodeBig(bomb, bomb.dir);
    for (const h of [...this.holes]) {
      if (this.time < h.at) continue;
      if (this.grid[this.idx(h.x, h.y, h.z)] || [...this.players.values()].some((o) => this.onField(o) && overlapsCell(o, h.x, h.y, h.z))) continue; // 사람이 있으면 다음 틱
      this.grid[this.idx(h.x, h.y, h.z)] = h.v;
      this.gridPiece[this.idx(h.x, h.y, h.z)] = h.id || 0;
      this.holes = this.holes.filter((x) => x !== h);
      this.gridChanged();
    }
  }
}
