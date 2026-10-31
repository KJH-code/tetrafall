// 사냥꾼 표식 알아보기 (2026-10-31 재혁 피드백: ① 몇 개인지 ② 붙은 순간 ③ 누가 달렸는지). three.js 없는 순수 계산 — client/render.js·main.js 가 쓰고 test/hunt-marks.test.js 가 검사.
// 서버 스냅샷 players[].marks = [{ by, n, left }] (사냥꾼마다 따로), 이벤트 mark { by, target, n } · markGone { by, target }. 수치 config HUNT_MARK_UI
import { CONFIG as C } from './config.js';

// 보여 줄 표식: 내가 붙인 것이 있으면 그것 (mine), 없으면 가장 많은 것. 없으면 null
export function pickMark(marks, myId) {
  const list = marks || [];
  const mine = list.find((m) => m.by === myId);
  if (mine) return { ...mine, mine: true };
  const best = list.reduce((a, b) => (!a || b.n > a.n ? b : a), null);
  return best ? { ...best, mine: false } : null;
}

// 칸: 최대치만큼, 앞에서 n 개가 찬 칸. full = 최대치 (R 쓸 수 있음)
export function markPips(n, max = C.HUNTER_MARK_MAX) {
  const k = Math.max(0, Math.min(max, n | 0));
  return { pips: Array.from({ length: max }, (_, i) => i < k), full: k >= max, n: k };
}

// 마름모 칸 글자 (◆ 찬 칸 · ◇ 빈 칸)
export function pipText(n, max = C.HUNTER_MARK_MAX) {
  return markPips(n, max).pips.map((on) => (on ? '◆' : '◇')).join('');
}

// 붙는 순간 커졌다 줄어드는 배율 (age = 붙고 나서 ms). 그 뒤는 1
export function popScale(age, U = C.HUNT_MARK_UI) {
  if (!(age >= 0) || age >= U.popMs) return 1;
  const u = age / U.popMs;
  return 1 + U.popScale * Math.sin(Math.PI * u) * (1 - u);
}

// 맞은 사람 화면 가장자리 빨강 진하기 (0~1): 표식 수 (1 → edge[0], 최대 → edge[1]) + 새로 붙은 순간 (popAge ms) 더함. 사라지기 직전 깜빡이면 0
export function edgeLevel(n, max = C.HUNTER_MARK_MAX, popAge = Infinity, blink = false, U = C.HUNT_MARK_UI) {
  if (!(n > 0) || blink) return 0;
  const k = max > 1 ? (Math.min(n, max) - 1) / (max - 1) : 1;
  const base = U.edge[0] + (U.edge[1] - U.edge[0]) * k;
  const [add, ms] = U.edgePulse;
  const pulse = popAge >= 0 && popAge < ms ? add * (1 - popAge / ms) : 0;
  return Math.min(1, base + pulse);
}

// 사라지기 직전 깜빡 (left = 남은 ms)
export function markBlink(left, now) {
  return left < C.MARK_BLINK_MS && Math.floor(now / C.MARK_BLINK_PERIOD_MS) % 2 === 1;
}
