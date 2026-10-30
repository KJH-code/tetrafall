// Game 메서드 묶음: 블록 자리 고르기: 하늘 계단 사슬·자동 블록 (CLEAR_BIAS 점수). server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, rotatedCells, footprint } from '../shared/pieces.js';
import { skyReach, cellBox } from './game-util.js';

export class PlacementPart {
  // ---- 하늘 계단 ----
  // 하늘 블록이 SKY_COUNT 개가 되도록 맨 위에 하나씩 붙인다 (자리가 없으면 다음 틱에 다시)
  // 한 틱에 SKY_SPAWN_PER_TICK 개까지 (2026-10-26 버그: 판 시작 7개를 한 틱에 놓아 서버 틱이 멈춤 → 7틱에 나눠 놓음)
  // 사슬이 여럿이면 (SKY_CHAINS) 블록이 가장 적은 사슬부터, 한 틱에 모두 합쳐 SKY_SPAWN_PER_TICK 개
  fillSky() {
    const n = Array.from({ length: this.skyChains }, () => 0);
    for (const pc of this.pieces) if (pc.sky && pc.chain < this.skyChains) n[pc.chain]++;
    for (let k = 0; k < C.SKY_SPAWN_PER_TICK; k++) {
      const c = n.indexOf(Math.min(...n));
      if (n[c] >= C.SKY_COUNT || !this.spawnSky(c)) return;
      n[c]++;
    }
  }

  spawnSky(chain = 0) {
    const skies = this.pieces.filter((pc) => pc.sky && pc.chain === chain);
    // 사슬 맨 위 = 마지막에 붙인 블록. 그게 착지·녹아 없으면 가장 높은 하늘 블록, 하나도 없으면 새 사슬
    const top = skies.find((pc) => pc.id === this.skyTops[chain]) || skies.reduce((a, pc) => (!a || pc.pz > a.pz ? pc : a), null);
    const piece = this.chooseSkyPlacement(top);
    if (!piece) return null;
    // 모든 하늘 블록이 같은 순간에 한 칸씩 내려가게 판 시작 시각 기준 SKY_FALL_STEP_MS 박자에 맞춤 (높이차가 그대로)
    const step = C.SKY_FALL_STEP_MS;
    const nextStepAt = this.roundStartTime + (Math.floor((this.time - this.roundStartTime) / step) + 1) * step;
    this.addPiece(piece, { phase: 'falling', controller: null, sky: true, chain, stepMs: step, nextStepAt, controlEndsAt: 0 });
    this.skyTops[chain] = piece.id;
    return piece;
  }

  // 하늘 블록 자리: 맨 위 블록(top) 옆, 높이 = top 지금 높이 + SKY_RISE_MIN~MAX, 칸 사이 거리 SKY_GAP_MIN ~ skyReach(높이차) × SKY_REACH_SAFETY.
  // 다른 공중 블록과 같은 기둥에는 안 놓고, 높이가 비슷한(2칸 안) 블록과도 SKY_GAP_MIN 은 띄움.
  // 조건을 만족하는 후보 중에서는 자동 블록처럼 CLEAR_BIAS 점수로 가중 무작위 (층 클리어 유도 유지). top 이 없으면 착지 높이 + SKY_BASE_UP
  chooseSkyPlacement(top) {
    // 빠르게 (2026-10-26 버그: 판 시작 사슬 7개를 한 틱에 놓느라 틱이 0.2~0.9초 멈춤): 기둥 높이를 한 번만 재고,
    // 싼 조건(같은 기둥·틈·붙음)으로 먼저 거른 뒤 점수는 placementScorer (placementScore 와 같은 값). 후보마다 객체를 안 만들고
    // 고른 자리만 블록으로 만듦 (고르는 결과는 예전 방식과 같음)
    const sc = this.placementScorer();
    const W = this.W;
    const busy = new Uint8Array(W * this.D); // 다른 공중 블록이 있는 기둥
    for (const pc of this.pieces) for (const [dx, dy] of pc.cells) if (this.inXY(pc.px + dx, pc.py + dy)) busy[(pc.py + dy) * W + pc.px + dx] = 1;
    // 다른 블록 칸 (붙음 검사용): [x, y, pz] 납작하게
    const others = this.pieces.map((pc) => ({ pz: pc.pz, xy: pc.cells.flatMap(([dx, dy]) => [pc.px + dx, pc.py + dy]) }));
    const topXY = top ? top.cells.flatMap(([dx, dy]) => [top.px + dx, top.py + dy]) : null;
    // 칸 4개(cx·cy 납작) 와 칸 목록 xy 사이 가장 가까운 거리의 제곱
    const gap2 = (cxy, px, py, xy) => {
      let best = Infinity;
      for (let i = 0; i < 8; i += 2) {
        const ax = px + cxy[i];
        const ay = py + cxy[i + 1];
        for (let j = 0; j < xy.length; j += 2) {
          const dx = Math.max(0, Math.abs(ax - xy[j]) - 1);
          const dy = Math.max(0, Math.abs(ay - xy[j + 1]) - 1);
          const d = dx * dx + dy * dy;
          if (d < best) best = d;
        }
      }
      return best;
    };
    const minGap2 = C.SKY_GAP_MIN * C.SKY_GAP_MIN;
    const rises = [];
    for (let r = C.SKY_RISE_MIN; r <= C.SKY_RISE_MAX; r++) rises.push(r);
    // 높이차는 무작위로 하나 먼저, 그 높이에 자리가 없으면 나머지
    const first = rises.splice(Math.floor(this.rng() * rises.length), 1);
    for (const r of top ? first.concat(rises) : [0]) {
      const pz0 = top ? top.pz + r : 0;
      if (top && pz0 + 1 > C.SKY_TOP_Z) continue;
      const maxGap = top ? skyReach(r) * C.SKY_REACH_SAFETY : Infinity;
      const maxGap2 = maxGap * maxGap;
      const tb = top ? cellBox(top) : null;
      const cands = [];
      let best = -Infinity;
      for (const shape of SHAPE_NAMES) {
        for (let rot = 0; rot < 4; rot++) {
          const cells = rotatedCells(shape, rot);
          const cxy = cells.flatMap(([dx, dy]) => [dx, dy]);
          const { w, d } = footprint(cells);
          for (let px = 0; px <= this.W - w; px++) {
            // 맨 위 블록과 x 로만 봐도 멀면 이 열 전체를 건너뜀 (테두리 상자 거리 ≤ 칸 거리)
            if (top && Math.max(0, tb.x0 - (px + w), px - tb.x1) > maxGap) continue;
            for (let py = 0; py <= this.D - d; py++) {
              if (top) {
                const bx = Math.max(0, tb.x0 - (px + w), px - tb.x1);
                const by = Math.max(0, tb.y0 - (py + d), py - tb.y1);
                if (bx * bx + by * by > maxGap2) continue;
              }
              let landZ = 0;
              let hit = false;
              for (let i = 0; i < 8; i += 2) {
                const k = (py + cxy[i + 1]) * W + px + cxy[i];
                if (busy[k]) hit = true;
                if (sc.tops[k] > landZ) landZ = sc.tops[k];
              }
              if (hit) continue;
              if (top && gap2(cxy, px, py, topXY) > maxGap2) continue;
              const pz = top ? pz0 : Math.min(C.SKY_TOP_Z - 1, landZ + C.SKY_BASE_UP);
              if (pz <= landZ) continue; // 놓자마자 착지하는 자리 (기둥이 사슬 높이까지 찼음)
              if (landZ + 1 > this.H) continue; // pieceFits
              let close = false;
              for (const o of others) if (Math.abs(o.pz - pz) <= 2 && gap2(cxy, px, py, o.xy) < minGap2) close = true;
              if (close) continue;
              const score = C.CLEAR_BIAS > 0 ? sc.score(cells, px, py, landZ) : 0;
              if (score > best) best = score;
              cands.push({ shape, rot, px, py, pz, score });
            }
          }
        }
      }
      if (!cands.length) continue;
      let total = 0;
      for (const c of cands) total += c.w = Math.exp(C.CLEAR_BIAS * (c.score - best));
      let x = this.rng() * total;
      let pick = cands[cands.length - 1];
      for (const c of cands) {
        x -= c.w;
        if (x <= 0) {
          pick = c;
          break;
        }
      }
      return this.makePiece(pick.shape, pick.rot, pick.px, pick.py, pick.pz);
    }
    return null;
  }


  // placementScore 를 지금 격자로 빠르게 (자동 블록·하늘 블록 자리 고르기): 기둥 높이·가장 낮은 층을 한 번만 재고, 덩어리 찾기는 배열 스택·도장(stamp)으로 (Set 없이).
  // score(cells, px, py, z) 는 같은 자리의 placementScore(piece, L) 와 같은 값 (테스트로 고정)
  placementScorer() {
    const W = this.W;
    const D = this.D;
    const N = W * D;
    const tops = new Int16Array(N);
    let L = Infinity;
    for (let x = 0; x < W; x++) {
      for (let y = 0; y < D; y++) {
        const t = this.columnTop(x, y);
        tops[y * W + x] = t;
        if (t < L) L = t;
      }
    }
    const S = C.CLEAR_SCORE;
    const seen = new Uint32Array(N);
    const cov = new Uint32Array(N);
    const stack = new Int32Array(N);
    let stamp = 1;
    // 가장 낮은 층의 빈 칸 덩어리를 한 번만 나눠 둠 (comp: 칸 → 덩어리 번호, size: 덩어리 칸 수)
    const comp = new Int32Array(N).fill(-1);
    const size = [];
    let baseRemaining = 0;
    let baseBad = 0;
    for (let i = 0; i < N; i++) {
      if (tops[i] !== L || comp[i] >= 0) continue;
      const id = size.length;
      let n = 0;
      let sp = 0;
      stack[sp++] = i;
      comp[i] = id;
      while (sp) {
        const c = stack[--sp];
        n++;
        const cx = c % W;
        for (let k = 0; k < 4; k++) {
          const q = k === 0 ? (cx + 1 < W ? c + 1 : -1) : k === 1 ? (cx > 0 ? c - 1 : -1) : k === 2 ? (c + W < N ? c + W : -1) : c - W;
          if (q >= 0 && tops[q] === L && comp[q] < 0) {
            comp[q] = id;
            stack[sp++] = q;
          }
        }
      }
      size.push(n);
      baseRemaining += n;
      if (n % 4 !== 0) baseBad++;
    }
    // 덮인 칸을 뺀 뒤 덩어리 id 의 남은 조각들 크기. 덮인 칸 둘레 이웃(같은 덩어리)이 한 번의 탐색에서 다 만나면
    // 나머지는 한 조각 (크기 = 원래 - 덮인 칸) 이라 거기서 멈춤 → 보통 블록 둘레 몇 칸만 봄
    const ringMark = new Uint32Array(N);
    const ring = new Int32Array(16); // 블록 4칸 둘레는 많아야 10칸
    // 덩어리 id 에서 덮인 칸(covStamp)을 뺀 조각들의 크기를 out 에. 덮인 칸 둘레(같은 덩어리 이웃)를 너비 우선으로 찾다가
    // 첫 조각이 둘레를 다 만나면 남은 칸 전부가 한 조각 (크기 = 원래 - 덮인 칸) → 보통 블록 둘레 몇십 칸만 봄
    const parts = (id, covered, coveredIn, covStamp, out) => {
      const rs = ++stamp;
      let nr = 0;
      for (const c of covered) {
        const cx = c % W;
        for (let k = 0; k < 4; k++) {
          const q = k === 0 ? (cx + 1 < W ? c + 1 : -1) : k === 1 ? (cx > 0 ? c - 1 : -1) : k === 2 ? (c + W < N ? c + W : -1) : c - W;
          if (q < 0 || comp[q] !== id || cov[q] === covStamp || ringMark[q] === rs) continue;
          ringMark[q] = rs;
          ring[nr++] = q;
        }
      }
      if (!nr) return; // 덩어리가 통째로 덮임
      let left = size[id] - coveredIn;
      const ss = ++stamp;
      let found = 0;
      for (let r = 0; r < nr; r++) {
        const r0 = ring[r];
        if (seen[r0] === ss) continue;
        let n = 0;
        let head = 0;
        let tail = 0;
        stack[tail++] = r0;
        seen[r0] = ss;
        while (head < tail) {
          const c = stack[head++];
          n++;
          if (ringMark[c] === rs && ++found === nr && !out.length) {
            out.push(left); // 첫 조각이 둘레를 다 만남 → 남은 칸 전부 한 조각
            return;
          }
          const cx = c % W;
          for (let k = 0; k < 4; k++) {
            const q = k === 0 ? (cx + 1 < W ? c + 1 : -1) : k === 1 ? (cx > 0 ? c - 1 : -1) : k === 2 ? (c + W < N ? c + W : -1) : c - W;
            if (q < 0 || comp[q] !== id || cov[q] === covStamp || seen[q] === ss) continue;
            seen[q] = ss;
            stack[tail++] = q;
          }
        }
        out.push(n);
        left -= n;
      }
    };
    const covered = [0, 0, 0, 0];
    const out = [];
    const score = (cells, px, py, z) => {
      let holes = 0;
      for (const [dx, dy] of cells) holes += z - tops[(py + dy) * W + px + dx];
      if (holes > 0) return -S.HOLE * holes - (z - L);
      if (z !== L) return -(z - L);
      // 여기까지 오면 덮인 칸은 모두 가장 낮은 층의 빈 칸
      const covStamp = ++stamp;
      for (let k = 0; k < 4; k++) {
        const c = (py + cells[k][1]) * W + px + cells[k][0];
        cov[c] = covStamp;
        covered[k] = c;
      }
      const remaining = baseRemaining - 4;
      // 빠른 길: 블록 둘레(대각선 포함) 칸이 모두 필드 안의 빈 칸이면 둘레가 이어진 고리라 남은 칸은 한 조각 →
      // 덩어리 크기가 4 줄어도 4로 나눈 나머지는 그대로라 bad 도 그대로 (테트로미노는 구멍이 없어서 둘레가 한 고리)
      let ringOpen = true;
      for (let k = 0; k < 4 && ringOpen; k++) {
        const c = covered[k];
        const cx = c % W;
        const cy = (c - cx) / W;
        for (let oy = -1; oy <= 1 && ringOpen; oy++) {
          for (let ox = -1; ox <= 1; ox++) {
            const x = cx + ox;
            const y = cy + oy;
            if (x < 0 || y < 0 || x >= W || y >= D) {
              ringOpen = false; // 필드 끝에 닿으면 끝과 블록 사이에 갇힌 칸이 생길 수 있어 느린 길로
              break;
            }
            const q = y * W + x;
            if (cov[q] !== covStamp && tops[q] !== L) {
              ringOpen = false;
              break;
            }
          }
        }
      }
      if (ringOpen) return S.FILL + (remaining === 0 ? S.CLEAR : 0) - S.BAD_GAP * baseBad;
      let bad = baseBad;
      for (let k = 0; k < 4; k++) {
        const id = comp[covered[k]];
        let dup = false;
        for (let j = 0; j < k; j++) if (comp[covered[j]] === id) dup = true;
        if (dup) continue; // 덩어리마다 한 번
        let coveredIn = 0;
        for (let j = 0; j < 4; j++) if (comp[covered[j]] === id) coveredIn++;
        if (size[id] % 4 !== 0) bad--;
        out.length = 0;
        parts(id, covered, coveredIn, covStamp, out);
        for (const n of out) if (n % 4 !== 0) bad++;
      }
      return S.FILL + (remaining === 0 ? S.CLEAR : 0) - S.BAD_GAP * bad;
    };
    return { tops, L, score };
  }

  // 자동 블록 고르기: 들어갈 수 있는 모든 (모양, 회전, 위치) 중에서 가중 무작위로 하나.
  // 가중치 = exp(CLEAR_BIAS × 점수). CLEAR_BIAS 0 이면 완전 무작위, 클수록 가장 낮은 층을 클리어하는 쪽으로 몰린다.
  // CLEAR_PICK_SHAPE 가 false 면 모양은 무작위로 정하고 회전·위치만 고른다 (이 경우 클리어가 거의 안 일어난다).
  chooseAutoPlacement(randomShape) {
    const shapes = C.CLEAR_BIAS > 0 && C.CLEAR_PICK_SHAPE ? SHAPE_NAMES : [randomShape];
    // 빠르게 (2026-10-26: 판 시작 블록 자리 고르기에 틱이 0.1~0.4초 멈춤): 기둥 높이는 placementScorer 가 한 번만 재고,
    // 점수도 그걸로 (placementScore 와 같은 값). 블록은 고른 자리만 만듦 → 고르는 결과는 예전과 같음
    const sc = this.placementScorer();
    const W = this.W;
    // 다른 블록(떨어지는 중·조종 중)과 같은 기둥에는 안 떨어뜨린다: 그림자가 겹치지 않게
    const busy = new Uint8Array(W * this.D);
    for (const pc of this.pieces) for (const [dx, dy] of pc.cells) if (this.inXY(pc.px + dx, pc.py + dy)) busy[(pc.py + dy) * W + pc.px + dx] = 1;
    const cands = [];
    let best = -Infinity;
    for (const shape of shapes) {
      for (let r = 0; r < 4; r++) {
        const cells = rotatedCells(shape, r);
        const { w, d } = footprint(cells);
        for (let px = 0; px <= this.W - w; px++) {
          for (let py = 0; py <= this.D - d; py++) {
            let landZ = 0;
            let hit = false;
            for (const [dx, dy] of cells) {
              const i = (py + dy) * W + px + dx;
              if (busy[i]) hit = true;
              if (sc.tops[i] > landZ) landZ = sc.tops[i];
            }
            if (landZ + 1 > this.H || landZ > C.PIECE_SPAWN_Z) continue; // pieceFits
            if (hit) continue;
            const score = C.CLEAR_BIAS > 0 ? sc.score(cells, px, py, landZ) : 0;
            if (score > best) best = score;
            cands.push({ shape, r, px, py, score });
          }
        }
      }
    }
    if (!cands.length) return null;
    let total = 0;
    for (const c of cands) {
      c.w = Math.exp(C.CLEAR_BIAS * (c.score - best)); // best 기준으로 빼서 overflow 방지
      total += c.w;
    }
    let x = this.rng() * total;
    let pick = cands[cands.length - 1];
    for (const c of cands) {
      x -= c.w;
      if (x <= 0) {
        pick = c;
        break;
      }
    }
    return this.makePiece(pick.shape, pick.r, pick.px, pick.py, C.PIECE_SPAWN_Z);
  }


  // 가장 낮은 기둥 높이 = 아직 안 찬 가장 낮은 층
  lowestLayer() {
    let L = Infinity;
    for (let x = 0; x < this.W; x++) for (let y = 0; y < this.D; y++) L = Math.min(L, this.columnTop(x, y));
    return L;
  }

  // 자동 블록 자리 점수. 높을수록 가장 낮은 층(L) 클리어에 가깝다.
  // - 밑에 빈칸(구멍)을 만들면 벌점: 구멍 위층은 다시 채울 수 없다
  // - L 층에 딱 붙으면 가점, 그걸로 L 층이 다 차면 큰 가점
  // - L 층에 남는 빈 영역 중 칸 수가 4의 배수가 아닌 덩어리는 벌점: 평평한 4칸 블록으로 영영 못 채운다
  // - L 보다 높은 곳에 평평하게 얹으면 높이만큼 약한 벌점
  placementScore(piece, L) {
    const S = C.CLEAR_SCORE;
    const z = piece.landZ;
    let holes = 0;
    for (const [dx, dy] of piece.cells) holes += z - this.columnTop(piece.px + dx, piece.py + dy);
    if (holes > 0) return -S.HOLE * holes - (z - L);
    if (z !== L) return -(z - L);
    const covered = new Set(piece.cells.map(([dx, dy]) => (piece.px + dx) * 100 + (piece.py + dy)));
    const open = (x, y) => this.columnTop(x, y) === L && !covered.has(x * 100 + y);
    let remaining = 0;
    let bad = 0;
    const seen = new Set();
    for (let x = 0; x < this.W; x++) {
      for (let y = 0; y < this.D; y++) {
        if (!open(x, y) || seen.has(x * 100 + y)) continue;
        let size = 0;
        const stack = [[x, y]];
        seen.add(x * 100 + y);
        while (stack.length) {
          const [cx, cy] = stack.pop();
          size++;
          for (const [nx, ny] of [[cx + 1, cy], [cx - 1, cy], [cx, cy + 1], [cx, cy - 1]]) {
            if (nx < 0 || ny < 0 || nx >= this.W || ny >= this.D) continue;
            if (!open(nx, ny) || seen.has(nx * 100 + ny)) continue;
            seen.add(nx * 100 + ny);
            stack.push([nx, ny]);
          }
        }
        remaining += size;
        if (size % 4 !== 0) bad++;
      }
    }
    return S.FILL + (remaining === 0 ? S.CLEAR : 0) - S.BAD_GAP * bad;
  }
}
