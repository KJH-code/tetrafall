// Game 메서드 묶음: 캐릭터: 대포수. server/game.js 가 Game.prototype 에 붙임 (메서드 안 this = Game).
// 2026-10-30 game.js 쪼개기: 원래 game.js 의 줄을 그대로 옮김 (동작·로그 문구 같음, tools/game-hash.js 로 확인)
import { CONFIG as C } from '../shared/config.js';
import { CELL } from '../shared/pieces.js';
import { cellKey } from './game-util.js';

export class CannonPart {
  // ---- 대포수 (2026-10-26, docs/characters.md 3.6) ----
  // 쌓인 블록 1칸 부숨 (격자 칸 또는 떨어지는 블록의 한 칸). 시작 지형·바닥은 안 부숨. 부쉈으면 true
  breakCell(x, y, z) {
    const key = cellKey(x, y, z);
    if (this.pieceCells.has(key)) {
      const pc = this.pieces.find((q) => q.id === this.pieceCells.get(key));
      pc.cells = pc.cells.filter(([dx, dy]) => !(pc.px + dx === x && pc.py + dy === y));
      if (!pc.cells.length) this.removePiece(pc);
      else {
        this.refreshPieceCells();
        this.updateLanding(pc);
      }
      return true;
    }
    if (!this.inXY(x, y) || z < 0 || z >= this.H) return false;
    const v = this.grid[this.idx(x, y, z)];
    if (!v || v === CELL.TERRAIN) return false;
    this.grid[this.idx(x, y, z)] = 0;
    this.gridChanged();
    return true;
  }

  // 시간 장전: 탄이 덜 찼으면 CANNON_RELOAD_MS 마다 한 발
  cannonReload(p) {
    if (p.cannonAmmo >= C.CANNON_AMMO_MAX) {
      p.reloadAt = 0;
      return;
    }
    if (!p.reloadAt) p.reloadAt = this.time + C.CANNON_RELOAD_MS;
    else if (this.time >= p.reloadAt) {
      p.cannonAmmo++;
      p.reloadAt = p.cannonAmmo < C.CANNON_AMMO_MAX ? this.time + C.CANNON_RELOAD_MS : 0;
      this.emit({ type: 'reload', who: p.id, ammo: p.cannonAmmo });
    }
  }

  // 포탄 (big = R 대형 포탄) 을 조준 방향으로 쏨 + 반동
  fireShell(p, big) {
    const cp = Math.cos(p.pitch || 0);
    const dir = { x: cp * Math.cos(p.yaw), y: cp * Math.sin(p.yaw), z: Math.sin(p.pitch || 0) };
    const speed = big ? C.CANNON_R_SPEED : C.CANNON_SHELL_SPEED;
    const range = big ? C.CANNON_R_RANGE : C.CANNON_SHELL_RANGE;
    const sh = {
      id: ++this.shellCounter,
      big,
      owner: p.id,
      x: p.x + dir.x * 0.5,
      y: p.y + dir.y * 0.5,
      z: p.z + C.EYE_HEIGHT - 0.2 + dir.z * 0.5,
      dir,
      speed,
      dieAt: this.time + (range / speed) * 1000,
      hit: new Set(),
    };
    this.shells.push(sh);
    const recoil = big ? C.CANNON_R_RECOIL : p.grounded ? C.CANNON_RECOIL : C.CANNON_RECOIL_AIR;
    const hl = Math.hypot(dir.x, dir.y) || 1;
    p.kbx -= (dir.x / hl) * recoil;
    p.kby -= (dir.y / hl) * recoil;
    this.emit({ type: 'shellFire', who: p.id, id: sh.id, big, x: sh.x, y: sh.y, z: sh.z, dir, speed, recoil });
    return sh;
  }

  // 평타 포탄: 탄 1발 쓰고 쏨
  cannonShot(p) {
    p.cannonAmmo--;
    if (!p.reloadAt) p.reloadAt = this.time + C.CANNON_RELOAD_MS;
    this.fireShell(p, false);
    this.log(`  [포탄] ${p.name} 발사 (남은 ${p.cannonAmmo}발)`);
  }

  // F 발밑 포격: 위로 크게 + 발밑 범위 넉백
  cannonJump(p) {
    p.vz = C.CANNON_JUMP_UP;
    p.grounded = false;
    const hits = [];
    for (const t of this.players.values()) {
      if (!this.foe(p, t)) continue;
      const dx = t.x - p.x;
      const dy = t.y - p.y;
      const d = Math.hypot(dx, dy);
      if (d > C.CANNON_FBLAST_RANGE || Math.abs(t.z - p.z) > 1.5) continue;
      const a = this.rng() * Math.PI * 2;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : Math.cos(a), d > 0.05 ? dy : Math.sin(a), C.CANNON_FBLAST_KB_SPEED, C.CANNON_FBLAST_KB_UP, C.CANNON_FBLAST_STUN_MS, C.CANNON_FBLAST_DAMAGE, { by: p.id, kind: 'groundshot' }, true);
      this.emit({ type: 'hit', kind: 'groundshot', by: p.id, target: t.id, ok: hit });
      if (hit) hits.push(t.name);
    }
    this.emit({ type: 'groundShot', who: p.id, x: p.x, y: p.y, z: p.z, r: C.CANNON_FBLAST_RANGE });
    this.log(`  [스킬] ${p.name} 발밑 포격${hits.length ? ` → ${hits.join(', ')}` : ''}`);
    return true;
  }

  // R 대형 포탄
  cannonBig(p) {
    this.fireShell(p, true);
    this.log(`  [필살] ${p.name} 대형 포탄 발사`);
    return true;
  }

  // 포탄 이동: 보통 포탄은 처음 닿는 것에서 멈춤 (사람 넉백 / 쌓인 블록 1칸 부숨). 대형 포탄은 관통하며 쌓인 블록 부수고 사람 밀침, 끝에서 폭발
  updateShells(dt) {
    for (const sh of [...this.shells]) {
      const sub = Math.max(1, Math.ceil((sh.speed * dt) / 0.15));
      const h = dt / sub;
      let end = null;
      for (let s = 0; s < sub && !end; s++) {
        sh.x += sh.dir.x * sh.speed * h;
        sh.y += sh.dir.y * sh.speed * h;
        sh.z += sh.dir.z * sh.speed * h;
        const r = sh.big ? C.CANNON_R_RADIUS : C.CANNON_SHELL_RADIUS;
        const owner = this.players.get(sh.owner);
        // 사람
        for (const t of this.players.values()) {
          if (!this.onField(t) || t.id === sh.owner || sh.hit.has(t.id) || this.sameTeam(owner, t)) continue; // 같은 팀은 통과
          if (!(sh.x > t.x - C.PLAYER_HALF - r && sh.x < t.x + C.PLAYER_HALF + r && sh.y > t.y - C.PLAYER_HALF - r && sh.y < t.y + C.PLAYER_HALF + r && sh.z > t.z - r && sh.z < t.z + C.PLAYER_HEIGHT + r)) continue;
          sh.hit.add(t.id);
          const big = sh.big;
          const hit = this.applyKnockback(t, sh.dir.x, sh.dir.y, big ? C.CANNON_R_KB_SPEED : C.CANNON_SHELL_KB_SPEED, big ? C.CANNON_R_KB_UP : C.CANNON_SHELL_KB_UP, big ? C.CANNON_R_STUN_MS : C.CANNON_SHELL_STUN_MS, big ? C.CANNON_R_DAMAGE : C.CANNON_SHELL_DAMAGE, { by: sh.owner, kind: big ? 'bigshell' : 'shell' }, true);
          this.emit({ type: 'hit', kind: big ? 'bigshell' : 'shell', by: sh.owner, target: t.id, ok: hit });
          this.log(`  [포탄] ${owner ? owner.name : '?'} → ${t.name} ${hit ? `넉백 (${t.name} ${t.damage}%)` : '무적이라 무시'}${big ? ' 대형' : ''}`);
          if (!big) {
            end = { what: 'player' };
            break;
          }
        }
        if (end) break;
        // 블록·바닥
        if (sh.big) {
          const broke = [];
          for (let x = Math.floor(sh.x - r); x <= Math.floor(sh.x + r); x++) for (let y = Math.floor(sh.y - r); y <= Math.floor(sh.y + r); y++) for (let z = Math.floor(sh.z - r); z <= Math.floor(sh.z + r); z++) if (this.breakCell(x, y, z)) broke.push([x, y, z]);
          if (broke.length) {
            this.emit({ type: 'blockBreak', who: sh.owner, cells: broke, big: true });
            this.log(`  [포탄] ${owner ? owner.name : '?'} 대형 포탄 블록 ${broke.length}칸 부숨`);
          }
          if (sh.z < 0 && this.inXY(Math.floor(sh.x), Math.floor(sh.y))) end = { what: 'floor' };
        } else {
          const cx = Math.floor(sh.x);
          const cy = Math.floor(sh.y);
          const cz = Math.floor(sh.z);
          if (this.solidAt(cx, cy, cz)) {
            const broke = this.breakCell(cx, cy, cz);
            if (broke) {
              this.emit({ type: 'blockBreak', who: sh.owner, cells: [[cx, cy, cz]], big: false });
              this.log(`  [포탄] ${owner ? owner.name : '?'} 블록 부숨 (${cx},${cy},${cz})`);
            }
            end = { what: broke ? 'block' : 'terrain' };
          }
        }
      }
      if (!end && this.time >= sh.dieAt) end = { what: 'expire' };
      if (!end) continue;
      this.shells = this.shells.filter((x) => x !== sh);
      this.emit({ type: 'shellEnd', id: sh.id, who: sh.owner, big: sh.big, what: end.what, x: sh.x, y: sh.y, z: sh.z });
      if (sh.big) this.bigShellBlast(sh);
    }
  }

  // 대형 포탄 끝 폭발: 둘레 사람을 바깥으로
  bigShellBlast(sh) {
    const owner = this.players.get(sh.owner);
    let n = 0;
    for (const t of this.players.values()) {
      if (!owner || !this.foe(owner, t)) continue;
      const dx = t.x - sh.x;
      const dy = t.y - sh.y;
      const d = Math.hypot(dx, dy);
      if (d > C.CANNON_R_BLAST_RANGE || Math.abs(t.z + 0.8 - sh.z) > C.CANNON_R_BLAST_RANGE) continue;
      const hit = this.applyKnockback(t, d > 0.05 ? dx : sh.dir.x, d > 0.05 ? dy : sh.dir.y, C.CANNON_R_BLAST_KB_SPEED, C.CANNON_R_BLAST_KB_UP, C.CANNON_R_BLAST_STUN_MS, C.CANNON_R_BLAST_DAMAGE, { by: sh.owner, kind: 'bigshell' }, true);
      if (hit) n++;
      this.emit({ type: 'hit', kind: 'bigshell', by: sh.owner, target: t.id, ok: hit });
    }
    this.emit({ type: 'bigShellBlast', who: sh.owner, x: sh.x, y: sh.y, z: sh.z, r: C.CANNON_R_BLAST_RANGE });
    this.log(`  [필살] ${owner ? owner.name : '?'} 대형 포탄 폭발 (${n}명)`);
  }
}
