// 튜토리얼 자동 조종 (확인용): 스냅샷(state)만 보고 단계마다 입력·행동을 냄 → 실제로 끝까지 통과되는지.
// test/tutorial.test.js 는 서버에 바로 (handleInput·handleAction), Playwright 는 __tf.inputOverride·__tf.act 로 같은 것을 씀. 게임 코드는 안 씀
import { CONFIG as C } from './config.js';
import { tutorialLayout } from './tutorial.js';

export class TutorialPilot {
  constructor() {
    this.stepId = null;
    this.k = 0;
    this.mem = {};
    this.prevZ = null;
  }

  // state: 스냅샷 (players·tutorial·items·pieces·field), myId: 나. 반환 { input, actions: ['jump'|'dash'|'push'|'skill'|'ult'|'fire'] }
  next(state, myId) {
    const me = state.players.find((p) => p.id === myId);
    const tut = state.tutorial;
    const out = { input: { type: 'input', fwd: 0, strafe: 0, jump: false, yaw: me ? me.yaw : 0, pitch: 0 }, actions: [] };
    if (!me || !tut || tut.done || tut.ok || !me.alive) return out;
    if (tut.id !== this.stepId) {
      this.stepId = tut.id;
      this.k = 0;
      this.mem = {};
    }
    const k = ++this.k;
    const vz = this.prevZ === null ? 0 : me.z - this.prevZ;
    this.prevZ = me.z;
    const onGround = Math.abs(vz) < 1e-3;
    const dist = (x, y) => Math.hypot(x - me.x, y - me.y);
    const face = (x, y) => (out.input.yaw = Math.atan2(y - me.y, x - me.x));
    const go = (x, y, stop = 0.25) => {
      face(x, y);
      out.input.fwd = dist(x, y) > stop ? 1 : 0;
    };
    const dummy = state.players.find((p) => p.dummy && p.alive);
    const W = state.field ? state.field.w : 10;
    const D = state.field ? state.field.d : 10;
    const m = this.mem;
    switch (tut.id) {
      case 'move':
        go(tut.target.x, tut.target.y, 0.15);
        break;
      case 'jump': {
        go(tut.target.x, tut.target.y, 0.15);
        const wallX = Math.floor(tut.target.x) - 2; // 벽 앞면 (목표는 벽 위 가운데쯤)
        if (onGround && me.z < 0.5 && me.x > wallX - 1.4) {
          out.input.jump = true;
          m.jumpAt = k;
        }
        if (m.jumpAt && k - m.jumpAt >= 7 && !m.air && me.z > 0.4) {
          out.actions.push('jump'); // 꼭대기 근처에서 2단 점프
          m.air = true;
        }
        if (onGround) m.air = false;
        break;
      }
      case 'dash':
        out.input.yaw = 0;
        if (k % 30 === 3) out.actions.push('dash');
        break;
      case 'push':
      case 'ringout':
        if (!dummy) break;
        go(dummy.x, dummy.y, 1.0);
        if (dist(dummy.x, dummy.y) < 1.5 && k % 6 === 0) out.actions.push('push');
        break;
      case 'crit': {
        if (!dummy) break;
        const d = dist(dummy.x, dummy.y);
        face(dummy.x, dummy.y);
        if (onGround) {
          out.input.fwd = d > 1.9 ? 1 : d < 1.4 ? -1 : 0;
          if (d <= 1.9 && d >= 1.2 && k % 4 === 0) out.input.jump = true;
        } else {
          out.input.fwd = d > 0.9 ? 1 : 0;
          if (vz < 0 && me.z > dummy.z + 0.35 && d < 1.8) out.actions.push('push');
        }
        break;
      }
      case 'skill':
      case 'ult': {
        if (!dummy) break;
        // 갈고리 R 은 옆 기둥 블록을 잡음, 나머지는 허수아비 쪽
        if (tut.id === 'ult' && me.char === 'hook') {
          const blocks = (m.pillar ||= findPillar(state));
          if (blocks) face(blocks.x, blocks.y);
        } else face(dummy.x, dummy.y);
        if (dist(dummy.x, dummy.y) > 3) out.input.fwd = 1;
        if (k % 15 === 5) out.actions.push(tut.id);
        break;
      }
      case 'item': {
        const it = (state.items || [])[0];
        if (!me.held && it) go(it.x + 0.5, it.y + 0.5, 0.1);
        else if (dummy) {
          face(dummy.x, dummy.y);
          if (k % 10 === 0) out.actions.push('fire');
        }
        break;
      }
      case 'dodge': {
        const shade = new Set();
        for (const pc of state.pieces || []) if (pc.phase === 'falling') for (const [x, y] of pc.shadow || []) shade.add(`${x},${y}`);
        const covered = (x, y) => {
          for (const ox of [-0.4, 0.4]) for (const oy of [-0.4, 0.4]) if (shade.has(`${Math.floor(x + ox)},${Math.floor(y + oy)}`)) return true;
          return false;
        };
        if (m.flee && !covered(m.flee.x, m.flee.y) && shade.size) go(m.flee.x, m.flee.y, 0.1);
        else if (covered(me.x, me.y)) {
          let best = null;
          for (let a = 0; a < 16; a++) {
            const x = me.x + Math.cos((a / 16) * Math.PI * 2) * 2.4;
            const y = me.y + Math.sin((a / 16) * Math.PI * 2) * 2.4;
            if (x < 1 || y < 1 || x > W - 1 || y > D - 1 || covered(x, y)) continue;
            const score = Math.hypot(x - W / 2, y - D / 2);
            if (!best || score < best.score) best = { x, y, score };
          }
          m.flee = best;
          if (best) go(best.x, best.y, 0.1);
        } else m.flee = null;
        break;
      }
      case 'climb':
        out.input.yaw = 0;
        out.input.fwd = me.z >= 4.9 && me.x >= Math.floor(W / 2) + 1.3 ? 0 : 1;
        out.input.jump = out.input.fwd === 1;
        break;
    }
    return out;
  }
}

// 단계 표에서 기둥 칸 (갈고리 R 이 잡을 블록)
function findPillar(state) {
  const step = C.TUTORIAL_STEPS.find((st) => st.id === 'ult');
  const f = state.field || { w: 10, d: 10 };
  const c = tutorialLayout(step, f.w, f.d).cells[0];
  return c ? { x: c[0] + 0.5, y: c[1] + 0.5 } : null;
}
