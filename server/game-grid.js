// Game 메서드 묶음: 격자: 칸 읽기·판 크기·기둥 높이. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { cellKey, byCount } from './game-util.js';

export class GridPart {
  // ---------- 격자 ----------
  inXY(cx, cy) {
    return cx >= 0 && cx < this.W && cy >= 0 && cy < this.D;
  }

  // 판 크기: 필드에 나가는 사람·봇 수 → FIELD_SIZES (블록 마스터는 마스터 빼고)
  fieldSizeFor(n) {
    return byCount(C.FIELD_SIZES, n);
  }

  setFieldSize(size) {
    this.H = this.sky ? C.SKY_GRID_H : C.GRID_H;
    this.W = size;
    this.D = size;
    this.spawnPoints = C.spawnPointsFor(size, size);
    this.grid = new Uint8Array(this.W * this.D * this.H);
    this.gridPiece = new Int32Array(this.grid.length); // 칸마다 착지한 블록 id (갈고리 R 덩어리). 블록이 아닌 칸·지워진 칸은 의미 없음 (grid 색과 같이 봄)
  }

  // 넓이 배율 (10×10 = 1): 떨어지는 블록 동시 개수·필드 아이템 수에 곱함
  areaScale() {
    return (this.W * this.D) / (C.GRID_W * C.GRID_D);
  }

  itemMax() {
    return Math.round(C.ITEM_MAX_ON_FIELD * this.areaScale());
  }

  idx(cx, cy, cz) {
    return (cz * this.D + cy) * this.W + cx;
  }

  gridAt(cx, cy, cz) {
    if (!this.inXY(cx, cy) || cz < 0 || cz >= this.H) return 0;
    return this.grid[this.idx(cx, cy, cz)];
  }

  // 플레이어 충돌용: 바닥, 쌓인 블록, 떨어지는 블록
  solidAt(cx, cy, cz) {
    if (cz < 0) return this.inXY(cx, cy); // 필드 안은 바닥, 밖은 허공
    if (this.inXY(cx, cy) && cz < this.H && this.grid[this.idx(cx, cy, cz)]) return true;
    return this.pieceCells.has(cellKey(cx, cy, cz));
  }

  // 그 기둥에서 가장 높은 블록 바로 위 z (블록 없으면 0)
  columnTop(cx, cy) {
    for (let z = this.H - 1; z >= 0; z--) {
      if (this.grid[this.idx(cx, cy, z)]) return z + 1;
    }
    return 0;
  }

  // 격자가 바뀐 뒤: 떨어지는 블록 착지점, 아이템·폭탄 높이 다시 계산
  gridChanged() {
    this.gridVersion++;
    this.gridDirty = true;
    for (const pc of this.pieces) this.updateLanding(pc);
    for (const it of this.items) it.z = this.columnTop(it.x, it.y);
    for (const b of this.bombs) b.z = this.columnTop(b.x, b.y);
  }
}
