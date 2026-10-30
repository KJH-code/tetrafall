// Game 메서드 묶음: 블록: 떨어지기·조종·착지·압사·층 지우기·용암·유령 투하. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { SHAPE_NAMES, rotatedCells, footprint } from '../shared/pieces.js';
import { EPS, cellKey, fmtTime, pieceCellValue } from './game-util.js';

export class PiecesPart {
  // ---------- 블록 ----------
  // 떨어지는 블록은 여러 개 (this.pieces). 조종 블록은 한 번에 하나 (조종권 아이템이 하나뿐이라).
  // 블록끼리는 공중에서 겹치지 않는다: 한 칸 아래를 다른 블록이 차지하고 있으면 그 칸이 빌 때까지 기다린다.

  // 예전 코드·테스트 호환: "대표 블록" = 조종 중인 블록, 없으면 첫 블록
  get piece() {
    return this.pieces.find((pc) => pc.phase === 'control') || this.pieces[0] || null;
  }

  set piece(v) {
    this.pieces = v ? [v] : [];
    if (v && !v.id) v.id = ++this.pieceCounter;
    this.refreshPieceCells();
  }

  // 떨어지는 블록이 이 사람을 깔기까지 남은 시간 (ms). CRUSH_WARN_MS 안에 깔 블록이 없으면 null.
  // 블록 칸이 몸(가로 판정 상자)과 겹치고, 지금 몸 위에 있으며, 착지 높이가 머리보다 낮으면 깔림
  crushDanger(p) {
    if (this.isGhost(p) || this.time < p.shieldUntil) return null; // 블록이 통과하는 사람 (유령·부활 무적)
    let best = null;
    const b = this.aabb(p);
    for (const piece of this.pieces) {
      if (piece.phase !== 'falling') continue;
      if (!(piece.pz + 1 > p.z && piece.landZ < p.z + C.PLAYER_HEIGHT)) continue;
      const over = piece.cells.some(([dx, dy]) => {
        const x = piece.px + dx;
        const y = piece.py + dy;
        return x < b.x1 && x + 1 > b.x0 && y < b.y1 && y + 1 > b.y0;
      });
      if (!over) continue;
      // 몸 꼭대기(머리)에 닿을 때까지: 지금 높이에서 머리 위 칸까지 내려오는 칸 수 × 한 칸 간격
      const steps = Math.max(0, Math.ceil(piece.pz - (p.z + C.PLAYER_HEIGHT)));
      const eta = Math.max(0, steps * piece.stepMs + (piece.nextStepAt - this.time) - piece.stepMs);
      if (eta <= C.CRUSH_WARN_MS && (best === null || eta < best)) best = eta;
    }
    return best;
  }

  pieceWorldCells(piece = this.piece) {
    return piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy, piece.pz]);
  }

  refreshPieceCells() {
    this.pieceCells.clear();
    for (const piece of this.pieces) {
      for (const [x, y, z] of this.pieceWorldCells(piece)) this.pieceCells.set(cellKey(x, y, z), piece.id);
    }
  }

  controlledPiece(p) {
    return this.pieces.find((pc) => pc.phase === 'control' && pc.controller === p.id) || null;
  }

  // 현재 xy 에서 착지 z (착지 가능한 가장 낮은 z). 격자만 본다 (플레이어는 압사 대상이지 장애물이 아님)
  computeLandZ(piece) {
    let landZ = 0;
    for (const [dx, dy] of piece.cells) {
      const top = this.columnTop(piece.px + dx, piece.py + dy);
      if (top > landZ) landZ = top;
    }
    return landZ;
  }

  pieceFits(piece) {
    if (piece.landZ + 1 > this.H || piece.landZ > piece.pz) return false;
    // 블록 마스터: 조종 중인 블록은 주변보다 너무 높게 못 놓음 (빨간 미리보기)
    if (this.mode === 'master' && piece.phase === 'control' && this.tooTall(piece.cells.map(([dx, dy]) => [piece.px + dx, piece.py + dy]), piece.landZ)) return false;
    return true;
  }

  updateLanding(piece) {
    piece.landZ = this.computeLandZ(piece);
    piece.fits = this.pieceFits(piece);
  }

  makePiece(shape, rot, px, py, pz) {
    const cells = rotatedCells(shape, rot);
    const piece = { id: 0, shape, rot, cells, px, py, pz, landZ: 0, fits: false };
    this.updateLanding(piece);
    return piece;
  }

  // ---- 판이 길어질수록 빨라지고 많아진다 ----
  elapsed() {
    return this.time - this.roundStartTime;
  }

  rampT() {
    return Math.min(1, Math.max(0, this.elapsed() / C.RAMP_FULL_MS));
  }

  autoFallStepMs() {
    return C.AUTO_FALL_STEP_MS + (C.AUTO_FALL_STEP_MIN_MS - C.AUTO_FALL_STEP_MS) * this.rampT();
  }

  autoSpawnDelayMs() {
    return C.AUTO_SPAWN_DELAY_MS + (C.AUTO_SPAWN_DELAY_MIN_MS - C.AUTO_SPAWN_DELAY_MS) * this.rampT();
  }

  targetConcurrent() {
    return Math.max(1, Math.round(Math.min(C.CONCURRENT_MAX, C.CONCURRENT_START + Math.floor(this.elapsed() / C.CONCURRENT_RAMP_MS)) * this.areaScale())); // 넓은 판은 넓이만큼 더
  }

  addPiece(piece, fields) {
    piece.id = ++this.pieceCounter;
    Object.assign(piece, fields);
    this.pieces.push(piece);
    this.refreshPieceCells();
    return piece;
  }

  // randomSpot: 블록 마스터는 무작위 자리에서 시작 (바로 Enter 를 눌러도 한 곳에 탑이 안 쌓이게)
  spawnControlled(controller, randomSpot = false) {
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const rot = Math.floor(this.rng() * 4);
    const { w, d } = footprint(rotatedCells(shape, rot));
    const px = randomSpot ? Math.floor(this.rng() * (this.W - w + 1)) : Math.floor((this.W - w) / 2);
    const py = randomSpot ? Math.floor(this.rng() * (this.D - d + 1)) : Math.floor((this.D - d) / 2);
    const piece = this.makePiece(shape, rot, px, py, C.CONTROL_HOVER_Z);
    this.addPiece(piece, {
      phase: 'control',
      controller: controller.id,
      stepMs: C.HARD_DROP_STEP_MS,
      nextStepAt: 0,
      controlEndsAt: this.time + C.CONTROL_TIME_MS,
    });
    this.updateLanding(piece); // 조종 블록이 된 뒤 다시 (블록 마스터 높이 제한)
    controller.hasControl = false;
    this.emit({ type: 'controlStart', who: controller.id });
    this.log(`  [블록] ${shape} 조종 시작: ${controller.name}`);
    return piece;
  }

  spawnAuto() {
    const shape = SHAPE_NAMES[Math.floor(this.rng() * SHAPE_NAMES.length)];
    const piece = this.chooseAutoPlacement(shape);
    if (!piece) return null;
    const stepMs = this.autoFallStepMs();
    return this.addPiece(piece, { phase: 'falling', controller: null, stepMs, nextStepAt: this.time + stepMs, controlEndsAt: 0 });
  }

  // 예전 호환: 조종권 보유자가 있으면 조종 블록, 없으면 자동 블록 하나
  spawnPiece() {
    const holder = [...this.players.values()].find((p) => p.alive && p.hasControl) || null;
    if (holder && !this.pieces.some((pc) => pc.controller !== null)) return this.spawnControlled(holder);
    return this.spawnAuto();
  }

  updateSpawning() {
    if (this.mode === 'practice' && this.practice.noBlocks) return; // 연습: 블록 안 떨어짐
    if (this.time < this.nextSpawnAt) return;
    if (this.mode === 'master') {
      // 블록 마스터: 자동 블록 없이 마스터 편 각자의 블록만. 떨어뜨리면 MASTER_NEXT_PIECE_MS 뒤 다음 블록 (dropPiece 가 시계를 맞춤)
      for (const p of this.players.values()) {
        if (p.master && p.alive && this.time >= p.nextPieceAt && this.time >= this.masterStallUntil && !this.controlledPiece(p)) this.spawnControlled(p, true); // 반격 아이템을 먹은 동안은 안 나옴
      }
      return;
    }
    const holder = [...this.players.values()].find((p) => p.alive && p.hasControl) || null;
    if (holder && !this.pieces.some((pc) => pc.controller !== null)) {
      this.spawnControlled(holder);
      this.nextSpawnAt = this.time + this.autoSpawnDelayMs();
      return;
    }
    if (this.sky) {
      this.fillSky();
      return;
    }
    const autos = this.pieces.filter((pc) => pc.controller === null && !pc.thrownBy).length; // 던진 블록은 안 셈
    if (autos >= this.targetConcurrent()) return;
    this.spawnAuto(); // 자리가 없으면 다음 간격에 다시
    this.nextSpawnAt = this.time + this.autoSpawnDelayMs();
  }



  // 용암에 녹은 하늘 블록: 격자에 안 남고 사라짐
  meltPiece(piece) {
    this.emit({ type: 'melt', cells: this.pieceWorldCells(piece) });
    this.log(`  [하늘] ${piece.shape} 용암에 녹음 (z=${piece.pz})`);
    this.removePiece(piece);
  }

  movePiece(piece, dx, dy) {
    const { w, d } = footprint(piece.cells);
    const nx = Math.max(0, Math.min(this.W - w, piece.px + dx));
    const ny = Math.max(0, Math.min(this.D - d, piece.py + dy));
    if (nx === piece.px && ny === piece.py) return;
    piece.px = nx;
    piece.py = ny;
    this.updateLanding(piece);
    this.refreshPieceCells();
  }

  rotatePiece(piece, dir) {
    const rot = (piece.rot + dir + 4) % 4;
    const cells = rotatedCells(piece.shape, rot);
    const { w, d } = footprint(cells);
    piece.rot = rot;
    piece.cells = cells;
    piece.px = Math.max(0, Math.min(this.W - w, piece.px));
    piece.py = Math.max(0, Math.min(this.D - d, piece.py));
    this.updateLanding(piece);
    this.refreshPieceCells();
  }

  // reason: 'hard' = 조종자가 Enter, 'timeout' = 8초 초과, 'left' = 조종자 사망·이탈
  dropPiece(piece = this.piece, reason = 'hard') {
    if (!piece || !piece.fits) return; // 그 자리엔 못 넣는다 (기둥이 꽉 참)
    const who = this.players.get(piece.controller);
    piece.phase = 'falling';
    piece.stepMs = this.mode === 'master' && who && who.master ? this.masterDropStep : C.HARD_DROP_STEP_MS; // 블록 마스터 편은 인원별 빠르기
    piece.nextStepAt = this.time + piece.stepMs;
    const name = who ? who.name : '?';
    if (this.mode === 'master' && who && who.master) who.nextPieceAt = this.time + C.MASTER_NEXT_PIECE_MS;
    const what = reason === 'hard' ? `하드드롭 by ${name}` : reason === 'timeout' ? `자동 낙하 (8초 초과, 조종자 ${name})` : `자동 낙하 (조종자 ${name} 사망·이탈)`;
    this.log(`  [블록] ${piece.shape} ${what} → (${piece.px},${piece.py}) 착지 z=${piece.landZ}`);
  }

  // 조종권을 먹은 순간 바로 조종을 시작한다 (CONTROL_TAKEOVER).
  // 자동 블록이 떨어지는 중이면 가장 높이 있는 것을 하늘로 올려 넘겨받고, 없으면 새 블록을 하늘에.
  // 다른 사람이 조종한 블록이 아직 있으면 그 블록이 착지한 뒤 다음 블록을 조종한다.
  startControlNow(p) {
    if (!C.CONTROL_TAKEOVER || !p.hasControl) return;
    if (this.pieces.some((pc) => pc.controller !== null)) return;
    let piece = null;
    for (const pc of this.pieces) if (pc.phase === 'falling' && !pc.thrownBy && !pc.sky && !pc.ghostBy && (!piece || pc.pz > piece.pz)) piece = pc; // 던진 블록·하늘 계단 블록·유령 블록은 못 뺏음
    if (!piece) {
      this.spawnControlled(p);
      return;
    }
    Object.assign(piece, {
      pz: C.CONTROL_HOVER_Z,
      phase: 'control',
      controller: p.id,
      stepMs: C.HARD_DROP_STEP_MS,
      nextStepAt: 0,
      controlEndsAt: this.time + C.CONTROL_TIME_MS,
    });
    p.hasControl = false;
    this.updateLanding(piece);
    this.refreshPieceCells();
    this.emit({ type: 'controlStart', who: p.id });
    this.log(`  [블록] ${piece.shape} 조종 시작: ${p.name} (떨어지던 블록 넘겨받음)`);
  }

  removePiece(piece) {
    const i = this.pieces.indexOf(piece);
    if (i >= 0) this.pieces.splice(i, 1);
    this.refreshPieceCells();
  }

  discardPiece(piece, reason) {
    this.log(`  [블록] ${piece.shape} 폐기 (${reason})`);
    this.removePiece(piece);
    this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + (this.mode === 'master' ? C.MASTER_NEXT_PIECE_MS : this.autoSpawnDelayMs()));
    if (piece.controller !== null) this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
  }

  // 한 칸 아래에 다른 블록이 있으면 true (그 블록이 비킬 때까지 기다린다)
  blockedByPiece(piece) {
    for (const [x, y, z] of this.pieceWorldCells(piece)) {
      const other = this.pieceCells.get(cellKey(x, y, z - 1));
      if (other !== undefined && other !== piece.id) return true;
    }
    return false;
  }

  updatePieces() {
    this.updateSpawning();
    for (const piece of [...this.pieces]) {
      if (piece.phase === 'control') {
        const ctl = this.players.get(piece.controller);
        if (!ctl || !ctl.alive) {
          // 조종자가 죽거나 나가면 그 자리에서 자동 낙하 (안 맞으면 폐기)
          if (piece.fits) this.dropPiece(piece, 'left');
          else this.discardPiece(piece, '조종자 이탈, 자리 없음');
        } else if (this.time >= piece.controlEndsAt) {
          if (piece.fits) this.dropPiece(piece, 'timeout');
          else this.discardPiece(piece, '시간 초과, 자리 없음');
        }
        continue;
      }
      // falling
      if (this.meltsInLava(piece)) {
        this.meltPiece(piece);
        continue;
      }
      while (this.pieces.includes(piece) && this.time >= piece.nextStepAt) {
        if (piece.pz <= piece.landZ) {
          this.landPiece(piece);
          break;
        }
        piece.nextStepAt += piece.stepMs;
        if (this.blockedByPiece(piece)) continue;
        piece.pz--;
        this.refreshPieceCells();
        this.crushCheck(piece);
        if (this.meltsInLava(piece)) {
          this.meltPiece(piece);
          break;
        }
        if (piece.pz <= piece.landZ) {
          this.landPiece(piece);
          break;
        }
      }
    }
  }

  // 하늘 블록은 용암이 켜진 뒤 아래면이 용암 표면에 닿으면 녹는다 (그 전에 기둥에 닿으면 보통 착지)
  meltsInLava(piece) {
    return !!piece.sky && this.lava.active && piece.pz <= this.lava.z && piece.pz > piece.landZ;
  }

  // 그림자(경고)를 보일지: 보통 블록은 착지 SHADOW_LEAD_MS 전부터, 하늘 블록은 착지 높이 + SKY_SHADOW_CELLS 안으로 내려오면 (봇도 같은 기준)
  shadowVisible(piece, eta) {
    if (piece.phase !== 'falling') return false;
    return piece.sky ? piece.pz - piece.landZ <= C.SKY_SHADOW_CELLS : eta <= C.SHADOW_LEAD_MS;
  }

  // 블록 셀이 플레이어 AABB 와 겹치면 압사
  crushCheck(piece = this.piece) {
    const cells = this.pieceWorldCells(piece);
    for (const p of this.players.values()) {
      if (!this.onField(p) || this.isGhost(p) || this.time < p.shieldUntil) continue; // 유령·부활 무적은 블록이 통과 (압사 면역)
      for (const [cx, cy, cz] of cells) {
        if (
          cx < p.x + C.PLAYER_HALF - EPS &&
          cx + 1 > p.x - C.PLAYER_HALF + EPS &&
          cy < p.y + C.PLAYER_HALF - EPS &&
          cy + 1 > p.y - C.PLAYER_HALF + EPS &&
          cz < p.z + C.PLAYER_HEIGHT - EPS &&
          cz + 1 > p.z + EPS
        ) {
          if (this.headBonk(p, piece)) break; // 머리 박음: 아래로 빠져나갈 공간이 있으면 안 깔림
          if (piece.thrownBy) {
            const by = this.players.get(piece.thrownBy);
            this.log(`  [투척] ${by ? by.name : '?'} 의 ${piece.shape} 에 ${p.name} 깔림`);
          }
          // 조종한 블록·던진 블록이면 그 사람의 킬, 자동 블록이면 마지막으로 날린 사람
          const src = piece.controller !== null ? { by: piece.controller, kind: 'control' } : piece.thrownBy ? { by: piece.thrownBy, kind: 'thrown' } : piece.ghostBy ? { by: piece.ghostBy, kind: 'ghost' } : null;
          this.kill(p, 'crush', src);
          break;
        }
      }
    }
  }

  // 머리 박음 (2026-10-26 재혁: 압사 완화). 블록 아래면에서 몸 아래 기둥 꼭대기(필드 밖이면 끝없이)까지 빈 공간이
  // CRUSH_ESCAPE_CELLS 칸 이상이면 압사 대신 블록 아래로 밀어 내리고 짧은 경직. 땅에 선 채 깔리면 공간이 키보다 작아 그대로 압사
  headBonk(p, piece) {
    const bottom = piece.pz; // 블록은 한 층 (모든 칸이 pz)
    let floor = -Infinity;
    const h = C.PLAYER_HALF - EPS;
    for (let cx = Math.floor(p.x - h); cx <= Math.floor(p.x + h); cx++) {
      for (let cy = Math.floor(p.y - h); cy <= Math.floor(p.y + h); cy++) {
        if (!this.inXY(cx, cy)) continue; // 필드 밖은 바닥이 없음
        let top = 0;
        for (let z = Math.min(bottom, this.H) - 1; z >= 0; z--) {
          if (this.grid[this.idx(cx, cy, z)] || (this.pieceCells.has(cellKey(cx, cy, z)) && this.pieceCells.get(cellKey(cx, cy, z)) !== piece.id)) {
            top = z + 1;
            break;
          }
        }
        floor = Math.max(floor, top);
      }
    }
    if (bottom - floor < C.CRUSH_ESCAPE_CELLS) return false;
    p.z = bottom - C.PLAYER_HEIGHT;
    p.vz = Math.min(p.vz, 0);
    p.grounded = false;
    p.stunUntil = Math.max(p.stunUntil, this.time + C.HEAD_BONK_STUN_MS);
    this.emit({ type: 'headBonk', who: p.id, x: p.x, y: p.y, z: p.z });
    this.log(`  [머리 박음] ${p.name} ← ${piece.shape} (빈 공간 ${Number.isFinite(floor) ? bottom - floor : '∞'}칸)`);
    return true;
  }

  landPiece(piece = this.piece) {
    this.landed[piece.ghostBy ? 'ghost' : piece.sky ? 'sky' : piece.controller !== null ? 'control' : piece.thrownBy ? 'item' : 'auto']++;
    const cell = pieceCellValue(piece); // 색 구분용
    for (const [x, y, z] of this.pieceWorldCells(piece)) {
      if (z >= 0 && z < this.H) {
        this.grid[this.idx(x, y, z)] = cell;
        this.gridPiece[this.idx(x, y, z)] = piece.id;
      }
    }
    const cells = this.pieceWorldCells(piece);
    this.emit({ type: 'land', cells: cells.map(([x, y, z]) => [x, y, z]), controlled: piece.controller !== null });
    const wasControlled = piece.controller !== null;
    if (piece.thrownBy) this.brickShock(piece);
    this.removePiece(piece);
    this.gridVersion++;
    this.gridDirty = true;
    this.clearLayers();
    if (this.mode === 'kills') this.sinkIfTall();
    for (const pc of this.pieces) this.updateLanding(pc);
    if (!piece.thrownBy && !piece.sky && this.mode !== 'master') this.nextSpawnAt = Math.max(this.nextSpawnAt, this.time + this.autoSpawnDelayMs()); // 던진 블록은 자동 블록 간격에 안 끼어듦 (마스터 블록은 dropPiece 가 정함)
    if (wasControlled) {
      this.controlItemNextAt = this.time + C.CONTROL_ITEM_RESPAWN_MS;
      // 남의 조종 블록이 끝나길 기다리던 조종권 보유자는 바로 조종 시작
      const holder = [...this.players.values()].find((p) => p.alive && p.hasControl);
      if (holder) this.startControlNow(holder);
    }
    for (const it of this.items) it.z = this.columnTop(it.x, it.y);
  }

  // 한 층이 꽉 차면 제거하고 위의 블록·플레이어·아이템을 내린다 (용암도 같이 내려간다)
  clearLayers() {
    const layerSize = this.W * this.D;
    const full = [];
    for (let z = 0; z < this.H; z++) {
      let ok = true;
      for (let i = 0; i < layerSize && ok; i++) if (!this.grid[z * layerSize + i]) ok = false;
      if (ok) full.push(z);
    }
    if (!full.length) return;
    this.dropLayers(full);
    this.emit({ type: 'clear', n: full.length });
    this.log(`  [층 클리어] z=${full.join(',')} 제거 → 위 블록·플레이어 ${full.length}칸 내려앉음`);
  }

  // 킬 점수전: 가장 높은 기둥이 KILLS_SINK_HEIGHT 에 닿으면 맨 아래 층을 지워 전체를 한 칸씩 내림 (필드가 안 막히게)
  sinkIfTall() {
    let n = 0;
    while (this.maxColumnTop() >= C.KILLS_SINK_HEIGHT) {
      this.dropLayers([0]);
      n++;
    }
    if (n) this.log(`  [가라앉음] 가장 높은 기둥 ${C.KILLS_SINK_HEIGHT}칸 → 맨 아래 ${n}층 지움, 전체가 ${n}칸 내려앉음`);
  }

  maxColumnTop() {
    let top = 0;
    for (let x = 0; x < this.W; x++) for (let y = 0; y < this.D; y++) top = Math.max(top, this.columnTop(x, y));
    return top;
  }

  // 층들을 지우고 위의 블록·플레이어·용암을 그만큼 내린다
  dropLayers(full) {
    const layerSize = this.W * this.D;
    const next = new Uint8Array(this.grid.length);
    const nextPiece = new Int32Array(this.grid.length); // 블록 id 도 같이 내림
    let dst = 0;
    for (let z = 0; z < this.H; z++) {
      if (full.includes(z)) continue;
      next.set(this.grid.subarray(z * layerSize, (z + 1) * layerSize), dst * layerSize);
      nextPiece.set(this.gridPiece.subarray(z * layerSize, (z + 1) * layerSize), dst * layerSize);
      dst++;
    }
    this.grid = next;
    this.gridPiece = nextPiece;
    this.gridVersion++;
    this.gridDirty = true;
    for (const p of this.players.values()) {
      if (p.master) continue; // 마스터는 필드 위 하늘에 둔 채로
      let shift = 0;
      for (const z of full) if (p.z >= z + 1 - 1e-3) shift++;
      p.z -= shift;
    }
    if (this.lava.active) this.lava.z -= full.filter((z) => z < this.lava.z).length;
    // 건축가 블록·구멍 기록도 같이 내림 (지워진 층에 있던 것은 버림)
    const moved = new Map();
    for (const b of this.bblocks.values()) {
      if (full.includes(b.z)) continue;
      b.z -= full.filter((z) => z < b.z).length;
      moved.set(cellKey(b.x, b.y, b.z), b);
    }
    this.bblocks = moved;
    for (const q of this.quakes) q.cells = q.cells.filter(([, , z]) => !full.includes(z)).map(([x, y, z]) => [x, y, z - full.filter((f) => f < z).length]);
    this.holes = this.holes.filter((h) => !full.includes(h.z));
    for (const h of this.holes) h.z -= full.filter((z) => z < h.z).length;
  }

  // ---------- 용암 ----------
  avgHeight() {
    let sum = 0;
    for (let x = 0; x < this.W; x++) for (let y = 0; y < this.D; y++) sum += this.columnTop(x, y);
    return sum / (this.W * this.D);
  }

  updateLava(dtMs) {
    if (this.mode === 'practice' && this.practice.noBlocks) return; // 연습: 용암 없음
    if (this.mode === 'kills') return; // 킬 점수전은 용암 대신 아래층을 지움 (sinkIfTall)
    const lava = this.lava;
    if (!lava.active) {
      const piled = this.avgHeight() - this.baseAvgHeight >= C.LAVA_TRIGGER_AVG_HEIGHT; // 시작 지형 빼고 쌓인 만큼
      const late = this.sky && this.elapsed() >= this.skyLavaMs; // 하늘 계단: 시간이 지나도 시작 (인원별 SKY_LAVA_TRIGGER_BY_COUNT)
      if (!piled && !late) return;
      lava.active = true;
      lava.z = C.LAVA_START_Z;
      lava.startedAt = this.time;
      this.emit({ type: 'lava' });
      this.log(`  [용암] ${piled ? '' : `${fmtTime(this.skyLavaMs)} 지남 (하늘 계단), `}쌓인 평균 높이 ${(this.avgHeight() - this.baseAvgHeight).toFixed(2)} → 용암 상승 시작 @ ${fmtTime(this.elapsed())}`);
      return;
    }
    lava.z = Math.min(this.H + 1, lava.z + dtMs / C.LAVA_RISE_MS_PER_CELL);
    // 필드 밖에서 용암 높이 아래로 가면 밀려 떨어진 것이라 낙사로 센다 (용암판은 필드보다 넓게 그려짐)
    for (const p of this.players.values()) {
      if (!this.onField(p) || p.z >= lava.z - 0.05) continue;
      const inField = p.x >= 0 && p.x < this.W && p.y >= 0 && p.y < this.D;
      this.kill(p, inField ? 'lava' : 'fall');
    }
    this.items = this.items.filter((it) => it.z >= lava.z);
  }

  // ---------- 유령 투하 (2026-10-26 재혁) ----------
  // 이 사람이 유령 투하를 할 수 있는 상태면 남은 쿨 ms (0 = 바로), 아니면 null
  ghostCd(p) {
    if (!C.GHOST_DROP_ENABLED || this.phase !== 'playing' || this.mode !== 'survival') return null;
    if (p.alive || p.spectator || p.master || p.dummy || (p.isBot && !C.GHOST_DROP_BOTS) || !this.players.has(p.id)) return null;
    return Math.max(0, (p.ghostReadyAt || 0) - this.time);
  }

  // 죽은 사람이 (x, y) 칸에 1칸 블록을 떨어뜨림. 되면 블록, 안 되면 ghostDropFail 이벤트 + null
  ghostDrop(id, rx, ry) {
    const p = this.players.get(id);
    if (!p) return null;
    const fail = (reason) => {
      this.emit({ type: 'ghostDropFail', who: id, reason });
      return null;
    };
    if (!C.GHOST_DROP_ENABLED || this.phase !== 'playing' || this.mode !== 'survival') return fail('mode');
    const cd = this.ghostCd(p);
    if (cd === null) return fail('notDead');
    if (cd > 0) return fail('cooldown');
    const x = Math.floor(Number(rx));
    const y = Math.floor(Number(ry));
    if (!Number.isFinite(x) || !Number.isFinite(y) || !this.inXY(x, y)) return fail('outside');
    const top = this.columnTop(x, y);
    if (top >= this.H) return fail('full');
    if (this.pieces.some((pc) => pc.cells.some(([dx, dy]) => pc.px + dx === x && pc.py + dy === y))) return fail('busy');
    const pz = Math.min(top + (this.sky ? C.GHOST_DROP_UP_SKY : C.GHOST_DROP_UP), this.H - 1); // 켬 판은 느려서 낮게
    const stepMs = this.sky ? C.SKY_FALL_STEP_MS : this.autoFallStepMs(); // 그 판 보통 블록 속도
    const piece = { id: 0, shape: 'ghost', rot: 0, cells: [[0, 0]], px: x, py: y, pz, landZ: top, fits: true };
    this.addPiece(piece, { phase: 'falling', controller: null, ghostBy: p.id, ghostSlot: p.slot, ghostColor: p.color, stepMs, nextStepAt: this.time + stepMs, controlEndsAt: 0 });
    this.updateLanding(piece);
    p.ghostReadyAt = this.time + C.GHOST_DROP_CD_MS;
    this.emit({ type: 'ghostDrop', who: p.id, x, y, z: pz, slot: p.slot, color: p.color });
    this.log(`  [유령] ${p.name} → (${x},${y}) 투하`);
    return piece;
  }
}
