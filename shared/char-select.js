// 대기실 캐릭터 고르기 계산: DOM·three.js 없는 순수 계산 — client/char-stage.js·main.js 가 쓰고 test/char-select.test.js 가 검증한다.
import { CONFIG as C } from './config.js';

// 큰 3D 캐릭터의 몸 방향 (z 축 각, 0 = 카메라 정면). 고른 뒤(또는 처음) sec 초 지남
// 도발하는 EMOTE_MS 동안은 정면, 그 뒤부터 천천히 돎
export function stageYaw(sec) {
  const hold = C.EMOTE_MS / 1000;
  return sec <= hold ? 0 : (sec - hold) * C.CHAR_STAGE_SPIN;
}

// 도발 포즈 진행: 고른 뒤 ageMs → { on, t(초) } (figureAnim 의 emote = EMOTE_CHAR, emoteT)
export function tauntAt(ageMs) {
  if (!(ageMs >= 0) || ageMs > C.EMOTE_MS) return { on: false, t: 0 };
  return { on: true, t: ageMs / 1000 };
}

// '랜덤': 지금 캐릭터 말고 하나를 뽑고, 그 전에 불이 옮겨 다닐 순서 (끝으로 갈수록 느려짐)
// rnd: 0~1 난수 함수. 반환 { pick, steps: [{ char, at(ms) }] } — 마지막 step 이 pick, at 은 CHAR_RANDOM_MS
export function randomReel(chars, current, rnd = Math.random) {
  const pool = chars.filter((c) => c !== current);
  const list = pool.length ? pool : chars;
  const pick = list[Math.min(list.length - 1, Math.floor(rnd() * list.length))];
  const steps = [];
  let at = 0;
  let i = Math.floor(rnd() * chars.length);
  let gap = C.CHAR_RANDOM_STEP_MS;
  while (at + gap < C.CHAR_RANDOM_MS) {
    at += gap;
    i = (i + 1) % chars.length;
    if (chars[i] === pick) i = (i + 1) % chars.length; // 끝 전에 미리 멈춰 보이지 않게
    steps.push({ char: chars[i], at });
    gap = Math.round(gap * 1.25);
  }
  steps.push({ char: pick, at: C.CHAR_RANDOM_MS });
  return { pick, steps };
}
