// 직접 해 보는 튜토리얼 (2026-10-29 재혁): 단계 표(config TUTORIAL_STEPS)를 필드 칸으로 펴기·문구 채우기·완료 판정. DOM·three.js 없는 순수 계산.
// 서버(server/tutorial.js)가 단계마다 지형·허수아비·아이템을 놓고 judge 로 판정, 화면(main.js)은 stepText 로 띠 문구를 만든다. 테스트 test/tutorial.test.js
import { CONFIG as C } from './config.js';

export const TUTORIAL_N = C.TUTORIAL_STEPS.length;

// 이 캐릭터가 하는 단계들 (skipChars 에 있으면 뺌)
export function tutorialSteps(char) {
  return C.TUTORIAL_STEPS.filter((st) => !(st.skipChars || []).includes(char));
}

export function tutorialStep(id) {
  return C.TUTORIAL_STEPS.find((st) => st.id === id) || null;
}

// 필드 가운데 기준 → 필드 좌표 (블록·아이템은 가운데 칸 기준 칸 번호, 사람·허수아비·목표는 그 칸 가운데 기준). 블록 칸은 필드 밖으로 안 나가게 자름
export function tutorialLayout(step, W, D) {
  const cx = Math.floor(W / 2); // 가운데 칸 (블록 칸 기준)
  const cy = Math.floor(D / 2);
  const px = cx + 0.5; // 사람·허수아비 자리는 칸 가운데 기준
  const py = cy + 0.5;
  const inField = (x, y) => x >= 0 && x < W && y >= 0 && y < D;
  const [sx, sy, yaw] = step.start || [0, 0, 0];
  const out = {
    start: { x: px + sx, y: py + sy, yaw: yaw || 0 },
    target: step.target ? { x: px + step.target[0], y: py + step.target[1], z: step.minZ || 0 } : null,
    cells: [],
    dummies: (step.dummies || []).map(([x, y, damage]) => ({ x: px + x, y: py + y, damage: damage || 0 })),
    items: (step.items || []).map(([x, y, type]) => ({ x: cx + x, y: cy + y, type })), // 아이템은 칸
  };
  const put = (x, y, h) => {
    if (!inField(x, y)) return;
    for (let z = 0; z < h; z++) out.cells.push([x, y, z]);
  };
  for (const [x0, y0, x1, y1, h] of step.blocks || []) {
    for (let x = cx + x0; x <= cx + x1; x++) for (let y = cy + y0; y <= cy + y1; y++) put(x, y, h);
  }
  for (const [x, y0, y1, h] of step.stairs || []) for (let y = cy + y0; y <= cy + y1; y++) put(cx + x, y, h);
  return out;
}

// 띠 문구: {키 id} → keyName(id) (지금 키 설정 이름), {skillDesc}·{ultDesc} → 고른 캐릭터 설명
export function stepText(step, { char = C.CHAR_DEFAULT, keyName = (id) => id } = {}) {
  return step.text.replace(/\{(\w+)\}/g, (m, k) => {
    if (k === 'skillDesc') return C.SKILL_DESC[char] || '';
    if (k === 'ultDesc') return C.ULT_DESC[char] || '';
    return keyName(k);
  });
}

// 진행 칸 '2 / 11'
export function progressLabel(i, n = TUTORIAL_N) {
  return `${Math.min(i + 1, n)} / ${n}`;
}

// 완료 판정. ctx: { me: { x, y, z, grounded }, target, dummyMax (허수아비 최고 피해 %), dashed, ringout, crit, skill, ult, itemUsed, dodged }
export function judge(step, ctx) {
  const me = ctx.me;
  switch (step.kind) {
    case 'reach': {
      const t = ctx.target;
      if (!me || !t) return false;
      const near = Math.hypot(me.x - t.x, me.y - t.y) <= C.TUTORIAL_REACH_R;
      return near && (!step.minZ || (me.grounded && me.z >= step.minZ - 0.01));
    }
    case 'dash':
      return !!ctx.dashed;
    case 'damage':
      return (ctx.dummyMax || 0) >= step.pct;
    case 'ringout':
      return !!ctx.ringout;
    case 'crit':
      return !!ctx.crit;
    case 'skill':
      return !!ctx.skill;
    case 'ult':
      return !!ctx.ult;
    case 'item':
      return !!ctx.itemUsed;
    case 'dodge':
      return (ctx.dodged || 0) >= step.n;
    case 'climb':
      return !!me && me.grounded && me.z >= step.z - 0.01;
    default:
      return false;
  }
}

// 다음 단계 번호 (넘기기·해냄 둘 다). 끝이면 null
export function nextStep(i, n = TUTORIAL_N) {
  return i + 1 < n ? i + 1 : null;
}
